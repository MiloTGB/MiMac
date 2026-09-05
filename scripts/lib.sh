#!/usr/bin/env bash
# lib.sh — shared helpers for MiMac scripts
# Source this file; do not execute directly.

[[ -n "${_LIB_SH_LOADED:-}" ]] && return 0
_LIB_SH_LOADED=1

# Resolve the real path of a file, following symlinks.
# Works on macOS (which may lack readlink -f on older versions).
resolve_path() {
  local target="$1"
  while [[ -L "$target" ]]; do
    local dir
    dir="$(cd "$(dirname "$target")" && pwd)"
    target="$(readlink "$target")"
    # Handle relative symlink targets
    [[ "$target" != /* ]] && target="$dir/$target"
  done
  echo "$(cd "$(dirname "$target")" && pwd)/$(basename "$target")"
}

# Constants
STATE_DIR="$HOME/.mimac"
LOGFILE="$STATE_DIR/install.log"
LOG_MAX_SIZE=10485760  # 10MB

# Color codes (only when output is a terminal)
if [[ -t 2 ]]; then
  _R=$'\033[0m'        # Reset
  _B=$'\033[1m'        # Bold
  _D=$'\033[2m'        # Dim
  _CYN=$'\033[36m'     # Cyan
  _GRN=$'\033[32m'     # Green
  _YLW=$'\033[33m'     # Yellow
  _RED=$'\033[31m'     # Red
  _BLU=$'\033[34m'     # Blue
else
  _R='' _B='' _D='' _CYN='' _GRN='' _YLW='' _RED='' _BLU=''
fi

# Logging helpers
log()     { printf '%s  ▸%s %s\n' "$_CYN" "$_R" "$*" >&2; }
ok()      { printf '%s  ✓%s %s\n' "$_GRN" "$_R" "$*" >&2; }
warn()    { printf '%s  ⚠%s %s\n' "$_YLW" "$_R" "$*" >&2; }
err()     { printf '%s  ✗%s %s\n' "$_RED" "$_R" "$*" >&2; }
info()    { printf '    %s\n' "$*" >&2; }
section() { printf '\n%s%s══ %s%s\n\n' "$_B" "$_BLU" "$*" "$_R" >&2; }
dry()     { if (( DRY_RUN )); then printf '%s  ◦%s %s\n' "$_BLU" "$_R" "$*" >&2; else log "$@"; fi; }
logskip() { printf '%s  ·%s %s (%s)\n' "$_YLW" "$_R" "$1" "$2" >&2; }

# Refresh sudo timestamp to prevent timeout during long-running installs.
# Uses -n (non-interactive) so it never prompts — only extends an active session.
sudo_refresh() { sudo -n -v 2>/dev/null || true; }

# macOS-only guard
check_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: This script is designed for macOS only." >&2
    echo "Detected OS: $(uname -s)" >&2
    exit 1
  fi
}

# Log rotation
setup_logging() {
  mkdir -p "$STATE_DIR"
  if [[ -f "$LOGFILE" ]] && [[ $(stat -f%z "$LOGFILE" 2>/dev/null || echo 0) -gt $LOG_MAX_SIZE ]]; then
    mv "$LOGFILE" "${LOGFILE}.$(date +%s).old" 2>/dev/null || true
    echo "[MiMac] Rotated log file (exceeded $((LOG_MAX_SIZE / 1024 / 1024))MB)" >&2
  fi
}

mimac_mktemp()   { mktemp    "${TMPDIR:-/tmp}/mimac.XXXXXX"; }
mimac_mktemp_d() { mktemp -d "${TMPDIR:-/tmp}/mimac.XXXXXX"; }

###############################################################################
# Secret scanning                                                             #
###############################################################################
#
# syncall commits with `git add -A`, which stages untracked files as well as
# modified ones, and then pushes to public repos. Without a gate, a key or token
# dropped into any repo under $HOME is committed and published without anyone
# looking at it. These two functions are that gate.

# A suggestive plist key name AND a substantial <string> value. The name alone
# is not enough: apps store booleans and integers under names like
# ExportPassword and AiMaxTokens, and flagging those trains you to dismiss the
# gate.
_scan_plist_key_values() {
  awk '
    /<[kK][eE][yY]>/ {
      if (tolower($0) ~ /<key>[^<]*(api[_-]?key|token|secret|password|passphrase|credential)s?<\/key>/) {
        keyline = $0; keyno = NR; pending = 1
      } else { pending = 0 }
      next
    }
    pending {
      if (match($0, /<string>[^<]*<\/string>/)) {
        # inner text = match minus "<string>" (8) and "</string>" (9)
        if (RLENGTH - 17 >= 12) printf "%d:%s\n", keyno, keyline
      }
      pending = 0
    }
  ' "$1" 2>/dev/null || true
}

# Returns 0 when the files are clean, 1 when anything looks like a secret.
scan_for_secrets() {
  (( $# == 0 )) && return 0

  # Case-INSENSITIVE: field names, and material that identifies itself.
  local -a patterns_i=(
    '-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----'
    '(api[_-]?key|apikey|secret[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|password|passphrase|token)['\''"]?[[:space:]]*[:=][[:space:]]*['\''"]?[A-Za-z0-9_./+-]{12,}'
    'Bearer[[:space:]]+[A-Za-z0-9._-]{20,}'
  )

  # Case-SENSITIVE: vendor prefixes are defined by their exact casing, and
  # matching them with -i turns them into base64 noise — `AIza…` folded to
  # case-insensitive matches <data> blobs in real plists.
  local -a patterns_s=(
    'sk-(ant-)?[A-Za-z0-9_-]{20,}'          # OpenAI sk- / sk-proj-, Anthropic sk-ant-
    'gh[pousr]_[A-Za-z0-9]{30,}'            # GitHub classic PAT / OAuth / refresh
    'github_pat_[A-Za-z0-9_]{20,}'          # GitHub fine-grained PAT
    'AKIA[0-9A-Z]{16}'                      # AWS access key id
    'xox[baprs]-[A-Za-z0-9-]{10,}'          # Slack
    'AIza[0-9A-Za-z_-]{35}'                 # Google API key
  )
  local pat file hits=0 line target tmp_xml out rc pass gflags
  local -a active
  for file in "$@"; do
    [[ -f "$file" ]] || continue

    # Binary plists are not greppable — the patterns below would silently match
    # nothing. Scan an xml1 copy; the stored file is left untouched.
    target="$file"
    tmp_xml=""
    if [[ "$(head -c 8 "$file" 2>/dev/null)" == "bplist00" ]]; then
      tmp_xml="$(mimac_mktemp)"
      if plutil -convert xml1 -o "$tmp_xml" "$file" 2>/dev/null; then
        target="$tmp_xml"
      else
        warn "could not convert $file to xml1 — scanning raw bytes"
        rm -f "$tmp_xml"
        tmp_xml=""
      fi
    fi

    for pass in i s; do
      if [[ "$pass" == i ]]; then active=("${patterns_i[@]}"); gflags=-Ein
      else                        active=("${patterns_s[@]}"); gflags=-En
      fi
      for pat in "${active[@]}"; do
        # -e because several patterns begin with `-`. rc 0 = match, 1 = no
        # match, >1 = grep could not run the pattern at all.
        rc=0
        out=$(grep "$gflags" -e "$pat" "$target" 2>/dev/null) || rc=$?
        if (( rc > 1 )); then
          # A pattern that does not compile would otherwise report "clean". For
          # a gate that blocks a push, failing closed is the only safe reading.
          err "secret scan FAILED on ${file} (grep rc=${rc}) — pattern: ${pat:0:60}"
          hits=1
          continue
        fi
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          err "possible secret in ${file}: ${line:0:120}"
          hits=1
        done <<< "$out"
      done
    done

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      err "possible secret in ${file}: ${line:0:120}"
      hits=1
    done < <(_scan_plist_key_values "$target")

    [[ -n "$tmp_xml" ]] && rm -f "$tmp_xml"
  done
  return "$hits"
}

# Wraps scan_for_secrets with the confirmation. Returns 0 to proceed.
# Lowercases with `tr` rather than ${x,,} so this sources cleanly under the
# bash 3.2 that macOS ships.
require_clean_secrets() {
  scan_for_secrets "$@" && return 0
  warn "Potential secrets detected in files above."
  if (( ${NONINTERACTIVE:-0} )); then
    err "Aborting (NONINTERACTIVE=1)."
    return 1
  fi
  if [[ ! -t 0 ]]; then
    err "Aborting (not a TTY — cannot confirm)."
    return 1
  fi
  printf '%s  Push/commit anyway?%s ' "$_YLW" "$_R" >&2
  local _ans
  read -r _ans </dev/tty
  _ans=$(printf '%s' "$_ans" | tr '[:upper:]' '[:lower:]')
  [[ "$_ans" =~ ^(y|yes)$ ]]
}

# Ensure DRY_RUN is defined (default 0 if not set by caller)
: "${DRY_RUN:=0}"

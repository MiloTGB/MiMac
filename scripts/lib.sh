#!/usr/bin/env bash
# lib.sh — shared helpers for MiMac scripts
# Source this file; do not execute directly.
# Scope: the scripts in scripts/, and the Makefile's update recipe. Standalone
# bin/ tools use bin/lib/common.sh. Both define ok, warn, err and info, so a
# function here whose lines must stay together on one stream prints with
# printf, as topgrade_verdict does.

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

# BREW_PATHS — where Homebrew's brew is when installed: /opt/homebrew on Apple
# silicon, /usr/local on Intel. MIMAC_BREW names one other path instead, so a
# test can stand a stub in for it; scripts/sync takes MIMAC_BREW the same way.
if [[ -n "${MIMAC_BREW:-}" ]]; then
  BREW_PATHS=("$MIMAC_BREW")
else
  BREW_PATHS=(/opt/homebrew/bin/brew /usr/local/bin/brew)
fi

# homebrew_on_path — put Homebrew on PATH when it is installed and its bin is
# not on PATH. Returns 1 when there is no Homebrew.
#
# make all runs every phase with the PATH it started with, and on a new Mac
# that shell started before Phase 2 installed Homebrew. brew-packages runs
# `brew shellenv` for itself, which reaches its own process alone, so after it
# build-tools failed with "Go is not installed" and post-install skipped the
# topgrade, gh and htop configs as "not installed" — on the Mac Phase 2 had
# just installed them on. Ported from mrk (its audit 19, W-31).
#
# Only when the bin is missing: shellenv puts Homebrew first on PATH, and a
# PATH that already holds it keeps its order, so a Mac set up from its
# dotfiles sees no change.
homebrew_on_path() {
  local b
  for b in "${BREW_PATHS[@]}"; do
    [[ -x "$b" ]] || continue
    case ":$PATH:" in
      *":${b%/*}:"*) ;;
      *) eval "$("$b" shellenv)" ;;
    esac
    return 0
  done
  return 1
}

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

# Scripts in scripts/ that setup does NOT link into ~/bin: phase entry points
# (run them through make), sourced helpers, and dev-only tools. doctor reads
# the same list, so a name added here is neither linked nor reported missing.
mimac_skip_link() {
  case "$1" in
    brew-packages|install|setup|post-install) return 0 ;;  # internal phases
    defaults.sh|hardening.sh|lib.sh) return 0 ;;           # helpers, not commands
    uninstall) return 0 ;;                                  # use make targets
    # ~/bin/status belongs to the mimac-status TUI (make mimac-status links
    # it). Linking this script too made setup and build-tools overwrite each
    # other's link on every run. `make status` still runs this script, which
    # prints the same dashboard as text (mimac-status --plain).
    status) return 0 ;;
    *) return 1 ;;
  esac
}

mimac_mktemp()   { mktemp    "${TMPDIR:-/tmp}/mimac.XXXXXX"; }
mimac_mktemp_d() { mktemp -d "${TMPDIR:-/tmp}/mimac.XXXXXX"; }

# mimac_is_dotfile PATH — PATH, an entry at the top of dotfiles/, is one setup
# links into ~: a regular file, not a directory or a symlink, and not
# documentation, an example or Finder's .DS_Store. doctor and mimac-status
# (checkDotfiles) apply the same rule.
#
# setup used to link whatever was there. Claude Code creates dotfiles/.claude/
# for a session started in that folder (.gitignore lists it), and setup would
# then have moved the real ~/.claude — settings, sessions, memory — into
# ~/.mimac/backups and linked ~/.claude into the repository. mrk did exactly
# that (its audit 19, W-4).
mimac_is_dotfile() {
  [[ -f "$1" && ! -L "$1" ]] || return 1
  case "${1##*/}" in
    *.example|README*|*.md|.DS_Store) return 1 ;;
  esac
}

# tool_freshness REPO BINDIR — for each Go tool MiMac builds, print its name
# and its state, tab-separated: "ok"; "stale", when a source under tools/<dir>
# or tools/theme — go.mod and go.sum included, since a dependency bump changes
# the binary without touching a .go file — is newer than BINDIR/NAME; or
# "missing". Both tools import the shared theme, so a change there makes each
# one stale. doctor and mimac-status both read it, so they agree.
tool_freshness() {
  local repo=$1 bindir=$2 name dir bin f state
  for name in mimac-picker mimac-status; do
    case "$name" in
      mimac-picker) dir=picker ;;
      *)            dir=$name ;;
    esac
    bin="$bindir/$name"
    if [[ ! -e "$bin" ]]; then
      state=missing
    else
      state=ok
      while IFS= read -r -d '' f; do
        if [[ "$f" -nt "$bin" ]]; then state=stale; break; fi
      done < <(find "$repo/tools/$dir" "$repo/tools/theme" \( -name '*.go' -o -name go.mod -o -name go.sum \) -print0 2>/dev/null)
    fi
    printf '%s\t%s\n' "$name" "$state"
  done
}

# topgrade_verdict RC LOG — say what topgrade's exit status RC means, from the
# Summary it printed into LOG, a recording of the run.
#
# topgrade exits 1 when any step failed, and with no_retry and assume_yes, as
# assets/topgrade.toml sets them, it runs every step first and stops for none.
# So a run that upgraded everything but one cask ended on a bare
# "make: *** [update] Error 1", which reads as though the run broke off there.
# topgrade prints its Summary only once every step has run, so the Summary is
# the evidence: with it, this names the steps that failed and says the rest
# ran; without it, it says the run stopped short, and never that everything
# ran. Ported from mrk, where a 404 on one cask download did exactly this.
#
# topgrade draws a step's header two ways: "── 20:04:24 - Summary ────" at a
# terminal, in U+2500, and "―― 20:04:24 - Summary ――" away from one, in
# U+2015. Both are read. A command after the Summary that fails is not in it:
# topgrade runs the ones after it and exits 1, which is the "though its
# summary shows" case below.
#
# Every line goes to stderr through printf, in this file's own marks, and not
# through warn and info, so the verdict reads the same whichever library a
# caller sourced last (bin/lib/common.sh defines both too).
topgrade_verdict() {
  local rc=$1 log=$2 found n=0 failed=0 after=0 names="" cleanup=""
  local _w="${_YLW}  ⚠${_R}" _g="${_GRN}  ✓${_R}" _i="   "
  # Strip colour codes, and the window title topgrade sets before each header,
  # which shares the header's line when the terminal reports no width.
  #
  # In the C locale, set for this pipeline alone: the recording is read as
  # bytes. It holds the output of every package manager topgrade ran, and in a
  # UTF-8 locale macOS's sed, tr and awk each stop at the first byte that is not
  # UTF-8 — one Latin-1 file name in a download line is enough — so the Summary
  # below it was never seen. The header patterns are byte strings and match the
  # same in the C locale.
  found=$(export LC_ALL=C; sed -e $'s/\x1b\\[[0-9;?]*[A-Za-z]//g' -e $'s/\x1b][^\x07]*\x07//g' "$log" 2>/dev/null | tr -d '\r' | awk '
    /^(──|――) (.* - )?Summary (─|―)/ { insum = 1; seen = 1; n = 0; f = 0; post = 0; names = ""; next }
    insum && /^(──|――) /    { insum = 0 }
    insum && /: OK$/        { n++; next }
    insum && /: FAILED$/    { n++; f++; sub(/: FAILED$/, ""); names = names (names == "" ? "" : ", ") $0; next }
    seen && !insum && /^(──|――) / { post++ }
    END { if (seen) printf "%d\t%d\t%d\t%s\n", n, f, post, names }')
  if [[ -z "$found" ]]; then
    if (( rc != 0 )); then
      printf '%s %s\n' "$_w" "topgrade stopped before its summary (exit $rc): not every step ran. Its last output is above." >&2
    fi
    return 0
  fi
  IFS=$'\t' read -r n failed after names <<< "$found"
  if (( failed > 0 )); then
    printf '%s %s\n' "$_w" "Update finished: every step ran. $failed of $n failed: $names." >&2
    if (( after == 1 )); then
      cleanup=", and the clean-up command after them ran"
    elif (( after > 1 )); then
      cleanup=", and the $after clean-up commands after them ran"
    fi
    printf '%s %s\n' "$_i" "Nothing was interrupted: the other $(( n - failed )) succeeded$cleanup." >&2
    # make sets MAKELEVEL for a recipe: only there does an "Error" line follow.
    if [[ -n "${MAKELEVEL:-}" ]]; then
      printf '%s %s\n' "$_i" "The exit status is $rc for the failed step alone, which make reports next as \"Error $rc\"." >&2
    else
      printf '%s %s\n' "$_i" "The exit status is $rc for the failed step alone." >&2
    fi
  elif (( rc != 0 )); then
    printf '%s %s\n' "$_w" "topgrade exited $rc, though its summary shows no failed step: a command after the summary failed. See above." >&2
  elif (( n == 1 )); then
    printf '%s %s\n' "$_g" "Update finished: its one step succeeded." >&2
  else
    printf '%s %s\n' "$_g" "Update finished: all $n steps succeeded." >&2
  fi
}

# run_topgrade [ARGS...] — run topgrade, then say what its exit status means
# (topgrade_verdict). Returns topgrade's status. make update runs it.
#
# At a terminal the run is recorded through script(1), which gives topgrade a
# terminal of its own, so its colours, progress bars and sudo prompt are as
# they were; script returns the command's status. Without a terminal it is a
# plain tee. The recording is removed afterwards.
#
# It is removed on INT, TERM and HUP too: otherwise a run interrupted away from
# a terminal (`make update | tee log`, then Ctrl-C) left its output so far in
# $TMPDIR. The trap removes the file, puts the caller's traps back, and sends
# the signal again, so the shell still ends as the signal ends it, or as the
# caller's own trap decides. At a terminal Ctrl-C reaches topgrade through
# script, and the run ends by the last lines here.
run_topgrade() {
  local log rc=0 saved sig
  if ! log=$(mimac_mktemp); then
    topgrade "$@"
    return
  fi
  saved=$(trap -p INT TERM HUP)
  for sig in INT TERM HUP; do
    # shellcheck disable=SC2064  # the path, the traps and the signal as they are now
    trap "rm -f $(printf '%q' "$log")
trap - INT TERM HUP
$saved
kill -s $sig \$\$" "$sig"
  done
  if [[ -t 0 && -t 1 && "$(uname -s)" == Darwin ]] && command -v script >/dev/null 2>&1; then
    script -q "$log" topgrade "$@" || rc=$?
  else
    topgrade "$@" 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
  fi
  topgrade_verdict "$rc" "$log"
  rm -f "$log"
  trap - INT TERM HUP
  eval "$saved"
  return "$rc"
}

# Ensure DRY_RUN is defined (default 0 if not set by caller)
: "${DRY_RUN:=0}"

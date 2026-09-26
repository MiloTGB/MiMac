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
    # other's link on every run. `make status` still runs this script.
    status) return 0 ;;
    *) return 1 ;;
  esac
}

mimac_mktemp()   { mktemp    "${TMPDIR:-/tmp}/mimac.XXXXXX"; }

# Ensure DRY_RUN is defined (default 0 if not set by caller)
: "${DRY_RUN:=0}"

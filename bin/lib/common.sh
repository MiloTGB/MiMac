#!/usr/bin/env bash
# common.sh — shared helpers for MiMac bin/ scripts
# Source this file; do not execute directly.

[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# ── Colors (tput-based, degrades gracefully) ─────────────────────────────────

if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
  _BOLD="$(tput bold)"
  _DIM="$(tput dim)"
  _RST="$(tput sgr0)"
  _RED="$(tput setaf 1)"
  _GRN="$(tput setaf 2)"
  _YLW="$(tput setaf 3)"
  _BLU="$(tput setaf 4)"
  _CYN="$(tput setaf 6)"
else
  _BOLD='' _DIM='' _RST='' _RED='' _GRN='' _YLW='' _BLU='' _CYN=''
fi

# ── Logging ──────────────────────────────────────────────────────────────────

log()  { printf '%s  ▸%s %s\n' "$_CYN" "$_RST" "$*" >&2; }
ok()   { printf '%s  ✓%s %s\n' "$_GRN" "$_RST" "$*" >&2; }
warn() { printf '%s  ⚠%s %s\n' "$_YLW" "$_RST" "$*" >&2; }
err()  { printf '%s  ✗%s %s\n' "$_RED" "$_RST" "$*" >&2; }

# ── Confirmation prompt ─────────────────────────────────────────────────────

# Usage: confirm "Do something?" && do_it
# Honors YES=1 for auto-confirm (non-interactive use).
# shellcheck disable=SC2034  # read by callers
CONFIRM_LAST=""
confirm() {
  local prompt="${1:-Continue?}"
  if [[ "${YES:-}" == "1" ]]; then
    CONFIRM_LAST="y"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    CONFIRM_LAST="n"
    return 1
  fi
  printf '%s [y/N]: ' "$prompt" >&2
  local ans
  read -r ans </dev/tty
  # shellcheck disable=SC2034
  CONFIRM_LAST="$ans"
  [[ "$ans" =~ ^[Yy]$ ]]
}

# ── Utility functions ───────────────────────────────────────────────────────

# Check if a process is running by name.
is_running() {
  pgrep -xq "$1" 2>/dev/null
}

# Exit with error if any required commands are missing.
# Usage: require_cmd jq curl git
require_cmd() {
  local missing=()
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    err "Missing required command(s): ${missing[*]}"
    err "Install with: brew install ${missing[*]}"
    exit 1
  fi
}

# Format bytes into human-readable size (e.g., 1.5G, 234M).
human_bytes() {
  local bytes="${1:-0}"
  if (( bytes >= 1073741824 )); then
    printf '%.1fG' "$(echo "$bytes / 1073741824" | bc -l)"
  elif (( bytes >= 1048576 )); then
    printf '%.1fM' "$(echo "$bytes / 1048576" | bc -l)"
  elif (( bytes >= 1024 )); then
    printf '%.1fK' "$(echo "$bytes / 1024" | bc -l)"
  else
    printf '%dB' "$bytes"
  fi
}

# Get size of a file or directory in bytes.
du_bytes() {
  local target="${1:-.}"
  if [[ -f "$target" ]]; then
    stat -f%z "$target" 2>/dev/null || echo 0
  elif [[ -d "$target" ]]; then
    du -sk "$target" 2>/dev/null | awk '{print $1 * 1024}'
  else
    echo 0
  fi
}

# Safe delete — refuses to remove anything outside $HOME.
# Honors DRY_RUN=1 to preview without acting.
safe_rm() {
  local target="$1"
  if [[ -z "$target" ]]; then
    err "safe_rm: no target specified"
    return 1
  fi

  # Resolve to absolute path
  local abs
  abs="$(cd "$(dirname "$target")" 2>/dev/null && pwd)/$(basename "$target")"

  if [[ "$abs" != "$HOME"/* ]]; then
    err "safe_rm: refusing to delete outside \$HOME: $abs"
    return 1
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log "[dry-run] Would remove: $abs"
    return 0
  fi

  rm -rf "$abs"
}

# Resolve the real path of a file, following symlinks.
resolve_path() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1"
  else
    local target="$1"
    while [[ -L "$target" ]]; do
      local dir
      dir="$(cd "$(dirname "$target")" && pwd)"
      target="$(readlink "$target")"
      [[ "$target" != /* ]] && target="$dir/$target"
    done
    echo "$(cd "$(dirname "$target")" && pwd)/$(basename "$target")"
  fi
}

: "${DRY_RUN:=0}"

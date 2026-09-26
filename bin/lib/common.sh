#!/usr/bin/env bash
# common.sh — shared helpers for MiMac bin/ scripts
# Source this file; do not execute directly.

[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# ── Colors (tput-based, degrades gracefully) ─────────────────────────────────

if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
  _RST="$(tput sgr0)"
  _RED="$(tput setaf 1)"
  _GRN="$(tput setaf 2)"
  _YLW="$(tput setaf 3)"
  _CYN="$(tput setaf 6)"
else
  _RST='' _RED='' _GRN='' _YLW='' _CYN=''
fi

# ── Logging ──────────────────────────────────────────────────────────────────

log()  { printf '%s  ▸%s %s\n' "$_CYN" "$_RST" "$*" >&2; }
ok()   { printf '%s  ✓%s %s\n' "$_GRN" "$_RST" "$*" >&2; }
warn() { printf '%s  ⚠%s %s\n' "$_YLW" "$_RST" "$*" >&2; }
err()  { printf '%s  ✗%s %s\n' "$_RED" "$_RST" "$*" >&2; }
info() { printf '    %s\n' "$*" >&2; }

# ── Utility functions ───────────────────────────────────────────────────────

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

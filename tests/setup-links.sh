#!/usr/bin/env bash
# setup-links.sh — prove that setup --only dotfiles backs up whatever a link
# replaces, and makes no backup directory when it replaces nothing.
#
# setup used to back up only a real file in a dotfile's place. A link that
# pointed elsewhere, or at nothing, was replaced with no record, so a dotfile
# linked in from another folder was lost. And it made a timestamped backup
# directory on every run, so ~/.mimac/backups filled with empty ones that the
# dashboard counted as backups.
#
# setup runs under a throwaway HOME, against this repository's dotfiles. Each
# place is filled with one kind of thing first: a file, a directory, a link
# elsewhere, a dangling link, and a link that reaches the same file by another
# path. Under /bin/bash and the bash running this file.
# Nothing reaches the real HOME. `make test` runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" != --inner ]]; then
  run_under() {
    # shellcheck disable=SC2016  # expanded by the inner bash, not this one
    printf '  under bash %s\n' "$("$1" -c 'echo "${BASH_VERSION%%(*}"')"
    "$1" "${BASH_SOURCE[0]}" --inner "$1"
  }
  rc=0
  run_under /bin/bash || rc=1
  if [[ ! "$BASH" -ef /bin/bash ]]; then run_under "$BASH" || rc=1; fi
  exit "$rc"
fi
BASH_UNDER_TEST="$2"

# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

W=$(mimac_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
H="$W/home" S="$W/stubs" ELSE="$W/elsewhere"
mkdir -p "$H" "$S" "$ELSE"
ln -s "$BASH_UNDER_TEST" "$S/bash"
printf '#!/bin/sh\nexit 0\n' > "$S/sudo"; chmod +x "$S/sudo"

D="$REPO_ROOT/dotfiles"
# A second path to the same dotfiles directory, for the -ef case.
ln -s "$D" "$W/dotfiles-alias"

setup() { # ARGS... — output in $W/out, status in RC
  env -i HOME="$H" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="${TMPDIR:-/tmp}" TERM=dumb \
    "$BASH_UNDER_TEST" "$REPO_ROOT/scripts/setup" --only dotfiles "$@" > "$W/out" 2>&1
  RC=$?
}
show() { sed 's/^/    /' "$W/out"; }
backups() { find "$H/.mimac/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null; }

# The places, each filled with something else first.
echo "my own aliases" > "$H/.aliases"                    # a real file
mkdir -p "$H/.hushlogin" && echo x > "$H/.hushlogin/x"   # a directory
echo "zprofile from elsewhere" > "$ELSE/zprofile"
ln -s "$ELSE/zprofile" "$H/.zprofile"                    # a link elsewhere
ln -s "$W/gone" "$H/.zshenv"                             # a dangling link
ln -s "$W/dotfiles-alias/.gitconfig" "$H/.gitconfig"     # the same file, another path

# ── 1. A dry run moves nothing, and makes no backup directory ────────────────

setup --dry-run
if (( RC == 0 )) && [[ -z "$(backups)" ]] && [[ -f "$H/.aliases" && ! -L "$H/.aliases" ]] \
   && [[ "$(readlink "$H/.zprofile")" == "$ELSE/zprofile" ]] \
   && grep -q "Would backup: $H/.zprofile" "$W/out" && grep -q "Would backup: $H/.zshenv" "$W/out"; then
  pass "a dry run: names the two links it would back up, and moves and makes nothing"
else
  fail "a dry run: exit $RC, backups: $(backups | tr '\n' ' ')"; show
fi

# ── 2. The real run: each one backed up, the same file relinked without one ──

setup
B=$(backups)
if (( RC == 0 )) && [[ "$(printf '%s\n' "$B" | grep -c .)" == 1 ]] \
   && [[ -f "$B/.aliases" && "$(cat "$B/.aliases")" == "my own aliases" ]] \
   && [[ -d "$B/.hushlogin" ]] \
   && [[ -L "$B/.zprofile" && "$(readlink "$B/.zprofile")" == "$ELSE/zprofile" ]] \
   && [[ -L "$B/.zshenv" && "$(readlink "$B/.zshenv")" == "$W/gone" ]] \
   && [[ ! -e "$B/.gitconfig" && ! -L "$B/.gitconfig" ]]; then
  pass "a file, a directory, a link elsewhere and a dangling link are backed up; the same file is not"
else
  fail "the real run: exit $RC, backed up: $(find "$B" -mindepth 1 -maxdepth 1 -exec basename {} \; 2>/dev/null | tr '\n' ' ')"; show
fi

linked=1
for f in .aliases .hushlogin .zprofile .zshenv .gitconfig .zshrc Makefile; do
  [[ "$(readlink "$H/$f")" == "$D/$f" ]] || { linked=0; echo "    not linked: $f -> $(readlink "$H/$f")"; }
done
if (( linked )); then pass "every dotfile is linked into the home"; else fail "some dotfiles are not linked"; fi

# ── 3. A second run: nothing to back up, and no new backup directory ─────────

sleep 1   # a new run would name its directory for a new second
setup
if (( RC == 0 )) && [[ "$(backups)" == "$B" ]]; then
  pass "a run with nothing to back up makes no backup directory"
else
  fail "a second run: exit $RC, backups now: $(backups | tr '\n' ' ')"; show
fi

if (( fails )); then
  err "$fails setup link check(s) failed"
  exit 1
fi
ok "setup link checks passed"

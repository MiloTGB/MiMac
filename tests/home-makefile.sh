#!/usr/bin/env bash
# home-makefile.sh — prove that ~/Makefile runs every one of ~/MiMac's make
# targets from the home directory, with its ARGS.
#
# ~/Makefile is dotfiles/Makefile, linked into the home. It used to forward
# eleven targets by name and no others, so `make check` or `make sync-clean`
# from ~ said "No rule to make target".
#
# Each case runs dotfiles/Makefile with MIMAC naming a stub Makefile that
# records the target and ARGS it was asked for, so nothing is run. One case
# hands it the real Makefile under make -n, which prints and runs nothing.
# Ported from mrk's tests/home-makefile.sh. `make test` runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

W=$(mimac_mktemp_d) || exit 1
trap 'rm -rf "$W"' EXIT
STUB="$W/MiMac"
mkdir -p "$STUB" "$W/home"
: > "$W/log"

# The stub ~/MiMac: every target records itself, help says who it is, and one
# target fails, as a target ~/MiMac has no rule for does.
cat > "$STUB/Makefile" <<MK
help:
	@echo "stub help"
nope:
	@exit 3
.DEFAULT:
	@printf '%s ARGS=%s\n' "\$@" "\$(ARGS)" >> "$W/log"
MK

# home ARGS... — dotfiles/Makefile from the home, as make finds ~/Makefile
home() {
  : > "$W/log"
  (cd "$W/home" && make --no-print-directory -f "$REPO_ROOT/dotfiles/Makefile" MIMAC="$STUB" "$@") > "$W/out" 2>&1
}
logged() { [[ "$(cat "$W/log")" == "$1" ]]; }

home check
if logged "check ARGS="; then pass "make check: forwarded to ~/MiMac"; else fail "make check: $(cat "$W/out" "$W/log")"; fi

home trim-services ARGS=-n
if logged "trim-services ARGS=-n"; then pass "a forwarded target keeps its ARGS"; else fail "make trim-services ARGS=-n: $(cat "$W/out" "$W/log")"; fi

home doctor ARGS=--fix
if logged "doctor ARGS=--fix"; then pass "a named rule keeps its ARGS too"; else fail "make doctor ARGS=--fix: $(cat "$W/out" "$W/log")"; fi

home
if grep -q 'From ~/' "$W/out" && grep -q 'stub help' "$W/out" && [[ ! -s "$W/log" ]]; then
  pass "make with no target: the help, ~/'s and ~/MiMac's"
else
  fail "make with no target:"; sed 's/^/    /' "$W/out"
fi

home nope; rc=$?
if (( rc != 0 )); then pass "a target that fails in ~/MiMac fails here too (exit $rc)"; else fail "make nope exited 0"; fi

# Every target of the real Makefile reaches ~/MiMac.
missed=""
while IFS= read -r t; do
  [[ "$t" == help ]] && continue
  home "$t"
  logged "$t ARGS=" || missed="$missed $t"
done < <(sed -nE 's/^([a-zA-Z][a-zA-Z0-9_-]*):.*/\1/p' "$REPO_ROOT/Makefile" | sort -u)
if [[ -z "$missed" ]]; then
  pass "every target of ~/MiMac's Makefile is forwarded from the home"
else
  fail "not forwarded:$missed"
fi
if grep -q '^Makefile ' "$W/log"; then fail "make tried to rebuild ~/Makefile through ~/MiMac"; fi

# The real Makefile, under make -n: the recipe it would run, run by none.
if (cd "$W/home" && make -n --no-print-directory -f "$REPO_ROOT/dotfiles/Makefile" MIMAC="$REPO_ROOT" update) 2>&1 | grep -q 'run_topgrade'; then
  pass "make -n update against the real Makefile: its recipe, printed and not run"
else
  fail "make -n update against the real Makefile did not reach its recipe"
fi

if (( fails )); then
  err "$fails home Makefile check(s) failed"
  exit 1
fi
ok "home Makefile checks passed"

#!/usr/bin/env bash
# homebrew-path.sh — prove that what runs after Phase 2 finds the Homebrew it
# installed, though the shell make all started in had none on its PATH.
#
# make all runs every phase with the PATH it started with. On a new Mac that
# PATH predates Homebrew, so build-tools failed with "Go is not installed" just
# after Phase 2 had installed Go, and post-install skipped the topgrade, gh and
# htop configs as "not installed". homebrew_on_path in lib.sh fixes both.
#
# Homebrew is a sandbox prefix: MIMAC_BREW names its brew, a stub whose
# shellenv puts the prefix's bin on PATH as the real one does, and the bin
# holds a stub go that records the build. make build-tools runs in a copy of
# the repository under a throwaway HOME, with a new Mac's PATH. Nothing reaches
# the real Homebrew, ~/bin or the network. Under /bin/bash and the bash running
# this file. `make test` runs it.

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
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
P="$W/homebrew"    # the sandbox Homebrew prefix
H="$W/home"
mkdir -p "$P/bin" "$H"
NEW_MAC_PATH=/usr/bin:/bin:/usr/sbin:/sbin

cat > "$P/bin/brew" <<EOF
#!/bin/sh
[ "\$1" = shellenv ] || exit 9
echo 'export HOMEBREW_PREFIX="$P";'
echo 'export PATH="$P/bin:$P/sbin\${PATH+:\$PATH}";'
EOF
cat > "$P/bin/go" <<EOF
#!/bin/sh
out=""
while [ \$# -gt 0 ]; do
  [ "\$1" = -o ] && { out="\$2"; shift; }
  shift
done
printf 'go build %s\n' "\${out##*/}" >> "$W/go-builds"
[ -n "\$out" ] && printf '#!/bin/sh\n' > "\$out"
exit 0
EOF
chmod +x "$P/bin/brew" "$P/bin/go"

# lib.sh as the bash under test sources it, with MIMAC_BREW set before.
in_bash() { # SCRIPT [PATH] — run SCRIPT after sourcing lib.sh; its output
  # shellcheck disable=SC2016  # expanded by the bash under test
  env -i HOME="$H" PATH="${2:-$NEW_MAC_PATH}" MIMAC_BREW="${BREW:-$P/bin/brew}" \
    "$BASH_UNDER_TEST" -c '. "$1/scripts/lib.sh"; '"$1" bash "$REPO_ROOT" 2>&1
}

# ── 1. homebrew_on_path ──────────────────────────────────────────────────────

# shellcheck disable=SC2016  # expanded by the bash under test
PROBE='homebrew_on_path; echo "rc=$? PATH=$PATH"'
out=$(in_bash "$PROBE")
if [[ "$out" == "rc=0 PATH=$P/bin:$P/sbin:$NEW_MAC_PATH" ]]; then
  pass "Homebrew installed, not on PATH: its bin goes first"
else
  fail "Homebrew not on PATH: $out"
fi

out=$(in_bash "$PROBE" "/usr/bin:$P/bin:/bin")
if [[ "$out" == "rc=0 PATH=/usr/bin:$P/bin:/bin" ]]; then
  pass "Homebrew already on PATH: the PATH and its order are left as they are"
else
  fail "Homebrew already on PATH: $out"
fi

out=$(BREW="$W/none/bin/brew" in_bash "$PROBE")
if [[ "$out" == "rc=1 PATH=$NEW_MAC_PATH" ]]; then
  pass "no Homebrew: returns 1, and the PATH is unchanged"
else
  fail "no Homebrew: $out"
fi

# ── 2. make build-tools with a new Mac's PATH ────────────────────────────────

R="$W/MiMac"
while IFS= read -r -d '' f; do
  [[ -f "$REPO_ROOT/$f" ]] || continue
  mkdir -p "$R/$(dirname "$f")"
  cp -p "$REPO_ROOT/$f" "$R/$f"
done < <(git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard Makefile scripts bin tools)
: > "$W/go-builds"
env -i HOME="$H" PATH="$NEW_MAC_PATH" MIMAC_BREW="$P/bin/brew" TERM=dumb \
  make --no-print-directory -C "$R" build-tools > "$W/out" 2>&1; rc=$?
if (( rc == 0 )) && grep -q 'go build mimac-picker' "$W/go-builds" && grep -q 'go build mimac-status' "$W/go-builds" \
   && ! grep -q 'Go is not installed' "$W/out"; then
  pass "make build-tools with a new Mac's PATH: finds Homebrew's go and builds both tools"
else
  fail "make build-tools with a new Mac's PATH: exit $rc"; sed 's/^/    /' "$W/out"
fi

: > "$W/go-builds"
env -i HOME="$H" PATH="$NEW_MAC_PATH" MIMAC_BREW="$W/none/bin/brew" TERM=dumb \
  make --no-print-directory -C "$R" build-tools > "$W/out" 2>&1; rc=$?
if (( rc != 0 )) && grep -q 'Go is not installed' "$W/out" && [[ ! -s "$W/go-builds" ]]; then
  pass "make build-tools with no Homebrew at all: still says Go is not installed"
else
  fail "make build-tools with no Homebrew: exit $rc"; sed 's/^/    /' "$W/out"
fi

# ── 3. post-install calls it before its first lookup ─────────────────────────

# post-install configures this Mac's apps and is not run here. What matters is
# that homebrew_on_path runs before the first `command -v`.
pi="$REPO_ROOT/scripts/post-install"
call=$(grep -n '^homebrew_on_path' "$pi" | head -1 | cut -d: -f1)
first=$(grep -n 'command -v' "$pi" | head -1 | cut -d: -f1)
if [[ -n "$call" && -n "$first" ]] && (( call < first )); then
  pass "post-install puts Homebrew on PATH (line $call) before its first lookup (line $first)"
else
  fail "post-install: homebrew_on_path at line '${call}', first command -v at line '${first}'"
fi

if (( fails )); then
  err "$fails Homebrew PATH check(s) failed"
  exit 1
fi
ok "Homebrew PATH checks passed"

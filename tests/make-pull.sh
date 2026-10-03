#!/usr/bin/env bash
# make-pull.sh — prove that make pull rebuilds and relinks what the commits it
# pulled changed, and nothing else.
#
# make pull used to only fast-forward. A pull that changed tools/ left the old
# Go binaries in ~/bin, one that added a script left it off the PATH, and one
# that added a dotfile left it unlinked, each until the matching make target
# was run by hand. check-updates' "yes" pulls through it, so it did none of
# this either.
#
# Each case commits to a scratch origin and runs make pull in a clone of it at
# ~/MiMac under a throwaway HOME, so the clone is the checkout ~/bin serves. go
# is a stub that records the build and writes a placeholder binary; sudo,
# defaults, osascript, launchctl, chsh and xcode-select are stubs that run
# nothing. The last cases pull into a second clone ~/bin does not serve, make a
# build fail, and make the pull itself fail.
# Nothing reaches the real HOME, ~/bin, the network or any preferences.
# Ported from mrk's tests/make-pull.sh. `make test` runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

REAL_GIT="$(command -v git)" || { fail "git not found"; exit 1; }
REAL_MAKE="$(command -v make)" || { fail "make not found"; exit 1; }

W=$(mimac_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
H="$W/home"         # the throwaway HOME
S="$W/stubs"        # first on PATH
ORIGIN="$W/origin.git"
UP="$W/upstream"    # where the cases commit, then push to ORIGIN
CLONE="$H/MiMac"    # the checkout ~/bin serves
OTHER="$W/other"    # a checkout it does not
mkdir -p "$H/bin" "$S" "$UP"
: > "$W/calls"

# ── Stubs ────────────────────────────────────────────────────────────────────

for cmd in sudo defaults osascript launchctl chsh xcode-select; do
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/calls"\n' "$cmd" "$W" > "$S/$cmd"
  chmod +x "$S/$cmd"
done
# go build -o BINARY . — record the build, write BINARY. With $W/go-fails
# there, the build fails instead.
cat > "$S/go" <<EOF
#!/bin/sh
[ -f "$W/go-fails" ] && { echo "go: stub build failure" >&2; exit 1; }
out=""
while [ \$# -gt 0 ]; do
  [ "\$1" = -o ] && { out="\$2"; shift; }
  shift
done
printf 'go build %s\n' "\${out##*/}" >> "$W/go-builds"
[ -n "\$out" ] && printf '#!/bin/sh\n' > "\$out"
exit 0
EOF
chmod +x "$S/go"
ln -s "$REAL_GIT" "$S/git"
ln -s "$REAL_MAKE" "$S/make"

# MIMAC_BREW names a brew that does not exist, so the Makefile's brew-env finds
# no Homebrew to put ahead of the stubs. Without it, on a Mac with Homebrew,
# the real go would build the tools in place of the stub, fetching modules.
run_env() {
  env -i HOME="$H" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" MIMAC_BREW="$W/no-homebrew/bin/brew" \
    TMPDIR="${TMPDIR:-/tmp}" TERM=dumb \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test.invalid \
    GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test.invalid \
    "$@"
}

# ── The scratch origin: the repository's files as they are now ───────────────

while IFS= read -r -d '' f; do
  [[ -f "$REPO_ROOT/$f" ]] || continue
  mkdir -p "$UP/$(dirname "$f")"
  cp -p "$REPO_ROOT/$f" "$UP/$f"
done < <(git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard Makefile scripts bin dotfiles tools)
run_env git -C "$UP" init -q -b main
run_env git -C "$UP" add -A
run_env git -C "$UP" commit -qm seed
run_env git clone -q --bare "$UP" "$ORIGIN"
run_env git -C "$UP" remote add origin "$ORIGIN"
run_env git clone -q "$ORIGIN" "$CLONE" || { fail "could not clone the scratch origin"; exit 1; }
run_env git clone -q "$ORIGIN" "$OTHER" || { fail "could not clone the scratch origin"; exit 1; }

# commit_upstream MESSAGE — commit what the case changed in $UP, push it
commit_upstream() {
  run_env git -C "$UP" add -A &&
    run_env git -C "$UP" commit -qm "$1" &&
    run_env git -C "$UP" push -q origin main
}

# pull CHECKOUT [MAKE ARGS] — make pull there; output in $W/out, status in RC
RC=0
pull() {
  local where=$1; shift
  : > "$W/go-builds"
  run_env make -C "$where" pull "$@" > "$W/out" 2>&1
  RC=$?
}
builds() { wc -l < "$W/go-builds" | tr -d ' '; }
show() { sed 's/^/    /' "$W/out"; }

# ── 1. Nothing new: nothing built or linked ──────────────────────────────────

pull "$CLONE"
if (( RC == 0 )) && [[ "$(builds)" == 0 ]] && [[ -z "$(ls -A "$H/bin")" ]]; then
  pass "nothing new: exit 0, nothing built, nothing linked"
else
  fail "nothing new: exit $RC, $(builds) build(s), ~/bin: $(find "$H/bin" -mindepth 1 -exec basename {} \; | tr '\n' ' ')"; show
fi

# ── 2. Only docs changed: nothing built or linked ────────────────────────────

mkdir -p "$UP/docs" && echo "notes" > "$UP/docs/notes.md"
commit_upstream "docs only"
pull "$CLONE"
if (( RC == 0 )) && [[ "$(builds)" == 0 ]] && [[ -z "$(ls -A "$H/bin")" ]]; then
  pass "a docs-only pull: nothing built, nothing linked"
else
  fail "a docs-only pull: exit $RC, $(builds) build(s)"; show
fi

# ── 3. tools/ changed: both TUIs rebuilt and linked ──────────────────────────

echo "// touched" >> "$UP/tools/theme/theme.go"
commit_upstream "tools"
pull "$CLONE"
if (( RC == 0 )) && [[ "$(builds)" == 2 ]] && grep -q 'go build mimac-picker' "$W/go-builds" \
   && grep -q 'go build mimac-status' "$W/go-builds" \
   && [[ "$(readlink "$H/bin/status")" == "$CLONE/bin/mimac-status" ]]; then
  pass "a tools/ pull: both TUIs rebuilt, and ~/bin/status linked to the new binary"
else
  fail "a tools/ pull: exit $RC, builds: $(tr '\n' ';' < "$W/go-builds")"; show
fi

# ── 4. tools/ changed with PULL_BUILD=0: not rebuilt, and said so ────────────

echo "// touched again" >> "$UP/tools/theme/theme.go"
commit_upstream "tools again"
pull "$CLONE" PULL_BUILD=0
if (( RC == 0 )) && [[ "$(builds)" == 0 ]] && grep -q 'rebuild skipped (PULL_BUILD=0)' "$W/out"; then
  pass "PULL_BUILD=0: the rebuild is skipped, and the output says so"
else
  fail "PULL_BUILD=0: exit $RC, $(builds) build(s)"; show
fi

# ── 5. A new script: made executable and linked into ~/bin ───────────────────

printf '#!/usr/bin/env bash\necho hello\n' > "$UP/scripts/new-tool"
commit_upstream "a new script, committed without its executable bit"
pull "$CLONE"
if (( RC == 0 )) && [[ "$(builds)" == 0 && -x "$CLONE/scripts/new-tool" ]] \
   && [[ "$(readlink "$H/bin/new-tool")" == "$CLONE/scripts/new-tool" ]]; then
  pass "a new script: made executable and linked into ~/bin, nothing built"
else
  fail "a new script: exit $RC, link: $(readlink "$H/bin/new-tool" 2>/dev/null)"; show
fi

# ── 6. A new dotfile: linked into the home ───────────────────────────────────

echo "# new" > "$UP/dotfiles/.newrc"
commit_upstream "a new dotfile"
pull "$CLONE"
if (( RC == 0 )) && [[ "$(readlink "$H/.newrc")" == "$CLONE/dotfiles/.newrc" ]]; then
  pass "a new dotfile: linked into the home"
else
  fail "a new dotfile: exit $RC, link: $(readlink "$H/.newrc" 2>/dev/null)"; show
fi

# ── 7. A checkout ~/bin does not serve: built, nothing relinked ──────────────

before=$(ls -l "$H/bin" "$H" 2>/dev/null)
echo "// touched in other" >> "$UP/tools/theme/theme.go"
printf '#!/usr/bin/env bash\necho other\n' > "$UP/scripts/other-tool"
commit_upstream "tools and a script, pulled elsewhere"
pull "$OTHER"
after=$(ls -l "$H/bin" "$H" 2>/dev/null)
if (( RC == 0 )) && [[ "$(builds)" == 2 && "$before" == "$after" ]] \
   && grep -q 'built, not linked' "$W/out" && grep -q 'not relinked' "$W/out" \
   && [[ "$(readlink "$H/bin/status")" == "$CLONE/bin/mimac-status" ]]; then
  pass "another checkout: built there, and ~/bin and the home left pointing at ~/MiMac"
else
  fail "another checkout: exit $RC, $(builds) build(s), ~/bin/status: $(readlink "$H/bin/status")"; show
fi

# ── 8. A build that fails: the other steps run, and pull exits non-zero ──────

echo "// broken" >> "$UP/tools/theme/theme.go"
printf '#!/usr/bin/env bash\necho third\n' > "$UP/scripts/third-tool"
commit_upstream "tools and a script, with a failing build"
: > "$W/go-fails"
pull "$CLONE"
rm -f "$W/go-fails"
if (( RC != 0 )) && [[ "$(readlink "$H/bin/third-tool")" == "$CLONE/scripts/third-tool" ]]; then
  pass "a failed build: make pull exits $RC, and the script is still linked"
else
  fail "a failed build: exit $RC, third-tool: $(readlink "$H/bin/third-tool" 2>/dev/null)"; show
fi

# ── 9. A pull that cannot fast-forward: non-zero, nothing built ──────────────

echo "local" > "$CLONE/local-change"
run_env git -C "$CLONE" add local-change && run_env git -C "$CLONE" commit -qm local
echo "// upstream" >> "$UP/tools/theme/theme.go"
commit_upstream "diverging"
pull "$CLONE"
if (( RC != 0 )) && [[ "$(builds)" == 0 ]]; then
  pass "a diverged checkout: make pull exits $RC and builds nothing"
else
  fail "a diverged checkout: exit $RC, $(builds) build(s)"; show
fi

# setup refreshes a sudo timestamp with `sudo -n -v`, which never prompts and
# changes nothing when there is none. Anything else is a step that should not
# have run.
calls=$(grep -vxF 'sudo -n -v' "$W/calls" || true)
if [[ -n "$calls" ]]; then
  fail "a stub that must not run was called: $(tr '\n' ';' <<< "$calls")"
else
  pass "no sudo, defaults, launchctl, osascript, chsh or xcode-select step ran"
fi

if (( fails )); then
  err "$fails make pull check(s) failed"
  exit 1
fi
ok "make pull checks passed"

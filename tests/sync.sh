#!/usr/bin/env bash
# sync.sh — prove that sync --check reports the Brewfile's drift without
# changing anything, that a failed brew read is a failure and never an empty
# install, and that --prune prunes whether or not anything new is installed.
#
# sync --check is what the status dashboard and doctor read. And --prune used
# to run after the additions, every way out of which ends the script — nothing
# new installed among them — so `make sync-clean` pruned nothing unless there
# was also something new to add, and it was picked. A run with nothing to do
# also exited 1, because its EXIT trap ended on a false test.
#
# sync runs from a scratch copy of the repository (scripts/sync, scripts/lib.sh
# and a Brewfile), with MIMAC_BREW naming a stub brew that reads what is
# installed from files the cases write, and a stub gum that picks every choice
# it is offered. No real Homebrew is read and nothing outside the scratch copy
# is written. `make test` runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

W=$(mimac_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
REPO="$W/repo" S="$W/stubs"
mkdir -p "$REPO/scripts" "$S" "$W/home"
cp "$REPO_ROOT/scripts/sync" "$REPO_ROOT/scripts/lib.sh" "$REPO/scripts/"

cat > "$REPO/Brewfile" <<'EOF'
# CLI Tools
brew "jq"
brew "wget"

# Applications
cask "firefox"
cask "gone-app"
EOF
cp "$REPO/Brewfile" "$W/Brewfile.orig"

# The stub brew: leaves, list --formula and list --cask answer from files; a
# case makes one fail by writing its name to $W/brew-fails.
cat > "$S/brew" <<EOF
#!/bin/sh
case "\$1 \${2:-}" in
  "shellenv "*) exit 0 ;;
  "leaves "*)        what=leaves ;;
  "list --formula")  what=formula ;;
  "list --cask")     what=cask ;;
  *) echo "brew stub: unexpected: \$*" >&2; exit 9 ;;
esac
grep -qx "\$what" "$W/brew-fails" 2>/dev/null && { echo "Error: stub failure" >&2; exit 1; }
cat "$W/installed-\$what" 2>/dev/null
exit 0
EOF
# The stub gum: choose prints every choice it was offered, as picking all.
cat > "$S/gum" <<'EOF'
#!/bin/sh
[ "$1" = choose ] || exit 9
shift
for a in "$@"; do
  case "$a" in --*) ;; *) printf '%s\n' "$a" ;; esac
done
EOF
chmod +x "$S/brew" "$S/gum"

installed() { # LEAVES FORMULAE CASKS, each space-separated
  : > "$W/brew-fails"
  tr ' ' '\n' <<< "$1" > "$W/installed-leaves"
  tr ' ' '\n' <<< "$2" > "$W/installed-formula"
  tr ' ' '\n' <<< "$3" > "$W/installed-cask"
}

command -v python3 >/dev/null || { fail "python3 not found"; exit 1; }
# A pseudo-terminal for the prune cases: sync hands gum /dev/tty, which a run
# with no terminal does not have. stdout and stderr arrive as one stream there.
cat > "$W/at-a-terminal.py" <<'PY2'
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
out = b""
while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace").replace("\r", ""))
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
PY2

ENV=(env -i HOME="$W/home" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$W" TERM=dumb MIMAC_BREW="$S/brew")
# sync ARGS... — stdout in $W/out, stderr in $W/err, status in RC
RC=0
sync() {
  "${ENV[@]}" "$REPO/scripts/sync" "$@" < /dev/null > "$W/out" 2> "$W/err"
  RC=$?
}
# sync_tty ARGS... — the same at a terminal; all output in $W/out, $W/err empty
sync_tty() {
  "${ENV[@]}" python3 "$W/at-a-terminal.py" "$REPO/scripts/sync" "$@" > "$W/out" 2>&1
  RC=$?
  : > "$W/err"
}
unchanged() { cmp -s "$REPO/Brewfile" "$W/Brewfile.orig"; }
show() { sed 's/^/    out: /' "$W/out"; sed 's/^/    err: /' "$W/err"; }

# ── 1. --check: the drift, tab-separated, on stdout alone ────────────────────

# ripgrep is new; wget is a dependency now, not a leaf, and still installed;
# gone-app is not installed at all.
installed "jq ripgrep" "jq ripgrep wget" "firefox zoom"
sync --check
want=$'add\tformula\tripgrep\nadd\tcask\tzoom\nprune\tcask\tgone-app'
if (( RC == 0 )) && [[ "$(cat "$W/out")" == "$want" ]] && unchanged; then
  pass "--check: adds and prunes on stdout, by sync's rules, and the Brewfile unchanged"
else
  fail "--check: exit $RC"; show
fi

# ── 2. --check when brew fails: exit 1, nothing on stdout ────────────────────

for what in leaves formula cask; do
  installed "jq" "jq wget" "firefox"
  echo "$what" > "$W/brew-fails"
  sync --check
  if (( RC == 1 )) && [[ ! -s "$W/out" ]] && grep -q 'failed' "$W/err"; then
    pass "--check with a failing brew read ($what): exit 1, nothing reported as missing"
  else
    fail "--check with a failing brew read ($what): exit $RC"; show
  fi
done

# ── 3. Nothing new, nothing stale: up to date, and exit 0 ────────────────────

installed "jq wget" "jq wget" "firefox gone-app"
sync -n
if (( RC == 0 )) && grep -q 'Brewfile is up to date' "$W/err" && unchanged; then
  pass "nothing to do: says the Brewfile is up to date, and exits 0"
else
  fail "nothing to do: exit $RC (the EXIT trap used to make this 1)"; show
fi

# ── 4. --prune with nothing new installed: the prune still runs ──────────────

installed "jq" "jq" "firefox"
sync_tty -p -n
if (( RC == 0 )) && grep -q 'Sync — Removals from Brewfile' "$W/out" \
   && grep -q '\- brew "wget"' "$W/out" && grep -q '\- cask "gone-app"' "$W/out" \
   && grep -q '\[dry run\] Brewfile not modified' "$W/out" && unchanged; then
  pass "--prune --dry-run with nothing new: offers both stale entries, changes nothing"
else
  fail "--prune --dry-run with nothing new: exit $RC"; show
fi

sync_tty -p
if (( RC == 0 )) && ! grep -q 'wget' "$REPO/Brewfile" && ! grep -q 'gone-app' "$REPO/Brewfile" \
   && grep -q '^brew "jq"' "$REPO/Brewfile" && grep -q '^cask "firefox"' "$REPO/Brewfile"; then
  pass "--prune with nothing new: removes the stale entries and keeps the rest"
else
  fail "--prune with nothing new: exit $RC, Brewfile:"; sed 's/^/    /' "$REPO/Brewfile"; show
fi
cp "$W/Brewfile.orig" "$REPO/Brewfile"

# ── 5. --prune when Homebrew reports nothing installed: refused ──────────────

installed "" "" ""
sync -p
if (( RC == 1 )) && grep -q 'refusing to prune' "$W/err" && unchanged; then
  pass "--prune with nothing installed: refused, and the Brewfile unchanged"
else
  fail "--prune with nothing installed: exit $RC"; show
fi

if (( fails )); then
  err "$fails sync check(s) failed"
  exit 1
fi
ok "sync checks passed"

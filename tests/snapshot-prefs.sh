#!/usr/bin/env bash
# snapshot-prefs.sh — prove that snapshot-prefs commits and pushes app
# preferences to mimac-prefs, license registrations included, and leaves out a
# plist that changed only in keys that change on their own; that a failed push
# is said, kept, and pushed by the next run; that a dry run writes and pushes
# nothing; that a secret stops the commit; and that pull-prefs brings it all to
# a second Mac.
#
# From 2026-08 to 2026-10 snapshot-prefs exported locally only. The push came
# back from mrk with its safeguards, onto a remote that already had history, and
# into a ~/.mimac/preferences post-install had created empty.
#
# Each case runs the real snapshot-prefs under a throwaway HOME. defaults is a
# stub first on PATH that answers read and export from fixture plists;
# MIMAC_APPS_DIR names a folder of fake apps. PREFS_REPO is a scratch bare
# repository seeded with one commit, as the real one has history.
# Nothing reaches the real HOME, the network or any preferences.
# snapshot-prefs needs bash 4, and hands itself to Homebrew's under an older
# one. `make test` runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

REAL_GIT="$(command -v git)" || { fail "git not found"; exit 1; }
command -v python3 >/dev/null || { fail "python3 not found"; exit 1; }

W=$(mimac_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
H="$W/home"             # the throwaway HOME
S="$W/stubs"            # first on PATH
D="$W/domains"          # what the stub defaults holds
A="$W/Applications"     # MIMAC_APPS_DIR
ORIGIN="$W/prefs.git"   # PREFS_REPO
P="$H/.mimac/preferences"
mkdir -p "$H" "$S" "$D" "$A"/{iTerm,Loopback,SoundSource,"Audio Hijack"}.app
: > "$W/calls"

# ── Stubs ────────────────────────────────────────────────────────────────────

cat > "$S/defaults" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$W/calls"
case "\$1" in
  read)    [ -f "$D/\$2.plist" ] ;;
  export)  [ -f "$D/\$2.plist" ] && cp "$D/\$2.plist" "\$3" ;;
  *)       exit 1 ;;
esac
EOF
chmod +x "$S/defaults"
ln -s "$REAL_GIT" "$S/git"

# fixtures SETTING TICK [SECRET] — write the four domains and Loopback's App
# Support files. SETTING is a real setting in each; TICK drives the keys that
# change on their own; SECRET puts a GitHub token in iTerm2's.
cat > "$W/fixtures.py" <<'PY'
import datetime, os, plistlib, sys
d, home, setting, tick = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
secret = len(sys.argv) > 5
t = datetime.datetime(2026, 10, 1) + datetime.timedelta(hours=tick)
reg = {"Code": "TEST-LICENSE-CODE-0001", "Name": "Test Owner"}
domains = {
    "com.googlecode.iterm2": {"Default Bookmark Guid": setting, "NoSyncTimeOfFirstLaunch": tick,
                              "iTerm Version": f"3.5.{tick}", "SULastCheckTime": t},
    "com.rogueamoeba.Loopback": {"registrationInfo": reg, "showInMenuBar": setting == "on",
                                 "NSWindow Frame Main": f"{tick} 0 800 600"},
    "com.rogueamoeba.audiohijack": {"registrationInfo": reg, "recordingFormat": setting,
                                    "homeWindowState": tick},
    "com.rogueamoeba.soundsource": {"uuid": f"u-{tick}", "outputVolume": setting},
}
if secret:
    domains["com.googlecode.iterm2"]["githubToken"] = "ghp_" + "A1b2C3d4" * 5
for name, value in domains.items():
    with open(f"{d}/{name}.plist", "wb") as f:
        plistlib.dump(value, f, fmt=plistlib.FMT_BINARY)
sup = os.path.join(home, "Library", "Application Support", "Loopback")
os.makedirs(sup, exist_ok=True)
with open(os.path.join(sup, "Devices.plist"), "wb") as f:
    plistlib.dump({"devices": [setting], "alias": f"a-{tick}".encode()}, f)
PY
fixtures() { python3 "$W/fixtures.py" "$D" "$H" "$@"; }

ENV=(env -i HOME="$H" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="${TMPDIR:-/tmp}" TERM=dumb
     PREFS_REPO="$ORIGIN" MIMAC_APPS_DIR="$A" NONINTERACTIVE=1
     GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
     GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test.invalid
     GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test.invalid)

# snap [ARGS] — snapshot-prefs. Output in $W/out, exit status in RC.
RC=0
snap() {
  "${ENV[@]}" "$REPO_ROOT/scripts/snapshot-prefs" "$@" > "$W/out" 2>&1
  RC=$?
}
has()    { grep -qF -- "$1" "$W/out"; }
show()   { sed 's/^/    /' "$W/out"; }
pushed() { "$REAL_GIT" -C "$ORIGIN" rev-list --count --all 2>/dev/null || echo 0; }
clean()  { [[ -z "$("$REAL_GIT" -C "$P" status --porcelain)" ]]; }
pushed_key() { # FILE KEY — KEY's value in the pushed copy of FILE
  "$REAL_GIT" -C "$ORIGIN" show "HEAD:$1" | python3 -c '
import plistlib, sys
v = plistlib.loads(sys.stdin.buffer.read())
for k in sys.argv[1].split("/"):
    v = v.get(k) if isinstance(v, dict) else None
print(v)' "$2"
}
fingerprint() {
  { "$REAL_GIT" -C "$P" rev-parse HEAD; "$REAL_GIT" -C "$P" status --porcelain
    (cd "$P" && find . -type f -not -path './.git/*' | LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done)
  } | cksum
}

# The remote, with history of its own, as mimac-prefs has from March 2026.
SEED="$W/seed"
"$REAL_GIT" init -q --bare "$ORIGIN"
"${ENV[@]}" git init -q -b main "$SEED"
echo "# mimac-prefs" > "$SEED/README.md"
"${ENV[@]}" git -C "$SEED" add -A
"${ENV[@]}" git -C "$SEED" commit -qm "Initial commit"
"${ENV[@]}" git -C "$SEED" push -q "$ORIGIN" main
"$REAL_GIT" -C "$ORIGIN" symbolic-ref HEAD refs/heads/main

# ── 1. The first run: an empty ~/.mimac/preferences, cloned into ────────────

mkdir -p "$P"   # as post-install leaves it
fixtures off 0
snap
if (( RC == 0 )) && has "Pushed to $ORIGIN" && [[ "$(pushed)" == 2 ]] && clean \
   && [[ -f "$P/README.md" ]] && "$REAL_GIT" -C "$ORIGIN" show HEAD:app-support/Loopback/Devices.plist >/dev/null 2>&1; then
  pass "first run: clones into the empty directory, commits the four plists and Loopback's files, and pushes on top of the remote's history"
else
  fail "first run: exit $RC, $(pushed) commit(s) on the remote"; show
fi
if [[ "$(pushed_key Loopback.plist registrationInfo/Code)" == TEST-LICENSE-CODE-0001 \
   && "$(pushed_key AudioHijack.plist registrationInfo/Name)" == "Test Owner" ]]; then
  pass "the license registrations are pushed, as chosen"
else
  fail "the license registrations were not pushed"
fi
if "$REAL_GIT" -C "$ORIGIN" show HEAD:iTerm2.plist | head -1 | grep -q '^<?xml'; then
  pass "the plists are committed as XML, so a commit diffs as text"
else
  fail "iTerm2.plist was committed in another form"
fi

# ── 2. Only keys that change on their own: no commit ────────────────────────

fixtures off 5
snap
if (( RC == 0 )) && has "No changes to push." && has "Left out, changed only in keys that change on their own" \
   && [[ "$(pushed)" == 2 ]] && clean; then
  pass "a window frame, a Sparkle time, iTerm2's NoSync keys, a uuid, an alias: left out, and no commit"
else
  fail "noise only: exit $RC, $(pushed) commit(s)"; show
fi

# ── 3. A real change: committed, and named ──────────────────────────────────

fixtures on 6
snap
if (( RC == 0 )) && has "Pushed to" && [[ "$(pushed)" == 3 ]] && has "AudioHijack.plist: recordingFormat" \
   && has "Loopback.plist: showInMenuBar" && clean; then
  pass "a real change in each plist: committed, with the keys that changed named"
else
  fail "a real change: exit $RC, $(pushed) commit(s)"; show
fi

# ── 4. A push that fails: said, kept, and pushed by the next run ────────────

mv "$ORIGIN" "$ORIGIN.away"
fixtures off 7
snap
rc_failed=$RC
said=0; has "The commit is kept in $P. The next run of snapshot-prefs pushes it." && has "mimac-prefs does not have the last commit" && said=1
mv "$ORIGIN.away" "$ORIGIN"
fixtures off 8   # nothing new but noise
snap
if (( rc_failed != 0 && said == 1 )) && (( RC == 0 )) && has "Pushing 1 commit(s) that an earlier run left unpushed" \
   && has "Pushed to" && [[ "$(pushed)" == 4 ]]; then
  pass "a failed push exits $rc_failed and says the commit is kept; the next run, finding nothing new, pushes it"
else
  fail "failed push: exit $rc_failed, said $said; next run exit $RC, $(pushed) commit(s)"; show
fi

# ── 5. A dry run writes and pushes nothing ──────────────────────────────────

before=$(fingerprint)
fixtures on 9
snap --dry-run
if (( RC == 0 )) && has "Would commit" && has "Dry run: nothing was committed or pushed." \
   && [[ "$(fingerprint)" == "$before" && "$(pushed)" == 4 ]]; then
  pass "--dry-run reports what would be committed, and leaves ~/.mimac/preferences and the remote as they were"
else
  fail "--dry-run: exit $RC"; show
fi

# ── 6. A secret stops the commit ────────────────────────────────────────────

fixtures on 10 secret
snap
if (( RC != 0 )) && has "possible secret in" && has "Aborting (NONINTERACTIVE=1)" && [[ "$(pushed)" == 4 ]] \
   && [[ "$("$REAL_GIT" -C "$P" rev-list --count HEAD)" == 4 ]]; then
  pass "a GitHub token in a plist: the scan stops the commit, and nothing is pushed"
else
  fail "a secret: exit $RC, $(pushed) commit(s)"; show
fi
"$REAL_GIT" -C "$P" reset -q --hard

# ── 7. An app with no preferences yet keeps its saved copy ──────────────────

rm "$D/com.rogueamoeba.soundsource.plist"
fixtures on 11; rm "$D/com.rogueamoeba.soundsource.plist"
snap
if (( RC == 0 )) && has "Skipping SoundSource (no preferences here yet — the saved copy is kept)" \
   && "$REAL_GIT" -C "$ORIGIN" show HEAD:SoundSource.plist >/dev/null 2>&1; then
  pass "an installed app with no preferences: skipped, and its saved copy kept"
else
  fail "no preferences: exit $RC"; show
fi

# ── 8. Mid-merge: refused before anything is exported ───────────────────────

: > "$P/.git/MERGE_HEAD"
n_calls=$(wc -l < "$W/calls")
snap
rm -f "$P/.git/MERGE_HEAD"
if (( RC == 1 )) && has "merge in progress" && [[ "$(wc -l < "$W/calls")" == "$n_calls" ]]; then
  pass "a repository stopped mid-merge: refused, and nothing exported"
else
  fail "mid-merge: exit $RC"; show
fi

# ── 9. A directory of local-only snapshots: adopted, not overwritten ────────

H2="$W/home2"; P2="$H2/.mimac/preferences"
mkdir -p "$P2"
echo "<plist>old local export</plist>" > "$P2/iTerm2.plist"
"${ENV[@]}" HOME="$H2" "$REPO_ROOT/scripts/snapshot-prefs" > "$W/out" 2>&1; RC=$?
# Its old export is replaced by this run's, which matches what is pushed; the
# files it never had come from the remote, and none is committed as removed.
if (( RC == 0 )) && has "No changes to push." && ! has "(removed)" && [[ -f "$P2/README.md" ]] \
   && [[ -f "$P2/SoundSource.plist" && -f "$P2/app-support/Loopback/Devices.plist" ]] \
   && [[ "$("$REAL_GIT" -C "$P2" rev-parse HEAD)" == "$("$REAL_GIT" -C "$ORIGIN" rev-parse HEAD)" ]]; then
  pass "a directory of local-only snapshots takes the remote's history, and deletes nothing it never had"
else
  fail "adopting a local directory: exit $RC"; show
fi

# ── 10. pull-prefs on another Mac, and a Mac that is behind ─────────────────

H3="$W/home3"; P3="$H3/.mimac/preferences"; mkdir -p "$H3"
H4="$W/home4"; mkdir -p "$H4"
pull() { "${ENV[@]}" HOME="$H3" "$REPO_ROOT/scripts/pull-prefs" > "$W/out" 2>&1; RC=$?; }
snap_on() { "${ENV[@]}" HOME="$1" "$REPO_ROOT/scripts/snapshot-prefs" > "$W/out" 2>&1; RC=$?; }

pull
if (( RC == 0 )) && cmp -s "$P3/Loopback.plist" <("$REAL_GIT" -C "$ORIGIN" show HEAD:Loopback.plist); then
  pass "pull-prefs on a new Mac: clones what was pushed, license registrations included"
else
  fail "pull-prefs clone: exit $RC"; show
fi

# A fourth Mac pushes a change, which leaves the first behind. The first's next
# snapshot fast-forwards before it exports, so its own push is one too.
fixtures off 12
snap_on "$H4"; rc4=$RC
fixtures on 13
snap_on "$H"
if (( rc4 == 0 && RC == 0 )) && has "Pushed to" && ! has "Could not fast-forward"; then
  pass "a Mac behind the remote catches up before its snapshot, and its push goes through"
else
  fail "a Mac behind: the fourth Mac exited $rc4, the first $RC"; show
fi

pull
if (( RC == 0 )) && [[ "$("$REAL_GIT" -C "$P3" rev-parse HEAD)" == "$("$REAL_GIT" -C "$ORIGIN" rev-parse HEAD)" ]]; then
  pass "pull-prefs again: fast-forwards to what was pushed since"
else
  fail "pull-prefs update: exit $RC"; show
fi

echo local > "$P3/local-only"
"${ENV[@]}" git -C "$P3" add -A && "${ENV[@]}" git -C "$P3" commit -qm local
fixtures off 14
snap_on "$H"
pull
if (( RC == 1 )) && has "Could not fast-forward" && [[ -f "$P3/local-only" ]]; then
  pass "pull-prefs with commits of its own: refuses to merge, and changes nothing"
else
  fail "pull-prefs, diverged: exit $RC"; show
fi

if (( fails )); then
  err "$fails snapshot-prefs check(s) failed"
  exit 1
fi
ok "snapshot-prefs checks passed"

#!/usr/bin/env bash
# update-verdict.sh — prove that make update ends by saying what topgrade's
# exit status means: which steps failed and that the others ran, or that the
# run stopped short, and never the first when the second is true.
#
# A run in which one cask failed to download used to end, after every other
# step had completed, on "make: *** [update] Error 1" and nothing else.
#
# topgrade is a stub first on PATH that prints the transcript TRANSCRIPT names
# and exits RC; nothing is upgraded. The real Makefile's update recipe runs it,
# under a throwaway HOME: through tee, as it does with no terminal, and on
# macOS inside a pseudo-terminal too, where it records the run with script(1).
# The transcripts use the header forms real runs of topgrade 17 print, with no
# terminal and through script (taken from mrk's recordings). Three more hold a
# byte that is not UTF-8 and run in a UTF-8 locale, where macOS's sed stops on
# one. A run interrupted with no terminal must leave no recording behind.
# Ported from mrk's tests/update-verdict.sh. `make test` runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

command -v python3 >/dev/null || { fail "python3 not found"; exit 1; }

W=$(mimac_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
S="$W/stubs" T="$W/transcripts" TMP="$W/tmp"
mkdir -p "$S" "$T" "$TMP" "$W/home" "$W/nobrew"
: > "$W/brew-calls"

cat > "$S/topgrade" <<'EOF'
#!/bin/sh
cat "$TRANSCRIPT"
[ $# -gt 0 ] && echo "topgrade args: $*"
# HOLD: a run still under way, for the cases that interrupt it.
[ -n "${HOLD:-}" ] && { echo "holding"; sleep 30; }
exit "$RC"
EOF
cat > "$W/nobrew/brew" <<EOF
#!/bin/sh
echo "\$1" >> "$W/brew-calls"
EOF
chmod +x "$S/topgrade" "$W/nobrew/brew"

# The transcripts: a run's last step, topgrade's Summary, and one clean-up
# command after it, in each of the three ways topgrade 17 draws a header:
#   plain   no terminal: "―― 20:04:24 - Summary ――", in U+2015
#   wide    a terminal, as script(1) records it: the window title on a line of
#           its own, then "── 20:04:24 - Summary ────", in U+2500, CRLF
#   narrow  a terminal that reports no width: the title and a U+2015 header on
#           one line, CRLF
header() { # FORM TITLE
  case "$1" in
    plain)  printf '―― 20:04:24 - %s ――\n' "$2" ;;
    wide)   printf '\033]0;Topgrade - %s\a\r\n── 20:04:24 - %s ──────────────────────────\r\n' "$2" "$2" ;;
    narrow) printf '\033]0;Topgrade - %s\a―― 20:04:24 - %s ――\r\n' "$2" "$2" ;;
  esac
}
text() { # FORM LINE...
  local form=$1 eol=$'\n'
  shift
  [[ "$form" == plain ]] || eol=$'\r\n'
  printf "%s$eol" "$@"
}
summary() { # FORM STATUS-OF-TLDR STATUS-OF-CASK
  header "$1" 'GitHub CLI Extensions'; text "$1" 'All extensions are up to date'
  header "$1" Summary
  text "$1" 'oh-my-zsh: OK' 'pipx: OK' "TLDR: $2" 'GitHub CLI Extensions: OK' \
    'Git Repositories: OK' 'Brew (ARM): OK' "Brew Cask (ARM): $3" 'Cleanup: OK'
  header "$1" 'Refresh zsh completions'
}
summary plain OK FAILED > "$T/one-failed"
summary wide OK $'\033[31mFAILED\033[0m' > "$T/one-failed-wide"
summary narrow OK FAILED > "$T/one-failed-narrow"
summary plain FAILED FAILED > "$T/two-failed"
summary plain OK OK > "$T/all-ok"
printf '%s\n' 'Error: Configuration error' 'unknown field nope, expected one of ...' > "$T/no-summary"
# The same runs with one byte that is not UTF-8 above the Summary: a file name
# in Latin-1, as a package manager can print one.
{ printf 'Downloading caf\xe9.dmg\n'; cat "$T/one-failed"; } > "$T/one-failed-latin1"
{ printf 'Downloading caf\xe9.dmg\r\n'; cat "$T/one-failed-wide"; } > "$T/one-failed-wide-latin1"
{ printf 'Downloading caf\xe9.dmg\n'; cat "$T/all-ok"; } > "$T/all-ok-latin1"

ENV=(env -i HOME="$W/home" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" TERM=dumb)
RC_SEEN=0
# update TRANSCRIPT RC [LOCALE] — make update with no terminal, in the C locale
# env -i leaves, or in LOCALE. Output in $W/out.
update() {
  "${ENV[@]}" ${3:+LC_ALL="$3"} TRANSCRIPT="$T/$1" RC="$2" make --no-print-directory -C "$REPO_ROOT" update < /dev/null > "$W/out" 2>&1
  RC_SEEN=$?
}
has() { grep -qF -- "$1" "$W/out"; }
show() { sed 's/^/    /' "$W/out"; }
tidy() { [[ -z "$(find "$TMP" -mindepth 1 -maxdepth 1)" ]]; }

# ── 1. One step failed ───────────────────────────────────────────────────────

update one-failed 1
verdict=$(grep -n 'Update finished' "$W/out" | cut -d: -f1)
last_step=$(grep -n 'Refresh zsh completions' "$W/out" | cut -d: -f1)
make_err=$(grep -n '\*\*\* \[update\] Error' "$W/out" | head -1 | cut -d: -f1)
if (( RC_SEEN != 0 )) && has "Update finished: every step ran. 1 of 8 failed: Brew Cask (ARM)." \
   && has "Nothing was interrupted: the other 7 succeeded, and the clean-up command after them ran." \
   && has 'which make reports next as "Error 1".' \
   && (( last_step < verdict && verdict < make_err )) && tidy; then
  pass "one failed step: named, the rest said to have run, between topgrade's last line and make's error"
else
  fail "one failed step: exit $RC_SEEN, lines $last_step/$verdict/$make_err"; show
fi

# ── 1b. The other two ways topgrade draws its headers ───────────────────────

for form in wide narrow; do
  update "one-failed-$form" 1
  if has "Update finished: every step ran. 1 of 8 failed: Brew Cask (ARM)." \
     && has "the other 7 succeeded, and the clean-up command after them ran."; then
    pass "the $form header form is read the same"
  else
    fail "the $form header form:"; show
  fi
done

# ── 1c. A byte that is not UTF-8 in the recording, in a UTF-8 locale ────────

# Every case above runs in the C locale, which env -i leaves, and a shell at a
# terminal runs in a UTF-8 one. There macOS's sed stops at the first byte that
# is not UTF-8. Where sed does not stop on such a byte, the cases still run,
# and cannot fail for this reason; the note says so.
UTF8=en_US.UTF-8
if printf 'caf\xe9\n' | "${ENV[@]}" LC_ALL="$UTF8" sed 's/x/y/' >/dev/null 2>&1; then
  logskip "a byte that is not UTF-8" "this sed reads it in $UTF8, so the next three checks cannot fail here"
fi
for t in one-failed-latin1 one-failed-wide-latin1; do
  update "$t" 1 "$UTF8"
  if has "Update finished: every step ran. 1 of 8 failed: Brew Cask (ARM)." && ! has "stopped before its summary"; then
    pass "a byte that is not UTF-8 above the Summary ($t): the Summary is still read"
  else
    fail "a byte that is not UTF-8 above the Summary ($t):"; show
  fi
done
update all-ok-latin1 0 "$UTF8"
if (( RC_SEEN == 0 )) && has "Update finished: all 8 steps succeeded."; then
  pass "the same with nothing failed: still says all 8 succeeded"
else
  fail "a byte that is not UTF-8, nothing failed: exit $RC_SEEN"; show
fi

# ── 2. Two failed ────────────────────────────────────────────────────────────

update two-failed 1
if has "every step ran. 2 of 8 failed: TLDR, Brew Cask (ARM)." && has "the other 6 succeeded"; then
  pass "two failed steps: both named, in topgrade's order"
else
  fail "two failed steps:"; show
fi

# ── 3. Nothing failed ────────────────────────────────────────────────────────

update all-ok 0
if (( RC_SEEN == 0 )) && has "Update finished: all 8 steps succeeded." && ! has "failed"; then
  pass "nothing failed: says all 8 succeeded, and exits 0"
else
  fail "nothing failed: exit $RC_SEEN"; show
fi

# ── 4. topgrade stopped before its summary: never "every step ran" ───────────

update no-summary 1
if (( RC_SEEN != 0 )) && has "topgrade stopped before its summary (exit 1): not every step ran." && ! has "Update finished"; then
  pass "no summary: says the run stopped short, and does not say every step ran"
else
  fail "no summary: exit $RC_SEEN"; show
fi

# ── 5. Every step OK, and still a failure status ─────────────────────────────

update all-ok 3
if (( RC_SEEN != 0 )) && has "topgrade exited 3, though its summary shows no failed step" && ! has "all 8 steps succeeded"; then
  pass "a failure after the summary: reported as that, not as success"
else
  fail "a failure after the summary: exit $RC_SEEN"; show
fi

# ── 6. No topgrade: brew update and upgrade, and no verdict ──────────────────

env -i HOME="$W/home" PATH="$W/nobrew:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" TERM=dumb \
  make --no-print-directory -C "$REPO_ROOT" update < /dev/null > "$W/out" 2>&1; rc=$?
if (( rc == 0 )) && [[ "$(tr '\n' ' ' < "$W/brew-calls")" == "update upgrade " ]] && ! has "Update finished"; then
  pass "without topgrade: brew update, then brew upgrade"
else
  fail "without topgrade: exit $rc, brew calls: $(tr '\n' ' ' < "$W/brew-calls")"; show
fi

# ── 7. At a terminal: recorded through script(1), the status kept ────────────

if [[ "$(uname -s)" == Darwin ]]; then
  cat > "$W/at-a-terminal.py" <<'PY'
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
PY
  "${ENV[@]}" TRANSCRIPT="$T/one-failed-wide" RC=1 python3 "$W/at-a-terminal.py" \
    make --no-print-directory -C "$REPO_ROOT" update > "$W/out" 2>&1; rc=$?
  if (( rc != 0 )) && has "Update finished: every step ran. 1 of 8 failed: Brew Cask (ARM)." && tidy; then
    pass "at a terminal: the run is recorded through script, read, and its recording removed"
  else
    fail "at a terminal: exit $rc, TMPDIR: $(find "$TMP" -mindepth 1 | tr '\n' ' ')"; show
  fi
fi

# ── 8. Interrupted away from a terminal: the recording is removed ────────────

# The command in a session of its own, with no terminal. When the stub says
# "holding", the whole process group gets the signal, as Ctrl-C or a closed
# window sends it.
cat > "$W/interrupt.py" <<'PY'
import os, signal, subprocess, sys
sig, argv = getattr(signal, "SIG" + sys.argv[1]), sys.argv[2:]
p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT, start_new_session=True)
out = b""
for line in iter(p.stdout.readline, b""):
    out += line
    if b"holding" in line:
        os.killpg(p.pid, sig)
        break
out += p.stdout.read()
rc = p.wait()
sys.stdout.write(out.decode("utf-8", "replace"))
print("ended: %d" % rc)
PY
# await_tidy — the trap runs as the shell ends, which can be a moment after
# the command the driver waits for has gone
await_tidy() {
  local i
  for (( i = 0; i < 30; i++ )); do
    tidy && return 0
    sleep 0.1
  done
  return 1
}
for sig in INT TERM HUP; do
  "${ENV[@]}" HOLD=1 TRANSCRIPT="$T/one-failed" RC=1 python3 "$W/interrupt.py" "$sig" \
    make --no-print-directory -C "$REPO_ROOT" update > "$W/out" 2>&1
  if has "holding" && ! has "ended: 0" && ! has "Update finished" && await_tidy; then
    pass "SIG$sig with no terminal: the run ends, and its recording is removed"
  else
    fail "SIG$sig with no terminal: left in TMPDIR: $(find "$TMP" -mindepth 1 | tr '\n' ' ')"; show
    rm -f "$TMP"/*
  fi
done

# The caller's own traps: one set before run_topgrade still runs when the
# signal comes during it, and after a run that ends by itself the traps are as
# they were before it. Compared before and after, not with a fixed list: a
# signal ignored on entry, as INT is in a job started with &, is one bash 5
# lists and bash 3.2 does not. Under /bin/bash and the bash running this.
BASHES=(/bin/bash)
[[ "$BASH" -ef /bin/bash ]] || BASHES+=("$BASH")
for b in "${BASHES[@]}"; do
  # shellcheck disable=SC2016  # expanded by the bash under test
  "${ENV[@]}" HOLD=1 TRANSCRIPT="$T/all-ok" RC=0 python3 "$W/interrupt.py" TERM \
    "$b" -c '. "$1"; trap "echo the caller trap ran; exit 7" TERM; run_topgrade; echo not reached' bash "$REPO_ROOT/scripts/lib.sh" \
    > "$W/out" 2>&1
  # shellcheck disable=SC2016
  after=$("${ENV[@]}" TRANSCRIPT="$T/all-ok" RC=0 "$b" -c \
    '. "$1"; trap "echo mine" TERM; before=$(trap -p INT TERM HUP); run_topgrade >/dev/null 2>&1
     [[ "$(trap -p INT TERM HUP)" == "$before" ]] && trap -p TERM' bash "$REPO_ROOT/scripts/lib.sh" < /dev/null 2>&1)
  if has "the caller trap ran" && has "ended: 7" && ! has "not reached" && await_tidy \
     && [[ "$after" == "trap -- 'echo mine' SIGTERM" ]]; then
    # shellcheck disable=SC2016
    pass "the caller's trap ($("$b" -c 'echo "${BASH_VERSION%%(*}"')): it runs on a signal during the run, and the traps are as they were after one"
  else
    fail "the caller's trap under $b: after a run the traps had changed, or TERM's was: '$after'"; show
    rm -f "$TMP"/*
  fi
done

# ── 9. One stream: the verdict is on stderr, whichever library came last ─────

# In the clean environment of the other cases: a MAKELEVEL inherited from
# `make test` would add make's clause to the last line.
# shellcheck disable=SC2016  # expanded by the inner bash
"${ENV[@]}" "$BASH" -c '. "$1/scripts/lib.sh"; . "$1/bin/lib/common.sh"; topgrade_verdict 1 "$2"' bash "$REPO_ROOT" "$T/one-failed" \
  > "$W/verdict-out" 2> "$W/out"
if [[ ! -s "$W/verdict-out" ]] && [[ "$(wc -l < "$W/out" | tr -d ' ')" == 3 ]] \
   && has "  ⚠ Update finished: every step ran. 1 of 8 failed: Brew Cask (ARM)." \
   && has "    Nothing was interrupted: the other 7 succeeded" && has "    The exit status is 1 for the failed step alone."; then
  pass "with common.sh sourced too: the same three lines, all on stderr, none on stdout"
else
  fail "with common.sh sourced too: stdout holds: $(tr '\n' '|' < "$W/verdict-out")"; show
fi

if (( fails )); then
  err "$fails update verdict check(s) failed"
  exit 1
fi
ok "update verdict checks passed"

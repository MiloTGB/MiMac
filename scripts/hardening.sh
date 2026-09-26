#!/usr/bin/env bash
set -euo pipefail

# MiMac hardening — opt-in security tweaks with rollback (inspired by Strap)
#
# Every change is recorded in ~/.mimac/hardening-rollback.sh before it is made,
# first run wins: a re-run never records MiMac's own settings as the originals.

# Resolve symlinks
_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
SCRIPT_DIR="$(cd "$(dirname "$_self")" && pwd)"

# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ROLL_DIR="$HOME/.mimac"
ROLL="$ROLL_DIR/hardening-rollback.sh"

# Create rollback directory and script with error checking
if ! mkdir -p "$ROLL_DIR"; then
  echo "Error: Failed to create rollback directory: $ROLL_DIR" >&2
  exit 1
fi

if [[ ! -f "$ROLL" ]]; then
  if ! printf '#!/usr/bin/env bash\n' > "$ROLL" || ! chmod +x "$ROLL"; then
    echo "Error: Failed to initialize rollback script: $ROLL" >&2
    exit 1
  fi
fi

rollback(){ grep -qFx "$*" "$ROLL" 2>/dev/null && return 0; echo "$*" >> "$ROLL"; }

have_sudo=0
if command -v sudo >/dev/null 2>&1; then
  have_sudo=1
  # Ask for the password once, up front, not part-way through.
  if [[ -t 0 ]] && ! sudo -n true 2>/dev/null; then
    log "Hardening needs administrator privileges"
    sudo -v || have_sudo=0
  fi
fi

###############################################################################
# 1) Touch ID for sudo (pam_tid)                                              #
###############################################################################
#
# macOS 14 and later include /etc/pam.d/sudo_local from /etc/pam.d/sudo, and
# Apple's template calls it the "local config file which survives system
# update". This used to edit /etc/pam.d/sudo itself — the file macOS updates
# replace — so Touch ID quietly switched off after every update. The line now
# goes in sudo_local wherever sudo includes it; /etc/pam.d/sudo is edited only
# on a macOS too old for the include. "Already on" means an uncommented line:
# the template carries a commented one.

PAM_SUDO=/etc/pam.d/sudo
PAM_LOCAL=/etc/pam.d/sudo_local
TID_LINE='auth       sufficient     pam_tid.so'
tid_on(){ grep -qE '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' "$1" 2>/dev/null; }

if (( ! have_sudo )); then
  log "Skipping Touch ID (sudo unavailable)"
elif tid_on "$PAM_SUDO" || tid_on "$PAM_LOCAL"; then
  log "Touch ID for sudo already enabled"
else
  pam_target=$PAM_SUDO
  if grep -qE '^[[:space:]]*auth[[:space:]]+include[[:space:]]+sudo_local' "$PAM_SUDO" 2>/dev/null; then
    pam_target=$PAM_LOCAL
  fi
  log "Enabling Touch ID for sudo ($pam_target)"
  tmpfile="$(mimac_mktemp)"
  pam_ready=1
  if [[ -e "$pam_target" ]]; then
    # An existing file may hold other lines: prepend, keep the rest, and keep
    # the original to put back.
    { echo "$TID_LINE"; cat "$pam_target"; } > "$tmpfile"
    if sudo cp "$pam_target" "$pam_target.backup.mimac" 2>/dev/null; then
      rollback "sudo mv $pam_target.backup.mimac $pam_target"
    else
      warn "Failed to back up $pam_target — leaving Touch ID alone"
      pam_ready=0
    fi
  else
    echo "$TID_LINE" > "$tmpfile"
    rollback "sudo rm -f $pam_target"
  fi
  # Editing sudo's own file: refuse a result that lost the account modules.
  if (( pam_ready )) && [[ "$pam_target" == "$PAM_SUDO" ]] && \
     ! grep -qE 'pam_smartcard\.so|pam_opendirectory\.so' "$tmpfile"; then
    warn "Generated PAM config appears invalid — leaving $pam_target alone"
    pam_ready=0
  fi
  if (( pam_ready )); then
    # Written beside the target and renamed over it, so a failure part-way
    # can never leave a truncated PAM file.
    if sudo cp "$tmpfile" "$pam_target.mimac-new" 2>/dev/null &&
       sudo chmod 444 "$pam_target.mimac-new" 2>/dev/null &&
       sudo mv "$pam_target.mimac-new" "$pam_target" 2>/dev/null; then
      log "Touch ID for sudo enabled"
    else
      sudo rm -f "$pam_target.mimac-new" 2>/dev/null || true
      warn "Failed to write $pam_target — it is unchanged"
    fi
  fi
  rm -f "$tmpfile"
fi

###############################################################################
# 2) Require password immediately after sleep/screensaver                     #
###############################################################################
#
# Through sysadminctl, which is what current macOS enforces. This used to write
# com.apple.screensaver askForPassword/askForPasswordDelay — keys macOS no
# longer reads, so the step reported success and changed nothing. Setting it
# needs the login password, which sysadminctl asks for itself, so it runs only
# at a terminal; otherwise this prints the command.

lock_status="$(sysadminctl -screenLock status 2>&1 || true)"
lock_prev=""
if [[ "$lock_status" == *immediate* ]]; then
  lock_prev=immediate
elif [[ "$lock_status" =~ delay\ is\ ([0-9]+)\ seconds ]]; then
  lock_prev="${BASH_REMATCH[1]}"
elif [[ "$lock_status" =~ [Oo]ff|disabled ]]; then
  lock_prev=off
fi

if [[ "$lock_prev" == immediate ]]; then
  log "A password is already required immediately on wake"
elif [[ -z "$lock_prev" ]]; then
  warn "Could not read the screen-lock delay — leaving it alone"
elif [[ ! -t 0 ]]; then
  warn "A password is not required immediately on wake. To require it, run:"
  warn "  sysadminctl -screenLock immediate -password -"
else
  log "Requiring a password immediately on wake (sysadminctl asks for your login password)"
  grep -qF "sysadminctl -screenLock " "$ROLL" 2>/dev/null || \
    rollback "sysadminctl -screenLock $lock_prev -password -"
  sysadminctl -screenLock immediate -password - || warn "sysadminctl did not change the screen-lock delay"
fi

###############################################################################
# 3) Firewall (global + stealth)                                              #
###############################################################################
#
# `--getglobalstate` prints "Firewall is enabled. (State = 1)". The old parse
# took the third word, so the rollback recorded "--setglobalstate enabled." —
# not a value socketfilterfw accepts — and without sudo. A state that cannot
# be read gets no rollback line: inventing "it was off" would let the rollback
# disable a firewall that was on.

FW=/usr/libexec/ApplicationFirewall/socketfilterfw
if (( ! have_sudo )); then
  log "Skipping firewall changes (sudo unavailable)"
else
  if fw_state="$("$FW" --getglobalstate 2>/dev/null)"; then
    case "$fw_state" in *enabled*) fw_prev=on ;; *) fw_prev=off ;; esac
    grep -qF -- "--setglobalstate" "$ROLL" 2>/dev/null || \
      rollback "sudo $FW --setglobalstate $fw_prev"
  else
    fw_prev=unknown
    warn "Could not read the firewall state — enabling it without a rollback line"
  fi
  if fw_stealth="$("$FW" --getstealthmode 2>/dev/null)"; then
    case "$fw_stealth" in *" is on"*) st_prev=on ;; *) st_prev=off ;; esac
    grep -qF -- "--setstealthmode" "$ROLL" 2>/dev/null || \
      rollback "sudo $FW --setstealthmode $st_prev"
  else
    st_prev=unknown
  fi

  if [[ "$fw_prev" == on ]]; then
    log "Firewall already enabled"
  elif sudo "$FW" --setglobalstate on >/dev/null 2>&1; then
    log "Firewall enabled"
  else
    warn "Failed to enable firewall"
  fi

  if [[ "$st_prev" == on ]]; then
    log "Firewall stealth mode already on"
  elif sudo "$FW" --setstealthmode on >/dev/null 2>&1; then
    log "Firewall stealth mode enabled"
  else
    warn "Failed to enable firewall stealth mode"
  fi
fi

log "Hardening done. Rollback: $ROLL"

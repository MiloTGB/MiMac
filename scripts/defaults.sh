#!/usr/bin/env bash
set -euo pipefail

# MiMac defaults - apply macOS defaults and generate a rollback script
#
# Usage:
#   defaults.sh                 # apply all defaults (except trackpad)
#   defaults.sh --with-trackpad # also apply trackpad gesture settings

ROLL_DIR="$HOME/.mimac"
ROLLBACK="$ROLL_DIR/defaults-rollback.sh"

WITH_TRACKPAD=false
for arg in "$@"; do
  case "$arg" in
    --with-trackpad) WITH_TRACKPAD=true ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Create rollback directory and script with error checking
if ! mkdir -p "$ROLL_DIR"; then
  echo "Error: Failed to create rollback directory: $ROLL_DIR" >&2
  exit 1
fi

# Initialize rollback script if it doesn't exist; preserve existing content
# (setup may have already written login-window-message rollback entries)
if [[ ! -f "$ROLLBACK" ]]; then
  if ! printf '#!/usr/bin/env bash\n' > "$ROLLBACK" || ! chmod +x "$ROLLBACK"; then
    echo "Error: Failed to initialize rollback script: $ROLLBACK" >&2
    exit 1
  fi
fi

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

# Append a line once — re-runs must not stack duplicates.
backup_line(){ grep -qFx "$1" "$ROLLBACK" 2>/dev/null && return 0; echo "$1" >> "$ROLLBACK"; }

# Helper: capture current value (if any) and append the inverse to rollback
# Usage: write_default <domain> <key> <type> <value>
write_default(){
  local domain="$1" key="$2" type="$3" value="$4"
  local current esc_domain esc_key
  esc_domain=$(printf '%q' "$domain")
  esc_key=$(printf '%q' "$key")

  # First run wins. Without this, a second run recorded MiMac's own values as
  # the "originals" below the real ones, and since the rollback runs top to
  # bottom it ended on MiMac's values — undoing nothing. Both line forms are
  # checked; the trailing space stops one key matching a longer one it prefixes.
  if ! grep -qF "defaults write $esc_domain $esc_key " "$ROLLBACK" 2>/dev/null &&
     ! grep -qF "defaults delete $esc_domain $esc_key " "$ROLLBACK" 2>/dev/null; then
    if current=$(defaults read "$domain" "$key" 2>/dev/null); then
      # read-type, not the value's shape: `defaults read` prints a boolean as
      # 1 or 0, so guessing from the value recorded every boolean as -int.
      case "$(defaults read-type "$domain" "$key" 2>/dev/null | awk '{print $NF}')" in
        boolean)
          if [[ "$current" == 1 ]]; then current=true; else current=false; fi
          backup_line "defaults write $esc_domain $esc_key -bool $current" ;;
        integer) backup_line "defaults write $esc_domain $esc_key -int $current" ;;
        float)   backup_line "defaults write $esc_domain $esc_key -float $current" ;;
        *)       backup_line "defaults write $esc_domain $esc_key -string $(printf '%q' "$current")" ;;
      esac
    else
      backup_line "defaults delete $esc_domain $esc_key >/dev/null 2>&1 || true"
    fi
  fi
  case "$type" in
    bool)   defaults write "$domain" "$key" -bool "$value" || return 1 ;;
    int)    defaults write "$domain" "$key" -int "$value" || return 1 ;;
    float)  defaults write "$domain" "$key" -float "$value" || return 1 ;;
    string) defaults write "$domain" "$key" -string "$value" || return 1 ;;
    *) log "Unknown type: $type" >&2; return 1 ;;
  esac
}

log "Applying macOS defaults..."

# Track failures
failed=0

###############################################################################
# General UI / UX                                                             #
###############################################################################

# Dark mode
write_default NSGlobalDomain AppleInterfaceStyle string Dark || failed=$((failed + 1))
# Always show scrollbars
# Why: overlay scrollbars appear/disappear and shift layout; always-visible scrollbars provide a consistent click target
write_default NSGlobalDomain AppleShowScrollBars string Always || failed=$((failed + 1))
# Show all filename extensions
# Why: hidden extensions can make malicious files appear harmless (e.g. "invoice.pdf.app" shows as "invoice.pdf")
write_default NSGlobalDomain AppleShowAllExtensions bool true || failed=$((failed + 1))
# Disable window open/close animations
# Why: eliminates visual delay when rapidly switching or tiling windows
write_default NSGlobalDomain NSAutomaticWindowAnimationsEnabled bool false || failed=$((failed + 1))
# Near-instant window resize animation
# Why: eliminates the perceivable lag when resizing windows
write_default NSGlobalDomain NSWindowResizeTime float 0.001 || failed=$((failed + 1))
# Don't restore windows on relaunch
# Why: stale windows from a previous session can cause confusion after crashes or updates
write_default NSGlobalDomain NSQuitAlwaysKeepsWindows bool false || failed=$((failed + 1))
# Expand save panel by default
# Why: collapsed panel hides the destination path, making accidental misplacement easy
write_default NSGlobalDomain NSNavPanelExpandedStateForSaveMode bool true || failed=$((failed + 1))
write_default NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 bool true || failed=$((failed + 1))
# Expand print dialog by default
write_default NSGlobalDomain PMPrintingExpandedStateForPrint bool true || failed=$((failed + 1))
write_default NSGlobalDomain PMPrintingExpandedStateForPrint2 bool true || failed=$((failed + 1))
# Save to disk (not iCloud) by default
# Why: avoids accidental sync of sensitive files to iCloud without explicit intent
write_default NSGlobalDomain NSDocumentSaveNewDocumentsToCloud bool false || failed=$((failed + 1))
# Instant Quick Look animation
write_default NSGlobalDomain QLPanelAnimationDuration float 0 || failed=$((failed + 1))
# Custom highlight color (green)
write_default NSGlobalDomain AppleHighlightColor string "0.7647 0.9765 0.5686 Green" || failed=$((failed + 1))

###############################################################################
# Sound                                                                       #
###############################################################################

# Mute system alert sound
write_default NSGlobalDomain com.apple.sound.beep.volume float 0 || failed=$((failed + 1))
# Disable UI sound effects
write_default NSGlobalDomain com.apple.sound.uiaudio.enabled bool false || failed=$((failed + 1))

###############################################################################
# Keyboard & input                                                            #
###############################################################################

# Key repeat speed (lower is faster)
write_default NSGlobalDomain KeyRepeat int 2 || failed=$((failed + 1))
write_default NSGlobalDomain InitialKeyRepeat int 15 || failed=$((failed + 1))
# Key repeat instead of accent character picker
# Why: the accent picker interrupts keyboard-driven navigation and editing in code and terminal
write_default NSGlobalDomain ApplePressAndHoldEnabled bool false || failed=$((failed + 1))
# Full keyboard access (Tab through all UI controls)
# Why: allows Tab to cycle through buttons, radio buttons, etc. without reaching for the mouse
write_default NSGlobalDomain AppleKeyboardUIMode int 2 || failed=$((failed + 1))
# Disable auto-capitalization
# Why: breaks commands, code, and domain names entered in text fields outside terminals
write_default NSGlobalDomain NSAutomaticCapitalizationEnabled bool false || failed=$((failed + 1))
# Disable smart dashes
# Why: converts "--" to an em dash, breaking markdown, CLI flags, and code
write_default NSGlobalDomain NSAutomaticDashSubstitutionEnabled bool false || failed=$((failed + 1))
# Disable double-space period shortcut
# Why: interferes with intentional spacing in code, prose, and command entry
write_default NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled bool false || failed=$((failed + 1))
# Disable smart quotes
# Why: curly quotes break shell scripts, JSON, code snippets, and command-line arguments
write_default NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled bool false || failed=$((failed + 1))
# Disable autocorrect
# Why: mangles technical terms, hostnames, variable names, and other domain-specific vocabulary
write_default NSGlobalDomain NSAutomaticSpellingCorrectionEnabled bool false || failed=$((failed + 1))

###############################################################################
# Dock                                                                        #
###############################################################################

# Dock on bottom (matches current system preference)
write_default com.apple.dock orientation string bottom || failed=$((failed + 1))
# Icon size 36 pixels
write_default com.apple.dock tilesize int 36 || failed=$((failed + 1))
# Scale effect for minimize
# Why: faster and less distracting than genie effect
write_default com.apple.dock mineffect string scale || failed=$((failed + 1))
# Minimize windows into application icon
# Why: keeps dock organized by grouping windows with their parent app
write_default com.apple.dock minimize-to-application bool true || failed=$((failed + 1))
# Disable dock icon bouncing
# Why: reduces visual noise and distractions when apps request attention
write_default com.apple.dock no-bouncing bool true || failed=$((failed + 1))
# Don't show recent applications
# Why: recents section clutters the dock and duplicates functionality of Cmd+Tab
write_default com.apple.dock show-recents bool false || failed=$((failed + 1))
# No delay before dock shows (if autohide enabled)
# Why: instant dock appearance feels more responsive when autohide is enabled
write_default com.apple.dock autohide-delay float 0 || failed=$((failed + 1))

###############################################################################
# Finder                                                                      #
###############################################################################

# Disable all Finder animations
# Why: speeds up navigation and window operations in Finder
write_default com.apple.finder DisableAllAnimations bool true || failed=$((failed + 1))

###############################################################################
# Screenshots                                                                 #
###############################################################################

# Disable window shadow in screenshots
# Why: cleaner screenshots without shadow artifacts, better for documentation
write_default com.apple.screencapture disable-shadow bool true || failed=$((failed + 1))
# Don't show floating thumbnail after capture
# Why: thumbnail can obstruct the next screenshot or interfere with rapid captures
write_default com.apple.screencapture show-thumbnail bool false || failed=$((failed + 1))
# Don't include date in screenshot filename
# Why: keeps filenames shorter and more manageable
write_default com.apple.screencapture include-date bool false || failed=$((failed + 1))
# Save screenshots to Desktop
write_default com.apple.screencapture location string "$HOME/Desktop" || failed=$((failed + 1))

###############################################################################
# Desktop Services                                                            #
###############################################################################

# Don't create .DS_Store files on network volumes
# Why: prevents pollution of shared network drives with macOS metadata
write_default com.apple.desktopservices DSDontWriteNetworkStores bool true || failed=$((failed + 1))
# Don't create .DS_Store files on USB volumes
# Why: keeps USB drives clean when sharing with non-Mac systems
write_default com.apple.desktopservices DSDontWriteUSBStores bool true || failed=$((failed + 1))

###############################################################################
# Disk images                                                                 #
###############################################################################

# Skip DMG verification
# Why: DMG verification is slow and rarely catches issues on modern downloads with checksums
write_default com.apple.frameworks.diskimages skip-verify bool true || failed=$((failed + 1))
write_default com.apple.frameworks.diskimages skip-verify-locked bool true || failed=$((failed + 1))
write_default com.apple.frameworks.diskimages skip-verify-remote bool true || failed=$((failed + 1))

###############################################################################
# Time Machine                                                                #
###############################################################################

# Don't prompt to use new disks for backup
# Why: prevents annoying prompts when connecting external drives not intended for backup
write_default com.apple.TimeMachine DoNotOfferNewDisksForBackup bool true || failed=$((failed + 1))

###############################################################################
# Software Update & App Store                                                 #
###############################################################################

# Auto-check for updates
# Why: ensures system stays current with security patches
write_default com.apple.SoftwareUpdate AutomaticCheckEnabled bool true || failed=$((failed + 1))
# Auto-download updates
# Why: downloads in background so updates are ready when convenient
write_default com.apple.SoftwareUpdate AutomaticDownload bool true || failed=$((failed + 1))
# Install system data files automatically
# Why: keeps system definitions current (malware signatures, timezone data)
write_default com.apple.SoftwareUpdate ConfigDataInstall bool true || failed=$((failed + 1))
# Install security updates automatically
# Why: critical security patches should be applied ASAP to prevent exploitation
write_default com.apple.SoftwareUpdate CriticalUpdateInstall bool true || failed=$((failed + 1))
# Auto-update App Store apps
# Why: keeps apps current with bug fixes and security patches
write_default com.apple.commerce AutoUpdate bool true || failed=$((failed + 1))

###############################################################################
# Activity Monitor                                                            #
###############################################################################

# Show CPU usage in dock icon
# Why: provides at-a-glance CPU monitoring without opening the app
write_default com.apple.ActivityMonitor IconType int 2 || failed=$((failed + 1))
# Show all processes
# Why: shows system processes for complete system visibility
write_default com.apple.ActivityMonitor ShowCategory int 100 || failed=$((failed + 1))
# Sort by CPU usage
# Why: immediately highlights performance bottlenecks
write_default com.apple.ActivityMonitor SortColumn string CPUUsage || failed=$((failed + 1))
# Sort descending
# Why: shows highest CPU consumers at the top
write_default com.apple.ActivityMonitor SortDirection int 0 || failed=$((failed + 1))
# Update every 1 second
# Why: provides real-time monitoring for performance troubleshooting
write_default com.apple.ActivityMonitor UpdatePeriod int 1 || failed=$((failed + 1))

###############################################################################
# TextEdit                                                                    #
###############################################################################

# Default to plain text
# Why: plain text is safer for code, configs, and technical content
write_default com.apple.TextEdit RichText int 0 || failed=$((failed + 1))

###############################################################################
# Terminal.app                                                                #
###############################################################################

# Default profile: Pro
write_default com.apple.Terminal "Default Window Settings" string Pro || failed=$((failed + 1))
write_default com.apple.Terminal "Startup Window Settings" string Pro || failed=$((failed + 1))
# Focus follows mouse
# Why: allows working across multiple terminal windows without clicking
write_default com.apple.Terminal FocusFollowsMouse bool true || failed=$((failed + 1))
# Secure keyboard entry
# Why: prevents other apps from capturing keystrokes (passwords, commands)
write_default com.apple.Terminal SecureKeyboardEntry bool true || failed=$((failed + 1))
# Don't show line marks
# Why: reduces visual clutter in terminal output
write_default com.apple.Terminal ShowLineMarks bool false || failed=$((failed + 1))

###############################################################################
# Menu bar clock                                                              #
###############################################################################

# Digital clock
write_default com.apple.menuextra.clock IsAnalog bool false || failed=$((failed + 1))
# Show AM/PM
# Why: 12-hour format with AM/PM is clearer for many users
write_default com.apple.menuextra.clock ShowAMPM bool true || failed=$((failed + 1))
# Show day of week
# Why: helps with date awareness without taking much space
write_default com.apple.menuextra.clock ShowDayOfWeek bool true || failed=$((failed + 1))
# Don't show date
# Why: day of week is more useful than date for daily context
write_default com.apple.menuextra.clock ShowDate int 0 || failed=$((failed + 1))

###############################################################################
# Trackpad (opt-in: --with-trackpad)                                          #
###############################################################################

if $WITH_TRACKPAD; then
  log "Applying trackpad defaults..."

  for domain in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    # Disable tap-to-click
    # Why: prevents accidental clicks when resting fingers on trackpad
    write_default "$domain" Clicking bool false || failed=$((failed + 1))
    # Suppress Force Touch
    # Why: prevents accidental Force Touch activations
    write_default "$domain" ForceSuppressed bool true || failed=$((failed + 1))
    # Bottom-right corner secondary click
    # Why: provides physical right-click location for precision
    write_default "$domain" TrackpadCornerSecondaryClick int 2 || failed=$((failed + 1))
    # Disable all multi-finger gestures
    # Why: prevents accidental gesture triggers during normal use
    write_default "$domain" TrackpadFiveFingerPinchGesture int 0 || failed=$((failed + 1))
    write_default "$domain" TrackpadFourFingerHorizSwipeGesture int 0 || failed=$((failed + 1))
    write_default "$domain" TrackpadFourFingerPinchGesture int 0 || failed=$((failed + 1))
    write_default "$domain" TrackpadFourFingerVertSwipeGesture int 0 || failed=$((failed + 1))
    write_default "$domain" TrackpadPinch bool false || failed=$((failed + 1))
    write_default "$domain" TrackpadRightClick bool false || failed=$((failed + 1))
    write_default "$domain" TrackpadRotate bool false || failed=$((failed + 1))
    write_default "$domain" TrackpadThreeFingerDrag bool false || failed=$((failed + 1))
    write_default "$domain" TrackpadThreeFingerHorizSwipeGesture int 0 || failed=$((failed + 1))
    write_default "$domain" TrackpadThreeFingerTapGesture int 0 || failed=$((failed + 1))
    write_default "$domain" TrackpadThreeFingerVertSwipeGesture int 0 || failed=$((failed + 1))
    write_default "$domain" TrackpadTwoFingerDoubleTapGesture int 0 || failed=$((failed + 1))
    write_default "$domain" TrackpadTwoFingerFromRightEdgeSwipeGesture int 0 || failed=$((failed + 1))
  done
fi

###############################################################################
# Finish up                                                                   #
###############################################################################

if (( failed > 0 )); then
  log "Warning: $failed default(s) failed to apply"
fi

log "Writing rollback helper to $ROLLBACK"
backup_line "killall Finder >/dev/null 2>&1 || true"
backup_line "killall Dock >/dev/null 2>&1 || true"
backup_line "killall SystemUIServer >/dev/null 2>&1 || true"

# Apply immediate effects
killall Finder >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true
killall SystemUIServer >/dev/null 2>&1 || true

log "Defaults applied. You can revert with: $ROLLBACK"

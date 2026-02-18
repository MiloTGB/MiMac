#!/usr/bin/env bash
set -euo pipefail

# Safari power-user defaults
#
# Applied by MiMac post-install. No rollback — re-run MiMac defaults
# or reset Safari preferences manually to revert.
#
# On macOS Sonoma+, Safari preferences live in a sandboxed container.
# We write to the container path directly.

log(){ printf "[safari-defaults] %s\n" "$*"; }

SAFARI_CONTAINER="$HOME/Library/Containers/com.apple.Safari/Data/Library/Preferences/com.apple.Safari"
SAFARI_DOMAIN="com.apple.Safari"

# Use container path if it exists, otherwise fall back to standard domain
write_safari() {
  if [[ -d "$HOME/Library/Containers/com.apple.Safari" ]]; then
    defaults write "$SAFARI_CONTAINER" "$@"
  else
    defaults write "$SAFARI_DOMAIN" "$@"
  fi
}

failed=0

###############################################################################
# General                                                                     #
###############################################################################

# Show full URL in Smart Search Field
write_safari ShowFullURLInSmartSearchField -bool true || ((failed++))

# Show favorites bar
write_safari ShowFavoritesBar-v2 -bool true || ((failed++))

# Show status bar
write_safari ShowOverlayStatusBar -bool true || ((failed++))

###############################################################################
# Privacy & Security                                                          #
###############################################################################

# Send Do Not Track header
write_safari SendDoNotTrackHTTPHeader -bool true || ((failed++))

# Prevent cross-site tracking
write_safari BlockStoragePolicy -int 2 || ((failed++))

# Don't auto-open "safe" downloads
write_safari AutoOpenSafeDownloads -bool false || ((failed++))

# Disable AutoFill for credit cards
write_safari AutoFillCreditCardData -bool false || ((failed++))

###############################################################################
# Developer                                                                   #
###############################################################################

# Enable Develop menu
write_safari IncludeDevelopMenu -bool true || ((failed++))

# Enable developer extras (Web Inspector in contextual menu)
write_safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true || ((failed++))
write_safari "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" -bool true || ((failed++))

###############################################################################
# Extensions                                                                  #
###############################################################################

# Enable extensions
write_safari ExtensionsEnabled -bool true || ((failed++))

# Auto-update extensions
write_safari InstallExtensionUpdatesAutomatically -bool true || ((failed++))

###############################################################################
# Summary                                                                     #
###############################################################################

if (( failed > 0 )); then
  log "Warning: $failed default(s) failed to apply"
else
  log "All defaults applied"
fi

log "Restart Safari for changes to take effect"

#!/usr/bin/env bash
set -euo pipefail

# Safari power-user defaults
#
# Applied by MiMac post-install.
#
# NOTE: macOS Sequoia (15+) blocks defaults write to Safari's sandboxed
# container. These settings must be configured manually in Safari preferences
# on Sequoia and later. This script will detect the restriction and skip
# gracefully.

log(){ printf "[safari-defaults] %s\n" "$*"; }

# Test if we can write to Safari's preferences
can_write_safari() {
  # Try writing a harmless test key
  if defaults write com.apple.Safari _MiMacTest -bool true 2>/dev/null; then
    defaults delete com.apple.Safari _MiMacTest 2>/dev/null || true
    return 0
  fi
  return 1
}

if ! can_write_safari; then
  log "Safari preferences are sandboxed on this macOS version."
  log "Please configure these settings manually in Safari → Settings:"
  log "  • General: Show full URL in Smart Search Field"
  log "  • General: Show Favorites Bar, Show Status Bar"
  log "  • Privacy: Prevent cross-site tracking, Send DNT header"
  log "  • General: Uncheck 'Open safe files after downloading'"
  log "  • Advanced: Enable Develop menu"
  log "  • Extensions: Enable extensions + auto-update"
  exit 0
fi

failed=0

# Show full URL in Smart Search Field
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true || ((failed++))
defaults write com.apple.Safari ShowFavoritesBar-v2 -bool true || ((failed++))
defaults write com.apple.Safari ShowOverlayStatusBar -bool true || ((failed++))
defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true || ((failed++))
defaults write com.apple.Safari BlockStoragePolicy -int 2 || ((failed++))
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false || ((failed++))
defaults write com.apple.Safari AutoFillCreditCardData -bool false || ((failed++))
defaults write com.apple.Safari IncludeDevelopMenu -bool true || ((failed++))
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true || ((failed++))
defaults write com.apple.Safari "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" -bool true || ((failed++))
defaults write com.apple.Safari ExtensionsEnabled -bool true || ((failed++))
defaults write com.apple.Safari InstallExtensionUpdatesAutomatically -bool true || ((failed++))

if (( failed > 0 )); then
  log "Warning: $failed default(s) failed to apply"
else
  log "All defaults applied"
fi

log "Restart Safari for changes to take effect"

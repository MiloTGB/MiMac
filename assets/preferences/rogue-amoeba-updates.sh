#!/usr/bin/env bash
set -euo pipefail

# Rogue Amoeba — disable Sparkle auto-updates (managed by topgrade)

log(){ printf "[rogue-amoeba-updates] %s\n" "$*"; }

failed=0

for bundle in com.rogueamoeba.AudioHijack com.rogueamoeba.Loopback com.rogueamoeba.soundsource; do
  defaults write "$bundle" SUAllowsAutomaticUpdates -int 0 || ((failed++))
  defaults write "$bundle" SUAutomaticallyUpdate -int 0 || ((failed++))
done

if (( failed > 0 )); then
  log "Warning: $failed default(s) failed to apply"
else
  log "All defaults applied"
fi

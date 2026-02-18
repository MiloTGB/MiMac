#!/usr/bin/env bash
# dev-test.sh — Test MiMac installation (local project, no GitHub remote)

set -e
TARGET_DIR="$HOME/MiMac"

echo "🧹 Cleaning up old mrk install…"
if [ -d "$TARGET_DIR" ]; then
  cd "$TARGET_DIR" || exit 1
  if make uninstall >/dev/null 2>&1; then
    echo "✓ Uninstalled previous mrk."
  else
    echo "⚠️ No uninstall target or cleanup incomplete."
  fi
fi

echo "ℹ️  Using existing local MiMac project…"

cd "$TARGET_DIR"
echo "🔧 Fixing permissions…"
make fix-exec

echo "🚀 Installing mrk…"
make install

echo "🩺 Running doctor…"
make doctor || true

echo "✅ Dev test complete. Fresh mrk installed from GitHub."

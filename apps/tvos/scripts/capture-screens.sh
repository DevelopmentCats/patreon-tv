#!/usr/bin/env bash
#
# capture-screens.sh — "Storybook"-style screen capture for PatreonTV.
#
# Builds the app, then for each screen launches it in gallery mode (real data,
# via GALLERY_SCREEN) on the booted tvOS Simulator and screenshots it. Output
# lands in screenshots/<screen>.png so a human or agent can review every page
# in one shot — no manual navigation.
#
# Requirements:
#   - A tvOS Simulator already booted (Xcode > Open Developer Tool > Simulator,
#     or `xcrun simctl boot "<name>"`).
#   - PATREON_SESSION_ID set to a valid session_id cookie.
#
# Usage:
#   PATREON_SESSION_ID=xxxxx ./scripts/capture-screens.sh
#   PATREON_SESSION_ID=xxxxx MATURE=0 ./scripts/capture-screens.sh   # hide NSFW
#
set -euo pipefail

: "${PATREON_SESSION_ID:?Set PATREON_SESSION_ID to a valid session_id cookie}"
MATURE="${MATURE:-1}"
QUERY="${QUERY:-cold}"          # seed term for the search screen
BUNDLE_ID="com.patreontv.PatreonTV"
SCHEME="PatreonTV"
OUT="screenshots"
SCREENS=(signin sessionExpired pairing home creators search settings postDetail creator player audioPlayer upnext)

cd "$(dirname "$0")/.."
mkdir -p "$OUT"

echo "▸ Ensuring project is generated…"
command -v xcodegen >/dev/null && xcodegen generate >/dev/null

echo "▸ Building for tvOS Simulator…"
DERIVED="$(mktemp -d)"
xcodebuild \
  -project PatreonTV.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath "$DERIVED" \
  build >/dev/null

APP="$(find "$DERIVED/Build/Products" -name 'PatreonTV.app' -type d | head -1)"
[ -n "$APP" ] || { echo "Build product not found"; exit 1; }

echo "▸ Installing to booted simulator…"
xcrun simctl install booted "$APP"

for screen in "${SCREENS[@]}"; do
  xcrun simctl terminate booted "$BUNDLE_ID" >/dev/null 2>&1 || true
  # SIMCTL_CHILD_* env vars are passed through to the launched app process.
  SIMCTL_CHILD_GALLERY_SCREEN="$screen" \
  SIMCTL_CHILD_PATREON_SESSION_ID="$PATREON_SESSION_ID" \
  SIMCTL_CHILD_GALLERY_MATURE="$MATURE" \
  SIMCTL_CHILD_GALLERY_QUERY="$QUERY" \
    xcrun simctl launch booted "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 8   # let data + remote images (and video first frame) load before the shot
  xcrun simctl io booted screenshot "$OUT/$screen.png" >/dev/null
  echo "  ✓ $screen → $OUT/$screen.png"
done

xcrun simctl terminate booted "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "▸ Done. Screens in ./$OUT/"

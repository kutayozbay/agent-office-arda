#!/bin/bash
#
# build-app.sh [--dev] [<install-dir>] — build "Agent Office.app" from app/ and web/ and install it
# (default ~/Applications).
# --dev builds "Agent Office Dev.app" instead, to try a branch next to the installed app: its own
# bundle id (so its own settings, permissions and Dock icon, with an orange stripe), its own config
# folder (~/.config/agent-office-dev: its own name, picture, room and scores), and no updater. It
# reads the same sessions, and can join your room as a second person to try the shared parts. Needs the Xcode command-line tools (swiftc, iconutil, codesign).
# The app runs on this Mac only: signed with the local certificate from scripts/signing-setup.sh
# when there is one (permissions survive rebuilds), else ad-hoc. Rebuilding replaces it in place.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV=0; ARGS=()
for a in "$@"; do if [[ "$a" == "--dev" ]]; then DEV=1; else ARGS+=("$a"); fi; done
DEST="${ARGS[0]:-$HOME/Applications}"
if [[ $DEV == 1 ]]; then NAME="Agent Office Dev"; BUNDLE_ID="local.agent-office.dev"; SLUG="agent-office-dev"
else NAME="Agent Office"; BUNDLE_ID="local.agent-office"; SLUG="agent-office"; fi
APP="$DEST/$NAME.app"
# what the in-app updater compares and updates: the newest release tag reachable from this commit,
# the GitHub repository of the checkout's origin, and the checkout itself
VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0)"; VERSION="${VERSION#v}"
REPO="$(git -C "$ROOT" remote get-url origin 2>/dev/null | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
if [[ $DEV == 1 ]]; then REPO=""; fi           # a dev build never updates itself: no repository, no Update button
xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
BUILD="$(mktemp -d)"; trap 'rm -rf "$BUILD"' EXIT
B="$BUILD/Agent Office.app/Contents"
mkdir -p "$B/MacOS" "$B/Resources"

# the file with the top-level startup code has to be called main.swift when there are several
cp "$ROOT/app/AgentOffice.swift" "$BUILD/main.swift"
swiftc -O -o "$B/MacOS/AgentOffice" "$BUILD/main.swift" "$ROOT/app/Room.swift" "$ROOT/app/Update.swift" "$ROOT/app/RoomSetup.swift" "$ROOT/app/Profile.swift" "$ROOT/app/Jukebox.swift" "$ROOT/app/Signing.swift" "$ROOT/app/Games.swift" "$ROOT/app/Terminal.swift" "$ROOT/app/Water.swift" -framework Cocoa -framework WebKit -framework Network -framework ServiceManagement -framework UserNotifications
cp "$ROOT/web/office.html" "$B/Resources/"
cp "$ROOT"/web/games*.js "$B/Resources/"                      # the mini-games (office.html loads them)
cp "$ROOT/web/terminal.html" "$B/Resources/"                 # the terminal under the office (Terminal.swift)
cp -R "$ROOT/web/vendor" "$B/Resources/"                     # xterm.js, which draws it
cp "$ROOT/app/nowplaying.py" "$B/Resources/"                 # the jukebox's Now Playing helper (Jukebox.swift)
cp "$ROOT/scripts/signing-setup.sh" "$B/Resources/"            # the app offers it (Signing.swift)

swift "$ROOT/scripts/make-icon.swift" "$BUILD/icon.png" "$([[ $DEV == 1 ]] && echo dev || echo app)"
mkdir "$BUILD/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/icon.png" --out "$BUILD/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$BUILD/icon.png" --out "$BUILD/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$B/Resources/AppIcon.icns"

cat > "$B/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>AgentOfficeSlug</key><string>$SLUG</string>
  <key>CFBundleExecutable</key><string>AgentOffice</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$(xml "$VERSION")</string>
  <key>AgentOfficeRepo</key><string>$(xml "$REPO")</string>
  <key>AgentOfficeSource</key><string>$(xml "$ROOT")</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>The shared room: Agent Office finds your team's room on the local network and joins it, so your lounges are one. Only names, pictures, chat and the mini-games' moves and scores are shared.</string>
  <key>NSBonjourServices</key><array><string>_agent-office._tcp</string></array>
  <key>NSAppleEventsUsageDescription</key><string>Clicking an agent brings its session to the front: Agent Office asks Terminal, iTerm or System Events (for a VS Code window) to show that tab or window. The lounge's jukebox asks Spotify which song is playing, and to skip or pause it when you press its buttons.</string>
</dict></plist>
PLIST
# Signed with the local certificate when scripts/signing-setup.sh made one: then every build is the
# same app to macOS and the permissions it was given stay. Without it, ad-hoc: each build is a new
# app to macOS, which asks for every permission again.
SIGN_ID="Agent Office Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_ID\""; then
  codesign --force --deep --sign "$SIGN_ID" "$BUILD/Agent Office.app" >/dev/null
else
  codesign --force --deep --sign - "$BUILD/Agent Office.app" >/dev/null
  echo "Signed ad-hoc: macOS asks for its permissions again after each build. Once: scripts/signing-setup.sh"
fi

mkdir -p "$DEST"
rm -rf "$APP"
mv "$BUILD/Agent Office.app" "$APP"
echo "Built: $APP"

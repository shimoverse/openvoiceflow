#!/usr/bin/env bash
#
# Build → sign → notarize → staple → DMG for the native OpenVoiceFlow app.
#
# Runs on macOS (a GitHub `macos-14` runner or a developer's Mac). Produces a
# single *universal* (arm64 + x86_64) Developer-ID-signed, Apple-notarized,
# stapled DMG at native/dist/OpenVoiceFlow-<version>.dmg.
#
# This is the native counterpart to the Python build-dmg.sh. The signing
# keychain is prepared by the caller (release-native.yml mirrors release.yml);
# this script only consumes the identity + notary credentials via env.
#
# Required env when OVF_NOTARIZE=1 (a real signed release):
#   OVF_SIGN_IDENTITY   "Developer ID Application: NAME (TEAMID)"
#   OVF_TEAM_ID         Apple Developer team id (10 chars)
#   OVF_NOTARY_KEY      path to the App Store Connect API key .p8
#   OVF_NOTARY_KEY_ID   the key id
#   OVF_NOTARY_ISSUER_ID the issuer id
# Optional:
#   OVF_VERSION         overrides MARKETING_VERSION from project.yml
#   OVF_NOTARIZE        1 (default) to sign+notarize; 0 for an unsigned local build
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # native/
cd "$HERE"

NOTARIZE="${OVF_NOTARIZE:-1}"
BUILD_DIR="build"
DIST_DIR="dist"
ARCHIVE="$BUILD_DIR/OpenVoiceFlow.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/OpenVoiceFlow.app"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# ── version ─────────────────────────────────────────────────────────────────
VERSION="${OVF_VERSION:-$(grep -E 'MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*: *"?([0-9.]+)"?.*/\1/')}"
echo "▸ Building OpenVoiceFlow $VERSION (notarize=$NOTARIZE)"

# ── project ─────────────────────────────────────────────────────────────────
# project.yml is the source of truth; regenerate the .xcodeproj so a stale
# checkout can never drift from it.
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "::error::xcodegen not found (brew install xcodegen)"; exit 1
fi
xcodegen generate

# ── archive (universal, hardened runtime) ───────────────────────────────────
SIGN_ARGS=(CODE_SIGN_STYLE=Manual)
if [[ "$NOTARIZE" == "1" ]]; then
  : "${OVF_SIGN_IDENTITY:?set OVF_SIGN_IDENTITY}"
  : "${OVF_TEAM_ID:?set OVF_TEAM_ID}"
  SIGN_ARGS+=(
    CODE_SIGN_IDENTITY="$OVF_SIGN_IDENTITY"
    DEVELOPMENT_TEAM="$OVF_TEAM_ID"
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"
  )
else
  # Local unsigned build: skip signing so it runs without a certificate.
  SIGN_ARGS+=(CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)
fi

xcodebuild \
  -project OpenVoiceFlow.xcodeproj \
  -scheme OpenVoiceFlow \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  "${SIGN_ARGS[@]}" \
  archive

# ── export the .app out of the archive ──────────────────────────────────────
if [[ "$NOTARIZE" == "1" ]]; then
  cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>${OVF_TEAM_ID}</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"
else
  mkdir -p "$EXPORT_DIR"
  cp -R "$ARCHIVE/Products/Applications/OpenVoiceFlow.app" "$APP"
fi

[[ -d "$APP" ]] || { echo "::error::export produced no .app"; exit 1; }

# ── notarize the app, then staple (offline Gatekeeper for the app itself) ────
if [[ "$NOTARIZE" == "1" ]]; then
  : "${OVF_NOTARY_KEY:?}"; : "${OVF_NOTARY_KEY_ID:?}"; : "${OVF_NOTARY_ISSUER_ID:?}"
  echo "▸ Notarizing the app bundle"
  ditto -c -k --keepParent "$APP" "$BUILD_DIR/OpenVoiceFlow.zip"
  xcrun notarytool submit "$BUILD_DIR/OpenVoiceFlow.zip" \
    --key "$OVF_NOTARY_KEY" --key-id "$OVF_NOTARY_KEY_ID" --issuer "$OVF_NOTARY_ISSUER_ID" \
    --wait
  xcrun stapler staple "$APP"
  # The DMG caption promises the user an "Open" button. Gatekeeper only offers
  # one for a notarized, stapled build — an un-notarized app gets a dead-end
  # "Move to Trash" instead, which would make that caption a lie. Assert it
  # rather than trusting the submit above to have succeeded.
  xcrun stapler validate "$APP" \
    || { echo "::error::app is not stapled — Gatekeeper would show no Open button"; exit 1; }
fi

# ── DMG (app + /Applications symlink, styled window) ────────────────────────
#
# A plain `hdiutil create` gives a window with two bare icons and no hint
# beyond "figure it out" — every polished Mac app instead ships a background
# with an arrow pointing at Applications and both icons pre-placed on it.
# That art already existed (native/assets/dmg-bg@2x.png, from
# render-dmg-bg.py) but nothing ever wired it into the build.
#
# Finder only picks up a window layout from a live, writable mount, hence the
# create → attach → style → detach → compress dance below instead of one
# `hdiutil create -format UDZO` call.
DMG="$DIST_DIR/OpenVoiceFlow-$VERSION.dmg"
VOLNAME="OpenVoiceFlow $VERSION"
STAGE="$BUILD_DIR/dmg"
BG_IMAGE="$HERE/assets/dmg-bg@2x.png"
rm -rf "$STAGE"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
if [[ -f "$BG_IMAGE" ]]; then
  # Finder displays DMG backgrounds at one image pixel per layout point; unlike
  # app assets it does not interpret @2x filename semantics. Keep the high-res
  # source in git, but stage a 660×400 copy so the artwork is not cropped to
  # its upper-left quadrant in the 660×422 Finder window.
  sips -z 400 660 "$BG_IMAGE" --out "$STAGE/.background/background.png" >/dev/null
fi

RW_DMG="$BUILD_DIR/OpenVoiceFlow-rw.dmg"
rm -f "$RW_DMG"
# Padded well past the app's size: this is a throwaway HFS+ container, not
# the shipped artifact — that's the UDZO conversion below.
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -fs HFS+ \
  -format UDRW -size 500m "$RW_DMG" >/dev/null

if [[ -f "$BG_IMAGE" ]]; then
  # Parse the actual mount point instead of assuming /Volumes/$VOLNAME. macOS
  # adds a numeric suffix when that path is already occupied; styling or
  # detaching by the requested volume name can otherwise target the wrong DMG.
  ATTACH_PLIST="$BUILD_DIR/dmg-attach.plist"
  hdiutil attach "$RW_DMG" -noautoopen -plist > "$ATTACH_PLIST"
  MOUNT_POINT="$(python3 - "$ATTACH_PLIST" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    payload = plistlib.load(handle)
mounts = [
    entity["mount-point"]
    for entity in payload.get("system-entities", [])
    if entity.get("mount-point")
]
if not mounts:
    raise SystemExit("hdiutil attach returned no mount point")
print(mounts[-1])
PY
)"
  cleanup_mount() {
    [[ -n "${MOUNT_POINT:-}" ]] || return 0
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 \
      || hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 \
      || true
  }
  trap cleanup_mount EXIT

  echo "▸ Styling the DMG window"
  # A stray/first-run Automation permission prompt for Finder would hang here
  # forever with no one to click it — bound the wait so that case degrades to
  # an unstyled DMG instead of stalling the whole release.
  osascript - "$MOUNT_POINT" <<'OSA' &
on run argv
    set mountPoint to item 1 of argv
    set dmgFolder to POSIX file mountPoint as alias
    tell application "Finder"
        tell folder dmgFolder
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {200, 120, 860, 542}
            set theViewOptions to icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 128
            set text size of theViewOptions to 12
            set background picture of theViewOptions to file ".background:background.png"
            set position of item "OpenVoiceFlow.app" to {165, 155}
            set position of item "Applications" to {495, 155}
            close
            open
            update without registering applications
            delay 2
        end tell
    end tell
end run
OSA
  osa_pid=$!
  waited=0
  while kill -0 "$osa_pid" 2>/dev/null && [[ $waited -lt 30 ]]; do
    sleep 1; waited=$((waited + 1))
  done
  if kill -0 "$osa_pid" 2>/dev/null; then
    echo "::warning::DMG styling timed out after 30s (Finder Automation permission?) — shipping an unstyled window"
    kill "$osa_pid" 2>/dev/null || true
    wait "$osa_pid" 2>/dev/null || true
  elif ! wait "$osa_pid"; then
    echo "::warning::DMG styling failed — shipping an unstyled window"
  fi
  sync
  cleanup_mount
  MOUNT_POINT=""
  trap - EXIT
fi

hdiutil convert "$RW_DMG" -format UDZO -ov -o "$DMG" >/dev/null
rm -f "$RW_DMG"

# ── sign the DMG itself ─────────────────────────────────────────────────────
#
# Not the same as signing the app inside it. Until 0.4.3 only the .app was
# signed; the DMG carried a stapled notarization ticket but no signature of its
# own, and `spctl -a -t install` evaluates the disk image against its own
# signature — a ticket is not one. That went unnoticed because the spctl check
# ended in `|| true` and swallowed the rejection.
#
# Must happen BEFORE notarizing: notarization staples a ticket to this exact
# artifact, and signing afterwards would invalidate it.
if [[ "$NOTARIZE" == "1" ]]; then
  echo "▸ Signing the DMG"
  codesign --force --timestamp --sign "$OVF_SIGN_IDENTITY" "$DMG" \
    || { echo "::error::could not sign the DMG with $OVF_SIGN_IDENTITY"; exit 1; }
fi

# ── notarize + staple the DMG (offline Gatekeeper for the download) ─────────
if [[ "$NOTARIZE" == "1" ]]; then
  echo "▸ Notarizing the DMG"
  xcrun notarytool submit "$DMG" \
    --key "$OVF_NOTARY_KEY" --key-id "$OVF_NOTARY_KEY_ID" --issuer "$OVF_NOTARY_ISSUER_ID" \
    --wait
  xcrun stapler staple "$DMG"
  # Blocking, not advisory: this used to end in `|| true`, so a lapsed
  # notarization shipped silently. Both checks must pass or the release stops.
  echo "▸ Verifying Gatekeeper acceptance"
  xcrun stapler validate "$DMG" \
    || { echo "::error::DMG is not stapled — Gatekeeper cannot verify it offline"; exit 1; }
  spctl -a -vvv -t install "$DMG" \
    || { echo "::error::Gatekeeper rejected the DMG; it would not offer an Open button"; exit 1; }
fi

# ── manifest ────────────────────────────────────────────────────────────────
SIZE=$(stat -f%z "$DMG")
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "OpenVoiceFlow-$VERSION.dmg  $SIZE bytes  sha256=$SHA"
echo "dmg_path=$DMG"      >> "${GITHUB_OUTPUT:-/dev/null}"
echo "dmg_version=$VERSION" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "dmg_sha256=$SHA"    >> "${GITHUB_OUTPUT:-/dev/null}"

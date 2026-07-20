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
fi

# ── DMG (app + /Applications symlink) ───────────────────────────────────────
DMG="$DIST_DIR/OpenVoiceFlow-$VERSION.dmg"
STAGE="$BUILD_DIR/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "OpenVoiceFlow $VERSION" \
  -srcfolder "$STAGE" -ov -format UDZO "$DMG"

# ── notarize + staple the DMG (offline Gatekeeper for the download) ─────────
if [[ "$NOTARIZE" == "1" ]]; then
  echo "▸ Notarizing the DMG"
  xcrun notarytool submit "$DMG" \
    --key "$OVF_NOTARY_KEY" --key-id "$OVF_NOTARY_KEY_ID" --issuer "$OVF_NOTARY_ISSUER_ID" \
    --wait
  xcrun stapler staple "$DMG"
  echo "▸ Verifying Gatekeeper acceptance"
  spctl -a -vvv -t install "$DMG" || true
fi

# ── manifest ────────────────────────────────────────────────────────────────
SIZE=$(stat -f%z "$DMG")
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "OpenVoiceFlow-$VERSION.dmg  $SIZE bytes  sha256=$SHA"
echo "dmg_path=$DMG"      >> "${GITHUB_OUTPUT:-/dev/null}"
echo "dmg_version=$VERSION" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "dmg_sha256=$SHA"    >> "${GITHUB_OUTPUT:-/dev/null}"

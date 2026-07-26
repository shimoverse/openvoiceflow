#!/usr/bin/env bash
#
# Build the app from this checkout and launch it. For looking at the thing on
# your own Mac — not a release build (see build-app.sh for signed + notarized).
#
#   bash native/scripts/run-local.sh
#
# Signs ad-hoc rather than not at all. The CI build passes
# CODE_SIGNING_ALLOWED=NO because it only needs to know the Swift compiles;
# an app you actually run needs a code signature, because macOS ties
# Accessibility and Input Monitoring grants to one — unsigned, the hotkey
# silently never fires.
#
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This builds a macOS app, and this is not a Mac ($(uname -s))." >&2
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # native/
cd "$HERE"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
fail() { printf '\n\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# ── prerequisites ───────────────────────────────────────────────────────────
step "Checking prerequisites"

if ! xcodebuild -version >/dev/null 2>&1; then
  fail "Xcode isn't installed, or only the command-line tools are.
  Get Xcode from the App Store (it's free, ~7 GB), open it once to accept the
  licence, then run:  sudo xcode-select -s /Applications/Xcode.app
  Building an app bundle needs full Xcode; the CLT alone can't."
fi
echo "  Xcode: $(xcodebuild -version | head -1)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "  XcodeGen: missing — this generates the .xcodeproj from project.yml."
  if command -v brew >/dev/null 2>&1; then
    step "Installing XcodeGen (one time, via Homebrew)"
    brew install xcodegen
  else
    fail "XcodeGen is missing and Homebrew isn't installed.
  Install Homebrew from https://brew.sh, then re-run this script."
  fi
else
  echo "  XcodeGen: $(xcodegen --version 2>&1 | head -1)"
fi

# ── build ───────────────────────────────────────────────────────────────────
step "Generating the Xcode project"
xcodegen generate

DERIVED="$HERE/build/local"

step "Building (first run pulls WhisperKit — expect 5–10 minutes)"
echo "  Later builds take well under a minute."
set +e
xcodebuild \
  -project OpenVoiceFlow.xcodeproj \
  -scheme OpenVoiceFlow \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build
BUILD_STATUS=$?
set -e

if [[ $BUILD_STATUS -ne 0 ]]; then
  fail "The build failed. The compiler errors are above — the lines that
  matter look like  SomeFile.swift:123:4: error: ...
  Copy those back to Claude and it can fix them."
fi

APP="$DERIVED/Build/Products/Debug/OpenVoiceFlow.app"
[[ -d "$APP" ]] || fail "Built, but no app at $APP — the layout changed."

# ── launch ──────────────────────────────────────────────────────────────────
# Kill a copy left over from a previous run, or the new one races it for the
# hotkey tap and neither reliably wins.
if pgrep -x OpenVoiceFlow >/dev/null 2>&1; then
  step "Quitting the running copy"
  killall OpenVoiceFlow 2>/dev/null || true
  sleep 1
fi

step "Launching"
open "$APP"

cat <<NOTES

  To relaunch after quitting, don't re-run this script — it rebuilds, and a
  new binary is what loses you the permission grants. Just reopen it:

      open $APP

NOTES

cat <<'NOTES'

  ─────────────────────────────────────────────────────────────────────────
  It's running. There is no window at first — that's the design. Look for a
  small waveform in the menu bar, top right.

  First launch walks you through onboarding: permissions, then the speech
  model download, then it asks you to say a sentence.

  Two things that will look like bugs and aren't:

  · macOS will ask for Microphone, Accessibility and Input Monitoring.
    It has to — those are the OS's to grant, not the app's.

  · After you rebuild, the hotkey may stop working. macOS ties permission
    grants to the exact binary, and rebuilding makes a new one. Fix:
    System Settings ▸ Privacy & Security ▸ Accessibility, remove
    OpenVoiceFlow with the −, then add this build back with the +.

  To dictate: hold the fn key (bottom left), talk, let go.
  To quit: menu-bar icon ▸ Quit.
  ─────────────────────────────────────────────────────────────────────────

NOTES

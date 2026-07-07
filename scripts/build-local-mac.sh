#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "This script requires macOS."
    exit 1
fi

cd "$REPO_ROOT"

LOCK_DIR="/tmp/openvoiceflow-local-build.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"

acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$LOCK_PID_FILE"
        return 0
    fi

    if [[ -f "$LOCK_PID_FILE" ]]; then
        owner_pid="$(cat "$LOCK_PID_FILE" 2>/dev/null || true)"
        if [[ -n "$owner_pid" ]] && ps -p "$owner_pid" >/dev/null 2>&1; then
            echo "Another local build is running (pid $owner_pid)."
            echo "If this is stale, remove: $LOCK_DIR"
            return 1
        fi
    fi

    rm -rf "$LOCK_DIR" >/dev/null 2>&1 || true
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$LOCK_PID_FILE"
        return 0
    fi

    echo "Another local build is running. If this is stale, remove: $LOCK_DIR"
    return 1
}

if ! acquire_lock; then
    exit 1
fi

cleanup_lock() {
    rm -f "$LOCK_PID_FILE" >/dev/null 2>&1 || true
    rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
}
trap cleanup_lock EXIT

ARCH="$(uname -m)"
case "$ARCH" in
    arm64)
        DMG_ARCH="arm64"
        ;;
    x86_64)
        DMG_ARCH="x86_64"
        ;;
    *)
        echo "Unsupported Mac architecture: $ARCH"
        exit 1
        ;;
esac

echo "Building local DMG for current architecture only..."
OVF_LOCAL_ONLY=1 OVF_BUILD_ARCH_ONLY="$DMG_ARCH" bash build-dmg.sh

VERSION="$(python3 -c "import re; print(re.search(r'version\\s*=\\s*\"(.+?)\"', open('pyproject.toml').read()).group(1))")"
DMG_PATH="$REPO_ROOT/dist/OpenVoiceFlow-$VERSION-$DMG_ARCH.dmg"

if [[ ! -f "$DMG_PATH" ]]; then
    echo "Expected DMG not found: $DMG_PATH"
    exit 1
fi

MOUNT_POINT="$(mktemp -d /tmp/ovf-local-build.XXXX)"

# A second `trap ... EXIT` REPLACES the first, so this must also release the
# build lock — otherwise the lock dir is left behind after every run that
# reaches the mount stage.
cleanup() {
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
    cleanup_lock
}
trap cleanup EXIT

echo "Mounting $DMG_PATH..."
hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

LAUNCHER="$MOUNT_POINT/OpenVoiceFlow.app/Contents/MacOS/OpenVoiceFlow"
if [[ ! -x "$LAUNCHER" ]]; then
    echo "Launcher not found or not executable: $LAUNCHER"
    exit 1
fi

echo "Checking launcher shell syntax..."
bash -n "$LAUNCHER"

echo "Running launcher smoke test for $DMG_ARCH..."
OVF_SMOKE_TEST=1 "$LAUNCHER"

APP_PATH="/Applications/OpenVoiceFlow.app"
echo "Installing app to $APP_PATH..."
pkill -f "OpenVoiceFlow.app/Contents/MacOS/OpenVoiceFlow" >/dev/null 2>&1 || true
rm -rf "$APP_PATH"
ditto "$MOUNT_POINT/OpenVoiceFlow.app" "$APP_PATH"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Install failed: $APP_PATH was not created"
    exit 1
fi

# Remove quarantine attributes to avoid Gatekeeper surprises during local testing.
xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1 || true

INSTALLED_LAUNCHER="$APP_PATH/Contents/MacOS/OpenVoiceFlow"
if [[ ! -x "$INSTALLED_LAUNCHER" ]]; then
    echo "Installed launcher missing or not executable: $INSTALLED_LAUNCHER"
    exit 1
fi

echo "Launching installed app from /Applications..."
LOG_FILE="$HOME/OpenVoiceFlow/launcher.log"
: > "$LOG_FILE"
open -a "$APP_PATH"
sleep 2

if pgrep -f "OpenVoiceFlow.app/Contents/MacOS/OpenVoiceFlow|openvoiceflow-runtime|\.openvoiceflow/venv/bin/python3" >/dev/null 2>&1; then
    echo "Launch check: OpenVoiceFlow runtime process detected."
else
    echo "Launch check: runtime process not detected. See fresh launcher log below."
fi

if [[ -f "$LOG_FILE" ]]; then
    echo "Recent launcher log:"
    tail -n 60 "$LOG_FILE"

    if grep -q "Accessibility permission not granted" "$LOG_FILE"; then
        echo "Launch is currently blocked by macOS Accessibility permission."
        echo "Opening Accessibility settings so OpenVoiceFlow can be added."
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true
    fi
fi

echo "Success: local $DMG_ARCH build smoke test passed."
echo "DMG: $DMG_PATH"
echo "Installed app: $APP_PATH"

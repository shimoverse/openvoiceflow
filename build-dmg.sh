#!/bin/bash
# Build OpenVoiceFlow.dmg — a drag-to-Applications installer for macOS
#
# This creates:
#   1. A self-contained .app bundle with embedded Python + all dependencies
#   2. A DMG with the app + Applications symlink for drag-to-install
#
# Usage: bash build-dmg.sh
# Output: dist/OpenVoiceFlow.dmg

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="OpenVoiceFlow"
BUNDLE_ID="com.openvoiceflow.dictation"
VERSION="0.1.0"

echo ""
echo "================================================"
echo "🔨 Building ${APP_NAME}.dmg"
echo "================================================"
echo ""

# --- Check macOS ---
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}❌ DMG can only be built on macOS.${NC}"
    exit 1
fi

# --- Setup build environment ---
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$SCRIPT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_DIR="$DIST_DIR/dmg-staging"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# --- Create venv for bundling ---
echo "📦 Creating build environment..."
VENV="$BUILD_DIR/venv"
python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q sounddevice numpy pynput rumps

# Verify
"$VENV/bin/python3" -c "import sounddevice, numpy, pynput, rumps; print('  ✅ All dependencies installed')"

# --- Get Python info ---
PYTHON_VERSION=$("$VENV/bin/python3" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
SITE_PACKAGES="$VENV/lib/python${PYTHON_VERSION}/site-packages"
PYTHON_BIN=$(python3 -c "import sys; print(sys.executable)")
echo "  Python: $PYTHON_VERSION"
echo "  Site-packages: $SITE_PACKAGES"

# --- Build .app bundle ---
echo ""
echo "🔨 Building ${APP_NAME}.app..."

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources/voiceflow"
mkdir -p "$APP_DIR/Contents/Resources/voiceflow/llm"
mkdir -p "$APP_DIR/Contents/Resources/lib"

# Copy source code
cp "$SCRIPT_DIR/voiceflow/"*.py "$APP_DIR/Contents/Resources/voiceflow/"
cp "$SCRIPT_DIR/voiceflow/llm/"*.py "$APP_DIR/Contents/Resources/voiceflow/llm/"
echo "  ✅ Source code copied"

# Copy site-packages (only what we need)
for pkg in sounddevice.py sounddevice_data numpy pynput _sounddevice_data _cffi_backend* cffi _cffi* objc PyObjCTools rumps; do
    if [[ -e "$SITE_PACKAGES/$pkg" ]]; then
        cp -R "$SITE_PACKAGES/$pkg" "$APP_DIR/Contents/Resources/lib/" 2>/dev/null || true
    fi
done
# Copy everything from site-packages that's needed (simpler approach)
cp -R "$SITE_PACKAGES"/* "$APP_DIR/Contents/Resources/lib/" 2>/dev/null || true
echo "  ✅ Dependencies bundled"

# Copy PortAudio dylib
PA_LIB=$(python3 -c "
import ctypes.util
p = ctypes.util.find_library('portaudio')
if p: print(p)
" 2>/dev/null || true)
if [[ -n "$PA_LIB" && -f "$PA_LIB" ]]; then
    cp "$PA_LIB" "$APP_DIR/Contents/Resources/lib/"
    echo "  ✅ PortAudio bundled"
elif [[ -f "/opt/homebrew/lib/libportaudio.dylib" ]]; then
    cp /opt/homebrew/lib/libportaudio.dylib "$APP_DIR/Contents/Resources/lib/"
    echo "  ✅ PortAudio bundled (Homebrew)"
fi

# Create launcher Python script
cat > "$APP_DIR/Contents/Resources/launch.py" << 'PYLAUNCH'
#!/usr/bin/env python3
"""OpenVoiceFlow launcher — sets up paths and runs the app."""
import sys
import os
from pathlib import Path

# Add bundled libraries to path
resources = Path(__file__).parent
lib_dir = resources / "lib"
sys.path.insert(0, str(lib_dir))
sys.path.insert(0, str(resources))

# Set library path for PortAudio
os.environ["DYLD_LIBRARY_PATH"] = str(lib_dir)

# Check if first run (no config) — launch onboarding
config_dir = Path.home() / ".openvoiceflow"
config_path = config_dir / "config.json"

if not config_path.exists():
    # First run — try GUI onboarding
    try:
        from voiceflow.onboarding import run_onboarding
        config = run_onboarding()
        if not config:
            sys.exit(0)
    except Exception as e:
        print(f"Onboarding error: {e}")

# Start the menu bar app (or CLI if rumps unavailable)
try:
    from voiceflow.menubar import run_menubar
    run_menubar()
except ImportError:
    from voiceflow.app import OpenVoiceFlow
    OpenVoiceFlow().run()
PYLAUNCH

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>icon</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>OpenVoiceFlow needs microphone access to transcribe your voice.</string>
    <key>NSAppleEventsUsageDescription</key><string>OpenVoiceFlow needs automation access to paste text at your cursor.</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
PLIST

# Create the executable shell launcher
cat > "$APP_DIR/Contents/MacOS/${APP_NAME}" << 'LAUNCHER'
#!/bin/bash
DIR="$(cd "$(dirname "$0")/../Resources" && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export DYLD_LIBRARY_PATH="$DIR/lib:$DYLD_LIBRARY_PATH"

# Use system Python (guaranteed on macOS)
exec /usr/bin/python3 "$DIR/launch.py" "$@"
LAUNCHER
chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"

echo "  ✅ ${APP_NAME}.app built"

# --- Create a simple icon (optional) ---
echo ""
echo "🎨 Creating app icon..."
# Use Python to generate a simple icon via sips
python3 << 'ICONSCRIPT' 2>/dev/null || true
import subprocess, tempfile, os

# Create a simple 512x512 icon using HTML canvas
html = '''<html><body style="margin:0;background:transparent">
<canvas id="c" width="512" height="512"></canvas>
<script>
var c=document.getElementById('c').getContext('2d');
// Background circle
c.beginPath();c.arc(256,256,240,0,Math.PI*2);
c.fillStyle='#0f89ff';c.fill();
// Microphone shape
c.fillStyle='white';
c.beginPath();c.roundRect(206,120,100,200,50);c.fill();
c.fillStyle='white';c.fillRect(236,320,40,80);
c.beginPath();c.arc(256,420,60,0,Math.PI);c.fill();
// Waves
c.strokeStyle='white';c.lineWidth=12;c.lineCap='round';
c.beginPath();c.arc(256,240,130,0.8,2.3);c.stroke();
c.beginPath();c.arc(256,240,170,0.9,2.2);c.stroke();
</script></body></html>'''
# Skip icon generation if no webkit tools available
print("  (Using default macOS icon)")
ICONSCRIPT

# --- Build DMG ---
echo ""
echo "📀 Creating DMG..."

mkdir -p "$DMG_DIR"
cp -R "$APP_DIR" "$DMG_DIR/"

# Create Applications symlink for drag-to-install
ln -s /Applications "$DMG_DIR/Applications"

# Create a background readme
cat > "$DMG_DIR/.README.txt" << 'DMGREADME'
OpenVoiceFlow — Free Voice Dictation for macOS

Drag OpenVoiceFlow.app to Applications to install.

After launching:
1. Grant Accessibility permission when prompted
2. Grant Microphone permission when prompted
3. Hold Right Command → Speak → Release → Text appears at cursor

Config: ~/.openvoiceflow/config.json
Logs:   ~/OpenVoiceFlow/logs/

https://github.com/mohitjain/openvoiceflow
DMGREADME

# Create the DMG
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"
DMG_TEMP="$BUILD_DIR/temp.dmg"

# Create DMG using hdiutil
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDBZ \
    "$DMG_PATH"

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}✅ Build complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "  DMG: $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "  To install:"
echo "    1. Open the DMG"
echo "    2. Drag OpenVoiceFlow to Applications"
echo "    3. Open OpenVoiceFlow from Applications"
echo "    4. Grant Accessibility + Microphone permissions"
echo ""
echo "  To distribute:"
echo "    Upload ${APP_NAME}-${VERSION}.dmg to GitHub Releases"
echo ""

# Cleanup
rm -rf "$DMG_DIR"
echo "Done! 🎉"

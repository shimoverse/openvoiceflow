#!/bin/bash
# Build OpenVoiceFlow.dmg — a drag-to-Applications installer for macOS
#
# Creates a THIN .app bundle that:
#   - Contains only source code + launcher script
#   - Auto-installs Python dependencies on first launch (native to user's Mac)
#   - Works on both Intel and Apple Silicon (no Rosetta needed)
#   - Works on macOS 12+ (Monterey and later)
#
# Usage: bash build-dmg.sh
# Output: dist/OpenVoiceFlow-VERSION.dmg

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

# --- Setup ---
DIST_DIR="$SCRIPT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_DIR="$DIST_DIR/dmg-staging"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# --- Build .app bundle ---
echo "🔨 Building ${APP_NAME}.app..."

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources/voiceflow/llm"

# Copy source code
cp "$SCRIPT_DIR/voiceflow/"*.py "$APP_DIR/Contents/Resources/voiceflow/"
cp "$SCRIPT_DIR/voiceflow/llm/"*.py "$APP_DIR/Contents/Resources/voiceflow/llm/"
echo "  ✅ Source code copied"

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
echo "  ✅ Info.plist created"

# Create the bootstrap launcher script
cat > "$APP_DIR/Contents/MacOS/${APP_NAME}" << 'LAUNCHER'
#!/bin/bash
#
# OpenVoiceFlow Launcher — Universal (Intel + Apple Silicon)
#
# On first run:
#   1. Checks for Homebrew (offers to install if missing)
#   2. Checks for whisper-cpp (installs via brew)
#   3. Creates Python venv at ~/.openvoiceflow/venv/
#   4. Installs Python packages natively
#   5. Downloads whisper model
#   6. Launches GUI onboarding wizard
#
# On subsequent runs:
#   - Updates source code and launches immediately
#

# --- Force native execution on Apple Silicon ---
# macOS .app bundles sometimes launch under Rosetta. Detect and re-exec natively.
if [[ "$(uname -m)" == "x86_64" ]] && [[ "$(sysctl -n machdep.cpu.brand_string 2>/dev/null)" == *"Apple"* ]]; then
    exec arch -arm64 "$0" "$@"
fi

# --- Architecture-aware command wrapper ---
# On Apple Silicon: prefix commands with arch -arm64 (in case Rosetta leaks through)
# On Intel: run commands directly
if [[ "$(uname -m)" == "arm64" ]]; then
    run() { "$@"; }
else
    # Check if this is Apple Silicon running under Rosetta
    if [[ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" == "1" ]]; then
        run() { arch -arm64 "$@"; }
    else
        # Genuine Intel Mac
        run() { "$@"; }
    fi
fi

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES="$APP_DIR/Resources"
VOICEFLOW_HOME="$HOME/.openvoiceflow"
VENV_DIR="$VOICEFLOW_HOME/venv"
LOG_DIR="$HOME/OpenVoiceFlow"
LOG_FILE="$LOG_DIR/voiceflow.log"
PYTHON="$VENV_DIR/bin/python3"

# Ensure directories
mkdir -p "$LOG_DIR" "$VOICEFLOW_HOME"

# --- macOS dialog helpers ---
show_dialog() {
    osascript -e "display dialog \"$1\" with title \"OpenVoiceFlow\" buttons {\"$2\"} default button \"$2\" with icon note" 2>/dev/null
}

show_error() {
    osascript -e "display dialog \"$1\" with title \"OpenVoiceFlow\" buttons {\"OK\"} default button \"OK\" with icon stop" 2>/dev/null
}

show_progress() {
    osascript -e "display notification \"$1\" with title \"OpenVoiceFlow\"" 2>/dev/null
}

# --- Source Homebrew ---
source_brew() {
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

source_brew

# --- Step 1: Check Python 3 ---
if ! command -v python3 &>/dev/null; then
    show_error "Python 3 is required.\n\nInstall it by running in Terminal:\n  xcode-select --install"
    exit 1
fi

# --- Step 2: Check/Install Homebrew ---
if ! command -v brew &>/dev/null; then
    show_dialog "OpenVoiceFlow needs Homebrew to install the speech engine.\n\nThis is a one-time setup." "Install Homebrew"

    osascript << 'EOF'
tell application "Terminal"
    activate
    do script "echo '🔧 Installing Homebrew...' && /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" && echo '' && echo '✅ Homebrew installed! Now close this window and reopen OpenVoiceFlow.' && echo ''"
end tell
EOF
    show_dialog "After Homebrew finishes installing in Terminal, relaunch OpenVoiceFlow from Applications." "OK"
    exit 0
fi

# --- Step 3: Check/Install whisper-cpp ---
if ! command -v whisper-cli &>/dev/null && ! command -v whisper-cpp &>/dev/null; then
    show_progress "Installing whisper-cpp (speech engine)..."
    run brew install whisper-cpp >>"$LOG_FILE" 2>&1

    if ! command -v whisper-cli &>/dev/null && ! command -v whisper-cpp &>/dev/null; then
        show_error "Failed to install whisper-cpp.\n\nTry manually in Terminal:\n  brew install whisper-cpp\n\nLog: $LOG_FILE"
        exit 1
    fi
    show_progress "whisper-cpp installed!"
fi

# --- Step 4: Create/update Python venv ---
if [[ ! -f "$PYTHON" ]]; then
    show_progress "Setting up OpenVoiceFlow (first run)..."

    # Create venv natively
    run python3 -m venv "$VENV_DIR" >>"$LOG_FILE" 2>&1

    # Install dependencies
    run "$VENV_DIR/bin/pip" install --upgrade pip -q >>"$LOG_FILE" 2>&1
    run "$VENV_DIR/bin/pip" install sounddevice numpy pynput rumps -q >>"$LOG_FILE" 2>&1

    if [[ $? -ne 0 ]]; then
        show_error "Failed to install Python packages.\n\nLog: $LOG_FILE"
        exit 1
    fi

    mkdir -p "$VOICEFLOW_HOME/models"
    mkdir -p "$LOG_DIR/logs"
fi

# Always sync latest source code into the venv
SITE_PKG=$(run "$PYTHON" -c "import site; print(site.getsitepackages()[0])" 2>/dev/null)
if [[ -n "$SITE_PKG" ]]; then
    rm -rf "$SITE_PKG/voiceflow" 2>/dev/null
    cp -R "$RESOURCES/voiceflow" "$SITE_PKG/" 2>/dev/null
fi

# --- Step 5: Download whisper model if missing ---
MODEL_FILE="$VOICEFLOW_HOME/models/ggml-base.en.bin"
if [[ ! -f "$MODEL_FILE" ]]; then
    show_progress "Downloading speech model (one-time, ~142 MB)..."
    mkdir -p "$VOICEFLOW_HOME/models"
    curl -L -o "$MODEL_FILE" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin" >>"$LOG_FILE" 2>&1
fi

# --- Step 6: Launch ---
CONFIG_FILE="$VOICEFLOW_HOME/config.json"

# First run — show onboarding wizard
if [[ ! -f "$CONFIG_FILE" ]]; then
    run "$PYTHON" -c "
from voiceflow.onboarding import run_onboarding
run_onboarding()
" >>"$LOG_FILE" 2>&1
fi

# Start menu bar app (or CLI fallback)
run "$PYTHON" -c "
try:
    from voiceflow.menubar import run_menubar
    run_menubar()
except Exception as e:
    print(f'Menu bar failed: {e}, falling back to CLI')
    from voiceflow.app import OpenVoiceFlow
    OpenVoiceFlow().run()
" >>"$LOG_FILE" 2>&1
LAUNCHER
chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"
echo "  ✅ Bootstrap launcher created"
echo "  ✅ ${APP_NAME}.app built"

# --- Build DMG ---
echo ""
echo "📀 Creating DMG..."

mkdir -p "$DMG_DIR"
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDBZ \
    "$DMG_PATH"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)

# Cleanup
rm -rf "$DMG_DIR"

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}✅ Build complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "  DMG: $DMG_PATH"
echo "  Size: $DMG_SIZE"
echo ""
echo "  ✅ No Rosetta needed (deps built natively on user's Mac)"
echo "  ✅ Works on macOS 12+ (Monterey and later)"
echo "  ✅ Works on Intel and Apple Silicon"
echo "  ✅ Auto-installs everything on first launch"
echo ""
echo "  Upload to GitHub:"
echo "    gh release delete v${VERSION} -y 2>/dev/null"
echo "    gh release create v${VERSION} \"$DMG_PATH\" \\"
echo "      --title \"OpenVoiceFlow v${VERSION}\" \\"
echo "      --notes \"Download, drag to Applications, launch. Everything installs automatically.\""
echo ""
echo "Done! 🎉"

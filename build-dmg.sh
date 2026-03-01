#!/bin/bash
# Build OpenVoiceFlow DMGs — one per architecture
# Produces:
#   dist/OpenVoiceFlow-VERSION-arm64.dmg   (Apple Silicon)
#   dist/OpenVoiceFlow-VERSION-x86_64.dmg  (Intel)
#
# The .app contains ONLY source code + a bash bootstrap launcher.
# Dependencies are installed NATIVELY on the user's Mac at first launch.
# No pre-compiled binaries = no Rosetta issues, no wrong-arch crashes.

set -e

GREEN='\033[0;32m'; NC='\033[0m'
APP_NAME="OpenVoiceFlow"
BUNDLE_ID="com.openvoiceflow.dictation"
VERSION=$(python3 -c "import re; v=re.search(r'version\s*=\s*\"(.+?)\"', open('pyproject.toml').read()); print(v.group(1) if v else '0.1.0')" 2>/dev/null || echo "0.1.0")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"

echo ""; echo "================================================"
echo "🔨 Building ${APP_NAME} v${VERSION} DMGs"
echo "================================================"

[[ "$(uname)" != "Darwin" ]] && echo "❌ Requires macOS." && exit 1

rm -rf "$DIST_DIR"; mkdir -p "$DIST_DIR"

build_dmg() {
    local ARCH=$1 ARCH_LABEL=$2
    echo ""; echo "📦 Building for $ARCH_LABEL ($ARCH)..."

    local APP_DIR="$DIST_DIR/build-$ARCH/${APP_NAME}.app"
    mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/voiceflow/llm"

    cp "$SCRIPT_DIR/voiceflow/"*.py "$APP_DIR/Contents/Resources/voiceflow/"
    cp "$SCRIPT_DIR/voiceflow/llm/"*.py "$APP_DIR/Contents/Resources/voiceflow/llm/"

    cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>OpenVoiceFlow needs microphone access to transcribe your voice.</string>
    <key>NSAppleEventsUsageDescription</key><string>OpenVoiceFlow needs Accessibility access to paste text at your cursor.</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>OVFTargetArch</key><string>${ARCH}</string>
</dict></plist>
PLIST

    # Capture vars before heredoc
    local LAUNCHER_ARCH="$ARCH"

    cat > "$APP_DIR/Contents/MacOS/${APP_NAME}" << LAUNCHER
#!/bin/bash
# OpenVoiceFlow bootstrap — installs deps natively, then launches

TARGET_ARCH="$LAUNCHER_ARCH"
APP_DIR="\$(cd "\$(dirname "\$0")/.." && pwd)"
RESOURCES="\$APP_DIR/Resources"
HOME_DIR="\$HOME/.openvoiceflow"
VENV="\$HOME_DIR/venv"
LOG_DIR="\$HOME/OpenVoiceFlow"
LOG="\$LOG_DIR/launcher.log"
PY="\$VENV/bin/python3"

mkdir -p "\$LOG_DIR" "\$HOME_DIR/models" "\$LOG_DIR/logs"
exec >> "\$LOG" 2>&1
echo "[\$(date)] Launching on \$(uname -m)"

notify() { osascript -e "display notification \"\$1\" with title \"OpenVoiceFlow\"" 2>/dev/null || true; }
fatal()  { osascript -e "display dialog \"\$1\" with title \"OpenVoiceFlow\" buttons {\"OK\"} default button \"OK\" with icon stop" 2>/dev/null; exit 1; }
alert()  { osascript -e "display dialog \"\$1\" with title \"OpenVoiceFlow\" buttons {\"OK\"} default button \"OK\" with icon note" 2>/dev/null; }

[[ -f /opt/homebrew/bin/brew ]] && eval "\$(/opt/homebrew/bin/brew shellenv)"
[[ -f /usr/local/bin/brew   ]] && eval "\$(/usr/local/bin/brew shellenv)"

ACTUAL="\$(uname -m)"
TRANSLATED="\$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)"

# Re-exec natively if running under Rosetta
[[ "\$TARGET_ARCH" == "arm64" && "\$ACTUAL" == "x86_64" && "\$TRANSLATED" == "1" ]] && exec arch -arm64 "\$0" "\$@"

# Wrong architecture check
if [[ "\$ACTUAL" != "\$TARGET_ARCH" && "\$TRANSLATED" != "1" ]]; then
    fatal "This build is for \${TARGET_ARCH} Macs. You have an \${ACTUAL} Mac.\n\nDownload the correct DMG from:\nhttps://github.com/shimoverse/openvoiceflow/releases"
fi

command -v python3 &>/dev/null || fatal "Python 3 not found. Run in Terminal: xcode-select --install"

if ! command -v brew &>/dev/null; then
    alert "Homebrew is needed (one-time). Terminal will open to install it.\n\nRelaunch OpenVoiceFlow when the Terminal says Done."
    osascript -e 'tell application "Terminal" to activate' \
        -e 'tell application "Terminal" to do script "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" && echo Done — close this window and relaunch OpenVoiceFlow"'
    exit 0
fi

if ! command -v whisper-cli &>/dev/null && ! command -v whisper-cpp &>/dev/null; then
    notify "Installing whisper-cpp..."
    brew install whisper-cpp || fatal "whisper-cpp install failed. Try: brew install whisper-cpp\nLog: \$LOG"
fi

if [[ ! -f "\$PY" ]]; then
    notify "First run setup (~1 min)..."
    python3 -m venv "\$VENV"
    "\$VENV/bin/pip" install -q --upgrade pip
    "\$VENV/bin/pip" install -q sounddevice numpy pynput rumps || fatal "Package install failed. Log: \$LOG"
fi

# Sync source code (supports future updates without reinstall)
SITE="\$("\$PY" -c "import site; print(site.getsitepackages()[0])" 2>/dev/null)"
[[ -n "\$SITE" ]] && rm -rf "\$SITE/voiceflow" 2>/dev/null && cp -R "\$RESOURCES/voiceflow" "\$SITE/"

MODEL="\$HOME_DIR/models/ggml-base.en.bin"
if [[ ! -f "\$MODEL" ]]; then
    notify "Downloading speech model (~142 MB, once)..."
    curl -L --progress-bar -o "\$MODEL" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
fi

"\$PY" -c "
try:
    from voiceflow.menubar import run_menubar
    run_menubar()
except Exception as e:
    print(f'Menu bar error: {e}')
    from voiceflow.app import OpenVoiceFlow
    OpenVoiceFlow().run()
"
LAUNCHER

    chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"

    local STAGING="$DIST_DIR/staging-$ARCH"
    local DMG="$DIST_DIR/${APP_NAME}-${VERSION}-${ARCH}.dmg"
    mkdir -p "$STAGING"
    cp -R "$APP_DIR" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "${APP_NAME} (${ARCH_LABEL})" -srcfolder "$STAGING" -ov -format UDBZ "$DMG" >/dev/null
    rm -rf "$STAGING" "$DIST_DIR/build-$ARCH"
    echo -e "  ${GREEN}✅ $DMG ($(du -h "$DMG" | cut -f1))${NC}"
}

build_dmg "arm64"  "Apple Silicon"
build_dmg "x86_64" "Intel"

echo ""
echo -e "${GREEN}✅ Done! Upload to GitHub:${NC}"
echo ""
echo "  gh release create v${VERSION} \\"
echo "    dist/${APP_NAME}-${VERSION}-arm64.dmg \\"
echo "    dist/${APP_NAME}-${VERSION}-x86_64.dmg \\"
echo "    --title \"OpenVoiceFlow v${VERSION}\" \\"
echo '    --notes "**Apple Silicon (M1/M2/M3/M4):** `OpenVoiceFlow-arm64.dmg`
**Intel Mac:** `OpenVoiceFlow-x86_64.dmg`

Drag to Applications, launch, done. Everything installs automatically."'

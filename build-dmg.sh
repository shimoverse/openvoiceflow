#!/bin/bash
# Build OpenVoiceFlow DMGs — one per architecture
# Produces:
#   dist/OpenVoiceFlow-VERSION-arm64.dmg   (Apple Silicon)
#   dist/OpenVoiceFlow-VERSION-x86_64.dmg  (Intel)
#
# The .app contains ONLY source code + a bash bootstrap launcher.
# Dependencies are installed NATIVELY on the user's Mac at first launch.
# No pre-compiled binaries = no Rosetta issues, no wrong-arch crashes.

set -euo pipefail

GREEN='\033[0;32m'; NC='\033[0m'
APP_NAME="OpenVoiceFlow"
BUNDLE_ID="com.openvoiceflow.dictation"
VERSION=$(python3 -c "import re; v=re.search(r'version\s*=\s*\"(.+?)\"', open('pyproject.toml').read()); print(v.group(1) if v else '0.1.0')" 2>/dev/null || echo "0.1.0")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
BUILD_ONLY_ARCH="${OVF_BUILD_ARCH_ONLY:-}"
LOCAL_ONLY_MODE="${OVF_LOCAL_ONLY:-0}"

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
PY_RUN="\$VENV/bin/OpenVoiceFlow"

mkdir -p "\$LOG_DIR" "\$HOME_DIR/models" "\$LOG_DIR/logs"
exec >> "\$LOG" 2>&1
echo "[\$(date)] Launching on \$(uname -m)"

notify() { osascript -e "display notification \"\$1\" with title \"OpenVoiceFlow\"" 2>/dev/null || true; }
fatal()  { osascript -e "display dialog \"\$1\" with title \"OpenVoiceFlow\" buttons {\"OK\"} default button \"OK\" with icon stop" 2>/dev/null; exit 1; }
alert()  { osascript -e "display dialog \"\$1\" with title \"OpenVoiceFlow\" buttons {\"OK\"} default button \"OK\" with icon note" 2>/dev/null; }
ask_permission_help() {
    osascript -e 'display dialog "OpenVoiceFlow needs permissions to work.\n\nOpen Accessibility settings now?" with title "OpenVoiceFlow Permissions" buttons {"Later", "Open Settings"} default button "Open Settings" with icon note' 2>/dev/null
}

ask_permissions_menu() {
    osascript -e 'display dialog "OpenVoiceFlow startup checks detected missing permissions. Choose which settings screen to open now." with title "OpenVoiceFlow Permissions" buttons {"Continue", "Microphone", "Accessibility"} default button "Accessibility" with icon note' 2>/dev/null
}

[[ -f /opt/homebrew/bin/brew ]] && eval "\$(/opt/homebrew/bin/brew shellenv)"
[[ -f /usr/local/bin/brew   ]] && eval "\$(/usr/local/bin/brew shellenv)"

ACTUAL="\$(uname -m)"
TRANSLATED="\$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)"

# Re-exec natively if running under Rosetta
[[ "\$TARGET_ARCH" == "arm64" && "\$ACTUAL" == "x86_64" && "\$TRANSLATED" == "1" ]] && exec arch -arm64 "\$0" "\$@"

# Wrong architecture check
if [[ "\$ACTUAL" != "\$TARGET_ARCH" && "\$TRANSLATED" != "1" ]]; then
    fatal "This build is for \${TARGET_ARCH} Macs. You have an \${ACTUAL} Mac.\n\nDownload the correct DMG from:\nhttps://openvoiceflow.vercel.app/download.html"
fi

# Fast-path smoke mode for local build verification.
if [[ "\${OVF_SMOKE_TEST:-0}" == "1" ]]; then
    echo "[OVF_SMOKE_TEST] launcher preflight passed on \$ACTUAL"
    exit 0
fi

# Prevent concurrent first-launch bootstraps from clobbering each other.
# Must run after any Rosetta re-exec logic above.
BOOTSTRAP_LOCK_DIR="\$HOME_DIR/.bootstrap.lock"
BOOTSTRAP_LOCK_PID="\$BOOTSTRAP_LOCK_DIR/pid"

_acquire_bootstrap_lock() {
    if mkdir "\$BOOTSTRAP_LOCK_DIR" 2>/dev/null; then
        echo "\$$" > "\$BOOTSTRAP_LOCK_PID"
        return 0
    fi

    # Stale lock recovery: clear lock if owner pid is gone.
    if [[ -f "\$BOOTSTRAP_LOCK_PID" ]]; then
        local owner_pid
        owner_pid="\$(cat "\$BOOTSTRAP_LOCK_PID" 2>/dev/null || true)"
        if [[ -n "\$owner_pid" ]] && ps -p "\$owner_pid" >/dev/null 2>&1; then
            notify "OpenVoiceFlow is already starting. Please wait."
            return 1
        fi
    fi

    rm -rf "\$BOOTSTRAP_LOCK_DIR" >/dev/null 2>&1 || true
    if mkdir "\$BOOTSTRAP_LOCK_DIR" 2>/dev/null; then
        echo "\$$" > "\$BOOTSTRAP_LOCK_PID"
        return 0
    fi

    notify "OpenVoiceFlow is already starting. Please wait."
    return 1
}

if ! _acquire_bootstrap_lock; then
    exit 0
fi

_release_bootstrap_lock() {
    rm -f "\$BOOTSTRAP_LOCK_PID" >/dev/null 2>&1 || true
    rmdir "\$BOOTSTRAP_LOCK_DIR" >/dev/null 2>&1 || true
}
trap _release_bootstrap_lock EXIT INT TERM

command -v python3 &>/dev/null || fatal "Python 3 not found. Run in Terminal: xcode-select --install"

if ! command -v brew &>/dev/null; then
    alert "Homebrew is needed (one-time). Terminal will open to install it.\n\nRelaunch OpenVoiceFlow when the Terminal says Done."
    osascript -e 'tell application "Terminal" to activate' \
        -e 'tell application "Terminal" to do script "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" && echo Done - close this window and relaunch OpenVoiceFlow"'
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
    "\$VENV/bin/pip" install -q sounddevice numpy pynput rumps pyobjc-framework-Cocoa || fatal "Package install failed. Log: \$LOG"
fi

# Runtime shim name helps users find the process in permission panes.
rm -f "\$PY_RUN" >/dev/null 2>&1 || true
cp "\$PY" "\$PY_RUN"
chmod +x "\$PY_RUN"

notify "OpenVoiceFlow is launching..."

# Sync source code (supports future updates without reinstall)
SITE="\$("\$PY" -c "import site; print(site.getsitepackages()[0])" 2>/dev/null)"
[[ -n "\$SITE" ]] && rm -rf "\$SITE/voiceflow" 2>/dev/null && cp -R "\$RESOURCES/voiceflow" "\$SITE/"

MODEL="\$HOME_DIR/models/ggml-base.en.bin"
if [[ ! -f "\$MODEL" ]]; then
    notify "Downloading speech model (~142 MB, once)..."
    curl -L --progress-bar -o "\$MODEL" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
fi

AX_OK="\$("\$PY_RUN" - <<'PY'
try:
    from ApplicationServices import AXIsProcessTrusted
    print("1" if AXIsProcessTrusted() else "0")
except Exception:
    print("0")
PY
)"

if [[ "\$AX_OK" != "1" ]]; then
    if ask_permission_help | grep -q "Open Settings"; then
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true
    fi
fi

# Trigger a one-time microphone permission check so OpenVoiceFlow appears
# in the Microphone privacy list before first dictation.
"\$PY_RUN" - <<'PY' >/dev/null 2>&1 || true
try:
    import sounddevice as sd
    # Requesting a tiny recording buffer prompts mic permission if needed.
    rec = sd.rec(1, samplerate=8000, channels=1, dtype='float32')
    sd.wait()
except Exception:
    pass
PY

PERM_CHOICE="\$(ask_permissions_menu || true)"
if [[ "\$PERM_CHOICE" == *"Accessibility"* ]]; then
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true
elif [[ "\$PERM_CHOICE" == *"Microphone"* ]]; then
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone" >/dev/null 2>&1 || true
fi

"\$PY_RUN" -c "
import json
import os


cfg_path = os.path.expanduser('~/.openvoiceflow/config.json')


def _load_cfg():
    if not os.path.exists(cfg_path):
        return {}
    try:
        with open(cfg_path) as f:
            return json.load(f)
    except Exception:
        return {}


def _save_cfg(cfg):
    os.makedirs(os.path.dirname(cfg_path), exist_ok=True)
    with open(cfg_path, 'w') as f:
        json.dump(cfg, f, indent=2)
    try:
        os.chmod(cfg_path, 0o600)
    except OSError:
        pass


def _needs_setup(cfg):
    backend = cfg.get('llm_backend', '')
    has_key = any(cfg.get(f'{b}_api_key') for b in ['openrouter', 'openai', 'anthropic', 'groq'])
    return not (has_key or backend in ['ollama', 'none'])


cfg = _load_cfg()
needs_setup = _needs_setup(cfg)

if needs_setup:
    try:
        from voiceflow.onboarding import run_onboarding
        run_onboarding()
    except Exception as e:
        print(f'Onboarding error: {e}')

    # If onboarding could not complete (for example no tkinter),
    # fall back to local raw mode so first launch still succeeds.
    cfg = _load_cfg()
    if _needs_setup(cfg):
        cfg['llm_backend'] = 'none'
        _save_cfg(cfg)
        print('No API key configured. Falling back to local mode (backend=none).')

try:
    from voiceflow.menubar import run_menubar
    run_menubar()
except Exception as e:
    import traceback
    print(f'Menu bar error: {e}')
    traceback.print_exc()
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

if [[ -n "$BUILD_ONLY_ARCH" ]]; then
    case "$BUILD_ONLY_ARCH" in
        arm64)
            build_dmg "arm64" "Apple Silicon"
            ;;
        x86_64)
            build_dmg "x86_64" "Intel"
            ;;
        *)
            echo "❌ Unsupported OVF_BUILD_ARCH_ONLY: $BUILD_ONLY_ARCH"
            exit 1
            ;;
    esac
else
    build_dmg "arm64"  "Apple Silicon"
    build_dmg "x86_64" "Intel"
fi

echo ""
if [[ "$LOCAL_ONLY_MODE" == "1" ]]; then
    echo -e "${GREEN}✅ Done (local-only mode).${NC}"
else
    echo -e "${GREEN}✅ Done! Upload to GitHub:${NC}"
    echo ""
    echo "  gh release create v${VERSION} \\"
    echo "    dist/${APP_NAME}-${VERSION}-arm64.dmg \\"
    echo "    dist/${APP_NAME}-${VERSION}-x86_64.dmg \\"
    echo "    --title \"OpenVoiceFlow v${VERSION}\" \\"
    echo '    --notes "**Apple Silicon (M1/M2/M3/M4):** `OpenVoiceFlow-arm64.dmg`
**Intel Mac:** `OpenVoiceFlow-x86_64.dmg`

Drag to Applications, launch, done. Everything installs automatically."'
fi

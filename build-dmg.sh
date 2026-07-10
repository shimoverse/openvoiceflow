#!/bin/bash
# Build OpenVoiceFlow DMGs — one per architecture
# Produces:
#   dist/OpenVoiceFlow-VERSION-arm64.dmg   (Apple Silicon)
#   dist/OpenVoiceFlow-VERSION-x86_64.dmg  (Intel)
#
# The .app contains a tiny native permissions launcher plus source code and a
# bash bootstrap. Python dependencies are installed natively on first launch.

set -euo pipefail

GREEN='\033[0;32m'; NC='\033[0m'
APP_NAME="OpenVoiceFlow"
BUNDLE_ID="com.openvoiceflow.dictation"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Read the version from the repo's own pyproject.toml (not the CWD's) and
# fail loudly rather than silently stamping a fallback version on the DMG.
VERSION=$(python3 -c "import re; v=re.search(r'version\s*=\s*\"(.+?)\"', open('$SCRIPT_DIR/pyproject.toml').read()); print(v.group(1))") || {
    echo "❌ Could not read version from $SCRIPT_DIR/pyproject.toml"; exit 1;
}
DIST_DIR="$SCRIPT_DIR/dist"
BUILD_ONLY_ARCH="${OVF_BUILD_ARCH_ONLY:-}"
LOCAL_ONLY_MODE="${OVF_LOCAL_ONLY:-0}"
ICON_FILE="$SCRIPT_DIR/assets/OpenVoiceFlow.icns"
ENTITLEMENTS_FILE="$SCRIPT_DIR/assets/OpenVoiceFlow.entitlements"
LAUNCHER_SOURCE="$SCRIPT_DIR/packaging/OpenVoiceFlowLauncher.m"
SIGN_IDENTITY="${OVF_SIGN_IDENTITY:-}"
NOTARIZE="${OVF_NOTARIZE:-0}"
NOTARY_PROFILE="${OVF_NOTARY_PROFILE:-}"
NOTARY_KEY="${OVF_NOTARY_KEY:-}"
NOTARY_KEY_ID="${OVF_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${OVF_NOTARY_ISSUER_ID:-}"

echo ""; echo "================================================"
echo "🔨 Building ${APP_NAME} v${VERSION} DMGs"
echo "================================================"

[[ "$(uname)" != "Darwin" ]] && echo "❌ Requires macOS." && exit 1
[[ ! -f "$ICON_FILE" ]] && echo "❌ Missing app icon: $ICON_FILE" && exit 1
[[ ! -f "$ENTITLEMENTS_FILE" ]] && echo "❌ Missing app entitlements: $ENTITLEMENTS_FILE" && exit 1
[[ ! -f "$LAUNCHER_SOURCE" ]] && echo "❌ Missing native launcher: $LAUNCHER_SOURCE" && exit 1

rm -rf "$DIST_DIR"; mkdir -p "$DIST_DIR"

sign_app_if_requested() {
    local APP_DIR=$1

    if [[ -z "$SIGN_IDENTITY" ]]; then
        echo "  ⚠️  OVF_SIGN_IDENTITY not set; building an unsigned app."
        return 0
    fi

    echo "  🔏 Signing app with: $SIGN_IDENTITY"
    xattr -cr "$APP_DIR" >/dev/null 2>&1 || true
    /usr/bin/codesign --force --timestamp --options runtime \
        --entitlements "$ENTITLEMENTS_FILE" --sign "$SIGN_IDENTITY" "$APP_DIR"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
}

notarize_dmg_if_requested() {
    local DMG=$1

    if [[ "$NOTARIZE" != "1" ]]; then
        echo "  ⚠️  OVF_NOTARIZE=1 not set; skipping Apple notarization."
        return 0
    fi

    if [[ -z "$SIGN_IDENTITY" ]]; then
        echo "❌ OVF_NOTARIZE=1 requires OVF_SIGN_IDENTITY."
        exit 1
    fi

    local ARGS=()
    if [[ -n "$NOTARY_PROFILE" ]]; then
        ARGS=(--keychain-profile "$NOTARY_PROFILE")
    elif [[ -n "$NOTARY_KEY" && -n "$NOTARY_KEY_ID" && -n "$NOTARY_ISSUER_ID" ]]; then
        ARGS=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
    else
        echo "❌ OVF_NOTARIZE=1 requires OVF_NOTARY_PROFILE or OVF_NOTARY_KEY + OVF_NOTARY_KEY_ID + OVF_NOTARY_ISSUER_ID."
        exit 1
    fi

    echo "  🔏 Signing DMG..."
    /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    /usr/bin/codesign --verify --verbose=2 "$DMG"

    echo "  📮 Submitting DMG to Apple notarization..."
    /usr/bin/xcrun notarytool submit "$DMG" "${ARGS[@]}" --wait
    /usr/bin/xcrun stapler staple "$DMG"
    /usr/bin/xcrun stapler validate "$DMG"
    # DMGs need the primary-signature context for Gatekeeper assessment;
    # otherwise spctl can return "rejected: Insufficient Context" even when
    # Apple notarization and stapling succeeded.
    /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
}

build_dmg() {
    local ARCH=$1 ARCH_LABEL=$2
    echo ""; echo "📦 Building for $ARCH_LABEL ($ARCH)..."

    local APP_DIR="$DIST_DIR/build-$ARCH/${APP_NAME}.app"
    mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/voiceflow/llm"

    cp "$SCRIPT_DIR/voiceflow/"*.py "$APP_DIR/Contents/Resources/voiceflow/"
    cp "$SCRIPT_DIR/voiceflow/llm/"*.py "$APP_DIR/Contents/Resources/voiceflow/llm/"
    cp "$ICON_FILE" "$APP_DIR/Contents/Resources/OpenVoiceFlow.icns"

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
    <key>CFBundleIconFile</key><string>OpenVoiceFlow.icns</string>
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

    local BOOTSTRAP="$APP_DIR/Contents/Resources/launcher.sh"
    cat > "$BOOTSTRAP" << LAUNCHER
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
PY_RUN="\$PY"

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

# A completion marker (not the venv python) gates the bootstrap: if pip
# failed after venv creation, checking for \$PY alone would skip the install
# forever and every launch would die on missing imports.
DEPS_MARKER="\$VENV/.ovf-deps-installed"
if [[ ! -f "\$PY" || ! -f "\$DEPS_MARKER" ]]; then
    notify "First run setup (~1 min)..."
    python3 -m venv "\$VENV"
    "\$VENV/bin/pip" install -q --upgrade pip
    "\$VENV/bin/pip" install -q sounddevice numpy pynput rumps pyobjc-framework-Cocoa || fatal "Package install failed. Relaunch OpenVoiceFlow to retry. Log: \$LOG"
    touch "\$DEPS_MARKER"
fi

notify "OpenVoiceFlow is launching..."

# Sync source code (supports future updates without reinstall)
SITE="\$("\$PY" -c "import site; print(site.getsitepackages()[0])" 2>/dev/null)"
[[ -n "\$SITE" ]] && rm -rf "\$SITE/voiceflow" 2>/dev/null && cp -R "\$RESOURCES/voiceflow" "\$SITE/"

# --fail + temp-file + move: an HTTP error page or interrupted transfer must
# never be left at \$MODEL, where it would be treated as a valid model forever.
MODEL="\$HOME_DIR/models/ggml-base.en.bin"
if [[ ! -f "\$MODEL" ]]; then
    notify "Downloading speech model (~142 MB, once)..."
    curl -fL --retry 3 --progress-bar -o "\$MODEL.download" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin" \
        || { rm -f "\$MODEL.download"; fatal "Speech model download failed. Check your internet connection and relaunch OpenVoiceFlow. Log: \$LOG"; }
    mv "\$MODEL.download" "\$MODEL"
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

    chmod +x "$BOOTSTRAP"
    /usr/bin/clang -fobjc-arc -fblocks -arch "$ARCH" -mmacosx-version-min=12.0 \
        "$LAUNCHER_SOURCE" -framework Cocoa -framework AVFoundation \
        -framework ApplicationServices -o "$APP_DIR/Contents/MacOS/${APP_NAME}"
    sign_app_if_requested "$APP_DIR"

    local STAGING="$DIST_DIR/staging-$ARCH"
    local DMG="$DIST_DIR/${APP_NAME}-${VERSION}-${ARCH}.dmg"
    mkdir -p "$STAGING"
    cp -R "$APP_DIR" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "${APP_NAME} (${ARCH_LABEL})" -srcfolder "$STAGING" -ov -format UDBZ "$DMG" >/dev/null
    notarize_dmg_if_requested "$DMG"
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
    echo "    --notes \"**Apple Silicon (M1/M2/M3/M4):** \\\`${APP_NAME}-${VERSION}-arm64.dmg\\\`
**Intel Mac:** \\\`${APP_NAME}-${VERSION}-x86_64.dmg\\\`

Drag to Applications, launch, done. Everything installs automatically.\""
fi

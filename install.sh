#!/bin/bash
# OpenVoiceFlow Installer
# Run: curl -fsSL https://raw.githubusercontent.com/shimoverse/openvoiceflow/main/install.sh | bash
#   OR: bash install.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "================================================"
echo "🎙️  OpenVoiceFlow Installer"
echo "================================================"
echo ""

# --- Check macOS ---
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}❌ OpenVoiceFlow only supports macOS.${NC}"
    exit 1
fi

# --- Homebrew (BUG-015 fix: support both arm64 and Intel Homebrew paths) ---
[[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ -f /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"

if ! command -v brew &>/dev/null; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [[ -f /usr/local/bin/brew ]] && eval "$(/usr/local/bin/brew shellenv)"
fi

# --- whisper.cpp ---
if ! command -v whisper-cli &>/dev/null && ! command -v whisper-cpp &>/dev/null; then
    echo "📦 Installing whisper.cpp..."
    brew install whisper-cpp
fi
echo -e "${GREEN}✅ whisper.cpp installed${NC}"

# --- Python venv ---
VOICEFLOW_HOME="$HOME/.openvoiceflow"
VENV_DIR="$VOICEFLOW_HOME/venv"
mkdir -p "$VOICEFLOW_HOME/models" "$VOICEFLOW_HOME/logs"

if [[ ! -d "$VENV_DIR" ]]; then
    echo "🐍 Creating Python environment..."
    python3 -m venv "$VENV_DIR"
fi

echo "📦 Installing Python packages..."
"$VENV_DIR/bin/pip" install -q --upgrade pip
"$VENV_DIR/bin/pip" install -q sounddevice numpy pynput rumps
echo -e "${GREEN}✅ Python environment ready${NC}"

# --- Install OpenVoiceFlow (BUG-006 fix: clone repo if running via curl-pipe) ---
# Use the [all] extra so users get the overlay HUD (pyobjc-framework-Cocoa)
# and menubar (rumps) features without a second install step.
# The repo check must confirm it's actually THIS project: under curl|bash
# $0 is "bash", dirname gives ".", and blindly running `pip install .` would
# install whatever unrelated project the user's CWD happens to contain.
echo "📥 Installing OpenVoiceFlow..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
CLONE_TMP=""
cleanup_clone() {
    [[ -n "$CLONE_TMP" ]] && rm -rf "$CLONE_TMP"
}
trap cleanup_clone EXIT
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/pyproject.toml" ]] \
        && grep -q '^name = "openvoiceflow"' "$SCRIPT_DIR/pyproject.toml"; then
    # Running from a cloned repo directory
    "$VENV_DIR/bin/pip" install -q "$SCRIPT_DIR[all]"
else
    # Running via curl-pipe — no source directory available; clone first
    CLONE_TMP="$(mktemp -d)"
    REPO_DIR="$CLONE_TMP/openvoiceflow"
    git clone --depth=1 https://github.com/shimoverse/openvoiceflow.git "$REPO_DIR"
    "$VENV_DIR/bin/pip" install -q "$REPO_DIR[all]"
fi
echo -e "${GREEN}✅ OpenVoiceFlow installed${NC}"

# --- Download whisper model ---
# --fail keeps curl from saving an HTML error page as the model, and the
# temp-file + move means an interrupted download is never mistaken for a
# valid model on the next run.
MODEL_FILE="$VOICEFLOW_HOME/models/ggml-base.en.bin"
if [[ ! -f "$MODEL_FILE" ]]; then
    echo "⬇️  Downloading Whisper model (base.en, ~142 MB)..."
    curl -fL --retry 3 -o "$MODEL_FILE.download" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
    mv "$MODEL_FILE.download" "$MODEL_FILE"
fi
echo -e "${GREEN}✅ Whisper model ready${NC}"

# --- Create shell command ---
# Exec the pip-installed console script ($VENV_DIR/bin/openvoiceflow) rather
# than reinventing a module-style invocation. The earlier `python3 -m
# openvoiceflow` form was broken: the Python package is named `voiceflow`.
BINDIR="$HOME/.local/bin"
mkdir -p "$BINDIR"
cat > "$BINDIR/openvoiceflow" << EOF
#!/bin/bash
exec "$VENV_DIR/bin/openvoiceflow" "\$@"
EOF
chmod +x "$BINDIR/openvoiceflow"

# Add to PATH if needed. Create ~/.zshrc when no rc file exists at all —
# a fresh macOS account has none, and skipping would leave `openvoiceflow`
# unfound in every new terminal despite the success message below.
if [[ ":$PATH:" != *":$BINDIR:"* ]]; then
    if [[ ! -f "$HOME/.zshrc" && ! -f "$HOME/.bashrc" ]]; then
        touch "$HOME/.zshrc"
    fi
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        if [[ -f "$rc" ]] && ! grep -q '.local/bin' "$rc"; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
        fi
    done
    export PATH="$BINDIR:$PATH"
fi

# --- Setup wizard ---
# BUG-014 fix: check if ANY backend key is set, or if backend is ollama/none
echo ""
echo "================================================"
echo "🔧 Quick Setup"
echo "================================================"
echo ""

CONFIG_FILE="$VOICEFLOW_HOME/config.json"
needs_setup=true

if [[ -f "$CONFIG_FILE" ]]; then
    # Check if any API key is set OR backend is ollama/none
    if python3 -c "
import json, sys
try:
    cfg = json.load(open('$CONFIG_FILE'))
    backend = cfg.get('llm_backend', '')
    has_key = any(cfg.get(f'{b}_api_key') for b in ['openrouter','openai','anthropic','groq'])
    if has_key or backend in ['ollama','none']:
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        needs_setup=false
    fi
fi

if [[ "$needs_setup" == "true" ]]; then
    echo "OpenVoiceFlow needs an LLM API key for transcript cleanup."
    echo ""
    echo "  FREE options:"
    echo "    OpenRouter (Gemma 4) — https://openrouter.ai/keys"
    echo "    Groq    — https://console.groq.com/keys"
    echo "    Ollama  — https://ollama.com (fully local, no key needed)"
    echo ""
    # Under `curl ... | bash` stdin is the script itself, so `read` would
    # consume script lines as "answers". Read from the terminal directly,
    # and skip the wizard when no terminal is available.
    if [[ -r /dev/tty ]]; then
        read -r -p "  Which backend? [openrouter/openai/anthropic/groq/ollama]: " BACKEND < /dev/tty
        BACKEND="${BACKEND:-openrouter}"

        "$BINDIR/openvoiceflow" --backend "$BACKEND"

        if [[ "$BACKEND" != "ollama" && "$BACKEND" != "none" ]]; then
            # -s: don't echo the key; pass it via stdin so it never appears
            # in `ps` output or shell history.
            read -r -s -p "  Paste your API key (input hidden): " API_KEY < /dev/tty
            echo ""
            if [[ -n "$API_KEY" ]]; then
                printf '%s\n' "$API_KEY" | "$BINDIR/openvoiceflow" --set-key "$BACKEND" -
            fi
        fi
    else
        echo "  (No interactive terminal — run 'openvoiceflow --setup' afterwards.)"
    fi
fi

# --- Done ---
echo ""
echo "================================================"
echo -e "${GREEN}✅ OpenVoiceFlow installed successfully!${NC}"
echo "================================================"
echo ""
echo "  Start:       openvoiceflow"
echo "  Menu bar:    openvoiceflow --menubar"
echo "  Test:        openvoiceflow --test"
echo "  Config:      openvoiceflow --setup"
echo ""
echo "  Hold [Right Cmd] → Speak → Release → Text appears at cursor"
echo ""
echo -e "${YELLOW}⚠️  First time: grant Accessibility permission when prompted${NC}"
echo "  System Settings → Privacy & Security → Accessibility → Terminal"
echo ""

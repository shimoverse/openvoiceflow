#!/bin/bash
# OpenOpenVoiceFlow Installer
# Run: curl -fsSL https://raw.githubusercontent.com/shimoverse-ops/openvoiceflow/main/install.sh | bash
#   OR: bash install.sh

set -e

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

# --- Homebrew ---
if ! command -v brew &>/dev/null; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# --- whisper.cpp ---
if ! command -v whisper-cli &>/dev/null && ! command -v whisper-cpp &>/dev/null; then
    echo "📦 Installing whisper.cpp..."
    eval "$(/opt/homebrew/bin/brew shellenv)"
    brew install whisper-cpp
fi
echo -e "${GREEN}✅ whisper.cpp installed${NC}"

# --- Python venv ---
VOICEFLOW_HOME="$HOME/.openvoiceflow"
VENV_DIR="$VOICEFLOW_HOME/venv"
mkdir -p "$VOICEFLOW_HOME/models" "$HOME/OpenVoiceFlow/logs"

if [[ ! -d "$VENV_DIR" ]]; then
    echo "🐍 Creating Python environment..."
    python3 -m venv "$VENV_DIR"
fi

echo "📦 Installing Python packages..."
"$VENV_DIR/bin/pip" install -q --upgrade pip
"$VENV_DIR/bin/pip" install -q sounddevice numpy pynput rumps
echo -e "${GREEN}✅ Python environment ready${NC}"

# --- Install OpenVoiceFlow ---
echo "📥 Installing OpenVoiceFlow..."
"$VENV_DIR/bin/pip" install -q .
echo -e "${GREEN}✅ OpenVoiceFlow installed${NC}"

# --- Download whisper model ---
MODEL_FILE="$VOICEFLOW_HOME/models/ggml-base.en.bin"
if [[ ! -f "$MODEL_FILE" ]]; then
    echo "⬇️  Downloading Whisper model (base.en, ~142 MB)..."
    curl -L -o "$MODEL_FILE" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
fi
echo -e "${GREEN}✅ Whisper model ready${NC}"

# --- Create shell command ---
BINDIR="$HOME/.local/bin"
mkdir -p "$BINDIR"
cat > "$BINDIR/openvoiceflow" << EOF
#!/bin/bash
exec "$VENV_DIR/bin/python3" -m openvoiceflow "\$@"
EOF
chmod +x "$BINDIR/openvoiceflow"

# Add to PATH if needed
if [[ ":$PATH:" != *":$BINDIR:"* ]]; then
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        if [[ -f "$rc" ]] && ! grep -q '.local/bin' "$rc"; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
        fi
    done
    export PATH="$BINDIR:$PATH"
fi

# --- Setup wizard ---
echo ""
echo "================================================"
echo "🔧 Quick Setup"
echo "================================================"
echo ""

CONFIG_FILE="$VOICEFLOW_HOME/config.json"
if [[ ! -f "$CONFIG_FILE" ]] || ! python3 -c "import json; assert json.load(open('$CONFIG_FILE')).get('gemini_api_key')" 2>/dev/null; then
    echo "OpenVoiceFlow needs an LLM API key for transcript cleanup."
    echo ""
    echo "  FREE options:"
    echo "    Gemini  — https://aistudio.google.com/apikey"
    echo "    Groq    — https://console.groq.com/keys"
    echo "    Ollama  — https://ollama.com (fully local, no key needed)"
    echo ""
    read -p "  Which backend? [gemini/openai/anthropic/groq/ollama]: " BACKEND
    BACKEND="${BACKEND:-gemini}"

    "$BINDIR/openvoiceflow" --backend "$BACKEND"

    if [[ "$BACKEND" != "ollama" && "$BACKEND" != "none" ]]; then
        read -p "  Paste your API key: " API_KEY
        if [[ -n "$API_KEY" ]]; then
            "$BINDIR/openvoiceflow" --set-key "$BACKEND" "$API_KEY"
        fi
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

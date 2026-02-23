# 🎙️ OpenVoiceFlow

**Free, open-source voice dictation for macOS.**

Hold a key → speak → release → clean text appears at your cursor. Anywhere.

OpenVoiceFlow combines **local** speech-to-text (whisper.cpp) with **LLM-powered cleanup** to remove filler words, fix grammar, and handle corrections — giving you polished text from messy speech.

> 💡 Built as a free alternative to [Wispr Flow](https://wisprflow.ai/) ($144/year) and [Superwhisper](https://superwhisper.com) ($85/year). OpenVoiceFlow costs **~$0–3/year**.

---

## How It Works

```
🎤 You speak        →  "um hey can you schedule a meeting for uh Thursday no wait Friday"
🔄 Whisper (local)  →  "um hey can you schedule a meeting for uh Thursday no wait Friday"
✨ LLM cleanup      →  "Hey, can you schedule a meeting for Friday?"
📋 Auto-paste       →  Text appears at your cursor in any app
```

**Two-stage pipeline:**
1. **whisper.cpp** runs locally on your Mac (Metal-accelerated on Apple Silicon). Your audio never leaves your machine.
2. **LLM cleanup** (your choice of provider) removes fillers, fixes grammar, handles corrections like "no wait" and "I mean".

## Installation

### Option 1: DMG Installer (easiest)

Download the latest `.dmg` from [Releases](https://github.com/shimoverse-ops/openvoiceflow/releases), open it, and drag **OpenVoiceFlow** to your Applications folder. On first launch, a setup wizard guides you through choosing your AI backend and entering an API key.

### Option 2: Quick Install (terminal)

```bash
git clone https://github.com/shimoverse-ops/openvoiceflow.git
cd openvoiceflow
bash install.sh
```

### Option 3: Manual Install

```bash
# 1. Install whisper.cpp
brew install whisper-cpp

# 2. Clone and set up
git clone https://github.com/shimoverse-ops/openvoiceflow.git
cd openvoiceflow
python3 -m venv ~/.openvoiceflow/venv
~/.openvoiceflow/venv/bin/pip install -e ".[all]"

# 3. Download a whisper model
mkdir -p ~/.openvoiceflow/models
curl -L -o ~/.openvoiceflow/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

# 4. Add your API key
openvoiceflow --set-key gemini YOUR_KEY_HERE

# 5. Run
openvoiceflow
```

## Usage

```bash
# First run — launches GUI setup wizard automatically
openvoiceflow

# Menu bar mode (icon in top bar)
openvoiceflow --menubar

# Re-run GUI setup wizard anytime
openvoiceflow --onboarding

# Test pipeline
openvoiceflow --test

# Interactive CLI setup
openvoiceflow --setup
```

**Default hotkey:** Hold `Right Command` → speak → release.

Grant **Accessibility** permission when macOS asks (System Settings → Privacy & Security → Accessibility).

## LLM Backends

OpenVoiceFlow supports 5 LLM backends for transcript cleanup. Choose based on your priorities:

| Backend | Cost | Speed | Privacy | Setup |
|---------|------|-------|---------|-------|
| **Gemini Flash** | ~$3/year | Fast | Cloud | `--set-key gemini KEY` |
| **Groq** | Free tier | Fastest | Cloud | `--set-key groq KEY` |
| **OpenAI** | ~$5/year | Fast | Cloud | `--set-key openai KEY` |
| **Claude** | ~$8/year | Fast | Cloud | `--set-key anthropic KEY` |
| **Ollama** | $0 forever | Slower | **Fully local** | Install [Ollama](https://ollama.com) |
| **None** | $0 | Instant | Local | Raw transcripts only |

### Switch backends

```bash
# Use Gemini (cheapest cloud option)
openvoiceflow --backend gemini
openvoiceflow --set-key gemini YOUR_KEY

# Use Ollama (fully local, completely free)
openvoiceflow --backend ollama
# Make sure Ollama is running: ollama serve

# Use Groq (fast, generous free tier)
openvoiceflow --backend groq
openvoiceflow --set-key groq YOUR_KEY

# Disable LLM cleanup (raw whisper output only)
openvoiceflow --backend none
```

### Getting API Keys

| Provider | Free Tier | Get Key |
|----------|-----------|---------|
| Gemini | 1000 req/day | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) |
| Groq | 30 req/min | [console.groq.com/keys](https://console.groq.com/keys) |
| OpenAI | Pay-as-you-go | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| Anthropic | Pay-as-you-go | [console.anthropic.com](https://console.anthropic.com/) |
| Ollama | ∞ (local) | [ollama.com](https://ollama.com) |

## Configuration

Config lives at `~/.openvoiceflow/config.json`:

```json
{
  "hotkey": "right_cmd",
  "whisper_model": "base.en",
  "llm_backend": "gemini",
  "gemini_api_key": "your-key-here",
  "sound_feedback": true,
  "auto_paste": true,
  "log_transcripts": true
}
```

### Hotkey Options

`right_cmd` · `right_alt` · `left_alt` · `f5` · `f6` · `f7` · `f8`

```bash
openvoiceflow --hotkey right_alt
```

### Whisper Models

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| `tiny.en` | 75 MB | Fastest | Good for quick notes |
| `base.en` | 142 MB | Fast | **Recommended** |
| `small.en` | 466 MB | Medium | More accurate |
| `medium.en` | 1.5 GB | Slower | High accuracy |

```bash
openvoiceflow --model small.en
```

## Running in Background

### Option A: nohup (simple)

```bash
nohup ~/.openvoiceflow/venv/bin/python3 -m voiceflow >> ~/OpenVoiceFlow/voiceflow.log 2>&1 &
```

### Option B: Login item (auto-start)

```bash
# Create a start script
cat > ~/Applications/start-openvoiceflow.command << 'EOF'
#!/bin/bash
nohup ~/.openvoiceflow/venv/bin/python3 -m voiceflow >> ~/OpenVoiceFlow/voiceflow.log 2>&1 &
disown
sleep 1
osascript -e 'tell application "Terminal" to close front window' 2>/dev/null
EOF
chmod +x ~/Applications/start-openvoiceflow.command
```

Then add to: **System Settings → General → Login Items → +** → select `start-openvoiceflow.command`.

## Transcript Logs

OpenVoiceFlow saves every dictation to `~/OpenVoiceFlow/logs/`:

- **Markdown** — `2025-02-22.md` (human-readable diary)
- **JSONL** — `2025-02-22.jsonl` (machine-readable, with raw + cleaned)

```bash
# View today's transcripts
cat ~/OpenVoiceFlow/logs/$(date +%Y-%m-%d).md

# Search all transcripts
grep -r "meeting" ~/OpenVoiceFlow/logs/
```

## Cost Comparison

| Solution | Annual Cost | Local Transcription | LLM Cleanup |
|----------|------------|--------------------:|------------:|
| Wispr Flow Pro | $144 | ❌ | ✅ |
| Superwhisper Pro | $85 | ✅ | ❌ |
| **OpenVoiceFlow + Gemini** | **~$3** | ✅ | ✅ |
| **OpenVoiceFlow + Ollama** | **$0** | ✅ | ✅ |

## Requirements

- macOS 12+ (Apple Silicon recommended for fast transcription)
- Python 3.9+
- ~200 MB disk space (whisper model + dependencies)
- Microphone access

## Project Structure

```
voiceflow/
├── voiceflow/
│   ├── __init__.py        # Package metadata
│   ├── __main__.py        # CLI entry point
│   ├── app.py             # Main app controller + hotkey listener
│   ├── config.py          # Configuration management
│   ├── menubar.py         # macOS menu bar integration
│   ├── onboarding.py      # GUI setup wizard (tkinter)
│   ├── recorder.py        # Audio recording
│   ├── system.py          # Paste, sounds, logging
│   ├── transcriber.py     # whisper.cpp integration
│   └── llm/
│       ├── __init__.py    # Backend registry
│       ├── base.py        # Abstract base class
│       ├── gemini.py      # Google Gemini
│       ├── openai_backend.py   # OpenAI
│       ├── anthropic_backend.py # Anthropic Claude
│       ├── groq_backend.py     # Groq
│       └── ollama_backend.py   # Ollama (fully local)
├── install.sh             # One-command installer
├── build-dmg.sh           # Build macOS DMG installer
├── pyproject.toml         # Package config
├── requirements.txt
├── LICENSE                # MIT
└── README.md
```

## Contributing

### Building the DMG

To create the DMG installer for distribution:

```bash
bash build-dmg.sh
```

This outputs `dist/OpenVoiceFlow-0.1.0.dmg`. Upload it to GitHub Releases.

### Ideas for contributors

- **Windows/Linux support** — pynput works cross-platform, but paste and sounds are macOS-specific
- **Streaming transcription** — real-time partial results while speaking
- **Custom LLM prompts** — per-app contexts (email mode, code mode, slack mode)
- **Clipboard history integration** — work with clipboard managers
- **Audio-based speaker diarization** — multi-speaker support

## License

MIT — do whatever you want with it.

---

Built with ❤️ as a free alternative to paid voice dictation tools.
If this saves you $144/year, consider starring the repo ⭐

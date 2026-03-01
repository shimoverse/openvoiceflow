# 🎙️ OpenVoiceFlow

> **$0–3/year** vs **$144/year** for Wispr Flow. Same quality. Your audio stays on your Mac.

**Free, open-source voice dictation for macOS.**

Hold a key → speak → release → clean text appears at your cursor. Anywhere.

OpenVoiceFlow combines **local** speech-to-text (whisper.cpp) with **LLM-powered cleanup** to remove filler words, fix grammar, and handle corrections — giving you polished text from messy speech.

| Solution | Annual Cost |
|----------|------------|
| Wispr Flow Pro | $144 |
| Superwhisper Pro | $85 |
| **OpenVoiceFlow + Gemini** | **~$3** |
| **OpenVoiceFlow + Ollama** | **$0** |

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

---

## Installation

### Option 1: DMG Installer (easiest)

Download the latest `.dmg` from [Releases](https://github.com/shimoverse/openvoiceflow/releases), open it, drag **OpenVoiceFlow** to Applications.

> **⚠️ First launch:** macOS will say it can't verify the app. Click **Done** → **System Settings → Privacy & Security** → **Open Anyway**. This only happens once.

On first launch, OpenVoiceFlow installs everything it needs and walks you through setup.

### Option 2: Quick Install

```bash
git clone https://github.com/shimoverse/openvoiceflow.git
cd openvoiceflow
bash install.sh
```

### Option 3: Manual

```bash
brew install whisper-cpp
git clone https://github.com/shimoverse/openvoiceflow.git
cd openvoiceflow
python3 -m venv ~/.openvoiceflow/venv
~/.openvoiceflow/venv/bin/pip install -e ".[all]"
mkdir -p ~/.openvoiceflow/models
curl -L -o ~/.openvoiceflow/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
openvoiceflow --set-key gemini YOUR_KEY_HERE
openvoiceflow
```

---

## Usage

```bash
openvoiceflow           # Launch (GUI wizard on first run)
openvoiceflow --menubar # Menu bar mode
openvoiceflow --test    # Test pipeline
openvoiceflow --setup   # Re-run setup
```

**Default hotkey:** Hold `Right Command` → speak → release.

Grant **Accessibility** permission when prompted (System Settings → Privacy & Security → Accessibility).

---

## LLM Backends

| Backend | Cost | Speed | Privacy |
|---------|------|-------|---------|
| **Gemini Flash** | ~$3/year | Fast | Cloud |
| **Groq** | Free tier | Fastest | Cloud |
| **OpenAI** | ~$5/year | Fast | Cloud |
| **Claude** | ~$8/year | Fast | Cloud |
| **Ollama** | $0 | Local | Fully private |
| **None** | $0 | Instant | Local |

```bash
openvoiceflow --backend gemini && openvoiceflow --set-key gemini YOUR_KEY
openvoiceflow --backend ollama   # Fully local — requires Ollama running
openvoiceflow --backend none     # Raw whisper output, no cleanup
```

**Get a free key:** [Gemini](https://aistudio.google.com/apikey) · [Groq](https://console.groq.com/keys)

---

## Configuration

`~/.openvoiceflow/config.json`:

```json
{
  "hotkey": "right_cmd",
  "whisper_model": "base.en",
  "llm_backend": "gemini",
  "gemini_api_key": "your-key-here",
  "sound_feedback": true,
  "auto_paste": true,
  "log_transcripts": true,
  "llm_prompt": null
}
```

**Hotkeys:** `right_cmd` · `right_alt` · `left_alt` · `f5`–`f12`

**Whisper models:** `tiny.en` (75MB) · `base.en` (142MB, recommended) · `small.en` (466MB) · `medium.en` (1.5GB)

**Custom LLM prompt** (e.g. code mode, email mode):
```bash
openvoiceflow --set-prompt "Fix grammar only. Preserve technical terms and code snippets exactly."
```

---

## Requirements

- macOS 12+ (Apple Silicon recommended)
- Python 3.9+
- ~200 MB disk (whisper model + deps)
- Microphone access

---

## Contributing

Ideas welcome:
- Windows/Linux support
- Streaming real-time transcription
- Per-app prompt contexts
- Speaker diarization

```bash
bash build-dmg.sh  # Build DMG for distribution
```

MIT License. Built as a free alternative to paid voice dictation tools.  
If this saves you $144/year, consider starring the repo ⭐

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

## Features

### 🪟 Floating Overlay (Visual Feedback)

A native macOS HUD overlay appears at the bottom of your screen, showing:
- 🔴 **Recording...** — while you speak
- ⏳ **Processing...** — animated dots while transcribing and cleaning
- ✅ **Result preview** — briefly flashes the cleaned text
- ❌ **Error messages** — microphone issues, no speech detected, etc.

Uses PyObjC/AppKit for a native, always-on-top overlay that works across all Spaces. Falls back gracefully if PyObjC is unavailable.

### 🔔 Notification Center

macOS notifications supplement the overlay for errors, setup issues, and update availability.

### 🔄 Auto-Update Check

On each launch, OpenVoiceFlow silently checks GitHub for newer versions in a background thread. If an update is available, you get a notification with the download link — no action needed otherwise.

### 📖 Personal Dictionary

Teach OpenVoiceFlow your custom spellings — names, technical terms, brand names:

```bash
# Add words
openvoiceflow --add-word "OpenVoiceFlow"
openvoiceflow --add-word "whisper.cpp"
openvoiceflow --add-word "Supabase"

# List all words
openvoiceflow --list-words

# Remove a word
openvoiceflow --remove-word "Supabase"
```

Dictionary words are injected into the LLM cleanup prompt so they're always spelled correctly.

Stored at `~/.openvoiceflow/dictionary.json`.

### 📌 Voice Snippets

Define voice shortcuts that expand to full text blocks:

```bash
# Add snippets
openvoiceflow --add-snippet "insert signature" "Best regards,\nMohit Jain\nmohit@example.com"
openvoiceflow --add-snippet "my email" "mohit.jain@example.com"
openvoiceflow --add-snippet "insert disclaimer" "This message is confidential..."

# List snippets
openvoiceflow --list-snippets

# Remove a snippet
openvoiceflow --remove-snippet "my email"
```

When you speak a trigger phrase exactly, the snippet expands immediately — no LLM call needed.

Stored at `~/.openvoiceflow/snippets.json`.

### 🌍 Multi-Language Support

Dictate in any language supported by Whisper:

```bash
openvoiceflow --language es   # Spanish
openvoiceflow --language de   # German
openvoiceflow --language ja   # Japanese
openvoiceflow --language fr   # French
openvoiceflow --language auto # Auto-detect language
```

When you switch to a non-English language, OpenVoiceFlow automatically upgrades to a multilingual Whisper model (e.g., `base` instead of `base.en`).

Multilingual models: `tiny` · `base` · `small` · `medium` · `large`

### 🎨 Style/Tone Modes

Adjust how the LLM cleans up your speech:

| Style | Description | Use for |
|-------|-------------|---------|
| `default` | Natural, balanced | General dictation |
| `casual` | Friendly, conversational | Messages, chats |
| `formal` | Professional, no contractions | Reports, documents |
| `code` | Preserves technical terms exactly | Code comments, commit messages |
| `email` | Email-formatted with proper structure | Emails, professional messages |

```bash
openvoiceflow --style casual
openvoiceflow --style code
openvoiceflow --style email
```

Style is also selectable from the menu bar dropdown.

### 📊 Statistics

Track your dictation usage:

```bash
openvoiceflow --stats
```

Output:
```
📊 OpenVoiceFlow Statistics
──────────────────────────────
   Dictations:    147
   Words:         12,843
   Characters:    71,206
   Recorded:      38.2 minutes
   Time saved:    ~321 minutes
   Days active:   14
```

Also visible in the menu bar app under **📊 Statistics**.

Stored at `~/.openvoiceflow/stats.json`.

### 🚀 Launch at Login

Start OpenVoiceFlow automatically when you log in to macOS:

```bash
openvoiceflow --autostart on   # Enable
openvoiceflow --autostart off  # Disable
```

Or toggle from the menu bar app. Uses a standard macOS LaunchAgent (`~/Library/LaunchAgents/com.openvoiceflow.app.plist`).

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
  "llm_prompt": null,
  "language": "en",
  "style": "default",
  "launch_at_login": false
}
```

**Hotkeys:** `right_cmd` · `right_alt` · `left_alt` · `f5`–`f12`

**Whisper models:**
- English-only (faster): `tiny.en` (75MB) · `base.en` (142MB) · `small.en` (466MB) · `medium.en` (1.5GB)
- Multilingual: `tiny` · `base` · `small` · `medium` · `large`

**Custom LLM prompt:**
```bash
openvoiceflow --set-prompt "Fix grammar only. Preserve technical terms and code snippets exactly."
openvoiceflow --clear-prompt  # Reset to default
```

---

## CLI Reference

```
openvoiceflow [options]

  --menubar              Run as menu bar app
  --setup / --onboarding Re-run setup wizard
  --test                 Test pipeline with microphone
  --show-config          Print current config
  --version              Show version

Backend & Model:
  --backend BACKEND      Set LLM backend (gemini/openai/anthropic/groq/ollama/none)
  --model MODEL          Set Whisper model
  --set-key BACKEND KEY  Save API key
  --language LANG        Set transcription language (en, es, de, ja, auto, ...)
  --set-prompt PROMPT    Set custom cleanup prompt
  --clear-prompt         Reset to default prompt

Style & Output:
  --style STYLE          Set output style (default/casual/formal/code/email)

Personal Dictionary:
  --add-word WORD        Add word to dictionary
  --remove-word WORD     Remove word from dictionary
  --list-words           List all dictionary words

Voice Snippets:
  --add-snippet TRIGGER TEXT   Add a voice snippet
  --remove-snippet TRIGGER     Remove a snippet
  --list-snippets              List all snippets

System:
  --stats                Show dictation statistics
  --autostart on|off     Enable/disable launch at login
```

---

## Requirements

- macOS 12+ (Apple Silicon and Intel both supported)
- Python 3.9+
- ~200 MB disk (whisper model + deps)
- Microphone access
- Accessibility permission (for auto-paste)

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

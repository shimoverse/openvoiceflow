<p align="center">
  <img src="https://img.shields.io/badge/macOS-12%2B-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 12+"/>
  <img src="https://img.shields.io/badge/Apple%20Silicon-Ready-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Apple Silicon"/>
  <img src="https://img.shields.io/badge/Intel-Ready-000000?style=for-the-badge&logo=intel&logoColor=white" alt="Intel"/>
  <img src="https://img.shields.io/github/license/shimoverse/openvoiceflow?style=for-the-badge&color=blue" alt="MIT License"/>
  <img src="https://img.shields.io/github/v/release/shimoverse/openvoiceflow?style=for-the-badge&color=brightgreen" alt="Release"/>
</p>

<h1 align="center">🎙️ OpenVoiceFlow</h1>

<p align="center">
  <strong>Speak. It types. Everywhere.</strong>
</p>

<p align="center">
  Free, open-source voice dictation for macOS.<br/>
  Local transcription. AI-powered cleanup. Zero subscriptions required.
</p>

<p align="center">
  <code>Hold a key → Speak → Release → Polished text appears at your cursor</code>
</p>

---

<br/>

## The $144 Question

Every year, millions of Mac users pay for voice dictation tools. We think that's wrong.

| | Annual Cost |
|---|:---:|
| Wispr Flow Pro | **$144** |
| Superwhisper Pro | **$85** |
| **OpenVoiceFlow + Gemini** | **~$3** |
| **OpenVoiceFlow + Ollama** | **$0** |

Your audio never leaves your Mac. Your wallet stays full. That's it.

<br/>

---

<br/>

## How It Works

```
   You say:    "um hey can you schedule a meeting for uh Thursday no wait Friday"
                                          ↓
   Whisper:    transcribes locally on your Mac (Metal-accelerated)
                                          ↓
   LLM:       removes fillers, fixes grammar, handles "no wait"
                                          ↓
   Result:     "Hey, can you schedule a meeting for Friday?"
                                          ↓
   Auto-paste: text appears at your cursor — Notion, Gmail, Slack, anywhere
```

**Two stages. One keystroke. Zero cloud audio.**

1. **whisper.cpp** runs locally on Apple Silicon (Metal GPU) or Intel. Your voice stays on your machine.
2. **LLM cleanup** (your choice) polishes the transcript: removes "um"s, handles corrections like "no wait, I mean", fixes punctuation.

<br/>

---

<br/>

## Get Started in 60 Seconds

### Download the App

Grab the latest `.dmg` from [**Releases**](https://github.com/shimoverse/openvoiceflow/releases). Open it. Drag to Applications. Done.

> First launch installs everything automatically and walks you through a setup wizard.

<details>
<summary><strong>Other install methods</strong></summary>

<br/>

**One-line install:**
```bash
git clone https://github.com/shimoverse/openvoiceflow.git && cd openvoiceflow && bash install.sh
```

**Manual setup:**
```bash
brew install whisper-cpp
git clone https://github.com/shimoverse/openvoiceflow.git
cd openvoiceflow
python3 -m venv ~/.openvoiceflow/venv
~/.openvoiceflow/venv/bin/pip install -e ".[all]"
openvoiceflow --set-key gemini YOUR_KEY_HERE
openvoiceflow
```

</details>

<br/>

---

<br/>

## Choose Your AI Backend

Pick what matters to you: cost, speed, or total privacy.

| Backend | Cost | Speed | Privacy | Best For |
|:--------|:----:|:-----:|:-------:|:---------|
| **Gemini Flash** ⭐ | ~$3/yr | Fast | Cloud | Most users. Free tier available. |
| **Groq** | Free tier | Fastest | Cloud | Speed demons. 30 req/min free. |
| **OpenAI** | ~$5/yr | Fast | Cloud | GPT ecosystem fans. |
| **Claude** | ~$8/yr | Fast | Cloud | Anthropic users. |
| **Ollama** | $0 | Local | **100% Private** | Privacy maximalists. Nothing leaves your Mac. |
| **None** | $0 | Instant | Local | Raw whisper output, no cleanup. |

```bash
openvoiceflow --backend gemini --set-key gemini YOUR_KEY
openvoiceflow --backend ollama    # fully local, $0
```

**Get a free key:** [Gemini](https://aistudio.google.com/apikey) · [Groq](https://console.groq.com/keys)

<br/>

---

<br/>

## Features

### 🪟 Floating Overlay

A native macOS HUD floats at the bottom of your screen, always visible, never in the way.

| State | What You See |
|:------|:-------------|
| 🔴 Recording | Red indicator while you speak |
| ⏳ Processing | Animated dots during transcription |
| ✅ Done | Brief flash of the cleaned text |
| ❌ Error | Clear error message with guidance |

Built with PyObjC/AppKit. Works across all Spaces and fullscreen apps.

---

### 📖 Personal Dictionary

Your words. Your spelling. Every time.

```bash
openvoiceflow --add-word "OpenVoiceFlow"
openvoiceflow --add-word "Kubernetes"
openvoiceflow --add-word "Supabase"
openvoiceflow --list-words
```

Dictionary words are injected into the LLM prompt so names, brands, and jargon are always spelled correctly.

---

### 📌 Voice Snippets

Say a phrase. Get a paragraph.

```bash
openvoiceflow --add-snippet "insert signature" "Best regards,
Mohit Jain
mohit@example.com"

openvoiceflow --add-snippet "my address" "742 Evergreen Terrace, Springfield"
```

Snippets expand instantly, no LLM call needed. Say the trigger, get the text.

---

### 🌍 100+ Languages

Dictate in any language Whisper supports. Mixed-language? Auto-detect handles it.

```bash
openvoiceflow --language es      # Spanish
openvoiceflow --language ja      # Japanese
openvoiceflow --language auto    # Auto-detect
```

Switches to a multilingual Whisper model automatically when you pick a non-English language.

---

### 🎨 Tone & Style

Match your output to where you're writing.

| Style | Tone | Use In |
|:------|:-----|:-------|
| `default` | Natural, balanced | Anywhere |
| `casual` | Friendly, contractions OK | Slack, iMessage, WhatsApp |
| `formal` | Professional, no contractions | Reports, proposals |
| `code` | Preserves technical terms exactly | IDEs, commit messages |
| `email` | Proper structure and greeting | Gmail, Outlook |

```bash
openvoiceflow --style casual
```

Also switchable from the menu bar.

---

### 📊 Your Stats

See how much time you've saved.

```bash
openvoiceflow --stats
```

```
📊 OpenVoiceFlow Statistics
──────────────────────────────
   Dictations:    147
   Words:         12,843
   Time saved:    ~321 minutes
   Days active:   14
```

---

### 🚀 Launch at Login

```bash
openvoiceflow --autostart on
```

Starts quietly in the menu bar every time you log in. Toggle from the menu bar or CLI.

---

### 🔄 Auto-Update

On each launch, a background check looks for new releases. You'll get a notification if there's an update. No interruptions, no nagging.

<br/>

---

<br/>

## Configuration

Everything lives in `~/.openvoiceflow/config.json`:

```json
{
  "hotkey": "right_cmd",
  "whisper_model": "base.en",
  "llm_backend": "gemini",
  "sound_feedback": true,
  "auto_paste": true,
  "language": "en",
  "style": "default",
  "launch_at_login": false
}
```

**Hotkeys:** `right_cmd` · `right_alt` · `left_alt` · `f5` through `f12`

**Whisper models:**

| Type | Models | Note |
|:-----|:-------|:-----|
| English-only (faster) | `tiny.en` · `base.en` · `small.en` · `medium.en` | Optimized for English |
| Multilingual | `tiny` · `base` · `small` · `medium` · `large` | 100+ languages |

<br/>

---

<br/>

<details>
<summary><strong>Full CLI Reference</strong></summary>

<br/>

```
openvoiceflow [options]

Launch:
  (no args)              Start listening (GUI wizard on first run)
  --menubar              Run as menu bar app
  --setup                Re-run setup wizard
  --test                 Test pipeline
  --version              Show version
  --show-config          Print current config

Backend & Model:
  --backend BACKEND      gemini / openai / anthropic / groq / ollama / none
  --model MODEL          Whisper model (base.en, small, large, etc.)
  --set-key BACKEND KEY  Save API key for a backend
  --language LANG        Transcription language (en, es, de, ja, auto, ...)
  --set-prompt PROMPT    Custom LLM cleanup prompt
  --clear-prompt         Reset to default prompt

Style:
  --style STYLE          default / casual / formal / code / email

Dictionary:
  --add-word WORD        Add to personal dictionary
  --remove-word WORD     Remove from dictionary
  --list-words           Show all dictionary words

Snippets:
  --add-snippet TRIGGER TEXT   Create a voice shortcut
  --remove-snippet TRIGGER     Remove a shortcut
  --list-snippets              Show all shortcuts

System:
  --stats                Show usage statistics
  --autostart on|off     Launch at login
```

</details>

<br/>

---

<br/>

## Requirements

- **macOS 12+** (Monterey, Ventura, Sonoma, Sequoia, Tahoe)
- **Apple Silicon or Intel** (both fully supported)
- Python 3.9+
- ~200 MB disk space
- Microphone access + Accessibility permission

<br/>

---

<br/>

## Contributing

We'd love help with:

- 🪟 Windows / Linux support
- 🎙️ Streaming real-time transcription
- 📱 Per-app context switching
- 🗣️ Speaker diarization
- 🎨 Better overlay designs

```bash
bash build-dmg.sh  # Build DMGs for distribution
```

<br/>

---

<br/>

<p align="center">
  <strong>MIT License</strong> · Built as a free alternative to paid voice dictation tools.
</p>

<p align="center">
  If this saves you $144/year, consider giving us a ⭐
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-12%2B-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 12+"/>
  <img src="https://img.shields.io/badge/Apple%20Silicon-Ready-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Apple Silicon"/>
  <img src="https://img.shields.io/badge/Intel-Ready-000000?style=for-the-badge&logo=intel&logoColor=white" alt="Intel"/>
  <img src="https://img.shields.io/github/license/shimoverse/openvoiceflow?style=for-the-badge&color=blue" alt="MIT License"/>
  <img src="https://img.shields.io/github/v/release/shimoverse/openvoiceflow?style=for-the-badge&color=brightgreen" alt="Release"/>
</p>

<h1 align="center">🎙️ OpenVoiceFlow</h1>

<p align="center">
  <strong>Your voice, your rules, your Mac.</strong>
</p>

<p align="center">
  The only open-source voice dictation app that learns who you are,<br/>
  adapts to every app you use, and gets smarter every time you correct it.<br/>
  All for $0.
</p>

<p align="center">
  <code>Hold a key → Speak → Release → Perfect text at your cursor. Anywhere.</code>
</p>

---

<br/>

## Why OpenVoiceFlow?

Other tools ask you to pay $144/year and trust their cloud. We don't.

| | Annual Cost | Open Source | Local Audio | Learns From You | Per-App Styles |
|---|:---:|:---:|:---:|:---:|:---:|
| **OpenVoiceFlow** | **$0-3** | ✅ MIT | ✅ | ✅ | ✅ |
| Wispr Flow | $144 | ❌ | ❌ | ✅ | ✅ |
| Superwhisper | $85 | ❌ | ✅ | Partial | ✅ |
| VoiceInk | Free (GPL) | ❌ PRs | ✅ | ❌ | ✅ |

Your audio never leaves your Mac. Your corrections teach the app. Your wallet stays full.

<br/>

---

<br/>

## How It Works

```
  🎤  "um hey can you schedule a meeting for uh Thursday no wait Friday"
                                    ↓
  🔊  Whisper — transcribes locally on your Mac (Metal GPU accelerated)
                                    ↓
  🗣️  Voice Commands — "new line", "period", "comma" replaced instantly
                                    ↓
  🧠  LLM Cleanup — removes fillers, handles "no wait", fixes grammar
                                    ↓
  📋  "Hey, can you schedule a meeting for Friday?"
                                    ↓
  ⌨️  Auto-paste — text appears at your cursor in any app
```

**Real-time streaming.** Words appear in the overlay as you speak, not after you stop. Powered by `whisper-stream`.

**Context-aware.** OpenVoiceFlow reads the app you're in, the text you have selected, and your personal profile to produce text that fits perfectly.

<br/>

---

<br/>

## Get Started in 60 Seconds

### Download the App

Grab the latest `.dmg` from [**Releases**](https://github.com/shimoverse/openvoiceflow/releases). Open it. Drag to Applications. Done.

> First launch installs everything automatically, walks you through setup, and interviews you so it knows your name, your team, and your jargon from day one.

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
git clone https://github.com/shimoverse/openvoiceflow.git && cd openvoiceflow
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

<br/>

### 🎙️ Real-Time Streaming

Words appear in the floating overlay **as you speak**. No waiting until you release the key.

Powered by `whisper-stream` (Metal-accelerated on Apple Silicon). Samples audio every 3 seconds, transcribes continuously, shows partial results live. Falls back to batch mode on Intel if needed.

```bash
openvoiceflow --streaming on     # default
openvoiceflow --streaming off    # classic batch mode
```

---

### 🪟 Native Floating Overlay

A macOS HUD pill floats at the bottom of your screen. Always visible, never in the way.

| State | What You See |
|:------|:-------------|
| 🔴 Recording | Red indicator while you speak |
| 🎙 Streaming | Live text appearing as you talk |
| ⏳ Processing | Animated dots during LLM cleanup |
| ✅ Done | Brief flash of the cleaned text |
| 📚 Learned | "mir → Meer" when auto-learn detects a correction |
| ❌ Error | Clear error message with guidance |

Built with PyObjC/AppKit. Works across all Spaces and fullscreen apps.

---

### 🧠 Know Me — Smart Profile Onboarding

**No other dictation app does this.** On first launch, OpenVoiceFlow interviews you:

1. **What's your name?** — So it's always spelled right
2. **What do you do?** — Your role and industry seed the vocabulary
3. **Who do you mention?** — Work names, home names, brands, tools
4. **How do you communicate?** — Casual, balanced, or formal

60 seconds. The very first dictation after setup nails your kid's name, your coworker's name, and your company jargon. All names auto-populate the dictionary too.

```bash
openvoiceflow --profile          # re-run the interview anytime
openvoiceflow --show-profile     # see what it knows
openvoiceflow --clear-profile    # start fresh
```

---

### 📚 Auto-Learn From Corrections

You dictate "picking up mir from school." You fix "mir" to "Meer." OpenVoiceFlow silently learns.

- Watches the text field for 30 seconds after each paste (5s, 10s, 15s, 20s, 30s)
- Detects word-level substitutions via macOS Accessibility API
- Adds corrections to your dictionary automatically
- Shows a subtle "📚 mir → Meer" notification in the overlay
- Stops watching if you switch apps

**You never open settings. You never type `--add-word`. You just fix a typo once, and it learns forever.**

```bash
openvoiceflow --auto-learn on    # default
openvoiceflow --auto-learn off
```

---

### 🎯 Per-App Context Detection

OpenVoiceFlow reads which app you're in and adapts automatically.

| App | Auto Style | What Changes |
|:----|:-----------|:-------------|
| VS Code, Xcode, Terminal, iTerm2 | `code` | Preserves technical terms, function names |
| Gmail, Outlook, Mail, Superhuman | `email` | Professional structure, greeting/closing |
| Slack, Discord, WhatsApp, iMessage | `casual` | Friendly tone, contractions |
| Word, Notion, Google Docs | `default` | Natural, balanced |

30 apps mapped out of the box. Add your own:

```bash
openvoiceflow --app-style "Figma" formal
openvoiceflow --list-app-styles
```

---

### 📎 Selected Text Context

Have text selected when you start dictating? OpenVoiceFlow reads it and feeds it to the LLM.

**Reply to an email:** Select the email text, hold your hotkey, speak your reply. The LLM understands what you're replying to and formats accordingly.

**Edit a paragraph:** Select it, dictate your revision. The AI knows what you're editing.

```bash
# enabled by default, toggle in config:
# "selected_text_context": true
```

---

### 🗣️ Voice Commands

Say punctuation and formatting commands naturally. They're replaced **before** the LLM sees the text, so there's zero added latency.

| Say | Get |
|:----|:----|
| "new line" | ↵ |
| "new paragraph" | ↵↵ |
| "period" / "full stop" | . |
| "comma" | , |
| "question mark" | ? |
| "exclamation mark" | ! |
| "colon" / "semicolon" | : / ; |
| "open paren" / "close paren" | ( / ) |
| "open quote" / "close quote" | " / " |
| "ellipsis" / "dot dot dot" | ... |
| "dash" / "hyphen" | - |
| "tab" | ⇥ |

Add custom commands:

```bash
openvoiceflow --add-command "smiley face" "😊"
openvoiceflow --list-commands
```

---

### 📖 Personal Dictionary

Teach OpenVoiceFlow words it should always spell correctly.

```bash
openvoiceflow --add-word "OpenVoiceFlow"
openvoiceflow --add-word "Kubernetes"
openvoiceflow --list-words
```

Words are injected into the LLM prompt so names, brands, and jargon always come out right. Auto-populated by the Know Me interview and auto-learn.

---

### 📌 Voice Snippets

Say a phrase. Get a paragraph.

```bash
openvoiceflow --add-snippet "insert signature" "Best regards,
Mohit Jain
mohit@example.com"

openvoiceflow --add-snippet "my address" "742 Evergreen Terrace, Springfield"
```

Snippets expand instantly. No LLM call needed.

---

### 🎨 Tone & Style Modes

| Style | Tone | Use In |
|:------|:-----|:-------|
| `default` | Natural, balanced | Anywhere |
| `casual` | Friendly, contractions OK | Slack, iMessage |
| `formal` | Professional, no contractions | Reports, proposals |
| `code` | Preserves technical terms | IDEs, commit messages |
| `email` | Proper structure | Gmail, Outlook |

```bash
openvoiceflow --style casual
```

Automatically set by per-app context detection, or choose manually.

---

### 🌍 100+ Languages

Dictate in any language Whisper supports.

```bash
openvoiceflow --language es      # Spanish
openvoiceflow --language ja      # Japanese
openvoiceflow --language auto    # Auto-detect
```

Auto-switches to a multilingual Whisper model when you pick a non-English language.

---

### 🔍 History Search

Search your past dictations from the command line.

```bash
openvoiceflow --search "meeting Friday"
openvoiceflow --search "budget" --search-last 7    # last 7 days
openvoiceflow --search "deploy" --search-date 2026-03-15
```

---

### 📊 Your Stats

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

Starts quietly in the menu bar every time you log in.

---

### 🔄 Auto-Update

Background check on each launch. Notification if there's a new version. No interruptions.

<br/>

---

<br/>

## The Full Picture

Here's everything OpenVoiceFlow does, compared to the paid alternatives:

| Feature | OpenVoiceFlow | Wispr Flow ($144) | Superwhisper ($85) | VoiceInk (GPL) |
|:--------|:---:|:---:|:---:|:---:|
| Local STT (whisper.cpp) | ✅ | ❌ Cloud | ✅ | ✅ |
| LLM cleanup | ✅ 6 backends | ✅ 1 | ✅ 1 | ✅ 1 |
| Real-time streaming | ✅ | ✅ | ✅ | ❌ |
| Per-app context | ✅ 30 apps | ✅ | ✅ | ✅ |
| Voice commands | ✅ 24 commands | ❌ | ❌ | ❌ |
| Selected text context | ✅ | ✅ | ✅ | ❌ |
| Smart profile onboarding | ✅ | Partial | ❌ | ❌ |
| Auto-learn corrections | ✅ | ✅ | ❌ | ❌ |
| Personal dictionary | ✅ | ✅ | ✅ | ✅ |
| Voice snippets | ✅ | ✅ | ❌ | ❌ |
| Multi-language (100+) | ✅ | ✅ | ✅ | ✅ |
| Style/tone modes | ✅ 5 modes | ✅ | ❌ | ❌ |
| History search | ✅ | ❌ | ❌ | ❌ |
| Floating overlay | ✅ | ✅ | ✅ | ✅ |
| Audio stays local | ✅ | ❌ | ✅ | ✅ |
| Open source (MIT) | ✅ | ❌ | ❌ | ❌ (GPL) |
| Price | **$0-3/yr** | $144/yr | $85/yr | $0 |

<br/>

---

<br/>

## Configuration

Everything lives in `~/.openvoiceflow/`:

| File | What |
|:-----|:-----|
| `config.json` | All settings (hotkey, backend, style, toggles) |
| `profile.json` | Your personal profile from the Know Me interview |
| `dictionary.json` | Custom words + auto-learned corrections |
| `snippets.json` | Voice snippet shortcuts |
| `stats.json` | Usage statistics |
| `models/` | Whisper model files |
| `logs/` | Daily transcript logs (JSONL + Markdown) |

<details>
<summary><strong>Full config reference</strong></summary>

<br/>

```json
{
  "hotkey": "right_cmd",
  "whisper_model": "base.en",
  "llm_backend": "gemini",
  "sound_feedback": true,
  "auto_paste": true,
  "language": "en",
  "style": "default",
  "streaming": true,
  "streaming_step_ms": 3000,
  "auto_style": true,
  "auto_learn": true,
  "voice_commands": true,
  "selected_text_context": true,
  "launch_at_login": false
}
```

**Hotkeys:** `right_cmd` · `right_alt` · `left_alt` · `f5` through `f12`

**Whisper models:**

| Type | Models |
|:-----|:-------|
| English-only (faster) | `tiny.en` · `base.en` · `small.en` · `medium.en` |
| Multilingual (100+ languages) | `tiny` · `base` · `small` · `medium` · `large` |

</details>

<br/>

---

<br/>

<details>
<summary><strong>Full CLI Reference</strong></summary>

<br/>

```
openvoiceflow [options]

Launch:
  (no args)                        Start listening (wizard on first run)
  --menubar                        Run as menu bar app
  --setup                          Re-run setup wizard
  --test                           Test pipeline
  --version                        Show version
  --show-config                    Print current config

Backend & Model:
  --backend BACKEND                gemini / openai / anthropic / groq / ollama / none
  --model MODEL                    Whisper model
  --set-key BACKEND KEY            Save API key
  --language LANG                  Transcription language (en, es, auto, ...)
  --set-prompt PROMPT              Custom LLM cleanup prompt
  --clear-prompt                   Reset to default

Streaming:
  --streaming on|off               Real-time streaming mode
  --streaming-step MS              Audio step size in milliseconds

Style & Context:
  --style STYLE                    default / casual / formal / code / email
  --app-style APP STYLE            Map an app to a style
  --remove-app-style APP           Remove mapping
  --list-app-styles                Show all mappings
  --auto-style on|off              Per-app auto-switching

Profile:
  --profile                        Run the Know Me interview
  --show-profile                   Print your profile
  --clear-profile                  Delete profile

Dictionary:
  --add-word WORD                  Add to dictionary
  --remove-word WORD               Remove from dictionary
  --list-words                     Show all words

Voice Commands:
  --add-command PHRASE TEXT         Add custom voice command
  --remove-command PHRASE           Remove command
  --list-commands                  Show all commands
  --voice-commands on|off          Enable/disable

Snippets:
  --add-snippet TRIGGER TEXT       Create voice shortcut
  --remove-snippet TRIGGER         Remove shortcut
  --list-snippets                  Show all snippets

Search:
  --search QUERY                   Search past dictations
  --search-date DATE               Filter by date (YYYY-MM-DD)
  --search-last DAYS               Filter last N days
  --limit N                        Max results

System:
  --stats                          Show usage statistics
  --autostart on|off               Launch at login
  --auto-learn on|off              Learn from corrections
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
- Microphone + Accessibility permission

<br/>

---

<br/>

## Contributing

We'd love help with:

- 🎙️ Streaming latency improvements
- 🧪 Unit test coverage
- 📱 Per-app context for more apps
- 🎨 Better overlay animations
- 🗣️ More voice commands
- 📖 Documentation and tutorials

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

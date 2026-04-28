# OpenVoiceFlow — UX Audit (lazy-and-dumb-user lens)

> **Status:** Discovery output. Not a fix list yet. Pairs with `PROJECT_AUDIT.md`, `PERSONA_AUDIT.md`, `READINESS_CHECKLIST.md`.
> Reviewed: 2026-04-27 against `main` at `0e946fa` (post-rc1).
>
> **Lens for this review:** Mohit asked for the bar to be set explicitly low — "users are lazy, users are dumb." That doesn't mean *insulting* users; it means the product has to assume the user **will not read the README, will not scroll through `--help`, will not remember the hotkey, will not figure out why something didn't work, and will not give a second chance after one frustration**. Every step has to either succeed silently or self-explain.

---

## TL;DR — three things that move the needle most

1. **First launch is a 3–10 minute black-box wait.** The DMG launcher silently bootstraps Homebrew, whisper.cpp, a Python venv, and downloads a 142 MB model. The user sees nothing. The single biggest friction point in the whole product. Fix: a real progress dialog with stage names + ETA.
2. **The post-paste experience teaches nothing.** After dictating "schedule meeting Friday" → text appears → silence. The user has no idea that "comma" became a comma, that "code mode" auto-engaged in VS Code, that auto-learn just saved a substitution. Fix: a single non-blocking toast per dictation that surfaces *what just got smarter*.
3. **All the sophistication is hidden.** Voice commands, snippets, dictionary, per-app styles, history search, statistics — every flagship v0.2 feature requires the user to know to run a specific CLI flag. Lazy users will use 5% of the product. Fix: a "Tips" notification rotation + visual menubar surfacing of the currently-active style/dictionary/streaming state.

The rest of this doc is the journey-by-journey breakdown.

---

## Methodology

The reviewer (Claude) walked the actual code paths the user hits at each stage:

- `build-dmg.sh` (the launcher script that bootstraps everything on first run)
- `voiceflow/onboarding.py` (tkinter setup wizard)
- `voiceflow/interview.py` (Know Me interview)
- `voiceflow/app.py` (hotkey listener, recording, processing)
- `voiceflow/overlay.py` (visual feedback HUD)
- `voiceflow/menubar.py` (rumps menubar)
- `voiceflow/learner.py` (auto-learn loop)
- `voiceflow/system.py` (paste, sounds, logging)
- `voiceflow/__main__.py` (CLI surface — 40+ flags)

For each journey: what *does* happen vs what *should* happen for a user who doesn't read manuals.

---

## Journey 1 — Discovery: "What is this thing?"

### What happens today

User lands on the GitHub repo or `docs/index.html` landing page.

- README opens with a comparison table vs Wispr Flow / Superwhisper / VoiceInk and a "Privacy at a glance" panel.
- Landing page shows an animated terminal demo (synthetic — typing characters appear letter by letter).
- No screenshot of the actual app. No video. No sample audio → text demo.
- Hero badges include `macOS 12+`, `Apple Silicon Ready`, `Intel Ready`, MIT license, latest release version.

### Friction (lazy user)

| Friction | Severity |
|---|---|
| No real "show me what this looks like" video / GIF | 🔴 — every successful Mac app of this category has one |
| Animated terminal demo is text-only; doesn't show the *floating overlay HUD*, the *menubar icon*, the *Know Me wizard*, or the actual paste-at-cursor moment | 🟠 — these are the magic; they're invisible |
| README hero leads with feature copy ("Your voice, your rules, your Mac") rather than a 5-second mental model ("Hold a key, talk, release, text appears anywhere") | 🟡 — the mental model line *is* in there but it's the third thing |
| Comparison table has no human-friendly framing ("here's the price of saying yes to Wispr") | 🟡 |

### Improvements (priority × effort)

- **🔴 Quick win.** Record a 15-second screen capture of: hold Right Cmd → say a sentence → see overlay → see clean text appear in Gmail. Convert to GIF (≤5 MB), drop into README hero + landing page hero. **Effort: 30 min. Impact: enormous.** Every visitor who otherwise needs to install to see what it does converts at the GIF.
- **🔴 Quick win.** Move the "Hold a key → speak → release" line into the literal first sentence under the title. Rest of the marketing flows from that mental model.
- **🟠 Medium.** Add three before/after audio samples on the landing page: "um hey can you schedule" → "Hey, can you schedule". Make the LLM cleanup magic visible.
- **🟡 Medium.** "What you'd say" calculator: pick the typing-speed-vs-talking-speed numbers and a yearly-time-saved estimator on the landing page. (`stats.py` already estimates 40 WPM for time-saved. Same math.)
- **🟡 Quick win.** Pin a one-screen architectural diagram (the same one in `docs/ARCHITECTURE.md`) on the landing page so privacy-conscious viewers can confirm the data flow without reading 281 lines.

---

## Journey 2 — Acquisition: "I want this. How do I get it?"

### What happens today

Three paths in the README — DMG, `bash install.sh`, manual `pip install`. The lazy/dumb user picks DMG.

1. README → Releases page → download the right DMG (arm64 or x86_64).
2. Open DMG → drag OpenVoiceFlow to Applications.
3. Double-click → macOS Gatekeeper: *"OpenVoiceFlow can't be opened because Apple cannot verify it's free of malware."*
4. User has to: System Settings → Privacy & Security → scroll to "OpenVoiceFlow was blocked" → click **Open Anyway** → re-launch → confirm a second dialog.

### Friction

| Friction | Severity |
|---|---|
| Gatekeeper dialog scares non-technical users into thinking the app is malware | 🔴 |
| The README footnote about Open Anyway exists but a user who launches the DMG directly from Applications never sees it | 🔴 |
| User has to know which DMG (arm64 vs x86_64) — the README explains, but `dist/OpenVoiceFlow-0.3.0-arm64.dmg` vs `-x86_64.dmg` doesn't tell a non-technical user which is theirs | 🟠 |
| First-launch silently kicks off ~3–10 minutes of bootstrap work; the user sees nothing | 🔴🔴 — covered in Journey 3 |

### Improvements

- **🔴 Quick win.** README hero adds an "Apple Silicon (M1/M2/M3/M4)" / "Intel" toggle that swaps the prominent download button. (`docs/index.html` could detect `navigator.userAgent` and pre-select.) Effort: 2 hours.
- **🔴 Medium.** Notarize the DMG (Apple Developer $99/yr, Decision D6 deferred). This *eliminates* the Gatekeeper override. Single biggest UX upgrade per dollar in the entire product.
- **🟠 Quick win.** First time the .app launches and detects it's been Gatekeeper-blocked-once-already, show a one-screen tkinter (or eventually native AppKit) "Welcome — here's why macOS yelled at you" explainer with a specific *click-here-to-open-System-Settings* button. (`pyobjc` can `osascript` open the right pane via x-apple.systempreferences URL.) Effort: 1 day.
- **🟡 Medium.** README install section adds a 30-second video showing the entire install + first-run flow. Sets expectations for the bootstrap wait.

---

## Journey 3 — First launch: "I just opened it. Now what?"

### What happens today

`build-dmg.sh` produces a thin `.app` bundle whose `Contents/MacOS/OpenVoiceFlow` is a bash launcher. On first run:

1. Detects Apple Silicon vs Intel; re-execs under `arch -arm64` if needed.
2. Sources Homebrew env (`/opt/homebrew/bin/brew` or `/usr/local/bin/brew`).
3. **If brew missing:** opens Terminal.app and runs the brew installer interactively. Pops a dialog telling the user to relaunch. `exit 0`. **The user is in Terminal staring at brew install output. Confused.**
4. **If brew found, whisper-cli/whisper-cpp missing:** silently `brew install whisper-cpp` (typically 30s–2min).
5. Creates Python venv at `~/.openvoiceflow/venv`.
6. Pip-installs `sounddevice numpy pynput rumps` (+`pyobjc` after my install.sh fix).
7. Pip-installs the package itself (`pip install ".[all]"`).
8. Downloads `~142 MB` `ggml-base.en.bin` from HuggingFace via `curl`.
9. Writes the source code into the venv's site-packages.
10. Launches the tkinter onboarding wizard.

Total time on a fresh Mac with reasonable network: **3–7 minutes**. On a slower connection or first-time brew install: **10+ minutes**.

**During all of this the user sees:** a Terminal window flash open if brew is missing, then nothing. The .app icon bounces in the dock once. No progress indicator. No "OpenVoiceFlow is setting up — this takes a few minutes" dialog. No way to know if it's working or hung.

### Friction

This is the single worst UX moment in the product.

| Friction | Severity |
|---|---|
| 3–10 minutes of silence; user assumes the app is broken | 🔴🔴🔴 |
| Terminal pops up uninvited when brew is missing; user thinks they did something wrong | 🔴 |
| If network is flaky, model download silently retries via `curl -L`; user has no visibility | 🔴 |
| If pip install fails (e.g., a transient PyPI mirror issue), user gets nothing | 🟠 |
| First-launch failure modes (brew install denied, network down, disk full) all dead-end without recovery suggestions | 🟠 |
| Re-launch after brew install requires user to know to do it; a confused user just quits | 🔴 |

### Improvements

- **🔴 P0.** Replace `osascript display dialog` ad-hoc messages with a *real* progress UI. Two viable paths:
  1. **Quick path (1 day):** spawn a tkinter progress window from the bash launcher (the bundle ships a `progress.py` that takes a stage name + step count). Update it via a named pipe as the bash script progresses. Crude but native-feeling.
  2. **Right path (1 week):** rewrite the launcher as a small Swift binary that drives an AppKit-native progress sheet, with each stage having its own message and an explicit Cancel. This also enables *macOS notarization* via xcodebuild + notarytool — bundling Swift means the bundle ships pre-built binaries the first launch can verify.
- **🔴 P0.** Each stage gets a one-line user-facing description:
  - "Welcome to OpenVoiceFlow — first launch sets up the tools it needs. This takes about 5 minutes."
  - "Step 1 of 5: Installing Homebrew (the macOS package manager). This is a one-time install."
  - "Step 2 of 5: Installing Whisper (the speech engine). About 90 MB."
  - "Step 3 of 5: Setting up Python."
  - "Step 4 of 5: Downloading the speech model (142 MB)."
  - "Step 5 of 5: Almost there!"
- **🟠 P1.** Per-stage failure handling: if brew install denied, show *"OpenVoiceFlow needs Homebrew to install Whisper. We can't install it for you because it asks for your admin password. Click here to install Homebrew yourself, then relaunch this app."* + a button that opens `https://brew.sh` in the browser.
- **🟠 P1.** Detect "previous bootstrap was incomplete" on relaunch — if `~/.openvoiceflow/venv` exists but `ggml-base.en.bin` is missing, resume from step 4 instead of restarting.
- **🟡 P2.** `model.bin.tmp` + atomic rename on download so a Ctrl-C-killed first-launch doesn't leave a half-downloaded model that breaks the next run.

---

## Journey 4 — Onboarding wizard (tkinter)

### What happens today

After the bootstrap, the wizard launches. 4 + optional 5th screen (Know Me interview):

1. **Welcome** — emoji 🎙️ + tagline + 4 ✅ bullet points + "Get Started →"
2. **Choose Your AI Backend** — 5 backend rows (Gemini / Groq / OpenAI / Anthropic / Ollama) each with name, cost badge, "Recommended" tag on Gemini. Radio buttons.
3. **Set Up [Backend]** — provider-specific instructions ("Open Google AI Studio, sign in, click Create API Key, paste here") + a 🔗 link button + a password-style API-key input.
4. **Choose Your Hotkey** — 5 options, each with a label and a one-line description.
5. **Personalize OpenVoiceFlow ✨** — final screen → starts the Know Me interview (or "Skip personalization").

Style: dark theme, navy + blue accent, SF Pro fonts, tkinter widgets.

### Friction

| Friction | Severity |
|---|---|
| Tkinter looks dated; not Mac-native; tab order is wonky; buttons render as flat colored boxes; no native AppKit polish | 🟠 |
| Backend choice page doesn't help an indecisive user: 5 options of similar cost. The "Recommended" star on Gemini helps but the cost-vs-privacy tradeoff is buried | 🟠 |
| Step 3 forces the user out of the app to register on a new website, find an API key page, copy it, come back. ~3–8 minutes of context switch. **User can drop here.** | 🔴 |
| API-key input has length≥10 validation only — pasted typo passes onboarding and silently fails on first dictation | 🟠 (deferred Wave 2E) |
| Hotkey screen recommends Right Cmd as default but doesn't warn that Right Cmd conflicts with Cmd-arrow text navigation in *every* macOS app | 🟠 |
| Onboarding finishes by silently writing config; no success animation, no first-dictation tutorial | 🟡 |

### Improvements

- **🔴 P0.** Add an "I'm not sure / I just want this to work" big button on the backend page that **picks Gemini, opens AI Studio in a new tab, AND copies a step-by-step instruction to the clipboard** so the user can paste it into a notes app while they navigate the provider site. Plus a "Paste your key when ready" persistent listener so the user doesn't have to come back to the app to paste.
- **🔴 P0.** **Real key validation** (Wave 2E in pending follow-ups): on paste, ping `/v1/models` (OpenAI/Groq), `/v1beta/models?key=…` (Gemini), `/api/tags` (Ollama), or a 1-token Anthropic call. Show ✓ or ✗ inline. ~1 second per check.
- **🟠 P1.** Hotkey page warns inline: "Right Command can conflict with Cmd-Right (jump to end of line). If you use that shortcut a lot, pick F5 instead." Show a live demo strip: tap your candidate hotkey now, the wizard echoes back what it captured.
- **🟠 P1.** Replace tkinter with a native AppKit wizard via `pyobjc` *or* a small Swift sidecar app the launcher invokes. (Big effort but the wizard is the user's first interactive impression of the product. Worth it.)
- **🟡 P2.** "Did you know?" tip strip across the bottom — "Tip: you can say 'comma', 'period', 'new paragraph' and OpenVoiceFlow will format for you" rotates every 4 seconds during the wizard.
- **🟡 P2.** After "Finish Setup" lands, run a *built-in 10-second tutorial*: "Hold your hotkey now and say 'hello world.' We'll show you what happens." (Tutorial fires once, never again.)

---

## Journey 5 — Know Me interview (the personalization wizard)

### What happens today

After the basic wizard, optional second wizard runs (`interview.py`, 6 screens, ~650 lines of tkinter).

1. Welcome — explains the value, "Your data never leaves your Mac" reassurance.
2. Name + occupation + industry.
3. People you mention (work + home).
4. Tools / technical terms you say a lot.
5. Communication style (formal / casual / etc.).
6. Done — saves to `~/.openvoiceflow/profile.json` and auto-populates the personal dictionary.

Style matches the basic wizard.

### Friction

| Friction | Severity |
|---|---|
| 6 screens feels long. A user who just wants to dictate skips it via "Skip personalization." | 🟠 |
| Name input is open-ended; no "I dictate as Mohit Jain so my LLM should always spell those right" explanation up front | 🟡 |
| Communication style is asked once and never revisited; if the user's voice changes they don't know to re-run `--profile` | 🟡 |
| The interview feeds dictionary + LLM-system-prompt context, but the user never sees evidence that it's *working*. Magic happens silently. | 🔴 |
| If interview crashes (now caught + surfaced post-SS6), the user is bounced back to nothing | 🟡 |

### Improvements

- **🔴 P1.** *Show the interview's effect.* At the end of the interview, run a **live demo**: "Say 'meeting with [colleague's name] tomorrow' now." Then show side-by-side: raw whisper vs cleaned-with-profile. Concrete proof the personalization works.
- **🔴 P1.** Make the interview *resumable*. Save partial progress; if the user closes the window mid-flow, next launch offers "Resume your personalization."
- **🟠 P1.** A *menubar item* that says "Re-run Know Me interview" — and surfaces it more prominently when stats show the user has dictated a lot but hasn't updated their profile in 90 days.
- **🟠 P2.** Industry → tool autocomplete. If the user types "Software Engineering" as occupation, suggest common tools (GitHub, Slack, Linear, Notion, Figma, Jira). Accept-all checkbox.
- **🟡 P2.** Optional: ask for sample text the user typically dictates (one paragraph) and use it as a seed for prompt-tuning. Out of scope for v0.3.x but interesting.

---

## Journey 6 — First dictation: "Does this thing work?"

### What happens today

User holds Right Cmd, speaks, releases.

1. `app.py:on_key_press` fires; debounce check.
2. `recorder.start()` opens a sounddevice stream.
3. If `sound_feedback` is on (default), `play_sound("start")` plays a system "Pop" sound.
4. If `pyobjc` is available, `overlay.show_recording()` displays a floating pill with a red dot that says "Recording…".
5. User speaks.
6. Release → `on_key_release` → `recorder.stop()`.
7. If duration < 0.3s, "Too short, skipping." prints to stderr.
8. If `streaming` is on AND `whisper-stream` is available, partial transcripts have already been showing in the overlay during step 5.
9. Background thread: save to temp WAV → `whisper.cpp` transcribes → strip `[BLANK_AUDIO]` → if not empty, ship to LLM cleanup.
10. LLM response comes back (1–3 s) → `paste_text()` → `pbcopy` + `osascript "keystroke v using command down"`.
11. Cleaned text appears at cursor.
12. If `log_transcripts` is on (default off in v0.3+), append to daily log.
13. If `auto_learn` is on (default off), kick off correction-watcher thread.

### Friction

| Friction | Severity |
|---|---|
| If `pyobjc` isn't installed (CLI-only install), the user has *no visual feedback at all* — release the hotkey, then 2-3 seconds of dead silence, then text appears. Disorienting. | 🔴 |
| If `paste_text` osascript fails (no Accessibility grant), the cleaned text is in the pasteboard but never pasted, the user gets a stderr line they don't see, and they assume the app didn't work | 🔴 |
| Wrong-app paste race: user speaks, then ALT+TABs to a different app while the LLM is processing, paste lands in the wrong app | 🟠 — covered in v0.4-C follow-up |
| If LLM returns an error (rate limit, network blip), `cleanup_text` returns the raw text quietly; user has no idea why their dictation came out unedited | 🟠 |
| The "your hotkey works" feedback loop is the system "Pop" sound — which the user might not associate with OpenVoiceFlow on day 1 | 🟡 |
| Voice commands ("comma", "period") are documented in README but a user who didn't read it produces "I think comma we should comma do that" — confused that nothing converted to actual commas | 🟠 |

### Improvements

- **🔴 P0.** **The overlay HUD must be visible to ALL users, not just `[overlay]`-extras users.** Three options:
  1. Bundle `pyobjc-framework-Cocoa` in the BASE deps (cost: ~10 MB on disk, every install). Cleanest.
  2. On first launch detect `HAS_APPKIT == False` and show a one-time native dialog: "Install the visual feedback HUD? (recommended)" → runs `pip install pyobjc-framework-Cocoa`.
  3. Build a Tk-based fallback overlay that's worse-but-functional.
  Recommendation: Option 1 unless the install size is a real concern.
- **🔴 P0.** **Surface paste failures.** Today `system.py:paste_text` prints a stderr message about Accessibility permission. That message must become a visible **macOS notification** (`osascript display notification`) AND a 5-second overlay banner: "Couldn't auto-paste — your text is on the clipboard, ⌘V to paste manually." Plus a one-click "Fix Accessibility access" link.
- **🔴 P1.** **Voice command tutor.** First time the user dictates a sentence with a comma in it (heuristic: punctuation in the *transcribed* whisper output but no `,` token), the overlay shows: "💡 Try saying 'comma' — OpenVoiceFlow will type it for you. We have 24 of these. Type `openvoiceflow --list-commands` or click here to see them." (Self-dismissing after 8 seconds.)
- **🟠 P1.** Per-dictation timing in the overlay: "Whisper 0.8s · Cleanup 1.4s" mini-line under the cleaned text. Shows the user the system is fast and gives a feel for which models/backends are slow.
- **🟠 P1.** Per-dictation "✓ Auto-learn watching" indicator if the watcher is running — so a user who's just opted in sees evidence.
- **🟡 P2.** Sound feedback differentiation: Pop = recording started, Purr = stopped, Glass = success, Basso = error. README documents this; menubar tooltip should too.

---

## Journey 7 — Daily-use experience

### What happens today

User has the menubar app running. Dictates ~10–50 times a day in different apps.

Menu bar shows:
- 🎙️ icon (or 🎙️💤 when paused; 🎙️❌ on setup error).
- Start/Stop listening.
- Status: "Ready — hold [right_cmd]"
- Style submenu (default / casual / formal / code / email).
- Auto-style toggle.
- Streaming toggle.
- Auto-learn toggle.
- Detected app status item.
- Stats item (opens stats output? Or just shows them?).
- Dictionary / Snippets / Profile shortcuts.
- LLM Backend submenu.
- Hotkey submenu.
- Open Config / View Logs.
- Quit.

`learner.py` watches each post-paste edit for 30 s; if it spots a substitution it adds to dictionary + shows `overlay.show_learned("mir → Meer")`.

Per-app context (via `pyobjc` `NSWorkspace.frontmostApplication()`) auto-switches the LLM style when the user moves between apps.

### Friction

| Friction | Severity |
|---|---|
| Detected-app status item updates somewhere ("right now: Slack → casual")? Need to verify behavior. If it doesn't update live, user can't tell when auto-style fires. | 🟠 |
| Style change is invisible — same text comes out either way to a casual eye | 🟡 |
| Auto-learn `show_learned` notification is great but only if `pyobjc` is present (Journey 6 issue again) | 🟠 |
| "Stats" menu item — opens what exactly? Stdout from `record_dictation`? Need to read code. | 🟡 |
| Dictionary / Snippets / Profile shortcuts — open a JSON in Finder? Open the CLI? Depends on impl. Either way, *editing JSON is a power-user action*; lazy users won't touch them. | 🔴 |
| There's no "weekly summary" — a user who's dictated 5,000 words this week never feels rewarded | 🔴 |
| Voice command discoverability — already noted in Journey 6 but also: snippets discoverability (`openvoiceflow --add-snippet "insert sig" "Best, Mohit"`) is even worse, since they require explicit creation before they do anything | 🔴 |

### Improvements

- **🔴 P0.** **Replace menubar JSON-shortcut items with proper editing UIs:**
  - Personal Dictionary → modal with a list, add/edit/delete buttons. Native AppKit table view (or tkinter as v0.3.x bridge).
  - Snippets → same treatment, plus an "Import templates" button that ships starter snippets ("My email signature", "My address", "Standard meeting decline").
  - Profile → opens the Know Me wizard for re-run.
- **🔴 P0.** **Weekly summary notification.** Sunday evening (or every 7th day) shows a notification: "📊 You dictated 8,432 words this week — saved you about 2 hours of typing." Click → opens an in-app stats panel.
- **🔴 P1.** **Live "currently in" status in menubar.** Title format: "🎙️ · code mode · Slack." One-glance evidence the auto-context is working.
- **🟠 P1.** **Tip rotation.** Once a day (configurable), show a tip notification: "Did you know? Say 'insert sig' and OpenVoiceFlow will paste your saved signature. Run `openvoiceflow --list-snippets` to see all of yours."
- **🟠 P1.** **In-menubar "What's working / not working" panel.** A click reveals: ✓ Whisper installed, ✓ Gemini key valid, ⚠ Accessibility grant missing → Fix. (This is `--doctor` (Wave 2F) but persistent and surfaced in the menubar instead of CLI-only.)
- **🟡 P2.** Achievements. "First 100 dictations." "First per-app auto-style switch." Tasteful, dismissable. (Mohit will know if this fits the brand voice.)

---

## Journey 8 — Power features (mostly hidden)

The following ship in v0.3.0 but a lazy user *will not find them* unless surfaced explicitly:

| Feature | Surface today | Lazy-user ETA |
|---|---|---|
| Voice commands (24) | README table; CLI `--list-commands` | Never |
| Snippets | CLI only | Never |
| Personal dictionary | CLI only; auto-populated by Know Me | Never (only via interview) |
| Per-app styles auto-detect | Menubar toggle, default on | Eventually notices weird LLM output in Code |
| History search | CLI `--search` | Never |
| Stats | CLI `--stats`, menubar item | Maybe via menubar |
| Streaming transcription | Menubar toggle | Notices speed |
| Launch at login | Menubar toggle | Doesn't notice; wonders why app isn't running after reboot |

### Improvements

- **🔴 P0.** **Surface voice commands proactively.** Two paths:
  1. After 10 dictations without a punctuation command, show a one-time educational notification.
  2. After every dictation, the overlay shows a tiny chip with the *last* converted command if any was used: "🗣 'comma' → ,". Reinforces the discovery.
- **🔴 P0.** **Snippet templates.** Onboarding asks: "Want some starter snippets? (Email signature, address, standard meeting decline)" and pre-fills them. User then knows snippets exist.
- **🟠 P1.** **History as a queryable thing.** Right-click the menubar → "Search history" → opens a Spotlight-style search panel. Far better than CLI.
- **🟠 P1.** **Stats become a menubar panel** (not just a `print()`). A small chart: dictations per day, words per day, time saved per week.
- **🟡 P2.** Per-app context status: when user switches into VS Code, a brief overlay flash: "🎙️ Code mode active." One-time per app per day.

---

## Journey 9 — Failure modes & recovery

### What happens today

Failure modes I can identify in the code:

- whisper.cpp not on PATH → printed error to stderr; CLI mode user sees it, menubar user gets a notification.
- whisper.cpp model file missing → auto-download attempt → fails silently if curl fails.
- LLM key missing → `validate()` returns `(False, msg)`; `validate_setup()` prints to stderr.
- LLM API returns 4xx/5xx → `cleanup_text` swallows the error, returns raw text. **User sees uncleaned text and assumes the cleanup just isn't very good.**
- Network down during dictation → 30s timeout, then `cleanup_text` returns raw.
- Accessibility permission denied → `paste_text` logs "Auto-paste failed" to stderr (post-BUG-009 fix).
- Apple Events permission denied → `osascript` exits non-zero, `paste_text` does the right thing.
- Microphone permission denied → `sounddevice.InputStream` raises; the recording starts but produces silence; whisper returns empty; "Too short, skipping" logs.
- Disk full → save_config / save_profile fails; user sees a Python traceback (in CLI) or nothing (in menubar).
- Gemini quota exceeded → 429 response → swallowed, raw transcript pasted.

### Friction

The overarching problem: **failure modes degrade silently or print to stderr.** A menubar user never sees stderr. They just notice things working badly.

| Friction | Severity |
|---|---|
| LLM 4xx/5xx → silent fallback to raw text. Worst possible failure mode: user thinks the product just isn't very good. | 🔴 |
| Network down → 30s freeze, then raw text. User thinks the app hung. | 🔴 |
| Mic permission denied → looks like nothing's recording. User has no clue why. | 🔴 |
| Quota exceeded on Gemini free tier → silent fallback, no "you've hit your free tier" message | 🟠 |

### Improvements

- **🔴 P0.** **Visible failure surface.** Every error path that today goes to stderr → ALSO shows a notification + an overlay banner. Specifically:
  - LLM 4xx/5xx: "⚠ Cleanup failed (Gemini returned 429: rate limit). Used raw text. Consider switching to Groq (free tier) or Ollama (local)."
  - Network down: "⚠ Cleanup couldn't reach the LLM. Used raw text. Reconnect and try again."
  - Mic permission denied: blocks at start time with a dialog: "OpenVoiceFlow can't hear you. Click to grant Microphone access."
  - Accessibility denied: same treatment.
- **🔴 P0.** `--doctor` *as a startup self-check too*. On every launch, run the same checks and surface failures *before* the user dictates. Currently `validate_setup` prints; instead: if not OK, halt the listener and notify "Setup incomplete — click for details."
- **🟠 P1.** Per-backend quota awareness: track 429s in a 24-hour window; if hit twice in a row, show a once-per-day notification "Gemini has rate-limited you 3x today. Free tier is 1000 req/day — consider switching."
- **🟡 P2.** Per-failure recovery suggestions are surfacing-the-user's-options heuristics. (E.g., disk-full → "Open Disk Utility"; permission denied → "Open System Settings → Privacy & Security → [Mic/Accessibility/Apple Events]" with the right pane URL.)

---

## Journey 10 — Sharing & virality

### What happens today

User wants to show OpenVoiceFlow to a friend. Options:

- Send the GitHub URL.
- Send the Releases URL with the .dmg.
- "Run `bash install.sh`" instructions.

### Friction

| Friction | Severity |
|---|---|
| Repo is private today; sharing the URL = 404 | 🔴 (resolved when public) |
| DMG is unsigned; friend hits Gatekeeper override too | 🟠 |
| No "Tell a friend" / share flow inside the app | 🟡 |
| Can't share *config*: friend has to re-onboard from scratch | 🟡 |

### Improvements

- **🟡 P2.** Menubar → "Tell a friend" → opens a pre-composed Twitter/iMessage/email with: "I've been using OpenVoiceFlow for X dictations / Y words. It's free, open-source, runs on my Mac. Try it: [link]." Pulls the X/Y from `stats.py`. Single sentence; one click.
- **🟡 P2.** Export/import config (without keys) so a power user can ship a starter pack ("Mohit's snippets + dictionary") to a friend.
- **🟡 P2.** README has a "What people are saying" section once there's organic traction. Empty until then.

---

## Cross-cutting opportunities (themes the journeys share)

### Theme A — Show, don't tell

| Today | Better |
|---|---|
| README describes auto-learn in prose | Animated screen-rec showing "mir" → typed by user → corrected in-context to "Meer" → next time user says "Meer" it's spelled right |
| "Per-app context detection" is a feature bullet | Live status in menubar: "🎙️ · email mode · Mail" |
| Voice commands are a README table | Inline chip after each dictation showing what command fired |
| Stats are a CLI `print()` | A menubar panel with bar chart + week-over-week delta |

### Theme B — Educate via micro-moments, not docs

| Today | Better |
|---|---|
| README says "say 'comma' for ," | First dictation that contains punctuation phonemes triggers a one-time tip |
| README says "you can change the prompt with --set-prompt" | After 100 dictations, a tip: "💡 If your dictations have a specific pattern, try a custom prompt: [example]" |
| Onboarding says profile improves accuracy | After a Know Me-personalized dictation that included a configured name, a chip: "✓ Profile picked up 'Anil' for you" |

### Theme C — Make every silent thing visible

The product currently has **at least 14 background things** that happen silently:

1. Bootstrap (Journey 3)
2. Per-app context detection
3. Voice command replacement
4. Selected text context capture
5. LLM cleanup (with which model?)
6. Auto-paste
7. Auto-learn watcher
8. Style preset injection
9. Dictionary injection
10. Snippets injection
11. Profile injection
12. Streaming transcription
13. Launch-at-login
14. Update check

A user only realizes any of these exist by reading the README. Each of these *should have a 1-line surface in the overlay or menubar* so the user understands what's happening.

### Theme D — Recovery > prevention

Lazy users *will* hit broken states (no internet, no mic permission, expired key). The product should assume failure is normal and design *one-click recovery paths* for each.

### Theme E — Native > tkinter

Tkinter is a porting layer that costs us:
- The wizard looks unprofessional vs Wispr Flow's polished onboarding.
- Tab order, focus rings, and font rendering are off.
- Buttons render as flat colored rectangles, not native macOS buttons.
- HiDPI scaling is iffy.

A small Swift sidecar app (or pyobjc-AppKit-native windows) for the wizard, the doctor panel, and the stats panel would be the single biggest-impact polish move.

---

## Suggested backlog ordering (impact ÷ effort)

### 🔴 Top 10 quick wins (≤ 1 day each, high impact)

1. **README hero GIF** (Journey 1) — show, don't tell.
2. **Apple-Silicon-vs-Intel detection on docs/index.html** (Journey 2) — pre-select the right download.
3. **First-launch progress dialog (tkinter MVP)** (Journey 3) — replace the silent 5-minute wait.
4. **Voice command tutor on first punctuation phoneme** (Journey 6) — discoverability.
5. **Surface paste failures as notification + overlay banner** (Journey 9) — recovery.
6. **Surface LLM-API failures as notification** (Journey 9) — recovery.
7. **Live menubar title showing current style + app** (Journey 7) — show the smart thing.
8. **Mic / Accessibility / Apple Events permission self-check at launch** (Journey 9) — block on missing perms.
9. **`openvoiceflow doctor` CLI subcommand** (Wave 2F) — self-diagnosis.
10. **Per-dictation tiny timing line in the overlay** (Journey 6) — confidence in speed.

### 🟠 Top 5 strategic investments (1 day–2 weeks)

1. **Notarize the DMG** (Decision D6) — eliminates Gatekeeper friction, unlocks Persona-2 and -4 mass install.
2. **Native AppKit wizard (Swift sidecar)** — replaces tkinter for the first interactive impression.
3. **Real key validation in onboarding** (Wave 2E) — prevents silent fail on day one.
4. **Native dictionary / snippets / profile editor** — makes the power features actually accessible.
5. **Stats menubar panel + weekly summary notification** — reward feedback loop.

### 🟡 Nice-to-haves

- Sharing flow ("Tell a friend")
- Export/import config
- Achievements
- Per-app overlay flash on context switch
- Tip-of-the-day rotation
- Resumable Know Me interview

---

## What this means for v0.3.x scope

- Do **not** push all 10 quick wins into v0.3.0 — the audit's job was readiness, not feature work.
- Mohit's call: are quick wins #1, #3, #5, #6 worth landing in v0.3.1 (a week-after-publish polish release)?
- Strategic investment #1 (notarize) and #3 (key validation, already in the deferred list) are the highest leverage v0.3.x candidates.
- Strategic investment #2 (native wizard) is a v0.4 conversation.

## What I deliberately didn't review

- The **algorithmic** quality of the LLM cleanup itself (e.g., does the prompt produce good results?). That's a product/eval question requiring real audio samples; I only walked structure.
- The **whisper.cpp model choice** UX (tiny.en vs base.en vs small.en — does the user know to upgrade?). Worth a separate pass.
- The **auto-learner correctness** — does it learn the right things? (Tests cover the substitution-extraction logic but not learner UX.)
- The **streaming transcription quality** — is it accurate enough that the overlay's partial transcripts feel useful or jittery?

These are all great follow-ups but require running the app on a real Mac with a real mic and a real LLM backend. I can spin up a separate review with that focus if useful.

---

## Closing

OpenVoiceFlow is — under the hood — a remarkably ambitious piece of software. v0.2 quietly added 15 modules of personalization (Know Me + auto-learn + per-app + dictionary + snippets + streaming + voice commands) on top of a clean v0.1 dictation core. The technical depth is well beyond what the README hero communicates.

**The gap between what the product *does* and what the user *experiences* is the biggest opportunity in front of you.** Almost every quick-win in this audit is in the surfacing layer — making the smart things visible — rather than building new smart things. That's a good problem to have.

# Privacy

OpenVoiceFlow is a personal-productivity tool that runs on your Mac. We wrote this document to be readable in one sitting: no legalese, no "we may collect" clauses that turn out to mean everything. If anything below is unclear or wrong, open a GitHub Discussion and we'll fix it.

This policy applies to OpenVoiceFlow `v0.3.x`. For older versions, check `git log PRIVACY.md` or the corresponding tagged release.

---

## 1. TL;DR

- **Your audio never leaves your Mac.** Transcription happens locally via `whisper.cpp` (and optionally `whisper-stream`). There is no audio upload, ever.
- **Your cleaned text goes wherever you tell it to.** The default LLM backend is OpenRouter Gemma 4 (cloud). You can switch to OpenAI / Anthropic / Groq, run Ollama locally, or pick `none` to skip the LLM step entirely.
- **OpenVoiceFlow has no servers.** No telemetry, no analytics, no crash reports, no accounts, no cloud sync. The only thing the app phones home for is a once-per-launch GitHub API check for a newer release, and that's opt-out.
- **Everything is on your disk, in your home directory.** API keys, profile, dictionary, snippets, optional logs — all in `~/.openvoiceflow/`, all `chmod 600` (owner-only). You can delete the folder at any time and the app forgets you.

---

## 2. Data inventory

Everything OpenVoiceFlow knows about you lives in one of the rows below.

| Artifact | Where it lives | What it contains | Default state | Goes off the Mac? |
|---|---|---|---|---|
| **Audio buffers** | RAM, then a temp WAV file | Your raw microphone audio while you hold the hotkey | Always on (it's how dictation works) | **No.** Sent to local `whisper.cpp` only. Temp WAV is deleted in a `finally` block after transcription. |
| **Cleaned transcripts (OpenRouter)** | In transit to `openrouter.ai` | The transcribed text + your system prompt, profile snippet, and any selected-text context | Default backend | **Yes** — to OpenRouter. You contract directly with OpenRouter under its terms. |
| **Cleaned transcripts (OpenAI)** | In transit to `api.openai.com` | Same as above | If you pick `--backend openai` | **Yes** — to OpenAI. |
| **Cleaned transcripts (Anthropic)** | In transit to `api.anthropic.com` | Same as above | If you pick `--backend anthropic` | **Yes** — to Anthropic. |
| **Cleaned transcripts (Groq)** | In transit to `api.groq.com` | Same as above | If you pick `--backend groq` | **Yes** — to Groq. |
| **Cleaned transcripts (Ollama)** | In transit to `http://localhost:11434` | Same as above | If you pick `--backend ollama` | **No.** Stays on the Mac (or wherever you point Ollama). |
| **Cleaned transcripts (none)** | Nowhere | The Whisper output is pasted directly with no LLM cleanup | If you pick `--backend none` | **No.** No LLM call is made at all. |
| **`config.json`** | `~/.openvoiceflow/config.json`, mode `600` | Hotkey, model, backend choice, cloud API keys (plaintext) | Created on first run | **No.** |
| **`profile.json`** | `~/.openvoiceflow/profile.json`, mode `600` | Your name, occupation, industry, names of people/tools you mention, communication style. | Empty until you complete the **Know Me** interview. | **No** — but the profile is injected into every LLM call's system prompt, so the chosen backend sees it. |
| **`dictionary.json`** | `~/.openvoiceflow/dictionary.json`, mode `600` | A list of `{word, aliases}` entries you've added | Empty until you add words via `--add-word` or the menubar | **No** — but words you add are injected into LLM system prompts, like the profile. |
| **`snippets.json`** | `~/.openvoiceflow/snippets.json`, mode `600` | Voice triggers and their expansions (e.g. `"my email" → "..."`). May contain signature blocks. | Empty until you add snippets | **No** — but expansions become part of dictated text and follow whatever path you've set for that text. |
| **`stats.json`** | `~/.openvoiceflow/stats.json`, mode `600` | Aggregate counters: total dictations, total words, time saved | On (counters increment automatically) | **No.** Never sent anywhere. |
| **Daily transcript logs** | `~/.openvoiceflow/logs/YYYY-MM-DD.{md,jsonl}`, mode `600` | Every dictation, raw + cleaned. Effectively a diary of everything you've spoken. | **Off by default.** Opt-in via `--log-transcripts on`. | **No.** Local only. |
| **LaunchAgent plist** | `~/Library/LaunchAgents/com.openvoiceflow.app.plist` | macOS launch-at-login configuration | Off by default. Opt-in via `--autostart on`. | **No.** |
| **GitHub update check** | In transit to `api.github.com/repos/shimoverse/openvoiceflow/releases/latest` | Public, unauthenticated GET. Sends only the standard HTTP headers your OS adds (no PII, no key, no user ID). | On by default. Opt-out via `--update-check off`. | **Yes** — a public, anonymous API call to GitHub once per launch. |

### Data flow for a single dictation

```
  mic audio  ──►  whisper.cpp (local)  ──►  raw transcript (RAM)
                                                  │
                                                  ▼
                                  voice-command replacement (local)
                                                  │
                                                  ▼
       profile + dictionary + selected text  ──►  LLM backend
                                                  │
                                  ┌───────────────┼────────────────┐
                                  ▼               ▼                ▼
                              OpenRouter /     Ollama            none
                              OpenAI /        (local)         (no call)
                              Anthropic /
                              Groq (cloud)
                                                  │
                                                  ▼
                                       cleaned text  ──►  paste at cursor
                                                  │
                              (optional, off by default)
                                                  ▼
                              ~/.openvoiceflow/logs/YYYY-MM-DD.{md,jsonl}
```

The only network egress in the whole pipeline is the chosen cloud LLM (if any) and the once-per-launch GitHub update check. Everything else stays on the Mac.

---

## 3. Sub-processors — who else sees your data

OpenVoiceFlow itself is **not** a sub-processor of your data. We have no servers, no database, no logs, and no copy of anything you dictate. When you point the app at a cloud LLM, you are contracting directly with that provider under their terms; we are not in the middle.

The third parties your install can talk to:

- **OpenRouter** (`openrouter.ai`) — receives your cleaned transcript + profile + dictionary + selected-text context every time you dictate, **if** OpenRouter is your backend (the default). Governed by OpenRouter's terms.
- **OpenAI** (`api.openai.com`) — same data, only if you pick `--backend openai`. Governed by OpenAI's API terms.
- **Anthropic** (`api.anthropic.com`) — same data, only if you pick `--backend anthropic`. Governed by Anthropic's API terms.
- **Groq** (`api.groq.com`) — same data, only if you pick `--backend groq`. Governed by Groq's API terms.
- **Ollama** (`http://localhost:11434` by default) — runs on your machine. No third party.
- **`none`** — no LLM call. The raw Whisper output is pasted without cleanup.
- **HuggingFace** (`huggingface.co`) — used **once**, during first-run, to download the Whisper model file. No account required, no PII sent. After that, the model is on disk and never re-fetched unless you change models.
- **GitHub** (`api.github.com`) — used for the once-per-launch update check (opt-out via `--update-check off`). Public endpoint, no auth.
- **Homebrew** (`brew.sh`) — used during install to fetch `whisper-cpp`. Standard Homebrew telemetry applies (you can opt out of that separately via `HOMEBREW_NO_ANALYTICS=1`).

If you set `--backend ollama` or `--backend none` and leave `--update-check off`, nothing leaves your Mac at runtime.

### What "selected text" means in the context payload

When you trigger dictation with text selected in the focused app, OpenVoiceFlow reads that selection (via the macOS Accessibility API) and sends it to the LLM as part of the user message, so the cleanup can match the surrounding context. Two implications worth flagging:

- Whatever you have selected when you start dictating goes to your chosen LLM backend. If that's OpenRouter/OpenAI/Anthropic/Groq, treat selected text the same way you'd treat anything you paste into a chat with that provider.
- This behavior is controlled by the `selected_text_context` config key (on by default). There is no current CLI flag to toggle it; edit `~/.openvoiceflow/config.json` to disable. (Tracked as a v0.3 follow-up.)

---

## 4. Permissions you grant macOS

OpenVoiceFlow asks macOS for these privileges. You grant them in **System Settings → Privacy & Security**, and you can revoke them at any time.

- **Microphone** — to capture audio while you hold the hotkey. Required for dictation.
- **Accessibility** — used for two things:
  1. **Auto-paste** — sending the cleaned text to the focused text field via simulated keystrokes.
  2. **Auto-learn** — reading the focused text field for 30 seconds after every paste, so the app can detect corrections you make and learn them. This is **off by default**. The Know Me interview asks before turning it on.
- **Apple Events** — to detect the frontmost app (so per-app styles work) and to perform the paste. Granted alongside Accessibility.
- **Notification Center** — to show a single notification when a newer release is available on GitHub. Only used by the update check; if you set `--update-check off`, no notifications are posted.

---

## 5. Defaults you can change

Every privacy-relevant default is one CLI flag away.

| Setting | Default | What it controls | Flag to change |
|---|---|---|---|
| `log_transcripts` | **off** | Writes every dictation (raw + cleaned) to `~/.openvoiceflow/logs/`. | `--log-transcripts on/off` |
| `auto_learn` | **off** | Reads the focused text field for 30 s post-paste to learn corrections. | `--auto-learn on/off` |
| `update_check` | on | Once-per-launch GitHub API check for a newer release. | `--update-check on/off` |
| `llm_backend` | `openrouter` | Which LLM backend (or none) cleans up your transcript. | `--backend openrouter\|openai\|anthropic\|groq\|ollama\|none` |
| `voice_commands` | on | Replaces spoken punctuation phrases ("new line", "comma") locally, before any LLM call. | `--voice-commands on/off` |
| `streaming` | on | Uses `whisper-stream` for real-time partial transcription. Audio still never leaves your Mac. | `--streaming on/off` |
| `auto_style` | on | Switches dictation style based on the frontmost app. Reads only the app name (via Apple Events), not its content. | `--auto-style on/off` |

To see your current settings, run `openvoiceflow --show-config`.

---

## 6. What we don't do

- **No telemetry.** We do not collect usage data, feature usage, dictation counts, error rates, or anything else. Nothing about how you use the app is sent anywhere.
- **No analytics.** No Google Analytics, no Mixpanel, no PostHog, no Segment, no Amplitude.
- **No crash reports.** If the app crashes, the crash dies with it. macOS may keep a system-level crash log under `~/Library/Logs/DiagnosticReports/`; that's Apple's, not ours.
- **No shared keys.** OpenVoiceFlow ships with no embedded API keys. You bring your own.
- **No cloud sync.** Your config and profile do not sync across machines. If you want them on a second Mac, copy `~/.openvoiceflow/` yourself.
- **No accounts.** There is no sign-up, no login, no email collected.
- **No third-party SDKs.** The Python dependencies are listed in `pyproject.toml`; none of them are analytics or tracking SDKs.
- **No retention or rotation logic.** We don't expire your files for you. Everything stays on disk until you delete it. To wipe what OpenVoiceFlow knows about you, quit the app, then `rm -rf ~/.openvoiceflow/` (and `rm ~/Library/LaunchAgents/com.openvoiceflow.app.plist` if you enabled launch-at-login). The next launch will be treated as a first run. Anything you've already sent to a cloud LLM lives by that provider's retention policy — delete it through their account or API.

---

## 7. GDPR posture

OpenVoiceFlow is a **bring-your-own-key (BYOK), self-managed, personal-productivity tool**. Practically:

- **OpenVoiceFlow is not a controller or processor** of your personal data under GDPR. We don't run servers and we have no copy of anything you dictate, store, or configure.
- **You are the controller** of the data on your Mac. You decide whether to fill out the Know Me interview, whether to log transcripts, and which LLM backend (if any) to use.
- **Each LLM provider you choose is an independent controller / processor** for the text you send them. If you need a Data Processing Addendum (DPA), Standard Contractual Clauses, or any other GDPR paperwork, you negotiate that **directly with that provider** under your own account. OpenVoiceFlow cannot sign a DPA on their behalf and does not pretend to.
- **EU users:** if your dictations contain personal data and you point the app at a non-EU cloud LLM (OpenRouter, OpenAI, Anthropic, Groq), you are responsible for the lawful basis and the international-transfer story. The simplest way to take every cloud provider out of the picture is `--backend ollama` or `--backend none`.
- **Regulated industries (healthcare, legal, financial, government):** OpenVoiceFlow has no SOC 2, no ISO 27001, no HIPAA BAA, and no FedRAMP. Don't use it for regulated data unless you have your own compliance overlay (your own DPA with the LLM provider, your own air-gapped Ollama deployment, your own organizational controls).

---

## 8. Children's privacy / COPPA

OpenVoiceFlow is not designed for, and not directed to, children under 13. We do not knowingly collect data from anyone (kids included), but we also don't perform any age verification. If a child under 13 is using your Mac and dictating into a cloud LLM, the LLM provider's children's-privacy policy applies, not ours.

---

## 9. Changes to this policy

This file is versioned alongside the code. Material changes get a line in `CHANGELOG.md` under the release that introduces them, and the diff is visible in `git log PRIVACY.md`. There is no email list, no banner, no "we've updated our privacy policy" pop-up — if you want to track changes, watch the repo or read the changelog when you upgrade.

---

## 10. Contact

- **Security issues** (vulnerabilities, exposed-key bugs, anything that needs a private disclosure channel): see [`SECURITY.md`](SECURITY.md).
- **General privacy questions** (what does this flag do, why does this connection happen, can we add an option for X): open a [GitHub Discussion](https://github.com/shimoverse/openvoiceflow/discussions).
- **Repo:** <https://github.com/shimoverse/openvoiceflow>

If something on this page is wrong, out of date, or doesn't match what the code actually does, that's a bug. Tell us.

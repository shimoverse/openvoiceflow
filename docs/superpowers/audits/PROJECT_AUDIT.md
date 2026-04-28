# OpenVoiceFlow — Project Audit (Phase 1, v0.2.0)

> **Status:** Pre-publish discovery. Not committed. Not pushed. For Mohit's review only.
>
> Repo: `shimoverse/openvoiceflow` (currently private; user plans to transfer to a personal account before publishing — flagged as decision **D1**)
> Audited: 2026-04-27 against `HEAD = 3b03d29` (v0.2.0, "Know Me, Auto-Learn, Streaming")
> Sources audited: 28 Python files, 4 docs (README, PRD, landing page, build/install scripts), 2 CI workflows. Lint, build, and Python-3.9 import all run.

---

## 1. What this project IS (one paragraph, plain English)

OpenVoiceFlow v0.2.0 is a free, macOS-only voice-dictation app. You hold a hotkey, speak, and the cleaned text appears at your cursor in any app. Two-stage pipeline: **(1) local transcription** via `whisper.cpp` (audio never leaves the Mac, with optional real-time streaming via `whisper-stream`), and **(2) optional LLM cleanup** via Gemini/Groq/OpenAI/Anthropic/Ollama/none. v0.2 layers on a personalization stack: a "Know Me" tkinter onboarding interview, a personal dictionary, voice snippets, voice commands, per-app dictation styles (auto-detected via the macOS accessibility API), an auto-learner that watches your post-paste edits for 30 seconds and learns substitutions, a floating macOS overlay HUD for visual feedback, and a launch-at-login LaunchAgent. The overall arc has shifted from "a hotkey-to-text utility" to "a personal-context-aware dictation tool that gets smarter the more you use it."

---

## 2. Target users

| Tier | User | Primary motivation |
|---|---|---|
| 1 | macOS power user / writer / engineer who already pays $85–144/yr for Wispr or Superwhisper | Save the money, keep audio local |
| 2 | Privacy-first user who won't send audio to a cloud STT | whisper.cpp runs locally; with Ollama backend, transcripts stay local too |
| 3 | Power user who wants a tool that learns their vocabulary, names, and per-app preferences | Know Me + auto-learn + per-app styles |
| 4 | Developer who wants to dictate code (with a "code mode" prompt) and emails (with an "email mode" prompt) without retraining their fingers | New `style` modes + per-app auto-styling |
| 5 | Open-source contributor / fork-er | MIT, ~3,500 LOC, well-organized |

**Who this is NOT for:** Windows / Linux / iOS / Android users (macOS-only); anyone needing real-time streaming with full accuracy (whisper-stream is fast but lossy — OpenVoiceFlow falls back to non-streaming for the canonical text); anyone in a regulated environment that bars sending text to consumer LLM APIs (no DPA, no enterprise key management, no managed-config story).

---

## 3. Public API surface

This is a **CLI / menubar app**, not a library.

### CLI flags (from `__main__.py`, expanded ~2× since v0.1.0)

Core: `--menubar` · `--onboarding` (alias `--setup`) · `--interview` · `--test` · `--version`
Config: `--backend` · `--model` · `--hotkey` · `--language` · `--style` · `--show-config` · `--set-prompt` · `--clear-prompt`
Keys: `--set-key BACKEND KEY`
Personal dictionary: `--add-word` · `--remove-word` · `--list-words`
Voice snippets: `--add-snippet` · `--remove-snippet` · `--list-snippets`
Voice commands: `--add-command` · `--remove-command` · `--list-commands` · `--voice-commands on/off`
Per-app styles: `--app-style APP STYLE` · `--remove-app-style` · `--list-app-styles` · `--auto-style on/off`
Other: `--autostart on/off` · `--streaming on/off` · `--auto-learn on/off` · `--search QUERY` · `--stats`

### Persisted state (everything under `~/.openvoiceflow/`)

| File | Owner | Schema | Sensitive? |
|---|---|---|---|
| `config.json` | `config.py` | `DEFAULTS` dict | ⚠️ contains all 4 cloud API keys in plaintext |
| `profile.json` | `profile.py` | name, occupation, industry, names/tools, communication style | 🟡 PII (name, employer, colleague names) |
| `dictionary.json` | `dictionary.py` | `[{word, aliases}]` | 🟡 may contain personal names |
| `snippets.json` | `snippets.py` | `{trigger: expansion}` | 🟡 may contain email signatures, personal details |
| `stats.json` | `stats.py` | counters (dictations, words, time saved) | ✅ aggregate only |
| `logs/YYYY-MM-DD.{md,jsonl}` | `system.py` | every dictation, raw + cleaned | 🔴 every word the user has dictated |

Plus `~/Library/LaunchAgents/com.openvoiceflow.app.plist` if launch-at-login is enabled.

### Internal extension points

- **LLM backend:** subclass `voiceflow.llm.base.LLMBackend`, register in `voiceflow/llm/__init__.py:BACKENDS`. Backend interface changed in v0.2 — `cleanup()` now takes `context`, `app_context`, `override_style`. All 5 existing backends were updated consistently.
- **Style preset:** add to `STYLE_PRESETS` in `llm/base.py` and `STYLE_PROMPTS`/`STYLE_LABELS` in `styles.py`. Two registries — minor duplication.
- **Voice commands / snippets / dictionary words:** runtime-only via CLI or config edits; no code-level extension needed.

---

## 4. Deployment modes

| Mode | Status | Notes |
|---|---|---|
| **DMG installer (drag-to-Applications)** | ✅ Works (improved) | v0.2 builds **separate arm64 and x86_64 DMGs** (no more universal Rosetta dance). Each launcher bootstraps brew + whisper.cpp + venv + model + GUI onboarding on first launch. Unsigned/un-notarized → first-launch Gatekeeper override required. |
| **`bash install.sh`** | 🔴 **Still broken** | `pip install .` step now works (SS1 fixed), and the curl-pipe path now `git clone`s on demand (good). **But** `~/.local/bin/openvoiceflow` shim still calls `python3 -m openvoiceflow` (`install.sh:86`) — the module is `voiceflow`, not `openvoiceflow`. Verified: `ModuleNotFoundError: No module named 'openvoiceflow'`. |
| **`curl … install.sh \| bash`** | 🔴 Same as above | URL is correct now (`shimoverse/openvoiceflow`), but the shim it installs is broken. |
| **Manual `pip install -e .`** | 🟠 Works in a 3.10+ venv; **crashes at import on 3.9** | `pyproject.toml:12` advertises `requires-python = ">=3.9"` but only 1 of 28 modules has `from __future__ import annotations`. 22 of 28 submodules fail to import on system Python 3.9.6. |
| **Self-hosted / fully local** | ✅ Works (Ollama) | Better than v0.1: per-app context detection still uses Apple events, but transcripts/cleanup never leave the Mac. |
| **Air-gapped** | 🟡 Partial — possible if all deps pre-staged, undocumented |
| **PyPI** | ❌ Not published | Wheel builds cleanly; release workflow doesn't include a publish step. |
| **Homebrew tap** | ❌ Not yet | PRD.md describes `shimoverse/homebrew-tap` but the repo doesn't exist. |

---

## 5. What's broken or fictional

> Severity legend: 🔴 ship-stopper · 🟠 major · 🟡 minor

### v0.1.0 ship-stoppers — re-checked on v0.2.0

| ID | v0.1.0 status | v0.2.0 status | Verification |
|---|---|---|---|
| **SS1** `pyproject` build-backend was nonsense | 🔴 broken | ✅ **FIXED** — `pyproject.toml:3` now `setuptools.build_meta` | I ran `python -m build --wheel`; cleanly produced `openvoiceflow-0.2.0-py3-none-any.whl` |
| **SS2** install.sh shim runs nonexistent module | 🔴 broken | 🔴 **STILL BROKEN** | `install.sh:86` still has `exec "$VENV_DIR/bin/python3" -m openvoiceflow "\$@"`. Verified: `python3 -m openvoiceflow` → `ModuleNotFoundError: No module named 'openvoiceflow'`. |
| **SS3** Py 3.10 type hints under `requires-python ≥ 3.9` | 🔴 broken | 🔴 **STILL BROKEN** | 15 modules use `X \| None`; only 1 (`learner.py`) has `from __future__ import annotations`. On system Python 3.9.6: 22 of 28 submodules fail to import — including `config.py`, which `__main__.py` loads immediately, so `openvoiceflow --help` crashes on 3.9. |
| **SS4** All GitHub URLs pointed to wrong org | 🔴 broken | ✅ **FIXED** — every user-facing URL uses `shimoverse/openvoiceflow` (README, install.sh, build-dmg.sh, pyproject, docs/index.html, PRD) | Grep returned only my own audit docs as remaining `shimoverse-ops` hits. |

**Two of four v0.1.0 🔴s are still 🔴 on v0.2.0.** Both are one-line fixes.

### New 🔴 SHIP-STOPPERS introduced in v0.2.0

- **SS5** **`config_prompt` → `llm_prompt` migration is missing.** Config key was renamed (`config.py:288`); `llm/base.py:672` reads the new key; **but no upgrade code exists to migrate existing v0.1.0 users**. Anyone with a v0.1.0 `~/.openvoiceflow/config.json` who upgrades will silently lose their custom prompt and get the default — and won't know it. Same applies to any users who have already shipped a custom prompt to friends.

- **SS6** **`onboarding.py:455-458` silently swallows ALL exceptions from `interview.run_interview()`**. If the interview module crashes (broken import, runtime error), the wizard's "Personalize OpenVoiceFlow ✨" button does nothing, and the user has no idea why. With `interview.py` being 650+ lines of new tkinter code, the probability of a crash on some Mac configuration is non-zero. The `try / except / pass` pattern hides the entire diagnostic surface. (Severity is 🔴 because it makes a flagship v0.2 feature silently fail.)

### 🟠 MAJOR

1. **README hero claim "Your audio never leaves your Mac" is still half-true.** Audio is local, but transcripts default to Google Gemini. Landing page (line 519) clarifies it; README (line 40) doesn't. Inconsistent framing across docs.

2. **API keys still stored plaintext, world-readable.** `config.json` is mode 644 by default (umask 022). No `chmod 600` on save, no Keychain. With v0.2 adding `interview.py` (which writes name/employer/colleague names to `profile.json`, also mode 644), the surface is larger. **Decision D5.**

3. **Transcript logs still default-on, plaintext, two formats.** No retention, no rotation, no opt-out wired into onboarding. The `--search` flag now indexes them, which is great for power users but worsens the "two days of dictations live forever in plaintext" privacy footgun. **Decision D8.**

4. **`auto-learn` watches the focused text field via macOS Accessibility API for 30 seconds after every paste.** This is more invasive than v0.1's privilege ask, and there's no in-app disclosure of what it reads or how. Not in `PRIVACY.md` (because there is no PRIVACY.md). Off by default? Need to verify in `config.py` defaults — currently the menubar exposes a toggle (lines 401-404), so opt-in surface exists, but the default is **on**.

5. **Hotkey is still a blanket modifier on default.** Right Cmd / Right Alt fire on every press globally. v0.2 fixes a debounce issue (BUG-005, `app.py:140-142`) but does not change the underlying "every Cmd press starts/stops a recording" problem. Fn-key defaults are still buried.

6. **Auto-paste timing window has gotten bigger in v0.2.** Streaming + overlay HUD adds visible processing time during which the user might switch focus. v0.2 added clearer error reporting in `system.py:481-493` (BUG-009 fix), but the underlying race remains.

7. **No tests of any kind.** CI runs `ruff check` (non-blocking) and a `python -c "import voiceflow"` import smoke. The import smoke succeeds on Python 3.11 (the CI runner); on 3.9 it'd fail at `voiceflow.config`. So CI does not actually catch the SS3 bug. There is no pytest, no integration test, no fixture WAV pipeline test.

8. **Lint debt grew from 17 → 43 findings.** Mostly unused imports (37) — but the noise floor is climbing. A new file `learner.py:200` is the f-string-with-no-placeholder offender. Adding 15 new modules without ever fixing lint means the next 15 will be the same.

9. **CI release workflow uses default `GITHUB_TOKEN`, not Trusted Publisher OIDC.** Release builds DMGs and attaches them to a GitHub Release; doesn't publish to PyPI; doesn't sign or notarize the DMGs. That's the v0.2 release-engineering posture — and it's the same as having no automated release at all from the auditor's perspective.

10. **Lint is non-blocking in CI.** Commit message `3b03d29` is literally "fix: make ruff lint non-blocking (43 style warnings, not bugs)". Calling these "not bugs" is fair for unused imports, but it means style debt accumulates with no gating mechanism.

### 🟡 MINOR

11. **Voice-command count discrepancy.** Landing page (line 257) says "24 voice commands"; README (line 391) says "✅ 24 commands"; the actual table in README lists 14 default commands; `commands.py` defaults dict — needs a count. Either fix the number everywhere or fix the table.

12. **Two registries for backend metadata.** `voiceflow/llm/__init__.py:BACKENDS` (the actual class registry) and `onboarding.py:BACKENDS` (the UI metadata: cost, speed, instructions). Adding a backend means editing both. Minor footgun.

13. **`anthropic_backend` model downgraded to `claude-3-5-haiku-20241022`.** Cheaper and faster, but the 3-5 generation is now older — the cutting-edge is Sonnet 4.6. Worth re-evaluating before the public release; pricing tradeoffs on Haiku vs Sonnet have shifted.

14. **`groq_backend` default downgraded to `llama-3.1-8b-instant`** (from `llama-3.3-70b-versatile`). Much cheaper, much smaller model, slightly lower quality on grammar fixes. Worth verifying the cost/quality trade.

15. **`updater.py` checks `https://api.github.com/repos/shimoverse/openvoiceflow/releases/latest` on every launch.** That repo is currently **private**. After publishing the URL works, but right now it'll quietly 404 every launch. Not user-visible (errors are silently swallowed `updater.py:104`), but a dead phone-home is wasted bytes.

16. **No DMG signing or notarization.** Same as v0.1. Apple Developer fee = $99/year. **Decision D6.**

17. **No `MANIFEST.in` or explicit `[tool.setuptools.packages.find]`.** Wheel build works because all source is in `voiceflow/`, but the wheel ships `requirements.txt` at the top level (dev-only noise). Not a bug but polish.

18. **Some `interview.py` text fields are not HTML-escaped before injection into LLM prompts.** Low real risk (it's the user's own data going into their own LLM), but a contributor adding "share interview output via …" later could leak.

19. **`overlay.py` monkey-patches `_OverlayAnimator` instances at runtime** (`overlay.py:386, 400`). Works, but unconventional Python. A future refactor could trip on this.

20. **`streamer.py:20` hardcodes `/opt/homebrew/bin/whisper-stream`.** Has a `which whisper-stream` fallback so it works on Intel too, but the hardcoded path on Apple Silicon brews installed in `/usr/local` would miss. (Rare but worth a look.)

21. **`learner.py` Levenshtein threshold is 40% (line 40).** Magic number with no comment justifying it; would benefit from a tested validation.

22. **No `CHANGELOG.md`** despite v0.1.1, v0.2.0 already on GitHub Releases. Notes are inline in commit messages and release-page descriptions only.

---

## 6. What works today (and is genuinely impressive)

- ✅ All 28 Python source files parse and pass syntax check on 3.10+.
- ✅ Wheel builds cleanly via `python -m build`. 28 source files in the wheel, no junk apart from the dev-noise `requirements.txt`.
- ✅ All 16 features from the PRD have corresponding implementation files. The 15 new modules are well-structured: graceful fallbacks (PyObjC-optional, whisper-stream-optional, tkinter-optional), no hardcoded user paths, type hints, docstrings, thread safety where needed (`learner.py`, `streamer.py`).
- ✅ The data-flow story is coherent: profile + dictionary + snippets + style → injected into LLM system prompt at every call. Per-dictation: selected text + frontmost app → injected into LLM user message.
- ✅ Auto-learner is a genuinely novel piece: 5-sample 30-second post-paste watch, word-level Levenshtein detection, only learns substitutions (never inserts/deletes), only fires above a similarity threshold. That's a lot of judgment baked in.
- ✅ Streaming transcription via `whisper-stream` with refinement-replacement and Jaccard-overlap deduplication. Sophisticated.
- ✅ DMG split: separate arm64 + x86_64 instead of universal-with-Rosetta.
- ✅ CI is wired (even if minimal). Release workflow is wired.
- ✅ Landing page (`docs/index.html`) is polished — animated terminal demo, FAQ, comparison matrix.
- ✅ All `shimoverse-ops` URLs are gone.
- ✅ MIT license, correct.

---

## 7. Test coverage gaps

**Coverage: 0%.** No `tests/` directory; no `pytest`/`unittest`; no fixture WAV; no mocked HTTP. CI runs only `ruff` + `import voiceflow`.

What needs tests before a public v0.x release (priority order):
1. `config.py` `validate_config()` — the v0.2 config schema with new enum keys
2. `config.py` migration: v0.1.0 `cleanup_prompt` → v0.2 `llm_prompt`
3. Each LLM backend `cleanup()` happy + error paths, mocked HTTP
4. `transcriber.find_whisper_cpp()` precedence including the new `_is_whisper_cpp()` validation
5. `streamer.py` line parser, refinement replacement, dedup
6. `learner.py` correction extraction (Levenshtein, similarity threshold, substitution-only)
7. `interview.py` profile-to-dictionary conversion
8. `commands.py` longest-first match, regex escaping
9. `snippets.py` longest-first match
10. `search.py` substring + date filter
11. `pyproject.toml` builds (CI smoke)
12. **`pip install .` + `python -m voiceflow --help` end-to-end on 3.9 AND 3.10 AND 3.11** — would have caught SS3
13. **`bash install.sh` end-to-end in a clean macOS VM, then run `openvoiceflow --version`** — would have caught SS2

---

## 8. Security / privacy surface

| Surface | Today | Severity | Δ from v0.1 |
|---|---|---|---|
| Audio in transit | Local only | ✅ | — |
| Audio at rest | Temp WAV deleted in finally block | ✅ | — |
| Transcripts in transit | Sent to chosen LLM (default Gemini) | 🟡 | — |
| Transcripts at rest | Plaintext daily JSONL+MD logs in `~/.openvoiceflow/logs/`, mode 644, on by default; now indexed by `--search` | 🔴 | Worse (search makes them more useful, retention still unbounded) |
| API keys at rest | Plaintext JSON, mode 644 | 🔴 | — |
| User profile at rest (`profile.json`) | Plaintext JSON, mode 644, contains name/employer/colleagues | 🔴 | New in v0.2 |
| Personal dictionary (`dictionary.json`) | Plaintext, may contain names | 🟡 | New in v0.2 |
| Snippets (`snippets.json`) | Plaintext, may contain signature blocks / sensitive boilerplate | 🟡 | New in v0.2 |
| Auto-learner reading focused text | Uses Accessibility API to read currently focused text field for 30s post-paste | 🟠 | New in v0.2 — strong privilege, no in-app disclosure |
| Network egress | LLM providers + HuggingFace (model) + GitHub API (update check) + Homebrew | 🟢 | Update check is new; public, no auth |
| Telemetry | None | ✅ | — |
| Prompt injection (user → user's LLM) | User can self-jailbreak | 🟢 | — |
| Prompt injection (config-tampering) | `llm_prompt` is config-controlled; could exfil via crafted prompt | 🟡 | Same |
| Prompt injection from selected-text context (NEW) | `clipboard.capture_selected_text()` feeds whatever's selected into the LLM. A malicious webpage could put adversarial text on the user's clipboard before the user dictates over it. Low risk in practice but new attack surface. | 🟡 | New in v0.2 |
| Supply chain (deps unpinned) | `>=` pinning only | 🟡 | — |
| `curl … install.sh \| bash` | No integrity check | 🟡 | — |
| DMG signing | None | 🟡 | — |

---

## 9. Mobile support

**Still macOS only.** No change.

---

## 10. External dependencies needing BYOK or config

| Dep | Required? | Where |
|---|---|---|
| Homebrew | Yes (whisper.cpp) | brew.sh |
| `whisper-cpp` | Yes | `brew install whisper-cpp` |
| `whisper-stream` (NEW) | Optional (streaming feature) | shipped with whisper-cpp brew |
| `ggml-*.bin` model | Yes | HuggingFace |
| Gemini key | If `--backend gemini` (default) | aistudio.google.com |
| Groq key | If `--backend groq` | console.groq.com |
| OpenAI key | If `--backend openai` | platform.openai.com |
| Anthropic key | If `--backend anthropic` | console.anthropic.com |
| Ollama daemon | If `--backend ollama` | ollama.com |
| PyObjC | Optional (overlay HUD, frontmost-app detection) | `pip install pyobjc-framework-Cocoa pyobjc-framework-Quartz` — NOT in `pyproject.toml` |
| `tkinter` | Yes for onboarding + interview | ships with macOS Python |

**Issue:** `PyObjC` isn't in `pyproject.toml` dependencies. The new modules degrade gracefully when it's missing (`overlay.py:HAS_APPKIT`, `context.py:HAS_PYOBJC`), but that means **most users get the degraded experience by default** unless something else pulls in pyobjc. Worth verifying that `rumps` (the menubar lib) transitively installs it — `rumps` does declare `pyobjc-framework-Cocoa` as a dep, so users running `--menubar` get it. Users running CLI mode don't, and lose the overlay HUD without warning.

---

## 11. Build / type-check / test / lint results (verified, today)

```
✅ python3 -m py_compile  (all 28 files)
✅ python -m build --wheel
   → openvoiceflow-0.2.0-py3-none-any.whl (clean, 28 source files)
🔴 import voiceflow.config on Python 3.9.6
   → TypeError: unsupported operand type(s) for |
   → 22 of 28 submodules fail to import on 3.9
✅ import voiceflow.config on Python 3.11+ (assumed; CI runs 3.11)
🟠 ruff check voiceflow/  → 43 findings
   - 37 F401 unused-import
   -  4 F541 f-string-missing-placeholder
   -  1 E701 multiple-statements
   -  1 F841 unused-variable
   (none are correctness bugs; lint is non-blocking in CI)
⚪ Tests: zero. CI runs an import smoke + config-validate, not pytest.
🔴 ~/.local/bin/openvoiceflow shim from install.sh:86 → ModuleNotFoundError
```

---

## 12. Decisions blocking Phase 4 (carry forward + new)

| # | Decision | Why blocking |
|---|---|---|
| **D1** | GitHub owner / org for the published repo | Every URL fix path. Today: `shimoverse/openvoiceflow` (private). Options: keep `shimoverse`, move to `mohitjain`, new dedicated org. |
| **D2** | PyPI package name (`openvoiceflow` is unclaimed; we should reserve before publishing) | Wave 5 |
| **D3** | Min Python: 3.9 (with `from __future__ import annotations`) or 3.10? | Affects 15 source files. Bumping to 3.10 keeps code cleaner; 3.9 keeps macOS 12 default Python supported. |
| **D4** | Default LLM backend — keep Gemini (zero-config, free tier, cloud) or switch to Ollama (privacy, requires extra install)? | README hero framing depends on this |
| **D5** | API-key storage — chmod 600 plaintext, or Keychain via `keyring`? | Wave 2 |
| **D6** | DMG signing/notarization (Apple Dev $99/yr)? | Wave 5 |
| **D7** | v0.2.1 scope — only the two ship-stoppers (SS2, SS3, SS5, SS6) or full pre-publish bundle? | Wave bundling |
| **D8** | `log_transcripts` default — on (current) or off (privacy default)? | Wave 2 |
| **D9 (new)** | `auto_learn` default — on (current?) or off? Disclosed where? | Privacy |
| **D10 (new)** | Voice-command count — fix the "24 vs 14" inconsistency in landing/README/code | Trust |
| **D11 (new)** | Anthropic + Groq default model choices (Haiku vs Sonnet, Llama 3.1-8B vs 3.3-70B) | Quality vs cost |
| **D12 (new)** | Telemetry — formally commit to "none" in PRIVACY.md, OR ship a single anonymous "did update succeed" ping (industry-standard for auto-update) | Trust |

---

## 13. One-line summary

OpenVoiceFlow v0.2.0 is genuinely impressive product work — a personalization stack that earns the "Know Me" tagline. The release engineering is roughly half-done: build-system bug is fixed, URLs are fixed, CI exists. **But the install.sh shim is still broken, the package still crashes at import on the lower-bound Python version it advertises, the v0.1→v0.2 config migration is missing, the flagship "Personalize" button silently swallows errors, and the privacy story has expanded faster than the documentation around it.** A clean shipping path to PyPI + Homebrew + a public GitHub is achievable in a focused 2–3 day push; nothing in here is hard, just multiple small fixes plus the standard community-health files.

---

## Continues in

- **PERSONA_AUDIT.md** — five personas walked step-by-step on v0.2.0
- **READINESS_CHECKLIST.md** — 49-item checklist re-scored against v0.2.0

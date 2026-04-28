# Changelog

All notable changes to OpenVoiceFlow are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
(with the pre-1.0 caveat documented in [VERSIONING.md](VERSIONING.md)).

## [Unreleased]

Tracking toward **0.3.0** — the pre-publish readiness pass. See
[`docs/superpowers/specs/v0.3-readiness.md`](docs/superpowers/specs/v0.3-readiness.md)
for the full spec.

### Added
- Pytest scaffold under `tests/` with smoke tests for config, transcriber argv
  assembly, LLM backends (mocked HTTP), commands/snippets matchers, learner
  correction extraction, and search filtering.
- `[dev]` extras in `pyproject.toml` (pytest, ruff, build, twine).
- CI Python matrix: 3.9, 3.10, 3.11 on macos-latest. Each leg runs
  `pip install .` and exercises `openvoiceflow --version`.
- `--update-check on/off` CLI flag and matching `update_check` config key
  for opting out of the daily GitHub-Releases ping.
- `--log-transcripts on/off` CLI flag for explicit control of the
  `~/.openvoiceflow/logs/` daily files.
- "Privacy at a glance" panel in the README that maps every on-disk file
  and every network egress in one table.
- `voiceflow/_secure_io.py` — `write_json_600()` helper that all
  config/profile/dictionary/snippets/stats writes now go through, plus a
  matching `chmod 600` on first-write of the daily log files.

### Changed
- **Config-key migration:** `cleanup_prompt` → `llm_prompt`. Existing
  `~/.openvoiceflow/config.json` files are migrated transparently on load;
  the rename was the v0.2.0 schema change that previously dropped users'
  custom prompts on upgrade. (Fixes SS5.)
- **Privacy defaults flipped to off for fresh installs.** New users get
  `log_transcripts: False` and `auto_learn: False` until they opt in via the
  Know Me onboarding interview. **Existing users keep their setting** — the
  migration logic only applies the new defaults when no config exists.
- `install.sh` shim now `exec`s the pip-installed `openvoiceflow` console
  script directly instead of `python3 -m openvoiceflow` (which never existed —
  the module is `voiceflow`). (Fixes SS2.)
- **Lint is now blocking in CI.** Previously `ruff check` was advisory; the
  43-finding backlog meant noise floor only ever climbed.
- README hero rewritten so the privacy framing matches the actual data flow
  (audio is local; transcripts go to whatever LLM backend you pick; default
  Gemini is cloud, Ollama is local).

### Fixed
- **SS2** — `install.sh` shim no longer crashes with
  `ModuleNotFoundError: No module named 'openvoiceflow'`.
- **SS3** — `from __future__ import annotations` added to all 30 modules
  using `X | None` syntax. `pip install .` and `openvoiceflow --version`
  now work on Python 3.9 (macOS 12 default) in addition to 3.10 / 3.11.
- **SS5** — Silent loss of custom `cleanup_prompt` on v0.1 → v0.2 upgrade.
  Migration now preserves the user's prompt under the new key.
- **SS6** — Onboarding "Personalize OpenVoiceFlow" button no longer
  silently swallows every exception from `interview.run_interview()`.
  Errors surface with a logged traceback and an in-app message.
- The cargo-culted PyObjC import in `overlay.py` that broke the module
  for anyone installing without the `[overlay]` extra.
- 43 lint findings (37 unused imports, 4 placeholder-less f-strings,
  1 multiple-statements, 1 unused variable). All resolved; lint now gates CI.

### Security
- All `~/.openvoiceflow/*.json` files (config, profile, dictionary,
  snippets, stats) and the daily transcript logs are written with
  mode 600 — owner-only — instead of inheriting umask 022. API keys
  and personal data are no longer world-readable on default macOS
  user accounts.
- Lint gating in CI closes the "style debt grew silently" loop.
- Twelve community-health files added so a procurement reviewer can find
  the answers they need without filing an issue: `SECURITY.md`,
  `PRIVACY.md`, `THREAT_MODEL.md`, `COMPLIANCE.md`, `CODE_OF_CONDUCT.md`,
  `CONTRIBUTING.md`, `SUPPORT.md`, `CHANGELOG.md` (this file),
  `VERSIONING.md`, `COMPATIBILITY.md`, `legal/DPA-template.md`,
  `legal/THIRD_PARTY_NOTICES.md`.

---

## [0.2.0] — 2026-03-15

**Know Me, Auto-Learn, Streaming.** Personalization stack landed. The
arc shifted from "hotkey-to-text utility" to "personal-context-aware
dictation that gets smarter the more you use it."

### Added
- **Know Me** — tkinter onboarding interview. Captures name, occupation,
  industry, frequently-mentioned names/tools, communication style.
  Output is injected into every LLM cleanup prompt as system context.
- **Auto-learn** — watches the focused text field via the macOS
  Accessibility API for 30 seconds after every paste and learns
  word-level substitutions from your edits. Levenshtein-gated,
  substitutions only (never inserts/deletes), 5-sample minimum.
- **Streaming transcription** via `whisper-stream` with
  refinement-replacement and Jaccard-overlap deduplication. Falls back
  to non-streaming for the canonical text.
- **Per-app context + per-app styles** — frontmost-app detection via
  Apple events; the cleanup prompt picks up the right style automatically
  (e.g. terse in Slack, formal in Mail).
- **Voice commands** — say "new line", "period", "delete that", etc.
  Configurable via `--add-command` / `--remove-command` /
  `--list-commands` / `--voice-commands on/off`.
- **Clipboard / selected-text context** — whatever's selected when you
  start dictating gets handed to the LLM as context.
- **History search** — `--search QUERY` greps the daily transcript logs.
- **Voice snippets** — trigger-phrase → expansion. `--add-snippet` /
  `--remove-snippet` / `--list-snippets`.
- **Personal dictionary** — proper-noun and acronym table.
  `--add-word` / `--remove-word` / `--list-words`.
- **Launch-at-login** — `--autostart on/off`; writes a LaunchAgent plist.
- **Statistics** — `--stats` shows dictations, words, time saved.
- **Auto-update notifier** — once-a-day check against the GitHub
  Releases API; quiet on failure.
- **Floating macOS overlay HUD** — visual feedback during recording,
  streaming, and auto-learn moments.
- New CLI flags across the board: `--version`, `--show-config`,
  `--set-prompt`, `--clear-prompt`, `--set-key`, `--app-style`,
  `--remove-app-style`, `--list-app-styles`, `--auto-style on/off`,
  `--streaming on/off`, `--auto-learn on/off`.

### Changed
- DMG installer split into separate `arm64` and `x86_64` artifacts —
  one-click install on any Mac, no Rosetta dance.
- `pyproject.toml` gained an `[overlay]` extra for the optional PyObjC
  dependencies (Cocoa, Quartz). `rumps` (the menubar lib) transitively
  installs Cocoa, so menubar users get the HUD by default.
- Codebase grew from ~13 modules to ~28. Backend `cleanup()` interface
  now accepts `context`, `app_context`, `override_style`; all 5 existing
  backends were updated consistently.
- Anthropic default model: `claude-3-5-haiku-20241022`.
- Groq default model: `llama-3.1-8b-instant`.

### Fixed
- 22 bugs from a deep QA audit (#3): debounce on the recording hotkey,
  auto-paste timing window, error reporting in `system.py`, and a long
  tail of small UX papercuts.

---

## [0.1.1] — 2026-03-01

Bug-fix release.

### Fixed
- Rosetta + macOS compatibility. The launcher now smart-detects
  architecture (Apple Silicon vs Intel) and bootstraps the right venv.
- First-launch dependency installation: `brew`, `whisper-cpp`, the
  `ggml-*.bin` model, and the Python venv now install on demand
  instead of failing if anything is missing.
- DMG install path on Intel Macs.
- Several broken GitHub URLs across the README and install scripts.

---

## [0.1.0] — 2026-02-22

Initial release.

### Added
- 13-module Python package (`voiceflow/`).
- Local transcription via `whisper.cpp`. Audio never leaves the Mac.
- Five LLM cleanup backends: Gemini, Groq, OpenAI, Anthropic, Ollama,
  plus a "none" pass-through.
- tkinter onboarding wizard for first-run setup.
- DMG installer (universal, with Rosetta fallback on Intel).
- Hotkey-driven dictation with auto-paste at the cursor.
- Configurable prompt, model, hotkey, language, and style.
- MIT licensed.

---

## Compare links

[Unreleased]: https://github.com/shimoverse/openvoiceflow/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/shimoverse/openvoiceflow/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/shimoverse/openvoiceflow/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/shimoverse/openvoiceflow/releases/tag/v0.1.0

# Changelog

All notable changes to OpenVoiceFlow are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
(with the pre-1.0 caveat documented in [VERSIONING.md](VERSIONING.md)).

## [Unreleased]

## [0.3.3] — 2026-07-10

### Added
- The menu-bar menu now includes a persistent **How to Use** guide, and the
  first-run hotkey tip also appears in the floating HUD instead of relying
  only on a potentially hidden macOS notification.
- `voiceflow/platform_support.py`: one place for OS, macOS-version,
  architecture (Apple Silicon / Intel / Rosetta), and permission detection.
- CLI platform gate: on Linux/Windows, `openvoiceflow` now prints a clear
  "macOS-only" explanation with uninstall guidance and exits cleanly instead
  of crashing with a traceback. `--doctor` and `--show-config` keep working
  so users can inspect state first.
- New doctor checks: operating system + version, architecture (warns on
  Rosetta-translated Python and Intel Homebrew on Apple Silicon), and the
  three macOS permissions dictation depends on (Microphone, Accessibility,
  Input Monitoring) with click-to-fix System Settings links.
- A launch below the supported macOS floor (12 Monterey) now prints an
  upgrade warning.
- CI: new `non-macos-guard` job on `ubuntu-latest` pins the "friendly
  message, never a traceback" guarantee and runs the full suite on Linux.
- Website: the download page now detects the visitor's OS. Windows, Linux,
  ChromeOS, Android, and iPhone/iPad visitors get an inert "Not available
  for <OS>" notice instead of a live DMG button; Safari-on-Mac visitors get
  an Apple Silicon / Intel recommendation via a WebGL renderer fallback
  (Chromium browsers already used architecture hints).

### Fixed
- Short streaming dictations no longer lose the final transcript fragment
  when `whisper-stream` exits without a trailing newline.
- Fresh installs now use the reliable batch recorder by default. Experimental
  real-time streaming remains available through the menu bar or
  `--streaming on`. Existing v0.3.2 installs are reset to batch mode once and
  can opt back into streaming afterward.
- `voiceflow.recorder` no longer imports `sounddevice` at module load —
  the import crashed the whole app (`OSError: PortAudio library not found`)
  on machines without PortAudio before any error handling could run.
- `find_whisper_cpp` / the doctor's Homebrew check use `shutil.which`
  instead of spawning `which`, which crashed on Windows.
- The keyboard-listener (pynput) import is now guarded in CLI and menu-bar
  modes: a missing input backend produces a clear error instead of a crash.
- Clipboard/keystroke/sound helpers (`pbcopy`, `pbpaste`, `osascript`,
  `afplay`) no longer propagate `FileNotFoundError` when the binaries are
  missing; failures surface as user-visible notifications.
- `--autostart` refuses politely off-macOS instead of writing a
  `~/Library/LaunchAgents` folder on Linux; on macOS it now prefers the
  supported `launchctl bootstrap`/`bootout` verbs, falling back to the
  deprecated `load`/`unload`.
- `validate_setup` reports a broken audio backend (`OSError`) instead of
  only a missing `sounddevice` package.

## [0.3.2] — 2026-07-09

### Fixed
- The DMG bootstrap now executes the virtual-environment Python interpreter at
  its original path, preventing a silent dynamic-library crash on launch.
- Native startup failures now show an alert with a direct link to the launcher
  log instead of making the app appear to do nothing.
- First-run Tk onboarding runs in an isolated process, so an incompatible
  system Tk build falls back to local transcription without killing the app.
- Menu-bar settings no longer clear uninitialized native submenus during
  startup.

## [0.3.1] — 2026-07-09

### Fixed
- The notarized macOS app now carries the hardened-runtime entitlements for
  microphone input and Apple Events, allowing recording and auto-paste to
  pass macOS privacy enforcement.
- DMGs now use a small native launcher so macOS attributes Microphone and
  Accessibility consent to OpenVoiceFlow instead of its Python bootstrap.
- First launch uses the native macOS consent prompts and no longer stacks two
  conflicting custom permission dialogs.

## [0.3.0] — 2026-07-08

The pre-publish readiness pass.

### Added
- Pytest scaffold under `tests/` with regression tests for every
  Wave-1 ship-stopper (`test_python39_compat`, `test_install_sh`,
  `test_config_migration`, `test_onboarding`, `test_voice_commands_count`,
  `test_updater`) plus privacy invariants (`test_chmod_600`,
  `test_privacy_defaults`) and package smoke tests. 60 tests total,
  green on Python 3.9, 3.10, and 3.11.
- `[dev]` extras in `pyproject.toml` (pytest, pytest-cov, ruff, build, twine).
- CI Python matrix: 3.9, 3.10, 3.11 on macos-latest. Lint is now a
  blocking step. A separate `build` job exercises `python -m build` and
  `twine check`.
- `--update-check on/off` CLI flag and matching `update_check` config key
  for opting out of the daily GitHub-Releases ping.
- `--log-transcripts on/off` CLI flag for explicit control of the
  `~/.openvoiceflow/logs/` daily files.
- "Privacy at a glance" panel in the README that maps every on-disk file
  and every network egress in one table.
- `voiceflow/_secure_io.py` — `secure_write_json()` and `secure_chmod()`
  helpers that all config / profile / dictionary / snippets / stats /
  daily-log writes now go through, enforcing mode 600.
- Community-health docs: SECURITY, PRIVACY, CONTRIBUTING, CODE_OF_CONDUCT,
  SUPPORT, VERSIONING, AGENTS, plus docs/COMPLIANCE, docs/COMPATIBILITY,
  docs/THREAT_MODEL, docs/ARCHITECTURE, docs/legal/DPA-template,
  docs/legal/THIRD_PARTY_NOTICES. ~14 files, ~2,100 lines.
- `RELEASE.md` — maintainer's three-command playbook plus
  when-things-go-wrong table.
- `.github/workflows/release.yml` rebuilt: tag-driven, Trusted Publisher
  PyPI publish on non-pre-release tags, split arm64/x86_64 DMG attach,
  `verify-version` gate that fails the release if tag ↔ pyproject ↔
  `__version__` disagree.

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
- **Code-review pass (2026-07)** — full-codebase review; the notable fixes:
  - Streaming mode + snippet match no longer crashes with a `NameError`
    (the dictation was silently lost with only an error sound).
  - OpenAI, Anthropic, and Groq backends now honor per-app style and app
    context (previously silently dropped — the per-app style feature only
    worked on OpenRouter/Ollama).
  - Empty LLM responses fall back to the raw transcript instead of pasting
    nothing.
  - Custom voice commands containing backslashes no longer crash every
    dictation; command expansions are no longer re-processed by later
    commands (single-pass replacement).
  - Snippet triggers only match on word boundaries — a trigger like `sig`
    no longer swallows a dictation starting with "significant…".
  - Menu bar: LLM Backend / Hotkey / Style submenus are now populated at
    startup (previously empty until first use); Streaming/Auto-Style/
    Auto-Learn toggles now apply to the running session; stopping or
    quitting aborts an in-flight recording instead of orphaning the
    whisper-stream process (hot mic).
  - Corrupt `config.json` no longer bricks every CLI entry point — the bad
    file is preserved as `config.json.corrupt` and defaults are restored.
  - Whisper model downloads use `curl --fail` with a temp file, so an HTTP
    error page or interrupted transfer can't be mistaken for a valid model
    forever after (fixed in `transcriber.py`, `install.sh`, and the DMG
    launcher).
  - Batch transcription timeout raised 30 s → 300 s so long dictations
    aren't discarded; Ollama cleanup timeout raised 30 s → 120 s for cold
    model loads.
  - Mic failures during recording start are surfaced (notification + error
    sound) instead of being silently swallowed with stale state.
  - Overlay no longer sticks on screen after too-short/no-speech/error
    aborts.
  - Selected-text capture no longer erases image/file clipboards when
    nothing was selected; `pbpaste`/`pbcopy` calls have timeouts.
  - `--show-config` no longer masks `hotkey` (over-broad secret matching);
    `--streaming-step` validates its value and `0` is no longer ignored;
    `--language` no longer crashes on a null `whisper_model`; env-var-only
    API-key setups aren't forced through onboarding on every launch.
  - Onboarding: re-running the wizard and switching backends no longer
    saves the old backend's key under the new backend's field; the Finish
    button survives a corrupt config; headless runs fail with instructions
    instead of a traceback (also fixed for `--profile`).
  - Interview: pressing Escape on the final screen no longer mislabels a
    saved profile as skipped.
  - `--autostart on` fails with a clear message when the executable can't
    be resolved (previously installed a LaunchAgent that silently never
    launched); the plist is generated with `plistlib` so paths containing
    `&` can't produce invalid XML.
  - `install.sh` works under `curl | bash` (wizard prompts read from
    `/dev/tty`), installs from the script's own directory instead of the
    CWD, creates `~/.zshrc` when no shell rc exists, and uses
    `set -euo pipefail`.
  - Release workflow: DMG job sequenced after the PyPI job so the two
    release-upload steps can't race creating the same GitHub Release.

### Changed (code-review pass)
- The typed 🎙 recording indicator is now opt-in
  (`"recording_indicator": true`): it edits the frontmost document and
  could delete a user character when focus changed mid-dictation; the
  overlay HUD remains the default recording feedback.
- `paste_text` no longer moves the caret to end-of-line before pasting —
  text is pasted at the cursor, as documented.
- `--set-key BACKEND -` reads the key from stdin so it stays out of shell
  history and `ps` output (used by `install.sh`, which also hides key input).

### Security (code-review pass)
- Config/profile/dictionary writes are atomic and created with mode 600
  from the first byte (previously created 644 then chmod'd — a crash
  mid-write could truncate the file or leave secrets world-readable).
- `~/.openvoiceflow/` is chmod 700; LaunchAgent stdout/stderr logs are
  pre-created with mode 600 (they capture dictated text via stdout).
- Update-notification strings from the GitHub API are escaped before
  AppleScript interpolation (a crafted release tag/URL could otherwise
  break out of the string literal).
- Internal `docs/superpowers/` documents removed from the repository, and
  the website build excludes any such directory as defense-in-depth.

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

[Unreleased]: https://github.com/shimoverse/openvoiceflow/compare/v0.3.3...HEAD
[0.3.3]: https://github.com/shimoverse/openvoiceflow/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/shimoverse/openvoiceflow/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/shimoverse/openvoiceflow/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/shimoverse/openvoiceflow/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/shimoverse/openvoiceflow/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/shimoverse/openvoiceflow/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/shimoverse/openvoiceflow/releases/tag/v0.1.0

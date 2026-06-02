# Contributing to OpenVoiceFlow

Thanks for thinking about contributing. This file is the operating manual for
patches, backends, and bug reports. If something here is wrong or out of date,
that itself is a bug — please open an issue.

## What this project is, briefly

OpenVoiceFlow is a free, macOS-only voice-dictation app: hold a hotkey, speak,
cleaned text appears at your cursor. See the [README](README.md) for the
two-stage pipeline (local whisper.cpp → optional LLM cleanup) and the install
options.

This is a **single-maintainer open-source project**. Issues and PRs get
best-effort responses on a human schedule. There is no SLA. If you need a fix
faster than the maintainer can land it, fork freely — that's what MIT is for.

## Dev-mode setup

The five commands a fresh clone needs to be ready to work:

```bash
git clone https://github.com/shimoverse/openvoiceflow.git
cd openvoiceflow
python -m venv .venv && source .venv/bin/activate
pip install -e ".[all,dev]"
pytest -q
```

`[all]` pulls in the optional `rumps` (menubar) and `pyobjc-framework-Cocoa`
(overlay HUD) extras; `[dev]` pulls in pytest, pytest-cov, ruff, build, and
twine. See `pyproject.toml` for the full list.

### macOS prerequisites

OpenVoiceFlow shells out to whisper.cpp, so you also need:

```bash
brew install whisper-cpp
```

That installs both `whisper-cli` (used for the canonical transcription pass)
and `whisper-stream` (used for the optional real-time streaming preview). If
you only have one or the other, the app degrades gracefully — but tests that
exercise the transcriber assume both are on PATH.

You do **not** need an LLM API key to run the test suite. Backend tests use
mocked HTTP. You only need a real key (OpenRouter / OpenAI / Anthropic / Groq) or
a local Ollama daemon if you want to dictate end-to-end on your own machine.

## The TDD discipline we follow

- **Tests fail first, then pass.** Every behavior change ships with a test
  that fails on `main` and passes on the change. If a reviewer can't see the
  red-then-green, the PR isn't done.
- **`ruff check voiceflow/` is blocking in CI.** Style debt accumulated on
  v0.2; on v0.3+ lint failures fail the build. Run `ruff check voiceflow/`
  before pushing.
- **CI runs the matrix Python 3.9, 3.10, 3.11 on macOS.** We support Python
  3.9 specifically because that's what macOS 12 ships by default — every
  `.py` file in `voiceflow/` that uses `X | None` annotations needs
  `from __future__ import annotations` at the top. CI catches this.
- **No `git push --force` to `main`.** Ever. Force-push to your own feature
  branches is fine.
- **Verification before completion.** Don't claim something works without
  running it. PRs that say "should work" without showing the run get bounced.

## Project structure

The code lives in `voiceflow/` — 28 modules grouped by role. Some highlights;
see `AGENTS.md` for the full file map and per-module summaries.

- **Config / system / startup** — `config.py`, `system.py`, `_secure_io.py`,
  `autostart.py`, `updater.py`, `__main__.py`, `app.py`.
- **Audio capture** — `recorder.py`, `clipboard.py`, `context.py`.
- **Transcription** — `transcriber.py` (whisper.cpp wrapper),
  `streamer.py` (whisper-stream wrapper).
- **LLM backends** — `llm/base.py` (abstract), `llm/__init__.py` (registry +
  dispatch), and one file per provider: `openrouter.py`, `openai_backend.py`,
  `anthropic_backend.py`, `groq_backend.py`, `ollama_backend.py`.
- **Personalization** — `profile.py`, `dictionary.py`, `snippets.py`,
  `commands.py`, `styles.py`, `learner.py`, `interview.py`, `search.py`,
  `stats.py`.
- **UI** — `menubar.py`, `overlay.py`, `onboarding.py`.

`AGENTS.md` is the deeper read for any agent (or human) doing structural
work. Start there before refactoring across modules.

## How to add a new LLM backend

The recipe — six places to edit, one test file to add:

1. **Subclass `LLMBackend`.** Create `voiceflow/llm/<provider>.py`. Subclass
   `voiceflow.llm.base.LLMBackend`. Set `name` and `default_model` class
   attributes.
2. **Implement `cleanup()` and `validate()`.** The `cleanup()` signature is
   `cleanup(self, text, context=None, app_context=None, override_style=None)`
   — see `voiceflow/llm/base.py` for the full contract. Use `_make_prompt()`
   on the base class to assemble the system prompt; do not re-implement that
   logic. `validate()` returns `(ok: bool, message: str)` and is what the
   onboarding wizard calls before saving the user's key.
3. **Register the class.** Add an entry to `BACKENDS` in
   `voiceflow/llm/__init__.py` so `get_backend()` can find it.
4. **Add config keys.** In `voiceflow/config.py`, add a `<provider>_api_key`
   field to `DEFAULTS`, and add `"<provider>"` to `VALID_BACKENDS`. Wire the
   env-var fallback in `get_api_key()` (e.g. `<PROVIDER>_API_KEY`).
5. **Add a CLI flag entry.** Update the `key_map` in `voiceflow/__main__.py`
   so `--set-key <provider> <KEY>` knows where to write.
6. **Add the GUI metadata.** Add a row to the `BACKENDS` dict in
   `voiceflow/onboarding.py` so the tkinter wizard offers the new option
   with cost/speed/instructions copy. (Yes, two registries — see issue
   tracker for the consolidation work.)
7. **README backend table.** Add a row to the comparison table in
   `README.md`. Keep the cost/speed numbers honest; users rely on these.
8. **Tests.** Add a test class to `tests/test_llm_backends.py` that mocks
   the HTTP layer and asserts `cleanup()` returns the cleaned string and
   `validate()` returns `(True, ...)` for a valid key.

If you skip step 6, your backend works from the CLI but is invisible in the
GUI. If you skip step 8, CI rejects the PR.

## How to add a new voice command

Voice commands live in `voiceflow/commands.py:DEFAULT_COMMANDS`. The lint
test (`tests/test_commands.py`) cross-checks the dict count against the
README table count, so you must update both:

1. Add the command to `DEFAULT_COMMANDS` in `voiceflow/commands.py`.
2. Add the row to the voice-commands table in `README.md` and bump the
   count in the surrounding prose.
3. Run `pytest tests/test_commands.py` — it'll fail loudly if the two
   numbers diverge.

## PR checklist

Copy this into your PR description and tick as you go:

- [ ] Tests added/updated; `pytest -q` green on Py 3.9, 3.10, 3.11
- [ ] `ruff check voiceflow/` clean
- [ ] No new `print()` for debug; remove any commented-out code
- [ ] CHANGELOG.md updated under "Unreleased"
- [ ] Docs (README / module docstring / AGENTS.md) match the change
- [ ] No fictional API examples
- [ ] No keys / secrets / personal paths leaked into the diff
- [ ] Behavior change → covered in tests
- [ ] If touching `~/.openvoiceflow/*.json` write paths, the chmod-600
      invariant is preserved (use `voiceflow/_secure_io.py`)

## Commit and branch conventions

- **Commit prefix:** `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`,
  `test:`. One concept per commit; one feature per PR.
- **Branch naming:** `feat/<short-slug>`, `fix/<short-slug>`,
  `docs/<short-slug>`. Long-lived release branches use `vX.Y-readiness`.
- **Squash on merge.** PR title becomes the squashed commit message.
- **Never `git push --force` to `main`.** Force-push your own branches
  freely.

## Issue triage

Maintainer prioritization, in order:

1. **Ship-stoppers** — the app crashes, an install path is broken, a
   security bug is in the open.
2. **Persona 1 friction** — anything that blocks an indie developer from
   forking, extending, or shipping their fork.
3. **Persona 2 friction** — anything that blocks an end user from
   completing the dictation happy path.
4. **Nice-to-have features** — new backends, new commands, new style
   presets.
5. **Maintenance** — refactors, lint cleanup, doc polish, dependency
   bumps.

If your issue is in tier 4 or 5, expect a slower response — that's the
maintainer's bandwidth, not a comment on the issue's quality.

## Code of conduct and license

This project adopts the [Contributor Covenant v2.1](CODE_OF_CONDUCT.md).
By participating you agree to abide by it.

Code is MIT-licensed (see [LICENSE](LICENSE)). Contributions are accepted
under the same license; you keep your copyright, you grant the project the
right to redistribute under MIT.

## Maintainer note

OpenVoiceFlow is currently maintained by [Mohit Jain](https://github.com/shimoverse)
as a single-maintainer project. Review timelines are best-effort. If a PR
sits for more than two weeks without a response, a polite ping in the PR
thread is welcome.

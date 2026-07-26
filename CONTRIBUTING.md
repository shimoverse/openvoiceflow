# Contributing to OpenVoiceFlow

Thanks for thinking about contributing. If anything in this file is wrong or
out of date, that itself is a bug — please open an issue.

## What this project is, briefly

OpenVoiceFlow is a free, macOS-only voice-dictation app: hold a hotkey, speak,
text appears at your cursor. The **shipping app is native Swift** and lives in
`native/`. The repo also carries the legacy Python app (`voiceflow/`, ≤ 0.3.6)
it replaced — end-of-life, no security fixes, kept for reference and the
macOS 12–13 fallback build. New work belongs in `native/` unless you're fixing
something in the website or docs.

This is a **single-maintainer open-source project**. Issues and PRs get
best-effort responses on a human schedule. There is no SLA. If you need a fix
faster than the maintainer can land it, fork freely — that's what MIT is for.

## Working on the native app (the usual case)

You need a Mac on macOS 14+, Xcode 16.4+ (WhisperKit 0.18 needs Swift tools
6.1), and XcodeGen:

```bash
brew install xcodegen
git clone https://github.com/shimoverse/openvoiceflow.git
cd openvoiceflow
bash native/scripts/run-local.sh   # generate project, build, launch
```

The Xcode project is **generated** from `native/project.yml` — edit that, not
the `.xcodeproj`. The build signs ad-hoc so the permission-bound features
(hotkey, paste) actually work on your machine.

What CI checks on every PR (`.github/workflows/ci.yml`):

- **`native-build`** — compiles the Swift app on macos-15 with Xcode 16.4.
  If your PR touches `native/`, this must pass.
- **`test`** — pytest on Python 3.9/3.10/3.11. This covers the website
  distribution tests (`tests/test_docs_distribution.py`) and the legacy app.
- **ruff** — lint for the Python tree.

There is **no Swift test target yet**; the app is verified by CI compile plus
on-device passes. Adding an XCTest target for the pure-logic pieces
(`Settings`, `CleanupProvider` prompt assembly, hotkey flag decoding) would be
one of the most valuable first contributions.

### Conventions in the Swift tree

- Match the file you're in: comment density, naming, SwiftUI idioms.
- Comments explain *why*, or a constraint the code can't show — not what the
  next line does.
- One feature per PR. Screenshots or a short screen recording in the PR body
  for anything visual.
- Version bumps are release work, not feature work — leave
  `project.yml`/`Info.plist` versions alone unless you're cutting a release
  (all four fields must move together; CI enforces it at release time).

## Working on the website (`docs/`)

The site is static HTML/CSS/JS served by Vercel from `docs/`. It has real
tests:

```bash
python3 -m pytest tests/test_docs_distribution.py -q
```

They pin download filenames, checksums, appcast integrity, and the
Gatekeeper-warning cards. If your change breaks one, read the test — each one
documents the support question or invariant it protects.

## Working on the legacy Python app

Only security-relevant or fallback-critical fixes are accepted; features
won't be. Setup, if you truly need it:

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e ".[all,dev]"
pytest -q
```

## Reporting bugs

Use the issue templates. The fields that make a report actionable: macOS
version (`sw_vers`), app version (menu bar → Open Dashboard → Settings shows
it), which speech engine you chose, and what the HUD showed when it went
wrong. For dictation-accuracy issues, the exact spoken phrase vs. what landed.

Security issues: **don't** open a public issue — see [SECURITY.md](SECURITY.md).

## Pull-request checklist

- [ ] CI green (`native-build` for Swift changes, pytest for website/Python)
- [ ] For UI changes: screenshot or recording in the PR body
- [ ] For behavior changes: the PR body says what changed *for the user*
- [ ] No version bumps, no new dependencies without discussion in an issue
- [ ] You're okay with MIT — everything merged is MIT-licensed

## License

By contributing you agree your work is licensed under the [MIT License](LICENSE).

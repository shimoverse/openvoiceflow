# Release runbook — OpenVoiceFlow v0.3.5 (agent hand-off)

**For an automated agent with full repo + CI + release access.** Everything up
to the release tag is already done and merged. Your job: cut the release and
update the public website. This is a **full public release** (not a beta/rc).

Repo: `shimoverse/openvoiceflow` · default branch: `main`

## Why (context)

A tester installed the old **v0.3.2** DMG on a fresh MacBook Pro and it launched
to nothing — no menu bar icon, no wizard, dead hotkey. Root causes were in the
DMG first-launch bootstrap: a stale lock that made every relaunch exit silently,
a false-positive `python3` check, no venv health check, invisible setup
progress, and Input Monitoring never being requested. These are fixed for
v0.3.5 (PR #23 app-level visibility, PR #24 bootstrap layer).

## Current state (already on `main` — do NOT redo)

- `main` HEAD is `chore: prepare v0.3.5`. Version is `0.3.5` in **both**
  `pyproject.toml` and `voiceflow/__init__.py`. `CHANGELOG.md` has a
  `## [0.3.5] — 2026-07-13` section.
- CI on `main` is green (pytest + `ruff check .` + a clang syntax check of the
  native launcher + a non-macOS guard job).
- The `v0.3.5` tag has **not** been pushed yet. The website still serves
  **v0.3.4**.

## Step 1 — Cut the release (triggers the automated pipeline)

1. Ensure local `main` == `origin/main`.
2. Create and push the tag:
   ```bash
   git tag -a v0.3.5 -m "v0.3.5"
   git push origin v0.3.5
   ```
   If a plain git tag push is blocked in your environment, create it via the
   GitHub API or `gh release create v0.3.5 --target main`. The tag must point at
   current `main` HEAD.
3. This fires `.github/workflows/release.yml`, which: verifies the tag matches
   `pyproject`/`__init__` (0.3.5), builds wheel + sdist, builds **signed +
   notarized + stapled** arm64 and x86_64 DMGs on a macOS runner, publishes to
   PyPI (**only** if the `PYPI_TRUSTED_PUBLISHING_ENABLED` repo var is `true` —
   if unset, PyPI is skipped by design; that's fine, the DMGs are what matter),
   and attaches everything to a new GitHub Release for tag `v0.3.5`.
   Apple signing secrets are already configured (0.3.3 and 0.3.4 released fine).
   Watch the run to completion. If the `build-dmg` job fails, read its log and
   report the exact failure — **do not** hand-build or publish unsigned DMGs.

## Step 2 — Update the website to v0.3.5 (branch → PR → green CI → merge)

The site hosts the DMG **binaries** committed under `docs/downloads/`
(byte-for-byte copies of the GitHub Release assets), and several files hardcode
the version and SHA-256. Update all of them together:

- **a) Hashes.** Download both v0.3.5 assets from the GitHub Release and compute
  their sha256:
  ```bash
  shasum -a 256 OpenVoiceFlow-0.3.5-arm64.dmg
  shasum -a 256 OpenVoiceFlow-0.3.5-x86_64.dmg
  ```
- **b) `docs/downloads/`.** Add `OpenVoiceFlow-0.3.5-arm64.dmg` and
  `OpenVoiceFlow-0.3.5-x86_64.dmg` (the **exact** release assets — a docs test
  hashes these files and compares to the pinned checksums, so they must match).
  `git rm` the two 0.3.4 DMGs (they'll be covered by redirects).
- **c) `docs/download.html`.** Change every `0.3.4` → `0.3.5`: the schema.org
  `softwareVersion`, the two `downloadUrl` entries, the three
  `href="downloads/OpenVoiceFlow-0.3.4-*.dmg"` links (the recommended button and
  both build rows), the two `aria-label`s, the two `sha256: ...` code blocks
  (real new hashes), and the "Download notes" text that says "v0.3.4".
- **d) `docs/site.js`.** Update the two `href: 'downloads/OpenVoiceFlow-0.3.4-*.dmg'`
  strings in the `builds` object to 0.3.5.
- **e) `vercel.json`.** Repoint every existing redirect destination to the 0.3.5
  DMGs, and **add** redirects for `/downloads/OpenVoiceFlow-0.3.4-arm64.dmg` and
  `-x86_64.dmg` → the 0.3.5 files (so the removed 0.3.4 binaries and all old
  links still resolve with a 308).
- **f) `tests/test_docs_distribution.py`.** Set `RELEASE_VERSION = "0.3.5"` and
  `ARM64_SHA256` / `X86_64_SHA256` to the real new hashes.
- **g) Verify locally.** Run `ruff check .` and `pytest -q` — the docs
  distribution test re-hashes the committed DMGs, so it fails unless (a)/(b)/(f)
  agree. Fix any stale version strings the test forbids.
- **h) Ship it.** Open a PR, let CI go green, merge to `main`. Vercel
  auto-deploys `main`.

## Step 3 — Verify live

- `https://openvoiceflow.vercel.app/download.html` shows 0.3.5 and links the
  0.3.5 DMGs; both DMG URLs return 200 and their sha256 match the release.
- Old URLs 308-redirect to 0.3.5:
  `/downloads/OpenVoiceFlow-0.3.2-arm64.dmg` and `-0.3.4-arm64.dmg` (+ x86_64).
- The GitHub Release for `v0.3.5` exists, is **not** marked pre-release, and has
  both signed DMGs attached.
- Report: the release URL, the two checksums, PyPI status (published or
  skipped-because-var-unset), and the final `origin/main` SHA of the website PR.

## Guardrails

- Only the release pipeline may produce the DMGs; the website must host those
  exact signed/notarized assets (hashes must match — never rebuild by hand).
- Use the branch → PR → green CI → merge flow for the website change.
- This is a real public, non-prerelease release. If anything in Step 1 fails,
  stop and report rather than working around signing/notarization.

---

## Immediate note for the tester (independent of this release)

The live site already serves **v0.3.4** (two versions newer than the v0.3.2 the
tester installed). Tell them to fully reset local state and re-download, because
a stale lock/venv in `~/.openvoiceflow` survives a reinstall:

```bash
rm -rf ~/.openvoiceflow
```

Then re-download from <https://openvoiceflow.vercel.app/download.html>, reinstall,
and grant **Microphone + Accessibility + Input Monitoring** when prompted.

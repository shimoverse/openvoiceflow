# Release runbook — OpenVoiceFlow v0.3.6 (agent hand-off)

**For a Mac-equipped agent with full repo + CI + release access ("Hermes").**
This session runs on Linux and cannot push tags (the git proxy 403s on tag
pushes) or build/sign/notarize on a Mac, so those steps are handed off here.

Two goals, in order:

1. **Internal test build first.** Cut a *notarized* macOS DMG and hand it to
   internal testers — the practical "TestFlight equivalent" for this app.
2. **Public launch after sign-off.** Promote the same version to a full release
   and update the public download site.

> **Why not real TestFlight / the App Store?** OpenVoiceFlow needs a global
> hotkey (`CGEventTap`) and paste-into-other-apps (Accessibility), both of which
> the Mac App Store sandbox forbids; the Python build also bootstraps a venv +
> model on first launch, which a sandbox can't do. So the distribution model is
> the same one Wispr Flow / Superwhisper / MacWhisper use: a **Developer-ID
> signed + notarized + stapled DMG**, downloaded directly. A notarized DMG opens
> with no Gatekeeper warning, which is what makes direct hand-off to testers
> clean.

Repo: `shimoverse/openvoiceflow` · default branch: `main`

## Current state (already on `main` — do NOT redo)

- `main` HEAD is `chore: prepare v0.3.6` at commit
  **`84d1df0baa8a4d6d9d4ca7607fa8f6ebb4ad897b`**. Version is `0.3.6` in **both**
  `pyproject.toml` and `voiceflow/__init__.py`. `CHANGELOG.md` has a
  `## [0.3.6] — 2026-07-18` section (Fn/Globe dead-hotkey fix + the
  production-hardening pass from #28).
- No `v0.3.6*` tag has been pushed. The website still serves **v0.3.5**.
- CI on `main` is green (pytest 251 passed + `ruff check .` + the native-launcher
  clang syntax check + the non-macOS guard job).
- Apple signing/notarization secrets are already configured (0.3.3–0.3.5
  released fine through this same pipeline).

## What ships in v0.3.6

- **Fn / 🌐 Globe key no longer fails silently.** macOS never delivers Fn to
  `pynput`, so choosing it left dictation permanently dead. Selecting Fn now
  raises an immediate modal pointing at Right Command (the default); the menu-bar
  picker hides Fn unless it's the current legacy selection; onboarding drops it.
- **Production-hardening pass** (from PR #28): consent-dialog-proof hotkey arming,
  max-duration recording watchdog, PortAudio stream-leak fix, clipboard
  data-loss fix, `O_EXCL|O_NOFOLLOW` secret writes + `0700` log dir + capped LLM
  reads + `ollama_url` scheme/loopback guard, version-stamped DMG venv marker,
  overlay run-loop/Reduce-Motion polish, Know-Me Escape guard. Full detail in
  `PRODUCTION_READINESS.md` and `CHANGELOG.md`.

---

## Step 1 — Cut the internal test build (RC tag → notarized DMGs, no PyPI, site untouched)

Push an **`-rc1` tag**. The pipeline classifies any pre-release suffix as
`is_prerelease=true`, which (a) marks the GitHub Release as **Pre-release**,
(b) **skips PyPI publish**, and (c) leaves the public website alone — while
still building the **identical signed + notarized DMGs** (the DMG name comes from
`pyproject` = `0.3.6`, not the tag). This is the same pattern used for the
v0.3.3-rc1 round.

```bash
git fetch origin main
# Tag must point at main HEAD 84d1df0 (verify first):
git rev-parse origin/main   # expect 84d1df0baa8a4d6d9d4ca7607fa8f6ebb4ad897b
git tag -a v0.3.6-rc1 -m "v0.3.6-rc1 (internal test build)" 84d1df0baa8a4d6d9d4ca7607fa8f6ebb4ad897b
git push origin v0.3.6-rc1
```

If a plain tag push is blocked in your environment, create it via the GitHub API
or `gh release create v0.3.6-rc1 --target main --prerelease`. The tag must point
at the SHA above.

This fires `.github/workflows/release.yml`, which:
- verifies the tag's base version (`0.3.6`) matches `pyproject`/`__init__`,
- builds wheel + sdist and attaches them to a **pre-release** GitHub Release,
- **skips PyPI** (pre-release),
- builds **signed + notarized + stapled** `arm64` and `x86_64` DMGs on a macOS
  runner and attaches them:
  `OpenVoiceFlow-0.3.6-arm64.dmg`, `OpenVoiceFlow-0.3.6-x86_64.dmg`.

Watch the run to completion. **If the `build-dmg` job fails, read its log and
report the exact failure — do not hand-build or publish unsigned DMGs.**

### Verify the DMGs are genuinely notarized (do this before handing to testers)

Download each asset and confirm on a Mac:

```bash
shasum -a 256 OpenVoiceFlow-0.3.6-arm64.dmg OpenVoiceFlow-0.3.6-x86_64.dmg
# Notarization ticket is stapled to the DMG:
xcrun stapler validate OpenVoiceFlow-0.3.6-arm64.dmg     # -> "The validate action worked!"
# Gatekeeper accepts it as notarized:
spctl -a -vv -t open --context context:primary-signature OpenVoiceFlow-0.3.6-arm64.dmg
# Mount, then check the app inside is Developer-ID signed + notarized:
spctl -a -vv /Volumes/OpenVoiceFlow/OpenVoiceFlow.app   # -> "accepted", "Notarized Developer ID"
```

---

## Step 2 — Distribute to internal testers (the "TestFlight equivalent")

The **pre-release GitHub Release** is the distribution channel. It exists on
GitHub but is not advertised anywhere public (the download site still shows
v0.3.5), so only people you send the link to will install it.

1. From the v0.3.6-rc1 Release page, copy the two asset URLs (arm64 for Apple
   Silicon, x86_64 for Intel Macs).
2. Send testers the correct link for their Mac plus the checksums from Step 1,
   and these install instructions:

   > **Install OpenVoiceFlow (internal test build)**
   > 1. First, fully reset any earlier install (a stale lock/venv in
   >    `~/.openvoiceflow` survives a reinstall):
   >    ```bash
   >    rm -rf ~/.openvoiceflow
   >    ```
   > 2. Download the DMG, open it, drag **OpenVoiceFlow** to Applications.
   >    Because the build is notarized, it opens with no "unidentified developer"
   >    warning — no right-click-Open dance needed.
   > 3. Launch it. First launch bootstraps Python + the Whisper model (~5 min,
   >    with a progress dialog). Grant **Microphone + Accessibility + Input
   >    Monitoring** when prompted.
   > 4. Dictation hotkey defaults to **Right Command**. (Fn/🌐 is intentionally
   >    unavailable — macOS doesn't expose it to apps.)

3. Collect feedback. If testers hit a blocker, fix it on `main`, bump to the next
   patch if the fix changes shipped code, and cut `v0.3.6-rc2` (repeat Step 1).
   RC tags are cheap — burn as many as needed; they never touch PyPI or the site.

---

## Step 3 — Promote to public launch (only after tester sign-off)

Once testers approve, promote the same code to a full public release. **Two
parts, both required.**

### 3a. Full release tag (drops the pre-release marker; publishes PyPI if enabled)

```bash
git tag -a v0.3.6 -m "v0.3.6" 84d1df0baa8a4d6d9d4ca7607fa8f6ebb4ad897b
git push origin v0.3.6
```

Same pipeline, but now `is_prerelease=false`: the GitHub Release is a normal
(non-pre-release) release, and PyPI publish runs **only if** the
`PYPI_TRUSTED_PUBLISHING_ENABLED` repo var is `true` (if unset it's skipped by
design — that's fine, the DMGs are what matter). Rebuilds the same
signed/notarized `OpenVoiceFlow-0.3.6-*.dmg` assets on the `v0.3.6` release.

### 3b. Update the website (branch → PR → green CI → merge)

Mirror the v0.3.5 website step, bumping every `0.3.5` → `0.3.6`:

- **a) Hashes.** `shasum -a 256` both **final** `v0.3.6` release DMGs.
- **b) `docs/downloads/`.** Add the exact `OpenVoiceFlow-0.3.6-arm64.dmg` and
  `-x86_64.dmg` release assets (a docs test re-hashes these and compares to the
  pinned checksums, so they must be byte-for-byte the release files). `git rm`
  the two 0.3.5 DMGs.
- **c) `docs/download.html`.** Change every `0.3.5` → `0.3.6`: schema.org
  `softwareVersion`, both `downloadUrl`s, the three
  `href="downloads/OpenVoiceFlow-0.3.5-*.dmg"` links, the two `aria-label`s, the
  two `sha256:` blocks (real new hashes), and any "v0.3.5" note text.
- **d) `docs/site.js`.** Update the two `href: 'downloads/OpenVoiceFlow-0.3.5-*.dmg'`
  strings in `builds` to 0.3.6.
- **e) `vercel.json`.** Repoint existing redirect destinations to the 0.3.6 DMGs
  and **add** redirects for the removed `/downloads/OpenVoiceFlow-0.3.5-*.dmg`
  → 0.3.6 (308), so old links keep resolving.
- **f) `tests/test_docs_distribution.py`.** Set `RELEASE_VERSION = "0.3.6"` and
  `ARM64_SHA256` / `X86_64_SHA256` to the real new hashes.
- **g) Verify locally.** `ruff check .` and `pytest -q` (the docs distribution
  test re-hashes the committed DMGs — it fails unless a/b/f agree).
- **h) Ship it.** Open a PR, green CI, merge to `main`. Vercel auto-deploys.

### 3c. Verify live

- `https://openvoiceflow.vercel.app/download.html` shows 0.3.6 and links the
  0.3.6 DMGs; both URLs 200 with matching sha256.
- Old URLs 308-redirect to 0.3.6 (`/downloads/OpenVoiceFlow-0.3.5-arm64.dmg`
  + x86_64, and earlier ones).
- The `v0.3.6` GitHub Release exists, is **not** pre-release, and has both signed
  DMGs attached.
- Report: the release URL, the two checksums, PyPI status (published or
  skipped-because-var-unset), and the final `origin/main` SHA of the website PR.

## Guardrails

- Only the release pipeline may produce the DMGs; the website must host those
  exact signed/notarized assets (hashes must match — never rebuild by hand).
- Internal-test round uses `-rc*` tags (pre-release, no PyPI, site untouched).
  Only push the bare `v0.3.6` tag after testers sign off.
- Use the branch → PR → green CI → merge flow for the website change.
- If any signing/notarization step fails, **stop and report** rather than
  working around it with an unsigned build.

---

## Notes for whoever asked for this

- **PR #29 (native Swift/SwiftUI rewrite)** is a separate open **draft** and is
  *not* part of v0.3.6. It's the long-term path where Fn *does* work (native
  `CGEventTap` reads the secondary-fn flag) and there's no Python bootstrap. It
  needs a Mac to build/run and is awaiting an explicit go-ahead before merge.
- v0.3.6 is the shipping Python app with Fn now failing loudly instead of
  silently, plus the hardening pass — the right thing to put in testers' hands
  today while the native rewrite bakes.

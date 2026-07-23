# Launch runbook — OpenVoiceFlow native (Mac-gated finish line)

**Audience:** the Mac-equipped agent/dev (Meeru / Harmi).
**Bottom line:** the native app **0.4.1 is already built, signed, notarized,
published, self-hosted on the website, and wired for Sparkle auto-update.** The
one thing standing between "published" and "safe to tell end users to install"
is a **real on-device run** — which only a Mac can do. Everything else here is
merge hygiene and next-release polish.

---

## 0. What is ALREADY done (do not redo these)

Verified against the live release and site on 2026-07-23:

- ✅ **`native-v0.4.1` is a published GitHub Release** with a **Developer-ID-
  signed, Apple-notarized** `OpenVoiceFlow-0.4.1.dmg` (universal, ~5.2 MB).
- ✅ **The website already serves it.** `docs/downloads/OpenVoiceFlow-0.4.1.dmg`
  and `docs/appcast.xml` are committed; both return **HTTP 200** live at
  `https://openvoiceflow.vercel.app/downloads/OpenVoiceFlow-0.4.1.dmg` and
  `…/appcast.xml`.
- ✅ **Sparkle auto-update is fully wired.** `Info.plist` has `SUFeedURL`
  (site-root appcast) and a real `SUPublicEDKey`. The private half is the repo
  secret `SPARKLE_ED_PRIVATE_KEY`, and the **published appcast is signed**
  (`sparkle:edSignature=…`, `sparkle:version=2`, `minimumSystemVersion=14.0`).
- ✅ **The Swift compiles in CI** — PR #39 adds a `native-build` job (macos-15 /
  Xcode 16.4) that `xcodegen`+`xcodebuild`-compiles the app on every PR.

> ⚠️ **DO NOT regenerate the Sparkle keypair.** The key in `Info.plist` is live;
> existing installs verify updates against it. A new keypair would break
> auto-update for every shipped 0.4.1 copy. (An old code comment used to say the
> key was "deliberately absent" — that's stale; it's present and in use.)

So the distribution machinery is **done**. What remains is validation + merges.

---

## 1. The one real launch gate: run it on a Mac

The app has been compiled by CI but, as far as we know, **never actually run on
a real device.** CI cannot grant TCC permissions, press the fn key, or paste
into a live app. Before promoting 0.4.1 to end users, one person must download
the shipped DMG (or build from `main`) and walk the full loop.

Install the **actual shipped artifact** so you're testing what users get:

```bash
curl -LO https://openvoiceflow.vercel.app/downloads/OpenVoiceFlow-0.4.1.dmg
shasum -a 256 OpenVoiceFlow-0.4.1.dmg
# expect: 300e65c1cead4216e120a6809fc050c53d9104613d000b4a9cbbd4d69f8ceddf
spctl --assess --type execute -vv /Volumes/OpenVoiceFlow/OpenVoiceFlow.app   # Gatekeeper must accept
```

Then the smoke checklist (§3). **If the loop works on a device, 0.4.1 is
genuinely launch-ready** — it's already downloadable and auto-updating. If
something's broken, fix it and cut a 0.4.2 (§4–5).

---

## 2. Merge the two launch PRs (neither changes the app)

Both target `main`; both are website/CI only, so they can't affect the shipped
DMG:

| PR | Branch | What | Blocker? |
| --- | --- | --- | --- |
| **#38** | `claude/launch-hardening-site` | Website accuracy + legal (WhisperKit, macOS 14+, privacy page, headline fix). **Reconciled** so the cleanup story matches the shipped app: OpenRouter (recommended) **plus** OpenAI/Anthropic/Groq **plus** Ollama **plus** Off — not OpenRouter-only. | Yes — the live homepage still has the old false headline until this merges. |
| **#39** | `claude/launch-hardening-ops` | Release-ops hardening: guard the retired `v*` Python pipeline at 0.4.0+, compile Swift in CI, version-source agreement checks, required appcast step. | No — pure hygiene, but merge it: it keeps CI compiling the Swift and blocks a wrong-product release. |

Merge order doesn't matter much; #38 is the user-visible one.

> **Deferred by product decision:** **PR #37** (OpenRouter as the *single* cloud
> gateway + the `google/gemma-4-31b-it` default) is held for a later phase — the
> default-model choice is being reconsidered. The site copy above intentionally
> describes all the backends the shipped app actually exposes, so nothing
> pre-announces #37.

---

## 3. On-device smoke test (only a real Mac can do this)

- [ ] **Gatekeeper:** `spctl --assess` accepts the app (offline too).
- [ ] **Onboarding:** welcome → three permission rows → "Getting ready" model
      download → "Say hello". Grant Microphone, Accessibility, Input Monitoring;
      confirm each dot turns green (`OnboardingView.swift`).
- [ ] **"Not listed?" escape hatch** works if the app is denied or attributed to
      Xcode/Terminal in a dev build.
- [ ] **fn/Globe push-to-talk** — the marquee feature. Set System Settings ▸
      Keyboard ▸ "Press 🌐 to: Do Nothing" first. Also verify Right ⌘ (default).
- [ ] **Full loop in 3+ apps** (Notes, Safari, VS Code/Slack): hold → speak →
      release → polished text pastes at the cursor. Confirm the per-app style map
      applies (code style in an editor, casual in Slack — `StyleStore`).
- [ ] **Cleanup, all paths:** with a real key, confirm OpenRouter cleanup runs;
      try a direct provider (OpenAI/Anthropic/Groq); set cleanup **Off** and
      confirm the raw transcript pastes.
- [ ] **Offline first-run** — fresh Mac, no network after the model download:
      transcription still works (WhisperKit is on-device).
- [ ] **Clipboard preservation** — copy an image, dictate, confirm the image is
      back on the clipboard after paste (`Paster.swift`).
- [ ] **Too-short nudge** — instant tap-release → "keep talking" nudge, not an
      error (`AppController.stopAndProcess`).
- [ ] **Max-duration ceiling** — hold past 300 s → finalizes + inserts, never
      records forever.
- [ ] **Sparkle:** menu-bar **Check for Updates…** reaches the live feed and
      reports "up to date" at 0.4.1. (Full 0.4.1→0.4.2 upgrade proof comes when
      you ship the next build — §5.)

---

## 4. Hardening review → fold into a 0.4.2 (not launch blockers)

Real gaps in the current Swift, each with a file pointer and a fix. None blocks
shipping 0.4.1, but the two **majors** are worth a fast-follow 0.4.2. Fix on a
device (so you can verify), then release per §5.

### 4.1 [MAJOR] Paste-failure path is UI-only — not wired
The HUD has a `.pasteBlocked` state, copy *"Copied instead — press ⌘V."*
(`HUDController.swift:27,33,472`), but **nothing triggers it**.
`Paster.paste(_:)` (`Paster.swift:16`) is fire-and-forget and
**unconditionally restores the old clipboard after 0.15 s** — so if Accessibility
was revoked or ⌘V doesn't land, the text is *both* un-pasted *and* wiped from the
clipboard. Silent data loss.
**Fix:** gate on `AXIsProcessTrusted()` first; if not trusted (or the post
fails), **leave the text on the clipboard** (skip restore) and have
`AppController.deliver` show `hud.show(.error(.pasteBlocked))`. Wire the
`.pasteBlocked` "Grant Access" button to the Accessibility settings deep link.

### 4.2 [MAJOR] Model / language changes need an app restart
`Transcriber` binds `modelName` at `init` (`Transcriber.swift:13`); there's **no
`setModel`**. Changing **Model** or **Language** in the dashboard updates
`Settings` but the live `Transcriber` keeps the old model — and `base.en` (the
default) can't transcribe non-English at all, so a language switch looks broken.
**Fix:** add `Transcriber.setModel(_:) async` that drops `kit` and re-warms;
call it from the settings binding. Consider auto-picking a multilingual variant
when `language != "en"`, or warn that `base.en` is English-only.

### 4.3 [MINOR] `warmUp()` can double-download the model
Onboarding's `prepareModelForOnboarding` and `startListening()`'s background
`Task { try? await warmUp() }` (`AppController.swift:93`) can both pass the
`kit == nil` guard across the `await` in `downloadAndLoad`
(`Transcriber.swift:23`) and fetch the model twice on first run.
**Fix:** cache the in-flight load as a `Task` on the actor; concurrent callers
await the same task.

### 4.4 [MINOR] "Sounds" toggle is inert
`Settings.soundFeedback` (`Settings.swift:13`) has a dashboard toggle
(`DashboardView.swift:485`) but nothing plays a sound. Wire `NSSound` on
record-start/success (respecting the toggle) or hide the control.

### 4.5 [MINOR] "Launch at login" is inert
`Settings.launchAtLogin` (`Settings.swift:14`) has no `SMAppService.mainApp`
registration, so the toggle does nothing. Wire
`SMAppService.mainApp.register()/unregister()` or hide it. (A common first-run
expectation for a menu-bar app.) — `automaticUpdates` **is** correctly wired to
Sparkle (`Updater.swift:28`); listed only to say it was checked.

---

## 5. Cutting a 0.4.2 (when you have app changes to ship)

The pipeline already does the hard parts. To ship a new build:

1. **Bump both version numbers together** — Sparkle orders strictly by build
   number, so the new build MUST exceed 2:
   - `native/project.yml`: `CURRENT_PROJECT_VERSION` → **3** (and
     `MARKETING_VERSION` → `0.4.2`).
   - `native/Info.plist`: `CFBundleVersion` → **3**,
     `CFBundleShortVersionString` → `0.4.2`.
   (PR #39's release guard *enforces* that these agree with the tag and exceed
   the last published appcast, so a mismatch fails the release loudly.)
2. **Reuse the existing Sparkle key** — it's already set up. Do **not**
   regenerate it (§0 warning).
3. **Tag it** (Linux agent can't push tags — this is yours):
   ```bash
   git tag native-v0.4.2-rc1 && git push origin native-v0.4.2-rc1   # exercise first
   git tag native-v0.4.2      && git push origin native-v0.4.2
   ```
   `release-native.yml` builds the signed/notarized universal DMG, signs the
   appcast, and attaches both to the Release.
4. **Publish to the site** — copy the new DMG into `docs/downloads/` and replace
   `docs/appcast.xml` with the freshly signed one (the site self-hosts both;
   `tests/test_docs_distribution.py` gates the version/hash). Update the version
   strings + SHA on `docs/download.html`.
5. **Verify the upgrade** — on a Mac running 0.4.1, confirm Sparkle offers →
   downloads → installs 0.4.2. That's the real proof the build-number discipline
   worked.

---

## 6. Ship checklist

- [ ] 0.4.1 DMG runs on a real Mac — full loop + fn-key push-to-talk verified (§3).
- [ ] `spctl --assess` accepts the shipped DMG.
- [ ] #38 merged (kills the old homepage headline; cleanup copy matches the app).
- [ ] #39 merged (CI compiles Swift; legacy pipeline guarded).
- [ ] (If shipping 0.4.2) build number bumped to ≥3, tagged, DMG+appcast on the
      site, Sparkle upgrade proven on a device.

## 7. Rollback

If a released DMG is bad: delete the tag + its GitHub Release, fix, re-tag —
but **never reuse a build number** (Sparkle ignores an equal/lower one). Bump
`CURRENT_PROJECT_VERSION` + `CFBundleVersion` to the next integer; the release
version-agreement guard will refuse a mismatch. The site's `docs/downloads/` DMG
and `docs/appcast.xml` can be reverted independently of the tag.

---

### References
- `native/RELEASE_NATIVE_RUNBOOK.md` — copy-paste release steps.
- `native/BUILD_RUNBOOK.md` — first-principles build/compile guide.
- `.github/workflows/release-native.yml` — the tag-driven signed release.
- `native/scripts/build-app.sh` — local build (`OVF_NOTARIZE=0` for unsigned).
- `native/scripts/appcast.sh` — Sparkle appcast signing.

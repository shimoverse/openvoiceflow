# Launch runbook — OpenVoiceFlow native 0.4.2 (Mac-gated finish line)

**Audience:** the Mac-equipped agent/dev (Meeru / Harmi).
**Goal:** take the native macOS app from "compiles in CI, never run on a real
Mac" to a **shipped, signed, notarized, auto-updating 0.4.2 release** with the
website flipped to match.

Everything below is here because it **cannot be done from the Linux CI agent**:
it needs a real Mac (to run the app, grant TCC permissions, generate the Sparkle
keypair) or push rights to create a git tag (the Linux agent is blocked from tag
pushes by the proxy). The Swift itself is authored and compiles; your job is to
*prove it works on a device* and *ship it*.

---

## 0. Where things stand (read first)

- **`main`** is the native app baseline. Its Swift **compiles in CI** — PR #39
  added a `native-build` job (macos-15 / Xcode 16.4: `xcodegen generate` +
  `xcodebuild … build`, unsigned Debug) that runs on every PR. So "does it
  compile" is now enforced automatically; **"does it work on a device" is what
  only you can answer.**
- **Three PRs are staged for the 0.4.2 launch** (all target `main`):
  | PR | Branch | What | State |
  | --- | --- | --- | --- |
  | **#37** | `claude/native-openrouter-gateway` | OpenRouter as the single cloud cleanup gateway; version bump **0.4.2 / build 3** | **draft** |
  | **#38** | `claude/launch-hardening-site` | Website accuracy + legal (WhisperKit, macOS 14+, privacy page, headline fix) | open |
  | **#39** | `claude/launch-hardening-ops` | Release-ops hardening (guard legacy `v*`, native CI build, version discipline, required appcast) | open |
- **Last published native tag:** `native-v0.4.1`. **Next:** `native-v0.4.2`
  (`CFBundleVersion` **3** — Sparkle orders by build number, so 0.4.1 users only
  auto-update if 3 > the build behind `native-v0.4.1`). No `native-v0.4.2` tag
  exists yet — **you create it.**
- **Signing/notarization is already automated** on the GitHub `macos-15`
  runners using the *same* Apple secrets the Python release uses. You do **not**
  need to sign locally. The one new secret is `SPARKLE_ED_PRIVATE_KEY` (§2).

---

## 1. Critical path (the only hard blockers to launch)

Do these in order. 1–2 are one-time setup; 3–6 are the release itself.

### 1.1 Land the three 0.4.2 PRs onto `main`

Recommended: **bundle #37 + #38 + #39 into one 0.4.2 launch** so the site, the
app, and the ops guards all describe the same version at once. Order:

1. Merge **#39** first (ops) if not already in — it's what makes CI compile the
   Swift and enforces version agreement at tag time. Harmless on its own.
2. Merge **#37** (the app + the 0.4.2/build-3 bump). CI's `native-build` job
   will compile it; if it goes green, the OpenRouter changes build clean.
   **Flip #37 out of draft** before merging.
3. Merge **#38** (website) — or hold it until the DMG is live (step 6) so the
   download link never points at a release that doesn't exist yet. Either works;
   holding is slightly safer.

> If you'd rather not bundle: #38's site copy already describes 0.4.2-era
> behavior (OpenRouter-only cleanup), so shipping it **before** 0.4.2 is live
> would briefly overstate what 0.4.1 users have. Bundling avoids that skew.

### 1.2 Local device build + smoke test (§3 has the full checklist)

Before tagging, build and run on a real Mac from the merged `main`:

```bash
cd native
xcodegen generate
open OpenVoiceFlow.xcodeproj     # or: bash scripts/build-app.sh with OVF_NOTARIZE=0
```

Run the app, walk onboarding, grant the three permissions, and **verify the full
loop end-to-end** (hold hotkey → speak → release → polished text pastes at the
cursor). The full smoke checklist is §3. **Do not tag until the loop works on a
device** — CI cannot do this.

### 1.3 Generate the Sparkle keypair (one-time) — §2

Without it the release **fails** now (PR #39 made the appcast step required).
Do §2 once, commit the public key, add the private key as a repo secret.

### 1.4 Tag the release candidate, then the release

```bash
# from an up-to-date main that includes #37 (0.4.2 / build 3)
git tag native-v0.4.2-rc1 && git push origin native-v0.4.2-rc1   # exercise the pipeline
# …verify the rc release artifacts (below), then:
git tag native-v0.4.2      && git push origin native-v0.4.2
```

`release-native.yml` fires on `native-v*`: it builds a **universal,
Developer-ID-signed, Apple-notarized, stapled DMG**, generates the Sparkle
appcast, and attaches both to the GitHub Release. The `-rc1` suffix marks it a
pre-release automatically.

### 1.5 Verify the release artifacts

On the published Release (rc first, then final):

- [ ] `OpenVoiceFlow-0.4.2.dmg` attached and downloadable.
- [ ] `appcast.xml` attached, `sparkle:version` = **3**, `sparkle:edSignature`
      present, `enclosure url` points at the site downloads path.
- [ ] Download the DMG on a clean Mac → `spctl --assess --type execute
      /Applications/OpenVoiceFlow.app` says **accepted** (Gatekeeper passes).
- [ ] **Auto-update proof:** install 0.4.1, then point it at the new appcast and
      confirm it offers → downloads → installs 0.4.2 (Sparkle). This is the whole
      reason build number discipline matters.

### 1.6 Flip the website

- [ ] Merge **#38** if you held it.
- [ ] Put `OpenVoiceFlow-0.4.2.dmg` where the site serves downloads
      (`docs/downloads/` — the site self-hosts DMGs; `tests/test_docs_distribution.py`
      gates version/hash accuracy, so update whatever it checks).
- [ ] Confirm `SUFeedURL` in `Info.plist` and the site-root `appcast.xml` agree
      (both the site-root feed).

**When 1.1–1.6 are green, 0.4.2 is launched.**

---

## 2. Sparkle keypair — one-time setup (hard blocker)

In-app auto-update needs an EdDSA keypair. The **public** half goes in
`Info.plist`; the **private** half becomes a repo secret the release signs with.

```bash
# Get Sparkle's tools (same version the release uses: 2.9.4)
curl -fsSL https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz | tar -xJ
./bin/generate_keys          # prints the PUBLIC key; stores the PRIVATE key in the Keychain
./bin/generate_keys -x sparkle_private.pem   # export the private key to a file for the secret
```

1. **Public key → `Info.plist`.** Set `SUPublicEDKey` to the printed public key
   (uncomment/replace the placeholder). Commit this **in the same change** that
   ships 0.4.2 — a mismatch means clients reject every update.
2. **Private key → repo secret `SPARKLE_ED_PRIVATE_KEY`** (Settings ▸ Secrets ▸
   Actions). Paste the exported private key string. Keep it out of git.
3. Confirm the Apple signing secrets already used by `release.yml` are present
   (they are — the Python DMGs ship signed): `APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`,
   `…_PASSWORD`, `APPLE_KEYCHAIN_PASSWORD`, `APPLE_NOTARY_KEY_BASE64`,
   `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`, `APPLE_CODESIGN_IDENTITY`.

> Guardrail already in place: `native/scripts/appcast.sh` now **fails loudly** if
> `SPARKLE_ED_PRIVATE_KEY` is unset (it used to no-op), and the appcast step is a
> required part of the release. So a release can't silently ship without an
> update feed — but that also means **you must do this before tagging.**

---

## 3. On-device smoke test (only a real Mac can do this)

CI compiles; it can't grant TCC permissions or synthesize a paste into a real
app. Walk this on a device from the release build:

- [ ] **Onboarding:** welcome → three permission rows → "Getting ready" model
      download → "Say hello". Grant Microphone, Accessibility, Input Monitoring;
      confirm each dot turns green.
- [ ] **The "Not listed?" escape hatch** works if the app is denied or attributed
      to Xcode/Terminal in a dev build (`OnboardingView.swift` permission rows).
- [ ] **fn/Globe key push-to-talk** — the marquee feature. Set System Settings ▸
      Keyboard ▸ "Press 🌐 to: Do Nothing" first, then hold-to-talk with fn.
      Also verify Right ⌘ (the default `Hotkey`).
- [ ] **Full loop in 3+ apps** — dictate into Notes, Safari, VS Code (or Slack).
      Verify the per-app style map applies (`FeatureStores.swift` `StyleStore`):
      code style in an editor, casual in Slack.
- [ ] **OpenRouter cleanup** — add a real OpenRouter key (Dashboard ▸ Settings),
      pick OpenRouter, confirm cleanup runs and the default model
      `google/gemma-4-31b-it` resolves (verified present on OpenRouter's live API;
      a `:free` variant exists too). Then set cleanup **Off** and confirm the raw
      transcript pastes.
- [ ] **Offline first-run** — fresh Mac, no network after the model download:
      transcription still works (WhisperKit is on-device).
- [ ] **Clipboard preservation** — copy an image, dictate, confirm your image is
      back on the clipboard after paste (`Paster.swift` snapshot/restore).
- [ ] **Too-short nudge** — tap-and-release instantly → "keep talking" nudge, not
      an error (`AppController.stopAndProcess`).
- [ ] **Max-duration ceiling** — hold past `maxRecordingSeconds` (300 s) →
      it finalizes and inserts, never records forever.
- [ ] **Sparkle "Check for Updates…"** from the menu bar reaches the feed.

---

## 4. Hardening review — fix while you're on the device

These are real gaps I found in the current Swift, but they need a device to
verify a fix (or are small enough to fold into the compile pass). Each has a
file pointer and a suggested fix. **Majors are worth fixing before 0.4.2;**
minors can ship as 0.4.3 if time-boxed. Fix without simplifying behavior.

### 4.1 [MAJOR] Paste-failure path is UI-only — not wired

The HUD already has a `.pasteBlocked` state with copy *"Copied instead — press
⌘V."* (`HUDController.swift:27,33,472`), but **nothing ever triggers it**.
`Paster.paste(_:)` (`Paster.swift:16`) is fire-and-forget: it sets the
pasteboard, synthesizes ⌘V, and **unconditionally restores the old clipboard
after 0.15 s** — so if Accessibility was revoked or ⌘V doesn't land, the user's
text is *both* un-pasted *and* wiped from the clipboard. Silent data loss.

**Fix:** in `Paster.paste`, gate on `AXIsProcessTrusted()` first. If not trusted
(or paste can't be posted), **leave the text on the clipboard** (skip the
restore) and have `AppController.deliver` show `hud.show(.error(.pasteBlocked))`
instead of `.result`. Wire the `.pasteBlocked` "Grant Access" action button to
open the Accessibility settings deep link.

### 4.2 [MAJOR] Model / language changes need an app restart

`Transcriber` binds `modelName` at `init` (`Transcriber.swift:13`) and there's
**no `setModel`**. Changing **Model** or **Language** in the dashboard updates
`Settings` (persisted) but the live `Transcriber` keeps the old model in memory.
A user who switches to a multilingual model or picks a non-English language sees
**no effect until relaunch** — and `base.en` (the default) can't transcribe
non-English at all, so a language switch appears broken.

**Fix:** add `Transcriber.setModel(_ name: String) async` that drops `kit`
(`kit = nil`), updates `modelName`, and re-warms. Call it from the Settings
binding when `whisperModel` changes. Consider auto-selecting a multilingual
variant when `language != "en"`, or warn in the UI that `base.en` is
English-only.

### 4.3 [MINOR] `warmUp()` can double-download the model

Two concurrent callers — onboarding's `prepareModelForOnboarding` and
`startListening()`'s background `Task { try? await warmUp() }`
(`AppController.swift:93`) — can both pass the `kit == nil` guard across the
`await` inside `downloadAndLoad` (`Transcriber.swift:23–36`) and fetch the model
twice on first run.

**Fix:** cache the in-flight load as a `Task` on the actor and have concurrent
callers `await` the same task, e.g. `private var loadTask: Task<WhisperKit,
Error>?`.

### 4.4 [MINOR] "Sounds" toggle is inert

`Settings.soundFeedback` (`Settings.swift:13`) has a dashboard toggle
(`DashboardView.swift:485`) but **nothing plays a sound** anywhere. Either wire
`NSSound` on record-start / success (respecting the toggle) or hide the control
until it does something.

### 4.5 [MINOR] "Launch at login" is inert

`Settings.launchAtLogin` (`Settings.swift:14`) is persisted but there's **no
`SMAppService.mainApp` registration**, so toggling it does nothing. Wire
`SMAppService.mainApp.register()/unregister()` to the binding, or hide the
control. (This is a common first-run expectation for a menu-bar app.)

> `automaticUpdates` **is** correctly wired to Sparkle (`Updater.swift:28`), so
> that toggle is fine — listed here only to say it was checked.

---

## 5. Ship checklist (tick before calling it launched)

- [ ] #37 (+ #39, + #38) merged to `main`; CI `native-build` green.
- [ ] `SUPublicEDKey` set in `Info.plist`; `SPARKLE_ED_PRIVATE_KEY` secret added.
- [ ] Device smoke test (§3) passes — full loop works, fn-key push-to-talk works.
- [ ] Major hardening items (§4.1, §4.2) fixed or consciously deferred to 0.4.3.
- [ ] `native-v0.4.2-rc1` tagged → release built → artifacts verified (§1.5).
- [ ] `native-v0.4.2` tagged → signed/notarized DMG + appcast published.
- [ ] `spctl` accepts the DMG; Sparkle updates 0.4.1 → 0.4.2 on a test machine.
- [ ] Website flipped: DMG in `docs/downloads/`, #38 merged, `appcast.xml` at the
      site root agrees with `Info.plist` `SUFeedURL`.

## 6. Rollback

If the rc or release DMG is bad: delete the bad tag + its GitHub Release, fix,
re-tag. Because Sparkle orders strictly by `CFBundleVersion`, **never reuse a
build number** — if 0.4.2 build 3 shipped and was pulled, the fixed build must be
**4** (bump `CURRENT_PROJECT_VERSION` in `project.yml` **and** `CFBundleVersion`
in `Info.plist`; the release-native version-agreement guard will refuse a
mismatch). The website's `docs/downloads/` DMG can be reverted independently of
the tag.

---

### Handy references in this repo
- `native/RELEASE_NATIVE_RUNBOOK.md` — copy-paste release steps.
- `native/BUILD_RUNBOOK.md` — first-principles build/compile guide (phases 0–F).
- `.github/workflows/release-native.yml` — the tag-driven signed release.
- `native/scripts/build-app.sh` — local build (`OVF_NOTARIZE=0` for unsigned).
- `native/scripts/appcast.sh` — Sparkle appcast signing.

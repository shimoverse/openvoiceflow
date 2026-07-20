# Native 0.4.0 — finish-line runbook (Mac agent)

Everything is authored and wired; what remains needs a Mac + repo admin. This
is the copy-paste version. Target: a signed, notarized OpenVoiceFlow **0.4.0**
DMG on the GitHub Release + live on the website, with in-app updates working.

The whole build/sign/notarize runs **on GitHub's macOS runner** via
`.github/workflows/release-native.yml`. Your local Mac is needed only to
generate keys, validate the Swift compiles, and push the tag.

---

## 0. Validate the Swift compiles (once)

The native Swift app is not in CI. Confirm it archives cleanly:

```bash
cd native
xcodegen generate
OVF_NOTARIZE=0 bash scripts/build-app.sh    # unsigned universal build + DMG
```

Fix any compile errors (Linux-authored: `Updater.swift`, the Phase E stores,
SwiftUI tag types). Behavior must stay intact — don't simplify to compile.

## 1. Sparkle keypair (once, ever)

```bash
# from the Sparkle 2.9.4 tools (bin/generate_keys)
./bin/generate_keys                 # stores the private key in your login keychain
./bin/generate_keys -p              # prints the PUBLIC key (base64)
./bin/generate_keys -x sparkle_private_key.txt   # exports the PRIVATE key
```

- Paste the **public** key into `native/Info.plist` → uncomment
  `SUPublicEDKey` and set it. Commit that to the native branch.
- Add the **private** key file's contents as repo secret
  `SPARKLE_ED_PRIVATE_KEY` (Settings ▸ Secrets ▸ Actions). Then delete the
  local file.

## 2. Confirm signing secrets exist

`release-native.yml` reuses the exact secrets that already ship the Python
DMGs — verify they're set (they are, if `release.yml` publishes signed):

```
APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64
APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD
APPLE_KEYCHAIN_PASSWORD
APPLE_NOTARY_KEY_BASE64
APPLE_NOTARY_KEY_ID
APPLE_NOTARY_ISSUER_ID
APPLE_CODESIGN_IDENTITY      # "Developer ID Application: NAME (TEAMID)"
```

No new signing secret needed — the team id is parsed from the identity string.

## 3. Tag & release (an RC first)

```bash
# from the native branch, once SUPublicEDKey is committed
git tag native-v0.4.0-rc1
git push origin native-v0.4.0-rc1     # → builds a *pre-release* DMG + appcast
```

Watch the run. On green, download the DMG, drag-install on a clean Mac, and
confirm: onboarding → grant the 3 permissions → hold hotkey → speak → text
pastes; **Check for Updates…** reaches the appcast (will report "up to date").

When happy, cut the real one:

```bash
git tag native-v0.4.0
git push origin native-v0.4.0         # → the notarized 0.4.0 DMG + appcast
```

## 4. Go live on the website

The website is already prepped (staged PR from `docs/`): 0.4.0 copy, one
universal-DMG download button, JSON-LD, and `appcast.xml`. Finish it by putting
the real artifacts in place:

```bash
# copy the notarized DMG the Release produced into the site, and the appcast
cp OpenVoiceFlow-0.4.0.dmg  docs/downloads/
cp appcast.xml              docs/appcast.xml     # from the Release asset
```

Then merge the staged website PR to `main` (Vercel deploys `docs/` from main).
Verify `https://openvoiceflow.vercel.app/appcast.xml` and the download resolve.

> macOS floor: native requires **14.0+** (WhisperKit). The site copy says so.
> Keep the Python 0.3.6 DMGs reachable for 12–13 users if you want a fallback
> link; otherwise 0.4.0 replaces them.

---

### What Linux already did (so you don't redo it)

- `Updater.swift` + launch wiring + menu hook; `SUFeedURL`/schedule in Info.plist.
- `release-native.yml`, `build-app.sh`, `appcast.sh` (all validated: `bash -n`,
  YAML parse).
- `docs/` staged for 0.4.0 (separate website PR).
- Everything except: key generation, the `SUPublicEDKey` commit, pushing the
  tag, and merging the website PR — all Mac/admin-gated.

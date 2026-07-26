# 0.5.0 release — handoff to Meeru

**Written 2026-07-26.** Read the "Where things stand" section first; some of
this is mid-flight and the state matters.

## What 0.5.0 is

The phase-06 design redesign of the native macOS app: first-run onboarding, the
dictation HUD, and the dashboard Home pane. Nine work items (T1–T9), merged to
`main` as commit `112607d` via PR #51.

The important property for you: **it was written entirely on a Linux machine.**
The Swift compiles — GitHub's macOS runners verified every commit — but nothing
in it has ever been *run*. For a release whose whole point is how it looks, that
is the gap you're being asked to close.

## Where things stand

| Step | State |
| --- | --- |
| Code merged to `main` | Done — `112607d` |
| Tag `native-v0.5.0` pushed | Done — points at `112607d` |
| Release build (signed DMG + appcast) | **FAILED**, then fixed; needs a re-run |
| Website updated to 0.5.0 | Not started — blocked on the DMG existing |
| The nine visual checks | Not started — needs a Mac |

### Why the release build failed

`spctl -a -vvv -t install` rejected the DMG with `no usable signature`.

The cause is a real, pre-existing gap, not a fluke. The pipeline signed the
`.app`, notarized it, notarized the DMG, and stapled a ticket to the DMG — but
it **never code-signed the DMG itself**. `spctl -t install` evaluates a disk
image against its own signature, and a stapled ticket is not a signature.

This went unnoticed through 0.4.1, 0.4.2 and 0.4.3 because that check ended in
`|| true` and silently swallowed the rejection. Phase 06 made the check
blocking, which is what surfaced it — the check is doing its job; the pipeline
was the thing that was wrong.

**This did not harm users.** The app inside the DMG was always properly signed
and notarized, which is why 0.4.3 gives the mild "downloaded from the
Internet → Open" prompt rather than a hard refusal. The fix closes a real gap,
it doesn't repair a shipped defect.

The fix adds `codesign --force --timestamp --sign "$OVF_SIGN_IDENTITY"` to the
DMG, **before** notarization — signing after stapling would invalidate the
ticket.

## Task A — get the release built

By the time you read this the fix may already be merged and the tag moved. Check
first:

```bash
gh run list --workflow=release-native.yml --limit 3
gh release view native-v0.5.0
```

If a green run and a release with an attached DMG exist, skip to Task B.

If not, the fix is in `native/scripts/build-app.sh`. The tag must point at a
commit that *contains* the fix, because the workflow checks out the tag:

```bash
git fetch origin main && git checkout main && git pull
git tag -f native-v0.5.0 && git push -f origin native-v0.5.0
```

### If it fails again

The signing step is the only untested part — nobody has run `codesign` against
a DMG in this pipeline before. Two plausible failures:

- **`codesign` can't find the identity.** The keychain is unlocked earlier in
  the workflow for the app signing, so the identity is present; if this fails,
  print `security find-identity -v -p codesigning` in the step to see what the
  runner actually has.
- **`spctl` still rejects it.** Then the assertion is stricter than this
  distribution model supports, and the honest fix is to drop the `spctl` check
  and keep `stapler validate` — which is what actually governs the user-facing
  prompt. Do **not** restore `|| true`; that hides failures rather than
  deciding about them. Say which you did and why.

## Task B — the nine things only eyes can check

This is the part that genuinely needs you, and it matters more than Task A.

Build and run the app locally:

```bash
git clone https://github.com/shimoverse/openvoiceflow.git ~/ovf-test \
  && cd ~/ovf-test && bash native/scripts/run-local.sh
```

Then work through **`native/design/PHASE06_TRY_IT.md`**, which lists the nine
checks in the order you hit them, phrased as what to look for. The two highest
value:

1. **Light mode.** The old build forced a dark window regardless of system
   appearance. Log in with Appearance: Light and confirm nothing stayed dark and
   no text is too faint. This is the single most likely place for a missed
   hardcoded colour.
2. **A live permission grant.** At the permissions step, grant Accessibility in
   System Settings while leaving the onboarding window frontmost, and *do not*
   click back into it. The dot should turn green within ~1 s on its own. The old
   build only noticed on refocus, so it looked frozen.

`native/design/PHASE06_ACCEPTANCE.md` has all 19 checks with what backs each —
ten are settled by source or CI, nine are yours.

Report findings in plain language. Anything that looks wrong is worth saying
even if you're unsure it's a bug.

## Task C — the website

**Do not start this until the release exists and has a real DMG.** The download
page must never point at a missing file, and the sha256 must be computed from
the published artifact — never hand-written.

The page also carries three "what happens next" cards added in this release
(drag to Applications / open it yourself / macOS will warn you once). Those are
version-independent — leave them alone.

What changes: the DMG in `docs/downloads/`, the sha256 (appears twice — the
displayed line and the copy button's `data-copy`), the version strings in
`docs/download.html`, `docs/appcast.xml`, and `RELEASE_VERSION` /
`UNIVERSAL_SHA256` in `tests/test_docs_distribution.py`. That test asserts the
checksum matches the file on disk, so it will catch a mismatch — run
`pytest tests/test_docs_distribution.py` before pushing.

Verify the digest against what GitHub published rather than trusting a local
copy:

```bash
gh release download native-v0.5.0 --pattern '*.dmg' --dir /tmp/rel
shasum -a 256 /tmp/rel/OpenVoiceFlow-0.5.0.dmg
```

I can do this part from here once the release exists — coordinate so we don't
both do it.

## Two hard constraints

**Never regenerate the Sparkle keypair.** `SUPublicEDKey` in
`native/Info.plist` is live. The private half is the repo secret
`SPARKLE_ED_PRIVATE_KEY`. Every shipped install verifies updates against that
public key, so a new keypair permanently breaks auto-update for everyone who
already has the app. There is no recovery path. If anything suggests
regenerating it, stop and ask.

**The build number must keep climbing.** Sparkle orders updates by
`CFBundleVersion`, not the marketing version. 0.5.0 is build 5; the live
appcast is build 4. If you cut another build, increment it — an equal or lower
number means clients never see the update, with no error to explain why.

## One thing to weigh before releasing

Once the release publishes, existing 0.4.3 installs auto-update to 0.5.0 within
about a day. That happens whether or not anyone has looked at the redesign.

If the visual checks in Task B haven't been done, consider doing them before
the release publishes rather than after. The build finishing is not the same as
it reaching people, and deleting an unreleased GitHub Release is cheap;
recalling an auto-update is not.

Owner's call, not yours or mine — but say so if you're being asked to publish
before anyone has seen it.

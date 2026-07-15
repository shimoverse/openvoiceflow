# Mac App Store submission checklist

## Code and bundle

- [x] Separate Store target; direct DMG target unchanged.
- [x] Native executable with no runtime shell, Homebrew, Python, venv, or pip.
- [x] App Sandbox enabled.
- [x] Microphone is the only protected hardware entitlement.
- [x] No Accessibility, Input Monitoring, Apple Events, or broad file-access entitlement.
- [x] whisper.cpp XCFramework version and SwiftPM checksum pinned.
- [x] Bundled model source, byte length, and SHA-256 pinned.
- [x] Privacy manifest included.
- [ ] Release archive signed with the account's Mac App Distribution/Apple Distribution identity.
- [ ] Installer/export signed with the required Mac Installer Distribution identity.
- [ ] Archive validated with Apple's upload tooling.

## Apple account

- [ ] Register `com.shimoverse.openvoiceflow` on the intended Apple Developer team.
- [ ] Create/read back the Mac App Store provisioning profile.
- [ ] Create the App Store Connect macOS app record.
- [ ] Confirm the displayed seller name. The current Individual membership displays the account holder's legal name; convert to an Organization before submission if a company seller name is required.
- [ ] Confirm Agreements, Tax, and Banking status if the app will be paid. They are not required for a free listing unless Apple shows an account action.

## Listing

- [x] Name, subtitle, keywords, description, and What's New copy drafted.
- [x] Privacy-label answers documented.
- [x] Review path and permission explanation documented.
- [x] Public privacy, support, and terms URLs implemented.
- [ ] Capture current Mac screenshots from the signed Release build.
- [ ] Select primary category Productivity and secondary category Utilities.
- [ ] Complete age rating (expected 4+; verify in App Store Connect).
- [ ] Complete export-compliance questions using `ITSAppUsesNonExemptEncryption=false`.
- [ ] Confirm app-name availability in App Store Connect; public search alone does not reserve the name.

## Verification before Submit for Review

- [ ] Clean install on a Mac with no prior OpenVoiceFlow state.
- [ ] Microphone prompt is attributed to OpenVoiceFlow.
- [ ] On-screen Record button works.
- [ ] Control+Option+Space press/release works without Input Monitoring.
- [ ] English transcription works fully offline.
- [ ] Output appears in the window and pasteboard.
- [ ] App relaunch preserves no private transcript history.
- [ ] No network traffic occurs during normal use.
- [ ] App Store Connect build reaches `VALID`.
- [ ] Final submission and legal attestations approved by the account holder.

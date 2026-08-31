# History Feedback and App Identities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give History copy actions visible self-dismissing feedback and show a real icon beside every app name in the dashboard.

**Architecture:** A small `HistoryCopyFeedback` state object owns cancellable acknowledgement timing. A pure `AppIdentityCatalog` owns bundle IDs and bundled resource names, while `AppIconProvider` performs AppKit resolution and a reusable SwiftUI view renders the result consistently.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit, Combine, pytest-driven Swift harnesses, SVG resources.

**Spec:** `docs/superpowers/specs/2026-08-30-history-app-logos-leaderboard-reliability-design.md`

## Global Constraints

- One installation remains one anonymous leaderboard identity; this plan does not alter analytics.
- Known seeded apps must never fall back to initials.
- Unknown app names use a neutral application glyph.
- Brand assets are identification-only and their provenance is documented.
- New Swift sources must compile for macOS 14 with Swift 5.10.

---

### Task 1: Self-dismissing copy acknowledgement

**Files:**
- Create: `native/Sources/OpenVoiceFlow/HistoryCopyFeedback.swift`
- Modify: `native/Sources/OpenVoiceFlow/DashboardView.swift:25-31,580-615`
- Create: `tests/test_native_history_app_identity.py`

**Interfaces:**
- Produces: `@MainActor final class HistoryCopyFeedback: ObservableObject`
- Produces: `func markCopied(_ entryID: UUID, dismissAfterNanoseconds: UInt64 = 1_500_000_000)`
- Produces: `func isCopied(_ entryID: UUID) -> Bool`

- [ ] **Step 1: Write the failing Swift-harness test**

Add a pytest that compiles `HistoryCopyFeedback.swift` with an async `@main` harness. The literal assertions are:

```swift
let first = UUID()
let second = UUID()
let feedback = await HistoryCopyFeedback()
await feedback.markCopied(first, dismissAfterNanoseconds: 80_000_000)
precondition(await feedback.isCopied(first))
await feedback.markCopied(second, dismissAfterNanoseconds: 10_000_000)
precondition(!(await feedback.isCopied(first)))
precondition(await feedback.isCopied(second))
try? await Task.sleep(nanoseconds: 30_000_000)
precondition(!(await feedback.isCopied(second)))
```

- [ ] **Step 2: Run the test and verify RED**

Run: `python3 -m pytest tests/test_native_history_app_identity.py::test_copy_feedback_moves_between_rows_and_self_dismisses -q`

Expected: FAIL because `HistoryCopyFeedback.swift` does not exist.

- [ ] **Step 3: Add the minimal state object**

Implement one published optional UUID and one cancellable `Task<Void, Never>`. `markCopied` cancels the previous task, publishes the new ID, sleeps, checks cancellation, and clears only when the same ID is still current.

- [ ] **Step 4: Wire the History button**

Add `@StateObject private var copyFeedback = HistoryCopyFeedback()`. Only after `NSPasteboard.setString` returns `true`, call `markCopied(entry.id)`. Render a `Label` whose title is `Copied` with `checkmark` for the acknowledged row and `Copy` with `doc.on.doc` otherwise.

- [ ] **Step 5: Run focused and full tests**

Run: `python3 -m pytest tests/test_native_history_app_identity.py -q`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add native/Sources/OpenVoiceFlow/HistoryCopyFeedback.swift native/Sources/OpenVoiceFlow/DashboardView.swift tests/test_native_history_app_identity.py
git commit -m "feat(native): acknowledge copied history rows"
```

### Task 2: Complete app-identity catalog and bundled marks

**Files:**
- Create: `native/Sources/OpenVoiceFlow/AppIdentityCatalog.swift`
- Modify: `native/Sources/OpenVoiceFlow/AppIconProvider.swift`
- Add: `native/Resources/BrandIcons/*.svg`
- Modify: `native/Resources/BrandIcons/README.md`
- Modify: `tests/test_native_history_app_identity.py`

**Interfaces:**
- Produces: `struct AppIdentityDescriptor: Equatable` with `bundleIdentifiers: [String]` and `brandResource: String?`
- Produces: `enum AppIdentityCatalog` with `static func descriptor(for name: String) -> AppIdentityDescriptor?`
- Consumes: `AppIconProvider.icon(for:)`

- [ ] **Step 1: Write the failing catalog behavior test**

Compile `AppIdentityCatalog.swift` with a harness containing the 24 literal seeded names plus `Claude`. Assert every name returns a descriptor with at least one bundle ID or a brand resource. Assert exact resources for the reported gaps:

```swift
precondition(AppIdentityCatalog.descriptor(for: "Notion")?.brandResource == "notion")
precondition(AppIdentityCatalog.descriptor(for: "Outlook")?.brandResource == "microsoftoutlook")
precondition(AppIdentityCatalog.descriptor(for: "Claude")?.brandResource == "claude")
precondition(AppIdentityCatalog.descriptor(for: "Discord")?.brandResource == "discord")
precondition(AppIdentityCatalog.descriptor(for: "Unknown") == nil)
```

- [ ] **Step 2: Run the catalog test and verify RED**

Run: `python3 -m pytest tests/test_native_history_app_identity.py::test_seeded_apps_and_claude_have_real_identity_descriptors -q`

Expected: FAIL because the catalog does not exist.

- [ ] **Step 3: Implement descriptors and resolver order**

Add exact bundle-ID aliases for installed lookup and branded fallbacks for all seeded names. Update `AppIconProvider` to resolve running app, each known bundle ID using `NSWorkspace.urlForApplication(withBundleIdentifier:)`, display name, and finally the descriptor's bundled SVG.

- [ ] **Step 4: Vendor and document marks**

Obtain SVG marks from Simple Icons 16.29.0 for Claude, Discord, Gmail, Google Chrome, iTerm2, JetBrains/PyCharm, Microsoft Outlook, Microsoft Word, Notion, OpenAI, Signal, Slack, Sublime Text, Superhuman, Telegram, Visual Studio Code, WhatsApp, and Zed. Use an Apple company mark for seeded Apple apps whose installed icon is absent and a Panic mark for Nova. Record source, version, CC0 distribution statement, and nominative trademark use in `BrandIcons/README.md`.

- [ ] **Step 5: Add the packaging test and verify GREEN**

For every non-nil `brandResource` returned by the literal harness list, assert `native/Resources/BrandIcons/<resource>.svg` exists and is non-empty. Run:

`python3 -m pytest tests/test_native_history_app_identity.py -q`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add native/Sources/OpenVoiceFlow/AppIdentityCatalog.swift native/Sources/OpenVoiceFlow/AppIconProvider.swift native/Resources/BrandIcons tests/test_native_history_app_identity.py
git commit -m "feat(native): cover app identities with real logos"
```

### Task 3: Use one icon-plus-name presentation everywhere

**Files:**
- Create: `native/Sources/OpenVoiceFlow/AppIdentityView.swift`
- Modify: `native/Sources/OpenVoiceFlow/DashboardView.swift:407-485,582-615,827-846,1478-1530`
- Modify: `tests/test_native_history_app_identity.py`

**Interfaces:**
- Produces: `struct AppIdentityIcon: View`
- Produces: `struct AppIdentityLabel: View`
- Consumes: `AppIconProvider.icon(for:)`

- [ ] **Step 1: Write the failing rendering contract**

Add a test that identifies each dashboard app-name consumer and requires `AppIdentityLabel(name:)` in Where You Dictate, Recent, History, and Styles. Require `AppIdentityIcon` inside the percentage ring. The break caught is reintroducing a text-only destination name.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `python3 -m pytest tests/test_native_history_app_identity.py::test_every_dashboard_app_name_uses_the_shared_identity_view -q`

Expected: FAIL on the current text-only rows.

- [ ] **Step 3: Add shared views and replace all four call sites**

`AppIdentityIcon` renders the resolved `NSImage` or `Image(systemName: "app.fill")`; `AppIdentityLabel` composes that icon with `Text(name)`. Replace `Text(row.app)`, both `Text(entry.app)` occurrences, and the Styles row's `Text(app)`/legacy `AppStyleIcon` pairing. Keep existing fonts, colors, truncation, and row spacing.

- [ ] **Step 4: Run tests and compile**

Run:

```bash
python3 -m pytest tests/test_native_history_app_identity.py -q
xcodebuild -project native/OpenVoiceFlow.xcodeproj -scheme OpenVoiceFlow -configuration Debug -derivedDataPath /tmp/openvoiceflow-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: tests PASS and Xcode reports `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add native/Sources/OpenVoiceFlow/AppIdentityView.swift native/Sources/OpenVoiceFlow/DashboardView.swift tests/test_native_history_app_identity.py
git commit -m "feat(native): show app logos across dashboard"
```

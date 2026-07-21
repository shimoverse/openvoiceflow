# OpenVoiceFlow Native Mac App — Product and Engineering Plan

**Status:** Proposed product plan

**Goal:** Evolve OpenVoiceFlow from a menu-bar dictation utility into a proper native Mac app with a Dock presence, premium onboarding, local profile and dictionary learning, useful local usage insights, and a strict privacy-first English-only workflow.

**Non-goal:** Copy Wispr Flow’s branding, layout, text, or proprietary behavior. The screenshots are reference material for information architecture and interaction quality only.

## Executive recommendation

Build a **native Swift macOS product**, not a larger Tk/rumps wrapper around the existing Python app.

Keep two distribution paths:

1. **OpenVoiceFlow Direct** — preserves the current strongest workflow: Right Command push-to-talk, automatic paste, selected-text context, optional LLM cleanup, and Accessibility-assisted correction learning.
2. **OpenVoiceFlow Mac App Store** — a separately signed and sandboxed native build with a visible Dock app, local transcription, local profile/dictionary/analytics, a normal global shortcut, and clipboard-first output. It must not install Homebrew/Python dependencies or silently access other applications.

The current repository already contains useful product logic to migrate: `profile.py`, `dictionary.py`, `learner.py`, `stats.py`, `onboarding.py`, `context.py`, and local secure persistence. The current implementation is Python/rumps/Tk and writes JSON/JSONL under `~/.openvoiceflow`; it is not the right long-term foundation for a polished native Store app.

## Product principles

- **One memorable action:** hold the shortcut, speak, release, and get usable English text.
- **Local by default:** audio, transcription, profile, dictionary, corrections, analytics, and history stay on the Mac. No account is required.
- **Honest analytics:** show only metrics actually recorded locally; never seed impressive numbers.
- **Progressive permissions:** explain each permission at the moment it is needed; never strand the user on a generic Settings screen.
- **Learning with consent:** a correction becomes a suggestion first, not a silent permanent rule.
- **English-only clarity:** do not pretend unsupported foreign-language audio is valid English.
- **Native Mac identity:** a real main window in the Dock plus a menu-bar status item, not a hidden background utility pretending to be an app.
- **Reversible privacy:** every learned term, stored session, and analytics category can be viewed, exported, disabled, or erased.

## Reference insights from the supplied screenshots

The screenshots suggest a strong information architecture worth adapting, not copying:

- A persistent left navigation separates **Home, Insights, Dictionary, and Settings**.
- The Dictionary screen has a clear primary **Add new** action, search/sort controls, and a prominent explanation of how personal words and names are learned.
- The Insights screen gives the user a hierarchy: a few headline metrics first, then correction breakdown, app/context usage, and a calendar-style activity view.
- The Home screen combines a welcome state, one hero action, a compact summary rail, and a recent activity feed.
- Settings groups shortcut, microphone, language, account/profile, and privacy rather than presenting a flat permission checklist.
- The product visibly exists in the Dock as well as the menu bar; the main app is where the user understands and controls the product.

OpenVoiceFlow should use a restrained native visual system—warm off-white surfaces, near-black type, a single saffron/orange accent, subtle waveform motion, generous spacing, and macOS-standard controls. It should not clone Wispr Flow’s colors, logo, screenshots, wording, or exact card composition.

## Information architecture

### Home

The first useful screen should answer: “What can I do right now?”

- Welcome line using the optional local profile name.
- One primary action: **Hold the shortcut to dictate**.
- Live state card: Ready → Listening → Transcribing → Copied.
- Today summary: words, sessions, average WPM, and learned corrections.
- Recent activity list with content hidden by default; show time, duration, word count, and correction status unless the user explicitly enables local transcript history.
- A quiet privacy statement: “Processed on this Mac. Nothing is sent.”

### Insights

Local-only dashboard; no team usage, leaderboard, sharing, or cloud account in the first product version.

Headline cards:

- Words dictated.
- Average words per minute.
- Time saved estimate, clearly labeled as an estimate.
- Corrections accepted / correction rate.

Secondary views:

- **Correction impact:** original recognition → final accepted text, without displaying raw content unless the user opens it.
- **Dictionary fixes:** learned terms applied, accepted, rejected, and manually added.
- **Apps used:** aggregate bundle identifiers/application names only, with an explicit opt-in and a one-click clear action. Off by default in the privacy-first build.
- **Activity heatmap:** sessions or words by day, never full transcript content.
- **Streak:** only after a real local session; empty state should say “Start your first dictation.”
- Date range: today, 7 days, 30 days, all time.

Every metric needs a tooltip explaining its calculation. Do not show “AI prompts,” team comparisons, or fabricated productivity claims.

### Dictionary

- Tabs: **All**, **Personal**, **Learned**, and **Needs review**.
- Primary action: **Add word**.
- Each row shows the canonical spelling, recognized aliases, source (manual/profile/learned), confidence, accepted-use count, and last-used date.
- Add/edit sheet fields:
  - Correct spelling.
  - Common misrecognitions or aliases.
  - Category: person, company, product, place, technical term, other.
  - “Always apply” versus “Suggest first.”
- Candidate review card after an observed correction: “You changed `X` to `Y`. Remember this next time?” with **Remember**, **Not now**, and **Never learn this**.
- Bulk import/export as a local JSON/CSV file chosen by the user.
- Delete one term, clear learned terms, or reset the entire dictionary.
- No “shared with team” surface until a real multi-device/team privacy model exists.

### Profile

A local profile, not an online account:

- Name or preferred display name.
- Role/occupation and optional industry.
- Important people, product names, companies, places, and technical terms.
- Preferred punctuation/style rules.
- Optional “how I usually write” examples, stored locally and never transmitted.

Profile terms seed the dictionary only after confirmation. The profile screen must explain that this is personalization on this Mac—not identity verification, cloud sync, or an account.

### Settings

Use the screenshot’s grouped structure, adapted to OpenVoiceFlow:

- **General:** launch behavior, Dock presence, menu-bar item, sounds, theme.
- **Shortcut:** record a normal global shortcut, test it, detect conflicts, restore default.
- **Microphone:** device selection, input meter, permission status, test recording.
- **Language:** English only in v1; show why non-English audio is rejected and make the model choice explicit.
- **Learning:** auto-suggest corrections, automatic acceptance threshold, observation duration, app exclusions, clear learned data.
- **Insights:** enable/disable local aggregate analytics, app breakdown, streaks, and retention window.
- **Privacy & Data:** transcript-history toggle, retention, export, erase all, open data folder, privacy explanation.
- **Profile & Dictionary:** edit local profile and terms.
- **About:** version, model version/checksum, open-source licenses, support, diagnostic export.

## First-run onboarding

Replace the current Tk wizard, which asks for a cloud LLM/API key before the first useful dictation, with a four-step native onboarding carousel. The user should be able to dictate locally without an API key.

### Card 1 — “Your voice, on your Mac”

- Explain the promise in one sentence.
- Show a small local-processing animation.
- State exactly what stays local: microphone audio, model processing, profile, dictionary, corrections, and insights.
- CTA: **Set up OpenVoiceFlow**.
- Secondary action: **Skip setup** goes to a usable default, not a dead end.

### Card 2 — “Choose how you speak”

- Show the default shortcut and a **Change shortcut** control.
- Listen for an actual test press rather than displaying a static keyboard image.
- Request microphone permission only after the user taps **Test microphone**.
- If permission is denied, show a specific **Open Microphone Settings** action plus a retry/read-back state.

### Card 3 — “Try one dictation”

- A guided 5-second exercise with a visible waveform.
- Show the exact path: hold → speak → release → text appears → paste.
- Display the result in the app and copy it to the clipboard.
- Do not request Accessibility just to complete the Store-safe first run.

### Card 4 — “Make it yours”

- Optional local name/profile fields.
- Explain the dictionary and correction-learning feature.
- Separate toggles for:
  - Learn corrections as suggestions.
  - Keep local transcript history.
  - Show local usage insights.
- Finish with **Start dictating** and a link to revisit the tour.

Onboarding requirements:

- Persist a versioned completion state and allow replay from Help.
- Every permission step must have success/failure/read-back UI.
- Never request cloud credentials in onboarding.
- Do not use fake sample statistics; use empty states until the user creates real data.
- Use native macOS sheets, keyboard focus, VoiceOver labels, reduced-motion support, and a visible progress indicator.

## English-only behavior

The current `base.en` model is an English-only transcription model, but model selection alone is not a reliable rejection mechanism. A non-English recording can still produce plausible garbage. Implement a local language gate:

1. Capture a short audio window.
2. Run local language identification using a pinned multilingual Whisper model or an equivalent on-device classifier.
3. Accept transcription only when English probability exceeds a documented threshold and the audio has sufficient speech confidence.
4. If the gate rejects the sample, show “OpenVoiceFlow currently supports English dictation” and delete the temporary audio immediately.
5. Never silently translate or store a rejected sample.
6. Add fixtures for English, Hindi, Spanish, code-switching, silence, music, and noisy speech. Code-switching should follow an explicit product rule rather than being guessed.

Model choice should be measured on Apple silicon for startup time, memory, language-gate accuracy, and transcription latency. Bundle only the model(s) required for the selected product target; do not download executable code at runtime.

## Correction-learning design

The existing `voiceflow/learner.py` already samples the focused Accessibility text field at 5, 10, 15, 20, and 30 seconds and extracts one-word substitutions using a similarity gate. That is a useful starting algorithm, not a complete product behavior.

### Learning pipeline

1. Save a short-lived local event containing the raw transcription, normalized output, timestamp, and target app only when the user has enabled learning.
2. If direct paste and Accessibility observation are authorized, watch only the same focused text field for a short configurable window.
3. Stop when the user changes apps, the field is not readable, the timeout expires, or the user presses **Stop learning**.
4. Compute token-level substitutions while ignoring insertions/deletions and punctuation-only edits.
5. Reject likely content edits, sentence rewrites, password fields, secure fields, and low-similarity substitutions.
6. Create a review candidate rather than silently changing the dictionary.
7. After the user accepts, store the canonical term, aliases, confidence, source, count, and last-used timestamp.
8. Apply accepted terms before transcription output or in the local post-processing stage.
9. Provide undo for the last learned rule and a complete learned-data reset.

### Privacy boundary

Universal after-the-fact correction learning requires Accessibility access and reading text in other applications. That is the highest-risk feature for both user trust and Mac App Store review. Therefore:

- **Direct edition:** may offer opt-in Accessibility-powered automatic paste, selected-text context, and correction observation with a clear permission explanation and app exclusions.
- **Mac App Store edition:** must start with local dictionary/profile learning and an in-app correction review flow. Automatic cross-app observation should be a separately tested capability, not assumed to be Store-compatible.
- Never inspect password fields, secure text fields, private browsing contexts, or excluded applications.
- Never send observed text to a server.
- Default to deleting raw before/after text after a candidate is accepted or rejected. Retain only the minimal dictionary rule and aggregate count unless the user explicitly enables history.

## Local data model

Use a native local SQLite/Core Data store inside the App Sandbox container. Do not keep growing JSONL transcript logs as the primary product database.

Suggested entities:

- `app_settings`: schema version, shortcut, model, language, privacy toggles, retention.
- `local_profile`: display name, role, industry, writing preferences.
- `dictionary_terms`: canonical term, aliases, category, source, confidence, uses, timestamps.
- `correction_candidates`: before/after token, source session, similarity, status, created/decided timestamps.
- `dictation_sessions`: timestamp, duration, word count, WPM, language confidence, app bundle ID only if opted in, accepted correction count; raw text optional and off by default.
- `daily_aggregates`: date, sessions, words, seconds, corrections, WPM samples.
- `onboarding_state`: version, completed cards, permission test results.

Security and controls:

- App Sandbox container only for Store edition.
- File protection/permissions and Keychain-backed encryption key if retaining correction candidates or transcript history.
- No analytics endpoint, crash upload, remote profile, team sync, or cloud database.
- Export all user data to a local file; erase all data with a confirmation and verification read-back.
- Add a database migration test for every schema change.

## Native Mac architecture

- SwiftUI for the dashboard, settings, onboarding, dictionary, and insights.
- AppKit `NSStatusItem` for the menu-bar waveform/status control.
- `LSUIElement = false` so the application appears in the Dock and has a normal app lifecycle/window.
- `AVAudioEngine` for low-latency recording, level meter, and interruption handling.
- Native/bridged `whisper.cpp` for local transcription and language identification.
- Carbon `RegisterEventHotKey` or another Store-review-compatible normal shortcut mechanism for push-to-talk.
- Clipboard-first output for the sandboxed edition; automatic cross-app paste remains a separate capability gate.
- Swift Charts for the local Insights views.
- SwiftData/Core Data or a reviewed SQLite layer for persistence.
- No Python runtime, Homebrew dependency, shell bootstrap, runtime `pip`, downloaded executable, self-updater, or hidden daemon in the Store target.

## Feedback capture

Add a small **Send feedback** entry under Help/About, but keep it privacy-safe:

- First create a local draft containing app version, model version, OS/architecture, and the user’s typed note.
- Do not attach transcripts or audio by default.
- Let the user inspect the draft and explicitly choose whether to open GitHub Discussions/issues or an email draft.
- Never silently upload diagnostics or usage data.

## Delivery phases

### Phase 0 — Product contract and feasibility

- Confirm the Direct versus Mac App Store feature matrix.
- Measure English language-gate options and native Whisper latency.
- Decide whether App Store edition output is clipboard-first or has a narrowly justified paste permission.
- Prototype the Dock/window/menu-bar lifecycle and permission read-back.

**Exit gate:** a 10-minute local dictation loop works with no network and the Store permission path is understood.

### Phase 1 — Native shell and onboarding

- Create the Swift native app target and AppKit/SwiftUI lifecycle.
- Add Dock presence, menu-bar item, main dashboard window, navigation, and versioned onboarding.
- Implement microphone device selection, shortcut recording, permission prompts, and test states.

**Exit gate:** a clean install reaches the first successful local dictation without a cloud key.

### Phase 2 — Local speech pipeline

- Integrate pinned whisper.cpp runtime.
- Add AVAudioEngine capture, VAD/recording lifecycle, English gate, transcription, model verification, and temporary-audio deletion.
- Add observable status states and failure recovery.

**Exit gate:** English fixtures pass, unsupported-language fixtures are rejected, and network-blocked tests still pass.

### Phase 3 — Profile, dictionary, and learning

- Migrate profile/dictionary semantics from `profile.py` and `dictionary.py`.
- Implement Add/Edit/Delete/Import/Export.
- Port the correction diff algorithm from `learner.py`, add candidate review, confidence/count thresholds, secure-field/app exclusions, and undo.

**Exit gate:** a user correction can become an accepted local rule, is applied on the next dictation, and can be erased completely.

### Phase 4 — Local Insights

- Replace the current cumulative `stats.py` counters with time-series aggregates.
- Add Home summary, Insights cards, correction breakdown, heatmap/streak, and optional app breakdown.
- Add empty states, calculation tooltips, retention controls, and export/erase.

**Exit gate:** every displayed metric is derived from real fixture data and no content is required to render the dashboard.

### Phase 5 — Direct-edition parity

- Preserve Right Command, automatic paste, selected-text context, optional LLM cleanup, overlay, and Accessibility-powered correction observation in the Direct target.
- Share domain logic and tests with the native app where safe; do not share unsandboxed dependencies into the Store target.

**Exit gate:** the existing direct DMG test suite and smoke flow remain green.

### Phase 6 — Mac App Store readiness

- Enable App Sandbox and microphone entitlement only for the Store target.
- Remove network/self-update/cloud features from the Store build unless separately reviewed.
- Create privacy manifest, privacy labels, support/privacy URLs, screenshots, review notes, signing/provisioning, archive validation, and clean-machine QA.
- Submit only after account-holder review of seller name, data declarations, and final permissions.

**Exit gate:** a signed archive installs on a clean Mac, passes offline dictation/erase/permission tests, and App Store Connect reports a valid build.

## Test strategy

### Unit tests

- English language-gate thresholds and silence/noise handling.
- Token diff: substitutions learned; insertions/deletions/content rewrites rejected.
- Names and multi-word terms preserved exactly.
- Dictionary precedence, aliases, confidence decay, undo, and deletion.
- Profile schema validation and migration.
- Analytics calculations: WPM, words, time saved, correction rate, streaks, date ranges.
- Database migrations, export/import, retention, and erase-all.
- Onboarding state and permission-state transitions.

### Integration tests

- Microphone permission denied/granted/revoked.
- Shortcut press/release and conflict handling.
- Offline transcription with network disabled.
- Model checksum failure and recovery.
- Clipboard output and no transcript persistence by default.
- Direct edition Accessibility watcher stops on app switch/timeout and excludes secure fields.

### UI tests

- First-run four-card onboarding at small and large Mac window sizes.
- Dock launch opens the main window; menu-bar item remains available.
- Dictionary candidate acceptance/rejection/undo.
- Insights empty state, real fixture state, date filters, and erase controls.
- Settings permission read-back and “Open System Settings” recovery path.
- VoiceOver labels, keyboard navigation, reduced motion, and dark/light appearance.

### Privacy/security checks

- Static scan for network clients, URL sessions, telemetry SDKs, hidden uploads, and secrets in the Store target.
- Runtime network denial test.
- Inspect entitlements for Sandbox/audio only.
- Verify no audio/transcript files remain after a default dictation.
- Verify erase-all removes database, model-independent user data, and Keychain entry.

## Acceptance criteria for the first proper native release

- The app appears in the Dock and opens a real dashboard window while retaining a menu-bar control.
- A new user completes onboarding in under two minutes and successfully dictates without an API key.
- English audio transcribes locally; unsupported-language audio is clearly rejected and discarded.
- A user can create a profile and add important names/terms locally.
- A user correction creates a visible candidate and only becomes a rule after acceptance.
- The next dictation uses the accepted spelling.
- Insights show real local metrics with honest empty states and no remote analytics.
- The user can inspect, export, disable, and erase all local data.
- Direct and Mac App Store builds have explicit, tested capability differences.
- No claim of App Store readiness is made until the signed archive and clean-machine permission flow are exercised.

## Open decisions to resolve before implementation

1. **Automatic paste:** preserve only in Direct, or pursue a separate sandbox/Accessibility feasibility spike for the Store build. Recommended default: Direct-only initially.
2. **Transcript history:** default off. Recommended default: retain aggregates and dictionary rules, delete raw text/audio after processing.
3. **Language gate model:** select based on measured false-accept/false-reject rates on Apple silicon, not only package size.
4. **Local profile depth:** start with name, role, important terms, and writing preferences; avoid collecting unnecessary personal biography.
5. **Cloud cleanup:** keep it in Direct; if desired later, add a separately consented local model rather than silently reintroducing a network dependency into the Store build.
6. **Seller identity:** the existing Apple Individual membership will display the account holder’s legal name. Convert to Organization only if the public seller name must be Shimoverse Studios/SJ Arts LLC.

## Source files to preserve or migrate

- `voiceflow/profile.py` → local profile schema and migration fixtures.
- `voiceflow/dictionary.py` → term/alias semantics and CRUD tests.
- `voiceflow/learner.py` → candidate-diff algorithm, with stronger consent and privacy boundaries.
- `voiceflow/stats.py` → metric definitions, replaced by daily aggregates.
- `voiceflow/onboarding.py` → behavior requirements only; replace Tk UI.
- `voiceflow/recorder.py`, `transcriber.py`, `streamer.py` → audio/model behavior; replace subprocess/runtime packaging in native target.
- `voiceflow/context.py`, `clipboard.py`, `system.py` → Direct-edition context/paste behavior; do not assume Store compatibility.
- `docs/ARCHITECTURE.md`, `PRIVACY.md`, `docs/COMPLIANCE.md`, `docs/THREAT_MODEL.md` → update after the native data model and distribution split are settled.

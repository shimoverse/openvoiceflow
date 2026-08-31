# History feedback, app identities, and leaderboard reliability

Date: 2026-08-30
Status: approved for specification

## Outcome

OpenVoiceFlow should make a successful History copy action obvious, show a recognizable icon anywhere the dashboard names a destination app, and reliably place every opted-in installation on the leaderboard under that installation's chosen nickname.

Each installation remains independent. There is no login, account, cross-device linking, or aggregation by nickname. Three Macs with three nicknames produce three leaderboard rows and retain three separate anonymous device IDs.

## Current problems

1. History's `Copy` button writes to the pasteboard but never acknowledges success.
2. The dashboard resolves installed app icons, but only Discord and Gmail have bundled fallbacks. Seeded Personalize entries such as Notion and Outlook therefore fall back to initials when their apps are not installed or cannot be resolved.
3. Home's Recent list and the full History list display app-name text without the icon used elsewhere.
4. Changing a leaderboard nickname only changes the local identity file. The server receives it after a later dictation sync, so the visible leaderboard can retain the old name.
5. The production leaderboard endpoint currently responds with HTTP 500. The app converts that failure into the ambiguous `No standings yet` state.

## Product behavior

### Copy acknowledgement

- A History row starts with the action label `Copy`.
- After the pasteboard accepts the row text, that row changes to `✓ Copied`.
- The acknowledgement returns to `Copy` automatically after approximately 1.5 seconds.
- Copying a second row moves the acknowledgement to the second row; stale timer work must not reset a newer acknowledgement.
- The copy action remains keyboard accessible and exposes the changed label to VoiceOver.

### App identity labels

- A reusable app-identity view owns the icon-plus-name presentation.
- It is used in all dashboard surfaces that name a dictated-into app: Home's `Where you dictate`, Home's `Recent`, History, and Personalize's Styles list.
- Resolution order is:
  1. exact running application icon;
  2. installed application resolved by known bundle ID or display name;
  3. bundled brand fallback for a known seeded service;
  4. a neutral application glyph for an unknown value.
- User-facing rows no longer use letter monograms for known seeded apps.
- The complete seeded style set is covered: Visual Studio Code, Xcode, PyCharm, Zed, Terminal, iTerm2, Sublime Text, Nova, Mail, Gmail, Outlook, Superhuman, Slack, Discord, Messages, WhatsApp, Telegram, Signal, Microsoft Word, Pages, Notion, Safari, and Google Chrome.
- Bundled assets are identification-only, include accessible app names in the surrounding UI, and record their sources and trademark status in `native/Resources/BrandIcons/README.md`.

### Leaderboard identity and sync

- `deviceId` remains the server primary key and continues to represent one installation.
- Nicknames are never used as identifiers or merge keys. Duplicate nicknames are allowed and remain separate rows.
- When nickname editing is committed by Return or focus loss, the app trims and validates the value, persists it locally, sends the installation's existing aggregate counters immediately, then refreshes the standings after a successful sync.
- The app does not send a request for each keystroke.
- Dictation text, audio, snippets, dictionary content, and Know-Me profile data remain local.
- Turning sharing off continues to stop leaderboard requests. Deleting leaderboard data continues to delete only the current installation's row.

### Failure states

- The analytics client exposes separate loading and error states for syncing and fetching.
- A failed leaderboard fetch shows a plain-language message and a `Try again` action. It must not say there are no standings.
- A failed nickname sync preserves the locally entered nickname and explains that the leaderboard has not updated yet; retrying does not require retyping it.
- API handlers return a service-unavailable response when database configuration is absent, while logging the detailed server-only cause. They never expose credentials or connection strings.

## Server and database recovery

The existing one-row-per-device PostgreSQL model matches the product requirement and remains in place. Recovery work will:

1. add executable API contract tests for request validation, row shaping, duplicate nicknames, and database failures;
2. replace or adapt the deprecated Vercel Postgres client to the database integration currently attached to the production project;
3. keep schema creation idempotent and retain existing device rows;
4. inspect authenticated Vercel runtime logs and environment-variable names without printing values;
5. attach or repair the production database integration if it is missing;
6. verify the deployed public endpoint returns a successful leaderboard payload.

No production rows will be invented or manually inflated. Existing installations will republish their real local aggregate totals when they next sync or when their nickname is committed.

## Components and files

| Component | Responsibility | Expected files |
|---|---|---|
| Copy feedback state | Track the acknowledged History row and dismiss it safely | `DashboardView.swift`, focused native contract tests |
| App identity renderer | Resolve and render installed or bundled app icons consistently | `AppIconProvider.swift`, `DashboardView.swift` |
| Brand resources | Cover every seeded Personalize app and document provenance | `native/Resources/BrandIcons/*`, `README.md`, `native/project.yml` if needed |
| Analytics client | Commit nickname changes, sync immediately, refresh, expose errors | `AnalyticsStore.swift`, `DashboardView.swift` |
| Leaderboard API | Preserve per-install rows and return actionable failures | `api/_db.js`, `api/analytics/ingest.js`, `api/leaderboard.js` |
| Database contract | Keep one row per `device_id`; duplicate display names permitted | `db/schema.sql` and API tests |
| Privacy/docs | Describe immediate nickname sync and per-install identity accurately | `PRIVACY.md`, generated docs source, affected public docs |

## Testing and verification

Implementation follows red-green-refactor for each behavior.

- Native source/Swift harness tests cover copy acknowledgement state, app-logo coverage, no-monogram known-app fallback, nickname commit behavior, refresh after successful sync, and visible failure/retry states.
- API tests exercise handlers against a controllable database adapter without a live production database.
- The full Python suite must remain green.
- `npm` tests or the repository's added API-test command must pass.
- The native app must compile through the repository's Xcode build gate.
- A local visual pass checks History, Recent, Where You Dictate, and Personalize in light and dark appearances.
- After PR checks pass and the change is squash-merged, production verification checks the public leaderboard endpoint and confirms the latest `origin/main` SHA.
- A real installation must remain the source of leaderboard totals; production verification will not upload fabricated usage data.

## Delivery and repository safety

The original checkout has unrelated local commits, deletions, and a history that no longer shares a merge base with the force-updated GitHub `main`. It will not be reset, stashed, or overwritten. Work proceeds in an isolated worktree on `codex/history-logos-leaderboard`, created directly from the fetched `origin/main`, through PR, green CI, squash merge, and production verification.

## Non-goals

- No user account or login.
- No cross-device linking or aggregation.
- No merge-by-nickname behavior.
- No dictated text, audio, or personal profile sync.
- No fabricated leaderboard rows or usage totals.
- No unrelated redesign of the dashboard.

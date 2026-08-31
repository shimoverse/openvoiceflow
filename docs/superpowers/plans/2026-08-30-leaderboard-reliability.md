# Leaderboard Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the production leaderboard and make each installation's committed nickname and real local totals appear promptly with honest error states.

**Architecture:** API handlers depend on a small database interface, enabling in-memory contract tests while the production adapter uses the Neon serverless PostgreSQL driver. The native analytics client validates HTTP results, publishes fetch/sync errors, and commits nicknames only on Return or focus loss before refreshing standings.

**Tech Stack:** Swift 5.10, SwiftUI, Foundation URLSession, Node.js built-in test runner, Vercel Functions, Neon PostgreSQL.

**Spec:** `docs/superpowers/specs/2026-08-30-history-app-logos-leaderboard-reliability-design.md`

## Global Constraints

- `deviceId` remains the primary key and represents exactly one installation.
- Duplicate nicknames are allowed and never merge rows.
- No login or cross-device linking is added.
- Only aggregate counters and the chosen nickname leave the Mac; never text, audio, snippets, dictionary entries, or profile data.
- Missing database configuration produces HTTP 503 without exposing secrets.
- Production verification must use real installation data, never fabricated totals.

---

### Task 1: Testable per-install API and supported database driver

**Files:**
- Create: `api/__tests__/leaderboard.test.js`
- Create: `api/__tests__/memory-database.js`
- Modify: `api/_db.js`
- Modify: `api/analytics/ingest.js`
- Modify: `api/leaderboard.js`
- Modify: `package.json`
- Create: `package-lock.json`

**Interfaces:**
- Produces from `_db.js`: `databaseUrl(env)`, `ensureSchema()`, `upsertDevice(device)`, `deleteDevice(deviceId)`, `readLeaderboard(deviceId, limit)`
- Produces from handlers: `createIngestHandler(database)` and `createLeaderboardHandler(database)`
- The in-memory database implements the same five methods and stores rows by `deviceId`.

- [ ] **Step 1: Write failing end-to-end handler tests**

Use request/response harness objects and one in-memory database to call real handlers. Required literal behaviors:

```javascript
await post({ deviceId: ID_A, displayName: "Desk", wordsTotal: 900, minutesSaved: 6 });
await post({ deviceId: ID_B, displayName: "Desk", wordsTotal: 1800, minutesSaved: 12 });
const board = await get({ deviceId: ID_A });
assert.equal(board.top.length, 2);
assert.deepEqual(board.top.map((row) => row.displayName), ["Desk", "Desk"]);
assert.equal(board.you.minutesSaved, 6);

await post({ deviceId: ID_A, displayName: "MacMini", wordsTotal: 900, minutesSaved: 6 });
const renamed = await get({ deviceId: ID_A });
assert.equal(renamed.you.displayName, "MacMini");
assert.equal(memory.rows.size, 2);
```

Also assert invalid UUID/name returns 400 and a database throwing `DatabaseUnavailableError` returns 503 `{ error: "service unavailable" }`.

- [ ] **Step 2: Run API tests and verify RED**

Run: `node --test api/__tests__/leaderboard.test.js`

Expected: FAIL because handler factories and database functions do not exist.

- [ ] **Step 3: Implement handler factories and database adapter**

Move SQL into `_db.js`. `databaseUrl` accepts `DATABASE_URL`, then `POSTGRES_URL`, then `POSTGRES_URL_NON_POOLING`; absence throws `DatabaseUnavailableError`. Use `@neondatabase/serverless@^0.10.4`, which supports the project's Node 18 floor, and remove deprecated `@vercel/postgres`.

`readLeaderboard` must rank rows by `minutes_saved DESC`, return the top ten plus the requesting device, and shape numeric ranks before the handler serializes them. `upsertDevice` retains `ON CONFLICT (device_id)` so a rename updates only that installation.

- [ ] **Step 4: Add scripts and verify GREEN**

Set `"test:api": "node --test api/__tests__/*.test.js"`. Run:

```bash
npm install --ignore-scripts
npm run test:api
npm run build
```

Expected: API tests PASS and the Vercel static build completes.

- [ ] **Step 5: Commit**

```bash
git add api package.json package-lock.json
git commit -m "fix(api): restore per-install leaderboard storage"
```

### Task 2: Native nickname commit and actionable error states

**Files:**
- Create: `native/Sources/OpenVoiceFlow/LeaderboardDisplayName.swift`
- Modify: `native/Sources/OpenVoiceFlow/AnalyticsStore.swift`
- Modify: `native/Sources/OpenVoiceFlow/DashboardView.swift:617-690,1017-1034,1230-1250`
- Create: `tests/test_native_leaderboard_reliability.py`

**Interfaces:**
- Produces: `AnalyticsIdentityStore.normalizedDisplayName(_:) -> String?`
- Produces: `@Published private(set) var leaderboardError: String?`
- Produces: `@Published private(set) var syncError: String?`
- Produces: `@discardableResult func syncNow(controller: AppController) async -> Bool`
- Produces: `func commitLeaderboardName()` in `DashboardView`

- [ ] **Step 1: Write failing normalization and UI-flow tests**

Compile a pure Swift normalization helper with literal assertions:

```swift
precondition(LeaderboardDisplayName.normalize("  Mac Mini  ") == "Mac Mini")
precondition(LeaderboardDisplayName.normalize("A\nB") == "AB")
precondition(LeaderboardDisplayName.normalize("   ") == nil)
precondition(LeaderboardDisplayName.normalize(String(repeating: "x", count: 45))?.count == 40)
```

Add a dashboard contract that requires a draft field, `.onSubmit`, focus-loss commit, `syncNow`, refresh after success, `Try again`, `leaderboardError`, and `syncError`. It must reject a direct binding that uploads every keystroke.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `python3 -m pytest tests/test_native_leaderboard_reliability.py -q`

Expected: FAIL because normalization and error/commit behavior are missing.

- [ ] **Step 3: Implement validation, transport results, and published errors**

Extract `LeaderboardDisplayName` to a Foundation-only source. Change sync to require a 2xx HTTP response; on error set `syncError` and return `false`. Change fetch to set/clear `leaderboardError` and reject malformed responses. Keep scheduled dictation sync throttled, but make committed nicknames call `syncNow` directly.

- [ ] **Step 4: Implement commit-on-submit/focus-loss UI**

Initialize a `leaderboardNameDraft` from the identity. `commitLeaderboardName` normalizes it, updates the local identity once, awaits `syncNow`, and calls `fetchLeaderboard` only after success. Add `Try again` to the leaderboard failure panel and show nickname sync failure below the field without discarding the draft.

- [ ] **Step 5: Verify native tests and compile**

Run:

```bash
python3 -m pytest tests/test_native_leaderboard_reliability.py -q
xcodebuild -project native/OpenVoiceFlow.xcodeproj -scheme OpenVoiceFlow -configuration Debug -derivedDataPath /tmp/openvoiceflow-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: tests PASS and `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add native/Sources/OpenVoiceFlow/AnalyticsStore.swift native/Sources/OpenVoiceFlow/LeaderboardDisplayName.swift native/Sources/OpenVoiceFlow/DashboardView.swift tests/test_native_leaderboard_reliability.py
git commit -m "fix(native): sync leaderboard names immediately"
```

### Task 3: Privacy documentation and full verification

**Files:**
- Modify: `PRIVACY.md`
- Modify: `scripts/docs_content.py`
- Regenerate: affected `docs/docs/*.html`, `docs/privacy.html`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes the shipped wire behavior from Tasks 1-2.
- Produces public copy stating one anonymous ID per installation and commit-time nickname sync.

- [ ] **Step 1: Update source-of-truth documentation**

State that duplicate nicknames remain separate, nickname edits send one aggregate update on Return/focus loss, and text/audio remain local. Add a changelog entry describing restored standings, honest errors, and independent installation rows.

- [ ] **Step 2: Regenerate and verify docs**

Run:

```bash
python3 scripts/build_docs.py
python3 -m pytest tests/test_docs_distribution.py tests/test_docs_seo.py -q
```

Expected: PASS.

- [ ] **Step 3: Run complete local gates**

Run:

```bash
npm run test:api
npm run build
python3 -m pytest -q
xcodebuild -project native/OpenVoiceFlow.xcodeproj -scheme OpenVoiceFlow -configuration Debug -derivedDataPath /tmp/openvoiceflow-derived CODE_SIGNING_ALLOWED=NO build
git diff --check
```

Expected: zero API failures, zero pytest failures, `BUILD SUCCEEDED`, and no whitespace errors.

- [ ] **Step 4: Commit**

```bash
git add PRIVACY.md CHANGELOG.md scripts/docs_content.py docs
git commit -m "docs: explain per-install leaderboard sync"
```

### Task 4: PR, production database recovery, and live proof

**Files:**
- No additional source files unless CI or production evidence exposes a defect.

**Interfaces:**
- Consumes: green local commits and the Vercel project connected to GitHub `main`.
- Produces: merged `origin/main`, deployed API, and successful public leaderboard response.

- [ ] **Step 1: Rebase on the latest remote and re-run affected gates**

Run `git fetch --all --prune --no-tags`, rebase onto `origin/main` only if needed, and rerun API, pytest, and Xcode gates after resolving any conflict.

- [ ] **Step 2: Push and open a PR**

Push `codex/history-logos-leaderboard`, open a PR describing privacy boundaries and verification, and wait for every required check.

- [ ] **Step 3: Inspect production configuration safely**

Use authenticated Vercel access to inspect runtime errors and environment-variable names only. Never print connection values. If the database integration is missing, attach a Neon PostgreSQL database to production and preview environments, then redeploy.

- [ ] **Step 4: Squash-merge and verify**

After green CI, squash-merge through GitHub, fetch `origin/main`, and verify:

```bash
curl --fail-with-body --silent --show-error https://openvoiceflow.com/api/leaderboard
```

Expected: HTTP 200 JSON containing a `top` array and nullable `you`, not HTTP 500/503.

- [ ] **Step 5: Verify real data flow**

Do not create test usage rows. Confirm the public response contains rows only after real opted-in installations sync. Report the final `origin/main` SHA and distinguish compile verification from on-device visual verification.

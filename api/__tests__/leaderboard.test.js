import assert from "node:assert/strict";
import { test } from "node:test";

import { DatabaseUnavailableError, databaseUrl } from "../_db.js";
import { createIngestHandler } from "../analytics/ingest.js";
import { createLeaderboardHandler } from "../leaderboard.js";
import { MemoryDatabase } from "./memory-database.js";

const ID_A = "00000000-0000-4000-8000-000000000001";
const ID_B = "00000000-0000-4000-8000-000000000002";

function responseRecorder() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    setHeader(name, value) {
      this.headers[name] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

async function call(handler, { method, body = {}, query = {}, headers = {} }) {
  const response = responseRecorder();
  await handler({ method, body, query, headers }, response);
  return response;
}

function usage(deviceId, displayName, wordsTotal, minutesSaved) {
  return {
    deviceId,
    displayName,
    wordsTotal,
    minutesSaved,
    streakDays: 3,
    featureUsage: {
      cleanupEnabled: true,
      snippetsCount: 2,
      dictionaryCount: 4,
      hasKnowMeProfile: false,
    },
    appVersion: "0.5.16",
    firstUseDate: "2026-08-20T12:00:00.000Z",
  };
}

test("database configuration accepts current and migrated Vercel variable names", () => {
  assert.equal(databaseUrl({ DATABASE_URL: "postgres://current" }), "postgres://current");
  assert.equal(databaseUrl({ POSTGRES_URL: "postgres://migrated" }), "postgres://migrated");
  assert.equal(databaseUrl({ POSTGRES_URL_NON_POOLING: "postgres://legacy" }), "postgres://legacy");
  assert.throws(() => databaseUrl({}), DatabaseUnavailableError);
});

test("duplicate nicknames remain separate installations and one can be renamed", async () => {
  const database = new MemoryDatabase();
  const ingest = createIngestHandler(database);
  const leaderboard = createLeaderboardHandler(database);

  const first = await call(ingest, {
    method: "POST",
    body: usage(ID_A, "Desk", 900, 65),
  });
  const second = await call(ingest, {
    method: "POST",
    body: usage(ID_B, "Desk", 1800, 130),
  });
  assert.equal(first.statusCode, 200);
  assert.equal(second.statusCode, 200);

  const board = await call(leaderboard, { method: "GET", query: { deviceId: ID_A } });
  assert.equal(board.statusCode, 200);
  assert.equal(board.body.top.length, 2);
  assert.deepEqual(board.body.top.map((row) => row.displayName), ["Desk", "Desk"]);
  assert.equal(board.body.you.minutesSaved, 65);
  assert.equal(board.body.you.inTop, true);

  const rename = await call(ingest, {
    method: "POST",
    body: usage(ID_A, "MacMini", 900, 65),
  });
  assert.equal(rename.statusCode, 200);

  const renamed = await call(leaderboard, { method: "GET", query: { deviceId: ID_A } });
  assert.equal(renamed.body.you.displayName, "MacMini");
  assert.equal(database.rows.size, 2);
});

test("ingest rejects an invalid installation id and blank nickname", async () => {
  const ingest = createIngestHandler(new MemoryDatabase());

  const badId = await call(ingest, {
    method: "POST",
    body: usage("not-a-uuid", "Desk", 900, 6),
  });
  assert.equal(badId.statusCode, 400);
  assert.deepEqual(badId.body, { error: "deviceId must be a UUID" });

  const blankName = await call(ingest, {
    method: "POST",
    body: usage(ID_A, " \n\t ", 900, 6),
  });
  assert.equal(blankName.statusCode, 400);
  assert.deepEqual(blankName.body, { error: "displayName is required" });
});

test("legacy space-separated aliases are compacted, custom names are untouched", async () => {
  const database = new MemoryDatabase();
  const ingest = createIngestHandler(database);
  const leaderboard = createLeaderboardHandler(database);

  await call(ingest, { method: "POST", body: usage(ID_A, "Warm Comet 20", 900, 65) });
  await call(ingest, { method: "POST", body: usage(ID_B, "My Custom Name", 900, 65) });

  const board = await call(leaderboard, { method: "GET", query: {} });
  assert.deepEqual(
    board.body.top.map((row) => row.displayName).sort(),
    ["My Custom Name", "WarmComet20"]
  );
});

test("legacy compaction only fires within the native app's 10-99 range", async () => {
  const database = new MemoryDatabase();
  const ingest = createIngestHandler(database);
  const leaderboard = createLeaderboardHandler(database);

  // Swift's compactLegacyDefault only accepts (10...99); "09" falls outside
  // that range and must be preserved exactly like the native client does.
  await call(ingest, { method: "POST", body: usage(ID_A, "Warm Comet 09", 900, 65) });
  await call(ingest, { method: "POST", body: usage(ID_B, "Warm Comet 99", 900, 130) });

  const board = await call(leaderboard, { method: "GET", query: {} });
  const byName = Object.fromEntries(board.body.top.map((row) => [row.minutesSaved, row.displayName]));
  assert.equal(byName[65], "Warm Comet 09");
  assert.equal(byName[130], "WarmComet99");
});

test("public leaderboard hides rows under the usage bar, caps at five, but always returns you", async () => {
  const database = new MemoryDatabase();
  const ingest = createIngestHandler(database);
  const leaderboard = createLeaderboardHandler(database);

  const ids = Array.from({ length: 7 }, (_, i) => `00000000-0000-4000-8000-00000000001${i}`);
  // Six devices clear the one-hour bar (ranks 1-6), one does not.
  for (const [i, id] of ids.entries()) {
    await call(ingest, { method: "POST", body: usage(id, `Device${i}`, 900, i < 6 ? 600 - i : 5) });
  }

  const board = await call(leaderboard, { method: "GET", query: { deviceId: ids[6] } });
  assert.equal(board.body.top.length, 5);
  assert.ok(board.body.top.every((row) => row.minutesSaved >= 60));

  assert.equal(board.body.you.minutesSaved, 5);
  assert.equal(board.body.you.inTop, false);
});

test("database outages return service unavailable without leaking details", async () => {
  const database = {
    async ensureSchema() {
      throw new DatabaseUnavailableError("DATABASE_URL contained secret material");
    },
  };
  const leaderboard = createLeaderboardHandler(database);
  const logged = [];
  const originalConsoleError = console.error;
  console.error = (...values) => logged.push(values);
  let response;
  try {
    response = await call(leaderboard, { method: "GET" });
  } finally {
    console.error = originalConsoleError;
  }

  assert.equal(response.statusCode, 503);
  assert.deepEqual(response.body, { error: "service unavailable" });
  assert.equal(JSON.stringify(response.body).includes("DATABASE_URL"), false);
  const serializedLogs = JSON.stringify(logged);
  assert.equal(serializedLogs.includes("contained secret material"), false);
  assert.match(serializedLogs, /DatabaseUnavailableError/);
});

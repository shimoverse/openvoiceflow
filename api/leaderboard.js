import * as productionDatabase from "./_db.js";
import { compactLegacyDefault } from "./_leaderboardAlias.js";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TOP_N = 10;

/// Only reveal rows that have crossed a meaningful usage bar, capped at a
/// fixed size regardless of how many devices actually qualify — together
/// these keep the public endpoint from ever hinting at the real user count.
const REVEAL_MINUTES_SAVED = 60;
const MAX_VISIBLE_ROWS = 5;

function publicRow(row) {
  return {
    displayName: compactLegacyDefault(row.displayName),
    minutesSaved: row.minutesSaved,
    rank: row.rank,
  };
}

export function createLeaderboardHandler(database = productionDatabase) {
  return async function handler(req, res) {
    if (req.method !== "GET") {
      res.setHeader("Allow", "GET");
      return res.status(405).json({ error: "method not allowed" });
    }

    const deviceId = typeof req.query.deviceId === "string" ? req.query.deviceId.toLowerCase() : "";
    const requestingDeviceId = UUID_RE.test(deviceId) ? deviceId : null;

    try {
      await database.ensureSchema();
      const { top, you } = await database.readLeaderboard(requestingDeviceId, TOP_N);
      const visible = top
        .filter((row) => row.minutesSaved >= REVEAL_MINUTES_SAVED)
        .slice(0, MAX_VISIBLE_ROWS);
      const inTop = you !== null && visible.some((row) => row.deviceId === you.deviceId);
      return res.status(200).json({
        top: visible.map(publicRow),
        you: you ? { ...publicRow(you), inTop } : null,
      });
    } catch (error) {
      console.error("leaderboard query failed", productionDatabase.databaseErrorDetails(error));
      return res.status(503).json({ error: "service unavailable" });
    }
  };
}

export default createLeaderboardHandler();

import { neon } from "@neondatabase/serverless";

export class DatabaseUnavailableError extends Error {
  constructor(message) {
    super(message);
    this.name = "DatabaseUnavailableError";
  }
}

let sqlClient = null;
let schemaReady = null;

export function databaseUrl(env = process.env) {
  const value = env.DATABASE_URL || env.POSTGRES_URL || env.POSTGRES_URL_NON_POOLING;
  if (typeof value !== "string" || value.length === 0) {
    throw new DatabaseUnavailableError("No supported PostgreSQL connection variable is configured");
  }
  return value;
}

/// Keep runtime logs useful without echoing driver messages that may contain
/// connection URLs or credentials.
export function databaseErrorDetails(error) {
  const name = typeof error?.name === "string" ? error.name : "Error";
  const code = typeof error?.code === "string" && /^[A-Z0-9_]+$/.test(error.code)
    ? error.code
    : undefined;
  return code ? { name, code } : { name };
}

function sql() {
  if (!sqlClient) sqlClient = neon(databaseUrl());
  return sqlClient;
}

// Schema creation remains idempotent and retries after a failed cold start.
export async function ensureSchema() {
  if (!schemaReady) {
    schemaReady = (async () => {
      const query = sql();
      await query`
        CREATE TABLE IF NOT EXISTS devices (
          device_id       UUID PRIMARY KEY,
          display_name    TEXT NOT NULL,
          words_total     INTEGER NOT NULL DEFAULT 0,
          minutes_saved   INTEGER NOT NULL DEFAULT 0,
          streak_days     INTEGER NOT NULL DEFAULT 0,
          feature_usage   JSONB NOT NULL DEFAULT '{}'::jsonb,
          country         TEXT,
          app_version     TEXT,
          first_use_date  TIMESTAMPTZ,
          first_seen      TIMESTAMPTZ NOT NULL DEFAULT now(),
          last_seen       TIMESTAMPTZ NOT NULL DEFAULT now()
        )
      `;
      await query`
        CREATE INDEX IF NOT EXISTS devices_minutes_saved_idx ON devices (minutes_saved DESC)
      `;
    })();
  }
  try {
    await schemaReady;
  } catch (error) {
    schemaReady = null;
    throw error;
  }
}

export async function deleteDevice(deviceId) {
  await sql()`DELETE FROM devices WHERE device_id = ${deviceId}`;
}

export async function upsertDevice(device) {
  const query = sql();
  await query`
    INSERT INTO devices (
      device_id, display_name, words_total, minutes_saved, streak_days,
      feature_usage, country, app_version, first_use_date, first_seen, last_seen
    ) VALUES (
      ${device.deviceId}, ${device.displayName}, ${device.wordsTotal}, ${device.minutesSaved},
      ${device.streakDays}, ${JSON.stringify(device.featureUsage)}, ${device.country},
      ${device.appVersion}, ${device.firstUseDate}, now(), now()
    )
    ON CONFLICT (device_id) DO UPDATE SET
      display_name = EXCLUDED.display_name,
      words_total = EXCLUDED.words_total,
      minutes_saved = EXCLUDED.minutes_saved,
      streak_days = EXCLUDED.streak_days,
      feature_usage = EXCLUDED.feature_usage,
      country = COALESCE(EXCLUDED.country, devices.country),
      app_version = EXCLUDED.app_version,
      first_use_date = COALESCE(devices.first_use_date, EXCLUDED.first_use_date),
      last_seen = now()
  `;
}

function rowShape(row) {
  return {
    deviceId: row.device_id,
    displayName: row.display_name,
    minutesSaved: Number(row.minutes_saved),
    rank: Number(row.rank),
  };
}

export async function readLeaderboard(deviceId, limit) {
  const query = sql();
  const topRows = await query`
    SELECT device_id, display_name, minutes_saved,
           RANK() OVER (ORDER BY minutes_saved DESC) AS rank
    FROM devices
    ORDER BY minutes_saved DESC, device_id ASC
    LIMIT ${limit}
  `;

  let you = null;
  if (deviceId) {
    const rows = await query`
      WITH ranked AS (
        SELECT device_id, display_name, minutes_saved,
               RANK() OVER (ORDER BY minutes_saved DESC) AS rank
        FROM devices
      )
      SELECT device_id, display_name, minutes_saved, rank FROM ranked
      WHERE device_id = ${deviceId}
    `;
    if (rows.length > 0) you = rowShape(rows[0]);
  }

  return { top: topRows.map(rowShape), you };
}

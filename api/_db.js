import { sql } from "@vercel/postgres";

let schemaReady = null;

// Vercel Postgres connects lazily per-request; this makes sure the table
// exists before the first query in a cold start. Idempotent, so it's cheap
// to call on every invocation once the promise resolves.
export function ensureSchema() {
  if (!schemaReady) {
    schemaReady = sql`
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
    `.then(() => sql`
      CREATE INDEX IF NOT EXISTS devices_minutes_saved_idx ON devices (minutes_saved DESC)
    `);
  }
  return schemaReady;
}

export { sql };

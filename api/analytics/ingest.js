import { sql, ensureSchema } from "../_db.js";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_COUNTER = 100_000_000; // generous ceiling against garbage/overflow, not a real usage limit
const FEATURE_KEYS = ["cleanupEnabled", "snippetsCount", "dictionaryCount", "hasKnowMeProfile"];
const CONTROL_CHARS_RE = /[\x00-\x1F\x7F]/g;

function isNonNegInt(v) {
  return typeof v === "number" && Number.isFinite(v) && Number.isInteger(v) && v >= 0 && v <= MAX_COUNTER;
}

function sanitizeName(raw) {
  if (typeof raw !== "string") return null;
  // Strip control characters, collapse whitespace, cap length. Display
  // names are shown to other users on the leaderboard, so they're the one
  // field here that's genuinely public-facing.
  const cleaned = raw.replace(CONTROL_CHARS_RE, "").replace(/\s+/g, " ").trim().slice(0, 40);
  return cleaned.length > 0 ? cleaned : null;
}

function sanitizeFeatureUsage(raw) {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return {};
  const out = {};
  for (const key of FEATURE_KEYS) {
    const v = raw[key];
    if (typeof v === "boolean") out[key] = v;
    else if (isNonNegInt(v)) out[key] = v;
  }
  return out;
}

export default async function handler(req, res) {
  if (req.method === "DELETE") {
    // Right-to-erasure path: a device can always remove its own row. No
    // auth beyond knowing the device ID itself — the same bar as the app
    // reading it back out of its own Settings pane.
    const deviceId = typeof req.query.deviceId === "string" ? req.query.deviceId.toLowerCase() : "";
    if (!UUID_RE.test(deviceId)) {
      return res.status(400).json({ error: "deviceId must be a UUID" });
    }
    try {
      await ensureSchema();
      await sql`DELETE FROM devices WHERE device_id = ${deviceId}`;
      return res.status(200).json({ ok: true });
    } catch (err) {
      console.error("analytics delete failed", err);
      return res.status(500).json({ error: "internal error" });
    }
  }

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST, DELETE");
    return res.status(405).json({ error: "method not allowed" });
  }

  const body = req.body || {};
  const deviceId = typeof body.deviceId === "string" ? body.deviceId.toLowerCase() : "";
  if (!UUID_RE.test(deviceId)) {
    return res.status(400).json({ error: "deviceId must be a UUID" });
  }
  const displayName = sanitizeName(body.displayName);
  if (!displayName) {
    return res.status(400).json({ error: "displayName is required" });
  }
  const wordsTotal = isNonNegInt(body.wordsTotal) ? body.wordsTotal : 0;
  const minutesSaved = isNonNegInt(body.minutesSaved) ? body.minutesSaved : 0;
  const streakDays = isNonNegInt(body.streakDays) ? body.streakDays : 0;
  const featureUsage = sanitizeFeatureUsage(body.featureUsage);
  const appVersion = typeof body.appVersion === "string" ? body.appVersion.slice(0, 20) : null;
  const firstUseDate = typeof body.firstUseDate === "string" && !Number.isNaN(Date.parse(body.firstUseDate))
    ? new Date(body.firstUseDate)
    : null;

  // Vercel's edge attaches this geo header itself — no client-supplied
  // location, and no IP address is read or stored anywhere in this request.
  const country = typeof req.headers["x-vercel-ip-country"] === "string"
    ? req.headers["x-vercel-ip-country"].slice(0, 2)
    : null;

  try {
    await ensureSchema();
    await sql`
      INSERT INTO devices (
        device_id, display_name, words_total, minutes_saved, streak_days,
        feature_usage, country, app_version, first_use_date, first_seen, last_seen
      ) VALUES (
        ${deviceId}, ${displayName}, ${wordsTotal}, ${minutesSaved}, ${streakDays},
        ${JSON.stringify(featureUsage)}, ${country}, ${appVersion}, ${firstUseDate}, now(), now()
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
    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error("analytics ingest failed", err);
    return res.status(500).json({ error: "internal error" });
  }
}

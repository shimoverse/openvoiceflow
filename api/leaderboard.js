import { sql, ensureSchema } from "./_db.js";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TOP_N = 10;

// Returns the top N by minutes saved, plus the requesting device's own row
// and rank if it opted in and isn't already in the top N. Deliberately never
// returns how many devices exist in total — that's not something this
// endpoint discloses, in either direction.
export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "method not allowed" });
  }

  const deviceId = typeof req.query.deviceId === "string" ? req.query.deviceId.toLowerCase() : "";
  const hasDeviceId = UUID_RE.test(deviceId);

  try {
    await ensureSchema();

    const { rows: top } = await sql`
      SELECT device_id, display_name, minutes_saved,
             RANK() OVER (ORDER BY minutes_saved DESC) AS rank
      FROM devices
      ORDER BY minutes_saved DESC
      LIMIT ${TOP_N}
    `;

    let you = null;
    if (hasDeviceId) {
      const { rows } = await sql`
        WITH ranked AS (
          SELECT device_id, display_name, minutes_saved,
                 RANK() OVER (ORDER BY minutes_saved DESC) AS rank
          FROM devices
        )
        SELECT device_id, display_name, minutes_saved, rank FROM ranked
        WHERE device_id = ${deviceId}
      `;
      if (rows.length > 0) you = rows[0];
    }

    const shape = (r) => ({ displayName: r.display_name, minutesSaved: r.minutes_saved, rank: Number(r.rank) });
    const inTop = you && top.some((r) => r.device_id === you.device_id);

    return res.status(200).json({
      top: top.map(shape),
      you: you ? { ...shape(you), inTop: Boolean(inTop) } : null,
    });
  } catch (err) {
    console.error("leaderboard query failed", err);
    return res.status(500).json({ error: "internal error" });
  }
}

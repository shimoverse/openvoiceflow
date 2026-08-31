export class MemoryDatabase {
  constructor() {
    this.rows = new Map();
  }

  async ensureSchema() {}

  async upsertDevice(device) {
    const existing = this.rows.get(device.deviceId);
    this.rows.set(device.deviceId, {
      ...existing,
      ...device,
      firstUseDate: existing?.firstUseDate ?? device.firstUseDate,
    });
  }

  async deleteDevice(deviceId) {
    this.rows.delete(deviceId);
  }

  async readLeaderboard(deviceId, limit) {
    const ordered = [...this.rows.values()].sort((a, b) =>
      b.minutesSaved - a.minutesSaved || a.deviceId.localeCompare(b.deviceId)
    );
    let previousMinutes = null;
    let previousRank = 0;
    const ranked = ordered.map((row, index) => {
      const rank = row.minutesSaved === previousMinutes ? previousRank : index + 1;
      previousMinutes = row.minutesSaved;
      previousRank = rank;
      return { ...row, rank };
    });
    return {
      top: ranked.slice(0, limit),
      you: deviceId ? ranked.find((row) => row.deviceId === deviceId) ?? null : null,
    };
  }
}

const ADJECTIVES = new Set([
  "Quiet", "Swift", "Calm", "Bright", "Steady", "Clever", "Brisk", "Gentle",
  "Sunny", "Nimble", "Bold", "Sharp", "Warm", "Cool", "Vivid", "Keen",
]);
const NOUNS = new Set([
  "Falcon", "Otter", "Maple", "Comet", "Harbor", "Ember", "Willow", "Lynx",
  "Meadow", "Aspen", "Heron", "Cedar", "Ridge", "Sparrow", "Tundra", "Coral",
]);

/// Mirrors LeaderboardAlias.compactLegacyDefault (native/Sources/OpenVoiceFlow/LeaderboardAlias.swift).
/// Devices that haven't relaunched since the alias format changed still have
/// "Adjective Noun NN" stored server-side; compact it here so every viewer
/// sees the current no-space format regardless of which client wrote it.
/// User-chosen display names never match this exact shape, so they pass through untouched.
export function compactLegacyDefault(name) {
  const parts = name.split(" ");
  if (parts.length !== 3) return name;
  const [adjective, noun, numberText] = parts;
  if (!ADJECTIVES.has(adjective) || !NOUNS.has(noun)) return name;
  const number = Number(numberText);
  if (!/^\d{2}$/.test(numberText) || number < 10 || number > 99) return name;
  return `${adjective}${noun}${number}`;
}

import Foundation

/// A readable, anonymous leaderboard alias. Generated aliases are one token
/// so they scan like handles rather than accidental first-and-last names.
enum LeaderboardAlias {
    private static let adjectives = [
        "Quiet", "Swift", "Calm", "Bright", "Steady", "Clever", "Brisk", "Gentle",
        "Sunny", "Nimble", "Bold", "Sharp", "Warm", "Cool", "Vivid", "Keen",
    ]
    private static let nouns = [
        "Falcon", "Otter", "Maple", "Comet", "Harbor", "Ember", "Willow", "Lynx",
        "Meadow", "Aspen", "Heron", "Cedar", "Ridge", "Sparrow", "Tundra", "Coral",
    ]

    static func make(adjective: String, noun: String, number: Int) -> String {
        "\(adjective)\(noun)\(number)"
    }

    static func random() -> String {
        make(
            adjective: adjectives.randomElement()!,
            noun: nouns.randomElement()!,
            number: Int.random(in: 1000...9999)
        )
    }

    /// Compact only names that exactly match the app's old generated format.
    /// User-chosen display names keep their original spacing.
    static func compactLegacyDefault(_ name: String) -> String {
        let parts = name.components(separatedBy: " ")
        guard parts.count == 3,
              adjectives.contains(parts[0]),
              nouns.contains(parts[1]),
              let number = Int(parts[2]),
              (10...99).contains(number),
              String(number) == parts[2]
        else { return name }

        return make(adjective: parts[0], noun: parts[1], number: number)
    }
}

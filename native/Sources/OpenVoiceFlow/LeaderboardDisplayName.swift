import Foundation

/// Public leaderboard names use the same boundary as the server: remove
/// control characters, collapse whitespace, trim, and cap at 40 characters.
enum LeaderboardDisplayName {
    static func normalize(_ raw: String) -> String? {
        let scalars = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let collapsed = String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let limited = String(collapsed.prefix(40))
        return limited.isEmpty ? nil : limited
    }
}

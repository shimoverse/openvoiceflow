import AppKit
import Foundation

/// Local, on-device feature stores ported from the Python app's modules
/// (dictionary.py, snippets.py, styles.py, profile.py, plus transcript logging
/// and stats). Everything persists as JSON in Application Support/OpenVoiceFlow
/// — the same directory Settings uses — and never leaves the machine.
///
/// Each store is an `ObservableObject` so the dashboard panes react to edits,
/// and each exposes a `promptFragment` that the cleanup call injects so the
/// very first dictation already knows your name, jargon, and corrections.

// MARK: - shared JSON persistence

enum AppSupport {
    static var dir: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OpenVoiceFlow", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = dir.appending(path: name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: dir.appending(path: name), options: [.atomic, .completeFileProtection])
    }
}

// MARK: - Profile (profile.py)

struct Profile: Codable, Equatable {
    var name = ""
    var occupation = ""
    var industry = ""
    var workNames: [String] = []
    var homeNames: [String] = []
    var technicalTerms: [String] = []
    var communicationStyle = ""
    var additionalContext = ""

    var isEmpty: Bool {
        name.isEmpty && occupation.isEmpty && industry.isEmpty
            && workNames.isEmpty && homeNames.isEmpty && technicalTerms.isEmpty
            && communicationStyle.isEmpty && additionalContext.isEmpty
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profile: Profile { didSet { AppSupport.save(profile, to: "profile.json") } }

    init() { profile = AppSupport.load(Profile.self, from: "profile.json") ?? Profile() }

    var hasProfile: Bool { !profile.isEmpty }

    /// Rich system-prompt fragment (mirrors get_profile_prompt_fragment).
    var promptFragment: String {
        guard !profile.isEmpty else { return "" }
        var lines = ["\n\nPERSONAL CONTEXT —"]

        var intro: [String] = []
        if !profile.name.isEmpty { intro.append("The user's name is \(profile.name).") }
        if !profile.occupation.isEmpty {
            intro.append(profile.industry.isEmpty
                ? "They work as a \(profile.occupation)."
                : "They work as a \(profile.occupation) (\(profile.industry) industry).")
        } else if !profile.industry.isEmpty {
            intro.append("They work in the \(profile.industry) industry.")
        }
        if !intro.isEmpty { lines.append(intro.joined(separator: " ")) }

        if !profile.workNames.isEmpty || !profile.homeNames.isEmpty {
            lines.append("Names they frequently mention:")
            if !profile.workNames.isEmpty { lines.append("  - Work: \(profile.workNames.joined(separator: ", "))") }
            if !profile.homeNames.isEmpty { lines.append("  - Home: \(profile.homeNames.joined(separator: ", "))") }
        }
        if !profile.technicalTerms.isEmpty {
            lines.append("Technical terms to spell correctly: \(profile.technicalTerms.joined(separator: ", "))")
        }
        if !profile.communicationStyle.isEmpty {
            lines.append("Communication style preference: \(profile.communicationStyle)")
        }
        if !profile.additionalContext.isEmpty {
            lines.append("Additional context: \(profile.additionalContext)")
        }
        lines.append("Always use these exact name spellings. When in doubt about a word, consider the user's industry and role for context.")
        return lines.joined(separator: "\n")
    }

    /// Names + terms to seed the dictionary (mirrors profile_to_dictionary).
    var dictionaryWords: [String] {
        var words: [String] = []
        for w in profile.workNames + profile.homeNames + profile.technicalTerms where !words.contains(w) {
            words.append(w)
        }
        for part in profile.name.split(separator: " ").map(String.init) where !part.isEmpty && !words.contains(part) {
            words.append(part)
        }
        return words
    }
}

// MARK: - Dictionary (dictionary.py)

struct DictionaryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var word: String
    var aliases: [String] = []

    enum CodingKeys: String, CodingKey { case word, aliases }
}

@MainActor
final class DictionaryStore: ObservableObject {
    @Published private(set) var entries: [DictionaryEntry] { didSet { AppSupport.save(entries, to: "dictionary.json") } }

    init() { entries = AppSupport.load([DictionaryEntry].self, from: "dictionary.json") ?? [] }

    func add(word: String, aliases: [String] = []) {
        let word = word.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        if let i = entries.firstIndex(where: { $0.word.lowercased() == word.lowercased() }) {
            entries[i].aliases = Array(Set(entries[i].aliases + aliases)).sorted()
        } else {
            entries.append(DictionaryEntry(word: word, aliases: aliases))
        }
    }

    func remove(_ entry: DictionaryEntry) { entries.removeAll { $0.id == entry.id } }

    /// Seed from the profile without clobbering user edits.
    func seed(with words: [String]) {
        for w in words where !entries.contains(where: { $0.word.lowercased() == w.lowercased() }) {
            entries.append(DictionaryEntry(word: w))
        }
    }

    var promptFragment: String {
        guard !entries.isEmpty else { return "" }
        let lines = entries.map { e -> String in
            e.aliases.isEmpty
                ? "  - \"\(e.word)\""
                : "  - \"\(e.word)\" (may be misheard as: \(e.aliases.joined(separator: ", ")))"
        }
        return "\n\nIMPORTANT — Personal dictionary. Always use these exact spellings:\n" + lines.joined(separator: "\n")
    }
}

// MARK: - Snippets (snippets.py)

struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: String
    var expansion: String

    enum CodingKeys: String, CodingKey { case trigger, expansion }
}

@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet] { didSet { AppSupport.save(snippets, to: "snippets.json") } }

    init() { snippets = AppSupport.load([Snippet].self, from: "snippets.json") ?? [] }

    func add(trigger: String, expansion: String) {
        let key = trigger.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        if let i = snippets.firstIndex(where: { $0.trigger == key }) {
            snippets[i].expansion = expansion
        } else {
            snippets.append(Snippet(trigger: key, expansion: expansion))
        }
    }

    func remove(_ snippet: Snippet) { snippets.removeAll { $0.id == snippet.id } }

    /// Exact, or trigger followed by a word break (mirrors match_snippet).
    func match(_ text: String) -> String? {
        guard !snippets.isEmpty else { return nil }
        let normalized = text.lowercased().trimmingCharacters(in: .whitespaces)
        if let exact = snippets.first(where: { $0.trigger == normalized }) { return exact.expansion }
        for s in snippets.sorted(by: { $0.trigger.count > $1.trigger.count }) where normalized.hasPrefix(s.trigger) {
            let rest = normalized.dropFirst(s.trigger.count)
            if rest.first.map({ !$0.isLetter && !$0.isNumber }) ?? true { return s.expansion }
        }
        return nil
    }
}

// MARK: - Per-app styles (styles.py + config default map)

@MainActor
final class StyleStore: ObservableObject {
    /// App display name → style id. Seeded with the Python defaults; editable.
    @Published var map: [String: String] { didSet { AppSupport.save(map, to: "styles.json") } }

    init() { map = AppSupport.load([String: String].self, from: "styles.json") ?? Self.defaults }

    static let defaults: [String: String] = [
        "Visual Studio Code": "code", "Xcode": "code", "PyCharm": "code", "Zed": "code", "Terminal": "code",
        "iTerm2": "code", "Sublime Text": "code", "Nova": "code",
        "Mail": "email", "Gmail": "email", "Outlook": "email", "Superhuman": "email",
        "Slack": "casual", "Discord": "casual", "Messages": "casual", "WhatsApp": "casual",
        "Telegram": "casual", "Signal": "casual",
        "Microsoft Word": "default", "Pages": "default", "Notion": "default",
        "Safari": "default", "Google Chrome": "default",
    ]

    /// The style for the app the user is dictating into (frontmost app).
    func styleForFrontmostApp(fallback: Settings.Style) -> Settings.Style {
        guard let app = NSWorkspace.shared.frontmostApplication?.localizedName,
              let id = map[app],
              let style = Settings.Style(rawValue: id) else { return fallback }
        return style
    }
}

// MARK: - History + stats (log_transcript + stats)

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var timestamp: Date
    var app: String
    var text: String
    var words: Int
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] { didSet { AppSupport.save(entries, to: "history.json") } }
    /// Persisted daily word totals keyed by yyyy-MM-dd (for the week chart + streak).
    @Published private(set) var dailyWords: [String: Int] { didSet { AppSupport.save(dailyWords, to: "stats.json") } }

    private static let maxEntries = 500

    init() {
        entries = AppSupport.load([HistoryEntry].self, from: "history.json") ?? []
        dailyWords = AppSupport.load([String: Int].self, from: "stats.json") ?? [:]
    }

    func record(app: String, text: String, words: Int, now: Date = Date()) {
        entries.insert(HistoryEntry(timestamp: now, app: app, text: text, words: words), at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
        dailyWords[Self.key(now), default: 0] += words
    }

    func clearAll() { entries = []; dailyWords = [:] }

    // Stats derived from dailyWords.
    var wordsToday: Int { dailyWords[Self.key(Date())] ?? 0 }
    var totalWords: Int { dailyWords.values.reduce(0, +) }

    /// Consecutive days up to today with at least one word.
    var streak: Int {
        var count = 0
        var day = Date()
        while (dailyWords[Self.key(day)] ?? 0) > 0 {
            count += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    /// Last 7 days Mon…Sun-style, oldest first, for the Home chart.
    var lastWeek: [Int] {
        (0..<7).reversed().map { offset in
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            return dailyWords[Self.key(day)] ?? 0
        }
    }

    private static func key(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

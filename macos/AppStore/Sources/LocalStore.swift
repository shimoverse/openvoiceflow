import Combine
import Foundation

struct LocalProfile: Codable {
    var displayName = ""
    var role = ""
}

struct DictionaryTerm: Codable, Identifiable, Hashable {
    let id: UUID
    var word: String
    var aliases: [String]
    var source: String
    var uses: Int
}

struct LocalUsage: Codable {
    var sessions = 0
    var words = 0
    var seconds = 0.0
    var corrections = 0
    var activeDays: Set<String> = []

    var wordsPerMinute: Int {
        guard seconds > 0 else { return 0 }
        return Int((Double(words) / seconds) * 60)
    }
}

private struct LocalStorePayload: Codable {
    var onboardingComplete = false
    var profile = LocalProfile()
    var dictionary: [DictionaryTerm] = []
    var usage = LocalUsage()
}

@MainActor
final class LocalStore: ObservableObject {
    static let shared = LocalStore()

    @Published private(set) var onboardingComplete = false
    @Published private(set) var profile = LocalProfile()
    @Published private(set) var dictionary: [DictionaryTerm] = []
    @Published private(set) var usage = LocalUsage()

    private let storeURL: URL

    private init() {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ))?.appendingPathComponent("OpenVoiceFlow", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            storeURL = directory.appendingPathComponent("local-store.json")
        } else {
            storeURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("openvoiceflow-local-store.json")
        }
        load()
    }

    func completeOnboarding() {
        onboardingComplete = true
        persist()
    }

    func updateProfile(name: String, role: String) {
        profile = LocalProfile(displayName: name.trimmingCharacters(in: .whitespacesAndNewlines), role: role.trimmingCharacters(in: .whitespacesAndNewlines))
        persist()
    }

    func addTerm(_ word: String) {
        let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !dictionary.contains(where: { $0.word.caseInsensitiveCompare(cleaned) == .orderedSame }) else { return }
        dictionary.append(DictionaryTerm(id: UUID(), word: cleaned, aliases: [], source: "Manual", uses: 0))
        dictionary.sort { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        persist()
    }

    func deleteTerms(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            dictionary.remove(at: index)
        }
        persist()
    }

    func recordDictation(text: String, duration: TimeInterval) {
        usage.sessions += 1
        usage.words += text.split(whereSeparator: { $0.isWhitespace }).count
        usage.seconds += duration
        usage.activeDays.insert(Self.dayFormatter.string(from: Date()))
        persist()
    }

    func clearLocalData() {
        onboardingComplete = false
        profile = LocalProfile()
        dictionary = []
        usage = LocalUsage()
        try? FileManager.default.removeItem(at: storeURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL), let payload = try? JSONDecoder().decode(LocalStorePayload.self, from: data) else { return }
        onboardingComplete = payload.onboardingComplete
        profile = payload.profile
        dictionary = payload.dictionary
        usage = payload.usage
    }

    private func persist() {
        let payload = LocalStorePayload(onboardingComplete: onboardingComplete, profile: profile, dictionary: dictionary, usage: usage)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

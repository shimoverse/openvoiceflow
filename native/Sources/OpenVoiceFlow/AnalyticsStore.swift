import Foundation

/// Opt-out anonymous usage sharing + leaderboard.
///
/// On by default (Settings ▸ Privacy ▸ "Share anonymous usage & leaderboard
/// rank"), turning it off stops every network call this file makes. What's
/// sent is a handful of aggregate counters this app already shows on the
/// Home pane — total words, minutes saved, streak, which features are in
/// use — tagged with a random device ID and a display name the user can
/// change. Never dictation text, snippets, dictionary entries, or the
/// Know-Me profile. See the Analytics & leaderboard section of the privacy
/// docs for the exact wire format.

// MARK: - Identity

struct AnalyticsIdentity: Codable, Equatable {
    var deviceId: String
    var displayName: String
}

@MainActor
final class AnalyticsIdentityStore: ObservableObject {
    @Published var identity: AnalyticsIdentity { didSet { AppSupport.save(identity, to: "analytics_identity.json") } }

    init() {
        identity = AppSupport.load(AnalyticsIdentity.self, from: "analytics_identity.json")
            ?? AnalyticsIdentityStore.makeIdentity()
    }

    private static func makeIdentity() -> AnalyticsIdentity {
        AnalyticsIdentity(deviceId: UUID().uuidString, displayName: randomDisplayName())
    }

    private static let adjectives = [
        "Quiet", "Swift", "Calm", "Bright", "Steady", "Clever", "Brisk", "Gentle",
        "Sunny", "Nimble", "Bold", "Sharp", "Warm", "Cool", "Vivid", "Keen",
    ]
    private static let nouns = [
        "Falcon", "Otter", "Maple", "Comet", "Harbor", "Ember", "Willow", "Lynx",
        "Meadow", "Aspen", "Heron", "Cedar", "Ridge", "Sparrow", "Tundra", "Coral",
    ]

    static func randomDisplayName() -> String {
        "\(adjectives.randomElement()!) \(nouns.randomElement()!) \(Int.random(in: 10...99))"
    }
}

// MARK: - Wire types

struct LeaderboardRow: Codable, Identifiable {
    var displayName: String
    var minutesSaved: Int
    var rank: Int
    var id: String { "\(rank)-\(displayName)" }

    enum CodingKeys: String, CodingKey { case displayName, minutesSaved, rank }
}

struct YouRow: Codable {
    var displayName: String
    var minutesSaved: Int
    var rank: Int
    var inTop: Bool
}

struct LeaderboardResponse: Codable {
    var top: [LeaderboardRow]
    var you: YouRow?
}

// MARK: - Client

@MainActor
final class AnalyticsClient: ObservableObject {
    @Published private(set) var leaderboard: LeaderboardResponse?
    @Published private(set) var isLoadingLeaderboard = false

    /// Base URL for the analytics API. The same Vercel project the docs site
    /// deploys to — see api/analytics/ingest.js and api/leaderboard.js.
    private let baseURL = URL(string: "https://openvoiceflow.com")!
    private var lastSyncedAt: Date?
    /// Don't hammer the endpoint on every single dictation — once every few
    /// minutes is plenty for counters that only move in small increments.
    private let minSyncInterval: TimeInterval = 180

    func syncIfDue(controller: AppController, force: Bool = false) {
        guard controller.settings.shareAnalytics else { return }
        if !force, let last = lastSyncedAt, Date().timeIntervalSince(last) < minSyncInterval { return }
        lastSyncedAt = Date()
        Task { await sync(controller: controller) }
    }

    private func sync(controller: AppController) async {
        let identity = controller.analyticsIdentity.identity
        let history = controller.historyStore
        let settings = controller.settings

        var body: [String: Any] = [
            "deviceId": identity.deviceId,
            "displayName": identity.displayName,
            "wordsTotal": history.totalWords,
            "minutesSaved": history.totalMinutes,
            "streakDays": history.streak,
            "appVersion": UpdaterController.shared.appVersion,
            "featureUsage": [
                "cleanupEnabled": settings.backend != .none,
                "snippetsCount": controller.snippetStore.snippets.count,
                "dictionaryCount": controller.dictionaryStore.entries.count,
                "hasKnowMeProfile": controller.profileStore.hasProfile,
            ],
        ]
        if let firstUse = settings.firstUseDate {
            body["firstUseDate"] = ISO8601DateFormatter().string(from: firstUse)
        }

        var req = URLRequest(url: baseURL.appending(path: "api/analytics/ingest"))
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Deletes this device's row from the leaderboard/analytics table
    /// entirely (right-to-erasure). Does not touch the local sharing
    /// toggle — call this from an explicit "Delete my leaderboard data"
    /// action, separate from just turning sharing off.
    func deleteMyData(deviceId: String) async {
        var components = URLComponents(url: baseURL.appending(path: "api/analytics/ingest"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "deviceId", value: deviceId)]
        guard let url = components.url else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: req)
        leaderboard = nil
    }

    /// Fetches the leaderboard. Safe to call whether or not sharing is on —
    /// the endpoint just won't know this device if it never sent data, and
    /// `you` comes back nil.
    func fetchLeaderboard(deviceId: String) async {
        isLoadingLeaderboard = true
        defer { isLoadingLeaderboard = false }
        var components = URLComponents(url: baseURL.appending(path: "api/leaderboard"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "deviceId", value: deviceId)]
        guard let url = components.url else { return }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return }
        leaderboard = try? JSONDecoder().decode(LeaderboardResponse.self, from: data)
    }
}

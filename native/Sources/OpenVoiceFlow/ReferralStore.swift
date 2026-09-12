import AppKit
import Foundation

/// Share OpenVoiceFlow — a referral link built from the same anonymous device
/// ID and toggle as the leaderboard (see AnalyticsStore.swift), not a second
/// identity system. The server (openvoiceflow-web) signs the link so nobody
/// can mint one in another device's name; see api/referrals/link.js and
/// api/_websiteAnalytics.js there for the signing side.

// MARK: - Wire types

struct ReferralLink: Codable, Equatable {
    var code: String
    var sig: String
    var url: URL
}

struct ReferralStats: Codable, Equatable {
    var clicks: Int
    var installs: Int
}

/// A pending "this install came from that device" claim, captured off the
/// pasteboard and not yet confirmed by the server (that happens the next
/// time `AnalyticsClient.syncNow` runs and the server checks the signature).
struct ReferralAttribution: Codable, Equatable {
    var referredBy: String
    var sig: String
}

// MARK: - Deferred attribution capture

/// A disk image has no install-time hook to carry a parameter through to
/// first launch, so the download page writes a marker to the system
/// pasteboard when the Download button is clicked (see docs/site.js in
/// openvoiceflow-web), and this reads it back exactly once.
enum ReferralAttributionCapture {
    private static let markerPrefix = "openvoiceflow-ref:v1:"
    private static let attributionFile = "referral_attribution.json"
    private static let checkedFile = "referral_pasteboard_checked.json"

    private struct CheckedFlag: Codable { var checked = true }

    /// Call once, early at launch. Only ever reads the general pasteboard on
    /// the very first call this installation makes — every call after that,
    /// including on relaunch, is a no-op, so a clipboard that later holds
    /// something else can never be misread as attribution. Never inspects,
    /// stores, or logs pasteboard content that doesn't match the marker.
    @MainActor
    static func captureIfNeeded(ownDeviceId: String) {
        guard AppSupport.load(CheckedFlag.self, from: checkedFile) == nil else { return }
        AppSupport.save(CheckedFlag(), to: checkedFile)

        guard let text = NSPasteboard.general.string(forType: .string),
              text.hasPrefix(markerPrefix) else { return }
        let rest = text.dropFirst(markerPrefix.count)
        let parts = rest.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let referredBy = parts[0].lowercased()
        guard referredBy != ownDeviceId.lowercased(), !parts[1].isEmpty else { return }
        AppSupport.save(ReferralAttribution(referredBy: referredBy, sig: parts[1]), to: attributionFile)
    }

    /// Read by `AnalyticsClient.syncNow` on every sync until the server has
    /// accepted it — harmless to resend, since the server's write is
    /// idempotent (first sync to report a referrer wins, see upsertDevice).
    static var pending: ReferralAttribution? {
        AppSupport.load(ReferralAttribution.self, from: attributionFile)
    }
}

// MARK: - Client

@MainActor
final class ReferralClient: ObservableObject {
    @Published private(set) var link: ReferralLink?
    @Published private(set) var isLoadingLink = false
    @Published private(set) var linkError: String?

    @Published private(set) var stats: ReferralStats?
    @Published private(set) var isLoadingStats = false
    @Published private(set) var statsError: String?

    private let baseURL = URL(string: "https://openvoiceflow.com")!

    /// Mints the link once per app run and reuses it — the server returns the
    /// same signed link for a given device ID every time, so there is
    /// nothing to gain from re-fetching on every sheet open.
    func ensureLink(deviceId: String) async {
        guard link == nil else { return }
        await fetchLink(deviceId: deviceId)
    }

    func fetchLink(deviceId: String) async {
        isLoadingLink = true
        defer { isLoadingLink = false }
        guard let url = endpoint("api/referrals/link", deviceId: deviceId) else {
            linkError = "Couldn’t create a link. Try again."
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                linkError = "Couldn’t create a link. Check your connection and try again."
                return
            }
            link = try JSONDecoder().decode(ReferralLink.self, from: data)
            linkError = nil
        } catch {
            linkError = "Couldn’t create a link. Check your connection and try again."
        }
    }

    func fetchStats(deviceId: String) async {
        isLoadingStats = true
        defer { isLoadingStats = false }
        guard let url = endpoint("api/referrals/stats", deviceId: deviceId) else {
            statsError = "Couldn’t load referral stats. Try again."
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                statsError = "Couldn’t load referral stats. Check your connection and try again."
                return
            }
            stats = try JSONDecoder().decode(ReferralStats.self, from: data)
            statsError = nil
        } catch {
            statsError = "Couldn’t load referral stats. Check your connection and try again."
        }
    }

    private func endpoint(_ path: String, deviceId: String) -> URL? {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "deviceId", value: deviceId)]
        return components?.url
    }
}

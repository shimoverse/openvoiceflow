import AppKit

/// Resolves the real macOS icon for an app the user has dictated into, keyed
/// by display name — the only identifier `HistoryStore` tracks (see
/// `HistoryEntry.app`, captured from `NSWorkspace.frontmostApplication`).
///
/// Deliberately does *not* ship any bundled logo assets: a fixed icon set
/// would only cover a handful of apps, needs upkeep as logos change, and
/// means redistributing third-party trademarks. Asking macOS for the icon
/// it already has on disk covers every app a user could possibly dictate
/// into, with zero maintenance.
@MainActor
enum AppIconProvider {
    private static var cache: [String: NSImage?] = [:]

    /// The running-or-installed app's own icon, or nil if nothing on this
    /// Mac matches `name` (uninstalled since, or the name isn't really an
    /// app — e.g. a browser tab title). Callers fall back to a monogram,
    /// same as the Styles pane already does for apps with no icon.
    static func icon(for name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let resolved = runningAppIcon(named: name) ?? installedAppIcon(named: name)
        cache[name] = resolved
        return resolved
    }

    /// Cheapest path: the app is (or recently was) running, so AppKit
    /// already has its icon loaded — no disk lookup at all.
    private static func runningAppIcon(named name: String) -> NSImage? {
        NSWorkspace.shared.runningApplications
            .first { $0.localizedName == name }?
            .icon
    }

    /// Fallback for an app that appears in history but isn't running right
    /// now. `fullPath(forApplication:)` is deprecated in favor of bundle-ID
    /// lookups, but we only ever have a display name to go on, and it's
    /// still the one Launch Services API that resolves one — so it stays,
    /// synchronous and cached, rather than reaching for an async Spotlight
    /// query for a nice-to-have icon.
    private static func installedAppIcon(named name: String) -> NSImage? {
        guard let path = NSWorkspace.shared.fullPath(forApplication: name) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    /// Shared with the Styles pane's per-app row, which shows the same
    /// letter fallback when there's no icon to draw.
    static func monogram(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased()
    }
}

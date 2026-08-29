import AppKit

/// Resolves the real macOS icon for an app the user has dictated into, keyed
/// by display name — the only identifier `HistoryStore` tracks (see
/// `HistoryEntry.app`, captured from `NSWorkspace.frontmostApplication`).
///
/// Prefer the app icon already installed on this Mac. A tiny branded fallback
/// set covers virtual/default entries (notably Gmail) and common apps that may
/// not be installed yet, so the Styles pane never substitutes initials for the
/// two recognizable services it presents out of the box.
@MainActor
enum AppIconProvider {
    private static var cache: [String: NSImage?] = [:]
    private static let bundledBrands = [
        "Discord": "discord",
        "Gmail": "gmail",
    ]

    /// The running-or-installed app's own icon, or nil if nothing on this
    /// Mac matches `name` (uninstalled since, or the name isn't really an
    /// app — e.g. a browser tab title). Callers fall back to a monogram,
    /// same as the Styles pane already does for apps with no icon.
    static func icon(for name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let resolved = runningAppIcon(named: name)
            ?? installedAppIcon(named: name)
            ?? bundledBrandIcon(named: name)
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

    /// Gmail may be used in a browser and Discord may not be installed yet,
    /// but both are seeded style destinations. Their compact SVG marks ship as
    /// identification-only fallbacks (see Resources/BrandIcons/README.md).
    private static func bundledBrandIcon(named name: String) -> NSImage? {
        guard let resource = bundledBrands[name],
              let url = Bundle.main.url(forResource: resource, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        return image
    }

    /// Shared with the Styles pane's per-app row, which shows the same
    /// letter fallback when there's no icon to draw.
    static func monogram(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased()
    }
}

/// Stable identity hints for apps and services shown in the dashboard.
///
/// Bundle identifiers resolve the exact installed macOS icon. Brand resources
/// cover seeded services that are not installed on this Mac (Gmail is the
/// common example) and keep Personalize recognizable from its first launch.
struct AppIdentityDescriptor: Equatable {
    let bundleIdentifiers: [String]
    let brandResource: String?
}

enum AppIdentityCatalog {
    private static let descriptors: [String: AppIdentityDescriptor] = [
        "Visual Studio Code": .init(
            bundleIdentifiers: ["com.microsoft.VSCode"], brandResource: "visualstudiocode"
        ),
        "Xcode": .init(bundleIdentifiers: ["com.apple.dt.Xcode"], brandResource: "apple"),
        "PyCharm": .init(
            bundleIdentifiers: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"], brandResource: "pycharm"
        ),
        "Zed": .init(bundleIdentifiers: ["dev.zed.Zed"], brandResource: "zedindustries"),
        "Terminal": .init(bundleIdentifiers: ["com.apple.Terminal"], brandResource: "apple"),
        "iTerm2": .init(bundleIdentifiers: ["com.googlecode.iterm2"], brandResource: "iterm2"),
        "Sublime Text": .init(
            bundleIdentifiers: ["com.sublimetext.4", "com.sublimetext.3"], brandResource: "sublimetext"
        ),
        "Nova": .init(bundleIdentifiers: ["com.panic.Nova"], brandResource: "panic"),
        "Mail": .init(bundleIdentifiers: ["com.apple.mail"], brandResource: "apple"),
        "Gmail": .init(bundleIdentifiers: [], brandResource: "gmail"),
        "Outlook": .init(bundleIdentifiers: ["com.microsoft.Outlook"], brandResource: "microsoftoutlook"),
        "Superhuman": .init(bundleIdentifiers: ["com.superhuman.desktop"], brandResource: "superhuman"),
        "Slack": .init(bundleIdentifiers: ["com.tinyspeck.slackmacgap"], brandResource: "slack"),
        "Discord": .init(bundleIdentifiers: ["com.hnc.Discord"], brandResource: "discord"),
        "Messages": .init(bundleIdentifiers: ["com.apple.MobileSMS"], brandResource: "apple"),
        "WhatsApp": .init(bundleIdentifiers: ["net.whatsapp.WhatsApp"], brandResource: "whatsapp"),
        "Telegram": .init(bundleIdentifiers: ["ru.keepcoder.Telegram"], brandResource: "telegram"),
        "Signal": .init(bundleIdentifiers: ["org.whispersystems.signal-desktop"], brandResource: "signal"),
        "Microsoft Word": .init(bundleIdentifiers: ["com.microsoft.Word"], brandResource: "microsoftword"),
        "Pages": .init(bundleIdentifiers: ["com.apple.iWork.Pages"], brandResource: "apple"),
        "Notion": .init(bundleIdentifiers: ["notion.id"], brandResource: "notion"),
        "Safari": .init(bundleIdentifiers: ["com.apple.Safari"], brandResource: "safari"),
        "Google Chrome": .init(bundleIdentifiers: ["com.google.Chrome"], brandResource: "googlechrome"),
        "Claude": .init(
            bundleIdentifiers: ["com.anthropic.claudefordesktop"], brandResource: "claude"
        ),
    ]

    static func descriptor(for name: String) -> AppIdentityDescriptor? {
        descriptors[name]
    }
}

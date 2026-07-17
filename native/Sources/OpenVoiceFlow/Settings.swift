import Foundation
import Security

/// User-visible preferences (no secrets). Persisted as JSON in Application
/// Support. API keys live in the Keychain (see `Keychain`), never on disk.
struct Settings: Codable, Equatable {
    var hotkey: Hotkey = .rightCommand
    var backend: Backend = .openrouter
    var whisperModel: String = "base.en"
    var language: String = "en"
    var style: Style = .default
    var autoPaste: Bool = true
    var soundFeedback: Bool = true
    var launchAtLogin: Bool = false
    var didOnboard: Bool = false

    enum Style: String, Codable, CaseIterable { case `default`, casual, formal, code, email }

    private static var url: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OpenVoiceFlow", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "settings.json")
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url, options: [.atomic, .completeFileProtection])
    }
}

/// The LLM cleanup backends (mirrors the Python app's set).
enum Backend: String, Codable, CaseIterable {
    case openrouter, openai, anthropic, groq, ollama, none

    var needsAPIKey: Bool {
        switch self {
        case .ollama, .none: return false
        default: return true
        }
    }
}

/// Thin Keychain wrapper for provider API keys. Keys are stored as generic
/// passwords keyed by backend, so they never touch the settings JSON.
enum Keychain {
    private static let service = "app.openvoiceflow.apikeys"

    static func setKey(_ key: String?, for backend: Backend) {
        let account = backend.rawValue
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let key, !key.isEmpty, let data = key.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func key(for backend: Backend) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: backend.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

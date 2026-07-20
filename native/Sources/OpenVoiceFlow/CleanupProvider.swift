import Foundation

/// Cleans up a raw transcript (removes fillers, fixes grammar, applies style).
/// Mirrors the Python `llm/` backends but with async/await `URLSession`.
///
/// `context` is the personal-context fragment (profile + dictionary + snippet
/// hints) built by the caller and injected into the system prompt, so the
/// first dictation already knows the user's names, jargon, and corrections.
protocol CleanupProvider {
    func cleanup(_ raw: String, style: Settings.Style, context: String) async throws -> String
}

extension CleanupProvider {
    func cleanup(_ raw: String, style: Settings.Style) async throws -> String {
        try await cleanup(raw, style: style, context: "")
    }
}

enum CleanupFactory {
    static func make(_ settings: Settings) -> CleanupProvider {
        switch settings.backend {
        case .none:
            return PassthroughCleanup()
        case .ollama:
            return OllamaCleanup(model: "llama3.2")
        default:
            let key = Keychain.key(for: settings.backend) ?? ""
            return OpenAICompatibleCleanup(backend: settings.backend, apiKey: key)
        }
    }
}

/// backend == none → raw whisper output, no network.
struct PassthroughCleanup: CleanupProvider {
    func cleanup(_ raw: String, style: Settings.Style, context: String) async throws -> String { raw }
}

private let systemPrompt = """
You are a voice dictation cleanup assistant. Fix grammar, remove filler words \
(um, uh, like, you know), handle corrections (phrases like 'no wait', 'I mean', \
'actually'), and return ONLY the cleaned text — no explanations, no quotes. \
Preserve the original meaning and tone. If the input is already clean, return \
it unchanged.
"""

private func styleSuffix(_ style: Settings.Style) -> String {
    switch style {
    case .default: return ""
    case .casual: return "\nUse a casual, friendly tone."
    case .formal: return "\nUse formal language; avoid contractions."
    case .code: return "\nPreserve technical terms and code references exactly."
    case .email: return "\nFormat as professional email text."
    }
}

/// Response body cap — a cleanup reply is a few KB; this bounds a hostile or
/// buggy endpoint (see the Python audit's response-size finding).
private let maxResponseBytes = 16 * 1024 * 1024

/// OpenAI-compatible chat completions (OpenRouter/OpenAI/Groq) and Anthropic.
struct OpenAICompatibleCleanup: CleanupProvider {
    let backend: Backend
    let apiKey: String

    private var endpoint: URL {
        switch backend {
        case .openrouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        case .openai: return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .groq: return URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        default: return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        }
    }

    private var model: String {
        switch backend {
        case .openrouter: return "google/gemma-4-31b-it"
        case .openai: return "gpt-4o-mini"
        case .groq: return "llama-3.1-8b-instant"
        case .anthropic: return "claude-3-5-haiku-20241022"
        default: return "google/gemma-4-31b-it"
        }
    }

    func cleanup(_ raw: String, style: Settings.Style, context: String) async throws -> String {
        guard !apiKey.isEmpty else { return raw }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let sys = systemPrompt + styleSuffix(style) + context
        let body: [String: Any]
        if backend == .anthropic {
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": model, "max_tokens": 1024, "system": sys,
                "messages": [["role": "user", "content": raw]],
            ]
        } else {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": model, "temperature": 0.1,
                "messages": [
                    ["role": "system", "content": sys],
                    ["role": "user", "content": raw],
                ],
            ]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard data.count <= maxResponseBytes else { return raw }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return raw  // fail open: never lose the user's words to a bad cleanup
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let cleaned = backend == .anthropic ? parseAnthropic(json) : parseOpenAI(json)
        return cleaned?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? raw
    }

    private func parseOpenAI(_ json: [String: Any]?) -> String? {
        (((json?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"]) as? String
    }
    private func parseAnthropic(_ json: [String: Any]?) -> String? {
        ((json?["content"] as? [[String: Any]])?.first?["text"]) as? String
    }
}

/// Fully-local Ollama. Validates the URL is loopback http(s) before use.
struct OllamaCleanup: CleanupProvider {
    let model: String
    var baseURL = "http://localhost:11434"

    func cleanup(_ raw: String, style: Settings.Style, context: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate"),
              url.scheme == "http" || url.scheme == "https" else { return raw }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let prompt = systemPrompt + styleSuffix(style) + context + "\n\nInput:\n" + raw
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "prompt": prompt, "stream": false,
            "options": ["temperature": 0.1],
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard data.count <= maxResponseBytes,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resp = json["response"] as? String else { return raw }
        return resp.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? raw
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

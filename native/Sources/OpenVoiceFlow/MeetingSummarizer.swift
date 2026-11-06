import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One bounded pass over *every* transcript window. The fallback quotes actual
/// transcript sentences; it is extractive, not a generative model.
enum MeetingSummarizer {
    static let windowCharacters = 3_000
    typealias Condense = (String) async throws -> String

    static func windows(_ transcript: String) -> [String] {
        let lines = transcript.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var result: [String] = []
        var current = ""
        for line in lines {
            var remaining = line[...]
            while !remaining.isEmpty {
                let space = windowCharacters - current.count
                if space == 0 {
                    result.append(current)
                    current = ""
                    continue
                }
                let part = String(remaining.prefix(space))
                current += part
                remaining = remaining.dropFirst(part.count)
                if !remaining.isEmpty || current.count == windowCharacters {
                    result.append(current)
                    current = ""
                } else {
                    current += "\n"
                }
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(current) }
        return result
    }

    static func extract(_ window: String) -> String {
        let clean = window.replacingOccurrences(of: #"\[\d\d:\d\d:\d\d\]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        // Select an informative verbatim sentence, never infer a decision/action.
        let sentences = clean.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let common: Set<String> = ["about", "after", "also", "and", "are", "but", "can", "for", "from", "have", "just", "like", "that", "the", "there", "this", "today", "was", "we", "were", "what", "when", "which", "with", "would", "you"]
        func words(_ text: String) -> [String] {
            text.lowercased().components(separatedBy: CharacterSet.letters.inverted)
                .filter { $0.count >= 4 && !common.contains($0) }
        }
        var frequency: [String: Int] = [:]
        for word in words(clean) { frequency[word, default: 0] += 1 }
        let eligible = sentences.filter { $0.count >= 25 && $0.count <= 260 }
        let best = eligible.max { left, right in
            let a = Set(words(left)).reduce(0) { $0 + frequency[$1, default: 0] }
            let b = Set(words(right)).reduce(0) { $0 + frequency[$1, default: 0] }
            return a < b
        } ?? sentences.first ?? ""
        return String(best.prefix(260))
    }

    static func title(from notes: String) -> String? {
        let stop: Set<String> = ["about", "after", "again", "also", "because", "could", "from", "have", "into", "just", "like", "meeting", "notes", "that", "their", "there", "these", "this", "those", "today", "were", "what", "when", "where", "which", "with", "would", "your", "will", "then", "they", "them", "some", "very", "more", "only", "been", "here", "we're", "it's"]
        let tokens = notes.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 4 && !stop.contains($0) }
        var counts: [String: Int] = [:]
        for token in tokens { counts[token, default: 0] += 1 }
        let ranked = counts.keys.sorted { counts[$0] == counts[$1] ? $0 < $1 : counts[$0]! > counts[$1]! }
        guard !ranked.isEmpty else { return nil }
        // All title words occur in the transcript-derived notes.
        return ranked.prefix(3).map { $0.capitalized }.joined(separator: " ")
    }

    static func generate(_ transcript: String, condense: Condense? = nil) async throws -> (notes: String, title: String?) {
        let chunks = windows(transcript)
        guard !chunks.isEmpty else { return ("", nil) }
        var bullets: [String] = []
        for chunk in chunks {
            try Task.checkCancellation()
            guard !extract(chunk).isEmpty else { continue }
            let raw: String
            if let condense { raw = try await condense(chunk) }
            else { raw = try await onDeviceOrExtract(chunk) }
            try Task.checkCancellation()
            let summary = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty { bullets.append("• " + String(summary.prefix(400))) }
        }
        let notes = bullets.joined(separator: "\n")
        return (notes, title(from: notes))
    }

    private static func onDeviceOrExtract(_ chunk: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), SystemLanguageModel.default.isAvailable {
            let session = LanguageModelSession(instructions: "Summarize only what the supplied meeting transcript explicitly states. No invented decisions, action items, people, or facts. Respond in one or two concise sentences. Do not add headings.")
            return try await withExtractiveFallback(chunk) { text in
                try await session.respond(to: text).content
            }
        }
        #endif
        return extract(chunk)
    }

    /// Keep a model refusal or transient device error from stranding saved notes.
    static func withExtractiveFallback(_ chunk: String, model: Condense) async throws -> String {
        do { return try await model(chunk) }
        catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            return extract(chunk)
        }
    }
}

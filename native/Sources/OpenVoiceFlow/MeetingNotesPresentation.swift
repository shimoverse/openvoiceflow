import Foundation

/// Presentation and sharing of the public, generated notes. Does not accept a transcript.
struct MeetingNotesPresentation {
    struct Section: Identifiable {
        let id: Int
        let title: String
        let symbol: String
        let blocks: [Block]
    }

    enum Block {
        case paragraph(String)
        case bullet(String, checked: Bool?)
    }

    let sections: [Section]

    init(_ markdown: String) {
        var results: [Section] = []
        var title: String?
        var lines: [String] = []

        func flush() {
            let blocks = Self.blocks(from: lines)
            if !blocks.isEmpty {
                let name = title ?? "Notes"
                results.append(Section(id: results.count, title: name,
                                       symbol: Self.symbol(for: name), blocks: blocks))
            }
            lines = []
        }

        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // Only top-level Markdown headings split cards. A document-level title
            // is not a section unless it actually has content below it.
            if let heading = Self.heading(in: line) {
                flush()
                title = heading
            } else {
                lines.append(raw)
            }
        }
        flush()
        sections = results
    }

    static func hasNotes(_ markdown: String) -> Bool {
        !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Only generated notes and the caller's explicit private-note opt-in can enter this payload.
    static func shareText(title: String, date: String, generatedNotes: String,
                          privateNotes: String = "", includePrivateNotes: Bool = false,
                          markdown: Bool = true) -> String? {
        guard hasNotes(generatedNotes) else { return nil }
        let cleanTitle = title.components(separatedBy: .newlines)
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = cleanTitle.isEmpty ? "Untitled meeting" : cleanTitle
        var output = markdown ? "# \(heading)\n\n\(date)\n\n\(generatedNotes.trimmingCharacters(in: .whitespacesAndNewlines))"
                              : "\(heading)\n\(date)\n\n\(plainText(generatedNotes))"
        if includePrivateNotes && !privateNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output += markdown ? "\n\n## My notes\n\n\(privateNotes.trimmingCharacters(in: .whitespacesAndNewlines))"
                               : "\n\nMy notes\n\(privateNotes.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return output + "\n"
    }

    static func safeFilename(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:<>|?*\"\n\r\t").union(.controlCharacters)
        let cleaned = title.components(separatedBy: forbidden).joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return String((cleaned.isEmpty ? "Meeting notes" : cleaned).prefix(80))
    }

    private static func heading(in line: String) -> String? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...2).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        let name = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : String(name)
    }

    private static func blocks(from lines: [String]) -> [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        func flushParagraph() {
            if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flushParagraph(); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flushParagraph()
                let text = String(line.dropFirst(2))
                if text.hasPrefix("[ ] ") {
                    result.append(.bullet(String(text.dropFirst(4)), checked: false))
                } else if text.lowercased().hasPrefix("[x] ") {
                    result.append(.bullet(String(text.dropFirst(4)), checked: true))
                } else {
                    result.append(.bullet(text, checked: nil))
                }
            } else if let number = line.firstIndex(of: "."),
                      !line[..<number].isEmpty,
                      line[..<number].allSatisfy({ $0.isNumber }),
                      line[line.index(after: number)...].first == " " {
                flushParagraph()
                result.append(.bullet(String(line[line.index(number, offsetBy: 2)...]), checked: nil))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return result
    }

    private static func symbol(for title: String) -> String {
        switch title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "overview": return "text.alignleft"
        case "key points": return "list.bullet"
        case "decisions": return "checkmark.seal"
        case "action items": return "checklist"
        case "open questions": return "questionmark.circle"
        default: return "note.text"
        }
    }

    private static func plainText(_ markdown: String) -> String {
        markdown.components(separatedBy: .newlines).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let heading = heading(in: trimmed) { return heading }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { return "• " + trimmed.dropFirst(2) }
            return line
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

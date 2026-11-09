// Keep the user's clipboard intact while the rendered fixture exercises Copy notes.
// Clipboard bytes remain in this process's memory; no values are logged or written to disk.
import AppKit
import Foundation

func run() throws -> Int32 {
    let board = NSPasteboard.general
    let original: [[(NSPasteboard.PasteboardType, Data)]] = try (board.pasteboardItems ?? []).map { item in
        try item.types.map { type in
            guard let data = item.data(forType: type) else {
                throw NSError(domain: "MeetingClipboardGuard", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Clipboard type could not be preserved; fixture not started"])
            }
            return (type, data)
        }
    }
    defer {
        board.clearContents()
        let restored = original.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty && !board.writeObjects(restored) {
            fputs("Could not restore clipboard items\n", stderr)
        }
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = Array(CommandLine.arguments.dropFirst())
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

do {
    let status = try run()
    exit(status)
} catch {
    fputs("Clipboard guard could not run fixture: \(error.localizedDescription)\n", stderr)
    exit(1)
}

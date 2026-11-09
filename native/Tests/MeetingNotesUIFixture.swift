// Test-only native host: production MeetingsView/Store/Recorder/presentation, isolated data.
import AppKit
import Foundation
import SwiftUI

@MainActor final class AppController: ObservableObject {
    @Published var isRecording = false
    @Published var isWorking = false
    @Published var meetingOperation = false
    func startMeetingRecording() async {}
    func stopMeetingRecording() async {}
    func pauseMeetingRecording() {}
    func resumeMeetingRecording() {}
    func importMeetingAudio(_ url: URL) async {}
    func transcribeMeeting(_ meeting: MeetingRecord) async {}
    func retryMeetingNotes(_ meeting: MeetingRecord) async {}
}

@MainActor @main struct MeetingNotesUIFixture {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Supply a new scratch directory") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        let scratch = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MEETING_NOTES_QA_SCRATCH"] ?? "", isDirectory: true).standardizedFileURL
        precondition(root.path.hasPrefix(scratch.path + "/") && scratch.path != "/", "Fixture must use isolated scratch")
        precondition(!FileManager.default.fileExists(atPath: root.path), "Refusing to reuse fixture data")
        let library = root.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let longBullets = (1...16).map { "- [ ] Verify milestone \($0) with the local team and document the final status before the next review." }.joined(separator: "\n")
        let specs: [(String, String, String, String)] = [
            ("Harbor planning review", "PRIVATE-DRAFT sentinel — internal budget thought", "RAW-CONVERSATION sentinel — verbatim unedited discussion", """
            ## Overview
            The team reviewed the harbor schedule and agreed on a small launch checklist.

            ## Key points
            - The draft agenda is ready for a local review.
            - The operations handoff remains scheduled for Thursday.

            ## Decisions
            - [x] Keep the pilot scope limited to two sites.

            ## Action items
            \(longBullets)

            ## Open questions
            - Who will confirm the final room setup?
            """),
            ("Orchard follow-up", "Second private reminder", "Second raw conversation, never in copy notes", """
            ## Overview
            The orchard follow-up will use a shorter checklist.

            ## Decisions
            - [x] Share the draft with the project team.
            """)
        ]
        let records = try specs.enumerated().map { offset, spec -> MeetingRecord in
            let id = UUID()
            let filename = "\(id.uuidString).caf"
            try Data("fixture audio only".utf8).write(to: library.appendingPathComponent(filename))
            var record = MeetingRecord(id: id, title: spec.0,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset * 60)),
                duration: 420, transcript: spec.2, notes: spec.1, audioFilename: filename)
            record.generatedNotes = spec.3
            return record
        }
        try JSONEncoder().encode(records).write(to: library.appendingPathComponent("meetings.json"))
        let store = MeetingStore(directory: library, recorder: MeetingRecorder())
        precondition(store.meetings == records)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 768),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Meeting notes fixture"
        window.contentView = NSHostingView(rootView: MeetingsView(controller: AppController(), store: store))
        window.makeKeyAndOrderFront(nil)
        app.run()
    }
}

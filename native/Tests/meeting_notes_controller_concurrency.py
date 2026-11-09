#!/usr/bin/env python3
"""Exercise extracted production controller methods against a real isolated MeetingStore.

No microphone, hotkey, app bundle, user library, or production test hook is used.
"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

native = Path(__file__).resolve().parents[1]
repo = native.parent
source = (native / "Sources/OpenVoiceFlow/AppController.swift").read_text()


def method(text: str, signature: str) -> str:
    # Match one exact declaration, then balance braces; reject drift rather than
    # silently exercising a stale hand-maintained transcription of the method.
    matches = list(re.finditer(re.escape(signature) + r"\s*\{", text))
    if len(matches) != 1:
        raise AssertionError(f"Expected exactly one method: {signature}")
    start = matches[0].start()
    brace = text.index("{", matches[0].start())
    depth = 0
    for at in range(brace, len(text)):
        if text[at] == "{":
            depth += 1
        elif text[at] == "}":
            depth -= 1
            if depth == 0:
                return text[start:at + 1]
    raise AssertionError(f"Unbalanced method: {signature}")


retry_signature = "func retryMeetingNotes(_ meeting: MeetingRecord) async"
start_signature = "private func startRecording()"


def run_case(text: str, directory: Path, name: str) -> subprocess.CompletedProcess:
    retry = method(text, retry_signature)
    start = method(text, start_signature)
    if "meetingStore.generateNotes(for: meeting)" not in retry or "try audio.start()" not in start:
        raise AssertionError("Controller method structure changed; update test harness")
    swift = r'''
import AppKit
import Combine
import Foundation
import os

@MainActor final class HeldCondense {
    var entered = false
    private var held: CheckedContinuation<Void, Never>?
    func run(_ chunk: String) async throws -> String {
        entered = true
        await withCheckedContinuation { held = $0 }
        let sentence = "The team agreed to review the launch checklist."
        let item = MeetingSummarizer.Item(section: "Overview", text: sentence, evidence: sentence)
        return String(data: try JSONEncoder().encode([item]), encoding: .utf8)!
    }
    func release() { held?.resume(); held = nil }
}

@MainActor final class StoreFacade {
    let real: MeetingStore
    let gate: HeldCondense
    init(real: MeetingStore, gate: HeldCondense) { self.real = real; self.gate = gate }
    var isRecording: Bool { real.isRecording }
    var isTranscribing: Bool { real.isTranscribing }
    var isFinalizing: Bool { real.isFinalizing }
    var notesGenerationID: UUID? { real.notesGenerationID }
    var notesFailureID: UUID? { real.notesFailureID }
    func generateNotes(for meeting: MeetingRecord) async throws {
        try await real.generateNotes(for: meeting, condense: { [gate] chunk in
            try await gate.run(chunk)
        })
    }
}

struct FakeSettings { var hotkey = "Fn"; var liveTranscript = false }
final class FakeAudio {
    var starts = 0
    func start() throws { starts += 1 }
}
final class FakeHUD {
    func setMaxSeconds(_ seconds: Double) {}
    func setShowChip(_ show: Bool) {}
    func show(_ state: FakeHUDState) {}
}
enum FakeHUDState {
    case recording(hotkey: String)
    case error(FakeHUDError)
}
enum FakeHUDError { case microphone }

@MainActor final class AppController {
    var isRecording = false
    var isWorking = false
    var pausedUntil: Date?
    var meetingOperation = false
    var notesRequestErrorID: UUID?
    var notesRequestError: String?
    var lastError: String?
    var meetingStore: StoreFacade
    var settings = FakeSettings()
    let audio = FakeAudio()
    let hud = FakeHUD()
    let log = Logger(subsystem: "org.openvoiceflow.qa", category: "controller")
    var dictationTask: Task<Void, Never>?
    var dictationGeneration = 0
    var pressTime = Date.distantPast
    var maxRecordingSeconds: Double { 300 }
    var shouldShowHotkeyChip: Bool { false }
    var streamPartials = false
    var maxRecordTask: Task<Void, Never>?
    init(meetingStore: StoreFacade) { self.meetingStore = meetingStore }
    func startPartialStream() {}
    func stopAndProcess() {}
    func probeStartRecording() { startRecording() }

    __RETRY__

    __START__
}

@MainActor @main struct ControllerConcurrencyProbe {
    static func main() async throws {
        let library = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let id = UUID()
        let transcript = "The team agreed to review the launch checklist."
        let meeting = MeetingRecord(id: id, title: "Private QA", createdAt: Date(), duration: 5,
            transcript: transcript, notes: "", audioFilename: "\(id.uuidString).caf")
        try JSONEncoder().encode([meeting]).write(to: library.appendingPathComponent("meetings.json"))
        let real = MeetingStore(directory: library, recorder: MeetingRecorder())
        let gate = HeldCondense()
        let controller = AppController(meetingStore: StoreFacade(real: real, gate: gate))
        let task = Task { await controller.retryMeetingNotes(meeting) }
        for _ in 0..<200 where !gate.entered { try await Task.sleep(for: .milliseconds(10)) }
        guard gate.entered, real.notesGenerationID == id else { fatalError("Real store did not enter held generation") }
        guard !controller.meetingOperation else { fatalError("Regeneration took the meetingOperation lock") }
        controller.probeStartRecording()  // Exact production method; fake audio cannot open microphone.
        guard controller.audio.starts == 1, controller.isRecording else {
            fatalError("Dictation start was blocked during notes generation")
        }
        gate.release()
        await task.value
        guard real.notesGenerationID == nil, real.notesCompletionID == id,
              real.meetings.first?.generatedNotes.contains("launch checklist") == true else {
            fatalError("Real store failed to complete and reset generation")
        }
        controller.maxRecordTask?.cancel()
        print("PASS production retryMeetingNotes + startRecording permit dictation during real-store notes generation")
    }
}
'''.replace("__RETRY__", retry).replace("__START__", start)
    path = directory / f"{name}.swift"
    path.write_text(swift)
    binary = directory / name
    sources = [native / "Sources/OpenVoiceFlow" / filename for filename in
               ("MeetingRecorder.swift", "MeetingSummarizer.swift", "MeetingSpeechGate.swift", "MeetingStore.swift")]
    compile_result = subprocess.run(["swiftc", "-parse-as-library", "-o", str(binary), str(path),
                                     *map(str, sources)], capture_output=True, text=True)
    if compile_result.returncode:
        raise RuntimeError(f"{name} compile failed:\n{compile_result.stderr}")
    result = subprocess.run([str(binary), str(directory / f"{name}-library")],
                            capture_output=True, text=True, timeout=15)
    return result


scratch = Path(os.environ.get("MEETING_NOTES_QA_SCRATCH", str(Path.home() / ".hermes/cache/scratch")))
scratch.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="meeting-controller-qa-", dir=scratch) as temporary:
    directory = Path(temporary)
    current = run_case(source, directory, "current")
    if current.returncode:
        raise AssertionError(f"Current controller FAILED: {current.stdout}\n{current.stderr}")
    print(current.stdout.strip(), flush=True)
    if "--verify-red" in sys.argv:
        baseline = subprocess.run(["git", "show", "HEAD:native/Sources/OpenVoiceFlow/AppController.swift"],
                                  cwd=repo, capture_output=True, text=True, check=True).stdout
        old = run_case(baseline, directory, "baseline")
        if old.returncode == 0 or "Regeneration took the meetingOperation lock" not in old.stderr:
            raise AssertionError(f"Baseline did not fail expected lock assertion: {old.stdout}\n{old.stderr}")
        print("PASS baseline RED: previous retryMeetingNotes blocked dictation", flush=True)

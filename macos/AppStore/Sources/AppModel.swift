import AppKit
import AVFoundation
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var statusText = "Ready — hold Control+Option+Space"
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false

    let shortcutDescription = "Control+Option+Space"

    private let audioCapture = AudioCapture()
    private let localStore = LocalStore.shared
    private var whisperContext: WhisperContext?
    private var recordingStartedAt: Date?

    var actionTitle: String {
        isRecording ? "Stop and transcribe" : "Start recording"
    }

    func hotKeyPressed() {
        guard !isRecording, !isBusy else { return }
        requestMicrophoneAndStart()
    }

    func hotKeyReleased() {
        guard isRecording else { return }
        stopAndTranscribe()
    }

    func toggleRecording() {
        isRecording ? stopAndTranscribe() : requestMicrophoneAndStart()
    }

    func testMicrophone() {
        requestMicrophoneAndStart()
    }

    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        statusText = "Copied — press Command+V in any app"
    }

    func reportShortcutFailure(_ error: Error) {
        statusText = error.localizedDescription
    }

    private func requestMicrophoneAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted {
                        self.beginRecording()
                    } else {
                        self.statusText = "Microphone access is off in System Settings"
                    }
                }
            }
        default:
            statusText = "Microphone access is off in System Settings"
        }
    }

    private func beginRecording() {
        do {
            _ = try audioCapture.start()
            recordingStartedAt = Date()
            transcript = ""
            isRecording = true
            statusText = "Listening… release Control+Option+Space when finished"
        } catch {
            statusText = "Could not start recording: \(error.localizedDescription)"
        }
    }

    private func stopAndTranscribe() {
        guard let recordingURL = audioCapture.stop() else { return }
        let duration = max(0, Date().timeIntervalSince(recordingStartedAt ?? Date()))
        recordingStartedAt = nil
        isRecording = false
        isBusy = true
        statusText = "Transcribing locally…"

        Task {
            do {
                let samples = try AudioCapture.samples(from: recordingURL)
                let context = try loadWhisperContext()
                let text = try await context.transcribe(samples: samples)
                transcript = text
                isBusy = false
                if text.isEmpty {
                    statusText = "No speech detected — try again"
                } else {
                    localStore.recordDictation(text: text, duration: duration)
                    copyTranscript()
                }
            } catch {
                isBusy = false
                statusText = "Transcription failed: \(error.localizedDescription)"
            }
        }
    }

    private func loadWhisperContext() throws -> WhisperContext {
        if let whisperContext {
            return whisperContext
        }
        guard let modelURL = Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin") else {
            throw WhisperFailure.modelMissing
        }
        let context = try WhisperContext.load(modelURL: modelURL)
        whisperContext = context
        return context
    }
}

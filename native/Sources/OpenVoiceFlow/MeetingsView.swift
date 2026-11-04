import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// A local meeting library. Recording and transcription enter through AppController
/// so they cannot overlap dictation or another model job.
struct MeetingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var store: MeetingStore
    @Environment(\.colorScheme) private var scheme

    @State private var selectedID: UUID?
    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var showConsent = false
    @State private var showDelete = false
    @State private var alertMessage: String?
    @State private var recordingStartedAt: Date?
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?

    init(controller: AppController, store: MeetingStore) {
        self.controller = controller
        self.store = store
    }

    private var dark: Bool { scheme == .dark }
    private var ink: Color { dark ? DT.inkDark : DT.inkLight }
    private var secondary: Color { dark ? DT.ink2Dark : DT.ink2Light }
    private var surface: Color { dark ? DT.cardDark : DT.cardLight }
    private var accent: Color { dark ? DT.emberDark : DT.emberLight }
    private var busy: Bool { controller.isRecording || controller.isWorking || controller.meetingOperation || store.isRecording || store.isTranscribing }
    private var selected: MeetingRecord? { store.meetings.first { $0.id == selectedID } }
    private var canEdit: Bool { selected != nil && !busy }

    var body: some View {
        HStack(spacing: 0) {
            library
                .frame(width: 254)
                .background(dark ? DT.sideDark : DT.sideLight)
            Rectangle().fill(secondary.opacity(0.18)).frame(width: 1)
            Group {
                if let meeting = selected {
                    detail(meeting)
                } else {
                    emptyDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dark ? DT.winDark : DT.winLight)
        }
        .foregroundStyle(ink)
        .onAppear { reconcileSelection() }
        .onDisappear { persistDrafts(); stopPlayback() }
        .onChange(of: selectedID) { previous, _ in
            if let previous, let record = store.meetings.first(where: { $0.id == previous }), hasChanges(record) {
                saveEdits(record)
            }
            stopPlayback()
            loadDrafts()
        }
        .onChange(of: store.meetings) { _, _ in reconcileSelection() }
        .onChange(of: store.isRecording) { _, recording in
            if recording {
                stopPlayback()
                if recordingStartedAt == nil { recordingStartedAt = Date() }
            } else {
                recordingStartedAt = nil
            }
        }
        .onChange(of: store.isTranscribing) { _, transcribing in
            if !transcribing, let meeting = selected, !hasChanges(meeting) { loadDrafts() }
        }
        .onChange(of: store.errorMessage) { _, message in
            if let message { alertMessage = message }
        }
        .alert("Meetings", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog("Before recording", isPresented: $showConsent, titleVisibility: .visible) {
            Button("Everyone agrees — Start recording") {
                recordingStartedAt = Date()
                Task { await controller.startMeetingRecording() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Make sure everyone agrees before recording. The microphone captures sound in your room and from speakers, but not remote participants heard only through headphones. Audio and notes stay on this Mac.")
        }
        .confirmationDialog("Delete this meeting?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete meeting and audio", role: .destructive) {
                guard !busy, let meeting = selected else { return }
                stopPlayback()
                do { try store.delete(meeting) }
                catch { alertMessage = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes the local audio, transcript, and notes.")
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Meetings")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text("Your recordings, transcripts & notes")
                    .font(.system(size: 11))
                    .foregroundStyle(secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 20)

            VStack(spacing: 8) {
                if store.isRecording {
                    Button {
                        Task { await controller.stopMeetingRecording() }
                    } label: {
                        Label("Stop recording", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DT.destructive)
                    .disabled(controller.isWorking || controller.isRecording || store.isTranscribing)
                    recordingStatus
                } else {
                    Button { persistDrafts(); stopPlayback(); showConsent = true } label: {
                        Label("Record meeting", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(busy)
                }
                Button(action: importAudio) {
                    Label("Import audio…", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)

            HStack {
                Text("LIBRARY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(secondary)
                Spacer()
                Text("\(store.meetings.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(secondary)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.meetings) { meeting in
                        Button { selectedID = meeting.id } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 13))
                                    .foregroundStyle(meeting.id == selectedID ? accent : secondary)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(meeting.title.isEmpty ? "Untitled meeting" : meeting.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(2)
                                    Text("\(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))  ·  \(duration(meeting.duration))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: DT.rControl)
                                .fill(meeting.id == selectedID ? accent.opacity(0.13) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(meeting.title), \(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .padding(.horizontal, 8)
            }
            if store.meetings.isEmpty {
                Text("Nothing here yet. Record a conversation or import an audio file.")
                    .font(.system(size: 12))
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(18)
                Spacer()
            }
            Divider().padding(.horizontal, 16)
            Label("Stored locally on this Mac · no uploads", systemImage: "lock.shield")
                .font(.system(size: 10))
                .foregroundStyle(secondary)
                .padding(16)
        }
    }

    private var recordingStatus: some View {
        HStack(spacing: 7) {
            Circle().fill(DT.destructive).frame(width: 7, height: 7)
            if let start = recordingStartedAt {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text("Recording · \(duration(context.date.timeIntervalSince(start)))")
                        .monospacedDigit()
                }
            } else {
                Text("Recording")
            }
            Spacer()
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(secondary)
    }

    private var emptyDetail: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path")
                .font(.system(size: 38, weight: .ultraLight))
                .foregroundStyle(accent)
            Text("Every conversation, in one place")
                .font(.system(size: 20, weight: .medium, design: .rounded))
            Text("Select a meeting to listen, read the transcript, and write your own notes.")
                .font(.system(size: 13))
                .foregroundStyle(secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detail(_ meeting: MeetingRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        Label("LOCAL MEETING", systemImage: "lock")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(dark ? DT.moss : DT.mossLight)
                        Spacer()
                        Text(meeting.createdAt.formatted(date: .complete, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        TextField("Meeting title", text: $titleDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .disabled(!canEdit)
                            .accessibilityLabel("Meeting title")
                        if canEdit && hasChanges(meeting) {
                            Button("Save changes") { saveEdits(meeting) }
                                .buttonStyle(.borderedProminent)
                                .tint(accent)
                        }
                    }
                    Text("\(duration(meeting.duration)) audio · Local audio recording")
                        .font(.system(size: 11))
                        .foregroundStyle(secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        if playingID == meeting.id { stopPlayback() }
                        else { play(meeting) }
                    } label: {
                        Label(playingID == meeting.id ? "Stop audio" : "Play audio",
                              systemImage: playingID == meeting.id ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    Button("Reveal audio", systemImage: "folder") {
                        let url = store.audioURL(for: meeting)
                        guard FileManager.default.fileExists(atPath: url.path) else {
                            alertMessage = "The audio file could not be found."
                            return
                        }
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Delete", systemImage: "trash", role: .destructive) { showDelete = true }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                }
                .controlSize(.small)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sectionTitle("YOUR NOTES")
                        Spacer()
                        if hasChanges(meeting) && canEdit {
                            Text("Unsaved changes")
                                .font(.system(size: 11))
                                .foregroundStyle(secondary)
                        }
                    }
                    TextEditor(text: $notesDraft)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(9)
                        .frame(minHeight: 130)
                        .background(surface, in: RoundedRectangle(cornerRadius: DT.rCard))
                        .overlay(RoundedRectangle(cornerRadius: DT.rCard).stroke(secondary.opacity(0.2)))
                        .disabled(!canEdit)
                        .accessibilityLabel("Personal meeting notes")
                    Text("Your notes are yours to write. No automatic summary is generated.")
                        .font(.system(size: 11))
                        .foregroundStyle(secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        sectionTitle("TRANSCRIPT")
                        Spacer()
                        if !meeting.transcript.isEmpty {
                            Button("Copy", systemImage: "doc.on.doc") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(meeting.transcript, forType: .string)
                            }
                            Button("Export…", systemImage: "square.and.arrow.up") { export(meeting) }
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    if store.isTranscribing {
                        Label("Transcribing locally…", systemImage: "waveform")
                            .font(.system(size: 12))
                            .foregroundStyle(secondary)
                            .padding(16)
                    } else if meeting.transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("No transcript yet. Transcribe this audio on your Mac, or keep it as a recording.")
                                .font(.system(size: 13))
                                .foregroundStyle(secondary)
                            Button("Transcribe / Retry", systemImage: "text.word.spacing") {
                                Task { await controller.transcribeMeeting(meeting) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            .disabled(busy)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(surface, in: RoundedRectangle(cornerRadius: DT.rCard))
                    } else {
                        Button("Transcribe again / Retry") {
                            Task { await controller.transcribeMeeting(meeting) }
                        }.disabled(busy)
                        Text(meeting.transcript)
                            .font(.system(size: 13))
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(surface, in: RoundedRectangle(cornerRadius: DT.rCard))
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(secondary)
    }

    private func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func reconcileSelection() {
        if let selectedID, store.meetings.contains(where: { $0.id == selectedID }) { return }
        self.selectedID = store.meetings.first?.id
        loadDrafts()
    }

    private func loadDrafts() {
        titleDraft = selected?.title ?? ""
        notesDraft = selected?.notes ?? ""
    }

    private func hasChanges(_ meeting: MeetingRecord) -> Bool {
        titleDraft != meeting.title || notesDraft != meeting.notes
    }

    private func saveEdits(_ meeting: MeetingRecord) {
        guard var current = store.meetings.first(where: { $0.id == meeting.id }) else { return }
        current.title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        current.notes = notesDraft
        do {
            try store.update(current)
            titleDraft = current.title
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func persistDrafts() {
        if let record = selected, hasChanges(record) { saveEdits(record) }
    }

    private func importAudio() {
        guard !busy else { return }
        persistDrafts()
        stopPlayback()
        let panel = NSOpenPanel()
        panel.title = "Import meeting audio"
        panel.message = "Choose audio to save in your local meeting library."
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await controller.importMeetingAudio(url) }
    }

    private func play(_ meeting: MeetingRecord) {
        stopPlayback()
        do {
            let audio = try AVAudioPlayer(contentsOf: store.audioURL(for: meeting))
            guard audio.play() else {
                alertMessage = "Unable to play this audio file."
                return
            }
            player = audio
            playingID = meeting.id
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        playingID = nil
    }

    private func export(_ meeting: MeetingRecord) {
        let panel = NSSavePanel()
        panel.title = "Export meeting text"
        panel.nameFieldStringValue = "\(meeting.title.isEmpty ? "Meeting" : meeting.title).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = "\(meeting.title)\n\(meeting.createdAt.formatted(date: .complete, time: .shortened))\n\nNotes\n\(meeting.notes)\n\nTranscript\n\(meeting.transcript)\n"
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { alertMessage = error.localizedDescription }
    }
}

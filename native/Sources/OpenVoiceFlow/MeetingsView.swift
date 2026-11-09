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
    @State private var titleBaseline = ""
    @State private var notesBaseline = ""
    private struct Draft { var title: String; var notes: String }
    @State private var pendingDrafts: [UUID: Draft] = [:]
    @AppStorage("meetingConsentDismissed") private var consentDismissed = false
    @State private var skipFutureConsent = false
    @State private var showConsent = false
    @State private var showDelete = false
    @State private var alertMessage: String?
    @State private var detailsExpanded = false
    @State private var includePrivateNotes = false
    @State private var expandedSections: Set<Int> = []

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
    private var busy: Bool { controller.isRecording || controller.isWorking || controller.meetingOperation || store.isRecording || store.isTranscribing || store.isFinalizing }
    private var selected: MeetingRecord? { store.meetings.first { $0.id == selectedID } }
    private var canEdit: Bool { selected != nil }

    var body: some View {
        HStack(spacing: 0) {
            library
                .frame(width: 220)
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
            detailsExpanded = false
            includePrivateNotes = false
            expandedSections = []
            loadDrafts()
        }
        .onChange(of: store.meetings) { _, new in
            if let id = selectedID, let current = new.first(where: { $0.id == id }) {
                if titleDraft == titleBaseline { titleDraft = current.title }
                if notesDraft == notesBaseline { notesDraft = current.notes }
                titleBaseline = current.title
                notesBaseline = current.notes
            }
            reconcileSelection()
        }
        .onChange(of: store.activeMeetingID) { _, active in
            if let active {
                persistDrafts()
                selectedID = active
            }
        }
        .onChange(of: store.isRecording) { _, recording in if recording { stopPlayback() } }
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
        .sheet(isPresented: $showConsent) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Before recording").font(.title2.bold())
                Text("Make sure everyone agrees before recording. The microphone captures sound in your room and from speakers, but not remote participants heard only through headphones. Audio, transcripts, and notes stay on this Mac.")
                Toggle("Do not show again", isOn: $skipFutureConsent)
                HStack {
                    Button("Cancel") { showConsent = false }
                    Spacer()
                    Button("Everyone agrees — Start recording") {
                        consentDismissed = skipFutureConsent
                        showConsent = false
                        Task { await controller.startMeetingRecording() }
                    }.buttonStyle(.borderedProminent).disabled(busy)
                }
            }
            .padding(24)
            .frame(width: 450)
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
                Text("Recordings & meeting notes")
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
                    Button {
                        if store.isPaused { controller.resumeMeetingRecording() }
                        else { controller.pauseMeetingRecording() }
                    } label: {
                        Label(store.isPaused ? "Resume recording" : "Pause recording",
                              systemImage: store.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                    recordingStatus
                } else {
                    Button {
                        persistDrafts(); stopPlayback()
                        if consentDismissed { Task { await controller.startMeetingRecording() } }
                        else { skipFutureConsent = false; showConsent = true }
                    } label: {
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
                Button("Recording disclaimer…") { skipFutureConsent = consentDismissed; showConsent = true }
                    .buttonStyle(.link)
                if consentDismissed {
                    Button("Reset recording disclaimer") { consentDismissed = false }
                        .buttonStyle(.link)
                }
                if let status = store.transcriptionStatus {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Transcription status: \(status)")
                }
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
                                    Text("\(meeting.createdAt.formatted(.dateTime.month(.abbreviated).day()))  ·  \(duration(meeting.duration))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(secondary)
                                        .lineLimit(1)
                                        .help(meeting.createdAt.formatted(date: .complete, time: .shortened))
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
            if store.isPaused {
                Text("Paused · \(duration(store.recordedDuration))")
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("Recording · \(duration(store.recordedDuration))")
                        .monospacedDigit()
                }
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
            Text("Select a meeting to review the essentials, follow up, or listen again.")
                .font(.system(size: 13))
                .foregroundStyle(secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detail(_ meeting: MeetingRecord) -> some View {
        let notes = MeetingNotesPresentation(meeting.generatedNotes)
        let hasNotes = MeetingNotesPresentation.hasNotes(meeting.generatedNotes)
        return ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("LOCAL MEETING", systemImage: "lock")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(dark ? DT.moss : DT.mossLight)
                        Spacer()
                        Text(meeting.createdAt.formatted(date: .complete, time: .shortened))
                            .font(.system(size: 12)).foregroundStyle(secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        TextField("Meeting title", text: Binding(
                            get: { titleDraft },
                            set: { value in
                                titleDraft = value
                                pendingDrafts[meeting.id] = Draft(title: value, notes: notesDraft)
                            }
                        ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .disabled(!canEdit)
                            .accessibilityLabel("Meeting title")
                        if canEdit && hasChanges(meeting) {
                            Button("Save changes") { saveEdits(meeting) }
                                .buttonStyle(.borderedProminent).tint(accent)
                        }
                    }
                    Text("\(duration(meeting.duration)) audio · Saved on this Mac")
                        .font(.system(size: 11)).foregroundStyle(secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("MEETING NOTES")
                        Text("The essentials, ready to use")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                        HStack(spacing: 10) {
                            Button("Copy notes", systemImage: "doc.on.doc") { copyNotes(meeting) }
                                .disabled(!hasNotes)
                            Menu {
                                Toggle("Include my notes", isOn: $includePrivateNotes)
                                Divider()
                                Button("Copy notes") { copyNotes(meeting) }
                                Button("Export Markdown…") { exportNotes(meeting, markdown: true) }
                                Button("Export plain text…") { exportNotes(meeting, markdown: false) }
                            } label: { Label("Share notes", systemImage: "square.and.arrow.up") }
                                .disabled(!hasNotes)
                            Spacer(minLength: 0)
                        }
                        if includePrivateNotes {
                            Label("Sharing includes your private notes", systemImage: "exclamationmark.shield")
                                .font(.system(size: 11)).foregroundStyle(secondary)
                        }
                    }
                    .controlSize(.small)
                    if store.isFinalizing && store.activeMeetingID == meeting.id {
                        ProgressView("Creating local meeting notes…")
                    }
                    if hasNotes {
                        ForEach(notes.sections) { section in noteCard(section) }
                    } else {
                        VStack(alignment: .leading, spacing: 9) {
                            Image(systemName: "text.book.closed")
                                .font(.system(size: 22, weight: .light)).foregroundStyle(accent)
                            Text("No meeting notes yet").font(.system(size: 15, weight: .medium))
                            Text(meeting.transcript.isEmpty
                                 ? "Once there’s a conversation, you can create notes here."
                                 : "Create notes from this conversation on your Mac.")
                                .font(.system(size: 12)).foregroundStyle(secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(surface, in: RoundedRectangle(cornerRadius: DT.rCard))
                    }
                    if !meeting.transcript.isEmpty && store.activeMeetingID != meeting.id {
                        Button(meeting.generatedNotes.isEmpty ? "Create notes" : "Regenerate notes") {
                            Task { await controller.retryMeetingNotes(meeting) }
                        }
                        .disabled(busy).font(.system(size: 11))
                    }
                    if let error = store.notesError, store.notesFailureID == meeting.id {
                        Text(error).foregroundStyle(DT.destructive)
                    }
                }

                // Keep live words visible without opening recording details.
                if store.isRecording && store.activeMeetingID == meeting.id {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(store.isPaused ? "PAUSED CONVERSATION" : "LIVE CONVERSATION",
                                  systemImage: "waveform")
                                .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                                .foregroundStyle(accent)
                            Spacer()
                            recordingStatus.frame(width: 125)
                        }
                        Text(meeting.transcript.isEmpty ? "Listening for speech…" : meeting.transcript)
                            .font(.system(size: 13)).lineSpacing(5)
                            .foregroundStyle(meeting.transcript.isEmpty ? secondary : ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(surface, in: RoundedRectangle(cornerRadius: DT.rCard))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sectionTitle("MY NOTES · PRIVATE")
                        Spacer()
                        if hasChanges(meeting) && canEdit {
                            Text("Unsaved changes").font(.system(size: 11)).foregroundStyle(secondary)
                        }
                    }
                    TextEditor(text: Binding(
                        get: { notesDraft },
                        set: { value in
                            notesDraft = value
                            pendingDrafts[meeting.id] = Draft(title: titleDraft, notes: value)
                        }
                    ))
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(9)
                        .frame(minHeight: 130)
                        .background(surface, in: RoundedRectangle(cornerRadius: DT.rCard))
                        .overlay(RoundedRectangle(cornerRadius: DT.rCard).stroke(secondary.opacity(0.2)))
                        .disabled(!canEdit)
                        .accessibilityLabel("Personal meeting notes")
                    Text("Only shared when you explicitly choose Include my notes.")
                        .font(.system(size: 11)).foregroundStyle(secondary)
                }

                DisclosureGroup(isExpanded: $detailsExpanded) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            Button {
                                if playingID == meeting.id { stopPlayback() }
                                else { play(meeting) }
                            } label: {
                                Label(playingID == meeting.id ? "Stop audio" : "Play audio",
                                      systemImage: playingID == meeting.id ? "stop.fill" : "play.fill")
                            }
                            .disabled(store.isRecording)
                            Button("Reveal audio", systemImage: "folder") {
                                let url = store.audioURL(for: meeting)
                                guard FileManager.default.fileExists(atPath: url.path) else {
                                    alertMessage = "The audio file could not be found."
                                    return
                                }
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            Spacer()
                            Button("Delete", systemImage: "trash", role: .destructive) { showDelete = true }
                                .disabled(busy)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                sectionTitle("CONVERSATION")
                                Spacer()
                                Button("Copy conversation", systemImage: "doc.on.doc") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(meeting.transcript, forType: .string)
                                }
                                .disabled(meeting.transcript.isEmpty).font(.system(size: 11))
                            }
                            if store.activeMeetingID == meeting.id, let status = store.transcriptionStatus {
                                Label(status, systemImage: "waveform")
                                    .font(.system(size: 12)).foregroundStyle(secondary)
                            }
                            if meeting.transcript.isEmpty {
                                Text(store.activeMeetingID == meeting.id && (store.isRecording || store.isTranscribing)
                                     ? "Listening for speech…"
                                     : "No conversation text yet. You can transcribe the audio on your Mac.")
                                    .font(.system(size: 13)).foregroundStyle(secondary)
                            } else {
                                Text(meeting.transcript)
                                    .font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(18)
                                    .background(surface, in: RoundedRectangle(cornerRadius: DT.rCard))
                            }
                            Button(meeting.transcript.isEmpty ? "Transcribe / Retry" : "Transcribe again / Retry",
                                   systemImage: "text.word.spacing") {
                                Task { await controller.transcribeMeeting(meeting) }
                            }
                            .disabled(busy).font(.system(size: 11))
                        }
                    }
                    .padding(.top, 15)
                } label: {
                    Label("Recording details", systemImage: "waveform")
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(18)
                .background(surface, in: RoundedRectangle(cornerRadius: DT.rCard))
            }
            .padding(30)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func noteCard(_ section: MeetingNotesPresentation.Section) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                Text(section.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(section.blocks.prefix(expandedSections.contains(section.id) ? section.blocks.count : 6).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(.init(text))
                        .font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .bullet(let text, let checked):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: checked == nil ? "circle.fill" :
                              (checked == true ? "checkmark.square.fill" : "square"))
                            .font(.system(size: checked == nil ? 5 : 13)).foregroundStyle(accent)
                            .frame(width: 15)
                            .accessibilityLabel(checked == true ? "Completed action" : "Action item")
                            .accessibilityHidden(checked == nil)
                        Text(.init(text))
                            .font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if section.blocks.count > 6 {
                Button(expandedSections.contains(section.id) ? "Show less" : "Show all \(section.blocks.count) items") {
                    if expandedSections.contains(section.id) { expandedSections.remove(section.id) }
                    else { expandedSections.insert(section.id) }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: DT.rCard))
        .overlay(RoundedRectangle(cornerRadius: DT.rCard).stroke(secondary.opacity(0.12)))
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
        if let active = store.activeMeetingID, selectedID == nil {
            selectedID = active
            loadDrafts()
            return
        }
        if let selectedID, store.meetings.contains(where: { $0.id == selectedID }) { return }
        self.selectedID = store.meetings.first?.id
        loadDrafts()
    }

    private func loadDrafts() {
        let record = selected
        titleBaseline = record?.title ?? ""
        notesBaseline = record?.notes ?? ""
        let pending = record.flatMap { pendingDrafts[$0.id] }
        titleDraft = pending?.title ?? titleBaseline
        notesDraft = pending?.notes ?? notesBaseline
    }

    private func hasChanges(_ meeting: MeetingRecord) -> Bool {
        titleDraft != titleBaseline || notesDraft != notesBaseline
    }

    private func saveEdits(_ meeting: MeetingRecord) {
        guard var current = store.meetings.first(where: { $0.id == meeting.id }) else { return }
        if titleDraft != titleBaseline { current.title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
        if notesDraft != notesBaseline { current.notes = notesDraft }
        do {
            try store.update(current)
            pendingDrafts.removeValue(forKey: meeting.id)
            titleDraft = current.title
            titleBaseline = current.title
            notesBaseline = current.notes
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

    private func sharePayload(_ meeting: MeetingRecord, markdown: Bool) -> String? {
        MeetingNotesPresentation.shareText(
            title: titleDraft,
            date: meeting.createdAt.formatted(date: .complete, time: .shortened),
            generatedNotes: meeting.generatedNotes,
            privateNotes: notesDraft,
            includePrivateNotes: includePrivateNotes,
            markdown: markdown
        )
    }

    private func copyNotes(_ meeting: MeetingRecord) {
        guard let text = sharePayload(meeting, markdown: true) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportNotes(_ meeting: MeetingRecord, markdown: Bool) {
        guard let text = sharePayload(meeting, markdown: markdown) else { return }
        let panel = NSSavePanel()
        panel.title = "Export meeting notes"
        panel.nameFieldStringValue = MeetingNotesPresentation.safeFilename(titleDraft) + (markdown ? ".md" : ".txt")
        panel.allowedContentTypes = markdown ? [UTType(filenameExtension: "md") ?? .plainText] : [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { alertMessage = error.localizedDescription }
    }
}

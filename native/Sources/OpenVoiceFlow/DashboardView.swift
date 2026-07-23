import AppKit
import SwiftUI

/// The dashboard window — design phase 03 (native/design/03-dashboard.dc.html).
///
/// Fixed 212 pt sidebar (text + selection tint, no icons — by design) and a
/// flexible content pane. Data-backed panes render the designed empty states
/// until their stores exist; stats celebrate outcomes (words, time back),
/// never engagement.
struct DashboardView: View {
    @ObservedObject var controller: AppController
    // Observe the stores directly so pane edits refresh live.
    @ObservedObject private var history: HistoryStore
    @ObservedObject private var dictionary: DictionaryStore
    @ObservedObject private var snippets: SnippetStore
    @ObservedObject private var styleStore: StyleStore
    @ObservedObject private var profileStore: ProfileStore
    @State private var pane: Pane = .home
    @State private var showInterview = false
    @State private var apiKeyDraft = ""       // mirrors the Keychain key for the selected backend
    @Environment(\.colorScheme) private var scheme

    init(controller: AppController) {
        self.controller = controller
        self.history = controller.historyStore
        self.dictionary = controller.dictionaryStore
        self.snippets = controller.snippetStore
        self.styleStore = controller.styleStore
        self.profileStore = controller.profileStore
    }

    enum Pane: String, CaseIterable {
        case home = "Home"
        case history = "History"
        case dictionary = "Dictionary"
        case snippets = "Snippets"
        case styles = "Styles"
        case knowMe = "Know-Me"
        case settings = "Settings"
    }

    private var dark: Bool { scheme == .dark }
    private var ink: Color { dark ? DT.inkDark : DT.inkLight }
    private var ink2: Color { dark ? DT.ink2Dark : DT.ink2Light }
    private var card: Color { dark ? DT.cardDark : DT.cardLight }
    private var hair: Color { dark ? .white.opacity(0.09) : .black.opacity(0.08) }
    private var fill: Color { dark ? .white.opacity(0.06) : .black.opacity(0.05) }
    private var accent: Color { DT.emberWave }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(hair)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 26)
                .padding(.horizontal, 30)
                .background(dark ? DT.winDark : DT.winLight)
        }
        .frame(minWidth: 1000, minHeight: 660)
    }

    // MARK: sidebar (212 pt, dot + label rows)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                RingGlyph(size: 22)
                Text("OpenVoiceFlow").font(.system(size: 13, weight: .bold)).foregroundStyle(ink)
            }
            .padding(.bottom, 14)
            .padding(.top, 34)  // room for traffic lights

            ForEach(Pane.allCases, id: \.self) { item in
                Button { pane = item } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(pane == item ? accent : .clear)
                            .frame(width: 6, height: 6)
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: pane == item ? .semibold : .regular))
                            .foregroundStyle(ink)
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(pane == item
                                  ? (dark ? DT.emberDark.opacity(0.14) : DT.emberLight.opacity(0.10))
                                  : .clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle().fill(DT.moss).frame(width: 6, height: 6)
                Text("v0.4.0 · up to date").font(.system(size: 11)).foregroundStyle(ink2)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 10)
        .frame(width: 212)
        .background(dark ? DT.sideDark : DT.sideLight)
    }

    // MARK: content router

    @ViewBuilder private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch pane {
                case .home: home
                case .history: historyPane
                case .dictionary: dictionaryPane
                case .snippets: snippetsPane
                case .styles: styles
                case .knowMe: knowMe
                case .settings: settingsPane
                }
            }
            .padding(.bottom, 30)
        }
        .sheet(isPresented: $showInterview) {
            KnowMeInterview(controller: controller)
        }
    }

    private func paneTitle(_ title: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .bold)).kerning(-0.4).foregroundStyle(ink)
            if let subtitle {
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(ink2)
            }
        }
    }

    // MARK: Home

    private var home: some View {
        VStack(alignment: .leading, spacing: 18) {
            paneTitle(greeting, homeSubtitle)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                let total = controller.historyStore.totalWords
                let streak = controller.historyStore.streak
                statCard("Words dictated", value: total > 0 ? "\(total)" : "0",
                         sub: controller.wordsToday > 0 ? "+\(controller.wordsToday) today" : "say something!",
                         subColor: controller.wordsToday > 0 ? DT.moss : ink2)
                statCard("Time saved", value: timeSaved, sub: "vs typing at 40 wpm", subColor: ink2)
                statCard("Streak", value: streak > 0 ? "\(streak)" : "—", sub: "days in a row", subColor: ink2)
                statCard("This week", value: "\(controller.historyStore.lastWeek.reduce(0, +))", sub: "words", subColor: ink2)
            }

            weekChart

            HStack {
                Text("Recent").font(.system(size: 13, weight: .bold)).foregroundStyle(ink)
                Spacer()
                Button("See all →") { pane = .history }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DT.emberLight)
            }
            Text("Dictations land here — searchable, on this Mac only.")
                .font(.system(size: 12.5)).foregroundStyle(ink2)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
        return "Good \(part)."
    }

    private var homeSubtitle: String {
        let words = controller.wordsToday
        guard words > 0 else { return "Hold \(controller.settings.hotkey.glyph) in any app to start." }
        let minutes = Int(Double(words) / 40.0)  // vs typing at 40 wpm
        return "You've spoken \(words) words today — about \(minutes) minutes you didn't spend typing."
    }

    private var timeSaved: String {
        // vs typing at 40 wpm, over all history.
        let minutes = Int(Double(controller.historyStore.totalWords) / 40.0)
        if minutes >= 60 { return "\(minutes / 60) h \(minutes % 60) m" }
        return "\(minutes) min"
    }

    private func statCard(_ label: String, value: String, sub: String?, subColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(ink2)
            Text(value).font(.system(size: 26, weight: .bold)).kerning(-0.5).foregroundStyle(ink)
            if let sub {
                Text(sub).font(.system(size: 11, weight: sub.hasPrefix("+") ? .semibold : .regular))
                    .foregroundStyle(subColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 12).fill(card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hair))
    }

    /// "This week" bar chart: 7 bars, 110 pt, today accented (design §4).
    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("This week").font(.system(size: 13, weight: .bold)).foregroundStyle(ink)
                Text("words per day").font(.system(size: 11)).foregroundStyle(ink2)
            }
            HStack(alignment: .bottom, spacing: 10) {
                let values = weekValues
                let peak = max(values.max() ?? 1, 1)
                ForEach(Array(values.enumerated()), id: \.offset) { i, value in
                    VStack(spacing: 4) {
                        UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 2,
                                               bottomTrailingRadius: 2, topTrailingRadius: 6)
                            .fill(i == values.count - 1 ? accent
                                  : (dark ? .white.opacity(0.14) : .black.opacity(0.12)))
                            .frame(maxWidth: 44)
                            .frame(height: max(110 * CGFloat(value) / CGFloat(peak), 110 * 0.04))
                        Text(["M", "T", "W", "T", "F", "S", "S"][i])
                            .font(.system(size: 10)).foregroundStyle(ink2)
                    }
                }
            }
            .frame(height: 130)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hair))
    }

    /// Real last-7-days totals from the history store.
    private var weekValues: [Int] { controller.historyStore.lastWeek }

    // MARK: History

    /// "Where you dictate" — a discreet, all-time per-app word breakdown that
    /// sits above the History list. Kept off the Home pane on purpose: it's a
    /// look-if-you-want stat, not a headline number. Single-hue (accent at
    /// stepped opacity) so it stays on-palette; hides itself until there are at
    /// least two apps to compare.
    @ViewBuilder private var appBreakdown: some View {
        let dist = history.appDistribution
        if dist.count >= 2 {
            let top = Array(dist.prefix(6))
            let shownFraction = top.reduce(0.0) { $0 + $1.fraction }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Where you dictate").font(.system(size: 13, weight: .bold)).foregroundStyle(ink)
                    Text("by words").font(.system(size: 11)).foregroundStyle(ink2)
                }
                GeometryReader { geo in
                    HStack(spacing: 1.5) {
                        ForEach(Array(top.enumerated()), id: \.offset) { i, row in
                            Rectangle()
                                .fill(accent.opacity(1.0 - Double(i) * 0.13))
                                .frame(width: max(geo.size.width * row.fraction, 2))
                        }
                        if shownFraction < 0.999 {
                            Rectangle().fill(dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                VStack(spacing: 6) {
                    ForEach(Array(top.enumerated()), id: \.offset) { i, row in
                        HStack(spacing: 8) {
                            Circle().fill(accent.opacity(1.0 - Double(i) * 0.13)).frame(width: 7, height: 7)
                            Text(row.app).font(.system(size: 12)).foregroundStyle(ink).lineLimit(1)
                            Spacer()
                            Text("\(Int((row.fraction * 100).rounded()))%")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                            Text("\(row.words)").font(.system(size: 11)).foregroundStyle(ink2)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(card))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hair))
        }
    }

    @ViewBuilder private var historyPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            paneTitle("History")
            appBreakdown
            if history.entries.isEmpty {
                emptyPanel(
                    title: "Nothing here yet",
                    body: "Hold \(controller.settings.hotkey.displayName) in any app and say hello. Every take lands here — on this Mac only.",
                    button: nil
                )
            } else {
                ForEach(history.entries) { entry in
                    HStack(spacing: 12) {
                        Text(entry.timestamp, format: .dateTime.hour().minute())
                            .font(.system(size: 11)).foregroundStyle(ink2).frame(width: 56, alignment: .leading)
                        Text(entry.app).font(.system(size: 10, weight: .bold)).foregroundStyle(ink2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(fill))
                        Text(entry.text).font(.system(size: 12.5)).foregroundStyle(ink).lineLimit(1)
                        Spacer()
                        Text("\(entry.words)").font(.system(size: 11)).foregroundStyle(ink2)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                        }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(DT.emberLight)
                    }
                    .padding(.vertical, 10)
                    .overlay(Rectangle().fill(hair).frame(height: 1), alignment: .top)
                }
                Text("Raw audio is discarded after transcription. Delete everything from Settings › Privacy.")
                    .font(.system(size: 11)).foregroundStyle(ink2).padding(.top, 6)
            }
        }
    }

    // MARK: Dictionary

    @ViewBuilder private var dictionaryPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            paneTitle("Dictionary", "Names and jargon Whisper gets wrong — corrected before cleanup ever runs.")
            addRow(placeholder: "Add a word (e.g. WhisperKit)") { dictionary.add(word: $0) }
            if dictionary.entries.isEmpty {
                emptyPanel(title: "No corrections yet",
                           body: "Add a word above, or run the Know-Me interview to seed names and jargon automatically.",
                           button: nil)
            } else {
                ForEach(dictionary.entries) { entry in
                    HStack {
                        Text(entry.word).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                        if !entry.aliases.isEmpty {
                            Text("↤ \(entry.aliases.joined(separator: ", "))")
                                .font(.system(size: 11)).foregroundStyle(ink2)
                        }
                        Spacer()
                        Button { dictionary.remove(entry) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(ink2)
                        }.buttonStyle(.plain)
                    }
                    .padding(.vertical, 9)
                    .overlay(Rectangle().fill(hair).frame(height: 1), alignment: .top)
                }
            }
        }
    }

    // MARK: Snippets

    @ViewBuilder private var snippetsPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            paneTitle("Snippets", "Say the trigger, get the expansion — mid-dictation.")
            SnippetAddRow(fill: fill, ink: ink, ink2: ink2, accent: DT.emberLight) { trigger, expansion in
                snippets.add(trigger: trigger, expansion: expansion)
            }
            if snippets.snippets.isEmpty {
                emptyPanel(title: "No snippets yet",
                           body: "Try one: trigger \"my address\", expansion your street address. Then just say it.",
                           button: nil)
            } else {
                ForEach(snippets.snippets) { snip in
                    HStack(alignment: .top, spacing: 12) {
                        Text(snip.trigger).font(.system(size: 11, weight: .bold)).foregroundStyle(DT.emberLight)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
                        Text(snip.expansion).font(.system(size: 12.5)).foregroundStyle(ink)
                        Spacer()
                        Button { snippets.remove(snip) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(ink2)
                        }.buttonStyle(.plain)
                    }
                    .padding(.vertical, 10)
                    .overlay(Rectangle().fill(hair).frame(height: 1), alignment: .top)
                }
            }
        }
    }

    /// A one-field add row used by the Dictionary pane.
    private func addRow(placeholder: String, onAdd: @escaping (String) -> Void) -> some View {
        InlineAddField(placeholder: placeholder, fill: fill, ink: ink, accent: DT.emberLight, onAdd: onAdd)
    }

    // MARK: Styles

    private var styles: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("Styles", "Cleanup adapts to where you're typing. Detected from the frontmost app.")
                .padding(.bottom, 12)
            ForEach(styleStore.map.sorted(by: { $0.key < $1.key }), id: \.key) { app, styleID in
                HStack(spacing: 12) {
                    Text(monogram(app))
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(ink2)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 7).fill(fill))
                    Text(app).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                        .frame(width: 150, alignment: .leading)
                    Picker("", selection: styleBinding(for: app)) {
                        Text("Casual").tag("casual")
                        Text("Neutral").tag("default")
                        Text("Formal").tag("formal")
                        Text("Code").tag("code")
                        Text("Email").tag("email")
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    Spacer()
                }
                .padding(.vertical, 11)
                .overlay(Rectangle().fill(hair).frame(height: 1), alignment: .top)
            }
            Text("Cleanup uses the frontmost app's style automatically; the menu-bar Style is the fallback.")
                .font(.system(size: 11)).foregroundStyle(ink2)
                .padding(.top, 12)
        }
    }

    private func styleBinding(for app: String) -> Binding<String> {
        Binding(get: { styleStore.map[app] ?? "default" },
                set: { styleStore.map[app] = $0 })
    }

    private func monogram(_ app: String) -> String {
        String(app.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased()
    }

    // MARK: Know-Me

    private var knowMe: some View {
        VStack(alignment: .leading, spacing: 18) {
            paneTitle("Know-Me", "A two-minute interview that teaches cleanup your voice. Stored locally, editable, deletable.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Profile").font(.system(size: 13, weight: .bold)).foregroundStyle(ink)
                    if profileStore.hasProfile {
                        profileRow("Name", profileStore.profile.name)
                        profileRow("Work", profileStore.profile.occupation)
                        profileRow("People", profileStore.profile.workNames.joined(separator: ", "))
                        profileRow("Jargon", profileStore.profile.technicalTerms.joined(separator: ", "))
                        profileRow("Tone", profileStore.profile.communicationStyle)
                        HStack(spacing: 12) {
                            Button("Re-run interview") { showInterview = true }.buttonStyle(.bordered)
                            Button("Clear") { profileStore.profile = Profile() }
                                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(DT.destructive)
                        }
                        .padding(.top, 4)
                    } else {
                        Text("Run the interview and cleanup learns your name, your team's jargon, and how you like to sound.")
                            .font(.system(size: 12.5)).foregroundStyle(ink2)
                        Button("Run interview (2 min)") { showInterview = true }
                            .buttonStyle(.borderedProminent).tint(DT.emberWave)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(card))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hair))

                VStack(alignment: .leading, spacing: 8) {
                    Text("What it does").font(.system(size: 13, weight: .bold)).foregroundStyle(ink)
                    Text("YOU SAID").font(.system(size: 11)).foregroundStyle(ink2)
                    Text("\"um yeah so tell priya we should ship the hud thing on friday i think\"")
                        .font(.system(size: 12.5)).italic().foregroundStyle(ink2)
                    Text("IT TYPES").font(.system(size: 11)).foregroundStyle(ink2)
                    Text("Priya — let's ship the HUD on Friday.")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                    Text("The profile is a local prompt fragment. It never syncs, and \"None\" backend ignores it entirely.")
                        .font(.system(size: 11)).foregroundStyle(ink2)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(card))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hair))
            }
        }
    }

    @ViewBuilder private func profileRow(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text(label).font(.system(size: 12)).foregroundStyle(ink2).frame(width: 54, alignment: .leading)
                Text(value).font(.system(size: 12.5)).foregroundStyle(ink)
            }
        }
    }

    // MARK: Settings

    static let whisperModels: [(String, String)] = [
        ("tiny", "Tiny — 39 MB"),
        ("small", "Small — 466 MB"),
        ("medium", "Medium — 1.5 GB"),
        ("large-v3-turbo", "Large v3 turbo — 1.6 GB"),
    ]
    static let languages: [(String, String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"),
        ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("hi", "Hindi"),
        ("ja", "Japanese"), ("zh", "Chinese"), ("ko", "Korean"),
    ]
    /// Cleanup providers offered when cleanup is on (excludes `.none`).
    static let cleanupProviders: [Backend] = [.anthropic, .openai, .groq, .openrouter, .ollama]

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            paneTitle("Settings")

            settingsCard("DICTATION") {
                settingsRow("Hotkey") {
                    Picker("", selection: hotkeyBinding) {
                        ForEach(Hotkey.allCases, id: \.self) { key in Text(key.displayName).tag(key) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 190)
                }
                settingsRow("Max take length") {
                    Picker("", selection: bind(\.maxRecordingSeconds)) {
                        Text("1 minute").tag(60.0)
                        Text("2 minutes").tag(120.0)
                        Text("5 minutes").tag(300.0)
                        Text("10 minutes").tag(600.0)
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 140)
                }
                settingsToggle("Sounds", isOn: bind(\.soundFeedback))
                settingsToggle("Paste automatically", isOn: bind(\.autoPaste))
            }

            settingsCard("TRANSCRIPTION — ON THIS MAC") {
                settingsRow("Whisper model") {
                    Picker("", selection: bind(\.whisperModel)) {
                        ForEach(whisperModelOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 210)
                }
                settingsRow("Language") {
                    Picker("", selection: bind(\.language)) {
                        ForEach(languageOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 170)
                }
            }

            cleanupCard

            settingsCard("PRIVACY + UPDATES") {
                settingsRow("Your data — on this Mac only") {
                    HStack(spacing: 14) {
                        Button("Reveal in Finder") { _ = NSWorkspace.shared.open(AppSupport.dir) }
                            .buttonStyle(.plain).foregroundStyle(DT.emberLight)
                        Button("Delete history…") { controller.historyStore.clearAll() }
                            .buttonStyle(.plain).foregroundStyle(DT.destructive)
                    }
                    .font(.system(size: 12))
                }
                settingsToggle("Automatic updates", isOn: autoUpdateBinding)
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
        .onAppear { reloadAPIKeyDraft() }
    }

    // MARK: AI cleanup card (toggle → provider → key → optional model)

    @ViewBuilder private var cleanupCard: some View {
        settingsCard("AI CLEANUP") {
            settingsToggle("Clean up my dictation", isOn: cleanupEnabledBinding)
            if controller.settings.backend != .none {
                settingsRow("Provider") {
                    Picker("", selection: backendBinding) {
                        ForEach(Self.cleanupProviders, id: \.self) { Text(providerLabel($0)).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 200)
                }
                if controller.settings.backend.needsAPIKey {
                    settingsRow("API key") {
                        SecureField("Paste your key", text: $apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 230)
                            .onChange(of: apiKeyDraft) { _, new in
                                Keychain.setKey(new, for: controller.settings.backend)
                            }
                    }
                    settingsRow("Model (optional)") {
                        TextField(
                            CleanupFactory.defaultModel(for: controller.settings.backend),
                            text: bind(\.cleanupModelOverride)
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 230)
                    }
                } else if controller.settings.backend == .ollama {
                    settingsRow("Endpoint") {
                        Text("localhost:11434 · fully local").foregroundStyle(ink2)
                    }
                }
            } else {
                settingsRow("Off — raw transcript, nothing leaves this Mac") { EmptyView() }
            }
        }
    }

    private func providerLabel(_ b: Backend) -> String {
        switch b {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI"
        case .groq: return "Groq"
        case .openrouter: return "OpenRouter"
        case .ollama: return "Ollama (on-device)"
        case .none: return "Off"
        }
    }

    // Always include the current value so the Picker selection is never orphaned.
    private var whisperModelOptions: [(String, String)] {
        var opts = Self.whisperModels
        let current = controller.settings.whisperModel
        if !opts.contains(where: { $0.0 == current }) { opts.insert((current, current), at: 0) }
        return opts
    }
    private var languageOptions: [(String, String)] {
        var opts = Self.languages
        let current = controller.settings.language
        if !opts.contains(where: { $0.0 == current }) { opts.insert((current, current), at: 0) }
        return opts
    }

    private func reloadAPIKeyDraft() {
        apiKeyDraft = Keychain.key(for: controller.settings.backend) ?? ""
    }

    // MARK: bindings

    /// Generic setting binding that persists on write.
    private func bind<V>(_ keyPath: WritableKeyPath<Settings, V>) -> Binding<V> {
        Binding(
            get: { controller.settings[keyPath: keyPath] },
            set: { controller.settings[keyPath: keyPath] = $0; controller.settings.save() }
        )
    }

    /// Hotkey needs the tap restarted, so it goes through the controller.
    private var hotkeyBinding: Binding<Hotkey> {
        Binding(get: { controller.settings.hotkey }, set: { controller.updateHotkey($0) })
    }

    /// Cleanup on/off: off ⇒ `.none` (local raw), on ⇒ Anthropic by default.
    private var cleanupEnabledBinding: Binding<Bool> {
        Binding(
            get: { controller.settings.backend != .none },
            set: { on in
                controller.settings.backend = on ? .anthropic : .none
                controller.settings.save()
                reloadAPIKeyDraft()
            }
        )
    }

    private var backendBinding: Binding<Backend> {
        Binding(
            get: { controller.settings.backend },
            set: { b in
                controller.settings.backend = b
                controller.settings.save()
                reloadAPIKeyDraft()
            }
        )
    }

    private var autoUpdateBinding: Binding<Bool> {
        Binding(
            get: { controller.settings.automaticUpdates },
            set: {
                controller.settings.automaticUpdates = $0
                controller.settings.save()
                UpdaterController.shared.setAutomaticChecks($0)
            }
        )
    }

    private func settingsCard(_ header: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(.system(size: 11, weight: .bold)).kerning(0.5).foregroundStyle(ink2)
                .padding(.horizontal, 16).padding(.vertical, 10)
            Divider().overlay(hair)
            rows()
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hair))
    }

    private func settingsRow(_ label: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(ink)
            Spacer()
            trailing().font(.system(size: 13))
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(ink)
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).tint(DT.moss).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: shared empty state (dashed border, waveform, CTA)

    private func emptyPanel(title: String, body bodyText: String, button: String?) -> some View {
        VStack(spacing: 12) {
            EmptyWave()
                .frame(width: 220, height: 34)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
            Text(bodyText)
                .font(.system(size: 12.5)).foregroundStyle(ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let button {
                Button(button) {}
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(DT.emberLight))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56).padding(.horizontal, 20)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hair, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

/// The animated brand ring — r = 0.34·size, 0.62 rad gap, ±10% five-lobe
/// wobble drifting at 0.7 rad/s (design phases 03/05/06).
struct RingGlyph: View {
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                ringCanvas(t: 0)
            } else {
                TimelineView(.animation) { context in
                    ringCanvas(t: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func ringCanvas(t: Double) -> some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width, h = canvasSize.height
            let cx = w / 2, cy = h / 2
            let R = min(w, h) * 0.34, gap = 0.62, off = -1.0
            var path = Path()
            var a = off + gap / 2
            var first = true
            while a <= off + 2 * .pi - gap / 2 {
                let r = R * (1 + 0.10 * sin(a * 5 - t * 0.7))
                let p = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
                if first { path.move(to: p); first = false } else { path.addLine(to: p) }
                a += 0.045
            }
            ctx.stroke(path, with: .color(DT.emberWave),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

/// Empty-state waveform: y = mid + sin(0.045x − 1.7t)·1.3·win(u).
private struct EmptyWave: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                waveCanvas(t: 0)
            } else {
                TimelineView(.animation) { context in
                    waveCanvas(t: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
    }

    private func waveCanvas(t: Double) -> some View {
        Canvas { ctx, size in
            let w = size.width, mid = size.height / 2
            var path = Path()
            var x: Double = 0
            var first = true
            while x <= w {
                let y = mid + sin(0.045 * x - 1.7 * t) * 1.3 * Voiceline.window(x / w) * 8
                if first { path.move(to: CGPoint(x: x, y: y)); first = false }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
                x += 2
            }
            let color = scheme == .dark ? DT.dimWaveDark : DT.dimWaveLight
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

/// A single-field "type + Enter (or Add)" row used by the Dictionary pane.
private struct InlineAddField: View {
    let placeholder: String
    let fill: Color
    let ink: Color
    let accent: Color
    let onAdd: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 8).fill(fill))
                .onSubmit(commit)
            Button("Add") { commit() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(accent))
        }
    }

    private func commit() {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        onAdd(value)
        text = ""
    }
}

/// A trigger + expansion add row used by the Snippets pane.
private struct SnippetAddRow: View {
    let fill: Color
    let ink: Color
    let ink2: Color
    let accent: Color
    let onAdd: (String, String) -> Void
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("trigger", text: $trigger)
                .textFieldStyle(.plain).font(.system(size: 13)).frame(width: 140)
                .padding(9).background(RoundedRectangle(cornerRadius: 8).fill(fill))
            TextField("expands to…", text: $expansion)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(9).background(RoundedRectangle(cornerRadius: 8).fill(fill))
                .onSubmit(commit)
            Button("Add") { commit() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(accent))
        }
    }

    private func commit() {
        let t = trigger.trimmingCharacters(in: .whitespaces)
        let e = expansion.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !e.isEmpty else { return }
        onAdd(t, e)
        trigger = ""; expansion = ""
    }
}

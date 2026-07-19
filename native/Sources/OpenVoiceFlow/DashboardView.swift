import SwiftUI

/// The dashboard window — design phase 03 (native/design/03-dashboard.dc.html).
///
/// Fixed 212 pt sidebar (text + selection tint, no icons — by design) and a
/// flexible content pane. Data-backed panes render the designed empty states
/// until their stores exist; stats celebrate outcomes (words, time back),
/// never engagement.
struct DashboardView: View {
    @ObservedObject var controller: AppController
    @State private var pane: Pane = .home
    @Environment(\.colorScheme) private var scheme

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
                case .history: history
                case .dictionary: dictionary
                case .snippets: snippets
                case .styles: styles
                case .knowMe: knowMe
                case .settings: settingsPane
                }
            }
            .padding(.bottom, 30)
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
                statCard("Words dictated", value: controller.wordsToday > 0 ? "\(controller.wordsToday)" : "0",
                         sub: controller.wordsToday > 0 ? "+\(controller.wordsToday) today" : "say something!",
                         subColor: controller.wordsToday > 0 ? DT.moss : ink2)
                statCard("Time saved", value: timeSaved, sub: "vs typing at 40 wpm", subColor: ink2)
                statCard("Streak", value: "—", sub: "days in a row", subColor: ink2)
                statCard("Speaking pace", value: "—", sub: nil, subColor: ink2)
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
        let minutes = Int(Double(controller.wordsToday) / 40.0)
        return minutes > 0 ? "\(minutes) min" : "0 min"
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

    /// Today's live count in the last slot; history store fills the rest later.
    private var weekValues: [Int] {
        var values = [Int](repeating: 0, count: 7)
        values[6] = controller.wordsToday
        return values
    }

    // MARK: History (designed empty state until the store exists)

    private var history: some View {
        VStack(alignment: .leading, spacing: 18) {
            paneTitle("History")
            emptyPanel(
                title: "Nothing here yet",
                body: "Hold \(controller.settings.hotkey.displayName) in any app and say hello. Every take lands here — searchable, on this Mac only.",
                button: "Try it now"
            )
            Text("Raw audio is discarded after transcription. Text history lives in ~/Library — delete any row, day, or everything in Settings › Privacy.")
                .font(.system(size: 11)).foregroundStyle(ink2)
        }
    }

    // MARK: Dictionary

    private var dictionary: some View {
        VStack(alignment: .leading, spacing: 18) {
            paneTitle("Dictionary", "Names and jargon Whisper gets wrong — corrected before cleanup ever runs.")
            emptyPanel(
                title: "No corrections yet",
                body: "When a transcript gets a name wrong, fix it once in History — it lands here and never happens again.",
                button: nil
            )
        }
    }

    // MARK: Snippets

    private var snippets: some View {
        VStack(alignment: .leading, spacing: 18) {
            paneTitle("Snippets", "Say the trigger, get the expansion — mid-dictation.")
            emptyPanel(
                title: "No snippets yet",
                body: "Try one: trigger \"my address\", expansion your street address. Then just say it.",
                button: "New snippet"
            )
        }
    }

    // MARK: Styles

    private var styles: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("Styles", "Cleanup adapts to where you're typing. Detected from the frontmost app.")
                .padding(.bottom, 12)
            ForEach(defaultStyleRows, id: \.app) { row in
                HStack(spacing: 12) {
                    Text(row.monogram)
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(ink2)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 7).fill(fill))
                    Text(row.app).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                        .frame(width: 90, alignment: .leading)
                    Picker("", selection: .constant(row.style)) {
                        Text("Casual").tag("Casual")
                        Text("Neutral").tag("Neutral")
                        Text("Formal").tag("Formal")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    Text(row.example).font(.system(size: 11.5)).italic().foregroundStyle(ink2)
                    Spacer()
                }
                .padding(.vertical, 13)
                .overlay(Rectangle().fill(hair).frame(height: 1), alignment: .top)
            }
            Text("VS Code and terminals default to verbatim — cleanup off, punctuation literal.")
                .font(.system(size: 11)).foregroundStyle(ink2)
                .padding(.top, 12)
        }
    }

    private var defaultStyleRows: [(monogram: String, app: String, style: String, example: String)] {
        [
            ("iM", "iMessage", "Casual", "lol ok — moving standup to 10"),
            ("Ma", "Mail", "Formal", "Could we move standup to 10:00 tomorrow?"),
            ("Sl", "Slack", "Neutral", "Can we move standup to 10 tomorrow?"),
        ]
    }

    // MARK: Know-Me

    private var knowMe: some View {
        VStack(alignment: .leading, spacing: 18) {
            paneTitle("Know-Me", "A two-minute interview that teaches cleanup your voice. Stored locally, editable, deletable.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Profile").font(.system(size: 13, weight: .bold)).foregroundStyle(ink)
                    Text("Run the interview and cleanup learns your name, your team's jargon, and how you like to sound.")
                        .font(.system(size: 12.5)).foregroundStyle(ink2)
                    Button("Run interview (2 min)") {}
                        .buttonStyle(.bordered)
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

    // MARK: Settings

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            paneTitle("Settings")

            settingsCard("DICTATION") {
                settingsRow("Hotkey") {
                    Text(controller.settings.hotkey.displayName)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(fill))
                }
                settingsRow("Max take length") { Text("5 minutes").foregroundStyle(ink2) }
                settingsToggle("Sounds", isOn: bind(\.soundFeedback))
            }

            settingsCard("TRANSCRIPTION — ON THIS MAC") {
                settingsRow("Whisper model") { Text(controller.settings.whisperModel).foregroundStyle(ink2) }
                settingsRow("Language") { Text(controller.settings.language).foregroundStyle(ink2) }
            }

            settingsCard("AI CLEANUP") {
                settingsRow("Backend") { Text(controller.settings.backend.rawValue).foregroundStyle(ink2) }
                settingsRow("Cloud API key") {
                    HStack(spacing: 8) {
                        Text("••••••••").font(.system(size: 12, design: .monospaced)).foregroundStyle(ink2)
                        Text("KEYCHAIN")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(DT.moss)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DT.moss))
                    }
                }
            }

            settingsCard("PRIVACY + UPDATES") {
                settingsRow("All data stays in ~/Library/Application Support/OpenVoiceFlow") {
                    HStack(spacing: 12) {
                        Button("Export…") {}.buttonStyle(.plain).foregroundStyle(DT.emberLight)
                        Button("Delete all…") {}.buttonStyle(.plain).foregroundStyle(DT.destructive)
                    }
                    .font(.system(size: 12))
                }
                settingsToggle("Automatic updates", isOn: .constant(true))
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private func bind(_ keyPath: WritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        Binding(
            get: { controller.settings[keyPath: keyPath] },
            set: { controller.settings[keyPath: keyPath] = $0; controller.settings.save() }
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

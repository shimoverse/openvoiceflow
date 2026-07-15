import SwiftUI

struct ContentView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = LocalStore.shared

    var body: some View {
        Group {
            if store.onboardingComplete {
                DashboardView()
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 760, minHeight: 540)
    }
}

private struct OnboardingView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = LocalStore.shared
    @State private var step = 0
    @State private var name = ""
    @State private var role = ""

    private let cards = [
        ("Your voice, on your Mac", "OpenVoiceFlow processes dictation locally. Nothing is sent to an OpenVoiceFlow server.", "lock.shield"),
        ("Choose how you speak", "Hold Control+Option+Space to dictate. You can change the shortcut later in Settings.", "keyboard"),
        ("Try one dictation", "Allow microphone access only when you are ready to test. Your result is copied to the clipboard.", "waveform"),
        ("Make it yours", "Add a local profile and important names. You can edit or erase everything later.", "person.crop.circle"),
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: cards[step].2)
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(.orange)
            Text(cards[step].0).font(.system(size: 32, weight: .bold, design: .rounded))
            Text(cards[step].1).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
            if step == 2 {
                Button("Test microphone") { model.testMicrophone() }.buttonStyle(.bordered)
            }
            if step == 3 {
                VStack(spacing: 10) {
                    TextField("Your name (optional)", text: $name)
                    TextField("Role or focus (optional)", text: $role)
                }.textFieldStyle(.roundedBorder).frame(width: 320)
            }
            HStack {
                Text("\(step + 1) of \(cards.count)").foregroundStyle(.secondary)
                Spacer()
                Button(step == cards.count - 1 ? "Start dictating" : "Continue") {
                    if step == cards.count - 1 {
                        store.updateProfile(name: name, role: role)
                        store.completeOnboarding()
                    } else { step += 1 }
                }.buttonStyle(.borderedProminent).tint(.orange)
            }.frame(width: 460)
            Spacer()
        }.padding(36)
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case insights = "Insights"
    case dictionary = "Dictionary"
    case profile = "Profile"
    case settings = "Settings"
    var id: String { rawValue }
}

private struct DashboardView: View {
    @State private var selection: DashboardSection? = .home

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: icon(for: section)).tag(section)
            }
            .navigationTitle("OpenVoiceFlow")
        } detail: {
            switch selection ?? .home {
            case .home: HomeView()
            case .insights: InsightsView()
            case .dictionary: DictionaryView()
            case .profile: ProfileView()
            case .settings: SettingsView()
            }
        }
    }

    private func icon(for section: DashboardSection) -> String {
        switch section {
        case .home: return "house"
        case .insights: return "chart.bar"
        case .dictionary: return "text.book.closed"
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape"
        }
    }
}

private struct HomeView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = LocalStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(store.profile.displayName.isEmpty ? "Ready when you are" : "Welcome back, \(store.profile.displayName)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(model.statusText, systemImage: model.isRecording ? "mic.fill" : "waveform")
                    Text("Hold Control+Option+Space, speak English, then release. Your result is copied locally to the clipboard.").foregroundStyle(.secondary)
                    Button(model.actionTitle) { model.toggleRecording() }.buttonStyle(.borderedProminent).tint(.orange).disabled(model.isBusy)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            HStack(spacing: 14) {
                MetricCard(title: "Words dictated", value: "\(store.usage.words)")
                MetricCard(title: "Average WPM", value: "\(store.usage.wordsPerMinute)")
                MetricCard(title: "Active days", value: "\(store.usage.activeDays.count)")
            }
            if !model.transcript.isEmpty { GroupBox("Latest local transcription") { Text(model.transcript).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(6) } }
            Text("English only · Local processing · Nothing is sent").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(30)
    }
}

private struct InsightsView: View {
    @ObservedObject private var store = LocalStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Insights").font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Real activity stored only on this Mac.").foregroundStyle(.secondary)
            HStack(spacing: 14) {
                MetricCard(title: "Sessions", value: "\(store.usage.sessions)")
                MetricCard(title: "Words", value: "\(store.usage.words)")
                MetricCard(title: "WPM", value: "\(store.usage.wordsPerMinute)")
                MetricCard(title: "Days", value: "\(store.usage.activeDays.count)")
            }
            GroupBox("How this is calculated") {
                Text("OpenVoiceFlow records session duration and word count after a completed local transcription. It does not upload analytics or store transcript history by default.")
                    .foregroundStyle(.secondary).padding(6)
            }
            Spacer()
        }.padding(30)
    }
}

private struct DictionaryView: View {
    @ObservedObject private var store = LocalStore.shared
    @State private var newTerm = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Dictionary").font(.system(size: 30, weight: .bold, design: .rounded)); Spacer(); TextField("Add a name or term", text: $newTerm).textFieldStyle(.roundedBorder).frame(width: 230); Button("Add") { store.addTerm(newTerm); newTerm = "" }.disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            Text("Personal spellings stay on this Mac. New correction learning is always reviewable.").foregroundStyle(.secondary)
            List { ForEach(store.dictionary) { term in VStack(alignment: .leading) { Text(term.word).fontWeight(.semibold); Text("\(term.source) · used \(term.uses) times").font(.caption).foregroundStyle(.secondary) } }.onDelete(perform: store.deleteTerms) }
            Spacer()
        }.padding(30)
    }
}

private struct ProfileView: View {
    @ObservedObject private var store = LocalStore.shared
    @State private var name = ""
    @State private var role = ""
    var body: some View {
        Form {
            Section("Local profile") {
                Text("OpenVoiceFlow uses this only to personalize this Mac. It is not an account.").foregroundStyle(.secondary)
                TextField("Name", text: $name)
                TextField("Role or focus", text: $role)
                Button("Save profile") { store.updateProfile(name: name, role: role) }
            }
        }.formStyle(.grouped).navigationTitle("Profile").onAppear { name = store.profile.displayName; role = store.profile.role }
    }
}

private struct SettingsView: View {
    @ObservedObject private var store = LocalStore.shared
    @ObservedObject private var model = AppModel.shared
    var body: some View {
        Form {
            Section("Dictation") { LabeledContent("Shortcut", value: "Control+Option+Space"); LabeledContent("Language", value: "English only"); Button("Test microphone") { model.testMicrophone() } }
            Section("Privacy") { Text("Audio and transcription are processed locally. Nothing is sent by this Store edition.").foregroundStyle(.secondary); Button("Erase all local app data", role: .destructive) { store.clearLocalData() } }
        }.formStyle(.grouped).navigationTitle("Settings")
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    var body: some View { VStack(alignment: .leading) { Text(value).font(.system(size: 28, weight: .bold)); Text(title).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14)) }
}

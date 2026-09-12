import AppKit
import SwiftUI

/// "Share" — presented from the sidebar, same treatment as Feedback.
///
/// The link is this device's own leaderboard identity turned into a URL (see
/// ReferralStore.swift): reusing that anonymous ID rather than standing up an
/// account system. Sharing it, and seeing whether it converts, both ride the
/// same Settings ▸ Privacy ▸ "Share anonymous usage & leaderboard rank"
/// toggle as the leaderboard — off, this pane asks you to turn it on instead
/// of quietly working around it.
struct ShareView: View {
    @ObservedObject var controller: AppController
    let onDismiss: () -> Void
    @ObservedObject private var referralClient: ReferralClient
    @ObservedObject private var analyticsIdentity: AnalyticsIdentityStore
    @State private var didCopy = false
    @Environment(\.colorScheme) private var scheme

    init(controller: AppController, onDismiss: @escaping () -> Void) {
        self.controller = controller
        self.onDismiss = onDismiss
        self.referralClient = controller.referralClient
        self.analyticsIdentity = controller.analyticsIdentity
    }

    private var dark: Bool { scheme == .dark }
    private var ink: Color { dark ? DT.inkDark : DT.inkLight }
    private var ink2: Color { dark ? DT.ink2Dark : DT.ink2Light }
    private var fill: Color { dark ? .white.opacity(0.06) : .black.opacity(0.05) }
    private var deviceId: String { analyticsIdentity.identity.deviceId }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Share OpenVoiceFlow").font(.system(size: 20, weight: .bold)).foregroundStyle(ink)
                Spacer()
                Button("Done") { onDismiss() }.buttonStyle(.plain).foregroundStyle(ink2)
            }

            if !controller.settings.shareAnalytics {
                sharingOffState
            } else {
                Text("Anyone who opens this link and installs shows up in your stats below.")
                    .font(.system(size: 13)).foregroundStyle(ink2)
                linkSection
                Divider()
                statsSection
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 480, height: 420)
        .background(SheetOutsideClickDismissal(onOutsideClick: onDismiss))
        .task(id: controller.settings.shareAnalytics) {
            guard controller.settings.shareAnalytics else { return }
            await referralClient.ensureLink(deviceId: deviceId)
            await referralClient.fetchStats(deviceId: deviceId)
        }
    }

    @ViewBuilder private var sharingOffState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sharing is off")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
            Text("Turn on \u{201C}Share anonymous usage & leaderboard rank\u{201D} in Settings ▸ Privacy to get a link and see who it brings in.")
                .font(.system(size: 13)).foregroundStyle(ink2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(fill))
    }

    @ViewBuilder private var linkSection: some View {
        if referralClient.isLoadingLink && referralClient.link == nil {
            Text("Creating your link…").font(.system(size: 13)).foregroundStyle(ink2)
        } else if let error = referralClient.linkError, referralClient.link == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(error).font(.system(size: 13)).foregroundStyle(ink2)
                Button("Try again") { Task { await referralClient.fetchLink(deviceId: deviceId) } }
                    .buttonStyle(.plain).foregroundStyle(dark ? DT.emberDark : DT.emberLight)
            }
        } else if let link = referralClient.link {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(link.url.absoluteString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(fill))

                HStack(spacing: 10) {
                    Button(didCopy ? "Copied" : "Copy Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
                        controller.usageCounters.record(.referralLinkShared)
                        didCopy = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            didCopy = false
                        }
                    }
                    .buttonStyle(.bordered)

                    ShareLink(item: link.url) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent).tint(DT.emberWave)

                    Spacer()
                }
            }
        }
    }

    @ViewBuilder private var statsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your stats").font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
            if referralClient.isLoadingStats && referralClient.stats == nil {
                Text("Loading…").font(.system(size: 13)).foregroundStyle(ink2)
            } else if let stats = referralClient.stats {
                HStack(spacing: 20) {
                    statTile(value: stats.clicks, label: stats.clicks == 1 ? "link open" : "link opens")
                    statTile(value: stats.installs, label: stats.installs == 1 ? "install" : "installs")
                }
            } else if let error = referralClient.statsError {
                Text(error).font(.system(size: 13)).foregroundStyle(ink2)
            }
        }
    }

    private func statTile(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.system(size: 22, weight: .bold)).foregroundStyle(ink)
            Text(label).font(.system(size: 12)).foregroundStyle(ink2)
        }
    }
}

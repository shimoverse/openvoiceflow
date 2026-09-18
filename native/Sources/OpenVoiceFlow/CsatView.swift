import AppKit
import SwiftUI

/// "How's OpenVoiceFlow treating you?" — a small card in the dashboard's
/// bottom-right corner: five stars, then an optional one-line comment.
///
/// It is deliberately quiet. It shows only when `CsatPrompt` says the person
/// has used the app enough for an opinion, sits below the content rather than
/// over it, and goes away for a month on dismiss or a season on send. The
/// only network call is `AnalyticsClient.submitCsat`, made when Send is
/// pressed; hovering and picking a star send nothing.
///
/// The rating shapes the reaction: five stars throws confetti across the
/// window (a static sparkle under Reduce Motion), four gets a warm pulse, three
/// or fewer turns the comment box into "What would make it better?" — the case
/// where the words matter most.
struct CsatView: View {
    @ObservedObject var controller: AppController
    let onClose: () -> Void

    static let maxCommentLength = 1000

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Stage: Equatable { case rating, comment, sending, thanks, failed }

    @State private var stage: Stage = .rating
    @State private var rating = 0
    @State private var hovered = 0
    @State private var comment = ""
    @State private var pulse = false
    /// Minted once per card so a retried Send lands on the same server row.
    @State private var responseId = UUID()
    @FocusState private var commentFocused: Bool

    private var dark: Bool { scheme == .dark }
    private var ink: Color { dark ? DT.inkDark : DT.inkLight }
    private var ink2: Color { dark ? DT.ink2Dark : DT.ink2Light }
    private var accent: Color { dark ? DT.emberDark : DT.emberLight }
    private var card: Color { dark ? DT.cardDark : DT.cardLight }
    private var hair: Color { dark ? .white.opacity(0.08) : .black.opacity(0.07) }
    private var fill: Color { dark ? .white.opacity(0.06) : .black.opacity(0.05) }

    private var canSend: Bool { rating > 0 && stage == .comment }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if stage == .thanks {
                Text(rating >= 4 ? "Thank you — that made our day." : "Thank you. We read every one of these.")
                    .font(.system(size: 12)).foregroundStyle(ink2)
                    .transition(.opacity)
            } else if stage == .failed {
                Text("Couldn’t send just now. Check your connection and try again.")
                    .font(.system(size: 12)).foregroundStyle(DT.errorAccent)
                Button("Try again") { Task { await send() } }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
            } else {
                stars
                if stage == .comment || stage == .sending {
                    commentField.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DT.rCard)
                .fill(card)
                .shadow(color: .black.opacity(dark ? 0.35 : 0.10), radius: 18, y: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: DT.rCard).stroke(hair, lineWidth: 1))
        .scaleEffect(pulse ? 1.03 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6), value: pulse)
        .animation(reduceMotion ? nil : DT.snap, value: stage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rate OpenVoiceFlow")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(stage == .thanks ? "Rating sent" : "How’s OpenVoiceFlow treating you?")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
            Spacer()
            Button {
                if stage != .thanks { controller.usageCounters.record(.csatDismissed) }
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ink2)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(fill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(stage == .thanks ? "Close" : "Not now")
            .help(stage == .thanks ? "Close" : "Not now")
        }
    }

    private var stars: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                let lit = star <= (hovered > 0 ? hovered : rating)
                Button { pick(star) } label: {
                    Image(systemName: lit ? "star.fill" : "star")
                        .font(.system(size: 20))
                        .foregroundStyle(lit ? accent : ink2.opacity(0.7))
                        .scaleEffect(lit && hovered == star ? 1.15 : 1)
                        .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6), value: lit)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(stage == .sending)
                .onHover { inside in
                    if stage == .sending { return }
                    hovered = inside ? star : (hovered == star ? 0 : hovered)
                }
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
            Spacer(minLength: 0)
            if rating > 0, stage == .rating || stage == .comment {
                Text(Self.caption(for: rating))
                    .font(.system(size: 11)).foregroundStyle(ink2)
                    .transition(.opacity)
            }
        }
    }

    private var commentField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                rating <= 3 ? "What would make it better?" : "Anything you’d like us to know?",
                text: $comment,
                axis: .vertical
            )
            .lineLimit(2...4)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .focused($commentFocused)
            .disabled(stage == .sending)
            .onChange(of: comment) { _, value in
                if value.count > Self.maxCommentLength { comment = String(value.prefix(Self.maxCommentLength)) }
            }
            HStack {
                Text("Optional. Nothing is sent until you press Send.")
                    .font(.system(size: 10)).foregroundStyle(ink2)
                Spacer()
                Button {
                    Task { await send() }
                } label: {
                    Text(stage == .sending ? "Sending…" : "Send")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private static func caption(for rating: Int) -> String {
        switch rating {
        case 5: return "Love it"
        case 4: return "Pretty good"
        case 3: return "It’s fine"
        case 2: return "Not great"
        default: return "Frustrating"
        }
    }

    private func pick(_ star: Int) {
        rating = star
        hovered = 0
        if stage == .rating { stage = .comment }
        if star == 5 {
            // Confetti is drawn by the parent (it has to cover the window, not
            // the card) — announce it rather than draw it here.
            NotificationCenter.default.post(name: .csatCelebrate, object: nil)
        } else if star == 4 && !reduceMotion {
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { pulse = false }
        }
        DispatchQueue.main.async { commentFocused = true }
    }

    private func send() async {
        guard rating > 0 else { return }
        stage = .sending
        let ok = await controller.analyticsClient.submitCsat(
            responseId: responseId, rating: rating, comment: comment, controller: controller
        )
        guard ok else { stage = .failed; return }
        controller.usageCounters.record(.csatSubmitted)
        controller.settings.csatNextPromptAt = CsatPrompt.nextPrompt(afterSubmitAt: Date())
        controller.settings.save()
        stage = .thanks
        try? await Task.sleep(for: .seconds(2.4))
        onClose()
    }
}

extension Notification.Name {
    /// Posted by CsatView on a five-star pick; DashboardView answers with a
    /// window-wide ConfettiBurst.
    static let csatCelebrate = Notification.Name("ovf.csat.celebrate")
}

/// A one-shot confetti shower drawn over the whole window.
///
/// Pure Canvas: a fixed set of pieces, each with its own launch angle, speed,
/// spin and colour, integrated analytically from the start time — no per-frame
/// state, so it is cheap and deterministic. Under Reduce Motion the caller
/// shows nothing at all; celebration is not worth a motion trigger.
struct ConfettiBurst: View {
    let startedAt: Date
    static let duration: TimeInterval = 2.6

    private struct Piece {
        let x0: Double      // launch x as a fraction of width
        let vx: Double      // points / second
        let vy: Double      // points / second, negative = up
        let spin: Double    // radians / second
        let size: Double
        let hue: Double
        let delay: Double
    }

    private static let pieces: [Piece] = {
        var rng = SystemRandomNumberGenerator()
        return (0..<110).map { i in
            let fromLeft = i % 2 == 0
            return Piece(
                x0: fromLeft ? Double.random(in: 0.0...0.12, using: &rng) : Double.random(in: 0.88...1.0, using: &rng),
                vx: (fromLeft ? 1 : -1) * Double.random(in: 180...520, using: &rng),
                vy: -Double.random(in: 520...900, using: &rng),
                spin: Double.random(in: -9...9, using: &rng),
                size: Double.random(in: 5...9, using: &rng),
                hue: Double.random(in: 0...1, using: &rng),
                delay: Double.random(in: 0...0.25, using: &rng)
            )
        }
    }()

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(startedAt)
            Canvas { ctx, size in
                let gravity = 1400.0
                for piece in Self.pieces {
                    let age = t - piece.delay
                    guard age > 0 else { continue }
                    let x = piece.x0 * size.width + piece.vx * age
                    let y = size.height * 0.62 + piece.vy * age + 0.5 * gravity * age * age
                    guard y < size.height + 20, x > -20, x < size.width + 20 else { continue }
                    let fade = max(0, min(1, (Self.duration - t) / 0.6))
                    var transform = CGAffineTransform(translationX: x, y: y)
                    transform = transform.rotated(by: piece.spin * age)
                    // Flip on the y axis as it spins so pieces read as flat
                    // paper catching the light rather than spinning dots.
                    transform = transform.scaledBy(x: 1, y: abs(cos(piece.spin * age * 0.7)) * 0.8 + 0.2)
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size * 0.35, width: piece.size, height: piece.size * 0.7)
                    let path = Path(roundedRect: rect, cornerRadius: 1.2).applying(transform)
                    ctx.fill(path, with: .color(Color(hue: piece.hue, saturation: 0.75, brightness: 0.95).opacity(fade)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

import SwiftUI

/// The resolved app icon with a neutral glyph only for genuinely unknown names.
@MainActor
struct AppIdentityIcon: View {
    let name: String
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(4, size * 0.22))
                .fill(.white)
            if let nsImage = AppIconProvider.icon(for: name) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .padding(max(1, size * 0.08))
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.22)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.22)))
        .accessibilityHidden(true)
    }
}

/// Shared icon-plus-name treatment for every dictated-into app label.
@MainActor
struct AppIdentityLabel: View {
    let name: String
    var iconSize: CGFloat = 18
    var spacing: CGFloat = 7
    var ringFraction: Double?
    var ringColor: Color = .accentColor
    var trackColor: Color = .clear

    var body: some View {
        HStack(spacing: spacing) {
            leadingIcon
            Text(name).lineLimit(1)
        }
    }

    @ViewBuilder private var leadingIcon: some View {
        if let ringFraction {
            ZStack {
                Circle().stroke(trackColor, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(ringFraction, 0.03))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                AppIdentityIcon(name: name, size: iconSize - 6)
                    .clipShape(Circle())
            }
            .frame(width: iconSize, height: iconSize)
        } else {
            AppIdentityIcon(name: name, size: iconSize)
        }
    }
}

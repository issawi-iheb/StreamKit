import SwiftUI

enum DemoPalette {
    static let accent = Color(red: 0.08, green: 0.58, blue: 0.54)
    static let accentBright = Color(red: 0.10, green: 0.70, blue: 0.63)
    static let accentDeep = Color(red: 0.04, green: 0.40, blue: 0.47)
}

enum DemoLayoutMetrics {
    static let pageMaximumWidth: CGFloat = 1080
    static let widePageMaximumWidth: CGFloat = 1200
    static let pageHorizontalInset: CGFloat = 20
    static let pageVerticalInset: CGFloat = 20
    static let pageSectionSpacing: CGFloat = 20
    static let panelSpacing: CGFloat = 12
    static let cardCornerRadius: CGFloat = 20
}

struct DemoScrollContainer<Content: View>: View {
    private let maximumWidth: CGFloat
    private let content: Content

    init(
        maximumWidth: CGFloat = DemoLayoutMetrics.pageMaximumWidth,
        @ViewBuilder content: () -> Content
    ) {
        self.maximumWidth = maximumWidth
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoLayoutMetrics.pageSectionSpacing) {
                content
            }
            .demoReadableContent(maximumWidth: maximumWidth)
            .padding(.horizontal, DemoLayoutMetrics.pageHorizontalInset)
            .padding(.vertical, DemoLayoutMetrics.pageVerticalInset)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

struct DemoScreenHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(DemoPalette.accent)

            Text(title)
                .font(.system(.title, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct DemoPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.72))
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DemoPalette.accentBright, DemoPalette.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.56)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(.white.opacity(configuration.isPressed ? 0.22 : 0.12), lineWidth: 1)
            }
            .shadow(
                color: DemoPalette.accentDeep.opacity(isEnabled ? (configuration.isPressed ? 0.12 : 0.24) : 0.08),
                radius: isEnabled && !configuration.isPressed ? 10 : 3,
                x: 0,
                y: configuration.isPressed ? 2 : 5
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct DemoSecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(DemoPalette.accentDeep.opacity(isEnabled ? 1 : 0.55))
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(DemoPalette.accent.opacity(configuration.isPressed ? 0.12 : 0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(DemoPalette.accent.opacity(isEnabled ? 0.28 : 0.12), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct DemoPlaybackActions: View {
    let onPlay: () -> Void
    let onPause: () -> Void
    var isPlayDisabled = false
    var isPauseDisabled = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill")
            }
            .demoPrimaryActionButtonStyle()
            .disabled(isPlayDisabled)

            Button(action: onPause) {
                Label("Pause", systemImage: "pause.fill")
            }
            .demoSecondaryActionButtonStyle()
            .disabled(isPauseDisabled)
        }
    }
}

struct DemoPanel<Content: View>: View {
    private let title: String
    private let symbol: String?
    private let content: Content

    init(
        _ title: String,
        symbol: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DemoLayoutMetrics.panelSpacing) {
            if let symbol {
                Label(title, systemImage: symbol)
                    .font(.headline)
            } else {
                Text(title)
                    .font(.headline)
            }

            content
        }
        .demoCardSurface()
        .tint(DemoPalette.accent)
    }
}

struct DemoInlineNotice: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                .red.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}

struct DemoCardSurface: ViewModifier {
    var cornerRadius: CGFloat = DemoLayoutMetrics.cardCornerRadius

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.045), lineWidth: 1)
            }
    }
}

struct DemoPlayerSurface: ViewModifier {
    var maximumWidth: CGFloat = DemoLayoutMetrics.pageMaximumWidth

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maximumWidth)
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(.black, in: RoundedRectangle(cornerRadius: DemoLayoutMetrics.cardCornerRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: DemoLayoutMetrics.cardCornerRadius, style: .continuous))
    }
}

extension View {
    func demoPrimaryActionButtonStyle() -> some View {
        buttonStyle(DemoPrimaryActionButtonStyle())
    }

    func demoSecondaryActionButtonStyle() -> some View {
        buttonStyle(DemoSecondaryActionButtonStyle())
    }

    func demoCardSurface(cornerRadius: CGFloat = DemoLayoutMetrics.cardCornerRadius) -> some View {
        modifier(DemoCardSurface(cornerRadius: cornerRadius))
    }

    func demoPlayerSurface(maximumWidth: CGFloat = DemoLayoutMetrics.pageMaximumWidth) -> some View {
        modifier(DemoPlayerSurface(maximumWidth: maximumWidth))
    }

    func demoReadableContent(maximumWidth: CGFloat = 960) -> some View {
        frame(maxWidth: maximumWidth)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

import SwiftUI

struct DemoScreenHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.tint)

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
        VStack(alignment: .leading, spacing: 12) {
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
    }
}

struct DemoCardSurface: ViewModifier {
    var cornerRadius: CGFloat = 20

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
    var maximumWidth: CGFloat = 1080

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maximumWidth)
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func demoCardSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(DemoCardSurface(cornerRadius: cornerRadius))
    }

    func demoPlayerSurface(maximumWidth: CGFloat = 1080) -> some View {
        modifier(DemoPlayerSurface(maximumWidth: maximumWidth))
    }

    func demoReadableContent(maximumWidth: CGFloat = 960) -> some View {
        frame(maxWidth: maximumWidth)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

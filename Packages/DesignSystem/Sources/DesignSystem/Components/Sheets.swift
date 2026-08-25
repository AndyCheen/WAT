import SwiftUI

/// Нижня шторка з макетів: радіус 32 зверху, ручка, димка, пружинна поява.
/// Власна, а не системна — системна не дає такої геометрії й тіні.
public struct WTSheet<Content: View>: View {
    @Environment(\.wtTheme) private var theme
    private let maxHeightFraction: CGFloat?
    private let onDismiss: () -> Void
    private let content: Content

    public init(
        maxHeightFraction: CGFloat? = nil,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.maxHeightFraction = maxHeightFraction
        self.onDismiss = onDismiss
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                WTColor.scrim
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                    .transition(.opacity)

                VStack(spacing: 0) {
                    Capsule()
                        .fill(theme.track)
                        .frame(width: 44, height: 5)
                        .padding(.top, 26)
                        .padding(.bottom, 20)

                    if let maxHeightFraction {
                        ScrollView { content }
                            .frame(maxHeight: proxy.size.height * maxHeightFraction)
                    } else {
                        content
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 42)
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: WTRadius.sheet,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: WTRadius.sheet,
                        style: .continuous
                    )
                    .fill(theme.sheet)
                )
                .wtShadow(.sheet)
                .transition(.move(edge: .bottom))
            }
        }
        .ignoresSafeArea()
    }
}

/// Центральна модалка (макети 2e і 4a).
public struct WTModal<Content: View>: View {
    @Environment(\.wtTheme) private var theme
    private let maxWidth: CGFloat
    private let onDismiss: () -> Void
    private let content: Content

    public init(maxWidth: CGFloat = 280, onDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.onDismiss = onDismiss
        self.content = content()
    }

    public var body: some View {
        ZStack {
            WTColor.modalScrim
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            content
                .padding(.vertical, 28)
                .padding(.horizontal, 22)
                .frame(maxWidth: maxWidth)
                .background(theme.sheet, in: RoundedRectangle(cornerRadius: WTRadius.card, style: .continuous))
                .wtShadow(.modal)
                .padding(24)
        }
        .transition(.opacity)
    }
}

/// Заголовок усередині шторки: назва + необовʼязковий підзаголовок.
public struct WTSheetTitle: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(WTFont.display(22, .semibold))
                .foregroundStyle(theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(WTFont.text(14, .bold))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

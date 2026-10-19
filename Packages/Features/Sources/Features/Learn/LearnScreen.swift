import SwiftUI
import DesignSystem

/// Розділ «Знання» — бібліотека історій (SPEC-LEARN §3; макет Design/Learn.html, варіант A, рішення від
/// 19.10.2026): «Продовжити» для незакінченої й полиці обкладинок, що гортаються вбік.
public struct LearnScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: LearnLibraryModel
    private let onBack: () -> Void
    private let onOpen: (String) -> Void

    public init(services: AppServices, onBack: @escaping () -> Void, onOpen: @escaping (String) -> Void) {
        _model = State(initialValue: LearnLibraryModel(services: services))
        self.onBack = onBack
        self.onOpen = onOpen
    }

    public var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    WTNavBar(title: "Знання", onBack: onBack)
                        .padding(.bottom, 20)
                    if let resume = model.resume {
                        Button { onOpen(resume.story.id) } label: {
                            WTLearnContinueCard(
                                kicker: "Продовжити",
                                title: resume.story.title,
                                caption: "\(resume.slide) з \(resume.count - 1)",
                                fraction: Double(resume.slide) / Double(max(1, resume.count - 1)),
                                style: resume.story.shelf.style
                            ) {
                                if resume.story.shelf == .body { WTLearnDrop(level: 0.5) } else { WTLearnEmoji(resume.story.emoji) }
                            }
                        }
                        .buttonStyle(WTPressStyle(scale: 0.98))
                        .accessibilityIdentifier("learn.continue")
                        .padding(.bottom, 6)
                    }
                    ForEach(model.shelves) { shelf in
                        shelfView(shelf)
                    }
                }
                .wtScreenTopPadding()
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.bottom, WTSpacing.screenBottom)
                .wtNoTopOverscroll()
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("learn.screen")
        }
        .onAppear { model.reload() }
    }

    private func shelfView(_ shelf: LearnLibraryModel.Shelf) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(shelf.shelf.title.uppercased())
                    .font(WTFont.text(13, .black))
                    .tracking(0.3)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("\(shelf.readCount) з \(shelf.entries.count)")
                    .font(WTFont.text(12, .heavy))
                    .foregroundStyle(theme.textMuted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shelf.entries) { entry in
                        Button { onOpen(entry.story.id) } label: {
                            WTLearnCover(emoji: entry.story.emoji, title: entry.story.title,
                                         caption: "\(entry.story.minutes) хв", style: entry.story.shelf.style,
                                         badge: entry.badge, isDraft: Self.showsDraftMark && entry.story.isDraft)
                        }
                        .buttonStyle(WTPressStyle(scale: 0.96))
                        .accessibilityIdentifier("learn.story.\(entry.story.id)")
                    }
                }
                .padding(.horizontal, WTSpacing.screenSide)
                // Тінь обкладинок не обрізати краєм стрічки.
                .padding(.vertical, 14)
            }
            .padding(.horizontal, -WTSpacing.screenSide)
            .padding(.vertical, -14)
        }
        .padding(.top, 24)
    }

    /// Мітка «чернетка» на обкладинках — лише в DEBUG (SPEC-LEARN §5.3): тестувальник бачить, що текст
    /// ще не вичитано, а в збірці для людей мітки немає.
    private static var showsDraftMark: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

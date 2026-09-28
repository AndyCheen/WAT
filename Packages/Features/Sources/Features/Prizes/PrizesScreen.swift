import SwiftUI
import Gamification
import DesignSystem

/// Екран «Призи» (SPEC-PRIZES §5): «Діє зараз» і «Готові до використання».
///
/// Жодних перемикачів і фільтрів: при двох видах призів фільтр був би контролом
/// заради контролу. Вміст збігається з блоком 3f, але 3f з часом почне обрізатися,
/// а сюди модуль росте без переверстки «Прогресу».
public struct PrizesScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: PrizeInventoryModel
    private let onBack: () -> Void

    public init(services: AppServices, onBack: @escaping () -> Void) {
        _model = State(initialValue: PrizeInventoryModel(services: services))
        self.onBack = onBack
    }

    public var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    WTNavBar(title: "Призи", onBack: onBack)
                        .padding(.bottom, 20)

                    if model.inventory.isEmpty {
                        emptyState
                    } else {
                        activeSection
                        readySection
                    }
                }
                .wtScreenTopPadding()
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.bottom, WTSpacing.screenBottom)
                .wtNoTopOverscroll()
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("prizes.screen")

            if let selection = model.selected {
                PrizeDetailModal(model: model, selection: selection)
            }
        }
        .onAppear { model.reloadMarkingSeen() }
        .wtFeedback(trigger: model.selected?.id) { $0 == nil ? nil : .tap }
        .wtFeedback(trigger: model.feedback) { $0?.feedback }
    }

    // MARK: - Секції

    @ViewBuilder
    private var activeSection: some View {
        if !model.inventory.active.isEmpty {
            WTSectionLabel("ДІЄ ЗАРАЗ")
                .padding(.bottom, 8)
            TimelineView(.periodic(from: model.now, by: 60)) { _ in
                let now = model.now
                let presenter = model.presenter
                VStack(spacing: 8) {
                    ForEach(model.inventory.active) { prize in
                        WTPrizeActiveCard(
                            emoji: prize.emoji,
                            title: prize.title,
                            subtitle: presenter.activeSubtitle(prize),
                            remaining: PrizePresenter.shortDuration(prize.remaining(at: now)),
                            fraction: prize.remainingFraction(at: now),
                            accessibilityLabel: presenter.activeAccessibilityLabel(prize),
                            accessibilityValue: presenter.activeAccessibilityValue(prize, at: now),
                            identifier: "prizes.active",
                            onTap: { model.select(.active(prize)) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var readySection: some View {
        if !model.inventory.ready.isEmpty {
            WTSectionLabel("ГОТОВІ ДО ВИКОРИСТАННЯ")
                .padding(.top, model.inventory.active.isEmpty ? 0 : 22)
                .padding(.bottom, 4)
            PrizeStackRows(model: model, identifierPrefix: "prizes.row")
        }
    }

    /// Сюди можна потрапити, лише якщо останній приз використали, поки екран відкритий:
    /// з 3f без призів вхід прихований (§4.2). Без емодзі-ілюстрації — як у досягнень.
    private var emptyState: some View {
        Text("Зараз призів немає")
            .font(WTFont.text(13, .bold))
            .foregroundStyle(theme.textMuted)
            .frame(maxWidth: .infinity, minHeight: 140)
            .accessibilityIdentifier("prizes.empty")
    }
}

/// Рядки готових стосів — ті самі на 3f і на екрані «Призи».
struct PrizeStackRows: View {
    let model: PrizeInventoryModel
    let identifierPrefix: String

    var body: some View {
        let stacks = model.inventory.ready
        let presenter = model.presenter
        VStack(spacing: 0) {
            ForEach(Array(stacks.enumerated()), id: \.element.id) { index, stack in
                let subtitle = presenter.rowSubtitle(stack)
                WTPrizeRow(
                    emoji: stack.oldest.emoji,
                    title: stack.oldest.title,
                    subtitle: subtitle.text,
                    isSubtitleWarning: subtitle.isWarning,
                    count: stack.count,
                    isNew: stack.isNew,
                    showsDivider: index < stacks.count - 1,
                    accessibilityValue: presenter.rowAccessibilityValue(stack),
                    identifier: "\(identifierPrefix).\(stack.key)",
                    onTap: { model.select(.stack(stack)) }
                )
            }
        }
    }
}

import SwiftUI
import Core
import DesignSystem
import Gamification

/// Вікно «Шлях рівнів» (WAT-44, SPEC-PRIZES §16, макет Design/LevelRoad.html, варіант A «Драбина»).
///
/// На весь екран, як «Склянка»: виїжджає знизу з 3f. Відкривається вже прокрученим — до призу, що чекає
/// дії, інакше до останнього отриманого. Призами тут не користуються — лише бачать шлях, забирають
/// вибір і відкривають таємні.
struct LevelRoadScreen: View {
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: LevelRoadModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()
            WTBubbles().ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                road
            }

            if model.showsGuide {
                WTXPGuide(
                    title: LevelRoadPresenter.guideTitle, rows: model.guideRows,
                    footnote: LevelRoadPresenter.guideFootnote, onClose: { model.setGuide(false) }
                )
                .zIndex(3)
            }
        }
        // Розкриття — накладкою, а не ще одним шаром `ZStack`: шар на весь екран змінював розкладку,
        // і шапка вікна стрибала під статус-бар.
        .overlay {
            if let reveal = model.reveal {
                WTMysteryReveal(
                    kicker: reveal.kicker, outcome: reveal.outcome,
                    buttonTitle: LevelRoadPresenter.doneTitle, onDone: { model.finishReveal() }
                )
                .transition(.opacity)
            }
        }
        .wtFeedback(trigger: model.feedback) { $0?.feedback }
    }

    // MARK: - Шапка

    /// Хрестик і «?» — однакові кола обабіч, тож шапка симетрична, а рівень — по центру.
    private var topBar: some View {
        HStack(alignment: .top) {
            WTCircleButton(action: onClose) {
                WTIcons.close(color: theme.accent)
            }
            .accessibilityLabel("Закрити")
            .accessibilityIdentifier("levelRoad.close")
            Spacer(minLength: 8)
            VStack(spacing: 3) {
                Text(model.headerTitle)
                    .font(WTFont.display(22, .bold))
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("levelRoad.title")
                // Один `Text` із двох шрифтів: два поруч у `HStack` переносили «XP до рівня 18» на другий рядок.
                (Text(model.headerXp).font(WTFont.number(13, .semibold))
                    + Text(" " + model.headerXpSuffix).font(WTFont.text(13, .heavy)))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                WTProgressBar(fraction: model.road.progress.fraction, height: 6)
                    .frame(width: 180)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            WTCircleButton(action: { model.setGuide(true) }) {
                WTIcons.question(color: theme.accent)
            }
            .accessibilityLabel(LevelRoadPresenter.guideTitle)
            .accessibilityIdentifier("levelRoad.guideButton")
        }
        .padding(.horizontal, WTSpacing.screenSide)
        .padding(.bottom, 10)
    }

    // MARK: - Драбина

    private var road: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.rows) { row in
                        WTRoadRow(level: row.level, style: row.style, hasReward: row.hasReward,
                                  nodeCenterY: row.nodeCenterY) {
                            rowContent(row)
                        }
                        .id(row.level)
                    }
                    WTRoadEnd(LevelRoadPresenter.endTitle)
                }
                .wtRoadRail(position: model.railPosition)
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.top, 18)
                .padding(.bottom, WTSpacing.screenBottom)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Верх і низ стежки тануть під шапкою, а не обрізаються лінією.
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                            .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .accessibilityIdentifier("levelRoad.screen")
            .onAppear {
                // Без анімації: вікно має виїхати вже на місці, а не їхати до фокуса після появи.
                proxy.scrollTo(model.focusLevel, anchor: .center)
                model.replayProgress(reduceMotion: reduceMotion)
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ row: LevelRoadRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch row.content {
            case .none:
                EmptyView()
            case .start(let title):
                Text(title)
                    .font(WTFont.text(13, .heavy))
                    .foregroundStyle(theme.textMuted)
                    .padding(.top, 3)
            case let .card(icon, title, subtitle, tone, isGrand):
                WTRoadPrizeCard(icon: icon, title: title, subtitle: subtitle, tone: tone, isGrand: isGrand)
                    .accessibilityLabel(row.accessibilityLabel ?? title)
                    .accessibilityIdentifier("levelRoad.node.\(row.level)")
            case .choice(let options):
                let selected = model.selectedKey(level: row.level)
                let done = model.claimedLevel == row.level
                WTRoadChoiceCard(
                    title: LevelRoadPresenter.choiceTitle,
                    subtitle: LevelRoadPresenter.choiceSubtitle(selected: selected, done: done),
                    takeTitle: LevelRoadPresenter.takeTitle, options: options,
                    selectedId: selected, isDone: done,
                    identifierPrefix: "levelRoad.choice.\(row.level)",
                    onSelect: { model.select(level: row.level, key: $0) },
                    onTake: { model.claim(level: row.level) }
                )
            case let .mystery(title, subtitle, isGrand):
                WTRoadMysteryCard(
                    title: title, subtitle: subtitle, buttonTitle: LevelRoadPresenter.openTitle, isGrand: isGrand,
                    buttonIdentifier: "levelRoad.mystery.\(row.level)",
                    onOpen: { model.open(level: row.level) }
                )
            }
            if row.isCurrent {
                WTRoadHerePill(label: LevelRoadPresenter.hereLabel, value: model.hereValue)
                    .accessibilityIdentifier("levelRoad.here")
            }
        }
    }
}

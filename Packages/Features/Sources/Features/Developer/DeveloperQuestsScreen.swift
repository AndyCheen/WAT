import SwiftUI
import Persistence
import Gamification
import DesignSystem

/// Режим розробника → «Завдання» (WAT-68): що видано сьогодні й цього тижня — з усіма станами, — і будь-яке завдання
/// каталогу на видачу. Параметри (T, блок, N) — як у пікера, без відбору.
struct DeveloperQuestsScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: DeveloperModel
    @State private var notice: String?
    private let onBack: () -> Void

    init(services: AppServices, onBack: @escaping () -> Void) {
        _model = State(initialValue: DeveloperModel(services: services))
        self.onBack = onBack
    }

    var body: some View {
        DeveloperPageLayout(title: "Завдання", onBack: onBack) {
            current
            ForEach([QuestScope.daily, .weekly, .adhoc], id: \.self) { scope in
                catalog(scope)
            }
        }
        .onAppear { model.reload() }
        .onChange(of: model.epoch) { model.reload() }
    }

    private var current: some View {
        DeveloperSection(title: "ЗАРАЗ") {
            if let notice { DeveloperNote(notice) }
            if model.currentQuests.isEmpty {
                DeveloperNote("Сьогодні й цього тижня завдань ще немає — їх видає перша порція дня.")
            }
            ForEach(Array(model.currentQuests.enumerated()), id: \.element.id) { index, quest in
                if index > 0 { WTDivider() }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.questTitle(quest))
                            .font(WTFont.text(16, .bold))
                            .foregroundStyle(quest.state == .cancelled ? theme.textMuted : theme.textPrimary)
                        Text("\(quest.snapshot.key) · \(model.questProgress(quest))")
                            .font(WTFont.text(12, .semibold))
                            .foregroundStyle(theme.textMuted)
                    }
                    Spacer(minLength: 8)
                    if quest.state == .active {
                        WTSectionAction("Виконати") { model.complete(quest) }
                            .accessibilityIdentifier("developer.quest.complete.\(quest.snapshot.key)")
                    }
                    if quest.state != .cancelled {
                        WTSectionAction("Скасувати") { model.cancel(quest) }
                            .accessibilityIdentifier("developer.quest.cancel.\(quest.snapshot.key)")
                    }
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func catalog(_ scope: QuestScope) -> some View {
        DeveloperSection(title: "ВИДАТИ · \(DeveloperPresenter.scope(scope).uppercased())") {
            if scope == .adhoc {
                DeveloperNote("Несподіване — одне на день: чинне скасовується. «За 2 хв» — щоб побачити сповіщення "
                              + "й появу картки.")
            }
            ForEach(Array(model.catalog(scope).enumerated()), id: \.element.key) { index, definition in
                if index > 0 { WTDivider() }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DeveloperPresenter.questTemplate(definition.title))
                            .font(WTFont.text(16, .bold))
                            .foregroundStyle(theme.textPrimary)
                        Text(definition.key)
                            .font(WTFont.text(12, .semibold))
                            .foregroundStyle(theme.textMuted)
                    }
                    Spacer(minLength: 8)
                    if scope == .adhoc {
                        WTSectionAction("За 2 хв") { issue(definition.key, delayMinutes: 2) }
                            .accessibilityIdentifier("developer.quest.issueLater.\(definition.key)")
                    }
                    WTSectionAction(scope == .adhoc ? "Зараз" : "Видати") { issue(definition.key) }
                        .accessibilityIdentifier("developer.quest.issue.\(definition.key)")
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func issue(_ key: String, delayMinutes: Int = 0) {
        let issued = model.issue(key, delayMinutes: delayMinutes)
        withAnimation(WTAnimation.fade) {
            notice = issued ? nil : "Не вдалося видати «\(key)» — пікер не має для нього параметрів сьогодні."
        }
    }
}

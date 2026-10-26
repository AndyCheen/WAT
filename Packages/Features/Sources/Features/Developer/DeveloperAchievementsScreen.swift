import SwiftUI
import Gamification
import DesignSystem

/// Режим розробника → «Досягнення» (WAT-68): увесь каталог без маскування — таємні з назвою, пасхалки й зняті теж.
/// «Відкрити» показує вікно відкриття, як справжнє; «Закрити» знімає разом з XP.
struct DeveloperAchievementsScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: DeveloperModel
    private let onBack: () -> Void

    init(services: AppServices, onBack: @escaping () -> Void) {
        _model = State(initialValue: DeveloperModel(services: services))
        self.onBack = onBack
    }

    var body: some View {
        DeveloperPageLayout(title: "Досягнення", onBack: onBack) {
            filters
            list
        }
        .onAppear { model.reload() }
        .onChange(of: model.epoch) { model.reload() }
    }

    private var filters: some View {
        DeveloperSection(title: "ВІДКРИТО \(model.unlockedCount) З \(model.achievements.count)") {
            TextField("Пошук за назвою чи ключем", text: $model.search)
                .font(WTFont.text(16, .semibold))
                .foregroundStyle(theme.textPrimary)
                .wtPlainTextInput()
                .padding(.vertical, 12)
                .accessibilityIdentifier("developer.achievements.search")
            WTDivider()
            DeveloperChips(chips: DeveloperModel.AchievementFilter.allCases.map { filter in
                .init(id: "developer.achievements.filter.\(filter)", title: filter.title,
                      isSelected: model.achievementFilter == filter) { model.achievementFilter = filter }
            })
            DeveloperNote("Відкрите тут відкатом порції не знімається. Закрите відкриється знову з наступною дією, "
                          + "якщо умова вже виконана, — і вдруге отримає вікно.")
        }
    }

    private var list: some View {
        let achievements = model.visibleAchievements
        return WTCard {
            LazyVStack(alignment: .leading, spacing: 0) {
                if achievements.isEmpty { DeveloperNote("Нічого не знайдено.") }
                ForEach(Array(achievements.enumerated()), id: \.element.id) { index, achievement in
                    if index > 0 { WTDivider() }
                    row(achievement)
                }
            }
        }
    }

    private func row(_ achievement: DeveloperAchievement) -> some View {
        HStack(spacing: 12) {
            Text(achievement.emoji)
                .font(WTFont.text(26, .bold))
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(WTFont.text(16, .bold))
                    .foregroundStyle(theme.textPrimary)
                Text("\(achievement.key) · \(DeveloperPresenter.achievementState(achievement))")
                    .font(WTFont.text(12, .semibold))
                    .foregroundStyle(theme.textMuted)
            }
            Spacer(minLength: 8)
            WTSectionAction(achievement.isUnlocked ? "Закрити" : "Відкрити") {
                withAnimation(WTAnimation.fade) { model.toggle(achievement) }
            }
            .accessibilityIdentifier("developer.achievement.\(achievement.key)")
        }
        .padding(.vertical, 10)
    }
}

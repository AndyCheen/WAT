import SwiftUI
import Observation
import Persistence
import Gamification
import DesignSystem

@MainActor
@Observable
public final class AchievementsViewModel {
    private let services: AppServices

    public private(set) var items: [AchievementSnapshot] = []
    public var selectedCategory = 0
    public var selected: AchievementSnapshot?

    public init(services: AppServices) {
        self.services = services
        reload()
    }

    public func reload() {
        items = services.gamification.achievementSnapshots()
        services.gamification.markAchievementsSeen()
    }

    public var categories: [AchievementCategory] { AchievementCatalog.categories }

    public var filtered: [AchievementSnapshot] {
        guard selectedCategory > 0, selectedCategory < categories.count else { return items }
        let category = categories[selectedCategory]
        return items.filter { $0.category == category }
    }

    public var unlockedCount: Int { items.filter(\.isUnlocked).count }
    public var totalCount: Int { items.count }
    public var leftCount: Int { totalCount - unlockedCount }
}

/// Макет 2e — категорії + сітка плиток 3×N + модалка деталей.
public struct AchievementsScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: AchievementsViewModel
    private let onBack: () -> Void

    public init(services: AppServices, onBack: @escaping () -> Void) {
        _model = State(initialValue: AchievementsViewModel(services: services))
        self.onBack = onBack
    }

    public var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    WTNavBar(title: "Досягнення", onBack: onBack)
                        .padding(.bottom, 20)

                    progressCard
                    tabs
                    grid
                }
                .padding(.top, WTSpacing.screenTop)
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.bottom, WTSpacing.screenBottom)
            }

            if let selected = model.selected {
                detailModal(selected).zIndex(10)
            }
        }
        .onAppear { model.reload() }
    }

    private var progressCard: some View {
        HStack(spacing: 16) {
            WTCountRing(value: model.unlockedCount, total: model.totalCount)
            VStack(alignment: .leading, spacing: 2) {
                Text("Прогрес нагород")
                    .font(WTFont.display(17, .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("Ще \(model.leftCount) до повного набору")
                    .font(WTFont.text(13, .bold))
                    .foregroundStyle(theme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(theme.chip, in: RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous))
        .padding(.bottom, 20)
    }

    private var tabs: some View {
        WTSegmentedTabs(
            titles: model.categories.map(\.title),
            selection: model.selectedCategory,
            filled: true,
            onSelect: { model.selectedCategory = $0 }
        )
        .padding(.bottom, 18)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(model.filtered) { item in
                WTAchievementTile(
                    emoji: item.emoji,
                    title: item.title,
                    isUnlocked: item.isUnlocked,
                    fraction: item.fraction,
                    progressLabel: item.progressLabel,
                    onTap: { model.selected = item }
                )
            }
        }
    }

    private func detailModal(_ item: AchievementSnapshot) -> some View {
        WTModal(onDismiss: { model.selected = nil }) {
            VStack(spacing: 10) {
                Text(item.emoji)
                    .font(.system(size: 30))
                    .opacity(item.isUnlocked ? 1 : 0.4)
                    .frame(width: 64, height: 64)
                    .background(theme.chip, in: Circle())

                Text(item.title)
                    .font(WTFont.display(17, .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(item.details)
                    .font(WTFont.text(13, .semibold))
                    .foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center)

                Text(item.isUnlocked ? "Виконано" : "Потрібно: \(item.progressLabel)")
                    .font(WTFont.text(12, .heavy))
                    .foregroundStyle(item.isUnlocked ? WTColor.successText : theme.textMuted)
                    .padding(.top, 4)

                Button { model.selected = nil } label: {
                    Text("Закрити")
                        .font(WTFont.display(14, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
    }
}

import SwiftUI
import Observation
import Persistence
import Gamification
import DesignSystem

@MainActor
@Observable
public final class AchievementsViewModel {
    /// Порожній результат фільтрів — два різні випадки з різним виходом (SPEC-ACHIEVEMENTS §7.4).
    public enum EmptyState: Equatable {
        /// Перетин фільтрів нічого не дав → «Скинути фільтри».
        case filtered
        /// Просили відкриті, а відкритих немає взагалі → «Показати всі».
        case nothingUnlocked
    }

    private let services: AppServices

    /// Уже в порядку §3.4 — фільтри лише вирізають, не пересортовують.
    public private(set) var items: [AchievementSnapshot] = []
    public private(set) var stateFilter: AchievementStateFilter = .all
    /// `nil` — псевдо-категорія «Всі».
    public private(set) var category: AchievementCategory?
    public private(set) var isCategoryMenuOpen = false
    public private(set) var selected: AchievementSnapshot?

    /// Лише читає: позначення переглянутими — справа `reload()` з `onAppear`. Коли `init`
    /// теж позначав, друге читання в `onAppear` уже не бачило жодного нового, і крапки
    /// «нове» на 2e не зʼявлялись узагалі.
    public init(services: AppServices) {
        self.services = services
        items = services.gamification.achievementSnapshots().sortedForDisplay
    }

    /// Знімок береться до позначення переглянутими: крапки «нове» видно весь цей візит
    /// і гаснуть лише наступного разу.
    public func reload() {
        items = services.gamification.achievementSnapshots().sortedForDisplay
        services.gamification.markAchievementsSeen()
    }

    // MARK: - Фільтри

    public var categories: [AchievementCategory] { AchievementCatalog.categories }

    public var filtered: [AchievementSnapshot] {
        items.filter { stateFilter.matches($0) && (category == nil || $0.category == category) }
    }

    public var emptyState: EmptyState? {
        guard !items.isEmpty, filtered.isEmpty else { return nil }
        return stateFilter == .unlocked && unlockedCount == 0 ? .nothingUnlocked : .filtered
    }

    /// Рахунок глобальний, а не в поточному фільтрі: «скільки я зібрав» не має
    /// стрибати від натиснутого чипа (§5.2).
    public var unlockedCount: Int { items.filter(\.isUnlocked).count }
    public var totalCount: Int { items.count }

    public func selectState(_ filter: AchievementStateFilter) {
        withAnimation(WTAnimation.fade) { stateFilter = filter }
    }

    /// Вибір у меню одразу застосовується й закриває меню — одним тапом.
    public func selectCategory(_ category: AchievementCategory?) {
        withAnimation(WTAnimation.sheet) {
            self.category = category
            isCategoryMenuOpen = false
        }
    }

    public func resetFilters() {
        withAnimation(WTAnimation.fade) {
            stateFilter = .all
            category = nil
        }
    }

    public func setCategoryMenu(open: Bool) {
        withAnimation(WTAnimation.sheet) { isCategoryMenuOpen = open }
    }

    // MARK: - Картка

    /// Модалка деталей зʼявлялася без переходу — присвоєння йшло повз `withAnimation`.
    public func select(_ item: AchievementSnapshot?) {
        withAnimation(WTAnimation.fade) { selected = item }
    }
}

/// Макет 2e — лічильник набору, один ряд фільтрів, сітка плиток 3×N, картка деталей
/// (SPEC-ACHIEVEMENTS §5).
public struct AchievementsScreen: View {
    @Environment(\.wtTheme) private var theme
    @State private var model: AchievementsViewModel
    private let onBack: () -> Void

    /// Ключ «Всі» в меню категорій: псевдо-категорія, у `AchievementCategory` її немає.
    private static let allCategoriesKey = "all"

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
                        .padding(.bottom, 16)

                    WTStatCounter(label: "ВІДКРИТО", value: model.unlockedCount, total: model.totalCount)
                        .accessibilityLabel("Прогрес нагород")
                        .accessibilityValue("\(model.unlockedCount) з \(model.totalCount) відкрито")
                        .accessibilityIdentifier("achievements.counter")
                        .padding(.bottom, 20)

                    filters
                    content
                }
                .wtScreenTopPadding()
                .padding(.horizontal, WTSpacing.screenSide)
                .padding(.bottom, WTSpacing.screenBottom)
                .wtNoTopOverscroll()
            }
            // Bounce лише коли контент реально не влазить.
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("achievements.screen")

            if let selected = model.selected {
                AchievementDetailModal(item: selected, onClose: { model.select(nil) })
            }
        }
        .wtPopover(isPresented: model.isCategoryMenuOpen, onDismiss: { model.setCategoryMenu(open: false) }) {
            categoryMenu
        }
        .onAppear { model.reload() }
        .wtFeedback(trigger: model.selected?.key) { $0 == nil ? nil : .tap }
        .wtFeedback(.toggle, trigger: model.category)
    }

    // MARK: - Фільтри

    /// Два фільтри, але ряд контролів один: стан — чипами назовні (його перемикають часто),
    /// категорія — у меню за кнопкою праворуч (її вибирають рідше й лишають надовго).
    private var filters: some View {
        HStack(spacing: 10) {
            WTChipTabs(
                options: AchievementStateFilter.allCases.map { WTOption(id: $0.rawValue, title: $0.title) },
                selection: model.stateFilter.rawValue,
                identifierPrefix: "achievements.state",
                onSelect: { id in
                    if let filter = AchievementStateFilter(rawValue: id) { model.selectState(filter) }
                }
            )

            WTFilterButton(
                activeTitle: model.category?.title,
                accessibilityLabel: "Фільтр за категорією",
                identifier: "achievements.category",
                onOpen: { model.setCategoryMenu(open: true) },
                onClear: { model.selectCategory(nil) }
            )
            .wtPopoverAnchor()
        }
        .padding(.bottom, 18)
    }

    private var categoryMenu: some View {
        WTPopoverMenu(
            header: "КАТЕГОРІЯ",
            options: [WTOption(id: Self.allCategoriesKey, title: "Всі")]
                + model.categories.map { WTOption(id: Self.key(for: $0), title: $0.title) },
            selection: model.category.map(Self.key(for:)) ?? Self.allCategoriesKey,
            identifierPrefix: "achievements.category.option",
            onSelect: { id in
                model.selectCategory(model.categories.first { Self.key(for: $0) == id })
            }
        )
    }

    /// `general` / `streak` / `volume` — стабільні ключі для e2e, не залежні від заголовків.
    private static func key(for category: AchievementCategory) -> String {
        String(describing: category)
    }

    // MARK: - Сітка й порожні стани

    @ViewBuilder
    private var content: some View {
        switch model.emptyState {
        case .filtered:
            emptyState("У цьому фільтрі порожньо", action: "Скинути фільтри") { model.resetFilters() }
        case .nothingUnlocked:
            emptyState("Ще нічого не відкрито", action: "Показати всі") { model.selectState(.all) }
        case nil:
            grid
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(model.filtered) { item in
                WTAchievementTile(
                    emoji: item.emoji,
                    title: item.title,
                    isUnlocked: item.isUnlocked,
                    isNew: item.isNew,
                    fraction: item.fraction,
                    progressLabel: item.progressLabel,
                    accessibilityValue: item.progressAccessibilityValue,
                    onTap: { model.select(item) }
                )
                .accessibilityIdentifier("achievements.tile.\(item.key)")
            }
        }
    }

    /// Без емодзі-ілюстрацій: на екрані, де кожна емодзі — окреме досягнення, велика 🔍
    /// читалась би як ще одна плитка. Порожній стан пояснює й дає вихід, а не прикрашає.
    private func emptyState(_ title: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(WTFont.display(15, .semibold))
                .foregroundStyle(theme.textPrimary)
                .accessibilityIdentifier("achievements.empty")
            WTSectionAction(action, action: perform)
                .accessibilityIdentifier("achievements.empty.action")
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .transition(.opacity)
    }
}

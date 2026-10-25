import SwiftUI
import Core
import Persistence
import DesignSystem

public enum AppRoute: Hashable {
    case progress
    /// 3f з уже відкритим вікном «Шлях рівнів» — тост рівня з вибором чи 🎁 (SPEC-PRIZES §16.6).
    case levelRoad
    case achievements
    case prizes
    case stats
    /// Екран «Налаштування» (WAT-15).
    case settings
    /// «Кнопки порцій» з «Налаштувань» (WAT-45).
    case portionButtons
    /// Екран «Призи» з уже відкритою карткою — тап по порятунку серії веде в картку
    /// заморозки, бо заморожувати можна лише з неї (SPEC-NOTIFICATIONS §12.1).
    case prizeCard(String)
    /// Екран «Сповіщення» (§15.1).
    case notifications
    /// DEBUG: «План сповіщень» — заплановане з часами (§16.11).
    case notificationPlan
    /// Звіт-історія (§11.3). Кілька періодів — злите «Підсумки тижня й місяця» грає їх підряд.
    case report([ReportPeriod])
    /// DEBUG: усі віджети в системних розмірах — для e2e й перевірки без домашнього екрана (WAT-30).
    case widgetGallery
    /// «Знання» — бібліотека історій (SPEC-LEARN §3).
    case learn
    /// Одна історія — з бібліотеки чи контекстного входу; `slide` — `--start-screen learn:<id>:<слайд>`.
    case learnStory(String, slide: Int? = nil)

    /// Бібліотека й історії — щоб кнопка «Що з цим робити» прибирала їх зі стека (`RootView.navigate`).
    var isLearn: Bool {
        switch self {
        case .learn, .learnStory: return true
        default: return false
        }
    }
}

/// Кореневий екран: стек навігації 1a → 3f → 2e, 1a → 3f → «Призи», 1a → 4a (PLAN.md §8).
public struct RootView: View {
    @State private var services: AppServices
    @State private var path: [AppRoute] = []
    @State private var themeMode: ThemeMode
    @State private var hapticsEnabled: Bool
    /// Онбординг поверх усього (WAT-56): на першому запуску — сам, повторно — з «Налаштувань».
    @State private var onboarding: OnboardingModel?
    private let onboardingOnLaunch: OnboardingMode?

    /// - Parameter onboarding: відкрити онбординг одразу — перший запуск (`AppServices.shouldOpenOnboarding`)
    ///   чи прапорець `--start-screen onboarding` для e2e.
    public init(services: AppServices, initialRoute: AppRoute? = nil, onboarding: OnboardingMode? = nil) {
        _services = State(initialValue: services)
        _themeMode = State(initialValue: services.profile.themeMode)
        _hapticsEnabled = State(initialValue: services.profile.hapticsEnabled)
        _path = State(initialValue: initialRoute.map { [$0] } ?? [])
        onboardingOnLaunch = onboarding
    }

    public var body: some View {
        WTThemedContainer(mode: themeMode, hapticsEnabled: hapticsEnabled) {
            NavigationStack(path: $path) {
                HomeScreen(
                    services: services,
                    onOpenSettings: { path.append(.settings) },
                    onOpenProgress: { path.append(.progress) },
                    onOpenLevelRoad: { path.append(.levelRoad) },
                    onOpenStats: { path.append(.stats) },
                    onOpenPrize: { path.append(.prizeCard($0)) },
                    onOpenLearn: { path.append($0.map { .learnStory($0) } ?? .learn) },
                    // Поки відкритий онбординг, пропозиція графіка чекає — головний під ним не «чистий».
                    isOnTop: { path.isEmpty && onboarding == nil }
                )
                .wtHideNavigationBar()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(route).wtHideNavigationBar()
                }
            }
            // Усередині контейнера: тема (`wtTheme`) діє лише на його вміст.
            .overlay {
                if let onboarding {
                    OnboardingScreen(model: onboarding)
                        .transition(.move(edge: .bottom))
                        .zIndex(1)
                }
            }
            // Над усім — і над стеком, і над шторками, і над онбордингом (поки він відкритий, вікно чекає).
            .overlay { celebrationOverlay }
        }
        .onAppear {
            if let mode = onboardingOnLaunch, onboarding == nil { openOnboarding(mode, animated: false) }
        }
        .onChange(of: onboarding == nil, initial: true) { _, closed in
            if closed { services.endCelebrationPause(.onboarding) } else { services.beginCelebrationPause(.onboarding) }
        }
        // Тап по сповіщенню, зокрема той, що запустив застосунок: `initial` — бо при холодному
        // старті маршрут з'являється раніше за перший кадр.
        .onChange(of: services.router.pendingPath, initial: true) {
            if let route = services.router.takePath() { path = route }
        }
        // «Як риба у воді» (SPEC-ACHIEVEMENTS-CATALOG §4.10): кожен відкритий екран — раз назавжди.
        .onChange(of: path, initial: true) {
            if let screen = Self.screen(for: path.last) { services.record(.screenOpened(screen)) }
        }
    }

    // MARK: - Вікно відкриття (WAT-60)

    /// Вікно відкриття досягнень — над будь-яким екраном (SPEC-ACHIEVEMENTS §8). `id` — кожне вікно програє
    /// свою появу заново.
    @ViewBuilder
    private var celebrationOverlay: some View {
        if let celebration = services.celebration {
            WTCelebration(
                pages: celebration.pages,
                level: celebration.level,
                finishTitle: celebration.finishTitle,
                laterTitle: celebration.laterTitle,
                appearDelay: celebration.appearDelay,
                onFinish: { withAnimation(WTAnimation.fade) { services.dismissCelebration() } },
                onLater: { withAnimation(WTAnimation.fade) { services.dismissCelebration(later: true) } }
            )
            .id(celebration.id)
            .transition(.opacity)
            .zIndex(2)
        }
    }

    private static func screen(for route: AppRoute?) -> AppScreen? {
        switch route {
        case nil: return .home
        case .progress?: return .progress
        case .levelRoad?: return .levelRoad
        case .achievements?: return .achievements
        case .prizes?, .prizeCard?: return .prizes
        case .stats?: return .stats
        case .settings?: return .settings
        case .portionButtons?: return .portionButtons
        case .notifications?: return .notifications
        case .report?: return .report
        case .learn?, .learnStory?: return .learn
        case .notificationPlan?, .widgetGallery?: return nil
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .progress, .levelRoad:
            ProgressScreen(
                services: services,
                opensLevelRoad: route == .levelRoad,
                onBack: { path.removeLast() },
                onOpenAllAchievements: { path.append(.achievements) },
                onOpenAllPrizes: { path.append(.prizes) },
                onOpenLearn: { path.append(.learnStory($0)) }
            )
        case .achievements:
            AchievementsScreen(services: services, onBack: { path.removeLast() })
        case .prizes:
            PrizesScreen(services: services, onBack: { path.removeLast() }, onOpenLearn: { path.append(.learnStory($0)) })
        case .stats:
            StatsScreen(services: services, onBack: { path.removeLast() }, onOpenReport: { path.append(.report($0)) })
        case .prizeCard(let key):
            PrizesScreen(services: services, onBack: { path.removeLast() }, focusKey: key,
                         onOpenLearn: { path.append(.learnStory($0)) })
        case .settings:
            SettingsScreen(
                services: services,
                themeMode: $themeMode,
                hapticsEnabled: $hapticsEnabled,
                onBack: { path.removeLast() },
                onOpenNotifications: { path.append(.notifications) },
                onOpenPortionButtons: { path.append(.portionButtons) },
                onOpenLearn: { path.append(.learnStory($0)) },
                onOpenOnboarding: { openOnboarding(.revisit) }
            )
        case .portionButtons:
            PortionButtonsScreen(services: services, onBack: { path.removeLast() })
        case .notifications:
            NotificationsScreen(
                services: services,
                onBack: { path.removeLast() },
                onOpenPlan: { path.append(.notificationPlan) }
            )
        case .notificationPlan:
            NotificationPlanScreen(services: services, onBack: { path.removeLast() })
        case .report(let periods):
            ReportScreen(services: services, periods: periods, onClose: { path.removeLast() })
        case .widgetGallery:
            WidgetGalleryScreen(services: services, onBack: { path.removeLast() })
        case .learn:
            LearnScreen(services: services, onBack: { path.removeLast() }, onOpen: { path.append(.learnStory($0)) })
        case let .learnStory(id, slide):
            LearnStoryScreen(services: services, storyId: id, startSlide: slide, onClose: { path.removeLast() },
                             onNavigate: navigate)
        }
    }

    // MARK: - Онбординг

    private func openOnboarding(_ mode: OnboardingMode, animated: Bool = true) {
        let model = OnboardingModel(services: services, mode: mode) { exit in closeOnboarding(exit) }
        if animated {
            withAnimation(WTAnimation.sheet) { onboarding = model }
        } else {
            onboarding = model
        }
    }

    /// «Як користуватися» на фініші веде в історію «Перші кроки» (SPEC-LEARN §3.2) — уже під закритим онбордингом.
    private func closeOnboarding(_ exit: OnboardingModel.Exit) {
        withAnimation(WTAnimation.sheet) { onboarding = nil }
        if exit == .learn { path.append(.learnStory(Self.firstStepsStory)) }
    }

    static let firstStepsStory = "app.start"

    /// «Що з цим робити» в історії «Знань»: історія дочитана, тож «назад» з екрана дії веде не в неї, а туди,
    /// звідки людина прийшла в «Знання».
    private func navigate(_ destination: LearnDestination) {
        while path.last?.isLearn == true { path.removeLast() }
        let route: AppRoute?
        switch destination {
        case .home:
            path = []
            route = nil
        case .customAmount:
            path = []
            services.router.open(.customAmount(ml: services.hydration.customAmountStart()))
            route = nil
        case .stats: route = .stats
        case .settings: route = .settings
        case .portionButtons: route = .portionButtons
        case .notifications: route = .notifications
        case .levelRoad: route = .levelRoad
        case .prizes: route = .prizes
        case .story(let id): route = .learnStory(id)
        }
        // Прийшли зі «Шляху рівнів» чи «Призів» — повернутися туди, а не відкрити вдруге.
        if let route, path.last != route { path.append(route) }
    }
}

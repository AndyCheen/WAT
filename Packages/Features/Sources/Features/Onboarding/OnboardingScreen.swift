import SwiftUI
import Core
import DesignSystem

/// Онбординг на весь екран (WAT-56, SPEC-ONBOARDING). Дизайн — за тимчасовим перемикачем `OnboardingDesign`
/// до вибору остаточного в WAT-57; кроки, тексти й логіка в обох спільні.
public struct OnboardingScreen: View {
    @Bindable private var model: OnboardingModel
    private let design: OnboardingDesign
    private typealias P = OnboardingPresenter

    public init(model: OnboardingModel, design: OnboardingDesign = .current) {
        self.model = model
        self.design = design
    }

    public var body: some View {
        ZStack {
            switch design {
            case .scene: OnboardingSceneView(model: model)
            case .steps: OnboardingStepsView(model: model)
            }
            if model.isConfirmingExit {
                WTModal(maxWidth: 320, onDismiss: model.stay) {
                    exitDialog
                }
            }
        }
    }

    private var exitDialog: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(P.exitTitle)
                .font(WTFont.display(20, .bold))
            Text(P.exitMessage)
                .font(WTFont.text(14, .bold))
                .opacity(0.7)
                .padding(.bottom, 10)
            WTPrimaryButton(P.exitConfirm, action: model.confirmExit)
                .accessibilityIdentifier("onboarding.exit.confirm")
            Button(P.exitStay, action: model.stay)
                .font(WTFont.text(15, .heavy))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(WTPressStyle())
                .accessibilityIdentifier("onboarding.exit.stay")
        }
        .modifier(DialogInk())
    }

    /// Кольори діалогу — з теми, як у решти модалок.
    private struct DialogInk: ViewModifier {
        @Environment(\.wtTheme) private var theme
        func body(content: Content) -> some View { content.foregroundStyle(theme.textPrimary) }
    }
}

// MARK: - «Сцена»

/// Угорі ілюстрація кроку на тлі розділу, унизу — питання на панелі (рішення від 19.10.2026).
struct OnboardingSceneView: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: OnboardingModel

    var body: some View {
        WTSceneLayout(style: style, sceneFraction: sceneFraction) {
            // На вітанні й фініші першого запуску панелі немає зовсім — не лише прозорої: інакше в дереві
            // доступності було б друге «Пропустити».
            if !model.hidesTopBar { topBar }
        } scene: {
            OnboardingSceneArt(model: model)
        } panel: {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        OnboardingStepBody(model: model, design: .scene)
                            .padding(.horizontal, WTSpacing.screenSide)
                            .padding(.top, WTSpacing.cardPaddingV)
                            .padding(.bottom, WTSpacing.cardPaddingH)
                            .id(model.step)
                            .transition(OnboardingTransition.step(forward: model.movesForward))
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: model.expansion) { old, new in OnboardingTransition.reveal(old, new, proxy) }
                }
                OnboardingFooter(model: model)
                    .padding(.horizontal, WTSpacing.screenSide)
            }
        }
    }

    /// Тло — ті самі стилі, що в «Знаннях»: вода для норми, тепле для дня, глибоке до нічного неба для нагадувань.
    private var style: WTStoryStyle {
        switch model.step.chapter {
        case .norm?: return .learnWater
        case .day?: return .learnWarm
        case .reminders?: return .learnDeep
        case .units?, nil: return .water
        }
    }

    /// Частка екрана під сцену: чим більше контролів у кроку, тим нижча сцена. Панель усе одно гортається.
    private var sceneFraction: CGFloat {
        let answers = model.draft.answers
        switch model.step {
        case .hello: return model.mode == .firstRun ? 0.6 : 0.3
        case .units: return 0.38
        case .gender: return answers.gender == .female ? 0.34 : 0.36
        case .age: return 0.38
        case .weight: return 0.46
        case .activity: return 0.38
        case .goal: return model.offersGoalChoice ? 0.32 : 0.38
        case .day: return answers.week.weekendEnabled ? 0.34 : 0.38
        case .rhythm: return 0.44
        case .glass: return 0.5
        case .reminders: return 0.56
        case .done: return 0.3
        }
    }

    private var topBar: some View {
        let onColor = style.isOnColor
        return HStack {
            WTBarButton(.back, onColor: onColor, action: model.back)
                .accessibilityIdentifier("onboarding.back")
            Spacer()
            OnboardingTrailingButton(model: model, onColor: onColor)
        }
        .overlay {
            WTPageDots(count: model.questionCount, current: model.questionNumber ?? model.questionCount + 1,
                       color: onColor ? .white : theme.accent)
        }
        .padding(.horizontal, WTSpacing.cardPaddingH / 2)
        .transition(.opacity)
    }
}

// MARK: - «Кроки»

/// Світлий екран, картки варіантів, смуга прогресу з розділів — альтернатива за тимчасовим перемикачем.
struct OnboardingStepsView: View {
    @Environment(\.wtTheme) private var theme
    @Bindable var model: OnboardingModel

    var body: some View {
        ZStack {
            theme.screen.ignoresSafeArea()
            WTBubbles().ignoresSafeArea()
            VStack(spacing: 0) {
                // Те саме, що в «Сцені»: прихованої панелі немає в дереві, а місце під нею лишається.
                ZStack {
                    if !model.hidesTopBar { topBar.transition(.opacity) }
                }
                .frame(minHeight: WTSpacing.screenTop - WTSpacing.cardPaddingV)
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            OnboardingStepBody(model: model, design: .steps)
                                .padding(.vertical, WTSpacing.cardPaddingV)
                                .frame(minHeight: geometry.size.height, alignment: centersContent ? .center : .top)
                                .id(model.step)
                                .transition(OnboardingTransition.step(forward: model.movesForward))
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .onChange(of: model.expansion) { old, new in OnboardingTransition.reveal(old, new, proxy) }
                    }
                }
                OnboardingFooter(model: model)
            }
            .padding(.horizontal, WTSpacing.screenSideHome)
        }
    }

    /// Вітання й фініш — посередині, як вікна «Склянка» й «Графік дня»; питання — від верху.
    private var centersContent: Bool {
        model.step == .hello || (model.step == .done && (model.mode == .firstRun || model.changes.isEmpty))
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            WTBarButton(.back, onColor: false, action: model.back)
                .accessibilityIdentifier("onboarding.back")
            WTSegmentedProgress(segments: OnboardingChapter.allCases.map {
                WTSegmentedProgress.Segment(weight: OnboardingCatalog.steps(in: $0).count, fraction: model.progress(of: $0))
            })
            OnboardingTrailingButton(model: model, onColor: false)
        }
    }
}

/// «Пропустити» на першому запуску, ✕ у повторному проході (§6, §7.4).
struct OnboardingTrailingButton: View {
    @Environment(\.wtTheme) private var theme
    let model: OnboardingModel
    let onColor: Bool

    var body: some View {
        if model.mode == .firstRun {
            Button(OnboardingPresenter.skip, action: model.skip)
                .font(WTFont.text(15, .heavy))
                .foregroundStyle(onColor ? Color.white : theme.textMuted)
                .frame(minHeight: 44)
                .buttonStyle(WTPressStyle())
                .accessibilityIdentifier("onboarding.skip")
        } else {
            WTBarButton(.close, onColor: onColor, action: model.close)
                .accessibilityIdentifier("onboarding.close")
        }
    }
}

enum OnboardingTransition {
    /// Щось розкрилось (було `false`, стало `true`) — докрутити вміст донизу. Із затримкою: нові рядки з'являються
    /// з анімацією, і прокрутка в тій самій транзакції ще не бачила б їхньої висоти.
    @MainActor
    static func reveal(_ old: [Bool], _ new: [Bool], _ proxy: ScrollViewProxy) {
        guard zip(old, new).contains(where: { !$0 && $1 }) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: revealDelay)
            withAnimation(WTAnimation.sheet) { proxy.scrollTo(OnboardingStepBody.bottomAnchor, anchor: .bottom) }
        }
    }

    static let revealDelay: Duration = .milliseconds(250)

    /// «Далі» — новий крок заїжджає справа, «‹» — зліва.
    static func step(forward: Bool) -> AnyTransition {
        .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity), removal: .opacity)
    }
}

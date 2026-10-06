import SwiftUI

/// Розкриття таємного призу — «Скриня» (SPEC-PRIZES §16.5, рішення від 06.10.2026).
///
/// 🎁 трясеться дедалі сильніше з трьома наростаючими вібраціями, тоді розкривається: промені, конфеті,
/// результат пружно вистрибує. Вміст визначений наперед — анімація лише показує його. «Барабан» і «Стрічка»
/// відкинуті: вони показували б, як 🌟 пролітає поруч, а «майже виграв» лише засмучує.
/// Reduce Motion — без трусіння, променів і конфеті: результат просто з'являється.
public struct WTMysteryReveal: View {
    public struct Outcome: Equatable, Sendable {
        public let emojis: [String]
        /// Бейдж «×N» — лише для набору одного призу.
        public let count: Int
        public let title: String
        public let subtitle: String
        public let announcement: String

        public init(emojis: [String], count: Int, title: String, subtitle: String, announcement: String) {
            self.emojis = emojis
            self.count = count
            self.title = title
            self.subtitle = subtitle
            self.announcement = announcement
        }
    }

    private enum Phase { case shaking, burst, done }

    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let kicker: String
    private let outcome: Outcome
    private let buttonTitle: String
    private let onDone: () -> Void

    @State private var phase: Phase = .shaking
    @State private var shakeAngle: Double = 0
    @State private var shakeScale: CGFloat = 1
    @State private var haptic: WTFeedback?
    @State private var hapticSerial = 0

    public init(kicker: String, outcome: Outcome, buttonTitle: String, onDone: @escaping () -> Void) {
        self.kicker = kicker
        self.outcome = outcome
        self.buttonTitle = buttonTitle
        self.onDone = onDone
    }

    public var body: some View {
        ZStack {
            theme.screen.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(kicker.uppercased())
                    .font(WTFont.text(13, .heavy))
                    .tracking(0.3)
                    .foregroundStyle(theme.textMuted)
                stage
                    .frame(width: 300, height: 300)
                    .padding(.top, 18)
                    .padding(.bottom, 10)
                VStack(spacing: 6) {
                    Text(outcome.title)
                        .font(WTFont.display(26, .bold))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(outcome.subtitle)
                        .font(WTFont.text(15, .bold))
                        .foregroundStyle(theme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .opacity(phase == .done ? 1 : 0)
                .offset(y: phase == .done ? 0 : 10)
                Spacer(minLength: 0)
                WTPrimaryButton(buttonTitle, action: onDone)
                    .opacity(phase == .done ? 1 : 0)
                    .allowsHitTesting(phase == .done)
                    .accessibilityHidden(phase != .done)
                    .accessibilityIdentifier("levelRoad.reveal.done")
            }
            .padding(.horizontal, WTSpacing.screenSide + 4)
            .padding(.bottom, WTSpacing.screenBottom)
        }
        .wtFeedback(trigger: hapticSerial) { _ in haptic }
        .task { await play() }
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private var stage: some View {
        ZStack {
            // Обертання — від часу, а не `withAnimation(.repeatForever)`: нескінченна транзакція
            // підхоплювала зсуви інших вʼюх, і шапка вікна під накладкою «пливла».
            TimelineView(.animation(paused: phase == .shaking || reduceMotion)) { context in
                rays.rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 40))
            }
            .opacity(phase == .shaking || reduceMotion ? 0 : 1)
            if !reduceMotion { confetti }
            Text("🎁")
                .font(.system(size: 150))
                .rotationEffect(.degrees(shakeAngle))
                .scaleEffect(phase == .shaking ? shakeScale : 1.7)
                .opacity(phase == .shaking ? 1 : 0)
                .accessibilityHidden(true)
            result
                .scaleEffect(phase == .shaking ? 0.3 : 1)
                .opacity(phase == .shaking ? 0 : 1)
        }
    }

    private var result: some View {
        Text(outcome.emojis.joined())
            .font(.system(size: outcome.emojis.count > 1 ? 76 : 96))
            .overlay(alignment: .bottomTrailing) {
                if outcome.count > 1 {
                    Text("×\(outcome.count)")
                        .font(WTFont.text(17, .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(theme.accent, in: Capsule())
                        .overlay(Capsule().stroke(theme.screen, lineWidth: 3))
                        .offset(x: 18, y: 2)
                }
            }
            .accessibilityHidden(true)
    }

    private var rays: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(theme.accent.opacity(0.22))
                    .frame(width: 22, height: 150)
                    .offset(y: -75)
                    .rotationEffect(.degrees(Double(index) * 30))
            }
        }
        // Рамка до маски: без неї маска лягала б на рамку одного променя (22 × 150) і обрізала решту.
        .frame(width: 300, height: 300)
        .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: 30, endRadius: 150))
        .accessibilityHidden(true)
    }

    /// Конфеті розлітаються від центру. Напрямки — «золотий кут» від індексу, без випадковості:
    /// картинка однакова від запуску до запуску, а розкид усе одно рівномірний.
    private var confetti: some View {
        let colors = [theme.accent, WTColor.orange, WTColor.success, theme.ringStart, WTColor.warnText]
        return ZStack {
            ForEach(0..<28, id: \.self) { index in
                let angle = Double(index) * 137.5 * .pi / 180
                let distance = 110 + Double((index * 53) % 90)
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors[index % colors.count])
                    .frame(width: 9, height: 9)
                    .rotationEffect(.degrees(phase == .shaking ? 0 : Double(index * 47 % 540)))
                    .offset(
                        x: phase == .shaking ? 0 : cos(angle) * distance,
                        y: phase == .shaking ? 0 : sin(angle) * distance
                    )
                    .opacity(phase == .burst ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }

    private func play() async {
        if reduceMotion {
            withAnimation(WTAnimation.fade) { phase = .done }
            feedback(.goalReached)
            announce()
            return
        }
        // Трусіння: шість поштовхів з наростанням, вібрація на кожен другий.
        for step in 0..<6 {
            let amplitude = 8 + Double(step) * 1.5
            withAnimation(.easeInOut(duration: 0.09)) {
                shakeAngle = step.isMultiple(of: 2) ? -amplitude : amplitude
                shakeScale = 1 + CGFloat(step) * 0.03
            }
            if !step.isMultiple(of: 2) { feedback(.anticipation(step / 2)) }
            try? await Task.sleep(for: .milliseconds(170))
        }
        withAnimation(.easeOut(duration: 0.1)) { shakeAngle = 0 }
        try? await Task.sleep(for: .milliseconds(100))

        withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { phase = .burst }
        feedback(.goalReached)
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.45)) { phase = .done }
        announce()
    }

    private func feedback(_ value: WTFeedback) {
        haptic = value
        hapticSerial += 1
    }

    private func announce() {
        AccessibilityNotification.Announcement(outcome.announcement).post()
    }
}

// MARK: - Довідник «Звідки XP»

public struct WTXPGuideRow: Identifiable, Equatable, Sendable {
    public let emoji: String
    public let title: String
    public let value: String

    public var id: String { title }

    public init(emoji: String, title: String, value: String) {
        self.emoji = emoji
        self.title = title
        self.value = value
    }
}

/// Картка-довідник за кнопкою «?» у вікні шляху рівнів (SPEC-PRIZES §16.14): ненав'язливо — лише за запитом.
public struct WTXPGuide: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let rows: [WTXPGuideRow]
    private let footnote: String
    private let onClose: () -> Void

    public init(title: String, rows: [WTXPGuideRow], footnote: String, onClose: @escaping () -> Void) {
        self.title = title
        self.rows = rows
        self.footnote = footnote
        self.onClose = onClose
    }

    public var body: some View {
        WTModal(maxWidth: 340, showsCloseButton: true, dismissesOnSwipe: true,
                closeIdentifier: "levelRoad.guide.close", onDismiss: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(WTFont.display(20, .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("levelRoad.guide")
                    .padding(.bottom, 12)
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Text(row.emoji)
                            .font(.system(size: 18))
                            .frame(width: 26)
                            .accessibilityHidden(true)
                        Text(row.title)
                            .font(WTFont.text(14, .bold))
                            .foregroundStyle(theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(row.value)
                            .font(WTFont.text(14, .heavy))
                            .foregroundStyle(theme.accent)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        if row != rows.last { Rectangle().fill(theme.line).frame(height: 1) }
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(footnote)
                    .font(WTFont.text(12, .bold))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }
}

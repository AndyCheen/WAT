import SwiftUI

/// Тост із необовʼязковою дією — «Порцію видалено · Скасувати».
///
/// У макетах його немає: там видалення безповоротне, хоча в базі це `soft delete`.
/// Дає користувачу шлях назад і не потребує окремого екрана.
public struct WTToast: View {
    @Environment(\.wtTheme) private var theme
    private let message: String
    private let actionTitle: String?
    private let duration: Double
    private let onAction: (() -> Void)?
    private let onDismiss: () -> Void

    public init(
        _ message: String,
        actionTitle: String? = nil,
        // Тост зі скасуванням треба встигнути прочитати й натиснути.
        duration: Double = 5,
        onAction: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.duration = duration
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(WTFont.text(14, .bold))
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("toast.message")

            if let actionTitle, let onAction {
                Button {
                    onAction()
                    onDismiss()
                } label: {
                    Text(actionTitle)
                        .font(WTFont.display(14, .semibold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WTPressStyle(scale: 0.94))
                .accessibilityIdentifier("toast.action")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, actionTitle == nil ? 16 : 4)
        .padding(.vertical, actionTitle == nil ? 14 : 6)
        .background(theme.card, in: RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous))
        .wtShadow(.card)
        .overlay(
            RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        // Ідентифікатора на контейнері тут свідомо немає: він успадковується дочірніми
        // й перекриває їхні власні — на цьому вже спотикались шторки (PLAN.md, §«Що зʼясувалося»).
        // `.task(id:)` знімається разом зі зникненням тоста, тож повторний показ
        // не тягне за собою «хвіст» від попереднього таймера.
        .task(id: message) {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}

/// Святкування виконаної норми: пульс кільця + краплі, що піднімаються.
///
/// Свідомо без сторонніх бібліотек — самі шейпи дизайн-системи. Не перехоплює дотики,
/// щоб не блокувати додавання наступної порції посеред анімації.
public struct WTGoalCelebration: View {
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    private let onFinish: () -> Void

    /// Зсуви крапель по горизонталі та їхні розміри — фіксовані, а не випадкові:
    /// анімація має виглядати однаково при кожному досягненні норми.
    ///
    /// Усі зсуви виходять за радіус кільця (121 pt): краплі піднімаються **обабіч**
    /// показника, а не крізь нього — інакше вони читаються як артефакти на цифрах.
    private static let drops: [(x: CGFloat, size: CGFloat, delay: Double)] = [
        (-152, 16, 0.00), (-131, 22, 0.10), (-110, 14, 0.20),
        (110, 20, 0.06), (131, 15, 0.16), (152, 21, 0.24)
    ]

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        ZStack {
            pulse
            if !reduceMotion { droplets }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(WTAnimation.celebration) { isAnimating = true }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }

    /// Кільце, що розходиться від центру прогресу й тане.
    private var pulse: some View {
        Circle()
            .stroke(theme.accent, lineWidth: 3)
            .frame(width: 242, height: 242)
            .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.35 : 0.96))
            .opacity(isAnimating ? 0 : 0.55)
    }

    private var droplets: some View {
        ZStack {
            ForEach(Array(Self.drops.enumerated()), id: \.offset) { _, drop in
                WTDropShape()
                    .fill(theme.accent.opacity(0.75))
                    .frame(width: drop.size, height: drop.size)
                    .offset(x: drop.x, y: isAnimating ? -150 : 40)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(
                        WTAnimation.celebration.delay(drop.delay),
                        value: isAnimating
                    )
            }
        }
    }
}

import SwiftUI

// Компоненти модуля «Призи» (SPEC-PRIZES §4, §5.2, §8). Приймають лише прості значення:
// що саме написати, вирішує Feature-шар, а тут — як це виглядає.

/// Рядок стосу готових призів — однаковий у блоці 3f і на екрані «Призи» (§4.1).
///
/// Кнопки дії в рядку немає свідомо: витратну дію робимо лише з картки, де видно
/// наслідок, — інакше випадковий тап спалював заморозку, яку берегли (§2, п. 5).
public struct WTPrizeRow: View {
    @Environment(\.wtTheme) private var theme
    private let emoji: String
    private let title: String
    private let subtitle: String
    private let isSubtitleWarning: Bool
    private let count: Int
    private let isNew: Bool
    private let showsDivider: Bool
    private let accessibilityValue: String
    private let identifier: String
    private let onTap: () -> Void

    /// - Parameters:
    ///   - isSubtitleWarning: підпис помаранчевий — «є що рятувати».
    ///   - showsDivider: волосок під рядком; в останнього рядка секції його немає.
    ///   - identifier: вішається на саму кнопку, а не на обгортку з волоском —
    ///     ідентифікатор контейнера успадковується дочірніми (CLAUDE.md §«Тести»).
    public init(
        emoji: String, title: String, subtitle: String, isSubtitleWarning: Bool = false,
        count: Int, isNew: Bool, showsDivider: Bool, accessibilityValue: String,
        identifier: String, onTap: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.isSubtitleWarning = isSubtitleWarning
        self.count = count
        self.isNew = isNew
        self.showsDivider = showsDivider
        self.accessibilityValue = accessibilityValue
        self.identifier = identifier
        self.onTap = onTap
    }

    public var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    WTPrizeIcon(emoji: emoji, size: 40, emojiSize: 20, isNew: isNew)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(WTFont.display(15, .semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(subtitle)
                            .font(WTFont.text(12, .bold))
                            .foregroundStyle(isSubtitleWarning ? WTColor.orange : theme.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("×\(count)")
                        .font(WTFont.text(13, .heavy))
                        .foregroundStyle(theme.accent)
                    WTIcons.chevronRight(color: theme.textMuted, size: 13)
                }
                .frame(minHeight: 56)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(WTPressStyle(scale: 0.98))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Приз: \(title)")
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)

            if showsDivider {
                Rectangle().fill(theme.line).frame(height: 1)
            }
        }
    }
}

/// Статус діючого призу в заголовку блоку «ПРИЗИ» на 3f (§4.1).
///
/// Пігулка, а не рядок списку: список відповідає на «що я можу використати», а діючий
/// приз — це стан. Крапка статична — пульсація на й так рухливому 3f відволікала б.
public struct WTPrizeStatusPill: View {
    @Environment(\.wtTheme) private var theme
    private let label: String
    private let remaining: String
    private let accessibilityLabel: String
    private let accessibilityValue: String
    private let identifier: String
    private let onTap: () -> Void

    /// - Parameters:
    ///   - label: «⚡ ×2 XP · » — Nunito, бо «×».
    ///   - remaining: «3:20» — Fredoka, лише цифри.
    public init(
        label: String, remaining: String, accessibilityLabel: String,
        accessibilityValue: String, identifier: String, onTap: @escaping () -> Void
    ) {
        self.label = label
        self.remaining = remaining
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.identifier = identifier
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 8, height: 8)
                    .padding(3)
                    .background(theme.accent.opacity(0.25), in: Circle())
                (Text(label).font(WTFont.text(12, .heavy))
                    + Text(remaining).font(WTFont.number(13, .semibold)))
                    .foregroundStyle(theme.textButton)
                    .lineLimit(1)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(height: 30)
            .background(theme.chip, in: Capsule())
        }
        .buttonStyle(WTPressStyle(scale: 0.95))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// Hero-картка діючого призу на екрані «Призи» (§5.2): тут місця досить, і діючий
/// приз — головне, що відбувається на екрані.
public struct WTPrizeActiveCard: View {
    @Environment(\.wtTheme) private var theme
    private let emoji: String
    private let title: String
    private let subtitle: String
    private let remaining: String
    private let fraction: Double
    private let accessibilityLabel: String
    private let accessibilityValue: String
    private let identifier: String
    private let onTap: () -> Void

    /// - Parameter fraction: частка часу, що лишилась, — смуга **спадає** до нуля,
    ///   як пісочний годинник.
    public init(
        emoji: String, title: String, subtitle: String, remaining: String, fraction: Double,
        accessibilityLabel: String, accessibilityValue: String, identifier: String,
        onTap: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.remaining = remaining
        self.fraction = fraction
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.identifier = identifier
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    WTPrizeIcon(emoji: emoji, size: 52, emojiSize: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(WTFont.display(17, .bold))
                            .foregroundStyle(theme.textPrimary)
                        Text(subtitle)
                            .font(WTFont.text(12, .bold))
                            .foregroundStyle(theme.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(remaining)
                        .font(WTFont.number(28, .semibold))
                        .foregroundStyle(theme.accent)
                }
                WTProgressBar(fraction: fraction, height: 6)
            }
            .padding(16)
            .background(theme.card, in: RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous))
            .wtShadow(.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(WTPressStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// Рядок стану під описом у картці призу (§8.2).
public enum WTPrizeDetailStatus: Equatable, Sendable {
    case none
    /// «Серія 12 днів збережеться» — помаранчевий: є що рятувати.
    case warning(String)
    /// «Якщо все ж закриєш норму — заморозка повернеться» — приглушене пояснення.
    case note(String)
    /// «Уже діє до 00:00» — акцент.
    case info(String)
    /// Великий залишок буста «3:20» без підпису «год : хв» — опис над ним уже каже «Діє до 00:00».
    case timer(String)
}

/// Кнопка дії в картці призу; неактивна — з причиною, яку VoiceOver читає як підказку.
public struct WTPrizeDetailAction: Equatable, Sendable {
    public let title: String
    public let isEnabled: Bool
    public let disabledHint: String?

    public init(title: String, isEnabled: Bool = true, disabledHint: String? = nil) {
        self.title = title
        self.isEnabled = isEnabled
        self.disabledHint = disabledHint
    }
}

/// Картка призу — спільна для блоку 3f і екрана «Призи» (§8).
///
/// На відміну від картки досягнення тут є кнопка: картка існує заради рішення
/// «використати зараз чи берегти», і вона ж — крок підтвердження (рядок → картка → кнопка),
/// тож окремого алерта «Ви впевнені?» немає.
public struct WTPrizeDetail: View {
    @Environment(\.wtTheme) private var theme
    private let emoji: String
    private let title: String
    private let count: Int
    private let details: String
    private let status: WTPrizeDetailStatus
    private let action: WTPrizeDetailAction?
    private let accessibilityValue: String
    private let onAction: () -> Void
    private let onClose: () -> Void

    /// - Parameter count: «×N» — бейдж на іконці, лише коли N ≥ 2. Кількість належить
    ///   предмету, а не назві: «Заморозка серії ×2» читалось як назва іншого призу.
    public init(
        emoji: String, title: String, count: Int, details: String,
        status: WTPrizeDetailStatus, action: WTPrizeDetailAction?,
        accessibilityValue: String, onAction: @escaping () -> Void, onClose: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.title = title
        self.count = count
        self.details = details
        self.status = status
        self.action = action
        self.accessibilityValue = accessibilityValue
        self.onAction = onAction
        self.onClose = onClose
    }

    public var body: some View {
        WTModal(
            maxWidth: 312, showsCloseButton: true, dismissesOnSwipe: true,
            closeIdentifier: "prizes.detail.close", onDismiss: onClose
        ) {
            VStack(spacing: 16) {
                info
                if let action {
                    WTPrimaryButton(action.title, isEnabled: action.isEnabled, action: onAction)
                        .accessibilityHint(action.isEnabled ? "" : (action.disabledHint ?? ""))
                        .accessibilityIdentifier("prizes.detail.action")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Інформаційна частина — один елемент для VoiceOver; кнопка й хрестик лишаються окремими.
    private var info: some View {
        VStack(spacing: 10) {
            icon
            Text(title)
                .font(WTFont.display(20, .semibold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(details)
                .font(WTFont.text(13, .semibold))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            statusView
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("prizes.detail")
    }

    private var icon: some View {
        Text(emoji)
            .font(.system(size: 34))
            .frame(width: 72, height: 72)
            .background(theme.prizeIconBg, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                if count >= 2 {
                    Text("×\(count)")
                        .font(WTFont.text(12, .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(theme.accent, in: Capsule())
                        .overlay(Capsule().stroke(theme.sheet, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .none:
            EmptyView()
        case .warning(let text):
            Text(text)
                .font(WTFont.text(13, .heavy))
                .foregroundStyle(WTColor.orange)
                .multilineTextAlignment(.center)
        case .note(let text):
            Text(text)
                .font(WTFont.text(12, .bold))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .info(let text):
            Text(text)
                .font(WTFont.text(13, .heavy))
                .foregroundStyle(theme.accent)
        case .timer(let text):
            Text(text)
                .font(WTFont.number(34, .semibold))
                .foregroundStyle(theme.accent)
                .monospacedDigit()
        }
    }
}

/// Квадратна іконка призу з крапкою «нове».
struct WTPrizeIcon: View {
    @Environment(\.wtTheme) private var theme
    let emoji: String
    let size: CGFloat
    let emojiSize: CGFloat
    var isNew = false

    var body: some View {
        Text(emoji)
            .font(.system(size: emojiSize))
            .frame(width: size, height: size)
            .background(theme.prizeIconBg, in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isNew { WTNewDot().offset(x: WTNewDot.outset, y: -WTNewDot.outset) }
            }
            .accessibilityHidden(true)
    }
}

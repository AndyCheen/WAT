import SwiftUI

/// Рядок завдання (SPEC-QUESTS §9.1): кружок із міні-кільцем прогресу (виконане — ✓), назва, чип «+N» XP і прогрес
/// праворуч. Без `fraction` кружок порожній, без `xp` — без чипа.
///
/// Свято виконаного (§9.2) — `isCelebrating`: ✓ «вистрибує», «+N XP» спливає й тане. Згортає рядок екран, коли
/// мине `WTAnimation.celebrationHold` (`wtCelebrationHold`): що лишається у списку — вирішує модель, не рядок.
public struct WTTaskRow: View {
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let title: String
    private let progress: String
    private let isDone: Bool
    private let fraction: Double?
    private let xp: Int?
    private let isCelebrating: Bool
    private let accessibilityText: String?

    public init(title: String, progress: String, isDone: Bool, fraction: Double? = nil, xp: Int? = nil,
                isCelebrating: Bool = false, accessibilityLabel: String? = nil) {
        self.title = title
        self.progress = progress
        self.isDone = isDone
        self.fraction = fraction
        self.xp = xp
        self.isCelebrating = isCelebrating
        self.accessibilityText = accessibilityLabel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                badge
                    .frame(width: Self.badgeSize, height: Self.badgeSize)

                Text(title)
                    .font(WTFont.display(15, .semibold))
                    // Виконане приглушене, але в мить свята — ще яскраве: рядок радіє, а не гасне.
                    .foregroundStyle(isDone && !isCelebrating ? theme.textMuted : theme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let xp {
                    Text("+\(xp)")
                        .font(WTFont.text(11, .black))
                        .foregroundStyle(theme.textButton)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.chip, in: RoundedRectangle(cornerRadius: WTRadius.chipSmall, style: .continuous))
                }

                Text(progress)
                    .font(WTFont.text(12, .heavy))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            }
            .padding(.vertical, 9)
            .overlay(alignment: .topTrailing) { flyingXp }

            Rectangle().fill(theme.line).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText ?? "\(title), \(progress)")
    }

    static let badgeSize: CGFloat = 26
    static let ringWidth: CGFloat = 3.5

    @ViewBuilder
    private var badge: some View {
        if isDone {
            ZStack {
                Circle().fill(theme.accent)
                WTIcons.check(color: .white, size: 13)
            }
            // «Вистрибує» з крапки — лише коли рядок святкує, а не щоразу, як виконане показують.
            .keyframeAnimator(initialValue: 1.0, trigger: isCelebrating) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                if isCelebrating && !reduceMotion {
                    LinearKeyframe(0.2, duration: 0.01)
                    SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
                } else {
                    LinearKeyframe(1.0, duration: 0.01)
                }
            }
        } else if let fraction {
            ZStack {
                Circle().stroke(theme.track, lineWidth: Self.ringWidth)
                Circle()
                    .trim(from: 0, to: max(0, min(1, fraction)))
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(Self.ringWidth / 2)
            .animation(WTAnimation.fade, value: fraction)
        } else {
            Circle().fill(theme.chip)
        }
    }

    /// «+N XP» живе в дереві завжди, прозорим: вставлений разом зі святом, він не побачив би зміни тригера й не
    /// програвся б.
    @ViewBuilder
    private var flyingXp: some View {
        if let xp {
            Text("+\(xp) XP")
                .font(WTFont.number(16, .semibold))
                .foregroundStyle(theme.textButton)
                .keyframeAnimator(initialValue: FlyingXp(), trigger: isCelebrating) { content, value in
                    content.opacity(value.opacity).offset(y: value.offset)
                } keyframes: { _ in
                    KeyframeTrack(\.opacity) {
                        if isCelebrating {
                            LinearKeyframe(1, duration: 0.25)
                            LinearKeyframe(1, duration: 0.35)
                            LinearKeyframe(0, duration: 0.7)
                        } else {
                            LinearKeyframe(0, duration: 0.01)
                        }
                    }
                    KeyframeTrack(\.offset) {
                        if isCelebrating && !reduceMotion {
                            LinearKeyframe(0, duration: 0.25)
                            LinearKeyframe(-22, duration: 1.05)
                        } else {
                            LinearKeyframe(0, duration: 0.01)
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private struct FlyingXp {
        var opacity: Double = 0
        var offset: CGFloat = 8
    }
}

public extension View {
    /// Кінець свята рядка (SPEC-QUESTS §9.2): `onEnd` — через `WTAnimation.celebrationHold`, і модель згортає рядок
    /// у «Виконані · N». Таймер — у в'ю: пішов екран — задача скасувалась, і рядок досвяткує, коли повернеться.
    func wtCelebrationHold(_ isActive: Bool, onEnd: @escaping @MainActor () -> Void) -> some View {
        task(id: isActive) {
            guard isActive else { return }
            try? await Task.sleep(for: WTAnimation.celebrationHold)
            guard !Task.isCancelled else { return }
            onEnd()
        }
    }
}

/// Рядок історії з таймлайном. Тап розкриває кнопку «Видалити» (макет 1a).
public struct WTHistoryRow: View {
    @Environment(\.wtTheme) private var theme
    private let amountLabel: String
    private let timeLabel: String
    private let isLast: Bool
    private let isOpen: Bool
    private let onTap: () -> Void
    private let onDelete: (() -> Void)?

    public init(
        amountLabel: String,
        timeLabel: String,
        isLast: Bool,
        isOpen: Bool = false,
        onTap: @escaping () -> Void = {},
        onDelete: (() -> Void)? = nil
    ) {
        self.amountLabel = amountLabel
        self.timeLabel = timeLabel
        self.isLast = isLast
        self.isOpen = isOpen
        self.onTap = onTap
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(theme.screen, lineWidth: 3))
                    .overlay(Circle().stroke(theme.accent, lineWidth: 2).padding(-1))
                    .padding(.top, 3)
                if !isLast {
                    Rectangle().fill(theme.line).frame(width: 2)
                }
            }
            .frame(width: 14)

            Button(action: onTap) {
                HStack(spacing: 10) {
                    Text(amountLabel)
                        .font(WTFont.display(18, .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 0)
                    if isOpen, let onDelete {
                        Button(action: onDelete) {
                            HStack(spacing: 6) {
                                WTIcons.trash(color: WTColor.danger)
                                Text("Видалити")
                                    .font(WTFont.text(14, .heavy))
                                    .foregroundStyle(WTColor.danger)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(theme.deleteBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(WTPressStyle(scale: 0.94))
                        .accessibilityIdentifier("history.delete")
                    } else {
                        Text(timeLabel)
                            .font(WTFont.text(15, .bold))
                            .foregroundStyle(theme.textMuted)
                    }
                }
                .padding(.bottom, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(WTPressStyle(scale: 0.99, opacity: 0.75))
        }
    }
}

/// Статичний рядок історії (макет 4a — без видалення).
public struct WTHistoryStaticRow: View {
    @Environment(\.wtTheme) private var theme
    private let amountLabel: String
    private let timeLabel: String
    private let isLast: Bool

    public init(amountLabel: String, timeLabel: String, isLast: Bool) {
        self.amountLabel = amountLabel
        self.timeLabel = timeLabel
        self.isLast = isLast
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(theme.accent, lineWidth: 2.5)
                    .frame(width: 14, height: 14)
                    .padding(.top, 3)
                if !isLast {
                    Rectangle().fill(theme.chip).frame(width: 2)
                }
            }
            .frame(width: 14)

            HStack(spacing: 10) {
                Text(amountLabel)
                    .font(WTFont.display(16, .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 0)
                Text(timeLabel)
                    .font(WTFont.text(14, .bold))
                    .foregroundStyle(theme.textMuted)
            }
            .padding(.bottom, 18)
        }
    }
}

/// Стан досягнення для плитки й картки — що показувати під назвою чи в нижньому слоті.
public enum WTAchievementStatus: Equatable, Sendable {
    case unlocked
    /// `unit` — «л», «мл» для об'єму (WAT-52). Окремо від чисел: у картці вони — Fredoka без кирилиці.
    case progress(fraction: Double, label: String, unit: String? = nil)
    /// Закрите разове — ціль в одну дію (WAT-51): ні смуги, ні «0/1». Таке досягнення або є, або ні,
    /// і порожня смуга з «0/1» нічого не міряє. У картці лишається рядок нагороди.
    case locked
    /// Функцію вимкнено — підпис замість прогресу («Увімкни сповіщення»).
    case caption(String)
    /// Таємне ще не відкрите: ні умови, ні прогресу (SPEC-ACHIEVEMENTS-CATALOG §4.9).
    case hidden

    var isUnlocked: Bool { self == .unlocked }
}

/// Плитка досягнення для сітки 3×N (макет 2e, SPEC-ACHIEVEMENTS §5.3).
///
/// Відкрита плитка під назвою не показує нічого — ні смуги, ні XP: у сітці з двох
/// десятків комірок однакові «+50 XP» читаються як шум. Нагорода живе в картці деталей.
public struct WTAchievementTile: View {
    @Environment(\.wtTheme) private var theme
    private let emoji: String
    private let title: String
    private let status: WTAchievementStatus
    private let isNew: Bool
    private let accessibilityValue: String
    private let onTap: () -> Void

    public init(
        emoji: String, title: String, status: WTAchievementStatus, isNew: Bool = false,
        accessibilityValue: String, onTap: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.title = title
        self.status = status
        self.isNew = isNew
        self.accessibilityValue = accessibilityValue
        self.onTap = onTap
    }

    private var isUnlocked: Bool { status.isUnlocked }

    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 22))
                    .opacity(isUnlocked ? 1 : 0.35)
                    .frame(width: 46, height: 46)
                    .background(isUnlocked ? theme.unlockedIconBg : theme.lockedIconBg, in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if isNew { WTNewDot().offset(x: WTNewDot.outset, y: -WTNewDot.outset) }
                    }

                Text(title)
                    .font(WTFont.display(12, .semibold))
                    .foregroundStyle(isUnlocked ? theme.textPrimary : theme.textMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)

                switch status {
                case .progress(let fraction, let label, let unit):
                    WTProgressBar(
                        fraction: fraction, height: 6,
                        fill: Color(hex: "#b9d4ee"), track: theme.track
                    )
                    Text(unit.map { "\(label) \($0)" } ?? label)
                        .font(WTFont.text(11, .heavy))
                        .foregroundStyle(theme.textMuted)
                case .caption(let caption):
                    Text(caption)
                        .font(WTFont.text(10, .bold))
                        .foregroundStyle(theme.textMuted)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.9)
                case .unlocked, .locked, .hidden:
                    EmptyView()
                }
            }
            // Плитки в одному рядку сітки мають різну висоту (у закритих є прогрес-бар),
            // тому вирівнюємо їх по верхньому краю — інакше рядок «стрибає».
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(WTPressStyle(scale: 0.95))
        .accessibilityLabel("Досягнення: \(title)")
        .accessibilityValue(accessibilityValue)
    }
}

/// Маленький бейдж досягнення для вітрини 4×2 на екрані «Прогрес» (макет 3f, SPEC-ACHIEVEMENTS §4.1).
///
/// Закритий бейдж показує прогрес кільцем по колу: у 48 pt прогрес-бар не вміщається,
/// а без індикації сірий кружечок у вітрині виглядає як помилка.
public struct WTAchievementBadge: View {
    @Environment(\.wtTheme) private var theme
    private let emoji: String
    private let title: String
    private let isUnlocked: Bool
    private let isNew: Bool
    private let fraction: Double
    private let accessibilityValue: String
    private let onTap: () -> Void

    private static let ringWidth: CGFloat = 3

    public init(
        emoji: String, title: String, isUnlocked: Bool, isNew: Bool = false,
        fraction: Double, accessibilityValue: String, onTap: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.title = title
        self.isUnlocked = isUnlocked
        self.isNew = isNew
        self.fraction = fraction
        self.accessibilityValue = accessibilityValue
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                icon
                Text(title)
                    .font(WTFont.text(11, .bold))
                    .foregroundStyle(isUnlocked ? theme.textPrimary : theme.textMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(WTPressStyle(scale: 0.95))
        .accessibilityLabel("Досягнення: \(title)")
        .accessibilityValue(accessibilityValue)
    }

    private var icon: some View {
        ZStack {
            Circle().fill(isUnlocked ? theme.unlockedIconBg : theme.lockedIconBg)
            if !isUnlocked {
                Circle()
                    .stroke(theme.dotOff, lineWidth: Self.ringWidth)
                Circle()
                    .trim(from: 0, to: max(0, min(1, fraction)))
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(emoji)
                .font(.system(size: 21))
                .opacity(isUnlocked ? 1 : 0.35)
        }
        // Кільце стоїть по внутрішньому краю кола, а не виходить за 48 pt.
        .padding(Self.ringWidth / 2)
        .frame(width: 48, height: 48)
        .overlay(alignment: .topTrailing) {
            if isNew { WTNewDot().offset(x: WTNewDot.outset, y: -WTNewDot.outset) }
        }
    }
}

/// Помаранчева крапка «щойно відкрито» — однакова на бейджі 3f і плитці 2e.
public struct WTNewDot: View {
    @Environment(\.wtTheme) private var theme

    public init() {}

    /// Зсув від кута кола: макетні `top:-2; right:-2` для самої крапки плюс 2 pt обведення,
    /// яке входить у рамку вʼюхи.
    static let outset: CGFloat = 4

    public var body: some View {
        Circle()
            .fill(WTColor.orange)
            .frame(width: 8, height: 8)
            // Обведення кольором фону відокремлює крапку від кола, на якому вона сидить.
            .padding(2)
            .background(theme.screen, in: Circle())
            .accessibilityHidden(true)
    }
}


// MARK: - Превʼю

#Preview("Рядки завдань") {
    VStack(spacing: 0) {
        WTTaskRow(title: "Половина до 14:00", progress: "ще 500 мл", isDone: false, fraction: 0.5, xp: 25)
        WTTaskRow(title: "Склянка після підйому", progress: "Готово", isDone: true, fraction: 1, xp: 15, isCelebrating: true)
        WTTaskRow(title: "Норма 5 днів", progress: "2/5 дн.", isDone: false, fraction: 0.4, xp: 100)
        WTTaskRow(title: "5 ранків зі склянкою", progress: "Готово", isDone: true, fraction: 1, xp: 75)
    }
    .padding(24)
    .environment(\.wtTheme, .light)
    .background(WTTheme.light.screen)
}

#Preview("Темна, найбільший шрифт") {
    VStack(spacing: 0) {
        WTTaskRow(title: "¾ норми до 6:30 пп", progress: "ще 1.05 л", isDone: false, fraction: 0.25, xp: 25)
        WTTaskRow(title: "Половина норми 4 дні", progress: "1/4 дн.", isDone: false, fraction: 0.25, xp: 75)
    }
    .padding(24)
    .environment(\.wtTheme, .dark)
    .background(WTTheme.dark.screen)
    .dynamicTypeSize(.xLarge)
}

/// Картка несподіваного завдання над «СЬОГОДНІ» (SPEC-QUESTS §9.1, макет A «Розділи»): ⚡ у колі, позначка виду,
/// назва, «ціль до часу · ще скільки», праворуч — живий відлік і нагорода. Виконане — «Готово · ⚡ у призах» на
/// світлішому тлі; згортання після свята — `wtCelebrationHold`, як у рядків.
public struct WTSurpriseCard: View {
    @Environment(\.wtTheme) private var theme
    private let kind: String
    private let title: String
    private let detail: String
    private let reward: String
    private let now: Date
    private let deadline: Date?
    private let isDone: Bool
    private let accessibilityText: String
    private let identifier: String
    private let timerIdentifier: String

    /// Ідентифікатори — на елементі тексту й на таймері окремо: на контейнері перший перекрив би другий.
    ///
    /// - Parameters:
    ///   - now: мить від `Clock` моделі — початок відліку.
    ///   - deadline: кінець вікна для `Text(timerInterval:)` — відлік іде сам, без перерисовки екрана.
    public init(kind: String, title: String, detail: String, reward: String, now: Date, deadline: Date?, isDone: Bool,
                accessibilityLabel: String, identifier: String, timerIdentifier: String) {
        self.now = now
        self.identifier = identifier
        self.kind = kind
        self.title = title
        self.detail = detail
        self.reward = reward
        self.deadline = deadline
        self.isDone = isDone
        self.accessibilityText = accessibilityLabel
        self.timerIdentifier = timerIdentifier
    }

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(theme.accent)
                Text("⚡").font(.system(size: 19))
            }
            .frame(width: Self.iconSize, height: Self.iconSize)

            VStack(alignment: .leading, spacing: 1) {
                Text(kind)
                    .font(WTFont.text(11, .black))
                    .tracking(0.3)
                    .foregroundStyle(WTColor.orange)
                Text(title)
                    .font(WTFont.display(15, .heavy))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(WTFont.text(12, .heavy))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityIdentifier(identifier)

            VStack(alignment: .trailing, spacing: 2) {
                timer
                Text(reward)
                    .font(WTFont.text(11, .black))
                    .foregroundStyle(theme.textButton)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(isDone ? theme.accent.opacity(Self.doneTint) : theme.chip,
                    in: RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous))
        .animation(WTAnimation.fade, value: isDone)
    }

    @ViewBuilder
    private var timer: some View {
        if isDone {
            WTIcons.check(color: theme.accent, size: 18)
                .frame(height: 22)
                .accessibilityHidden(true)
        } else if let deadline {
            // Картка видима лише всередині вікна, тож межа попереду; `max` — щоб діапазон не перевернувся на межі.
            Text(timerInterval: now...max(deadline, now), countsDown: true)
                .font(WTFont.number(22, .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(timerIdentifier)
        }
    }

    static let iconSize: CGFloat = 38
    /// Тло виконаної — акцент на 18 %, як `.surA.ok` у макеті.
    static let doneTint = 0.18

    /// Поява в хвилину `visibleFrom`: зверху з легким стисненням; з Reduce Motion — лише прозорість.
    public static func appearance(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .move(edge: .top).combined(with: .scale(scale: 0.97)).combined(with: .opacity),
                          removal: .opacity)
    }
}

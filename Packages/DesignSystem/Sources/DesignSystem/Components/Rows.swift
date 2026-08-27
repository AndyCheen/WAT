import SwiftUI

/// Рядок завдання: кружок-галочка + назва + прогрес. Спільний для 1a і 3f.
public struct WTTaskRow: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let progress: String
    private let isDone: Bool

    public init(title: String, progress: String, isDone: Bool) {
        self.title = title
        self.progress = progress
        self.isDone = isDone
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(isDone ? theme.accent : theme.chip)
                    if isDone { WTIcons.check(color: .white, size: 13) }
                }
                .frame(width: 26, height: 26)

                Text(title)
                    .font(WTFont.display(15, .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(progress)
                    .font(WTFont.text(12, .heavy))
                    .foregroundStyle(theme.textMuted)
            }
            .padding(.vertical, 9)

            Rectangle().fill(theme.line).frame(height: 1)
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

/// Картка призу з кнопкою «Активувати» (макет 3f).
public struct WTPrizeCard: View {
    @Environment(\.wtTheme) private var theme
    private let emoji: String
    private let title: String
    private let details: String
    private let isActivated: Bool
    private let onActivate: () -> Void

    public init(
        emoji: String, title: String, details: String,
        isActivated: Bool, onActivate: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.title = title
        self.details = details
        self.isActivated = isActivated
        self.onActivate = onActivate
    }

    public var body: some View {
        HStack(spacing: 14) {
            Text(emoji)
                .font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(WTColor.prizeIconBg, in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WTFont.display(15, .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(details)
                    .font(WTFont.text(12, .bold))
                    .foregroundStyle(theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onActivate) {
                Text(isActivated ? "Активовано" : "Активувати")
                    .font(WTFont.display(13, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        isActivated ? WTColor.textQuaternary : WTColor.orange,
                        in: RoundedRectangle(cornerRadius: WTRadius.chip, style: .continuous)
                    )
            }
            .buttonStyle(WTPressStyle(scale: 0.94))
            .disabled(isActivated)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            theme.isDark ? theme.card : WTColor.prizeBg,
            in: RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous)
        )
    }
}

/// Плитка досягнення для сітки 3×N з прогрес-баром (макет 2e).
public struct WTAchievementTile: View {
    @Environment(\.wtTheme) private var theme
    private let emoji: String
    private let title: String
    private let isUnlocked: Bool
    private let fraction: Double
    private let progressLabel: String
    private let onTap: () -> Void

    public init(
        emoji: String, title: String, isUnlocked: Bool,
        fraction: Double, progressLabel: String, onTap: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.title = title
        self.isUnlocked = isUnlocked
        self.fraction = fraction
        self.progressLabel = progressLabel
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 22))
                    .opacity(isUnlocked ? 1 : 0.35)
                    .frame(width: 46, height: 46)
                    .background(isUnlocked ? theme.chip : WTColor.neutralLocked, in: Circle())

                Text(title)
                    .font(WTFont.display(12, .semibold))
                    .foregroundStyle(isUnlocked ? theme.textPrimary : theme.textMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if !isUnlocked {
                    WTProgressBar(
                        fraction: fraction, height: 6,
                        fill: Color(hex: "#b9d4ee"), track: theme.track
                    )
                    Text(progressLabel)
                        .font(WTFont.text(11, .heavy))
                        .foregroundStyle(theme.textMuted)
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
    }
}

/// Картка досягнення для сітки 2×N у шторках (макети 1a і 3f).
public struct WTAchievementCard: View {
    @Environment(\.wtTheme) private var theme
    private let emoji: String
    private let title: String
    private let details: String
    private let isUnlocked: Bool

    public init(emoji: String, title: String, details: String, isUnlocked: Bool) {
        self.emoji = emoji
        self.title = title
        self.details = details
        self.isUnlocked = isUnlocked
    }

    public var body: some View {
        VStack(spacing: 8) {
            Text(emoji)
                .font(.system(size: 24))
                .opacity(isUnlocked ? 1 : 0.35)
                .frame(width: 52, height: 52)
                .background(isUnlocked ? WTColor.goldIconBg : theme.dotOff, in: Circle())

            Text(title)
                .font(WTFont.display(14, .semibold))
                .foregroundStyle(isUnlocked ? theme.textPrimary : theme.textMuted)
                .multilineTextAlignment(.center)

            Text(details)
                .font(WTFont.text(12, .bold))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .background(
            isUnlocked ? theme.chip : theme.button,
            in: RoundedRectangle(cornerRadius: WTRadius.tile, style: .continuous)
        )
    }
}

/// Маленький бейдж досягнення для сітки 4×N (макет 3f).
public struct WTAchievementBadge: View {
    @Environment(\.wtTheme) private var theme
    private let emoji: String
    private let title: String

    public init(emoji: String, title: String) {
        self.emoji = emoji
        self.title = title
    }

    public var body: some View {
        VStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 21))
                .frame(width: 48, height: 48)
                .background(theme.chip, in: Circle())
            Text(title)
                .font(WTFont.text(11, .bold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

/// Рядок нагороди за рівень (макет 3f, шторка «Нагороди за рівні»).
public struct WTLevelRewardRow: View {
    @Environment(\.wtTheme) private var theme
    private let level: Int
    private let emoji: String
    private let title: String
    private let details: String
    private let isUnlocked: Bool

    public init(level: Int, emoji: String, title: String, details: String, isUnlocked: Bool) {
        self.level = level
        self.emoji = emoji
        self.title = title
        self.details = details
        self.isUnlocked = isUnlocked
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("РІВЕНЬ \(level)")
                .font(WTFont.text(12, .heavy))
                .foregroundStyle(isUnlocked ? theme.accent : WTColor.textQuaternary)

            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Text(emoji)
                        .font(.system(size: 22))
                        .opacity(isUnlocked ? 1 : 0.35)
                        .frame(width: 44, height: 44)
                        .background(
                            isUnlocked ? WTColor.goldIconBg : WTColor.neutralLocked,
                            in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous)
                        )
                    if isUnlocked {
                        ZStack {
                            Circle().fill(WTColor.success)
                            WTIcons.check(color: .white, size: 9)
                        }
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(theme.sheet, lineWidth: 2))
                        .offset(x: 4, y: 4)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(WTFont.display(15, .semibold))
                        .foregroundStyle(isUnlocked ? theme.textPrimary : theme.textMuted)
                    Text(details)
                        .font(WTFont.text(12, .bold))
                        .foregroundStyle(theme.textMuted)
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(theme.line).frame(height: 1).padding(.top, 6)
        }
    }
}

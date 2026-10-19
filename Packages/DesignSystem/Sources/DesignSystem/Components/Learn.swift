import SwiftUI

// Бібліотека розділу «Знання» (SPEC-LEARN §3, макет Design/Learn.html, варіант A «Історії»): «Продовжити» і
// полиці обкладинок, що гортаються вбік. Компоненти знають лише прості значення — назви, частки, стиль полиці.

public extension WTIcons {
    /// «Знання» — кнопка в шапці головного.
    static func book(color: Color, size: CGFloat = 19) -> some View {
        Image(systemName: "book")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
    }
}

/// Стан обкладинки в бібліотеці.
public enum WTLearnBadge: Equatable, Sendable {
    case none
    case read
    case new
    /// Почата: частка дочитаного.
    case progress(Double)
}

/// Обкладинка історії на полиці: колір полиці, емодзі в колі, назва, тривалість.
public struct WTLearnCover: View {
    @Environment(\.wtTheme) private var theme
    private let emoji: String
    private let title: String
    private let caption: String
    private let style: WTStoryStyle
    private let badge: WTLearnBadge
    private let isDraft: Bool

    public init(emoji: String, title: String, caption: String, style: WTStoryStyle, badge: WTLearnBadge, isDraft: Bool = false) {
        self.emoji = emoji
        self.title = title
        self.caption = caption
        self.style = style
        self.badge = badge
        self.isDraft = isDraft
    }

    public var body: some View {
        let ink = WTLearnInk.of(style, theme: theme)
        VStack(alignment: .leading, spacing: 0) {
            Text(emoji)
                .font(.system(size: 26))
                .frame(width: 52, height: 52)
                .background(ink.empty, in: Circle())
            Spacer(minLength: 8)
            Text(title)
                .font(WTFont.text(15, .heavy))
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Text(caption)
                .font(WTFont.text(12, .heavy))
                .opacity(0.75)
                .padding(.top, 5)
            if case .progress(let fraction) = badge {
                WTProgressBar(fraction: fraction, height: 5, fill: ink.fill, track: ink.empty)
                    .padding(.top, 8)
            }
        }
        .foregroundStyle(ink.text)
        .padding(14)
        .frame(width: 132, height: 184, alignment: .topLeading)
        .background(alignment: .topTrailing) {
            Circle().fill(ink.empty.opacity(0.5)).frame(width: 110, height: 110).offset(x: 34, y: -30)
        }
        .background(WTStoryBackground(style: style))
        .overlay(alignment: .topTrailing) { corner(ink) }
        .clipShape(RoundedRectangle(cornerRadius: WTRadius.panel, style: .continuous))
        .shadow(color: WTShadow.card.color, radius: WTShadow.card.radius, x: 0, y: WTShadow.card.y)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, caption, badgeLabel].compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder
    private func corner(_ ink: WTLearnInk) -> some View {
        switch badge {
        case .read:
            WTIcons.check(color: style.isOnColor ? theme.waterDeep : .white, size: 11)
                .frame(width: 24, height: 24)
                .background(style.isOnColor ? Color.white.opacity(0.92) : WTColor.orange, in: Circle())
                .padding(12)
        case .new:
            Text("Нове")
                .font(WTFont.text(10, .black))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(WTColor.orange, in: Capsule())
                .padding(12)
        case .none, .progress:
            if isDraft {
                Text("чернетка")
                    .font(WTFont.text(10, .black))
                    .foregroundStyle(ink.text.opacity(0.8))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(ink.empty, in: Capsule())
                    .padding(12)
            }
        }
    }

    private var badgeLabel: String? {
        switch badge {
        case .read: return "прочитано"
        case .new: return "нове"
        case .progress(let fraction): return "прочитано \(Int((fraction * 100).rounded())) %"
        case .none: return nil
        }
    }
}

/// «Продовжити»: незакінчена історія на всю ширину, з ілюстрацією праворуч і кнопкою ▶.
public struct WTLearnContinueCard<Art: View>: View {
    @Environment(\.wtTheme) private var theme
    private let kicker: String
    private let title: String
    private let caption: String
    private let fraction: Double
    private let style: WTStoryStyle
    private let art: Art

    public init(kicker: String, title: String, caption: String, fraction: Double, style: WTStoryStyle,
                @ViewBuilder art: () -> Art) {
        self.kicker = kicker
        self.title = title
        self.caption = caption
        self.fraction = fraction
        self.style = style
        self.art = art()
    }

    public var body: some View {
        let ink = WTLearnInk.of(style, theme: theme)
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker.uppercased())
                    .font(WTFont.text(12, .black))
                    .tracking(0.6)
                    .opacity(0.8)
                Text(title)
                    .font(WTFont.display(21, .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                WTProgressBar(fraction: fraction, height: 5, fill: ink.fill, track: ink.empty)
                    .padding(.top, 12)
                Text(caption)
                    .font(WTFont.text(12, .heavy))
                    .opacity(0.85)
                    .padding(.top, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            art
                .environment(\.wtLearnInk, ink)
                .frame(width: 96, height: 112)
            Image(systemName: "play.fill")
                .font(.system(size: 15))
                .foregroundStyle(style.isOnColor ? theme.waterDeep : .white)
                .frame(width: 46, height: 46)
                .background(style.isOnColor ? Color.white : WTColor.orange, in: Circle())
        }
        .foregroundStyle(ink.text)
        .padding(.vertical, 18)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .background(WTStoryBackground(style: style))
        .clipShape(RoundedRectangle(cornerRadius: WTRadius.card + 2, style: .continuous))
        .shadow(color: WTShadow.modal.color.opacity(0.5), radius: 20, x: 0, y: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kicker): \(title), \(caption)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Контекстний вхід у «Знання» (SPEC-LEARN §3.2): «📖 Як працюють призи ›» там, де виникає питання.
public struct WTLearnLink: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let identifier: String
    private let action: () -> Void

    public init(_ title: String, identifier: String, action: @escaping () -> Void) {
        self.title = title
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                WTIcons.book(color: theme.textButton, size: 15)
                Text(title)
                    .font(WTFont.text(14, .heavy))
                    .foregroundStyle(theme.textButton)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                WTIcons.chevronRight(color: theme.textButton, size: 12)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(theme.chip, in: RoundedRectangle(cornerRadius: WTRadius.control, style: .continuous))
        }
        .buttonStyle(WTPressStyle(scale: 0.98))
        .accessibilityIdentifier(identifier)
    }
}

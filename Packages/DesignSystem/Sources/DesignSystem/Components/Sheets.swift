import SwiftUI

/// Нижня шторка з макетів: радіус 32 зверху, ручка, димка, пружинна поява.
/// Власна, а не системна — системна не дає такої геометрії й тіні.
public struct WTSheet<Content: View>: View {
    @Environment(\.wtTheme) private var theme
    @State private var dragOffset: CGFloat = 0
    private let maxHeightFraction: CGFloat?
    private let onDismiss: () -> Void
    private let content: Content

    /// Скільки треба протягнути вниз, щоб шторка закрилася.
    private static var dismissThreshold: CGFloat { 110 }

    public init(
        maxHeightFraction: CGFloat? = nil,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.maxHeightFraction = maxHeightFraction
        self.onDismiss = onDismiss
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                WTColor.scrim
                    .ignoresSafeArea()
                    // Димка світлішає разом із протягуванням — видно, що жест «працює».
                    .opacity(scrimOpacity)
                    .onTapGesture(perform: dismiss)
                    .transition(.opacity)

                VStack(spacing: 0) {
                    Capsule()
                        .fill(theme.track)
                        .frame(width: 44, height: 5)
                        .padding(.top, 26)
                        .padding(.bottom, 20)

                    if let maxHeightFraction {
                        ScrollView { content }
                            .frame(maxHeight: proxy.size.height * maxHeightFraction)
                    } else {
                        content
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 42)
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: WTRadius.sheet,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: WTRadius.sheet,
                        style: .continuous
                    )
                    .fill(theme.sheet)
                )
                .wtShadow(.sheet)
                .offset(y: dragOffset)
                .gesture(dragToDismiss)
                .transition(.move(edge: .bottom))
            }
        }
        .ignoresSafeArea()
    }

    private var scrimOpacity: Double {
        let faded = Double(dragOffset) / Double(Self.dismissThreshold * 2.4)
        return 1 - min(1, max(0, faded))
    }

    /// Протягування вниз закриває шторку. До цього єдиним способом був тап по димці —
    /// на 402-pt екрані до неї треба тягнутися через пів екрана.
    private var dragToDismiss: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Вгору шторка не їде — тільки легкий «опір».
                dragOffset = value.translation.height > 0
                    ? value.translation.height
                    : value.translation.height / 6
            }
            .onEnded { value in
                let passedDistance = value.translation.height > Self.dismissThreshold
                let flicked = value.predictedEndTranslation.height > 320
                if passedDistance || flicked {
                    dismiss()
                } else {
                    withAnimation(WTAnimation.sheet) { dragOffset = 0 }
                }
            }
    }

    private func dismiss() {
        dragOffset = 0
        onDismiss()
    }
}

/// Центральна модалка (макети 2e і 4a).
public struct WTModal<Content: View>: View {
    @Environment(\.wtTheme) private var theme
    @State private var dragOffset: CGFloat = 0
    private let maxWidth: CGFloat
    private let showsCloseButton: Bool
    private let dismissesOnSwipe: Bool
    private let closeIdentifier: String
    private let onDismiss: () -> Void
    private let content: Content

    /// Скільки протягнути картку вниз, щоб вона закрилась. Менше, ніж у шторки:
    /// модалка невисока, і довгий хід пальця виглядав би непропорційно.
    private static var dismissThreshold: CGFloat { 80 }

    /// - Parameters:
    ///   - showsCloseButton: хрестик 28 × 28 у правому верхньому куті. Тап по скриму —
    ///     невидимий жест, а VoiceOver скрим як елемент не бачить узагалі.
    ///   - dismissesOnSwipe: закриття свайпом униз.
    public init(
        maxWidth: CGFloat = 280,
        showsCloseButton: Bool = false,
        dismissesOnSwipe: Bool = false,
        closeIdentifier: String = "modal.close",
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.showsCloseButton = showsCloseButton
        self.dismissesOnSwipe = dismissesOnSwipe
        self.closeIdentifier = closeIdentifier
        self.onDismiss = onDismiss
        self.content = content()
    }

    public var body: some View {
        ZStack {
            WTColor.modalScrim
                .ignoresSafeArea()
                .opacity(scrimOpacity)
                .onTapGesture(perform: dismiss)

            content
                .padding(.vertical, 28)
                .padding(.horizontal, 22)
                .frame(maxWidth: maxWidth)
                .background(theme.sheet, in: RoundedRectangle(cornerRadius: WTRadius.card, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if showsCloseButton { closeButton }
                }
                .wtShadow(.modal)
                .offset(y: dragOffset)
                .gesture(dragToDismiss, including: dismissesOnSwipe ? .all : .subviews)
                .padding(24)
        }
        .transition(.opacity)
    }

    private var closeButton: some View {
        Button(action: dismiss) {
            WTIcons.close(color: theme.textMuted, size: 11)
                .frame(width: 28, height: 28)
                .background(theme.chip, in: Circle())
                // Видимий кружок 28 pt, але зона дотику ширша — ціль у куті дрібна.
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(WTPressStyle())
        .padding(4)
        .accessibilityLabel("Закрити")
        .accessibilityIdentifier(closeIdentifier)
    }

    private var scrimOpacity: Double {
        1 - min(1, max(0, Double(dragOffset) / Double(Self.dismissThreshold * 3)))
    }

    private var dragToDismiss: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation.height > 0
                    ? value.translation.height
                    : value.translation.height / 6
            }
            .onEnded { value in
                if value.translation.height > Self.dismissThreshold || value.predictedEndTranslation.height > 260 {
                    dismiss()
                } else {
                    withAnimation(WTAnimation.sheet) { dragOffset = 0 }
                }
            }
    }

    private func dismiss() {
        onDismiss()
    }
}

/// Картка деталей досягнення — одна на блок 3f, екран 2e і тост головного
/// (SPEC-ACHIEVEMENTS §7).
///
/// Композиція однакова для відкритого й закритого: змінюється лише вміст нижнього
/// слота — прогрес або чип «✓ Отримано». Дві картки поспіль не «перестрибують».
public struct WTAchievementDetail: View {
    @Environment(\.wtTheme) private var theme
    private let emoji: String
    private let title: String
    private let details: String
    private let isUnlocked: Bool
    private let rewardLabel: String
    private let fraction: Double
    private let valueLabel: String
    private let accessibilityValue: String
    private let onClose: () -> Void

    /// - Parameter rewardLabel: «+100 XP за виконання» — лише для закритого: після
    ///   розблокування XP уже нараховані й на поведінку не впливають (§7.1).
    public init(
        emoji: String, title: String, details: String, isUnlocked: Bool,
        rewardLabel: String, fraction: Double, valueLabel: String,
        accessibilityValue: String, onClose: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.title = title
        self.details = details
        self.isUnlocked = isUnlocked
        self.rewardLabel = rewardLabel
        self.fraction = fraction
        self.valueLabel = valueLabel
        self.accessibilityValue = accessibilityValue
        self.onClose = onClose
    }

    public var body: some View {
        WTModal(
            maxWidth: 312, showsCloseButton: true, dismissesOnSwipe: true,
            closeIdentifier: "achievements.detail.close", onDismiss: onClose
        ) {
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
                status
            }
            .frame(maxWidth: .infinity)
            // Уся картка — один елемент для VoiceOver; хрестик лишається окремим.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier("achievements.detail")
        }
    }

    private var icon: some View {
        Text(emoji)
            .font(.system(size: 34))
            .opacity(isUnlocked ? 1 : 0.35)
            .frame(width: 72, height: 72)
            .background(isUnlocked ? theme.unlockedIconBg : theme.lockedIconBg, in: Circle())
            .overlay {
                if isUnlocked { Circle().stroke(WTColor.orange.opacity(0.4), lineWidth: 2) }
            }
    }

    @ViewBuilder
    private var status: some View {
        if isUnlocked {
            HStack(spacing: 6) {
                WTIcons.check(color: WTColor.successText, size: 12)
                Text("Отримано")
                    .font(WTFont.text(13, .heavy))
                    .foregroundStyle(WTColor.successText)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(WTColor.success.opacity(0.12), in: Capsule())
        } else {
            // Спершу «навіщо мені це», потім «скільки лишилось».
            Text(rewardLabel)
                .font(WTFont.text(13, .heavy))
                .foregroundStyle(theme.accent)
            VStack(spacing: 4) {
                WTProgressBar(fraction: fraction, height: 8)
                Text(valueLabel)
                    .font(WTFont.number(12, .semibold))
                    .foregroundStyle(theme.textMuted)
            }
        }
    }
}

/// Меню вибору, що розкривається з кнопки (екран 2e, категорії — SPEC-ACHIEVEMENTS §3.3).
///
/// Показується через `wtPopover`; без затемнення екрана — затемнення лишаємо модалкам,
/// які справді вимагають рішення, а тут користувач лише звужує список.
public struct WTPopoverMenu: View {
    @Environment(\.wtTheme) private var theme
    private let header: String
    private let options: [WTOption]
    private let selection: String
    private let identifierPrefix: String
    private let onSelect: (String) -> Void

    public static let width: CGFloat = 228

    public init(
        header: String, options: [WTOption], selection: String,
        identifierPrefix: String, onSelect: @escaping (String) -> Void
    ) {
        self.header = header
        self.options = options
        self.selection = selection
        self.identifierPrefix = identifierPrefix
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WTSectionLabel(header, size: 11)
                .padding(.top, 14)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                let isSelected = option.id == selection
                Button { onSelect(option.id) } label: {
                    HStack {
                        Text(option.title)
                            .font(WTFont.display(15, .semibold))
                            .foregroundStyle(theme.textPrimary)
                        Spacer(minLength: 8)
                        if isSelected { WTIcons.check(color: theme.accent, size: 14) }
                    }
                    .padding(.horizontal, isSelected ? 10 : 16)
                    .frame(height: 44)
                    .background(
                        isSelected ? theme.chip : .clear,
                        in: RoundedRectangle(cornerRadius: WTRadius.chip, style: .continuous)
                    )
                    .padding(.horizontal, isSelected ? 6 : 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(WTPressStyle(scale: 0.98))
                .overlay(alignment: .top) {
                    // Волосок між рядками, але не впритул до підкладки вибраного.
                    if index > 0, !isSelected, options[index - 1].id != selection {
                        Rectangle().fill(theme.line).frame(height: 1).padding(.horizontal, 16)
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("\(identifierPrefix).\(option.id)")
            }
        }
        .padding(.bottom, 6)
        .frame(width: Self.width)
        .background(theme.sheet, in: RoundedRectangle(cornerRadius: WTRadius.card, style: .continuous))
        .wtShadow(.modal)
    }
}

/// Рамка кнопки, з якої розкривається `wtPopover`.
public struct WTPopoverAnchorKey: PreferenceKey {
    public static let defaultValue: Anchor<CGRect>? = nil
    public static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

public extension View {
    /// Позначає кнопку-якір для `wtPopover` на корені екрана.
    func wtPopoverAnchor() -> some View {
        anchorPreference(key: WTPopoverAnchorKey.self, value: .bounds) { $0 }
    }

    /// Поповер під кнопкою-якорем, вирівняний по її правому краю, з відступом 8.
    ///
    /// Вішається на корінь екрана, а не на кнопку: кнопка живе в `ScrollView`, і меню,
    /// намальоване там, лягало б під наступні блоки та під тап-перехоплювач.
    /// Перехоплювач прозорий — екран не «моргає» заради вибору категорії.
    func wtPopover<Menu: View>(
        isPresented: Bool,
        width: CGFloat = WTPopoverMenu.width,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Menu
    ) -> some View {
        overlayPreferenceValue(WTPopoverAnchorKey.self) { anchor in
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    if isPresented {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onDismiss)
                            .accessibilityHidden(true)
                    }
                    if isPresented, let anchor {
                        let rect = proxy[anchor]
                        content()
                            .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
                            .offset(x: rect.maxX - width, y: rect.maxY + 8)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .allowsHitTesting(isPresented)
        }
    }
}

/// Заголовок усередині шторки: назва + необовʼязковий підзаголовок.
public struct WTSheetTitle: View {
    @Environment(\.wtTheme) private var theme
    private let title: String
    private let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(WTFont.display(22, .semibold))
                .foregroundStyle(theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(WTFont.text(14, .bold))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

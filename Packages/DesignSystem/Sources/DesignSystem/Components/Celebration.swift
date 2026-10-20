import SwiftUI

// Вікно відкриття досягнення — «Хвиля» (WAT-60, SPEC-ACHIEVEMENTS §8; макет Design/Celebration.html, варіант B,
// рішення від 20.10.2026). Екран заливає вода, досягнення спливає бульбашкою й лопається колами. Компонент не знає
// доменних моделей — лише прості значення; тексти складає `CelebrationPresenter` у Features.

/// Сторінка вікна: одне досягнення чи, коли їх більше трьох, сітка знаків «Нові досягнення: N».
public struct WTCelebrationPage: Equatable, Sendable {
    /// Як бульбашка показує знак (§8.7).
    public enum Reveal: Equatable, Sendable {
        case none
        /// 🤫 Спливає з «?», стискається й розкривається знаком.
        case secret
        /// 🥚 Яйце похитується двічі, стискається й розкривається знаком.
        case egg
    }

    public let emoji: String
    /// Знаки сітки замість бульбашки — сторінка «Нові досягнення: N» (§8.1).
    public let grid: [String]
    public let label: String
    public let title: String
    public let details: String
    public let xp: Int
    public let reveal: Reveal
    /// «Далі: ⭐ Тиждень поспіль · 3 / 7» — наступна сходинка (§8.4).
    public let next: String?
    /// «Пасхалка! Тут їх більше» у першої знайденої — замість «Далі».
    public let note: String?
    /// Оголошення VoiceOver — одним рядком: «Нове досягнення: Ціль дня. Випито денну норму. Плюс 25 XP».
    public let accessibilityLabel: String

    public init(emoji: String, grid: [String] = [], label: String, title: String, details: String, xp: Int,
                reveal: Reveal = .none, next: String? = nil, note: String? = nil, accessibilityLabel: String) {
        self.emoji = emoji
        self.grid = grid
        self.label = label
        self.title = title
        self.details = details
        self.xp = xp
        self.reveal = reveal
        self.next = next
        self.note = note
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Рядок рівня на останній сторінці: віха й рівень однієї дії — одне свято (§8.2).
public struct WTCelebrationLevel: Equatable, Sendable {
    public let number: Int
    /// Частка шляху до наступного рівня — донат навколо номера.
    public let fraction: Double
    /// «⚡ Подвійний XP — у призах», «Обери приз: 🧊 або ⚡», «🎁 Таємний приз чекає».
    public let caption: String?

    public init(number: Int, fraction: Double, caption: String?) {
        self.number = number
        self.fraction = fraction
        self.caption = caption
    }
}

public extension WTTheme {
    /// Вода вікна відкриття. Макет — `ringEnd → waterDeep`, але у світлій темі білий текст на `#6bb6f2 → #3d8fd6`
    /// мав контраст 2,3–2,9 : 1 там, де стоять назва й опис. Тож світла вода глибшає до тих самих синіх, що в темній
    /// темі: верх — світлий, як кільце, від 40 % висоти — глибина (рішення від 20.10.2026, SPEC-ACHIEVEMENTS §8.8).
    var celebrationWater: [Gradient.Stop] {
        isDark
            ? [.init(color: ringEnd, location: 0), .init(color: waterDeep, location: 1)]
            : [.init(color: ringEnd, location: 0), .init(color: WTTheme.dark.ringEnd, location: 0.4),
               .init(color: WTTheme.dark.waterDeep, location: 1)]
    }

    /// Текст на білій кнопці: найглибша вода — контраст 6,5 : 1 на білому в обох темах.
    var celebrationInk: Color { WTTheme.dark.waterDeep }
}

/// Вікно на весь екран. Сторінки гортає саме: «Далі» на не останній, на останній — `finishTitle`
/// («Чудово» / «Обрати приз» / «Відкрити 🎁») і, якщо є, `laterTitle` («Пізніше»).
public struct WTCelebration: View {
    @Environment(\.wtTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let pages: [WTCelebrationPage]
    private let level: WTCelebrationLevel?
    private let finishTitle: String
    private let laterTitle: String?
    private let appearDelay: Double
    private let onFinish: () -> Void
    private let onLater: () -> Void

    @State private var index = 0
    @State private var appeared = false
    @State private var filled = false
    /// Відколи кнопки реагують: перші 0,5 с після появи — ні, другий тап по кнопці порції не має змести вікно
    /// (§8.3). Час, а не `allowsHitTesting`: перемкнений на кнопці, він ковтав перший тап уже після блокування.
    @State private var liveFrom: ContinuousClock.Instant?
    @AccessibilityFocusState private var titleFocused: Bool

    /// - Parameter appearDelay: після дії на головному вікно чекає, поки догра кільце (≈ 0,6 с, §8.5). Поки
    ///   вікна не видно, дотики вже не проходять під нього.
    public init(pages: [WTCelebrationPage], level: WTCelebrationLevel?, finishTitle: String, laterTitle: String?,
                appearDelay: Double = 0, onFinish: @escaping () -> Void, onLater: @escaping () -> Void) {
        self.pages = pages
        self.level = level
        self.finishTitle = finishTitle
        self.laterTitle = laterTitle
        self.appearDelay = appearDelay
        self.onFinish = onFinish
        self.onLater = onLater
    }

    private var isLast: Bool { index >= pages.count - 1 }

    public var body: some View {
        ZStack {
            // Тап по тлу нічого не робить — і під вікно не проходить. Без власного жесту: жест на тлі змагався з
            // кнопкою, і перший тап по «Чудово» губився.
            Color.clear.contentShape(Rectangle()).ignoresSafeArea()
            if appeared {
                water
                VStack(spacing: 0) {
                    if pages.indices.contains(index) {
                        WTCelebrationPageView(page: pages[index], isFirst: index == 0, titleFocused: $titleFocused)
                            .id(index)
                            .frame(maxHeight: .infinity)
                    }
                    footer
                }
                .padding(.top, 70)
                .padding(.horizontal, 28)
                .padding(.bottom, WTSpacing.screenBottom - 4)
                .transition(.opacity)
            }
        }
        .wtFeedback(trigger: appeared) { $0 ? .achievement : nil }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task { await appear() }
    }

    private func appear() async {
        if appearDelay > 0 { try? await Task.sleep(for: .seconds(appearDelay)) }
        withAnimation(reduceMotion ? .easeOut(duration: 0.25) : WTAnimation.fade) { appeared = true }
        if reduceMotion {
            filled = true
        } else {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.0).delay(0.04)) { filled = true }
        }
        titleFocused = true
        liveFrom = .now + .milliseconds(500)
    }

    private var isLive: Bool { liveFrom.map { ContinuousClock.now >= $0 } ?? false }

    // MARK: - Вода

    private var water: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LinearGradient(stops: theme.celebrationWater, startPoint: .top, endPoint: .bottom)
                if !reduceMotion {
                    WTCelebrationSurface(color: theme.ringEnd)
                        .frame(height: 32)
                        .offset(y: -31)
                    WTCelebrationBubbles()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .offset(y: filled ? 0 : proxy.size.height + 40)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Низ

    private var footer: some View {
        VStack(spacing: 14) {
            if pages.count > 1 { dots }
            if isLast, let level {
                WTCelebrationLevelRow(level: level)
                    .wtStoryAppear(delay: index == 0 ? 0.9 : 0.3)
            }
            Button(action: primary) {
                Text(isLast ? finishTitle : "Далі")
                    .font(WTFont.display(17, .heavy))
                    .foregroundStyle(theme.celebrationInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: WTRadius.button, style: .continuous))
            }
            .buttonStyle(WTPressStyle())
            .accessibilityIdentifier("celebration.primary")
            if isLast, let laterTitle {
                Button(action: { if isLive { onLater() } }) {
                    Text(laterTitle)
                        .font(WTFont.display(15, .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WTPressStyle())
                .accessibilityIdentifier("celebration.later")
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { page in
                Capsule()
                    .fill(Color.white.opacity(page == index ? 1 : 0.35))
                    .frame(width: page == index ? 20 : 7, height: 7)
                    .accessibilityLabel("Сторінка \(page + 1) з \(pages.count)")
                    .accessibilityAddTraits(page == index ? .isSelected : [])
                    .accessibilityIdentifier("celebration.page.\(page)")
            }
        }
        .animation(WTAnimation.fade, value: index)
    }

    private func primary() {
        guard isLive else { return }
        guard isLast else {
            withAnimation(WTAnimation.fade) { index += 1 }
            titleFocused = true
            return
        }
        onFinish()
    }
}

// MARK: - Сторінка

private struct WTCelebrationPageView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let page: WTCelebrationPage
    /// На першій сторінці вода ще наливається — бульбашка й текст чекають довше.
    let isFirst: Bool
    var titleFocused: AccessibilityFocusState<Bool>.Binding

    @State private var risen = false
    @State private var revealed = false
    @State private var squeeze: CGFloat = 1
    @State private var wobble: Double = 0
    /// Кола від бульбашки: 0 — ще не було, далі розходяться до 1.
    @State private var ripple: Double = 0

    private var textDelay: Double {
        (page.reveal == .none ? 1.35 : 1.9) - (isFirst ? 0 : 0.6)
    }

    var body: some View {
        VStack(spacing: 0) {
            if page.grid.isEmpty { bubble } else { grid }
            Text(page.label.uppercased())
                .font(WTFont.text(12, .black))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.top, 26)
                .accessibilityHidden(true)
                .wtStoryAppear(delay: textDelay)
            Text(page.title)
                .font(WTFont.display(30, .heavy))
                .foregroundStyle(.white)
                .padding(.top, 8)
                .accessibilityLabel(page.accessibilityLabel)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(titleFocused)
                .accessibilityIdentifier("celebration.title")
                .wtStoryAppear(delay: textDelay + 0.08)
            Text(page.details)
                .font(WTFont.text(16, .bold))
                .foregroundStyle(Color.white.opacity(0.88))
                .lineSpacing(3)
                .frame(maxWidth: 310)
                .padding(.top, 10)
                .accessibilityHidden(true)
                .wtStoryAppear(delay: textDelay + 0.16)
            xp
                .padding(.top, 16)
                .wtStoryAppear(delay: textDelay + 0.26)
            if let line = page.note ?? page.next {
                Text(line)
                    .font(WTFont.text(13, .heavy))
                    // Рядок пасхалки — теплий, як підпис призів; «Далі» — білий.
                    .foregroundStyle(page.note == nil ? Color.white : WTColor.prizeIconBg)
                    .padding(.top, 14)
                    .accessibilityIdentifier("celebration.next")
                    .wtStoryAppear(delay: textDelay + 0.36)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await play() }
    }

    // MARK: - Бульбашка

    private var face: String {
        guard !revealed else { return page.emoji }
        switch page.reveal {
        case .none: return page.emoji
        case .secret: return "?"
        case .egg: return "🥚"
        }
    }

    private var bubble: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.42), .white.opacity(0.12), .white.opacity(0.06)],
                                     center: UnitPoint(x: 0.34, y: 0.3), startRadius: 0, endRadius: 110))
            Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
            if !reduceMotion {
                ForEach(0..<2, id: \.self) { ring in
                    Circle()
                        .stroke(Color.white.opacity(0.55), lineWidth: 2)
                        .scaleEffect(1 + 0.9 * ripple)
                        .opacity(ripple == 0 ? 0 : 0.9 * (1 - ripple))
                        .animation(.easeOut(duration: 1.2).delay(Double(ring) * 0.25), value: ripple)
                }
            }
            if face == "?" {
                Text("?")
                    .font(WTFont.number(60, .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
            } else {
                Text(face).font(.system(size: 76))
            }
        }
        .frame(width: 164, height: 164)
        .scaleEffect(x: squeeze, y: 1)
        .rotationEffect(.degrees(wobble))
        .offset(y: risen || reduceMotion ? 0 : 560)
        .scaleEffect(risen || reduceMotion ? 1 : 0.55)
        .opacity(risen || reduceMotion ? 1 : 0)
        .accessibilityHidden(true)
    }

    /// Більше трьох за раз — знаки сіткою, по п'ять у ряд.
    private var grid: some View {
        let columns = Array(repeating: GridItem(.fixed(52), spacing: 10), count: min(5, page.grid.count))
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(page.grid.enumerated()), id: \.offset) { _, emoji in
                Text(emoji)
                    .font(.system(size: 28))
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.16), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5))
            }
        }
        .scaleEffect(risen || reduceMotion ? 1 : 0.7)
        .opacity(risen || reduceMotion ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var xp: some View {
        HStack(spacing: 0) {
            Text("+")
            if reduceMotion {
                Text("\(page.xp)")
            } else {
                WTCountUpText(Double(page.xp), delay: isFirst ? 1.7 : 0.9)
            }
            Text("\u{00a0}XP")
        }
        .font(WTFont.number(15, .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Color.white.opacity(0.2), in: Capsule())
        .accessibilityHidden(true)
    }

    // MARK: - Рух

    private func play() async {
        guard !reduceMotion else {
            revealed = true
            return
        }
        if isFirst { try? await Task.sleep(for: .milliseconds(450)) }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.1)) { risen = true }
        try? await Task.sleep(for: .milliseconds(1000))
        switch page.reveal {
        case .none:
            await rippleOut()
        case .secret:
            try? await Task.sleep(for: .milliseconds(350))
            await squeezeOpen()
        case .egg:
            for angle in [-12.0, 10, -7, 4, 0, -12, 10, -7, 4, 0] {
                withAnimation(.easeInOut(duration: 0.14)) { wobble = angle }
                try? await Task.sleep(for: .milliseconds(140))
            }
            await squeezeOpen()
        }
    }

    /// Стискається до ребра, на ньому міняє знак і розкривається — 0,5 с (§8.7).
    private func squeezeOpen() async {
        withAnimation(.easeIn(duration: 0.25)) { squeeze = 0.02 }
        try? await Task.sleep(for: .milliseconds(250))
        revealed = true
        withAnimation(.easeOut(duration: 0.25)) { squeeze = 1 }
        await rippleOut()
    }

    /// Кола спершу з'являються біля краю бульбашки, а тоді розходяться — два кроки, інакше SwiftUI злив би їх в один.
    private func rippleOut() async {
        ripple = 0.001
        try? await Task.sleep(for: .milliseconds(20))
        ripple = 1
    }
}

// MARK: - Рядок рівня

private struct WTCelebrationLevelRow: View {
    let level: WTCelebrationLevel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.04, min(1, level.fraction)))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(level.number)")
                    .font(WTFont.number(19, .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Рівень \(level.number)")
                    .font(WTFont.display(16, .heavy))
                    .foregroundStyle(.white)
                if let caption = level.caption {
                    Text(caption)
                        .font(WTFont.text(13, .bold))
                        .foregroundStyle(Color.white.opacity(0.82))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: WTRadius.tile, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(["Рівень \(level.number)", level.caption].compactMap { $0 }.joined(separator: ". "))
        .accessibilityIdentifier("celebration.level")
    }
}

// MARK: - Безкінечний рух — лише через `TimelineView` (CLAUDE.md: `repeatForever` тягнув за собою шапку)

/// Гребінь води: дві хвилі різної швидкості, що біжать уздовж верхнього краю. `Canvas`, а не `Shape`: дві фігури,
/// перебудовані щокадру, забирали собі перший тап по кнопці вікна — його доводилося повторювати.
private struct WTCelebrationSurface: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let back = CGRect(x: 0, y: -6, width: size.width, height: size.height)
                canvas.fill(Self.crest(in: back, phase: t / 5.2 * 2 * .pi), with: .color(color.opacity(0.45)))
                canvas.fill(Self.crest(in: CGRect(origin: .zero, size: size), phase: t / 3.2 * 2 * .pi), with: .color(color))
            }
        }
    }

    private static func crest(in rect: CGRect, phase: Double) -> Path {
        var path = Path()
        let wavelength = rect.width / 2
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for x in stride(from: 0, through: rect.width, by: 4) {
            let y = rect.midY + sin(Double(x) / wavelength * 2 * .pi - phase) * rect.height * 0.27
            path.addLine(to: CGPoint(x: rect.minX + x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Бульбашки, що підіймаються крізь воду. Розкид — від індексу («золотий перетин»), без випадковості:
/// картинка однакова від запуску до запуску.
private struct WTCelebrationBubbles: View {
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { canvas, size in
                    for index in 0..<14 {
                        let seed = Double(index)
                        let x = (seed * 0.618_034).truncatingRemainder(dividingBy: 1) * size.width
                        let diameter = 4 + (seed * 7).truncatingRemainder(dividingBy: 10)
                        let duration = 5 + (seed * 3.7).truncatingRemainder(dividingBy: 6)
                        let progress = ((t + seed * 1.9) / duration).truncatingRemainder(dividingBy: 1)
                        let y = size.height + 20 - progress * (size.height + 40)
                        canvas.fill(Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                                    with: .color(.white.opacity(0.22)))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

// MARK: - Превʼю

#Preview("Світла") {
    WTCelebration(
        pages: [WTCelebrationPage(emoji: "🎯", label: "Нове досягнення", title: "Ціль дня", details: "Випито денну норму",
                                  xp: 25, next: "Далі: 🖐️ Перша п'ятірка · 1 / 5",
                                  accessibilityLabel: "Нове досягнення: Ціль дня. Випито денну норму. Плюс 25 XP")],
        level: WTCelebrationLevel(number: 2, fraction: 0.1, caption: "⚡ Подвійний XP — у призах"),
        finishTitle: "Чудово", laterTitle: nil, onFinish: {}, onLater: {}
    )
    .environment(\.wtTheme, .light)
}

#Preview("Темна, таємне") {
    WTCelebration(
        pages: [WTCelebrationPage(emoji: "🍎", label: "Поки тебе не було · таємне", title: "В яблучко",
                                  details: "3 дні рівно норма, до мілілітра", xp: 100, reveal: .secret,
                                  accessibilityLabel: "Таємне досягнення: В яблучко")],
        level: nil, finishTitle: "Чудово", laterTitle: nil, onFinish: {}, onLater: {}
    )
    .environment(\.wtTheme, .dark)
    .background(WTTheme.dark.screen)
}

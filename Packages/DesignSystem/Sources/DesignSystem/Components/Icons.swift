import SwiftUI

/// Іконки з макета. Ті, що є в SF Symbols, беремо звідти; краплю рівня малюємо шляхом,
/// бо саме її форма — впізнаваний елемент шапки 1a.
public enum WTIcons {
    public static func chevronLeft(color: Color, size: CGFloat = 16) -> some View {
        Image(systemName: "chevron.left")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
    }

    public static func chevronRight(color: Color, size: CGFloat = 16) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
    }

    public static func gear(color: Color, size: CGFloat = 20) -> some View {
        Image(systemName: "gearshape")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
    }

    public static func close(color: Color, size: CGFloat = 12) -> some View {
        Image(systemName: "xmark")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
    }

    public static func trash(color: Color, size: CGFloat = 15) -> some View {
        Image(systemName: "trash")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
    }

    public static func check(color: Color, size: CGFloat = 13) -> some View {
        Image(systemName: "checkmark")
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(color)
    }
}

/// Крапля з номером рівня — кнопка переходу на екран прогресу (макет 1a).
public struct WTDropShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        // Пропорції з макета: M12 2s7 8 7 13a7 7 0 0 1-14 0c0-5 7-13 7-13z
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0.5 * w, y: 0.083 * h))
        path.addCurve(
            to: CGPoint(x: 0.79 * w, y: 0.625 * h),
            control1: CGPoint(x: 0.79 * w, y: 0.42 * h),
            control2: CGPoint(x: 0.79 * w, y: 0.5 * h)
        )
        path.addArc(
            center: CGPoint(x: 0.5 * w, y: 0.625 * h),
            radius: 0.29 * w,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addCurve(
            to: CGPoint(x: 0.5 * w, y: 0.083 * h),
            control1: CGPoint(x: 0.21 * w, y: 0.5 * h),
            control2: CGPoint(x: 0.21 * w, y: 0.42 * h)
        )
        path.closeSubpath()
        return path
    }
}

public struct WTLevelDrop: View {
    private let level: Int
    private let color: Color
    private let size: CGFloat
    private let hasBadge: Bool
    private let badgeBorder: Color

    public init(level: Int, color: Color, size: CGFloat = 30, hasBadge: Bool = false, badgeBorder: Color = .white) {
        self.level = level
        self.color = color
        self.size = size
        self.hasBadge = hasBadge
        self.badgeBorder = badgeBorder
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                WTDropShape().fill(color)
                Text("\(level)")
                    .font(WTFont.number(size * 0.4, .bold))
                    .foregroundStyle(.white)
                    .offset(y: size * 0.09)
            }
            .frame(width: size, height: size)

            if hasBadge {
                Circle()
                    .fill(WTColor.orange)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(badgeBorder, lineWidth: 1.5))
                    .offset(x: 1, y: -1)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Довга серія в шапці: число днів і одна крапля замість рядка крапок (WAT-10).
///
/// Колір розведений навмисне: помаранчева тут тільки крапля, число — звичайний
/// текстовий колір теми. Дві помаранчеві плями поруч перетягували б увагу з кільця,
/// а крапля лишається впізнаваною й сама.
public struct WTStreakDrop: View {
    private let count: Int
    private let numberColor: Color
    private let dropColor: Color
    private let size: CGFloat

    public init(count: Int, numberColor: Color, dropColor: Color = WTColor.orange, size: CGFloat = 26) {
        self.count = count
        self.numberColor = numberColor
        self.dropColor = dropColor
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(WTFont.number(20, .medium))
                .foregroundStyle(numberColor)
            WTDropShape()
                .fill(dropColor)
                .frame(width: size, height: size)
        }
    }
}

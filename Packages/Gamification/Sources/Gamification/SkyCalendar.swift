import Foundation

/// Сонцестояння й повня — для таємних «Найдовший день», «Найкоротший день» і «Повня»
/// (SPEC-ACHIEVEMENTS-CATALOG §4.8). Чисті функції за Меусом («Astronomical Algorithms», гл. 27 і 49),
/// без мережі й без `Date()`: момент — в UTC, локальний день із нього бере `CalendarService`.
///
/// Точність — хвилина: ΔT узято сталим (69 с — 2020-ті), дрібні планетарні поправки повні (≤ 30 с)
/// відкинуто. День розходиться з довідником хіба тоді, коли подія майже рівно опівночі за місцевим часом.
public enum SkyCalendar {
    public enum Solstice: Sendable, Hashable {
        /// Літнє — найдовший день (північна півкуля, як і решта застосунку).
        case june
        /// Зимове — найкоротший день.
        case december
    }

    /// Момент сонцестояння в році `year` (коректно для 1000–3000 рр.).
    public static func solstice(_ kind: Solstice, year: Int) -> Date {
        let y = Double(year - 2000) / 1000
        let mean: Double
        switch kind {
        case .june:
            mean = 2_451_716.56767 + 365_241.62603 * y + 0.00325 * y * y + 0.00888 * pow(y, 3) - 0.00030 * pow(y, 4)
        case .december:
            mean = 2_451_900.05952 + 365_242.74049 * y - 0.06223 * y * y - 0.00823 * pow(y, 3) + 0.00032 * pow(y, 4)
        }
        let t = (mean - 2_451_545.0) / 36_525
        let w = radians(35_999.373 * t - 2.47)
        let deltaLambda = 1 + 0.0334 * cos(w) + 0.0007 * cos(2 * w)
        let s = solsticeTerms.reduce(0.0) { $0 + $1.a * cos(radians($1.b + $1.c * t)) }
        return date(julianDay: mean + 0.00001 * s / deltaLambda)
    }

    /// Моменти повні в межах `[from, to]`.
    public static func fullMoons(from: Date, to: Date) -> [Date] {
        guard from <= to else { return [] }
        // k — номер новолуння від 6 січня 2000; повня — на половині.
        var k = (julianDay(from) - 2_451_550.09766) / synodicMonth
        k = k.rounded(.down) - 1.5
        var result: [Date] = []
        while true {
            let moment = fullMoon(k: k)
            if moment > to { break }
            if moment >= from { result.append(moment) }
            k += 1
        }
        return result
    }

    /// Момент повні з номером `k` (ціле + 0,5), Меус гл. 49.
    static func fullMoon(k: Double) -> Date {
        let t = k / 1236.85
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t
        let mean = 2_451_550.09766 + synodicMonth * k + 0.00015437 * t2 - 0.000000150 * t3 + 0.00000000073 * t4
        let e = 1 - 0.002516 * t - 0.0000074 * t2
        let m = radians(2.5534 + 29.10535670 * k - 0.0000014 * t2 - 0.00000011 * t3)
        let mp = radians(201.5643 + 385.81693528 * k + 0.0107582 * t2 + 0.00001238 * t3 - 0.000000058 * t4)
        let f = radians(160.7108 + 390.67050284 * k - 0.0016118 * t2 - 0.00000227 * t3 + 0.000000011 * t4)
        let omega = radians(124.7746 - 1.56375588 * k + 0.0020672 * t2 + 0.00000215 * t3)

        var c = -0.40614 * sin(mp)
        c += 0.17302 * e * sin(m)
        c += 0.01614 * sin(2 * mp)
        c += 0.01043 * sin(2 * f)
        c += 0.00734 * e * sin(mp - m)
        c -= 0.00515 * e * sin(mp + m)
        c += 0.00209 * e * e * sin(2 * m)
        c -= 0.00111 * sin(mp - 2 * f)
        c -= 0.00057 * sin(mp + 2 * f)
        c += 0.00056 * e * sin(2 * mp + m)
        c -= 0.00042 * sin(3 * mp)
        c += 0.00042 * e * sin(m + 2 * f)
        c += 0.00038 * e * sin(m - 2 * f)
        c -= 0.00024 * e * sin(2 * mp - m)
        c -= 0.00017 * sin(omega)
        c -= 0.00007 * sin(mp + 2 * m)
        c += 0.00004 * sin(2 * mp - 2 * f)
        c += 0.00004 * sin(3 * m)
        c += 0.00003 * sin(mp + m - 2 * f)
        c += 0.00003 * sin(2 * mp + 2 * f)
        c -= 0.00003 * sin(mp + m + 2 * f)
        c += 0.00003 * sin(mp - m + 2 * f)
        c -= 0.00002 * sin(mp - m - 2 * f)
        c -= 0.00002 * sin(3 * mp + m)
        c += 0.00002 * sin(4 * mp)
        return date(julianDay: mean + c)
    }

    // MARK: - Внутрішнє

    private static let synodicMonth = 29.530588861

    /// Періодичні члени сонцестояння, Меус табл. 27.C: A, B (°), C (°/століття).
    private static let solsticeTerms: [(a: Double, b: Double, c: Double)] = [
        (485, 324.96, 1934.136), (203, 337.23, 32964.467), (199, 342.08, 20.186),
        (182, 27.85, 445_267.112), (156, 73.14, 45036.886), (136, 171.52, 22518.443),
        (77, 222.54, 65928.934), (74, 296.72, 3034.906), (70, 243.58, 9037.513),
        (58, 119.81, 33718.147), (52, 297.17, 150.678), (50, 21.02, 2281.226),
        (45, 247.54, 29929.562), (44, 325.15, 31555.956), (29, 60.93, 4443.417),
        (18, 155.12, 67555.328), (17, 288.79, 4562.452), (16, 198.04, 62894.029),
        (14, 199.76, 31436.921), (12, 95.39, 14577.848), (12, 287.11, 31931.756),
        (12, 320.81, 34777.259), (9, 227.73, 1222.114), (8, 15.45, 16859.074)
    ]

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    /// TT → UTC: ΔT ≈ 69 с.
    private static let deltaT: TimeInterval = 69

    private static func date(julianDay: Double) -> Date {
        Date(timeIntervalSince1970: (julianDay - 2_440_587.5) * 86_400 - deltaT)
    }

    private static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }
}

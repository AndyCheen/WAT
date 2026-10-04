import Foundation
import Core

/// Один варіант тексту. `id` унікальний у межах типу: ротація «не два останні поспіль»
/// рахується по типу, а ситуації вечірнього підсумку мають різні набори (§14.1).
struct CopyVariant: Equatable {
    enum Requirement: Equatable {
        /// Текст з `{since}` — лише коли сьогодні вже була порція.
        case since
        /// «Почнімо з води» — лише коли активне завдання «Випити воду зранку».
        case morningQuest
        /// «…одна склянка, і норму закрито» — лише коли бракує не більше склянки.
        case singleGlass
    }

    let id: Int
    let title: String
    let body: String
    var requires: [Requirement] = []
}

/// Каталог текстів — SPEC-NOTIFICATIONS §14.2 з правками від 04.10.2026: емодзі перенесено на
/// початок заголовка (§14.1), заголовки порятунку скорочено до 30 символів.
///
/// Правила (§14.1): звертання на «ти», без родового минулого часу («пив / пила») — лише
/// теперішній і майбутній час, наказовий спосіб, безособові звороти; без докорів; заголовок
/// ≤ 30 символів, текст ≤ 100. Тест `CopyCatalogTests` перевіряє все це на найгірших значеннях.
///
/// Плейсхолдери: `{left}` — скільки бракує, `{glass}` — моя склянка, `{streak}` — серія з
/// узгодженим словом («12 днів»), `{since}` — від останньої порції, `{total}` — випито за день.
enum NotificationCopy {
    static let reminderPrimary: [CopyVariant] = [
        CopyVariant(id: 0, title: "💧 Час на воду",
                    body: "Від останньої порції — {since}. Склянка зараз — і темп відновлено", requires: [.since]),
        CopyVariant(id: 1, title: "Ковток?", body: "За темпом саме час для наступної склянки"),
        CopyVariant(id: 2, title: "Пауза затяглася", body: "Якщо вже п'єш — запиши. Якщо ні — саме час"),
        CopyVariant(id: 3, title: "💧 Вода чекає", body: "До цілі ще {left}. Почни з однієї склянки")
    ]

    static let reminderFollowUp: [CopyVariant] = [
        CopyVariant(id: 10, title: "Ще раз про воду", body: "Якщо зараз незручно — «Нагадати за годину»"),
        CopyVariant(id: 11, title: "Одна склянка", body: "Лише одна — і нагадування відпочинуть"),
        CopyVariant(id: 12, title: "💧 Без поспіху", body: "Склянка — пів хвилини, запис — один тап")
    ]

    static let morning: [CopyVariant] = [
        CopyVariant(id: 0, title: "☀️ Доброго ранку", body: "Склянка води після сну — найпростіший старт дня"),
        CopyVariant(id: 1, title: "Ранкова склянка",
                    body: "За ніч організм не отримав ні краплі. {glass} — і день почався"),
        CopyVariant(id: 2, title: "Почнімо з води",
                    body: "Перша склянка — і ранкове завдання вже зараховано", requires: [.morningQuest])
    ]

    static let eveningClosable: [CopyVariant] = [
        CopyVariant(id: 0, title: "🎯 Майже ціль",
                    body: "Лишилось {left} — одна склянка, і норму закрито", requires: [.singleGlass]),
        CopyVariant(id: 1, title: "Фінішна пряма", body: "Ще {left} — і день зараховано")
    ]

    static let eveningStreak: [CopyVariant] = [
        CopyVariant(id: 2, title: "🔥 Серія на кону", body: "Ще {left} — і серія {streak} продовжиться")
    ]

    /// Заспокійливе — **без згадки про серію**: обрив серії нічого не показує (ТЗ продукту §5.3).
    static let eveningSoothing: [CopyVariant] = [
        CopyVariant(id: 3, title: "Сьогодні — {total}",
                    body: "Це теж рух уперед. Ще склянка — і завтра почнеш ближче до цілі"),
        CopyVariant(id: 4, title: "День не ідеальний",
                    body: "І це нормально. Завтра — нова спроба, а склянка зараз ще наблизить до цілі"),
        CopyVariant(id: 5, title: "Вечір — час видихнути",
                    body: "{total} сьогодні — уже щось. Завтра візьмемо більше")
    ]

    static let rescueEvening: [CopyVariant] = [
        CopyVariant(id: 0, title: "🧊 Серію {streak} ще збережеш",
                    body: "Сьогодні норму вже не наздогнати — у тебе є заморозка. Закриєш норму — вона повернеться")
    ]

    static let rescueMorning: [CopyVariant] = [
        CopyVariant(id: 1, title: "🧊 Серію {streak} ще врятуєш",
                    body: "Учора норму не закрито. Заморозь учорашній день — і почни ранок зі склянки")
    ]

    static let comebackFirst: [CopyVariant] = [
        CopyVariant(id: 0, title: "💧 Почнімо знову", body: "Перерва звичку не ламає. Одна склянка — і новий початок"),
        CopyVariant(id: 1, title: "Склянка на старт",
                    body: "Кілька днів без записів — буває. Рівень і досягнення на місці")
    ]

    /// Останнє повідомлення — нейтральне й дає контроль, а не тисне (§12.4).
    static let comebackLastWithGift = CopyVariant(
        id: 2, title: "Нагадування на паузі",
        body: "Більше не турбуватимемо. Повернешся — на тебе чекатиме ⚡ подвійний XP"
    )

    static let comebackLast = CopyVariant(
        id: 3, title: "Нагадування на паузі",
        body: "Більше не турбуватимемо. Захочеш повернутися — одна склянка, і все знову працює"
    )

    /// Усе, що може потрапити в план, — для тесту каталогу.
    static var all: [CopyVariant] {
        reminderPrimary + reminderFollowUp + morning + eveningClosable + eveningStreak + eveningSoothing
            + rescueEvening + rescueMorning + comebackFirst + [comebackLastWithGift, comebackLast]
    }

    // MARK: - Вставки контексту (§12.2, §14.3)

    static func streakInsert(_ streak: Int) -> String {
        "Серія \(NotificationFormat.days(streak)) тримається на сьогоднішній нормі"
    }

    static func boostInsert(remaining: String) -> String {
        "⚡ Ще \(remaining) подвійного XP — ця склянка принесе вдвічі більше"
    }

    static func questInsert(title: String) -> String {
        "Ще 1 запис — і «\(title)» виконано"
    }

    static func weeklyInsert(xp: Int) -> String {
        "Норма дня закриє й тижневе завдання (+\(xp) XP)"
    }

    static func bounceBackInsert(xp: Int) -> String {
        "Закриєш норму сьогодні — +\(xp) XP «Знову в ритмі»"
    }
}

/// Тексти відлуння розблокувань (§12.1, тип 8). Публічні: відлуння складає композиційний
/// корінь — лише він знає, що саме відкрила порція з дії сповіщення.
public enum EchoText {
    public static let body = "Відкрито щойно — подивись у застосунку"

    public static func achievement(_ title: String) -> (title: String, body: String) {
        let full = "🏅 Досягнення: \(title)"
        if full.count <= 30 { return (full, body) }
        return ("🏅 Нове досягнення", "«\(title)» — відкрито щойно, подивись у застосунку")
    }

    public static func achievements(count: Int) -> (title: String, body: String) {
        ("🏅 Нові досягнення: \(count)", body)
    }

    public static func level(_ level: Int) -> (title: String, body: String) {
        ("🎉 Рівень \(level)", body)
    }

    public static let comebackGift = (title: "🎁 З поверненням!", body: "⚡ Подвійний XP уже в призах — подивись у застосунку")

    public static func bounceBack(xp: Int) -> (title: String, body: String) {
        ("🔁 Знову в ритмі: +\(xp) XP", "Норму закрито — ритм повернувся")
    }
}

/// Числа в текстах сповіщень (§14.1).
enum NotificationFormat {
    /// Скільки бракує — округлення **вгору** до 50, щоб людина не недобрала. Від 1000 — у літрах.
    static func left(_ ml: Int) -> String {
        volume(Int((Double(max(0, ml)) / 50).rounded(.up)) * 50)
    }

    /// «850 мл», «1,05 л», «2 л». Кома — лише тут: в інтерфейсі застосунку свій формат
    /// (`Volume.litersLabel`), і e2e на нього спираються (рішення від 04.10.2026).
    static func volume(_ ml: Int) -> String {
        guard ml >= 1000 else { return "\(ml) мл" }
        var text = String(format: "%.2f", Double(ml) / 1000)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: ",") + " л"
    }

    /// «1 год 40 хв», «2 год», «45 хв».
    static func duration(minutes: Int) -> String {
        let total = max(1, minutes)
        let hours = total / 60, rest = total % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) хв"
        case (_, 0): return "\(hours) год"
        default: return "\(hours) год \(rest) хв"
        }
    }

    static func days(_ n: Int) -> String { Plural.days(n) }
}

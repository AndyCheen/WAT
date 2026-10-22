import Foundation
import Core
import Persistence
import Gamification
import DesignSystem

/// Живі значення, з яких складаються тексти історій (SPEC-LEARN §5.4): ті самі правила й профіль, що й
/// нарахування, — після зміни балансу чи норми історія не бреше.
struct LearnContext: Equatable {
    struct Block: Equatable {
        let title: String
        let deadlineMinute: Int
        let targetMl: Int
    }

    var goalMl = 2000
    var blocks: [Block] = []
    var wakeMinutes = 8 * 60
    var sleepMinutes = 22 * 60
    var dayRhythmEnabled = true
    var level = 1
    var rules = XPRules.default
    var presets: [Int] = PresetPlace.home.defaults(for: .milliliters)
    var dailyCap = 8
    /// Система людини (WAT-58) — для живих значень. Довідкові факти («≈ 2,5 л на день») лишаються метричними:
    /// це цитати джерел, а не числа застосунку.
    var volumeUnit = VolumeUnit.milliliters
    var timeFormat = TimeFormat.hours24
}

/// Тексти й ілюстрації історій «Знань» — чиста функція «історія + значення → слайди», як `ReportPresenter`.
///
/// Версія 1 — чернетка (SPEC-LEARN §5.3): редактура й фактчек — окремою задачею. Правила тексту — §5.2:
/// на «ти», без роду, надзаголовок ≤ 24, заголовок ≤ 48, текст ≤ 140 знаків (`LearnCopyTests`).
struct LearnPresenter {
    let context: LearnContext

    func slides(for story: LearnStory) -> [LearnSlide] {
        let body: [LearnSlide]
        switch story.id {
        case "body.why": body = why()
        case "body.howMuch": body = howMuch()
        case "body.signs": body = signs()
        case "body.myths": body = myths()
        case "habits.rhythm": body = rhythm()
        case "habits.anchors": body = anchors()
        case "habits.special": body = special()
        case "app.start": body = start()
        case "app.xp": body = xp()
        case "app.streak": body = streak()
        case "app.prizes": body = prizes()
        case "app.reminders": body = reminders()
        default: body = []
        }
        return [cover(story)] + body.map { slide in
            var slide = slide
            // Кольорові — лише обкладинка й «що з цим робити»: решта на кольорі екрана, де видно графіки.
            if case .action = slide.kind { slide.style = story.shelf.style }
            if case .quizScore = slide.kind { slide.style = story.shelf.style }
            return slide
        }
    }

    private func cover(_ story: LearnStory) -> LearnSlide {
        let visual: LearnVisual
        switch story.id {
        case "body.why": visual = .drop(level: 0.55)
        case "app.xp": visual = .level(context.level)
        default: visual = .emoji(story.emoji)
        }
        return LearnSlide(kind: .cover, style: story.shelf.style,
                          kicker: story.id == "body.myths" ? "Вікторина · \(story.minutes) хв" : "\(story.minutes) хв читання",
                          title: story.title, text: coverText[story.id], visual: visual)
    }

    private let coverText: [String: String] = [
        "body.why": "Хвилина-дві — і норма перестане бути примхою застосунку.",
        "body.howMuch": "Звідки взялися «8 склянок» і що рахувати як воду.",
        "body.signs": "Як тіло підказує, що води замало, — і коли час до лікаря.",
        "body.myths": "Пʼять тверджень: правда чи міф? Відповідь — на звороті картки.",
        "habits.rhythm": "Чому краще потроху, ніж усе одразу.",
        "habits.anchors": "Як склянка води стає звичкою, а не зусиллям.",
        "habits.special": "Коли звичайної норми мало.",
        "app.start": "Усе, що треба знати в перший день.",
        "app.xp": "Звідки береться XP і що дає новий рівень.",
        "app.streak": "Як серія росте, множить XP і переживає пропуск.",
        "app.prizes": "Заморозка, бусти й таємні призи — що це й коли їх брати.",
        "app.reminders": "Як застосунок вирішує, коли нагадати, — і коли змовчати."
    ]

    // MARK: - Вода й тіло

    private func why() -> [LearnSlide] {
        [
            LearnSlide(kind: .fact, kicker: "З чого складається тіло", title: "Ти — більше ніж наполовину вода",
                       text: "У людини вагою 70 кг це ≈ 42 л. У немовлят частка ще більша — до 75 %.",
                       number: .init(value: 60, unit: "%"), visual: .body(fraction: 0.6), source: .popkin),
            LearnSlide(kind: .list, kicker: "Що вона робить", title: "Вода працює цілий день",
                       visual: .bodyMap(["🌡️", "🚚", "🦴", "🫘"]),
                       items: [.init(emoji: "🌡️", title: "Охолоджує", detail: "піт забирає зайве тепло"),
                               .init(emoji: "🚚", title: "Доставляє", detail: "поживні речовини до клітин"),
                               .init(emoji: "🦴", title: "Змащує", detail: "суглоби, очі й слизові"),
                               .init(emoji: "🫘", title: "Очищує", detail: "нирки фільтрують ≈ 180 л плазми на добу")],
                       source: .popkin),
            LearnSlide(kind: .fact, kicker: "Щоденний обмін", title: "Щодня йде ≈ 2,5 л — стільки ж треба повернути",
                       text: "Округлено: дорослий, помірний клімат, без спорту.",
                       visual: .columns(
                           .init(title: "Надходить", total: "≈ 2,5 л",
                                 parts: [("Напої", "1,7", 0.68), ("Їжа", "0,5", 0.2), ("Обмін речовин", "0,3", 0.12)]),
                           .init(title: "Виходить", total: "≈ 2,5 л",
                                 parts: [("Нирки", "1,5", 0.6), ("Шкіра й піт", "0,5", 0.2), ("Дихання", "0,3", 0.12),
                                         ("Інше", "0,2", 0.08)])),
                       source: .jequier),
            quiz("Правда чи міф?", "«Більшість води ми отримуємо з їжею»", isTrue: false,
                 "Їжа дає лише ≈ 20 % води, решту — напої. Тому склянки й рахуємо.", source: .efsa),
            LearnSlide(kind: .action(title: "Відкрити статистику", destination: .stats), kicker: "Що з цим робити",
                       title: "Потроху протягом дня",
                       text: "Твою норму застосунок ділить на ранок, день і вечір — і підкаже, коли відстаєш.",
                       visual: normRing)
        ]
    }

    private func howMuch() -> [LearnSlide] {
        [
            LearnSlide(kind: .fact, kicker: "Звідки «8 склянок»", title: "Половину поради просто забули",
                       text: "1945 року радили ≈ 2,5 л на день — і додали, що більшість цього вже є в їжі. Другу частину забули.",
                       visual: .glasses(full: 8, bonus: 0, locked: 0, chip: nil, legend: []), source: .valtin),
            LearnSlide(kind: .fact, kicker: "Скільки насправді", title: "2–2,5 л усієї води — разом з їжею",
                       text: "Із напоїв — ≈ 1,6 л жінкам і 2,0 л чоловікам: решту дає їжа.",
                       visual: .bars([.init(label: "Жінкам", value: "2,0 л", fraction: 0.8, lower: 0.8),
                                      .init(label: "Чоловікам", value: "2,5 л", fraction: 1, lower: 0.8)],
                                     legend: ["напої", "їжа"]),
                       source: .efsa),
            LearnSlide(kind: .fact, kicker: "Що додає", title: "Тапни, що стосується тебе сьогодні",
                       visual: .factors(base: context.goalMl, baseLabel: "норма",
                                        factors: [.init(emoji: "🏃", title: "Тренування", add: 500),
                                                  .init(emoji: "☀️", title: "Спека", add: 500),
                                                  .init(emoji: "🤰", title: "Вагітність", add: 300),
                                                  .init(emoji: "🤱", title: "Годування", add: 700)]),
                       source: .efsa),
            LearnSlide(kind: .list, kicker: "Що рахувати", title: "Записуй те, що пʼєш без цукру",
                       items: [.init(emoji: "💧", title: "Вода", detail: "звичайна й мінеральна"),
                               .init(emoji: "☕", title: "Чай і кава", detail: "помірно — теж рідина"),
                               .init(emoji: "🥛", title: "Молоко й несолодкі напої"),
                               .init(emoji: "🚫", title: "Солодке й алкоголь", detail: "краще не рахувати")],
                       source: .killer),
            LearnSlide(kind: .action(title: "Змінити норму", destination: .settings), kicker: "Що з цим робити",
                       title: "Твоя норма — \(ReportFormat.volume(context.goalMl, context.volumeUnit))",
                       text: "Багато рухаєшся чи живеш у спеці — норму можна підняти в налаштуваннях.",
                       visual: .drop(level: 0.8))
        ]
    }

    private func signs() -> [LearnSlide] {
        [
            LearnSlide(kind: .fact, kicker: "Уже 1–2 %", title: "Мала нестача — і вже помітно",
                       text: "Утрата близько 1,5 % води погіршує увагу й настрій, додає втоми й головного болю.",
                       visual: .tiles([.init(emoji: "😴", caption: "Втома"), .init(emoji: "🎯", caption: "Увага"),
                                       .init(emoji: "🤕", caption: "Голова"), .init(emoji: "😕", caption: "Настрій")]),
                       source: .ganio),
            LearnSlide(kind: .fact, kicker: "Перевірка кольором", title: "Тапни відтінок, найближчий до твого",
                       text: "Найпростіший показник — колір сечі.",
                       visual: .colorScale(verdicts: Array(repeating: "👍 Усе добре", count: 3)
                                           + Array(repeating: "🥤 Час для склянки", count: 2)
                                           + Array(repeating: "💧 Випий води зараз", count: 3),
                                           prompt: "Світліше — краще, темніше — пора пити"),
                       source: .armstrong),
            LearnSlide(kind: .list, kicker: "Інші ознаки", title: "Тіло підказує й інакше",
                       items: [.init(emoji: "👄", title: "Сухість у роті"),
                               .init(emoji: "🚻", title: "Рідше в туалет", detail: "ніж звичайно"),
                               .init(emoji: "🥵", title: "Спрага"),
                               .init(emoji: "😵", title: "Запаморочення", detail: "коли різко встаєш")],
                       source: .popkin),
            LearnSlide(kind: .list, kicker: "Коли до лікаря", title: "Не чекай, якщо…",
                       text: "Це не медична порада — при сумнівах краще спитати лікаря.",
                       items: [.init(emoji: "🚑", title: "Сплутаність чи сильне запаморочення"),
                               .init(emoji: "🚫", title: "Сечі немає понад 8 годин"),
                               .init(emoji: "🤒", title: "Блювота чи діарея понад добу"),
                               .init(emoji: "👶", title: "Дитина чи літня людина", detail: "зневоднюються швидше")],
                       source: .who),
            LearnSlide(kind: .action(title: "До головного", destination: .home), kicker: "Що з цим робити",
                       title: "Склянка — найпростіша перевірка",
                       text: "Не знаєш, чи вистачає води? Випий склянку зараз — і подивись, як почуваєшся за годину.",
                       visual: .drop(level: 0.4))
        ]
    }

    private func myths() -> [LearnSlide] {
        let statements: [(String, Bool, String, LearnSource)] = [
            ("«Кава зневоднює»", false,
             "Помірна кава гідратує не гірше за воду: 4 чашки на день у дослідженні не відрізнились від води.", .killer),
            ("«Рахується лише чиста вода»", false,
             "Чай, кава, молоко, суп і навіть фрукти теж дають воду. Солодке й алкоголь краще не рахувати.", .efsa),
            ("«Що більше, то краще»", false,
             "Нирки виводять до ≈ 1 л на годину. Кілька літрів поспіль розбавляють натрій у крові — це небезпечно.", .popkin),
            ("«Склянка перед їжею допомагає їсти менше»", true,
             "Схоже на правду: 500 мл перед їжею допомогли схуднути трохи більше за 12 тижнів дієти.", .dennis),
            ("«Спрага — це вже пізно»", false,
             "Здебільшого міф: спрага вмикається рано. Але в спеку, на тренуванні й з віком вона запізнюється.", .popkin)
        ]
        var slides = statements.enumerated().map { index, item in
            quiz("Твердження \(index + 1) з \(statements.count)", item.0, isTrue: item.1, item.2, source: item.3)
        }
        slides.append(LearnSlide(kind: .quizScore(title: "Скільки треба саме тобі", destination: .story("body.howMuch")),
                                 kicker: "Результат", title: "з \(statements.count)",
                                 text: "Тепер міфи про воду тебе не обдурять.", visual: .emoji("🏆")))
        return slides
    }

    // MARK: - Звички

    private func rhythm() -> [LearnSlide] {
        [
            LearnSlide(kind: .fact, kicker: "Тіло не запасає воду", title: "Випите разом виходить за ≈ 3 год",
                       visual: .curve(modes: ["Усе разом", "Потроху"],
                                      captions: ["Сплеск увечері — і знову мало", "Запас рівний цілий день"],
                                      start: clock(context.wakeMinutes),
                                      end: clock(context.sleepMinutes)),
                       source: .jequier),
            LearnSlide(kind: .fact, kicker: "Твій день", title: "Три цілі замість однієї",
                       text: "Застосунок стежить за кожною окремо — і підкаже, якщо котрась відстає.", visual: normRing),
            LearnSlide(kind: .fact, kicker: "Перед сном", title: "Менше — але не нуль",
                       text: "За 2 год до відбою застосунок кличе вдвічі рідше. Зовсім без води спиться гірше.",
                       number: .init(value: Double(PaceCurve.taperMinutes / 60), unit: "год"), visual: .emoji("🌙"),
                       source: .rosinger),
            LearnSlide(kind: .fact, kicker: "Ранкова склянка", title: "7–8 год сну — без води",
                       text: "Склянка після пробудження — найлегша звичка дня: її не треба памʼятати, лише поставити поруч.",
                       visual: .emoji("🌅")),
            LearnSlide(kind: .action(title: "Налаштування", destination: .settings), kicker: "Що з цим робити",
                       title: "Твій ритм — у налаштуваннях",
                       text: "Типово ритм дня ввімкнено. Там же — підйом і відбій: від них рахуються цілі.",
                       visual: .emoji("🧭"))
        ]
    }

    private func anchors() -> [LearnSlide] {
        [
            LearnSlide(kind: .fact, kicker: "Скільки часу", title: "Стільки в середньому до звички",
                       text: "У дослідженні — від 18 до 254 днів. Головне — повтор у тому ж місці й часі.",
                       number: .init(value: 66, unit: "днів"), visual: .dots(66), source: .lally),
            LearnSlide(kind: .fact, kicker: "Якорі", title: "Обери дві нагоди для склянки",
                       visual: .chips(options: ["🌅 Після пробудження", "🍽️ До їжі", "☕ З кавою", "🦷 Після чищення зубів",
                                                "🏋️ Після тренування", "💻 На перерві"],
                                      limit: 2, prompt: "Обери дві — і привʼяжи до них склянку")),
            LearnSlide(kind: .fact, kicker: "Середовище", title: "Що на очах — те й робиться",
                       text: "Пляшка на столі, склянка біля раковини — і рука тягнеться до води без нагадувань.",
                       visual: .tiles([.init(emoji: "🖥️", caption: "На столі"), .init(emoji: "🎒", caption: "У сумці"),
                                       .init(emoji: "🛏️", caption: "Біля ліжка"), .init(emoji: "🚗", caption: "В авто")])),
            LearnSlide(kind: .fact, kicker: "Пропуск", title: "Один день не зриває звичку",
                       text: "Пропуск майже не впливає на звичку. А серію врятує заморозка.",
                       visual: .chain(days: [.met, .met, .frozen, .met, .met, .today], labels: ["пн", "вт", "ср", "чт", "пт", "сб"],
                                      caption: nil),
                       source: .lally),
            LearnSlide(kind: .action(title: "Кнопки порцій", destination: .portionButtons), kicker: "Що з цим робити",
                       title: "Кнопки — під твою склянку",
                       text: "Постав на головний ті обʼєми, які справді пʼєш: склянку, кухоль, пляшку.",
                       visual: .emoji("🎛️"))
        ]
    }

    private func special() -> [LearnSlide] {
        [
            LearnSlide(kind: .fact, kicker: "Спорт", title: "Утрата з потом знижує витривалість",
                       text: "Зважся до й після тренування: кожен мінус кілограм — це ≈ 1–1,5 л води.",
                       number: .init(value: 2, unit: "%"),
                       visual: .bars([.init(label: "До", value: "75 кг", fraction: 1),
                                      .init(label: "Після", value: "74 кг", fraction: 0.86, isAccent: true)], legend: []),
                       source: .acsm),
            LearnSlide(kind: .fact, kicker: "Спека", title: "Пий наперед, а не коли вже душно",
                       text: "У спеку з потом може йти понад літр за годину. Склянка заздалегідь краща за пляшку потім.",
                       visual: .emoji("🌡️"), source: .acsm),
            LearnSlide(kind: .list, kicker: "Коли хворієш", title: "Самої води буває замало",
                       items: [.init(emoji: "🤒", title: "Температура", detail: "пий частіше, потроху"),
                               .init(emoji: "🤢", title: "Блювота чи діарея", detail: "регідратаційний розчин з аптеки"),
                               .init(emoji: "🧂", title: "Губляться солі", detail: "розчин повертає і воду, і їх"),
                               .init(emoji: "👩‍⚕️", title: "Дитина чи літня людина", detail: "до лікаря швидше")],
                       source: .who),
            LearnSlide(kind: .fact, kicker: "Ще коли пити більше", title: "Сухе повітря й жар",
                       visual: .tiles([.init(emoji: "✈️", caption: "Політ"), .init(emoji: "🏔️", caption: "Гори"),
                                       .init(emoji: "🧖", caption: "Сауна"), .init(emoji: "🍷", caption: "Після алкоголю")])),
            LearnSlide(kind: .action(title: "Додати порцію", destination: .customAmount), kicker: "Що з цим робити",
                       title: "Пляшку — одним тапом",
                       text: "Велика пляшка після тренування — у «Інше»: будь-який обʼєм одразу.", visual: .drop(level: 0.7))
        ]
    }

    // MARK: - Застосунок

    private func start() -> [LearnSlide] {
        let firstBlock = context.blocks.first
        return [
            LearnSlide(kind: .fact, kicker: "Порція", title: "Одним тапом",
                       text: "Кнопки можна змінити, а «Інше» — будь-який обʼєм.",
                       visual: .miniHome(goal: context.goalMl, buttons: context.presets)),
            LearnSlide(kind: .fact, kicker: "Помилка", title: "Не та порція? Є «Скасувати»",
                       text: "Кнопка зʼявляється в підказці одразу після порції. Пізніше — свайп по запису в історії.",
                       visual: .emoji("↩️")),
            LearnSlide(kind: .fact, kicker: "Кільце", title: "Понад 120 % уже не рахується",
                       text: "100 % — твоя норма. Воду понад 120 % застосунок запише, але XP і серія від неї не ростуть.",
                       number: .init(value: 120, unit: "%"), visual: .homeRing(percent: 100)),
            LearnSlide(kind: .fact, kicker: "Капсула", title: "Під кільцем — твоя частина доби",
                       text: "Скільки ще до кінця ранку, дня чи вечора — і скільки XP за це.",
                       visual: .dayPartPill(title: "До \(clock(firstBlock?.deadlineMinute ?? 12 * 60)) — ще \(context.volumeUnit.label(300))",
                                            xp: "+\(scaled(context.rules.perDayPartGoal)) XP", timeLeft: "1 год 20 хв")),
            LearnSlide(kind: .list, kicker: "Без застосунку", title: "Порцію можна додати й так",
                       items: [.init(emoji: "🧩", title: "Віджет", detail: "на робочому столі й екрані блокування"),
                               .init(emoji: "🔔", title: "Сповіщення", detail: "кнопка «+склянка»"),
                               .init(emoji: "🗣️", title: "Siri й «Команди»", detail: "«Додати воду»")]),
            LearnSlide(kind: .action(title: "Кнопки порцій", destination: .portionButtons), kicker: "Що з цим робити",
                       title: "Налаштуй під себе",
                       text: "Кнопки — під твою склянку, нагадування — під твій день.", visual: .emoji("🎛️"))
        ]
    }

    private func xp() -> [LearnSlide] {
        let rules = context.rules
        let unit = context.volumeUnit
        let step = max(1, rules.volumeStepMl)
        let perStep = scaled(rules.xpPerVolumeStep)
        let full = context.goalMl / step
        let capped = context.goalMl * 6 / 5 / step
        let road = levelRoad()
        var bonuses: [LearnSlide.Item] = [.init(emoji: "🎯", title: "Норма дня", value: "+\(scaled(rules.perDailyGoal))")]
        var segments: [WTLearnStackBar.Segment] = [.init(emoji: "💧", value: full * perStep, label: "вода"),
                                                   .init(emoji: "🎯", value: scaled(rules.perDailyGoal), label: "норма")]
        if context.dayRhythmEnabled, !context.blocks.isEmpty {
            bonuses.append(.init(emoji: "⏰", title: "Ранок, день, вечір", detail: "за кожну ціль",
                                 value: "+\(scaled(rules.perDayPartGoal))"))
            segments.append(.init(emoji: "⏰", value: context.blocks.count * scaled(rules.perDayPartGoal),
                                  label: "\(context.blocks.count) цілі"))
        }
        bonuses += [.init(emoji: "✅", title: "Завдання", detail: "щоденне / тижневе",
                          value: "\(questXp(.daily)) / \(questXp(.weekly))"),
                    .init(emoji: "🔥", title: "Серія", detail: "множить XP за воду", value: "до ×\(decimal(rules.streakMultiplierCap))")]
        // Типова пара щоденних — легке й середнє, ≈ 40 XP на день (SPEC-QUESTS §8).
        let questPair = rules.questXp(scope: .daily, difficulty: .easy) + rules.questXp(scope: .daily, difficulty: .medium)
        segments.append(.init(emoji: "✅", value: scaled(questPair), label: "завдання"))
        let visible = AchievementCatalog.active.filter { !$0.secrecy.isEgg }.count
        return [
            LearnSlide(kind: .fact, kicker: "Вода", title: "За кожні \(unit.portion(step)) — а не за натискання",
                       text: "Дві склянки по \(unit.portion(step / 2)) дають стільки ж, як одна на \(unit.number(step)). "
                           + "Понад 120 % норми XP не росте.",
                       number: .init(value: Double(perStep), prefix: "+", unit: "XP"),
                       visual: .glasses(full: full, bonus: max(0, capped - full), locked: 1, chip: "+\(perStep)",
                                        legend: ["норма", "до 120 %", "без XP"])),
            LearnSlide(kind: .list, kicker: "Бонуси", title: "Рівний день важить більше",
                       visual: .stack(unit: "XP", caption: "за рівний день з нормою", segments: segments), items: bonuses),
            LearnSlide(kind: .fact, kicker: "Досягнення", title: "Від першої склянки до року поспіль",
                       text: "Частина — таємні: їх знаходять випадково. За кожне — XP.",
                       number: .init(value: Double(visible), unit: ""), visual: .emoji("🏅")),
            LearnSlide(kind: .fact, kicker: "Рівні", title: "Новий рівень — це приз",
                       text: "До 10-го рівня приз — через рівень, далі — на кожному. Вибір і таємні призи чекають на тебе.",
                       visual: .ladder(road.nodes, progress: road.progress)),
            LearnSlide(kind: .action(title: "Шлях рівнів", destination: .levelRoad), kicker: "Що з цим робити",
                       title: "Зазирни у свій шлях", text: road.summary, visual: .level(context.level))
        ]
    }

    private func streak() -> [LearnSlide] {
        let rules = context.rules
        let days = Int(((rules.streakMultiplierCap - 1) / max(0.001, rules.streakMultiplierStep)).rounded())
        let sampleDays = [1, 3, 5, 7, days]
        let freezeLevel = (2...30).first { level in
            if case .prize(let grant) = LevelRoadCatalog.node(forLevel: level) { return grant.key == RewardCatalog.freezeKey }
            return false
        } ?? 8
        let choiceLevel = (2...30).first { level in
            if case .choice = LevelRoadCatalog.node(forLevel: level) { return true }
            return false
        } ?? 4
        return [
            LearnSlide(kind: .fact, kicker: "Серія", title: "Дні поспіль із нормою",
                       text: "Крапля з числом у шапці головного — твоя серія. Норму закрито — серія росте.",
                       visual: .chain(days: [.met, .met, .met, .met, .met, .met, .today],
                                      labels: CalendarService.weekdayLabels, caption: "6 днів поспіль")),
            LearnSlide(kind: .fact, kicker: "Множник", title: "Серія множить XP за воду",
                       text: "Кожен день серії додає +\(Int((rules.streakMultiplierStep * 100).rounded())) % — до ×\(decimal(rules.streakMultiplierCap)) на \(days)-й день.",
                       number: .init(value: rules.streakMultiplierCap, decimals: 1, prefix: "×", unit: ""),
                       visual: .bars(sampleDays.map { day in
                           let multiplier = rules.multiplier(streak: day)
                           return .init(label: "\(day)-й", value: "×\(decimal(multiplier, digits: 2))",
                                        fraction: multiplier / rules.streakMultiplierCap, isAccent: day == days)
                       }, legend: [])),
            LearnSlide(kind: .fact, kicker: "Заморозка", title: "Рятує вчорашній день",
                       text: "Учора пропуск, а позавчора — норма? Заморозка тримає ланцюг, але до числа день не додає.",
                       visual: .chain(days: [.met, .met, .frozen, .met, .today], labels: ["пн", "вт", "ср", "чт", "пт"],
                                      caption: "Ланцюг цілий")),
            LearnSlide(kind: .list, kicker: "Де взяти", title: "Заморозки дають рівні й таємні призи",
                       items: [.init(emoji: "🪜", title: "Шлях рівнів", detail: "\(freezeLevel)-й рівень і вибір на \(choiceLevel)-му"),
                               .init(emoji: "🎁", title: "Таємні призи", detail: "заморозка — частий вміст"),
                               .init(emoji: "📦", title: "«Призи»", detail: "там вони й чекають")]),
            LearnSlide(kind: .fact, kicker: "Обрив", title: "Знову в ритмі",
                       text: "Серія від \(rules.bounceBackMinStreak) днів обірвалась? Перший день з нормою після неї дає +\(scaled(rules.perBounceBack)) XP.",
                       visual: .emoji("🌱")),
            LearnSlide(kind: .action(title: "Мої призи", destination: .prizes), kicker: "Що з цим робити",
                       title: "Перевір свої заморозки",
                       text: "Призи чекають у «Призах» — заморожувати день можна лише звідти.", visual: .emoji("🧊"))
        ]
    }

    private func prizes() -> [LearnSlide] {
        let road = levelRoad()
        let token = { (key: String, title: String, caption: String) -> WTLearnTokens.Token in
            WTLearnTokens.Token(emoji: RewardCatalog.definition(key)?.emoji ?? "🎁", title: title, caption: caption)
        }
        return [
            LearnSlide(kind: .fact, kicker: "Три призи", title: "Заморозка, ×2 і ×3",
                       visual: .tokens([token(RewardCatalog.freezeKey, "Заморозка", "рятує вчорашній день"),
                                        token(RewardCatalog.boostKey, "×2 XP", "до \(clock(0))"),
                                        token(RewardCatalog.tripleKey, "×3 XP", "лише з таємних")])),
            LearnSlide(kind: .fact, kicker: "Жетон", title: "Приз чекає, доки ти натиснеш",
                       text: "Буст діє до \(clock(0)), один на раз, і множиться із серією. Заморозка рятує вчорашній день.",
                       visual: .emoji("🎟️")),
            LearnSlide(kind: .fact, kicker: "Шлях рівнів", title: "Що дає кожен рівень",
                       text: "До 10-го — приз через рівень, з 11-го — на кожному.",
                       visual: .ladder(road.nodes, progress: road.progress)),
            LearnSlide(kind: .fact, kicker: "Вибір і таємний", title: "Деякі призи чекають рішення",
                       text: "На вузлі вибору обираєш буст чи заморозку. Таємний відкриваєш — і бачиш, що всередині.",
                       visual: .emoji("🎁")),
            LearnSlide(kind: .action(title: "Шлях рівнів", destination: .levelRoad), kicker: "Що з цим робити",
                       title: "Відкрий свій шлях", text: road.summary, visual: .level(context.level))
        ]
    }

    private func reminders() -> [LearnSlide] {
        [
            LearnSlide(kind: .fact, kicker: "Нагадування", title: "Лише коли відстаєш",
                       text: "План складається наперед. Випито вчасно — нагадування зсувається саме.",
                       visual: .dayLine(drops: [0.04, 0.22, 0.45, 0.72, 0.9], bells: [0.33, 0.6],
                                        start: clock(context.wakeMinutes),
                                        end: clock(context.sleepMinutes))),
            LearnSlide(kind: .list, kicker: "Тиша", title: "Застосунок знає міру",
                       items: [.init(emoji: "🌙", title: "Не вночі", detail: "лише між підйомом і відбоєм"),
                               .init(emoji: "🔢", title: "Не більше \(context.dailyCap) на день"),
                               .init(emoji: "⏸️", title: "Пауза й тихі години", detail: "у налаштуваннях сповіщень")]),
            LearnSlide(kind: .list, kicker: "Що ще приходить", title: "Не лише «пора пити»",
                       items: [.init(emoji: "🌅", title: "Ранкова склянка"),
                               .init(emoji: "🎯", title: "Ціль частини доби", detail: "якщо до неї бракує"),
                               .init(emoji: "📊", title: "Звіт дня й тижня", detail: "тихо, без звуку"),
                               .init(emoji: "🧊", title: "Порятунок серії", detail: "коли її ще можна врятувати")]),
            LearnSlide(kind: .fact, kicker: "Ритм дня", title: "Можна й без цілей частин доби",
                       text: "Вимкни «Ритм дня» — і лишиться просто норма за день, без цілей ранку, дня й вечора.",
                       visual: .emoji("🎚️")),
            LearnSlide(kind: .fact, kicker: "Свій графік", title: "Застосунок підлаштується",
                       text: "Пʼєш раніше чи пізніше, ніж у налаштуваннях? Застосунок запропонує зсунути підйом і відбій.",
                       visual: .emoji("🧭")),
            LearnSlide(kind: .action(title: "Сповіщення", destination: .notifications), kicker: "Що з цим робити",
                       title: "Налаштуй під свій день",
                       text: "Частота, тиша й типи нагадувань — в одному місці.", visual: .emoji("🔔"))
        ]
    }

    // MARK: - Спільне

    private func quiz(_ kicker: String, _ statement: String, isTrue: Bool, _ explanation: String,
                      source: LearnSource) -> LearnSlide {
        LearnSlide(kind: .quiz(isTrue: isTrue, explanation: explanation), kicker: kicker, title: statement,
                   visual: .question, source: source)
    }

    /// Норма, поділена на цілі частин доби; без «Ритму дня» — одна ціль на день.
    private var normRing: LearnVisual {
        let blocks = context.dayRhythmEnabled ? context.blocks : []
        let total = max(1, blocks.reduce(0) { $0 + $1.targetMl })
        let unit = context.volumeUnit
        return .ring(total: unit.number(context.goalMl), caption: "\(unit.symbol) на день",
                     segments: blocks.isEmpty ? [.init(label: "Норма", value: unit.number(context.goalMl), share: 1)]
                         : blocks.map { block in
                             .init(label: "\(block.title) · до \(clock(block.deadlineMinute))",
                                   value: unit.number(block.targetMl), share: Double(block.targetMl) / Double(total))
                         })
    }

    private func clock(_ minutes: Int) -> String { ReportFormat.clock(minutes, context.timeFormat) }

    /// Драбина довкола поточного рівня: два взяті призи, наступний і два далі.
    private func levelRoad() -> (nodes: [WTLearnLadder.Node], progress: Double, summary: String) {
        let level = context.level
        let rewardLevels = (2...(level + 40)).filter { LevelRoadCatalog.node(forLevel: $0) != nil }
        let done = rewardLevels.filter { $0 <= level }.suffix(2)
        let ahead = rewardLevels.filter { $0 > level }.prefix(5 - done.count)
        let levels = Array(done) + Array(ahead)
        let nodes = levels.map { lv -> WTLearnLadder.Node in
            let (emoji, title) = describe(LevelRoadCatalog.node(forLevel: lv))
            let state: WTLearnLadder.State = lv <= level ? .done : lv == ahead.first ? .next : .later
            return .init(emoji: emoji, caption: "\(lv)-й рівень" + (state == .next ? " · наступний" : ""),
                         title: title, state: state)
        }
        let progress = levels.count > 1 ? max(0, Double(done.count) - 0.5) / Double(levels.count - 1) : 0
        let next = ahead.first ?? level + 1
        let nextTitle = describe(LevelRoadCatalog.node(forLevel: next)).title.lowercased()
        return (nodes, progress, "Ти на \(level)-му рівні. Наступний приз — на \(next)-му: \(nextTitle).")
    }

    private func describe(_ node: LevelNode?) -> (emoji: String, title: String) {
        switch node {
        case .prize(let grant):
            let definition = RewardCatalog.definition(grant.key)
            return (definition?.emoji ?? "🎁", definition?.title ?? "Приз")
        case .choice(let grants):
            return (grants.compactMap { RewardCatalog.definition($0.key)?.emoji }.joined(), "Вибір з двох")
        case .mystery(let pool):
            return ("🎁", pool.isGrand ? "Великий таємний приз" : "Таємний приз")
        case nil:
            return ("🎁", "Приз")
        }
    }

    /// «+15–40» — діапазон за складністю (SPEC-QUESTS §8).
    private func questXp(_ scope: QuestScope) -> String {
        let range = context.rules.questXpRange(scope)
        return "+\(scaled(range.lowerBound))–\(scaled(range.upperBound))"
    }

    /// XP з урахуванням загального множника балансу — як у довіднику «Звідки XP».
    private func scaled(_ xp: Int) -> Int {
        Int((Double(xp) * context.rules.xpMultiplier).rounded())
    }

    private func decimal(_ value: Double, digits: Int = 1) -> String {
        var text = String(format: "%.\(digits)f", value)
        while digits > 1, text.hasSuffix("0") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: ",")
    }
}

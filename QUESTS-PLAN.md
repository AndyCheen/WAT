# План реалізації WAT-29 — завдання: щоденні, тижневі, несподівані

> **Для виконавця.** ТЗ — `SPEC-QUESTS.md` (посилання `ТЗ §N` ведуть туди). Макет — `Design/Quests.html`, варіант
> **A «Розділи»**. Правила репозиторію — `CLAUDE.md`. Найважливіші тут:
>
> - час — лише `Clock`; доба, хвилина, тиждень — через `CalendarService`;
> - `metrics.commit()` — раз на дію;
> - кольори, розміри й анімації — токени `DesignSystem`, жодних магічних чисел у `Features`;
> - `accessibilityIdentifier` не вішати на контейнер;
> - `xcodebuild` — лише з `-derivedDataPath DerivedData`;
> - тексти — на «ти», без родового минулого часу;
> - вибір завдань — `StableHash`, ніколи `random` чи `hashValue`.

**Три підзадачі Linear — три PR**, кожен — логічні коміти. Підзадачі під WAT-29: §1 — WAT-63, §2 — WAT-64, §3 — WAT-65.
Порядок суворий: §2 спирається на знімок із §1, §3 — на обидва.

1. **Двигун і каталог** (§1) — Persistence, Gamification, трохи Features і App. Після нього застосунок уже видає
   нові завдання в старому вигляді рядків.
2. **Головний, 3f, віджет** (§2) — DesignSystem, Features, Widgets, e2e. Закриває WAT-35.
3. **Несподівані** (§3) — Insights, Gamification, Notifications, Persistence, Features, Widgets, e2e. Забирає з
   WAT-38 несподівані завдання й налаштування.

Що вже є і на що спиратися:
- `QuestEngine` (`Packages/Gamification/Sources/Gamification/QuestEngine.swift`);
- `QuestCatalog` (`Catalogs.swift`, перша секція);
- `QuestInstance`, `QuestScope.adhoc`, `QuestState` (`Persistence/Models`);
- `RewardSource.quest`, `NotificationType.challenge`, `NotificationPriority.challenge`, `DailyCap` з `.challenge`;
- `Insights.weakDayPart(days:)`;
- `GoalBlock`, `TimedPortion`, `PaceCurve.minute(reaching:)` (`Core`);
- `FirstWeekSimulation` + `AchievementBudgetTests` (`Packages/Features/Tests/FeaturesTests`).

---

## 1. Двигун і каталог (WAT-63)

### 1.1 Persistence

- **`QuestInstance`** (`GamificationRecords.swift`) — нові поля з типовими значеннями (легка міграція, як
  `celebratedAt` у WAT-62):
  - `rewardXp: Int = 0` — XP фіксується при видачі (ТЗ §8);
  - `difficultyRaw: Int = 0`;
  - `deadlineMinute: Int?` — T для «до T» і кінця блоку; `expiresAt` (уже є) — абсолютний дедлайн;
  - `blockIndex: Int?` — Д7, Н2;
  - `count: Int?` — N для Д6 і тижневих;
  - `weekdayIndex: Int?` — Н3.
- **`QuestState`** — `case cancelled = 4`, у кінець (raw зберігається). Скасоване до появи несподіване
  (ТЗ §6.4) не рахується як проігнороване.
- **`DayLogRepository.firstActiveDayKey()`** — перший день із `entriesCount > 0`. `earliestDayKey()` бере будь-який
  `DayLog`, зокрема створений знімком розкладу без порцій. Один запит з `fetchLimit = 1`, тест у `DayLogRepositoryTests`.
- **Ключі періоду не міняються:**
  - щоденне — `yyyy-MM-dd`;
  - тижневе — `WeekKey`;
  - несподіване — `adhoc:yyyy-MM-dd` (`GamificationStore.quests(scope: .adhoc)` уже фільтрує за префіксом `adhoc`).

### 1.2 День завдань — `QuestDay`

Новий файл `Gamification/Quests/QuestDay.swift`.

- **Факти одного дня з `DayLog`:**
  - порції `[TimedPortion]` — лише активні; хвилина — `calendar.minuteOfDay`;
  - розклад — `profile.schedule(for: log, isWeekend:)`, як у `DayHistory.record(from:)`;
  - норма — `goalMlSnapshot`;
  - `PaceCurve`, `goalBlocks()`;
  - `goalAhead` — `metrics.sum(.dayGoalAhead, periodType: .day, periodKey:)` > 0.
- **День без `DayLog`** (сьогодні до першої порції) — розклад і норма з профілю, порцій немає.
- **Кеш** `[dayKey: QuestDay]` на `GamificationService`. Скидати там само, де `history.invalidate(day:)`
  (`noteAchievementInputs`), а повністю — на `refresh`. `PerformanceTests` (межа на порцію) мають лишитися зеленими.

### 1.3 Умови — `DayCondition` і `QuestCondition`

Новий файл `Gamification/Quests/QuestCondition.swift`. Одна функція оцінки, яку ділять щоденні, тижневі й
несподівані.

```swift
enum DeadlineRule { case wakePlus(minutes: Int), curveShare(Double), personalGoal, blockEnd }
enum DayCondition {
    case shareBy(Double, DeadlineRule)          // Д1, Д2, Д11, Д3; Т6, Т8
    case wakeGlass(withinMinutes: Int)          // Д5, Т5
    case glasses(minMl: Int, deadline: DeadlineRule?)   // Д6, Д10 (N — з інстансу)
    case blockReached                            // Д7 (блок — з інстансу)
    case portionInEachBlock(minMl: Int)          // Д8
    case allBlocks                               // Д9, Т7
    case goalAhead                               // Д4
    case goal, halfGoal, anyPortion              // С1–С3, Т1, Т2, Т3, Т4
}
enum QuestCondition {
    case day(DayCondition)
    case daysCount(DayCondition)                 // Т1, Т3, Т5, Т6, Т7, Т8
    case daysRun(DayCondition)                   // Т2
    case weekend(DayCondition)                   // Т4
    case window(minMl: VolumeTarget, minutes: Int)       // Н1, Н4 (§3)
    case surpriseBlock, surpriseGoal             // Н2, Н3 (§3)
    case legacy(MetricRule, QuestTarget)         // архівні (ТЗ §3.7)
}
```

- `evaluate(_ condition:, day: QuestDay, params:) -> (progress: Double, target: Double, met: Bool)` — чиста функція.
- **«До T»** — порції з хвилиною < T. Порції до підйому йдуть у перший блок і в «після підйому» (ТЗ §3.2, §7).
- **Обʼємні цілі** — `VolumeTarget` (мл), округлені за системою людини (ТЗ §4.4). Для унцій —
  `VolumeUnit.milliliters(units:)` від цілого числа унцій. Порівняння ≥ з допуском 0,5 мл.
- **Резолв дедлайну:**
  - `wakePlus` — W + m;
  - `curveShare` — `curve.minute(reaching: G·s)`, вниз до 30 хв;
  - `personalGoal` — ТЗ §4.4;
  - `blockEnd` — `block.toMinute`.

  Резолвиться в мить видачі й пишеться в `deadlineMinute` / `expiresAt`. Для тижневих — на кожен день окремо, з
  розкладу того дня.

### 1.4 Каталог

`QuestCatalog` переїжджає з `Catalogs.swift` у `Gamification/Quests/QuestCatalog.swift`.

- **`QuestDefinition`:**
  - `key`, `scope`, `slot` (`QuestSlot: tempo, rhythm, starter, steady, habit, surprise`);
  - `condition`;
  - `difficulty` — фіксована або від N, як Т1 / Т2 (ТЗ §3.4);
  - `requirements` (`dayRhythm`, `remindersActive`, `minLevel`);
  - `title: QuestTitle` — шаблон із параметрами, без готового рядка: час і одиниці форматує `Features`;
  - `isRetired`.
- **Рядки** — дослівно з ТЗ §3.1–3.5 (ключі не міняти після релізу: на них історія ротації). Несподівані (ТЗ §3.6) —
  у §3 цього плану.
- **Архівні:** `daily.goal`, `daily.entries4`, `daily.morning`, `weekly.streak7`, `weekly.goal5days` — з `legacy(...)`
  і старим `rewardXp`. Не видаються, але `definition(_:)` їх знаходить: інстанси поточного дня й тижня доживають.
- **`dailySlots`** прибрати.

### 1.5 XP

`XPRules`:
- `perDailyQuest` / `perWeeklyQuest` замінити на `dailyQuestXp = [15, 25, 40]`, `weeklyQuestXp = [75, 100, 150]`,
  `surpriseShortXp = 25`, `surpriseLongXp = 50` і `questXp(scope:difficulty:)`;
- коментар `perBounceBack` («як щоденне завдання») оновити.

`awardQuestXP` бере `quest.rewardXp` з інстансу, а для архівних без нього — з визначення.

### 1.6 `DailyQuestPicker`

Новий файл, чиста функція — ТЗ §4 дослівно.

- **Вхід** `DailyPickInput`:
  - день, номер дня людини, зерно (`mysterySeed`), рівень, «Ритм дня», `remindersActive`;
  - розклад, норма, `P`, хвилина видачі;
  - чи закрито норму вчора, днів із нормою за 7, ключі щоденних за 7 днів;
  - медіани першої порції й закриття норми за 14 днів, блок-ціль Д7.
- **Вихід** — `[QuestPick]` (ключ + резолвлені параметри + складність + XP).
- **Стартові дні** (ТЗ §3.3) — тут же.
- **Зважений вибір:** `StableHash.fnv1a("<seed>|<day>|<slot>") % Σваг`, ваги цілі.
- **Блок-ціль Д7:** медіана «випито в блоці / ціль» за 14 днів із `QuestDay`. Тільки для «Ритму дня».

### 1.7 `WeeklyQuestPicker`

Новий файл, чиста функція — ТЗ §5 дослівно.

- **Вхід:** тиждень, індекс сьогоднішнього дня (0 — пн), чи це перший тиждень людини, зерно, рівень, «Ритм дня».
- **Історія:** днів із нормою по 4 повних тижнях; ключі й стани тижневих минулого тижня; частка норми за 14 днів;
  частки «вихідні / будні» за 4 тижні; Д2-успіхи за 7 днів.
- **Вихід** — 0–2 `QuestPick` з N і складністю.

### 1.8 `QuestEngine`

Переписати `QuestEngine.swift` на пікери й умови. Публічний інтерфейс — під `GamificationService`.

- **`ensureInstances(input:)`:**
  - щоденних за сьогодні немає → `DailyQuestPicker`;
  - тижневих за тиждень немає і днів лишилось ≥ 4 → `WeeklyQuestPicker`;
  - інстанси старих ключів, що вже є за сьогодні чи тиждень, лишаються, і нових поверх них не додаємо.
- **`evaluate(at:triggerRef:)`:**
  - щоденні сьогодні, тижневі тижня і, після §3, несподівані сьогодні;
  - тижневі рахують дні від дня `assignedAt` до сьогодні.
  - Повертає щойно виконані, як зараз.
- **`expireOverdue(at:)`** — невиконані з `expiresAt < now` → `.expired`. Викликати з `refresh` і `evaluate`.
- **`revert(...)`** — як зараз, на нових умовах; прострочене знову не відкривається.
- **`board(at:) -> QuestBoard`:**
  - `daily`, `weekly` — без прострочених невиконаних;
  - `weeklyStartsMonday: Bool` — Пт–Нд без тижневих;
  - `surprise: QuestSnapshot?` — `nil` до §3.

### 1.9 `GamificationService`

- **Збирає входи пікерів** з `dayLogs`, профілю, `xp.progress().level`, історії інстансів за 28 днів, `QuestDay`.
- **`public var remindersActive: () -> Bool = { false }`** ставить `AppServices`: увімкнено, дозволено, нагадування
  увімкнено. Так само, як `notificationsAuthorized`.
- **`questBoard(at:)`** замінює `dailyQuests()` / `weeklyQuests()` (або вони лишаються обгортками над ним для
  віджета й підказок).
- **`recordAllDailyQuestsIfDone`** — без змін за змістом: «усі щоденні дня», хай і одне.
- **Вада відкату** (ТЗ §7). У `metricsDidRevert` для кожного `reopened` — `metrics.revert(sourceRef: quest.id, at: date)`
  **до** `achievements.revert(...)`. Це відкотить `quest.completed` і `quest.weeklyCompleted`, тож досягнення
  «Тижнева мета» й «Сотня завдань» знімуться. `isEvaluating` уже стоїть — повторного входу не буде.
- **`internalMetrics`** — без змін (у §3 додасться `.surpriseQuestCompleted`).

### 1.10 Знімок

`QuestSnapshot` (`Snapshots.swift`):
- додати `kind` (`.volume / .count / .days`), `title: QuestTitle`, `deadline: Date?`, `difficulty`, `rewardXp` з
  інстансу, `slot`;
- **`progressLabel` і `title: String` прибрати** — тексти переходять у `QuestPresenter` (§2.2);
- до §2 тимчасовий `QuestPresenter` у `Features` уже потрібен для старих рядків. Зробити його тут, а в §2 доповнити.
- Розширення `active` / `completed` лишити.

### 1.11 Features і App (мінімум для §1)

- **`AppServices+Notifications.questHints`** — на нові ключі (ТЗ §9.4):
  - `morningQuestActive` — активне `daily.wakeGlass`;
  - `oneEntryLeftTitle` — `daily.glasses` / `daily.glassesBy` з одним залишком;
  - `weeklyClosesToday` — `weekly.goalDays` (`target − progress == 1`) або `weekly.weekend` (субота виконана), у неділю
    без норми.
- **`gamification.remindersActive`** — в `AppServices` поруч із `notificationsAuthorized`.
- **Довідник «Звідки XP»** (`LevelRoadPresenter`) і `LearnPresenter.questXp` — діапазони з `XPRules` (ТЗ §8):
  «+15–40 XP», «+75–150 XP». Перевірити тексти історій «XP і рівні» на згадки старих завдань.
- **DEBUG-прапорець `--quests`** (`LaunchConfiguration`):
  `--quests daily:daily.wakeGlass,daily.glasses;weekly:weekly.goalDays=5,weekly.wakeGlassDays=5`. Видає саме ці
  завдання повз пікери — e2e не залежать від зерна профілю. Без прапорця під `--uitest-*` — звичайний пікер.
  Задокументувати в `CLAUDE.md` разом з іншими прапорцями.
- **`SmokeUITests`** (тест «Додати 4 записи» з `home.tasks.toggleCompleted`) — на `--quests` з `daily.glasses`, логіка
  та сама. Остаточний вигляд — у §2.

### 1.12 Тести (`GamificationTests`, `FeaturesTests`)

- **`QuestCatalogTests`:**
  - ключі унікальні;
  - у кожного неархівного — слот і складність;
  - XP з `XPRules`;
  - найгірші назви (12 год, унції, N = 5) — ≤ 28 символів;
  - без родових форм.
- **`QuestConditionTests`** — на кожну умову: порція до підйому для Д5; «до T» строго; Д8 з порцією до підйому; Д6 з
  порцією 100 мл не рахується; унції (8 унц. = ціль 250 мл зараховує 8 унц.); Д4 з `day.goalAhead`.
- **`DailyQuestPickerTests`:**
  - детермінованість (той самий вхід → той самий вибір);
  - бюджет ≤ 4; після дня без норми — лише легкі з сумою ≤ 2;
  - складні — лише з ≥ 5 днями норми з 7;
  - без «Ритму дня» — одне з об'єднаного пулу;
  - без нагадувань — без Д4; рівень < 5 — без Д4 і Д9;
  - не вчорашнє; дедлайн < 60 хв — не допущене;
  - стартові дні.
  - **Ротація:** 12 тижнів × 4 типи людей (сильний з усім ввімкненим, середній, без ритму, без нагадувань) — правило
    «≤ 2 за 7 днів» не ламається, а середній інтервал повтору ≥ 4 дні (≥ 6 без ритму).
- **`WeeklyQuestPickerTests`:**
  - видача лише Пн–Чт; перший тиждень — одне легке;
  - N: +1 / −1, межі 3…6, запасний день;
  - Т3 для тих, кому важко;
  - «Звичка» не повторює минулий тиждень;
  - Т2 не допущене, коли N < 3.
- **`QuestEngineTests`:**
  - тижневі рахують лише з дня видачі;
  - прострочене зникає з `board` і не відкривається відкатом;
  - архівний інстанс доживає період;
  - XP з інстансу, буст множить, серія — ні.
- **`GamificationServiceTests`** — відкат порції, що закрила тижневе: XP знято, «Тижнева мета» знята, `quest.completed`
  відкочено. Наявні тести на старі ключі (`daily.entries4` тощо) перевести на `--quests`-подібний ін'єкційний вхід
  або нові ключі.
- **`FeaturesTests`** — `questHints` на нових ключах.

### 1.13 Документація

- **`CLAUDE.md`**, архітектура: абзац «Завдання» (пікери, `QuestDay`, умови, XP з інстансу, архівні ключі, `--quests`).
- **`PLAN.md`:** п. 23 «Що з'ясувалося» закрито; `XPRules` у §5.

---

## 2. Головний, 3f, віджет (WAT-64)

### 2.1 DesignSystem

- **`WTTaskRow`** (`Rows.swift`) розширити, не ламаючи наявних викликів:
  - `fraction: Double?` — міні-кільце в кружку (у макеті 26 pt, лінія 3,5);
  - `xp: Int?` — чип «+N»;
  - `isCelebrating: Bool` — анімація ✓ і «+N XP».

  Розміри й час анімації — токени (`WTAnimation`, `WTSpacing`).
- **Згортання рядка** після свята — модифікатор у `DesignSystem`, щоб `Features` не мав магічних 1,5 с.
- **`WTFeedback.questDone`** — легкий успіх.
- **Прев'ю:** світла й темна теми, Dynamic Type до межі `.wtTypeSizeLimit()`.

### 2.2 `QuestPresenter` (Features)

Чисті функції від `QuestSnapshot`, `VolumeUnit`, `TimeFormat`:
- **`title`:**
  - час — `TimeFormat.clock`;
  - N з `Plural` (3/4 склянки, 5 склянок; 3/4 дні, 5 днів; 3 ранки, 5 ранків; 2/3 ідеальні дні);
  - блок — «ранок / день / вечір».
- **`progressLabel`:**
  - «ще N мл» вгору до 50, «ще N унц.»;
  - «2/4», «2/5 дн.», «Готово».
- **Підписи секцій і порожні стани** — ТЗ §9.1: «ЦЬОГО ТИЖНЯ · ЩЕ 5 ДН.», «Усе на сьогодні 🎉», «Тиждень закрито 🎉»,
  «Тижневі завдання — з понеділка».
- **`accessibilityLabel`** рядка: «Половина до 14:00, ще 500 мл, 25 XP».

Тести — `QuestPresenterTests` на мл і унції, 24 і 12 год, плюралі.

### 2.3 Головний

**`HomeViewModel`:**
- `questBoard` замість `quests`; видимі списки, `completedQuestCount`, `showCompletedQuests` — з урахуванням секцій.
- **Щойно виконані дією:** порівняти `board` до і після `add` → `celebratingQuestIds`.
- **Якщо `presentCelebrations` показав вікно** — свято рядків відкладається до `celebrationDidClose`.
- **Вібрація — одна на дію**, у наявному ланцюгу `pulse`: `questDone` лише коли інших немає.
- **Хвилина** — від `Clock`; рядки з дедлайном зникають, поки екран відкритий (`TimelineView` лише будить екран,
  як для капсули частини доби).

**`HomeScreen.tasks`** — варіант A з макета:
- шапка «ЗАВДАННЯ» + «Виконані · N»;
- підзаголовки «СЬОГОДНІ» / «ЦЬОГО ТИЖНЯ · ЩЕ N ДН.»;
- рядки з `WTTaskRow(fraction:xp:)`;
- порожні стани.

Місце під картку несподіваного — у §3.

**Ідентифікатори:**
- `quest.row.<key>` на рядку, не на контейнері;
- `home.tasks.toggleCompleted` (є);
- `home.tasks.weeklyStartsMonday`.

### 2.4 3f без завдань (закриває WAT-35)

- `ProgressScreen.tasksBlock`, `questRows` і поля завдань у `ProgressViewModel` — прибрати.
- Тести, що їх читають, — прибрати.
- Порядок блоків 3f: донат → нагорода → призи → досягнення.

### 2.5 Віджет «Прогрес» (M)

- **`WidgetSnapshot.Quest`** — додати `expiresAt: Date?`, `isWeekly: Bool`. Нові поля — опційні: старий знімок у
  App Group мусить декодуватися.
- **`WidgetSnapshot`** — `weeklyStartsMonday: Bool?`.
- **`AppServices+Widgets`:**
  - підписи — з `QuestPresenter`;
  - прострочені не кладемо;
  - дедлайни — в `expiresAt`.
- **`WidgetTimeline.dates`** — записи на `expiresAt` щоденних сьогодні (ТЗ §9.3), у межах наявної стелі каденції.
- **`WidgetViews` (Прогрес):**
  - до 3 рядків: щоденні (2), тижневе (1);
  - стани «✓ Усе на сьогодні», «✓ Тиждень закрито», «З понеділка»;
  - ліва половина — `Link(watertracker://progress)`, права — `Link(watertracker://home)`.
- **`WidgetSample`** — нові назви.
- **DEBUG-галерея `--start-screen widgets`** показує нові стани.

### 2.6 e2e

- **`SmokeUITests`:** `--quests daily:daily.wakeGlass,daily.glasses --uitest-now <07:10>` → порція 250 → рядок
  «Склянка після підйому» святкує й зникає (`waitForNonExistence`), «Виконані · 1» → розгортає → рядок `isHittable`.
- **Новий тест:** дедлайн — `--uitest-now` після 08:00 з невиконаним Д5 — рядка немає, секції «Сьогодні» немає, якщо
  друге теж прострочене.
- **3f** — блоку «ЗАВДАННЯ» немає.
- **`WidgetsUITests`** — рядки «Прогресу» в галереї.

### 2.7 Бюджет і документація

- **`FirstWeekSimulation`** (персони «Типовий», «Старанний», «Дослідник»). Перевірки:
  - у день 1 — стартова пара;
  - 0 тостів за завдання;
  - щоденних на головному ≤ 2.

  `AchievementBudgetTests` — межі досягнень лишаються в силі. Якщо нові ключі зсунули числа — виправити каталог,
  а не межу.
- **Документація:**
  - `CLAUDE.md` — розділ «Головний / Завдання» і віджети;
  - `SPEC-WIDGETS.md` §3.7 — новий вигляд «Прогресу»;
  - `PLAN.md` §7.1–7.2 — рядок завдань на 1a, 3f без завдань.
- **WAT-35** → Done разом із PR.

---

## 3. Несподівані (WAT-65)

### 3.1 Insights

- **`weakWeekday(days:) -> WeakWeekday?`** (`Reports.swift`) — ТЗ §6.2: 42 дні; медіана «випито / норма» дня тижня
  < 0,7, інших ≥ 0,85; ≥ 3 таких дні.
- Пороги — у `ReportRules`, поруч із `weakMedian`.
- Тести в `InsightsTests`.

### 3.2 Сигнали й тихі періоди — від `AppServices`

`Gamification` не імпортує `Insights` і `Notifications`, тож сигнали приходять замиканнями:
- `gamification.surpriseSignals: () -> SurpriseSignals` — `weakDayPart` за 14 днів і `weakWeekday` за 42 дні,
  обидва до вчора. Кешувати в `AppServices` за `dayKey`: потрібні раз на день, у першу дію.
- `gamification.quietMinutes: (DayKey) -> [Range<Int>]` — з увімкнених `QuietPeriod` на цей день тижня.

### 3.3 Persistence

`UserProfile.surpriseQuestsPerWeek: Int = 2` (0 / 1 / 2).

### 3.4 Каталог і `SurprisePicker`

- **Рядки Н1–Н4** — ТЗ §3.6. Умови: `window`, `surpriseBlock`, `surpriseGoal`. XP — `surpriseShortXp` /
  `surpriseLongXp`.
- **`SurprisePicker`** — новий файл, чиста функція, ТЗ §6.1–6.3 дослівно.
  - **Вхід:**
    - сьогодні, номер дня людини, зерно, налаштування 0/1/2;
    - несподівані цього тижня й учора, стани двох останніх (для відступу);
    - виконані Н1 за 28 днів за блоками;
    - сигнали, розклад, тихі хвилини;
    - ключі сьогоднішніх щоденних, хвилина першої дії, чи закрито норму.
  - **Вихід** — `QuestPick?` з `assignedAt`, `expiresAt`, блоком або днем тижня.
  - **Дні-кандидати:** `StableHash("<seed>|<week>|surprise")` — для двох: `d1 = h % 7`,
    `d2 = (d1 + 2 + (h / 7) % 4) % 7`. Слабкий день тижня — завжди кандидат.

### 3.5 Двигун

- **`ensureInstances`** — у першу подію дня, після щоденних: `SurprisePicker` → інстанс `adhoc:<день>` з `assignedAt`
  у майбутньому.
- **`evaluate`:**
  - до `assignedAt` — перевірка скасування (ТЗ §6.4) → `.cancelled`;
  - у вікні — прогрес за `window` / блоком / нормою;
  - після — `.expired`.
- **`board.surprise`** — видиме, якщо `assignedAt ≤ now` і (активне й `now < expiresAt` або виконане сьогодні).
- **`awardQuestXP`** для несподіваного:
  - XP;
  - подія `quest.surpriseCompleted` з `sourceRef: quest.id` — додати в `MetricKey` і в `internalMetrics`, як
    тижневу;
  - ⚡ — `grantPrize(key: RewardCatalog.boostKey, source: .quest, ref: quest.id)`. Параметра `ref` у `grantPrize`
    зараз немає — додати (`acquiredByRef`) і дедуплікувати за ним, як `grantComebackGiftIfDue`. Відкат приз не
    забирає.
- **Досягнення «Несподіванка»** — дослівно з коментаря WAT-61 у WAT-29:
  - рядок `quest.firstSurprise` у `AchievementCatalog`;
  - `AchievementGate.surpriseQuests` з підписом «Увімкни несподівані завдання», поле в `AchievementGates` —
    відкрито, коли `surpriseQuestsPerWeek > 0`;
  - числа в тестах: 111 → 112 чинних, 101 → 102 видимих, легких 42 → 43.

### 3.6 Сповіщення

- **`NotificationContext.surprise: SurpriseSlot?`** — лише на сьогодні: id, вид, `fireAt`, дедлайн, ціль у мл, назва
  блоку чи день тижня, XP. Збирає `AppServices+Notifications` з `board` (активне, ще не видиме).
- **`PlanBuilder`:**
  - кандидат `.challenge`: `rel == 0`, id `wt.challenge.<dayKey>.<HHmm>`, `category: .reminder` (дія «+склянка»),
    `isFloating: false`;
  - **забирає основне нагадування** у вікні [−45, +30] — узагальнити `checkpoint(absorbing:)` на будь-який кандидат,
    що забирає;
  - **норму закрито** (`countedMl ≥ goalMl`) — кандидата немає.
- **`ConflictResolver`** — для `.challenge` `canMove = false`. `DailyCap` — без змін (`.challenge` уже в порядку).
- **Тексти:** `CopyKind.challenge(...)`, `NotificationCopy`, `TextComposer` — тексти з ТЗ §6.6.
  - `CopyCatalogTests` — найгірші значення (унції, 12 год, «Неділя»).
  - Дні тижня в називному — таблиця в `Copy`.
- **Тап** → головний (`AppServices.open` / обробка відповіді). `--notification-tap challenge` уже розбирається
  (`NotificationType(key:)`) — треба лише маршрут.
- **Тести** `NotificationsTests`:
  - забирає нагадування у вікні;
  - не зсувається, а в конфлікті з порятунком зникає;
  - ліміт 8;
  - ідентифікатор;
  - закрита норма — немає.

### 3.7 UI

- **`WTSurpriseCard`** (`DesignSystem`) — за макетом A:
  - іконка ⚡ у колі акценту, позначка виду кольором `orange`, назва, підпис;
  - праворуч `Text(timerInterval:)` і «+N XP · ⚡»;
  - виконане — «Готово · ⚡ у призах»;
  - поява — легкий `slidein` за токеном анімації, Reduce Motion — без руху.
- **`HomeScreen`** — картка над «СЬОГОДНІ». Поява в `assignedAt` при відкритому екрані — `TimelineView(.explicit([...]))`
  від дат картки. Ідентифікатори `quest.surprise`, `quest.surprise.timer`.
- **Віджет:**
  - `WidgetSnapshot.Surprise?` (назва, вид, `visibleFrom`, `expiresAt`, `isDone`) — опційне;
  - `WidgetTimeline.dates` — записи на `visibleFrom` і `expiresAt`;
  - рядок «Прогресу» з `Text(timerInterval:)`, і тоді щоденних — 1.
- **Налаштування:** рядок «Несподівані завдання» на екрані «Сповіщення» (`NotificationsSettingsModel` / `Screen`,
  `WTSegmentRow` «Вимк · 1 · 2», підпис «на тиждень»).
  - Зміна → `touch()`.
  - Ідентифікатори `notifications.surprise.option.<n>`.

### 3.8 DEBUG і демо

- `--quests surprise:surprise.glassNow@13:30` — несподіване повз пікер.
- **Під `--uitest-*` без цього прапорця несподіваних немає.** Демо-історія старша за 8 днів, і картка перекрила б
  чужі сценарії (так само вирішено з «Графіком дня»).

### 3.9 Тести

- **`SurprisePickerTests`:**
  - день < 8 → немає;
  - ліміти 0 / 1 / 2;
  - не поспіль;
  - відступ після двох проігнорованих і відновлення після виконаного;
  - без прогалин — лише Н4 і ≤ 1 на тиждень;
  - слабкий день → Н3;
  - слабка частина → Н1, а після двох виконаних — Н2;
  - виключення з Д7 і Д3;
  - тихі періоди;
  - межі вікна;
  - перша дія пізніше за хвилину − 15 → немає.
- **`QuestEngineTests`:**
  - до `assignedAt` невидиме;
  - скасування закритою нормою й темпом;
  - порції до появи не рахуються;
  - прострочене = проігноровано, скасоване — ні;
  - ⚡ один на інстанс після «відкат → знову».
- **`FeaturesTests`:**
  - рядок налаштування й гейт досягнення;
  - контекст сповіщень зі слотом;
  - знімок віджета з несподіваним.
- **e2e:**
  - `--quests surprise:surprise.glassNow@13:30 --uitest-now <13:35>` → картка й таймер видно, `isHittable`;
    порція 250 → «Готово · ⚡ у призах» → у «Призах» з'явився ⚡;
  - `--notification-tap challenge` → головний з карткою.
- **`FirstWeekSimulation`** — у тижні 1 несподіваних 0; тижнева персона з історією ≥ 8 днів — ≤ 2.

### 3.10 Документація

- **`CLAUDE.md`** — несподівані в розділі «Завдання» і «Сповіщення», прапорці.
- **`SPEC-NOTIFICATIONS.md` §10** — посилання «реалізовано за SPEC-QUESTS §6». §10.2 XP і §10.3 частота — звідти.
- **`SPEC-PRIZES.md` §13.1** — призи за завдання: лише ⚡ за несподіване (решта — «На майбутнє» SPEC-QUESTS §11).
- **WAT-38** — коментар: несподівані й налаштування зроблено тут; лишається сигнал «нагадування не допомагають».

---

## 4. Перевірка наприкінці кожного PR

```bash
make test-packages
make test-ui
```

- `PerformanceTests` (Gamification) — зелені, кеші не прибирати.
- `AchievementBudgetTests` — зелені.
- Ручна перевірка в симуляторі (`make install`): світла й темна теми, унції, 12 год, «Ритм дня» вимкнено.
- Linear: підзадача → Testing із підсумковим коментарем (що зроблено, як перевірити, нюанси, PR).

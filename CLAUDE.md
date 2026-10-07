# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Мова

Код, коментарі, документація й повідомлення комітів — **українською**. Коментар
пояснює *чому*, а не *що*: у цьому репозиторії вони фіксують прийняті рішення
й пастки, а не переказують сусідній рядок.

Тексти інтерфейсу звертаються до користувача на **«ти»** і без родового минулого часу
(«пив / пила») — навіть коли стать відома (SPEC-NOTIFICATIONS §14.1).

## Команди

Потрібен `xcodegen` (`brew install xcodegen`). `WaterTracker.xcodeproj` у `.gitignore` —
**правити `project.yml`, не `.pbxproj`**; `App/Info.plist` теж генерується.

```bash
make project        # xcodegen generate
make build          # збірка в симулятор (пінить -derivedDataPath DerivedData)
make test-packages  # 498 unit-тестів 9 пакетів, без симулятора — швидкий цикл
make test-ui        # 41 e2e-сценарій (XCUITest) у симуляторі
make test           # обидва набори
make install        # build + встановити й запустити в booted-симуляторі
make clean
```

Симулятор перевизначається: `make build SIMULATOR="iPhone 17 Pro"`.

Один пакет / один тест:

```bash
swift test --package-path Packages/Hydration
swift test --package-path Packages/Hydration --filter HydrationServiceTests
swift test --package-path Packages/Gamification --filter StreakEngineTests
```

Один e2e-сценарій:

```bash
xcodebuild test -scheme WaterTracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath DerivedData -only-testing:WaterTrackerUITests/SmokeUITests/testAddIntakeUpdatesProgressAndHistory
```

> `-derivedDataPath DerivedData` обов'язковий. Без нього `xcodebuild` пише в
> `~/Library/Developer/Xcode/DerivedData`, тека `DerivedData/` у проєкті лишається зі
> старою збіркою, і `make install` заганяє в симулятор код, якого в репозиторії вже немає.
> На це вже витратили день хибної «регресії» (PLAN.md §«Що з'ясувалося», п. 5).

## Архітектура

9 локальних SPM-пакетів у `Packages/` + тонкий app-таргет `App/`. Граф залежностей
жорсткий — його тримають самі маніфести `Package.swift`, зайвий `import` просто не збереться:

```
Features → (Hydration | Gamification | Insights | Notifications) → Metrics → Persistence → Core
Features → DesignSystem → Core
```

Ніхто не імпортує `Features`. `DesignSystem` не знає доменних моделей — приймає лише
прості view-моделі (`WTBar`, `WTCalendarCell`, `WTAchievementCard`…).

### Шина метрик — головне архітектурне рішення

Доменні модулі **не викликають один одного**. `HydrationService` публікує подію в
`MetricsService`, а `GamificationService` (підписник, `metrics.subscribe(self)` у
`bootstrap()`) реагує. Нова механіка = новий підписник, без правок у `Hydration`.

`MetricsService` (`Packages/Metrics`) дає чотири властивості, на яких тримається все інше:

- **Ідемпотентність** — подія з тим самим `name` + `sourceRef` не подвоює агрегат.
- **Реверс** — `revert(sourceRef:)` відкочує подію й похідні (undo порції).
- **Реплей** — `rebuildCounters()` перебудовує агрегати з сирих `MetricEventRecord`.
- **Батчинг** — `metrics.commit()` **один раз на дію користувача**, не на подію.
  Без цього одна порція коштувала 45 мс замість 9 (`GamificationTests/PerformanceTests`
  тримає межу — не прибирати кеші рівня, лічильників, квестів і досягнень).

Ключі метрик — `MetricKey` (`Packages/Metrics/Sources/Metrics/MetricKey.swift`),
єдине джерело правди і для квестів, і для досягнень, і для графіків. Квести й
досягнення декларативні: `metricKey + comparator + target` у `Gamification/Catalogs.swift`,
нова умова додається рядком у каталог, без коду.

**Призи** (SPEC-PRIZES): у каталозі 🧊 `streak.freeze`, ⚡ `xp.double` і 🌟 `xp.triple` (лише з таємних).
Приз **і є** жетон — дія лише з картки: `useFreeze(prizeId:)` / `activateBoost(prizeId:)` (будь-який буст, один на раз).
Який день заморожується, вирішує `StreakEngine.freezeTarget` (правило в doc-коментарі — не
переписувати без рішення). Заморожений день тримає ланцюг серії, але **не додає** до числа.
Буст множить увесь XP до 00:00 і перемножується з серією; прострочення — похідне від `Clock`.
Блок 3f і екран «Призи» ділять одну `PrizeInventoryModel` і `PrizePresenter` (усі тексти).
**Шлях рівнів** (WAT-44, SPEC-PRIZES §16): що дає рівень — декларативний `LevelRoadCatalog` (до 10-го приз через
рівень, з 11-го — на кожному). Звичайний приз видає `grantLevelRewards`, а вибір і таємний 🎁 чекають дії:
`claimChoice(level:key:)` / `openMystery(level:)`, один ref `level:N` на вузол. «Чекає» — похідна, не стан у БД;
старі ref `level:N:<key>` рахуються як отримані. Вміст 🎁 — `MysteryRoll` від зерна профілю, без RNG. Вікно —
`LevelRoadScreen` («Драбина», `WTRoad*`), тексти — `LevelRoadPresenter`, знімок — `levelRoad()`. Безкінечний рух
(похитування 🎁, промені «Скрині») — лише через `TimelineView`: `withAnimation(.repeatForever)` тягнув за собою шапку.
**XP за воду — за зарахований об'єм, не за порцію** (`XPRules.waterXp`), у межах стелі 120 %. Баланс — XP за крок
об'єму й загальний множник — у `Config/Balance.xcconfig` → `Info.plist` → `AppContainer.xpRules`; у DEBUG ті самі
імена в змінних середовища схеми перекривають файл.
Звіт-історія (`Features/Report`) так само: `ReportPresenter` — чиста функція «звіт → слайди з текстами»,
візуал — компоненти `Story.swift` у `DesignSystem`.
**Кнопки порцій** (WAT-45): `QuickAddPreset.place` — головний (3) чи підказки шторки «Інше» (4), сід окремо на
місце; степер перескакує значення, зайняте сусідом (`PresetRules`) — дубль зламав би `home.add.<ml>`. «Інше» з
кнопки — з `UserProfile.lastCustomAmountMl` (`HomeViewModel.openCustom`), зі сповіщення — з P через `apply(_:)`.
Після дії картка показує підтвердження й закривається сама (`successHold`); поки діє буст,
на донаті рівня 3f — бейдж «⚡×2» (на краплі головного — свідомо ні). Таймер — «06:53», без секунд.

Що саме відкрила конкретна дія, екран дізнається з черги `GamificationService.takeRecentUnlocks()`
(`HydrationService` про гейміфікацію не знає). `HomeViewModel` чистить чергу **до** дії й читає
**після** — інакше тост отримають розблокування зі старту чи повернутої порції.

### Композиційний корінь

`AppServices` (`Packages/Features/Sources/Features/AppServices.swift`) збирає репозиторії
та сервіси. `bootstrap()` створює профіль, стартову норму 2000 мл, пресети й підписує
гейміфікацію й сповіщення. `services.touch()` — «дія користувача завершена»: один раз на дію,
як `metrics.commit()`; просить перепланування сповіщень. `services.epoch` — зміни не від
екрана (повернення з фону, нова доба, пояс, дія зі сповіщення у фоні): екрани слухають його
й викликають `reload()`.

`CalendarService` бере пояс годинника на кожне читання (спільний кеш): після перельоту доба
рахується в новому поясі без перезапуску. У тестах пояс міняє `FixedClock.setTimeZone(_:)`.

### Сповіщення (SPEC-NOTIFICATIONS, WAT-36, WAT-37)

Лише локальні сповіщення: у момент доставки код не виконується, тож план складається
**наперед з припущенням «користувач більше нічого не робить»** і перебудовується на кожну зміну.

- `NotificationPlanner.plan(context:preferences:journal:)` — **чиста функція**, тести на `FixedClock`.
  Чотири дні з §6.1 прибиті дослівно (`SpecDaysTests`) — правка алгоритму, що їх ламає, суперечить ТЗ.
- Пакет `Notifications` не імпортує `Hydration` / `Gamification` / `Insights`: усе приходить
  значенням `NotificationContext`, яке збирає `AppServices+Notifications.swift`. Дія «+склянка»
  додає порцію там же, через `HydrationService`.
- `NotificationService`: послідовний воркер перепланування (`setNeedsReschedule` / `rescheduleNow`),
  журнал `NotificationLog`, атрибуція порції (підписник на `intake.added`), дозвіл.
  Метрики `notification.*` — у `GamificationService.internalMetrics`, інакше кожна позначка
  «доставлено» ганяла б квести.
- Ідентифікатори `wt.<тип>.<dayKey>.<слот>`, у нагадувань слот — `HHmm`. `wt.echo.*` дифф не знімає.
- `UNUserNotificationCenter` — лише в застосунку (`SystemNotificationCenter`): у SPM-тестах він
  падає. Тести й e2e — `InMemoryNotificationCenter`.
- Сервіси живуть у `App/Sources/AppContainer.swift` (лінивий `static`), бо делегат центру
  виставляється в `didFinishLaunching` і дія, що запустила застосунок, приходить раніше за вікно.
- Тексти — `Copy/NotificationCopy.swift`: на «ти», без роду, заголовок ≤ 30, текст ≤ 100,
  емодзі лише на початку заголовка. `CopyCatalogTests` перевіряє це на найгірших значеннях.
- **Цілі частин доби** — `GoalBlock` у `Core` (`PaceCurve.goalBlocks()`): частини, обрізані активними
  годинами, коротші за 2 год зливаються з сусідньою. Одне визначення для чекпоінта (тип 4), XP
  `dayPartGoal`, звіту й графіків 4a (`PaceCurve.partTargetsMl()` — ризки «ціль», ніч поза активними
  годинами без ризки); випите рахується за часом порцій, не за `DayLog.partTotals` (§24). Порція до
  підйому — першому блоку, після відбою — останньому (§25). Розклад дня — зі знімка в `DayLog` через
  `UserProfile.schedule(for:isWeekend:)`, не з профілю напряму: інакше зміна підйому переписує минулі дні.
- **Спад перед сном** (WAT-43, §29): останні `PaceCurve.taperMinutes` (2 год) до відбою крива йде з
  темпом `taperFactor` (½). Вікно — від відбою людини, не від `DayPart`; ваги `idealShare` не чіпати. Спад живе
  в приватних `pieces`, а `segments` лишаються по одному на частину доби — інакше `goalBlocks()` дав би блок
  і чекпоінт «до 20:00».
- **Чекпоінт** забирає собі основне нагадування у вікні `[−45, +30]` — ланцюг далі від нього.
  `SpecDaysTests` (§6.1) рахують лише тип 1, тож чекпоінти там вимкнені; повний день §6.3 — `CheckpointTests`.
- **Капсула частини доби** під кільцем головного (WAT-40, §26) — підказка, коли чекпоінт мовчить:
  `PaceCurve.dayPartProgress` (ті самі `GoalBlock`), тексти — `DayPartPresenter` («ще N мл» вгору до 50,
  як у чекпоінта). Хвилина — від `Clock` у `HomeViewModel.dayPartLine()`; `TimelineView` лише будить екран.
- **Звіти** рахує `Insights.report(for: ReportPeriod)` на льоту; для сповіщення `AppServices` кладе в
  контекст `ReportDigest` за періодами з `NotificationPlanner.reportPeriods`, текст складає `ReportText`.
  Денний — `.passive`, усі звіти без звуку й поза лімітом 8.

### Ритм дня (WAT-42, SPEC-NOTIFICATIONS §28)

- `UserProfile.dayRhythmEnabled`, типово увімкнено. Вимкнено — «просто норма за день»: планувальник не ставить
  чекпоінтів (`NotificationPreferences.dayRhythmEnabled`, власний `checkpointsEnabled` не скидається),
  `GamificationService` не дає XP `dayPartGoal` і не видає завдань із метрикою `part.*` (`QuestDefinition.isDayPartQuest`),
  капсули на головному немає, `Insights.report(for:)` повертає звіт без `blocks` (`showsDayParts`) і без думки
  «системна прогалина». Звіти йдуть за поточним перемикачем, не за днем.
- Вимкнення нарахованого не відкочує; увімкнення діє з наступної порції. Перемикач — на екрані «Налаштування»
  (WAT-15); щойно після вимикання — разова плашка «Рівні інтервали», мовчки режим не змінюється.

### Пропозиція графіка (WAT-41, SPEC-NOTIFICATIONS §27)

- `ScheduleShift.suggest` (`Insights`) — чиста функція: 14 повних днів до сьогодні проти **поточного**
  розкладу профілю, не знімків `DayLog`. Ранок — в обидва боки (підйом = медіана першої склянки), вечір раніше —
  лише понад нормальну паузу 2 год (§13.6). Будні й вихідні окремо. Пороги — `ScheduleShiftRules`.
- Частота — `ScheduleOfferPolicy`, стан — `UserProfile.scheduleOffer*`. Показ одразу пишеться як «закрили»:
  застосунок можуть закрити з відкритим вікном.
- Показ — лише на відкритті: `services.activation` (холодний старт / повернення з фону), а не `epoch` — той
  змінюється й опівночі. `HomeViewModel.offerScheduleIfNeeded` перевіряє, що головний «чистий». Вікно —
  `HomeSheet.schedule` на весь екран, тексти — `SchedulePresenter`.
- Застосування — `AppServices+Schedule.swift` (зачіпає `Hydration`): профіль → `scheduleDidChange()` → `touch()`.
- Межі розкладу (підйом від 04:00, відбій до 24:00, ≥ 6 год, крок 15 хв) — `DaySchedule`, одні для екрана
  «Сповіщення», вікна й `Insights`.

ViewModel-и — `@MainActor @Observable`, кешують знімки в збережені властивості й
перечитують їх у `reload()`. Весь доменний шар — `@MainActor`.

### Правила цілісності даних (Persistence)

- `DayLog` — денний агрегат, щоб графіки не рахувались по сирих порціях. Унікальний
  `dayKey` (`yyyy-MM-dd`, локальний).
- **Стеля 120 %**: `countedMl = min(totalMl, goal × 1.2)`; `totalMl` зберігає фактичне.
  Єдине місце перерахунку — `HydrationService.recompute(_:)`.
- `Intake` не редагується; видалення — **soft delete** (`deletedAt`), щоб коректно
  відкотити XP і мати undo. Обмеження 50…2000 мл за порцію.
- Норма змінюється через `GoalRevision`; `DayLog.goalMlSnapshot` оновлюється лише для
  **поточного** дня, минулі не чіпаються. Так само підйом і відбій (`wakeMinutesSnapshot` /
  `sleepMinutesSnapshot`): пишуться з порцією і в `HydrationService.scheduleDidChange()`.
- Схема — `Database.schema` (14 моделей), одне місце для майбутніх міграцій.

### Час

**Ніколи не викликати `Date()` напряму.** Єдине джерело — протокол `Clock`
(`Core/Clock.swift`); у тестах `FixedClock`. Доба, `dayKey`, години й частини доби —
через `CalendarService`. Інакше тести на серії та добові розрізи стають плаваючими.

### DesignSystem

- У Feature-шарі **жодних магічних чисел** — тільки токени (`WTColor`, `WTSpacing`,
  `WTRadius`, `WTAnimation`) і компоненти `WT*`.
- Кольори — з `@Environment(\.wtTheme)` (`WTTheme.light` / `.dark`). Захардкожений
  `Color(hex:)` у в'юсі = баг темної теми.
- Шрифти: `WTFont.text` / `WTFont.display` — Nunito (весь текст), `WTFont.number` —
  Fredoka (тільки цифри й латиниця). У макеті Fredoka підключена без кирилиці, тому так.
- Гаптика — семантична: `.wtFeedback(trigger:)` з `WTFeedback` (`.add`, `.goalReached`,
  `.levelUp`…), а не «дай medium impact». Глобальний вимикач — `\.wtHapticsEnabled`.
- Натискання — `WTPressStyle`, не `.plain`.
- Показ/приховування шторок — **тільки через `withAnimation(WTAnimation.sheet)`**
  (див. `HomeViewModel.present(_:)`). Пряме присвоєння `model.sheet = …` обходить
  `withAnimation`, і перехід `WTSheet` не програється взагалі. Вікно «Склянка» на весь екран —
  теж `HomeSheet` (`.glass`): так порція з нього йде тим самим шляхом із тостами розблокувань.
- Кілька `ForEach` в одному `LazyVGrid` — з різними ідентифікаторами: однакові 0…6 зливають комірки
  (мозаїка місяця губила перший тиждень).
- Поповер від кнопки — `wtPopoverAnchor()` на кнопці + `wtPopover(...)` на **корені** екрана:
  кнопка в `ScrollView`, і меню, намальоване там, лягало б під наступні блоки.
- Фон кола досягнення — `theme.unlockedIconBg` / `theme.lockedIconBg`, не `WTColor.goldIconBg`
  напряму: той фіксовано світлий і «світиться» в темній темі. Те саме для призів —
  `theme.prizeIconBg`, не `WTColor.prizeIconBg`.
- Макети розраховані на кадр 402 × 874 pt; Dynamic Type обмежено `.wtTypeSizeLimit()`
  у `WTThemedContainer`.

## Тести

- `accessibilityIdentifier` **не вішати на контейнер** — він успадковується дочірніми
  й перекриває їхні власні. На цьому двічі ламались e2e (шторки, потім тост).
- `waitForExistence` не є перевіркою видимості — елемент за межею екрана лишить тест
  зеленим. Для тостів і оверлеїв додатково перевіряти `isHittable` і межі вікна.
- Позначення «переглянуто» — лише в `reload()` з `onAppear`, не в `init` моделі: інакше
  друге читання вже не бачить нових, і крапки «нове» не з'являються зовсім (WAT-23).
- Прапорці запуску (`App/Sources/WaterTrackerApp.swift`, `LaunchConfiguration`):
  `--uitest-empty` (чиста in-memory БД), `--uitest-demo` (демо-історія),
  `--seed-demo`, `--start-screen progress|level-road|achievements|prizes|stats|settings|portion-buttons|notifications|notification-plan|report|schedule-suggestion`
  (`report` — минулий тиждень; період явно — `report:day:2026-10-04`, `report:month:2026-09`;
  `schedule-suggestion:wake-early|wake-late|sleep-late|sleep-early|both|weekend|weekdays` — вікно «Графік дня»
  повз правило частоти). `--seed-schedule-shift` — 10 днів із першою склянкою ≈ 06:30: вікно з'являється само.
  Демо-історія завжди має пропущений учора день після закритого позавчора й ≥ 2 заморозки —
  для e2e кнопки заморозки — і вважається такою, що вже відповіла на пропозицію графіка: її патерн
  залежить від дати, і вікно могло б перекрити чужий сценарій. На шляху рівнів у демо чекає по одному
  вузлу кожного виду — останній вибір і останній 🎁; номер рівня залежить від дати, тож e2e шукають
  `levelRoad.choice.*` / `levelRoad.mystery.*` за префіксом.
- Сповіщення в e2e: під `--uitest-*` центр — у пам'яті з дозволом `--notifications-auth
  authorized|denied|notDetermined` (типово є — інакше шторка дозволу після першої порції ламала б
  сценарії); `--notification-tap reminder|morning|evening|rescue|comeback|echo|report` імітує тап
  (`morning` — вікно «Склянка», `report` — звіт за минулий тиждень);
  `--uitest-now 2026-10-01T07:00:00+03:00` фіксує годинник для DEBUG-екрана «План сповіщень».

## Відомі прогалини

Актуальний список — `PLAN.md` §«Наступні кроки». Найсуттєвіші:

1. VoiceOver: `accessibilityLabel` / `accessibilityValue` є лише в модулі досягнень
   (WAT-23); решта екранів має тільки `accessibilityIdentifier` для e2e.
2. Рядки зашиті в коді українською — локалізація в `.xcstrings` не зроблена.
3. `HomeSheet.stats` реалізований (`WeekStatsSheet`), але недосяжний з UI.
4. `GoalCalculatorSheet` готовий і покритий тестами, але не підключений.
5. Сповіщення: етап C (несподівані завдання) — WAT-38; повний редизайн екрана «Сповіщення» —
   WAT-18; ассету звуку «булькання» (`drop.caf`) немає — грає системний.

## Робота із задачами Linear

Команда `WaterTracker` у Linear (issue-і `WAT-N`). Для кожної задачі, взятої в роботу:

1. Створити окрему гілку: `WAT-N_коротко-по-темі` (напр. `WAT-9_top-space`).
2. Одразу перевести задачу в статус **In Progress**.
3. Прочитати назву, опис і всі коментарі задачі — там може бути контекст, якого
   немає в назві.
4. Виконати задачу. За потреби лишати короткі коментарі й у задачі, і в коді.
5. Після досягнення мети — створити pull request і перевести задачу в статус
   **Testing**.
6. Залишити в задачі підсумковий коментар: що зроблено, що і як перевірити,
   нюанси (якщо були), посилання (PR, коміти).

## Документація

| Файл | Роль |
|---|---|
| `PLAN.md` | джерело правди: архітектура, модель даних, статус етапів, журнал пасток |
| `SPEC-TEMPLATE.md` | ТЗ |
| `SPEC-ACHIEVEMENTS.md` | ТЗ модуля «Досягнення» (WAT-22): блок 3f, екран 2e, картка деталей |
| `Design/Achievements.html` | макет модуля досягнень (6 кадрів 402×874) до цього ТЗ; перенесено в код у WAT-23 |
| `SPEC-PRIZES.md` | ТЗ модуля «Призи» (WAT-26): каталог, блок на 3f, екран «Призи», картка призу, правила заморозки й буста |
| `Design/Prizes.html` | макет модуля призів (6 кадрів 402×874) до цього ТЗ; перенесено в код у WAT-34 |
| `Design/LevelRoad.html` | макет вікна «Шлях рівнів» (WAT-44, SPEC-PRIZES §16): погоджено «Драбину» й «Скриню», компактний вибір; інфографіка частоти призів |
| `Config/Balance.xcconfig` | баланс XP: XP за крок об'єму води й загальний множник (SPEC-PRIZES §16.13) |
| `SPEC-NOTIFICATIONS.md` | ТЗ модуля «Сповіщення» (WAT-17): типи, нагадування за кривою темпу, анти-спам, тексти, налаштування, локальні сповіщення й планувальник; етапи 0 і A реалізовано в WAT-36 (рішення — §23), етап B — у WAT-37 (§24), одна модель цілей частин доби — WAT-39 (§25), капсула частини доби на головному — WAT-40 (§26), пропозиція змінити графік дня — WAT-41 (§27), перемикач «Ритм дня» — WAT-42 (§28), спад кривої темпу перед сном — WAT-43 (§29), екран «Налаштування» на весь екран — WAT-15 (§30) |
| `Design/DayPart.html` | макет капсули частини доби на головному (WAT-40): три варіанти, погоджено A (SPEC-NOTIFICATIONS §26) |
| `Design/Schedule.html` | макет вікна «Графік дня» (WAT-41): три варіанти, погоджено A «Час», і правило зсуву на 14 днях (SPEC-NOTIFICATIONS §27) |
| `Design/Notifications.html` | інтерактивний макет етапу B (WAT-37): вікно «Склянка», звіт-історія дня / тижня / місяця, рядки B на екрані «Сповіщення» |
| `DESIGN-TOKENS.md` | витяг токенів з макетів |
| `WaterTracker.html` | оригінальні макети (1a, 3f, 2e, 4a) |

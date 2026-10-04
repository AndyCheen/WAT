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
make test-packages  # 306 unit-тестів 9 пакетів, без симулятора — швидкий цикл
make test-ui        # 24 e2e-сценарії (XCUITest) у симуляторі
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

**Призи** (SPEC-PRIZES): у каталозі лише 🧊 `streak.freeze` і ⚡ `xp.double`, один приз на рівень.
Приз **і є** жетон — дія лише з картки: `useFreeze(prizeId:)` / `activateBoost(prizeId:)`.
Який день заморожується, вирішує `StreakEngine.freezeTarget` (правило в doc-коментарі — не
переписувати без рішення). Заморожений день тримає ланцюг серії, але **не додає** до числа.
Буст множить увесь XP до 00:00 і перемножується з серією; прострочення — похідне від `Clock`.
Блок 3f і екран «Призи» ділять одну `PrizeInventoryModel` і `PrizePresenter` (усі тексти).
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

### Сповіщення (SPEC-NOTIFICATIONS, WAT-36)

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
  **поточного** дня, минулі не чіпаються.
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
  `withAnimation`, і перехід `WTSheet` не програється взагалі.
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
  `--seed-demo`, `--start-screen progress|achievements|prizes|stats|notifications|notification-plan`.
  Демо-історія завжди має пропущений учора день після закритого позавчора й ≥ 2 заморозки —
  для e2e кнопки заморозки.
- Сповіщення в e2e: під `--uitest-*` центр — у пам'яті з дозволом `--notifications-auth
  authorized|denied|notDetermined` (типово є — інакше шторка дозволу після першої порції ламала б
  сценарії); `--notification-tap reminder|morning|evening|rescue|comeback|echo` імітує тап;
  `--uitest-now 2026-10-01T07:00:00+03:00` фіксує годинник для DEBUG-екрана «План сповіщень».

## Відомі прогалини

Актуальний список — `PLAN.md` §«Наступні кроки». Найсуттєвіші:

1. VoiceOver: `accessibilityLabel` / `accessibilityValue` є лише в модулі досягнень
   (WAT-23); решта екранів має тільки `accessibilityIdentifier` для e2e.
2. Рядки зашиті в коді українською — локалізація в `.xcstrings` не зроблена.
3. `HomeSheet.stats` реалізований (`WeekStatsSheet`), але недосяжний з UI.
4. `GoalCalculatorSheet` готовий і покритий тестами, але не підключений.
5. Сповіщення: етапи B (шторка «Склянка», звіти, чекпоінти) і C (несподівані завдання) —
   WAT-37 і WAT-38; ассету звуку «булькання» (`drop.caf`) немає — грає системний.

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
| `SPEC-NOTIFICATIONS.md` | ТЗ модуля «Сповіщення» (WAT-17): типи, нагадування за кривою темпу, анти-спам, тексти, налаштування, локальні сповіщення й планувальник; етапи 0 і A реалізовано в WAT-36, рішення реалізації — §23 |
| `DESIGN-TOKENS.md` | витяг токенів з макетів |
| `WaterTracker.html` | оригінальні макети (1a, 3f, 2e, 4a) |

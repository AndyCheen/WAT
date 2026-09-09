# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Мова

Код, коментарі, документація й повідомлення комітів — **українською**. Коментар
пояснює *чому*, а не *що*: у цьому репозиторії вони фіксують прийняті рішення
й пастки, а не переказують сусідній рядок.

## Команди

Потрібен `xcodegen` (`brew install xcodegen`). `WaterTracker.xcodeproj` у `.gitignore` —
**правити `project.yml`, не `.pbxproj`**; `App/Info.plist` теж генерується.

```bash
make project        # xcodegen generate
make build          # збірка в симулятор (пінить -derivedDataPath DerivedData)
make test-packages  # 126 unit-тестів 8 пакетів, без симулятора — швидкий цикл
make test-ui        # 9 e2e-сценаріїв (XCUITest) у симуляторі
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

8 локальних SPM-пакетів у `Packages/` + тонкий app-таргет `App/`. Граф залежностей
жорсткий — його тримають самі маніфести `Package.swift`, зайвий `import` просто не збереться:

```
Features → (Hydration | Gamification | Insights) → Metrics → Persistence → Core
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

### Композиційний корінь

`AppServices` (`Packages/Features/Sources/Features/AppServices.swift`) збирає репозиторії
та сервіси. `bootstrap()` створює профіль, стартову норму 2000 мл, пресети й підписує
гейміфікацію. `services.touch()` інкрементує `revision` після кожної дії.

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
- Макети розраховані на кадр 402 × 874 pt; Dynamic Type обмежено `.wtTypeSizeLimit()`
  у `WTThemedContainer`.

## Тести

- `accessibilityIdentifier` **не вішати на контейнер** — він успадковується дочірніми
  й перекриває їхні власні. На цьому двічі ламались e2e (шторки, потім тост).
- `waitForExistence` не є перевіркою видимості — елемент за межею екрана лишить тест
  зеленим. Для тостів і оверлеїв додатково перевіряти `isHittable` і межі вікна.
- Прапорці запуску (`App/Sources/WaterTrackerApp.swift`, `LaunchConfiguration`):
  `--uitest-empty` (чиста in-memory БД), `--uitest-demo` (демо-історія),
  `--seed-demo`, `--start-screen progress|achievements|stats`.

## Відомі прогалини

Актуальний список — `PLAN.md` §«Наступні кроки». Найсуттєвіші:

1. `scenePhase` не обробляється — застосунок, залишений відкритим на ніч, показує
   вчорашній день. Найближчий реальний баг.
2. VoiceOver: нуль `accessibilityLabel` / `accessibilityValue` (є лише
   `accessibilityIdentifier` для e2e).
3. Рядки зашиті в коді українською — локалізація в `.xcstrings` не зроблена.
4. `services.revision` пишеться, але його ніхто не читає.
5. `HomeSheet.stats` і `.achievements` реалізовані (`WeekStatsSheet`,
   `AchievementsSheetContent`), але недосяжні з UI.
6. `GoalCalculatorSheet` готовий і покритий тестами, але не підключений.

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
| `DESIGN-TOKENS.md` | витяг токенів з макетів |
| `WaterTracker.html` | оригінальні макети (1a, 3f, 2e, 4a) |

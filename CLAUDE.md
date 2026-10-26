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
make test-packages  # 966 unit-тестів 10 пакетів (+19 аудиту на вимогу), без симулятора — швидкий цикл
make test-ui        # 74 e2e-сценарії (XCUITest) у симуляторі
make test           # обидва набори
make install        # build + встановити й запустити в booted-симуляторі
make clean
```

Симулятор перевизначається: `make build SIMULATOR="iPhone 17 Pro"`.

Підпис — лише в `project.yml` (`DEVELOPMENT_TEAM`, `APP_BUNDLE_ID`, `APP_GROUP_ID`, WAT-69): вибране в інтерфейсі Xcode
`make project` скидає. Ідентифікатори глобальні в Apple; змінений ідентифікатор для iOS — інший застосунок, і дані на
телефоні не перейдуть. Групу код бере з Info.plist (`WTAppGroup`), не з рядка.

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

10 локальних SPM-пакетів у `Packages/` + тонкий app-таргет `App/` і розширення віджетів `WidgetExtension/`.
Граф залежностей жорсткий — його тримають самі маніфести `Package.swift`, зайвий `import` просто не збереться:

```
Features → (Hydration | Gamification | Insights | Notifications) → Metrics → Persistence → Core
Features → Widgets → DesignSystem → Core
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

**Досягнення** (WAT-24, `SPEC-ACHIEVEMENTS-CATALOG.md`): 112 чинних у `AchievementCatalog` (з них 3 — за «Знання», WAT-53,
і «Несподіванка», WAT-65) (`Catalogs.swift`), ключі наявних
не міняти — на них прогрес. Перший тиждень — 1–2 досягнення в день 1 (WAT-60, §10): нові — лише такі, що відкриваються не
раніше 2-го тижня; межі тримає `AchievementBudgetTests` на тижні `FirstWeekSimulation` (звіт — `AttentionAuditWeek1Tests`,
`WT_AUDIT=1`). Далі — `AchievementPacingTests` (WAT-67): 60 днів норми щодня рівно, з 2-го тижня ≤ 3 за день і ≤ 10 за
тиждень; пороги «N днів» розведено, щоб дні з досягненнями не збігались (SPEC-ACHIEVEMENTS-CATALOG §11). Зняте — не видалення, а `retired: true` (`AchievementDefinition.isRetired`, 7 штук): не рахується в
проході й відкаті, невідкритого немає в знімку, відкрите — звичайна плитка поза `tally`, але в «Колекції»; чинні —
`AchievementCatalog.active`. Відкат (`AchievementEngine.revert(since:)`) знімає лише відкрите **не раніше події**, яку
відкочують (час події, не мить відкату): підняття порогу не забирає відкритого раніше. Правило — `AchievementRule`: лічильник шини, рівень, факт шляху рівнів, колекція або
`HistoryFact` — факт **історії днів** (`DayHistory`: кеш `DayRecord` з точковим оновленням сьогоднішнього дня й
запам'ятовуванням фактів; `DayKey.ordinal` замість `Calendar`). Обʼєм — лише зарахований. Умови, які зіпсувало б
доливання («Влучність», «В яблучко», «Дзеркало», «Рівна крива»), дивляться **лише на завершені дні** — інакше доливання
й перший-ліпший відкат зняли б відкрите. Сонцестояння й повня — `SkyCalendar`. Точний об'єм порції в умові — лише метричний («Пі»), інакше — найменша порція системи
(«Наперсток», `Intake.smallestAmountsMl`): цілими унціями 50 і 314 мл не набрати (WAT-59). XP — від складності
(`AchievementDifficulty`), остаточні числа — WAT-25. Таємні — прапорець `AchievementSecrecy`: 🤫 у знімку вже «???»,
підказка й без прогресу; 🥚 до знахідки у знімку немає зовсім, лічильник — `tally` (102 + «🥚 N»). Маскування — лише в
`AchievementEngine.snapshots`, не у в'юсі. Залежні від «Ритму дня», сповіщень і несподіваних завдань (`AchievementGate`) поки функцію вимкнено
не рахуються ні в проході, ні у відкаті й мають `lockedCaption`. Прохід — лише на подіях із `AchievementCatalog.triggers`
(частини доби пропускаються), повторюється, поки XP за досягнення піднімає рівень. Факти сповіщень («Чуйність»,
«Вчасно» — лише після вечірнього порятунку, «На крок попереду») публікує `NotificationService` з ref `day.goalMet` —
відкат норми їх знімає. «Тижнева мета» (ключ `quest.first`) — подія `quest.weeklyCompleted` з ref завдання, «Несподіванка» (`quest.firstSurprise`) —
`quest.surpriseCompleted`.
«Темна сторона» — лише вибір у «Налаштуваннях», не системна тема.
**Вікно відкриття «Хвиля»** (WAT-62, SPEC-ACHIEVEMENTS §8): кожне відкрите — вікно на весь екран, не тост. Черга — у
базі: невідсвятковане = відкрите не раніше `UserProfile.celebrationsSince`, без `AchievementProgress.celebratedAt`, не
зняте (`GamificationService.pendingCelebrations(since:)`). `celebrationsSince` ставить `bootstrap()` **до** стартового
перерахунку (відкрите раніше — відсвятковане), демо й сіди — `settleCelebrations()` після сіду. Показ —
`AppServices.presentCelebrations(context:level:)`, оверлей `RootView` над усім; закриття (`dismissCelebration`) ставить
`celebratedAt` і `seenAt`, відкат `celebratedAt` не скидає. Паузи — за причиною (`CelebrationPause`): онбординг, шторки
й тости головного, звіт, історія «Знань», «Шлях рівнів», картка призу, системний запит дозволу; кінець останньої паузи
показує все, що назбиралось. На відкритті й опівночі — `.whileAway`, «Поки тебе не було». Дії «Відкриттів» і пасхалок —
`AppServices.record(_:)`: подія на шину й вікно поверх будь-якого екрана. Тексти — `CelebrationPresenter` (до трьох
сторінок, далі сітка; «Далі» — `AchievementCatalog.higherSteps` від 10 %), вигляд — `WTCelebration`. Рівень тієї самої
дії — рядок у вікні, без досягнень — тост; святкується раз (`UserProfile.highestCelebratedLevel`).

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
місце; крок — 50 мл до 1 л і 100 мл від 1 л (`PresetRules.stepped`); дублі дозволені, тож `ForEach` кнопок і чипів — за позицією, не за значенням. Підпис — `HomeScreen.amountTitle`
(до 1 л — мл, далі «1.05 л»), один для головного й налаштувань. «Інше» з
кнопки — з `UserProfile.lastCustomAmountMl` (`HomeViewModel.openCustom`), зі сповіщення — з P через `apply(_:)`.
Тап по числу в «Інше» — цифрова клавіатура, точний об'єм 50…2000 (WAT-50): без нього «Пі» (314 мл) і «Дзеркало»
(паліндром за день) з інтерфейсу не виконати — на сітці 50 мл немає ні 314, ні жодного чотиризначного паліндрома.
Набране живе в `HomeViewModel.customTyped` — в одиницях людини (в унціях — цілі унції 2…67), `customAmount` — мл;
`WTSheet` ігнорує лише `.container`, тож шторка стає над клавіатурою.
Після дії картка показує підтвердження й закривається сама (`successHold`); поки діє буст,
на донаті рівня 3f — бейдж «⚡×2» (на краплі головного — свідомо ні). Таймер — «06:53», без секунд.

**Завдання** (WAT-63, SPEC-QUESTS, план — QUESTS-PLAN §1): щоденні — слоти «Темп» і «Ритм», тижневі — «Сталість» і
«Звичка», дні 1–2 — стартові; каталог — `Gamification/Quests/QuestCatalog.swift`, **ключі не міняти**: на них ротація.
Видача — першою подією дня й тижня (`QuestEngine.ensureInstances`), вибір — чисті `DailyQuestPicker` /
`WeeklyQuestPicker` (`StableHash` від зерна профілю, історія — до вчора, `QuestHistory`). Умова — `DayCondition` на
`QuestDay` (порції, розклад і норма зі знімка дня; кеш на сервісі скидає подія дня), одна для щоденних і «день
зараховано» тижневих; тижневі рахують дні **від дня видачі**. «До T» — строго раніше; T, N і блок фіксуються на
інстансі, об'ємні цілі — у мілілітрах показаного числа (`QuestRules.shownMl`: «8 унц.» — 237 мл). XP — за складністю з
`XPRules`, **на інстансі в мить видачі**; буст множить, серія — ні. Невиконане з минулим дедлайном — `.expired` мовчки, з
дошки зникає й відкатом не оживає. Відкат завдання відкочує й його події шини (`quest.completed` / `weeklyCompleted`) —
до відкату досягнень. Архівні ключі (`daily.goal`, `daily.entries4`…) не видаються, але інстанс доживає свій період з
`legacyXp`. «≤ 2 за 7 днів» — разом із сьогоднішнім (`recentDays` = 6), на легкому дні не знімається; Д5 видається за
20 хв до дедлайну, решта — за годину (`minLeadMinutes`). «Норма без нагадувань» — лише з `remindersActive` (ставить
`AppServices`). Тексти — не в знімку: `QuestSnapshot.title` — шаблон `QuestTitle`, рядок складає `QuestPresenter`
(`Features/Quests`); дошка — `questBoard(at:)`. У тестах `GameEnv` типово **без завдань** (`QuestForcing()`): «Перша
склянка» закривається першою ж порцією й міняла б XP кожного тесту; `quests: nil` — справжні пікери.
**Адаптивні** (WAT-67, SPEC-QUESTS §13): ціль — від того, як людина зазвичай п'є (`QuestHistory.baseline()`: час 25/50/75/100 %
норми, склянки, звична порція, блоки), з кроком у бік ідеалу; результат за 14 днів (`QuestOutcome`, `questOutcomes`)
піднімає чи опускає планку (`QuestAdaptation.deadline` / `count` / `blockTarget`), 3 провали поспіль адаптивного (2 —
решти) — пауза. «Закрий блок» з особистою ціллю — `QuestInstance.targetMl`, назва `QuestTitle.blockAim` («Вдень —
500 мл»); «Склянка після підйому» — звична порція, якщо вона менша за 250. «Три частини» й «Норма без нагадувань» —
лише тим, кому досяжні й не щоденні. Тижневі «Звички» — N від днів минулого тижня (`habitBase`). Минулі періоди, що
лишились `active`, прострочує перша подія доби (`QuestEngine.expireStale`). Перевірка без бази —
`AdaptiveQuestSimulationTests` (кожне завдання ≥ 25 % на п'яти звичках).
**Несподівані** (WAT-65, SPEC-QUESTS §6, QUESTS-PLAN §3): Н1–Н4 — `QuestCatalog.surprise`, scope `.adhoc`, період
`adhoc:<день>`. Вибір — чиста `SurprisePicker` (з 8-го дня, ≤ 1/день, не поспіль, ліміт `UserProfile.surpriseQuestsPerWeek`
0/1/2, без прогалин — лише «Блискавка» й ≤ 1/тиждень, відступ після двох проігнорованих), дні-кандидати —
`StableHash("<seed>|<week>|surprise")`. Планується **в тому ж проході, що й щоденні** (`QuestEngine.ensureInstances`), лише
на сьогодні й лише в першу дію дня: перезапуск посеред дня не перепланує. Сигнали (`weakDayPart` 14 днів, `weakWeekday` 42)
і тихі хвилини — замиканнями `gamification.surpriseSignals` / `quietMinutes` від `AppServices`. До `assignedAt` інстанс
лише скасовується (`.cancelled` — норма закрита чи частина йде за темпом) і пише прогрес для тексту сповіщення; порції до
появи вікна не рахуються; прострочене = проігноровано. Дошка несе несподіване **наперед** (`QuestSnapshot.visibleFrom`),
видимість — `QuestSnapshot.isVisible(at:)`, одна для головного, віджета й сповіщень. Нагорода — XP 25/50 (`XPRules.questXp(scope:
.adhoc…)`), подія `quest.surpriseCompleted` і ⚡ `grantPrize(…, ref: quest.id)` — один на інстанс, відкат не забирає.
«Вимк» у «Сповіщеннях» (`setSurpriseQuestsPerWeek(0)`) скасовує сьогоднішнє. Картка — `WTSurpriseCard` над «Сьогодні»
(`quest.surprise`, таймер `quest.surprise.timer`), тексти — `QuestPresenter.surprise*`.
**Блок на головному** (WAT-64, варіант A, SPEC-QUESTS §9.1–9.2) — лише там і у віджеті «Прогрес», на 3f завдань немає
(WAT-35). Що видно — чиста `QuestBlock.make(board:now:celebrating:showCompleted:)`: «Сьогодні» / «Цього тижня · ще N дн.»,
виконані — за «Виконані · N»; невиконане з минулим дедлайном зникає й без дії (`TimelineView` будить екран, час — `Clock`).
«Усе на сьогодні 🎉» — лише коли нічого не прострочено (`QuestBoard.expiredDaily`), інакше секції немає зовсім. Свято —
у рядку (`WTTaskRow(isCelebrating:)`), без тоста: `HomeViewModel.add` порівнює виконані до й після дії
(`celebratingQuestIds`); відкрила дія вікно досягнення — рядки чекають у `pendingQuestIds` до `celebrationDidClose`
і поки чекають — лишаються в списку. Згортання — `wtCelebrationHold` через `WTAnimation.celebrationHold`. Вібрація
`questDone` — останньою в ланцюгу `pulse`, лише коли гучнішого немає. Чип XP — з бустом і загальним множником
(`HomeViewModel.questXp`). Рядок — один елемент доступності з підписом `QuestPresenter.accessibilityLabel` і
ідентифікатором `quest.row.<ключ>`.
Подарунок за повернення й «Знову в ритмі» дії екран дізнається з черги `GamificationService.takeRecentUnlocks()`
(`HydrationService` про гейміфікацію не знає). `HomeViewModel` чистить чергу **до** дії й читає
**після** — інакше тост отримають розблокування зі старту чи повернутої порції. Досягнення з неї головний не показує —
їх святкує вікно з черги в базі.

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
  годинами, коротші за 2 год зливаються з сусідньою. Закрито — від **90 %** цілі (`GoalBlock.reachedMl`, WAT-67, §32):
  «ще N мл» чекпоінта й капсули — до цієї межі; порівнювати лише через `GoalBlock.isReached`, не `>= targetMl`. Одне визначення для чекпоінта (тип 4), XP
  `dayPartGoal`, звіту й «Рівномірності» 4a (рядки — ті самі блоки, повна смуга — ціль, WAT-47); випите в блоці
  рахується за часом порцій, не за `DayLog.partTotals` (§24). «Типова доба» лишається на 5 частинах
  (`PaceCurve.partTargetsMl()`, ніч поза активними годинами без ризки). Порція до
  підйому — першому блоку, після відбою — останньому (§25). Розклад дня — зі знімка в `DayLog` через
  `UserProfile.schedule(for:isWeekend:)`, не з профілю напряму: інакше зміна підйому переписує минулі дні.
- **Спад перед сном** (WAT-43, §29): останні `PaceCurve.taperMinutes` (2 год) до відбою крива йде з
  темпом `taperFactor` (½). Вікно — від відбою людини, не від `DayPart`; ваги `idealShare` не чіпати. Спад живе
  в приватних `pieces`, а `segments` лишаються по одному на частину доби — інакше `goalBlocks()` дав би блок
  і чекпоінт «до 20:00».
- **«Закрити норму»** (WAT-67, §32): вечірній підсумок, коли бракує більше за склянку, — категорія `CLOSE`, дія додає
  весь залишок (`PlannedNotification.actionMl` → `userInfo[glassMl]`, до 600 мл). Назви дій у категорії статичні.
- **Нагадування не допомагають** (§32): справжня відповідь — дія, тап чи порція за 15 хв; менше 30 % за 7 днів
  (`NotificationJournal.remindersIgnored`) — «Рідше» без повторних (лише з типовою частотою, `adaptiveReminders`) і разове
  вікно «Нагадувань забагато?» (`HomeSheet.reminderHelp`, `ReminderHelpScreen`) на чистому відкритті головного.
- **Чекпоінт** забирає собі основне нагадування у вікні `[−45, +30]` — ланцюг далі від нього. Так само **несподіване**
  `.challenge` (WAT-65, SPEC-QUESTS §6.6): `NotificationContext.surprise` (лише ще не видиме), id
  `wt.challenge.<dayKey>.<HHmm>`, приходить рівно в мить появи й не зсувається (`ConflictResolver`): у конфлікті з
  сильнішим — лише в застосунку. Тихі хвилини доби — `QuietWindow.minutes(onWeekday:)`, одні для плану й пікера.
  `SpecDaysTests` (§6.1) рахують лише тип 1, тож чекпоінти там вимкнені; повний день §6.3 — `CheckpointTests`.
- **Капсула частини доби** під кільцем головного (WAT-40, §26) — підказка, коли чекпоінт мовчить:
  `PaceCurve.dayPartProgress` (ті самі `GoalBlock`), тексти — `DayPartPresenter` («ще N мл» вгору до 50,
  як у чекпоінта). Хвилина — від `Clock` у `HomeViewModel.dayPartLine()`; `TimelineView` лише будить екран.
- **Звіти** рахує `Insights.report(for: ReportPeriod)` на льоту; для сповіщення `AppServices` кладе в
  контекст `ReportDigest` за періодами з `NotificationPlanner.reportPeriods`, текст складає `ReportText`.
  Денний — `.passive`, усі звіти без звуку й поза лімітом 8. Без сповіщень звіт відкривається з картки «Звіти» на 4a
  (`StatsViewModel.reportLinks`, лише періоди з порціями, WAT-67); «Обʼєм по днях» має режим «Рік» (середнє за день).

### Віджети (WAT-30, SPEC-WIDGETS)

- **Пише лише застосунок.** Розширення `WaterTrackerWidgets` лінкує тільки пакет `Widgets` і SwiftData не відкриває:
  два процеси в одному сховищі — застарілі дані й розбіжні кеші метрик. Застосунок наприкінці кожного проходу
  перепланування (`NotificationService.onRescheduled`) пише `WidgetSnapshot` у App Group
  (`<APP_GROUP_ID>/widget-snapshot.json`, `AppServices+Widgets.swift`); той самий зміст таймлайнів не
  перезавантажує. Нову добу без запуску застосунку віджет проєктує сам (`WidgetDay.resolve`).
- **Кнопки йдуть у процес застосунку** (`App/Shared/Intents`, у двох цілях) через `ForegroundContinuableIntent`,
  недоступний у розширенні (`@available(iOSApplicationExtension, unavailable)`), — **не `LiveActivityIntent`**: той
  додає ~3 с до кожного тапу («Команди» чекають, чи почне застосунок Live Activity). Порція йде
  `AppServices.perform(_:)` — тим самим шляхом, що «+склянка» зі сповіщення (відлуння, перепланування).
  Тіло `perform()` — лише в застосунку (`#if !WIDGET_EXTENSION`). «Додати воду» в «Командах» — `AddWaterIntent`,
  лише в застосунку, джерело `.shortcut`. «Скасувати» — лише щойно додану з віджета порцію.
  `perform(_:)` повертається одразу після порції й знімка — кожна частка секунди тут видна як пауза на віджеті;
  відлуння, перепланування й `reloadAllTimelines()` — у повернутій задачі під фоновим завданням
  (`AppContainer.finishInBackground`): натиснутий віджет WidgetKit перезавантажує сам і має бути першим у його черзі.
- **Таймлайн — короткий** (`WidgetTimeline`): після тапу віджет оновлюється, лише коли намальовано всі записи (×4 —
  світла/темна, повний колір/тонований). Не більше 12 кроків каденції, а поки видно «Скасувати» чи «Інше» — до їхнього
  кінця; далі WidgetKit просить новий таймлайн сам.
- **«Інше»** розгортає підказки шторки «Інше» в самому віджеті (вікна поверх робочого столу віджет не має): стан —
  `WidgetCustomPicker` в App Group, кнопки — звичайний `AppIntent` (`CustomPickerIntent`, лише в розширенні, без
  застосунку), окремо для кожного віджета, згортається сам за хвилину; порція згортає всі.
- **Запас води** — `HydrationReserve`: порція піднімає рівень на свій об'єм (ємність — 2 типові порції), нуль за
  10 хв до першого нагадування з плану, без плану — `PaceCurve.nextDueMinute` (та сама формула, що в планувальника).
  Та сама остання порція — рівень тягнеться без стрибків (відкриття застосунку відсуває нагадування на 30 хв).
- **Фіксований об'єм «Кнопки»** — `WidgetPortionGrid` (WAT-59): сітка кнопок головного в системі людини, одиниця в
  ідентифікаторі (`ml.250` / `oz.8`). Поставлені віджети зберігають ідентифікатор — `ml.N` не перейменовувати.
- В'юшки — у пакеті; кнопки через `\.widgetActionButton` (інтенти в SPM-пакеті Xcode 16 не індексує). Тексти —
  `WidgetPresenter` і `DayPartPresenter` (один для капсули головного й віджета). `kind` — `WidgetKind.identifier`,
  не міняти: поставлені віджети зникнуть. Кільце «Запасу» на екрані блокування — `Gauge`, не
  `ProgressView(timerInterval:)`: поза WidgetKit той — спінер.
- **«Прогрес» (M)** (WAT-64, SPEC-QUESTS §9.3): ліва половина — `Link` на 3f, права — на головний. Права — лише
  невиконані: до 2 щоденних і одне тижневе, стани — `WidgetPresenter.quests(_:at:)`. Несподіване (WAT-65) — першим
  рядком із `Text(timerInterval:)`, і тоді щоденних один; `WidgetSnapshot.surprise` несе його наперед, таймлайн має записи
  на `visibleFrom` і `expiresAt`. Знімок несе дедлайни
  (`Quest.expiresAt`), `expiredDailyQuests` і `weeklyStartsMonday` (усі нові поля — опційні: старий знімок у App Group
  декодується), таймлайн — запис на кожен дедлайн невиконаного щоденного.
- **Тоновані віджети iOS 18** лишають від кольору лише прозорість: тема — `WTTheme.tinted` (`wtWidgetTheme()` за
  `widgetRenderingMode`), акцентним (`widgetAccentable`) робити лише тло, не текст поверх нього; галочки — `CheckBadge`.
  Тло віджета (`containerBackground`) у тонованому режимі прибирається — усе, що несе зміст (вода «Запасу»), малювати
  у вмісті. Зеленого «закрито» у віджетах немає — пігулка `WTDonePill` кольору акценту (та сама — у «Рівномірності» 4a, WAT-47).
- **Ніч** (після відбою й до підйому) — «Запас води», «Частина доби» й кільце «Запасу» на екрані блокування стають
  нічним небом (`Views/WidgetNight.swift`: `NightSky`, `NightMoon`, палітра `WTTheme.night`) без відсотків запасу:
  «0%» уночі читалося як «води немає». Фаза ночі в `WidgetPresenter.part` — раніше за «норму закрито».
- Переходи — `watertracker://home|custom|stats|progress` (`WidgetLink`) → `.onOpenURL` → `AppServices.open(_:)`.

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
  лише понад нормальну паузу 2 год (§13.6). Будні й вихідні окремо. Пороги — `ScheduleShiftRules`. Зсув від 2 год —
  уже з 5 активних днів, менший — з 8 (WAT-67).
- Частота — `ScheduleOfferPolicy`, стан — `UserProfile.scheduleOffer*`. Показ одразу пишеться як «закрили»:
  застосунок можуть закрити з відкритим вікном.
- Показ — лише на відкритті: `services.activation` (холодний старт / повернення з фону), а не `epoch` — той
  змінюється й опівночі. `HomeViewModel.offerScheduleIfNeeded` перевіряє, що головний «чистий». Вікно —
  `HomeSheet.schedule` на весь екран, тексти — `SchedulePresenter`.
- Застосування — `AppServices+Schedule.swift` (зачіпає `Hydration`): профіль → `scheduleDidChange()` → `touch()`.
- Межі розкладу (підйом від 04:00, відбій до 24:00, ≥ 6 год, крок 15 хв) — `DaySchedule`, одні для екрана
  «Сповіщення», вікна й `Insights`.

### Знання (WAT-53, SPEC-LEARN)

- Бібліотека й історії — варіант A «Історії» з `Design/Learn.html` (рішення від 19.10.2026): повноекранні слайди з
  тапом через той самий `WTStoryPlayer`, що й звіт (стилі полиць `WTStoryStyle.learnWater/learnDeep/learnWarm`). Вхід —
  кнопка «книжка» в шапці головного (`AppRoute.learn`), контекстні — «Детальніше» в довіднику «Звідки XP», «Як працюють
  призи», «Як працює серія» в календарі, «Як користуватися» в «Налаштуваннях» (`AppRoute.learnStory`).
- `LearnCatalog` — метадані 12 історій (ідентифікатор — ключ прогресу й ref метрики, не міняти); тексти й ілюстрації
  складає `LearnPresenter` — чиста функція з живими значеннями (`LearnContext`: норма, блоки цілей, `XPRules`,
  `LevelRoadCatalog`, рівень): після зміни балансу історія не бреше. Ілюстрації — `WTLearn*` у `DesignSystem`, колір —
  з `WTLearnInk` за стилем слайда; інтерактивні тримають стан у собі й нічого не пишуть.
- Вікторина — картка, що перевертається (`WTLearnFlipCard`); прихований бік — `hidden()`, а не прозорість, інакше
  VoiceOver і XCUITest бачать кнопки під відповіддю.
- Прогрес — `LearnProgress` / `LearnStore`: рядок з'являється, щойно бібліотека показала історію; історія без рядка —
  нова (крапка на кнопці головного), але на першому відкритті «Нове» на обкладинках не горить. Фініш і кнопка «Що з цим
  робити» — `finishLearnStory`: події `learn.completed` і полиці з ref від історії, досягнення «Відкриттів»; XP за
  історію немає. Тексти — `LearnFeatureTests` (довжини, без роду, джерело в кожного факту полиці «Вода й тіло»).

### Онбординг (WAT-56, SPEC-ONBOARDING)

- **Чорновий**: тексти, графіку, фактчек і остаточний дизайн доводить WAT-57. Кроки — декларативний
  `OnboardingCatalog` (одиниці → стать і стан → вік → вага → активність → норма → день → ритм → склянка → нагадування);
  новий крок — рядок у каталозі плюс вигляд у `OnboardingStepBody` / `OnboardingSceneArt`.
- Перший запуск — сам, лише коли `onboardingState == .notShown` **і** в базі немає жодної порції
  (`AppServices.shouldOpenOnboarding`): хто оновився з історією, вікна поверх головного не бачить. Повторно — рядок
  «Підібрати під себе» в «Налаштуваннях». Оверлей у `RootView` поверх стека; поки він відкритий, головний не «чистий».
- `OnboardingModel` нічого не пише сама — `AppServices.applyOnboarding` одним проходом, один `touch()` і `epoch`.
  Перший запуск: «Пропустити» на вітанні — нічого, далі — лише кроки, підтверджені «Далі»; норма — лише після кроку
  «Норма». Повторний прохід: поточні значення з «Зараз», запис — лише «Зберегти» з переліком змін; ручну норму
  (`GoalSource.manual`) мовчки не переписуємо; ✕ питає, лише якщо людина щось змінила сама.
- Норма — `GoalFormulaRegistry.current` + надбавка стану (`GoalInputs.condition`, лише при «Жінка»); розклад для екрана —
  `GoalFormula.breakdown`. Поправка ±50 мл — відносно розрахунку й скидається зі зміною вхідних даних.
- Одиниці: `UserProfile.volumeUnit` / `massUnit` / `timeFormat` (12 год — «7:30 дп», `TimeFormat`). Поза онбордингом
  поки діють лише у віджетах; налаштування одиниць і показ по застосунку — окремо.
- Дизайн — **тимчасовий** перемикач `OnboardingDesign` («Сцена» / «Кроки») у `UserDefaults`, секція «Тимчасово» в
  «Налаштуваннях»; прибрати в WAT-57. Обидва каркаси ділять `OnboardingStepBody`; тло сцен — стилі «Знань»
  (`WTStoryStyle`), ілюстрації — `WTScene*` з «чорнилом» `WTLearnInk`. Прихованої верхньої панелі не має бути в дереві
  доступності — не лише прозорої (друге «Пропустити» ламало e2e).

### Режим розробника (WAT-68)

- «Налаштування» → «Режим розробника» — **лише DEBUG**: `#if DEBUG` на самому рядку, як «План сповіщень»; екрани й доменні
  методи компілюються завжди — їх покривають тести. Сторінки — `AppRoute.developer(DeveloperPage)`,
  `--start-screen developer[:day|achievements|quests]`.
- Дії — `AppServices+Developer.swift`: тим самим шляхом, що й дія людини (порція — `HydrationService`, приз —
  `GamificationService`), і кінчаються так само: `touch()`, `epoch`, вікно відкриття. Зміна минулого дня — ще й
  `gamification.refresh`, як після демо-історії. Порція в минулий день відкриває досягнення з часом самої порції:
  раніше за `celebrationsSince` — без вікна, як відкрите заднім числом.
- Повз правила — `GamificationService+Developer.swift`: відкрити / закрити досягнення (і таємні, і пасхалки), видати /
  виконати / скасувати завдання (параметри — як у пікера, без відбору), XP, будь-який рівень, зупинити буст, заморозка дня
  без призу. Рівень — поправка журналу до порогу (`XPEngine.adjust`, униз — від'ємний запис `.debug`, а не відкат чужих
  нарахувань); видані призи й досягнення лишаються, `highestCelebratedLevel` іде за рівнем — наступне справжнє підняття
  святкується. Примусове позначене `GamificationService.developerRef` (`unlockedByRef` / `completedByRef`) — **відкат порції його
  не знімає**. Прохід після дії йде з іншим ref: відкрите ним за умовою відкочується, як завжди. Скасоване виконане
  завдання знімає й залежні досягнення («Тижнева мета»), як відкат.
- Масові дії (демо-історія, серія днів) — кроками: крок — день в одному `SaveBatch` (`Persistence`: `save()` сховищ
  відкладено до кінця кроку), між кроками — пауза на кадр і індикатор поверх сторінки. Пакет — **на крок, не на всю
  історію**: незбережене перебирає кожна вибірка, і пакет на 60 днів ішов учетверо довше, ніж без пакета.
  `FixtureSeeder.steps` — ті самі кроки й для старту e2e (підряд, без пауз).
- Дні: норма одного дня — `HydrationService.setGoal(_:on:)` (ревізія на день і колишня норма на наступний — інакше нова
  потекла б до сьогодні), заповнення — чиста `DayFill` (рівно по активних годинах, кратно 50 мл, ≥ 20 хв між порціями:
  кілька в одну хвилину відкрили б пасхалки «серією»). Мить дня за хвилиною — `CalendarService.date(_:minute:)`, не
  «північ + N хвилин»: у день переведення годинника те дає годину зсуву.
- Годинник — `OffsetClock` (`Core`): у DEBUG застосунок збирає його поверх системного завжди, зсув — у `DeveloperSettings`
  (`UserDefaults`, живе між запусками), зміна — як переведений системний час (`handleTimeChange`). e2e мають власне, щоразу
  порожнє сховище налаштувань розробника; з `--uitest-now` — `FixedClock`, і зсуву немає.
- Скидання — **на наступному запуску**: сервіси тримають живі об'єкти бази, стерти з-під них на ходу — падіння. Режим
  розробника пише `DeveloperSettings.pendingReset` і закриває застосунок (`exit(0)`), `AppContainer` до сервісів кличе
  `Database.erase(_:in:)`. «Прогрес» лишає `Database.settingsModels` і скидає стан гри в профілі, «усе» — порожнє сховище
  й онбординг. Нова модель — у `progressModels` чи `settingsModels` (`DatabaseEraseTests` тримає повноту).
- Сповіщення: зразок будь-якої ситуації (`NotificationSample`, 16 видів + відлуння) за 5 чи 30 с —
  `NotificationPlanner.sample` складає той самий `PlannedNotification` (категорія дій, перехід, текст від `TextComposer`),
  `NotificationService.scheduleSample` ставить його з ідентифікатором `debug.` — поза диффом плану й без приглушення при
  відкритому застосунку. Композитор ставить нагадуванню `wt.reminder.…` — `sample` повертає `debug.` після нього.
- Об'єм тут — завжди мілілітри (`DeveloperPresenter`): так він зберігається. Дата й час — системний `DatePicker`: свого
  компонента точної хвилини в `DesignSystem` немає.

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
- Схема — `Database.schema` (17 моделей), одне місце для майбутніх міграцій. `VersionedSchema` свідомо немає (WAT-67): нове
  поле — **лише опційне чи з типовим значенням** (легка міграція), перейменування — `@Attribute(originalName:)`.
  Перед першим відкриттям зміненої схеми — копія сховища в `Backups/` (`Database.backupIfSchemaChanged`, три останні);
  сховище не відкрилось — `StoreFailureScreen`, а не тиха база в пам'яті (`AppContainer.storeError`).

### Одиниці (WAT-46, WAT-58)

Усе зберігається в **мілілітрах, кілограмах і хвилинах**; `UserProfile.volumeUnit` / `massUnit` / `timeFormat` —
лише показ і тексти. Перемикаються в онбордингу й у «Налаштуваннях» → «Одиниці» (`WTSegmentRow`, рядки —
`OnboardingPresenter.unitRows`); кожна зміна — `touch()`, тож тексти сповіщень і знімок віджетів перескладаються одразу.
- **Об'єм** у тексті — тільки через `VolumeUnit.label` (до 1 л мл, далі «1.05 л») / `format(_:metric:)` / `portion` /
  `number` з одиницею профілю: метричний формат у кожного місця свій («1.25 л» на кільці, «1,05 л» у сповіщенні) і
  закріплений тестами, унції — однакові скрізь, цілі, «8 унц.» (крапку в кінці речення знімає `VolumeUnit.tidy`).
  Кроки редагування — `VolumeSteps` (Hydration) у одиницях системи; змінювати систему — лише
  `HydrationService.setVolumeUnit(_:)` (і з онбордингу), він переводить кнопки порцій.
- **Час** — `TimeFormat.clock` / `hourRange`, ніколи не «%02d:%02d» і не `DateFormatter("HH:mm")`. Презентери беруть
  формат параметром (`format:` / `timeFormat`, типово 24 год — на цьому стоять старі тести), моделі — з профілю.
- **Вага** — `MassUnit.label` / `units`; крок ваги — від показаного числа, не від кілограмів.
- **Віджети** читають систему зі знімка (`WidgetSnapshot.unitRaw` / `timeFormatRaw`) через `WidgetDay.unit` /
  `timeFormat`; позначення поруч із великим числом — `WidgetPresenter.bigUnit`, не `Text("л")`.

### Час

**Ніколи не викликати `Date()` напряму.** Єдине джерело — протокол `Clock`
(`Core/Clock.swift`); у тестах `FixedClock`, у DEBUG-застосунку — `OffsetClock` режиму розробника. Доба, `dayKey`, години й частини доби —
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
  теж `HomeSheet` (`.glass`): так порція з нього йде тим самим шляхом, а вікно відкриття чекає, поки воно закриється.
- Кілька `ForEach` в одному `LazyVGrid` — з різними ідентифікаторами: однакові 0…6 зливають комірки
  (мозаїка місяця губила перший тиждень).
- Поповер від кнопки — `wtPopoverAnchor()` на кнопці + `wtPopover(...)` на **корені** екрана:
  кнопка в `ScrollView`, і меню, намальоване там, лягало б під наступні блоки.
- Фон кола досягнення — `theme.unlockedIconBg` / `theme.lockedIconBg`, не `WTColor.goldIconBg`
  напряму: той фіксовано світлий і «світиться» в темній темі. Те саме для призів —
  `theme.prizeIconBg`, не `WTColor.prizeIconBg`.
- Безкінечний рух поряд із кнопкою — `TimelineView` з `Canvas`, не з `Shape`: дві фігури, перебудовані щокадру,
  ковтали перший тап по «Чудово» у вікні відкриття (WAT-62). Блокування кнопки на час — перевіркою часу в дії,
  не `allowsHitTesting`.
- Макети розраховані на кадр 402 × 874 pt; Dynamic Type обмежено `.wtTypeSizeLimit()`
  у `WTThemedContainer`.

## Тести

- **Аудит 60 днів** (WAT-67) — `LongRunAuditTests` (Features, на вимогу): 12 типів людей через `HomeViewModel` і справжні
  планувальник, пікери й сповіщення на `FixedClock` — норма, XP, рівні, досягнення, призи, успішність кожного завдання,
  навантаження сповіщеннями, дні на ліміті. Для калібрування після змін балансу:
  `WT_AUDIT=1 WT_AUDIT_OUT=<тека> swift test --package-path Packages/Features --parallel --filter LongRunAuditTests`
  (персона — 1–3 хв). Журнал сповіщень застосунок чистить через 35 днів — аудит знімає його щодня. Зерно профілю — мить
  створення, тож прогони трохи різняться: дивись на тенденцію, а не на одиниці.
- `accessibilityIdentifier` **не вішати на контейнер** — він успадковується дочірніми
  й перекриває їхні власні. На цьому двічі ламались e2e (шторки, потім тост).
- `waitForExistence` не є перевіркою видимості — елемент за межею екрана лишить тест
  зеленим. Для тостів і оверлеїв додатково перевіряти `isHittable` і межі вікна.
- Позначення «переглянуто» — лише в `reload()` з `onAppear`, не в `init` моделі: інакше
  друге читання вже не бачить нових, і крапки «нове» не з'являються зовсім (WAT-23).
- Сітка 2e лінива, а досягнень 102: плитку шукати після фільтра категорії (`achievements.category.option.<key>`),
  інакше вона може бути ще не на екрані. Вікно відкриття на справжньому годиннику нестабільне (повня, 11:11, 1 квітня
  відкривають таємні) — закріплюй `--uitest-now`.
- Вікно відкриття модальне й на весь екран: сценарій, що додає першу порцію на `--uitest-empty` чи робить «Відкриття»
  (тема, кнопки порцій, історія «Знань», графік), закриває його `dismissCelebrationIfPresent(app)`
  (`Tests/AppUITests/CelebrationHelpers.swift`) — інакше наступний тап ляже у вікно. Помічник чекає появи (≈ 0,6 с
  після дії), тож на кроках без вікна давай йому малий `timeout`.
- Прапорці запуску (`App/Sources/WaterTrackerApp.swift`, `LaunchConfiguration`):
  `--uitest-empty` (чиста in-memory БД), `--uitest-demo` (демо-історія),
  `--seed-demo`, `--start-screen progress|level-road|achievements|prizes|stats|settings|portion-buttons|notifications|notification-plan|report|schedule-suggestion|widgets|learn|onboarding|developer`
  (`developer:day|achievements|quests` — сторінка режиму розробника;
  `learn:app.xp` — одразу історія, `learn:body.why:4` — з п'ятого слайда, вікторина;
  `onboarding` — перший запуск, `onboarding:revisit` — повторний прохід; `--onboarding-design scene|steps`, під
  `--uitest-*` типово «Сцена»; сам онбординг під `--uitest-*` не відкривається)
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
  сценарії); `--notification-tap reminder|morning|evening|rescue|comeback|echo|report|challenge` імітує тап
  (`morning` — вікно «Склянка», `report` — звіт за минулий тиждень);
  `--uitest-now 2026-10-01T07:00:00+03:00` фіксує годинник для DEBUG-екрана «План сповіщень».
- Завдання в e2e: `--quests daily:daily.wakeGlass,daily.glasses;weekly:weekly.goalDays=5;surprise:surprise.glassNow@13:30`
  (лише DEBUG) видає саме ці завдання повз пікери — вибір пікера залежить від зерна профілю й дня. Без прапорця під
  `--uitest-*` — звичайний пікер: на `--uitest-empty` це стартові «Перша склянка» й «Половина норми»; **несподіваних без
  `surprise:` немає зовсім** (`surprisesEnabled = false`): демо-історія старша за 8 днів, і картка перекрила б чужі
  сценарії. Ставиться до `bootstrap()`. Рядок шукати за
  `quest.row.<ключ>` (`descendants(matching: .any)`): назва — частина його підпису, окремим `staticText` її немає.
  Підйом типово о 08:00 — дедлайн «Склянки після підйому» о 09:00.
- Віджети в e2e: домашній екран у XCUITest нестабільний, тож в'юшки — у DEBUG-галереї `--start-screen widgets`
  (кнопки кличуть `AppServices.perform` напряму, ідентифікатори `widget.add.<мл>` / `widget.undo`), дії —
  `--widget-action add:250,undo`, переходи — `XCUIDevice.shared.system.open(watertracker://…)` (не `app.open`:
  той нестабільно чіпляється за системний діалог «Відкрити у програмі?»). Галерея без `--uitest-now` о пізній годині
  показує нічний стан. Під `--uitest-*` знімок у App Group не пишеться.

## Відомі прогалини

Актуальний список — `PLAN.md` §«Наступні кроки». Найсуттєвіші:

1. VoiceOver: `accessibilityLabel` / `accessibilityValue` є лише в модулі досягнень
   (WAT-23); решта екранів має тільки `accessibilityIdentifier` для e2e.
2. Рядки зашиті в коді українською — локалізація в `.xcstrings` не зроблена.
3. `HomeSheet.stats` реалізований (`WeekStatsSheet`), але недосяжний з UI.
4. `GoalCalculatorSheet` готовий і покритий тестами, але не підключений (норму рахує онбординг — WAT-56).
5. Онбординг чорновий — фіналізація в WAT-57.
6. Сповіщення: повний редизайн екрана «Сповіщення» — WAT-18; ассету звуку «булькання» (`drop.caf`) немає — грає системний.
7. Межа доби — опівночі, відбій — не пізніше 24:00: порції сови після півночі йдуть у наступний день (WAT-67, §32 п. 6).

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
| `SPEC-ACHIEVEMENTS-CATALOG.md` | каталог досягнень (WAT-49): 115 досягнень у 8 категоріях (+3 за «Знання» — WAT-53; перебалансування першого тижня — WAT-60, §10: 112), складність і «коли ≈», таємні з підказкою й пасхалки, невидимі до знахідки; реалізація — WAT-24, XP — WAT-25 |
| `ACHIEVEMENTS-RARITY.md` | аналіз WAT-60: що відкривається в перший тиждень і чому, виміри до / після симуляцією аудиту, хід рішень; ТЗ — у SPEC-ACHIEVEMENTS-CATALOG §10 і SPEC-ACHIEVEMENTS §8 |
| `ACHIEVEMENTS-RARITY-PLAN.md` | план реалізації WAT-60 для виконавця: §1 каталог (архівні, пороги, відкат з часу події), §2 вікно відкриття «Хвиля» (черга `celebratedAt`, паузи, e2e) |
| `Design/Celebration.html` | макет вікна відкриття досягнення (WAT-60): три варіанти, погоджено B «Хвиля»; перший тиждень до / після для трьох персон |
| `SPEC-PRIZES.md` | ТЗ модуля «Призи» (WAT-26): каталог, блок на 3f, екран «Призи», картка призу, правила заморозки й буста |
| `Design/Prizes.html` | макет модуля призів (6 кадрів 402×874) до цього ТЗ; перенесено в код у WAT-34 |
| `Design/LevelRoad.html` | макет вікна «Шлях рівнів» (WAT-44, SPEC-PRIZES §16): погоджено «Драбину» й «Скриню», компактний вибір; інфографіка частоти призів |
| `Config/Balance.xcconfig` | баланс XP: XP за крок об'єму води й загальний множник (SPEC-PRIZES §16.13) |
| `SPEC-WIDGETS.md` | ТЗ віджетів (WAT-30): набір, «Скасувати», налаштування «Кнопки», алгоритм «Запасу води», екран блокування, Пункт керування, «Команди»; один пише — застосунок, віджет читає знімок |
| `Design/Widgets.html` | інтерактивний макет віджетів (WAT-30): три сторінки домашнього екрана, варіанти «Запасу води» й «Огляду дня», екран блокування, StandBy, Пункт керування |
| `SPEC-NOTIFICATIONS.md` | ТЗ модуля «Сповіщення» (WAT-17): типи, нагадування за кривою темпу, анти-спам, тексти, налаштування, локальні сповіщення й планувальник; етапи 0 і A реалізовано в WAT-36 (рішення — §23), етап B — у WAT-37 (§24), одна модель цілей частин доби — WAT-39 (§25), капсула частини доби на головному — WAT-40 (§26), пропозиція змінити графік дня — WAT-41 (§27), перемикач «Ритм дня» — WAT-42 (§28), спад кривої темпу перед сном — WAT-43 (§29), екран «Налаштування» на весь екран — WAT-15 (§30), «Рівномірність» блоками цілей із ціллю-смугою — WAT-47 (§31) |
| `Design/DayPart.html` | макет капсули частини доби на головному (WAT-40): три варіанти, погоджено A (SPEC-NOTIFICATIONS §26) |
| `Design/Evenness.html` | макет «Рівномірності за день» (WAT-47): чотири варіанти на 5 частинах і на блоках, погоджено A «Смуги» на блоках цілей (SPEC-NOTIFICATIONS §31) |
| `Design/Schedule.html` | макет вікна «Графік дня» (WAT-41): три варіанти, погоджено A «Час», і правило зсуву на 14 днях (SPEC-NOTIFICATIONS §27) |
| `Design/Notifications.html` | інтерактивний макет етапу B (WAT-37): вікно «Склянка», звіт-історія дня / тижня / місяця, рядки B на екрані «Сповіщення» |
| `SPEC-LEARN.md` | ТЗ розділу «Знання» (WAT-53): каталог 12 історій на трьох полицях, вхід із шапки головного й контекстні входи, правила формату, текстів, джерел і руху, прогрес читання, технічна схема |
| `Design/Learn.html` | макет розділу «Знання» (WAT-53): три варіанти вигляду — історії, картки, лонгрід — на тих самих зразкових історіях; бібліотека, програвач, вікторина |
| `SPEC-ONBOARDING.md` | ТЗ онбордингу (WAT-56): склад кроків і чого не питаємо, розрахунок норми зі станом, пропуск, повторний прохід із «Зараз» і «Що зміниться», застереження; рішення реалізації; фіналізація — WAT-57 |
| `Design/Onboarding.html` | макет онбордингу (WAT-56): дизайни формату «Кроки» — A «Кроки», B «Вода», C «Сцена»; реалізовано «Сцену», «Кроки» — за тимчасовим перемикачем |
| `SPEC-QUESTS.md` | ТЗ завдань (WAT-29): щоденні (слоти «Темп» і «Ритм»), тижневі («Сталість» і «Звичка»), несподівані; каталог, алгоритми видачі, XP за складністю, показ на головному й у віджеті «Прогрес», бюджет уваги; 3f без завдань |
| `QUESTS-PLAN.md` | план реалізації WAT-29 для виконавця: §1 двигун і каталог, §2 головний / 3f / віджет, §3 несподівані (сповіщення `.challenge`, налаштування, «Несподіванка») |
| `Design/Quests.html` | макет завдань (WAT-29): три варіанти блоку на головному, погоджено A «Розділи»; віджет «Прогрес» і сповіщення несподіваного |
| `DESIGN-TOKENS.md` | витяг токенів з макетів |
| `WaterTracker.html` | оригінальні макети (1a, 3f, 2e, 4a) |

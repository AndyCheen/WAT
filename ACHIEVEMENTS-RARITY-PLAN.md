# План реалізації WAT-60 — рідкісні досягнення й вікно «Хвиля»

> **Для виконавця.** ТЗ — `SPEC-ACHIEVEMENTS-CATALOG.md` §10 (каталог) і `SPEC-ACHIEVEMENTS.md` §8 (вікно
> відкриття). Аналіз і виміри — `ACHIEVEMENTS-RARITY.md`. Макет — `Design/Celebration.html`, варіант **B «Хвиля»**.
> Правила репозиторію — `CLAUDE.md`. Найважливіші тут:
>
> - час — лише `Clock`;
> - `metrics.commit()` — раз на дію;
> - кольори й розміри — токени `DesignSystem`;
> - `accessibilityIdentifier` не вішати на контейнер;
> - `xcodebuild` — лише з `-derivedDataPath DerivedData`.

**Два PR — дві підзадачі Linear**, кожна — логічні коміти в одному PR:

1. **Каталог** (§1) — Gamification, трохи Notifications і Features. Самостійний.
2. **Вікно відкриття** (§2) — Persistence, Gamification, Features, DesignSystem, e2e. Спирається на §1.

**Залежність від WAT-29:**

- «Несподіванка» з'являється разом із несподіваними завданнями — §1.6.
- Вада «`questCompleted` не відкочується» (`GamificationService.swift:179`) зачіпає «Тижневу мету», «Несподіванку» й
  «Без хвостів». Її виправляє WAT-29; якщо §1 іде першим — виправити тут.

---

## 1. Каталог

### 1.1 Архівні досягнення

`SPEC-ACHIEVEMENTS-CATALOG §10.2`.

- **`AchievementDefinition`** (`AchievementRule.swift`): поле `isRetired: Bool`, у `init` — `retired: Bool = false`.
  `isCore` для архівного — `false`.
- **`AchievementEngine`:**
  - `evaluate` і `revert` архівні пропускають;
  - `snapshots` — архівне невідкрите не потрапляє в знімок, як пасхалка до знахідки; відкрите — звичайний знімок;
  - `collectionCounts` — відкрите архівне рахується в `.all` («Колекція», «Вітрина», «Музей»), але не в `.core`.
- **Знімок** (`AchievementSnapshot`): поле `isRetired`.
  - `tally` (`Snapshots.swift`) рахує видимим лише `!isEgg && !isRetired`.
  - `AchievementCatalog.categories` архівних не враховує.
- **Тести** `GamificationTests`:
  - на чистій установці архівне не відкривається й не видно;
  - відкрите до архівації — видно, не в `tally`, рахується в «Колекції»;
  - ціль «Усе зібрано» його не містить.

### 1.2 Відкат знімає лише відкрите не раніше події

`SPEC-ACHIEVEMENTS-CATALOG §10.3`.

- `AchievementEngine.revert(_:policy:at:since:)` знімає досягнення, лише якщо `progress.unlockedAt >= since`.
- `GamificationService.metricsDidRevert` передає `since` — найраніший `occurredAt` серед `events`, які відкочують.
  **Перевірити:** це час самої події, а не мить відкату. Якщо ні — брати час порції з `sourceRef`.
- **Тести:**
  - «Добрий ранок», відкритий за старим порогом 1: новий поріг 10, видалення пізнішої порції — лишається відкритим;
  - наявні тести відкату («порція, що відкрила, — знімає») — зелені.

### 1.3 Рядки каталогу

`Catalogs.swift`. Ключі не змінюються.

| Ключ | Зміна |
|---|---|
| `volume.1l`, `portions.10`, `level.5`, `mystery.first`, `discover.levelChoice`, `discover.undo`, `discover.notifications` | `retired: true` |
| `volume.10l` | `target: 20_000`, `details: "20 л води загалом"` |
| `rhythm.morning` | `target: 10`, `.medium`, `details: "10 днів із закритою ціллю ранку"` |
| `rhythm.allThree` | `target: 3`, `details: "3 дні, коли закрито всі три цілі"` |
| `rhythm.even90` | `rule: .history(.evennessDays(min: 90))`, `target: 7`, `details: "7 днів із «Рівномірністю за день» від 90"` |
| `rhythm.responsive` | `target: 30`, `details: "30 порцій за 15 хв після нагадування"` |
| `rhythm.ahead` | `target: 10`, `details: "10 днів із нормою без жодного нагадування"` |
| `stats.bullseye` | `target: 3`, `.medium`, `details: "3 дні рівно норма, до мілілітра"` (підказка та сама) |
| `stats.accuracy` | `target: 10`, `details: "10 днів, коли випито 100–105 % норми"` |
| `special.halfFull` | `target: 5`, `.medium`, `details: "5 днів, коли до 12:00 випито пів норми"` |
| `special.eightGlasses` | `title: "Вісім на вісім"`, `rule: .history(.daysWithEntries(min: 8))`, `target: 8`, `.medium`, `details: "8 днів по 8 порцій. «8 склянок» — міф, але гарний"` |
| `quest.allDaily` | `title: "Без хвостів"`, `target: 10`, `.medium`, `details: "10 днів, коли виконано всі щоденні завдання"` |
| `quest.first` | `title: "Тижнева мета"`, `details: "Виконано перше тижневе завдання"`, `rule: .count(.weeklyQuestCompleted)` |
| `discover.dark` | `details: "Темну тему обрано в налаштуваннях"` |
| `special.fullMoon` | `rule: .history(.goalOnFullMoon)`, `details: "Норма в день повного місяця"` |
| `special.twins` | `details: "Два дні поспіль однаковий обсяг, до мілілітра, — не рівно норма"` |
| `quest.firstSurprise` *(нове, §1.6)* | «Несподіванка», ⏱️, `.game`, `.easy`, `details: "Виконано перше несподіване завдання"`, `rule: .count(.surpriseQuestCompleted)`, `target: 1`, `gate: .surpriseQuests` |

Оновити doc-коментарі секцій: числа в заголовках, «Рівні — лише віхи» без 5-го.

### 1.4 Правила історії

`DayHistory.swift`.

- `evennessDays(min:)` — завершені активні дні з `evenness >= min`. Додати в `onlyFinishedDays`.
- `daysWithEntries(min:)` — дні з `entries >= min`.
- `goalOnFullMoon` — день із нормою, що припадає на повню.
- `twinDays` — додатково `lhs.totalMl != lhs.goalMl`.
- `bestEvenness`, `bestEntriesInDay`, `portionOnFullMoon` прибрати, якщо більше ніде не вживаються.
- **Тести** `DayHistoryTests` — на кожне правило, зокрема: «рівно норма двічі поспіль — не близнюки».

### 1.5 Подія «тижневе завдання виконано»

- `MetricKey.weeklyQuestCompleted = "quest.weeklyCompleted"`.
- `GamificationService.awardQuestXP`: для визначення з `scope == .weekly` — ще одна подія з тим самим
  `sourceRef: quest.id`, щоб відкочувалась разом із завданням.
- До `internalMetrics` не додавати: досягнення мають на неї реагувати.

### 1.6 «Несподіванка» — разом із несподіваними завданнями WAT-29

Потрібні: подія `quest.surpriseCompleted` (від `awardQuestXP` для несподіваного scope), гейт
`AchievementGate.surpriseQuests` з підписом «Увімкни несподівані завдання» і поле в `AchievementGates`.

- Якщо на момент §1 несподіваних завдань у `main` ще немає — **рядок каталогу не додавати**: недосяжне досягнення без
  гейта висіло б «у процесі». Додати пункт у план WAT-29.
- Інакше — додати тут.

### 1.7 Поза Gamification

- **«Вчасно».** `NotificationService.noteGoalMet`: `$0.type == .rescue && $0.slot == "pm"`. Тест у
  `NotificationsTests`: ранковий порятунок «Вчасно» не дає.
- **«Темна сторона».** `RootView`: прибрати `.onChange(of: colorScheme, initial: true) { … record(.darkTheme) }`.
  Вибір «Темна» вже записує `SettingsModel` (`SettingsModel.swift:141`). «Дискотека» не змінюється.

### 1.8 Числа, бюджет, документація

- Тести, що тримають числа каталогу (118 / 108 / 82, пороги, назви), — на 112 / 102 / 76 і нові пороги.
- **Бюджет першого тижня — постійна перевірка.** Тиждень з `AttentionAuditWeek1Tests` (у `main` з WAT-29; інакше —
  з гілки `claude/epic-lovelace-0a4f7e`) винести в спільний помічник.
  - Додати персону «Старанний» (patch `wat60-audit-diligent-persona.patch` у нотатках сесії).
  - Новий `AchievementBudgetTests` — у звичайному прогоні, без друку: «Типовий» і «Старанний», день 1 ≤ 2, тиждень
    ≤ 6 / ≤ 8, не більше одного вікна на дію (останнє — після §2).
  - Звіт аудиту лишається на вимогу (`WT_AUDIT=1`).
- **`CLAUDE.md`, розділ «Досягнення»:** 112 замість 118, архівні, правило відкату з часу події.
- **Перевірка:** `make test-packages` зелений. Аудит дає 2 / 6 / 8 / 10 (день 1 / «Типовий» / «Старанний» /
  «Дослідник») — з точністю до днів завдань WAT-29.

---

## 2. Вікно відкриття «Хвиля»

### 2.1 Дані

- **`AchievementProgress.celebratedAt: Date?`** (`GamificationRecords.swift`). Опційне поле — легка міграція SwiftData.
  **Перевірити**, що `Database.schema` не версіонована вручну. Якщо версіонована — додати етап.
- **`UserProfile.celebrationsSince: Date?`.**
  - `AppServices.bootstrap()` ставить `clock.now`, якщо поле порожнє, **до** стартового перерахунку.
  - Усе, що відкрито раніше, — відсвятковане: оновлення застосунку не вивалить вікно на десятки сторінок.
  - Відкрите перерахунком після оновлення (нові умови) — вже після цієї дати, тож отримає одне вікно.
- **Сіди.** Демо-історія (`--seed-demo`, `--uitest-demo`) і сіди e2e ставлять `celebrationsSince` **після** сіду.
- **Відкат.** `AchievementEngine.revert` скидає `seenAt`, але **не** `celebratedAt`.

### 2.2 Gamification

- `pendingCelebrations(since:) -> [AchievementSnapshot]` — відкрите, не архівне, `celebratedAt == nil`,
  `unlockedAt >= since`, за `unlockedAt`.
- `markCelebrated(keys:)` — ставить `celebratedAt` і `seenAt` (крапки «нове» за відсвятковане немає).
- `takeRecentUnlocks()` лишається для подарунка за повернення й бонусу «Знову в ритмі». Досягнення з нього головний
  більше не показує тостом.
- **Тести:**
  - `pending` / `mark` / `since`;
  - відкат не скидає `celebratedAt`, повторне відкриття — не в черзі;
  - архівне ніколи не в черзі.

### 2.3 Модель показу (Features)

- **`Celebration`** — значення:
  - сторінки (`CelebrationPage`: знак, назва, опис, XP, вид — звичайне / таємне / пасхалка / перша пасхалка,
    «Далі»);
  - рядок рівня (`CelebrationLevel`: номер і вузол `LevelRoadCatalog.node(forLevel:)`);
  - контекст: `.action` чи `.whileAway`.
- **`CelebrationPresenter`** — чиста функція.
  - Опис — `details` знімка з одиницями профілю.
  - «Далі» — §8.4 ТЗ: те саме `rule`, найменша ціль понад поточну, не таємне й не архівне, відкритий гейт, прогрес
    ≥ 10 %, формат плитки «3 / 7».
  - Більше трьох — одна сторінка «Нові досягнення: N».
  - Підписи й тексти кнопок — тут.
  - Тести: тексти на «ти» й без роду, правило «Далі», сторінка-сітка.
- **`AppServices`:**
  - `celebration: Celebration?` (observable);
  - `presentCelebrations(context:level:)` — бере чергу, будує, показує, якщо показ не призупинено;
  - `beginCelebrationPause()` / `endCelebrationPause()` — лічильник;
  - `dismissCelebration(_:)` — `markCelebrated` і, для «Обрати приз» / «Відкрити 🎁», маршрут на 3f з «Шляхом
    рівнів».
- **Паузи:**
  - онбординг (оверлей `RootView`);
  - повноекранне вікно «Склянка» й шторки головного;
  - звіт (`ReportScreen`);
  - історія «Знань» (`LearnStoryScreen`);
  - вікно «Шлях рівнів» (`LevelRoadModel`, до кінця розкриття скрині);
  - системний запит дозволу.

  Закінчення паузи викликає `presentCelebrations`.
- **Заміна `unlockAnnouncement`, `UnlockText`, `announceUnlocks()` і `announceUnlocks(keys:)`** на
  `presentCelebrations`. Місця виклику:
  - `AppServices.swift:132`, `:186`;
  - `AppServices+Achievements.swift` (`record`);
  - `LearnViewModel`, `LevelRoadModel`, `ReportViewModel`, `PrizeInventoryModel`.
- **Відкриття застосунку** (`services.activation`): якщо черга не порожня — `presentCelebrations(context:
  .whileAway)`. Порції з віджета, сповіщення й «Команд» і завершений учорашній день потрапляють сюди.

### 2.4 Головний

`HomeViewModel`.

- **`add` / `confirmCustom` / `apply`.** Відкрите дією — `services.presentCelebrations(context: .action, level:)` з
  рівнем дії. Тост — лише коли досягнень немає, у тому самому порядку, що й зараз: подарунок → рівень із призом →
  рівень → «Знову в ритмі».
  - Тост рівня й рядок рівня — лише для рівня, вищого за `UserProfile.highestCelebratedLevel` (нове поле). Рівень,
    знятий відкатом і досягнутий знову, удруге не святкується (побічна знахідка WAT-60).
- **Вібрація.** Вікно — `HomePulse.Kind.achievementUnlocked` → нове `WTFeedback.achievement`. Без вікна —
  `goalReached` > `levelUp` > `capped` > `added` (П2 аудиту).
- **`remove` і пропозиція графіка.** `queuedToast` для досягнень («Нерішучість») замінити паузою: вікно — після
  закриття тоста «Порцію видалено · Скасувати».
- **`permissionOfferPending`** чекає ще й закриття вікна.
- **`achievementDetail`, відкритий із тоста,** прибрати, якщо інших входів немає.

### 2.5 DesignSystem

- **`WTCelebration`** (`Components/Celebration.swift`) — за таблицею §8.2 ТЗ.
  - Тло — `LinearGradient(theme.ringEnd → theme.waterDeep)` і `WTStoryWaves(level: 1)`.
  - Безкінечні бульбашки — лише через `TimelineView` (`CLAUDE.md`, пастка з `repeatForever`).
  - Бульбашка-медаль із колами; розкриття таємного й пасхалки; рядок рівня; крапки сторінок.
  - Біла кнопка з текстом `waterDeep` і текстова «Пізніше».
  - Блокування дотику 0,5 с; Reduce Motion; `.isModal`.
  - Ідентифікатори — `SPEC-ACHIEVEMENTS` §10; на контейнер — жодного.
  - `#Preview` світла й темна.
- **`WTFeedback.achievement`** — семантична вібрація «успіх», відмінна від `.levelUp` і `.goalReached`.
- Нових кольорів немає.

### 2.6 RootView

- Оверлей вікна — над стеком і шторками, з найвищим `zIndex`. Під час онбордингу — пауза.
- Прибрати `unlockToast` (`WTToast` з `unlockAnnouncement`).

### 2.7 Тести

- **Features** (`HomeViewModel`, `AppServices`):
  - дія з досягненням — вікно, а не тост;
  - лише рівень — тост;
  - два досягнення + рівень із вибором — дві сторінки, головна кнопка веде на «Шлях рівнів»;
  - вибір «Темна» в налаштуваннях — вікно поверх налаштувань;
  - відкрите під час звіту — після його закриття;
  - відкриття застосунку з чергою — «Поки тебе не було»;
  - рівень після відкату не святкується вдруге.
- **Аудит.** Колектори `AttentionAuditWeek1Tests` перевести з тостів на вікна; бюджет «≤ 1 вікно на дію» — у
  `AchievementBudgetTests`.
- **e2e:**
  - Помічник `dismissCelebrationIfPresent(_:)`: тапати `celebration.primary`, поки вікно є. Замінити ним очікування
    «тост зник» (`SmokeUITests.swift:22`) і застосувати в усіх сценаріях, що додають першу порцію на
    `--uitest-empty`.
  - Новий `CelebrationUITests`:
    - перша порція — «Перша крапля»: `isHittable`, у межах вікна;
    - «Чудово» закриває, крапки на краплі рівня немає;
    - норма з рівнем 2 — рядок рівня;
    - `--widget-action add:…` — на відкритті вікно «Поки тебе не було».

    Годинник — `--uitest-now`: на справжньому таємні на удачу роблять тест нестабільним.
- **Перевірка:** `make test` повністю.

### 2.8 Документація й приймання

- **`CLAUDE.md`:**
  - «Досягнення» — вікно замість тоста, `celebratedAt`, `celebrationsSince`, паузи;
  - «Тести» — помічник e2e.
- **`PLAN.md` «Що з'ясувалося»:** відкат перевіряв увесь каталог — підняття порогу забирало б відкрите.
- **Ручне приймання в симуляторі:**
  - світла й темна тема, Reduce Motion, VoiceOver;
  - **контраст білого тексту на воді у світлій темі** — якщо мало, затемнити верх градієнта в межах наявних токенів
    і записати рішення в ТЗ.

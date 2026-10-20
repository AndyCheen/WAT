import XCTest
import SwiftData
import Core
import Persistence
import Hydration
import Notifications
@testable import Features

/// Онбординг (WAT-56, SPEC-ONBOARDING). «Сьогодні» — понеділок 19 жовтня 2026, 12:00 за Києвом.
@MainActor
final class OnboardingFeatureTests: XCTestCase {
    private var clock: FixedClock!
    private var center: InMemoryNotificationCenter!
    private var services: AppServices!
    private var exits: [OnboardingModel.Exit] = []

    private static let kyiv = TimeZone(identifier: "Europe/Kyiv")!

    override func setUp() async throws {
        try await super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.kyiv
        clock = FixedClock(now: calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))!)
        center = InMemoryNotificationCenter()
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock, notificationCenter: center)
        services.bootstrap()
        await services.notifications.refreshAuthorization()
        exits = []
    }

    private func model(_ mode: OnboardingMode) -> OnboardingModel {
        OnboardingModel(services: services, mode: mode) { [weak self] in self?.exits.append($0) }
    }

    private func go(_ model: OnboardingModel, to step: OnboardingStep) {
        while model.step != step { model.next() }
    }

    /// Профіль людини, що вже користується застосунком: чоловік, 34 роки, 78 кг, норма 2.5 л задана вручну.
    private func seedProfile() {
        let profile = services.profile
        profile.gender = .male
        profile.birthYear = 1992
        profile.weightKg = 78
        profile.activity = .medium
        profile.weekSchedule = WeekSchedule(weekday: DaySchedule(wakeMinutes: 7 * 60, sleepMinutes: 22 * 60 + 30),
                                            weekendEnabled: true, weekend: DaySchedule(wakeMinutes: 9 * 60, sleepMinutes: 23 * 60 + 30))
        profile.glassMl = 300
        services.profiles.save()
        services.hydration.setGoal(2500, source: .manual)
    }

    // MARK: - Каталог (§3, §9)

    func testCatalogStartsWithHelloEndsWithDoneAndUnitsComeFirst() {
        let steps = OnboardingCatalog.steps
        XCTAssertEqual(steps.first, .hello)
        XCTAssertEqual(steps.last, .done)
        XCTAssertEqual(OnboardingCatalog.questions.first, .units, "одиниці — до ваги, склянки й годин")
        XCTAssertEqual(OnboardingCatalog.questions.count, 10)
        XCTAssertEqual(Set(steps).count, steps.count, "крок — лише раз")
        for chapter in OnboardingChapter.allCases {
            XCTAssertFalse(OnboardingCatalog.steps(in: chapter).isEmpty, "\(chapter) без кроків")
        }
        // Норма — після всіх своїх вхідних даних.
        let goal = steps.firstIndex(of: .goal)!
        for input in [OnboardingStep.gender, .age, .weight, .activity] {
            XCTAssertLessThan(steps.firstIndex(of: input)!, goal)
        }
    }

    // MARK: - Перший запуск (§6, §8)

    func testOpensByItselfOnlyWithoutHistory() {
        XCTAssertTrue(services.shouldOpenOnboarding)
        services.hydration.addIntake(amountMl: 250)
        XCTAssertFalse(services.shouldOpenOnboarding, "хто вже пив, після оновлення онбординг сам не бачить")
    }

    func testTypicalAnswersSetDocumentedGoal() {
        let model = model(.firstRun)
        XCTAssertEqual(model.calculatedGoalMl, 2550, "70 кг, стать і вік не вказано, помірно — SPEC-ONBOARDING §5")
        go(model, to: .done)
        model.finish()

        XCTAssertEqual(services.hydration.currentGoal(), 2550)
        XCTAssertEqual(services.profiles.goalRevisions().first?.source, .calculated)
        XCTAssertEqual(services.profile.onboardingState, .completed)
        XCTAssertFalse(services.shouldOpenOnboarding)
        XCTAssertTrue(services.profile.glassConfirmed, "вікно «Склянка» вже не питає склянку")
        XCTAssertEqual(exits, [.home])
    }

    func testAdjustedGoalIsManual() {
        let model = model(.firstRun)
        go(model, to: .goal)
        model.stepGoal(1)
        model.stepGoal(1)
        XCTAssertEqual(model.goalMl, 2650)
        go(model, to: .done)
        model.finish(.learn)
        XCTAssertEqual(services.hydration.currentGoal(), 2650)
        XCTAssertEqual(services.profiles.goalRevisions().first?.source, .manual)
        XCTAssertEqual(exits, [.learn])
    }

    func testSkipOnHelloChangesNothing() {
        let model = model(.firstRun)
        model.skip()
        XCTAssertEqual(services.hydration.currentGoal(), 2000)
        XCTAssertNil(services.profile.weightKg)
        XCTAssertEqual(services.profile.onboardingState, .skipped)
        XCTAssertFalse(services.shouldOpenOnboarding, "пропущений онбординг сам більше не відкривається")
    }

    /// «Пропустити» посередині — «закінчити зараз»: лише підтверджені «Далі» кроки, і без кроку «Норма» норма не міняється.
    func testSkipMidwayKeepsOnlyConfirmedSteps() {
        let model = model(.firstRun)
        model.next()
        model.draft.answers.volumeUnit = .usFluidOunces
        model.next()
        model.draft.answers.gender = .female
        model.skip()

        XCTAssertEqual(services.profile.volumeUnit, .usFluidOunces)
        XCTAssertEqual(services.profile.gender, .unspecified, "стать не підтверджено «Далі»")
        XCTAssertEqual(services.hydration.currentGoal(), 2000, "числа, якого людина не бачила, не ставимо")
        XCTAssertEqual(services.profile.onboardingState, .skipped)
    }

    // MARK: - Норма

    func testConditionAddsToGoalOnlyForFemale() {
        let model = model(.firstRun)
        model.draft.answers.gender = .female
        model.draft.answers.age = 28
        model.draft.answers.weightKg = 60
        XCTAssertEqual(model.calculatedGoalMl, 2150)
        model.draft.answers.condition = .pregnancy
        XCTAssertEqual(model.calculatedGoalMl, 2450)
        model.draft.answers.condition = .breastfeeding
        XCTAssertEqual(model.calculatedGoalMl, 2850)
        model.draft.answers.gender = .male
        XCTAssertFalse(model.goalParts.contains { $0.id == "condition" }, "стан без статі «Жінка» не діє")
    }

    func testAdjustResetsWhenFormulaInputsChange() {
        let model = model(.firstRun)
        model.stepGoal(1)
        XCTAssertEqual(model.draft.goalAdjustMl, 50)
        model.draft.answers.glassMl = 300
        XCTAssertEqual(model.draft.goalAdjustMl, 50, "склянка формулу не чіпає")
        model.weightValue = 80
        XCTAssertEqual(model.draft.goalAdjustMl, 0, "+50 не переїжджає на нове число")
    }

    // MARK: - Повторний прохід (§7)

    func testRevisitPrefillsCurrentValues() {
        seedProfile()
        let model = model(.revisit)
        let answers = model.draft.answers
        XCTAssertEqual(answers.gender, .male)
        XCTAssertEqual(answers.age, 34)
        XCTAssertEqual(answers.weightKg, 78)
        XCTAssertEqual(answers.week.weekday.wakeMinutes, 7 * 60)
        XCTAssertTrue(answers.week.weekendEnabled)
        XCTAssertEqual(answers.glassMl, 300)
        XCTAssertTrue(model.isCurrent(\.gender, .male))
        XCTAssertFalse(model.isCurrent(\.gender, .female))
        XCTAssertEqual(model.mark(for: .weight), .current)
        XCTAssertTrue(model.changes.isEmpty)
    }

    func testRevisitKeepsManualGoalUnlessChosen() {
        seedProfile()
        let model = model(.revisit)
        XCTAssertEqual(model.calculatedGoalMl, 2950, "78 × 35 × 0.95 + 350")
        XCTAssertTrue(model.offersGoalChoice)
        XCTAssertEqual(model.draft.goalChoice, .keepCurrent, "ручну норму мовчки не переписуємо")
        XCTAssertEqual(model.goalMl, 2500)
        model.draft.goalChoice = .calculated
        XCTAssertEqual(model.goalMl, 2950)
        XCTAssertEqual(model.changes.map(\.id), ["goal"])
    }

    func testRevisitSavesOnlyAfterSaveAndListsChanges() {
        seedProfile()
        let model = model(.revisit)
        model.weightValue = 80
        XCTAssertEqual(model.mark(for: .weight), .was("78 кг"))
        XCTAssertEqual(model.changes.map(\.id), ["weight"])
        XCTAssertEqual(services.profile.weightKg, 78, "до «Зберегти» нічого не пишеться")

        go(model, to: .done)
        model.save()
        XCTAssertEqual(services.profile.weightKg, 80)
        XCTAssertEqual(services.hydration.currentGoal(), 2500, "норма лишилась ручною")
    }

    func testRevertReturnsCurrentValue() {
        seedProfile()
        let model = model(.revisit)
        model.weightValue = 90
        model.revert(.weight)
        XCTAssertEqual(model.draft.answers.weightKg, 78)
        model.stepTime(.wake, weekend: false, direction: 1)
        XCTAssertEqual(model.timeMark(.wake, weekend: false), .was("07:00"))
        model.revertTime(.wake, weekend: false)
        XCTAssertEqual(model.timeMark(.wake, weekend: false), .current)
        XCTAssertTrue(model.changes.isEmpty)
    }

    func testCloseWithChangesAsksAndWritesNothing() {
        seedProfile()
        let model = model(.revisit)
        model.draft.answers.glassMl = 400
        model.close()
        XCTAssertTrue(model.isConfirmingExit)
        XCTAssertTrue(exits.isEmpty)
        model.confirmExit()
        XCTAssertEqual(exits, [.home])
        XCTAssertEqual(services.profile.glassMl, 300)
    }

    func testCloseWithoutChangesLeavesAtOnce() {
        let model = model(.revisit)
        model.close()
        XCTAssertFalse(model.isConfirmingExit)
        XCTAssertEqual(exits, [.home])
    }

    /// «Просто норма» переводить нагадування «за темпом» на рівні інтервали — і це видно в переліку (§3.1).
    func testRhythmOffSwitchesPaceRemindersToIntervals() {
        let model = model(.revisit)
        model.draft.answers.dayRhythm = false
        XCTAssertTrue(model.changes.map(\.id).contains("reminderMode"))
        go(model, to: .done)
        model.save()
        XCTAssertFalse(services.profile.dayRhythmEnabled)
        XCTAssertEqual(services.notifications.settings.reminderMode, .interval)
    }

    /// Новий розклад — у запис сьогоднішнього дня, як і з екрана «Сповіщення» (WAT-39).
    func testScheduleChangeReachesTodaysLog() throws {
        services.hydration.addIntake(amountMl: 250)
        let model = model(.revisit)
        model.stepTime(.wake, weekend: false, direction: -4)
        go(model, to: .done)
        model.save()
        let log = try XCTUnwrap(services.dayLogs.existingDayLog(for: services.calendar.today))
        XCTAssertEqual(log.scheduleSnapshot?.wakeMinutes, 7 * 60)
    }

    // MARK: - Одиниці (§3.1)

    func testWeightFollowsMassUnit() {
        let model = model(.firstRun)
        model.draft.answers.massUnit = .pounds
        XCTAssertEqual(model.weightValue, 154)
        model.weightValue = 160
        XCTAssertEqual(model.draft.answers.weightKg, 72.57, accuracy: 0.01)
        XCTAssertEqual(OnboardingPresenter.weight(model.draft.answers.weightKg, .pounds), "160 фунтів")
        XCTAssertEqual(OnboardingPresenter.weight(Mass.kilograms(152, from: .pounds), .pounds), "152 фунти")
        XCTAssertEqual(OnboardingPresenter.volume(250, .usFluidOunces), "8 унц.")
        XCTAssertEqual(OnboardingPresenter.goal(2550, .milliliters), "2.55 л")
        XCTAssertEqual(OnboardingPresenter.goal(2500, .milliliters), "2.5 л")
    }

    func testUnitsAreSavedFromUnitsStep() {
        let model = model(.firstRun)
        model.draft.answers.volumeUnit = .usFluidOunces
        model.draft.answers.massUnit = .pounds
        model.draft.answers.timeFormat = .hours12
        go(model, to: .done)
        model.finish()
        XCTAssertEqual(services.profile.volumeUnit, .usFluidOunces)
        XCTAssertEqual(services.profile.massUnit, .pounds)
        XCTAssertEqual(services.profile.timeFormat, .hours12)
        // Через `HydrationService.setVolumeUnit` (WAT-58): типові кнопки стають типовими унцій, а не «7 унц.».
        XCTAssertEqual(services.hydration.quickAddAmounts(), PresetPlace.home.defaults(for: .usFluidOunces))
    }

    // MARK: - Нагадування (§3.1)

    func testNotNowPostponesThePermissionSheet() async {
        center = InMemoryNotificationCenter(status: .notDetermined)
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock, notificationCenter: center)
        services.bootstrap()
        await services.notifications.refreshAuthorization()
        let model = model(.firstRun)
        go(model, to: .reminders)
        XCTAssertEqual(model.reminders, .notAsked)
        model.postponeReminders()
        XCTAssertEqual(model.step, .done)
        XCTAssertFalse(services.notifications.shouldOfferPermission(at: clock.now), "шторка після першої порції — через 3 дні")
    }

    // MARK: - Тексти (SPEC-NOTIFICATIONS §14.1)

    func testCopyIsGenderNeutralAndHasDisclaimers() {
        let forbidden: Set<String> = ["пив", "пила", "випив", "випила", "готовий", "готова", "порахував", "порахувала",
                                      "вказав", "вказала", "пропустив", "пропустила", "сам", "сама", "радий", "рада"]
        var lines: [String] = []
        for mode in [OnboardingMode.firstRun, .revisit] {
            for step in OnboardingCatalog.steps {
                for reminders in [OnboardingReminders.notAsked, .granted, .denied] {
                    let header = OnboardingPresenter.header(step, mode: mode, offersGoalChoice: true, reminders: reminders)
                    lines += [header.title] + [header.subtitle].compactMap { $0 }
                }
            }
        }
        lines += [OnboardingPresenter.conditionDisclaimer, OnboardingPresenter.goalDisclaimer, OnboardingPresenter.exitMessage,
                  OnboardingPresenter.doneSubtitle, OnboardingPresenter.changesSubtitle, OnboardingPresenter.typicalHint]
        for line in lines {
            let words = Set(line.lowercased().split { !$0.isLetter }.map(String.init))
            XCTAssertTrue(words.isDisjoint(with: forbidden), "«\(line)»")
        }
        XCTAssertTrue(OnboardingPresenter.conditionDisclaimer.contains("не медична порада"))
        XCTAssertTrue(OnboardingPresenter.goalDisclaimer.contains("не є медичною порадою"))
    }
}

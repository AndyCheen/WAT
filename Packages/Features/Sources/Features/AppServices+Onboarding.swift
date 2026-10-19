import Foundation
import Core
import Persistence
import Hydration
import Notifications

/// Онбординг (WAT-56, SPEC-ONBOARDING): що зараз у застосунку й запис відповідей. Тут, а не в моделі екрана, бо
/// запис зачіпає `Hydration` (норма, знімок розкладу дня) і сповіщення — як `AppServices+Schedule`.
extension AppServices {

    /// Перший запуск: онбординг ще не показували, і в базі немає жодної порції (§8). Хто оновився з історією,
    /// сам його не бачить — вікно поверх звичного головного виглядало б як скидання.
    public var shouldOpenOnboarding: Bool {
        profile.onboardingState == .notShown && dayLogs.earliestDayKey() == nil
    }

    /// Поточні значення — «Зараз» на кроках повторного проходу й «було» на фініші (§7.2).
    func onboardingBaseline() -> OnboardingBaseline {
        let profile = self.profile
        let year = calendar.calendar.component(.year, from: calendar.now)
        var answers = OnboardingAnswers()
        answers.volumeUnit = profile.volumeUnit
        answers.massUnit = profile.massUnit
        answers.timeFormat = profile.timeFormat
        answers.gender = profile.gender
        answers.condition = profile.gender == .female ? profile.bodyCondition : .none
        answers.age = profile.birthYear.map { year - $0 }.flatMap { OnboardingAnswers.ageRange.contains($0) ? $0 : nil }
        answers.weightKg = profile.weightKg ?? OnboardingAnswers.typicalWeightKg
        answers.activity = profile.activity
        answers.week = profile.weekSchedule
        answers.dayRhythm = profile.dayRhythmEnabled
        answers.glassMl = profile.glassMl

        let today = calendar.today.rawValue
        let revision = profiles.goalRevisions().first { $0.effectiveFromKey <= today }
        return OnboardingBaseline(
            answers: answers, goalMl: hydration.currentGoal(),
            // Без ревізії норма — типова з `bootstrap()`, яка й пишеться з джерелом `.onboarding`.
            goalSource: revision?.source ?? .onboarding,
            weightKnown: profile.weightKg != nil, reminderMode: notifications.settings.reminderMode,
            currentYear: year, climate: profile.climate
        )
    }

    /// Стан дозволу для кроку «Нагадування». `postponed` — «Не зараз» уже натиснули в цьому проході.
    func onboardingReminders(postponed: Bool) -> OnboardingReminders {
        switch notifications.authorization {
        case .denied?: return .denied
        case .authorized?: return profile.notificationsEnabled ? .granted : .disabledInApp
        case .notDetermined?, nil: return postponed ? .postponed : .notAsked
        }
    }

    /// Записує відповіді одним проходом: одна дія користувача — один `touch()` (§7.4).
    ///
    /// `steps` — що записувати. На першому запуску «Пропустити» зберігає лише підтверджені «Далі» кроки (§6), тож
    /// незачеплені значення профілю лишаються типовими; у повторному проході — усе, бо незмінене пишеться саме в себе.
    func applyOnboarding(_ draft: OnboardingDraft, steps: Set<OnboardingStep>, goal: OnboardingGoal, state: OnboardingState) {
        let profile = self.profile
        let baseline = goal.baseline
        let answers = draft.answers

        if steps.contains(.units) {
            // Через `HydrationService`: він же переводить кнопки порцій на сітку нової системи (WAT-46).
            hydration.setVolumeUnit(answers.volumeUnit)
            profile.massUnit = answers.massUnit
            profile.timeFormat = answers.timeFormat
        }
        if steps.contains(.gender) {
            profile.gender = answers.gender
            profile.bodyCondition = answers.effectiveCondition
        }
        if steps.contains(.age) { profile.birthYear = answers.age.map { baseline.currentYear - $0 } }
        if steps.contains(.weight) { profile.weightKg = answers.weightKg }
        if steps.contains(.activity) { profile.activity = answers.activity }

        let scheduleChanged = steps.contains(.day) && answers.week != baseline.answers.week
        if steps.contains(.day) { profile.weekSchedule = answers.week }
        if steps.contains(.rhythm) {
            profile.dayRhythmEnabled = answers.dayRhythm
            if OnboardingChanges.switchesToIntervals(baseline: baseline, draft: draft) {
                notifications.settings.reminderMode = .interval
            }
        }
        if steps.contains(.glass) {
            profile.glassMl = answers.glassMl
            // Склянку задали тут — вікно «Склянка» вже не питатиме «скільки в твоїй склянці?» (§7.1).
            profile.glassConfirmed = true
        }
        profile.onboardingState = state
        profiles.save()

        // Норма — лише з пройденого кроку «Норма»: число, якого людина не бачила, не ставимо (§6). Типову
        // норму з `bootstrap()` замінює й розрахована, що випадково з нею збіглась, — тепер вона «розрахована».
        if steps.contains(.goal), draft.goalChoice == .calculated {
            let goalMl = goal.final(draft)
            if goalMl != baseline.goalMl || baseline.goalSource == .onboarding {
                hydration.setGoal(goalMl, source: draft.goalAdjustMl == 0 ? .calculated : .manual)
            }
        }
        // Розклад сьогодні — у запис дня, минулі дні лишаються зі своїми знімками (WAT-39).
        if scheduleChanged { hydration.scheduleDidChange() }
        // Головний і «Налаштування» перечитують себе: зміни прийшли не з їхнього екрана.
        epoch &+= 1
        touch()
    }

    /// «Пропустити» на вітанні — нічого не змінюється, але сам онбординг більше не відкривається (§6).
    func skipOnboarding() {
        profile.onboardingState = .skipped
        profiles.save()
    }
}

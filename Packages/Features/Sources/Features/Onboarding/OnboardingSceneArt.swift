import SwiftUI
import Core
import Persistence
import DesignSystem

/// Ілюстрація «Сцени» на кожен крок (SPEC-ONBOARDING §10): не прикраса, а те, що робить відповідь — «35 мл на
/// кожен кілограм», «×0.95», стрілка ваг, бонус активності, доба з підйомом і відбоєм, блоки ранку, дня й вечора.
/// Кольори — з «чорнила» тла розділу (`wtLearnInk`, задає `WTSceneLayout`).
struct OnboardingSceneArt: View {
    let model: OnboardingModel
    private typealias P = OnboardingPresenter

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, WTSpacing.screenSideHome)
            .id(model.step)
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    @ViewBuilder
    private var content: some View {
        let answers = model.draft.answers
        switch model.step {
        case .hello:
            WTLearnDrop(level: 0.62).frame(maxWidth: 210)
        case .units:
            WTSceneSample(rows: P.unitsSample(answers), caption: P.unitsSampleCaption)
        case .gender:
            VStack(spacing: 14) {
                WTSceneNumber(P.mlPerKg(answers), unit: "мл", caption: P.mlPerKgCaption, size: 64)
                if let badge = P.conditionBadge(answers.effectiveCondition, answers.volumeUnit) {
                    WTSceneBadge(badge)
                }
            }
            .animation(WTAnimation.sheet, value: answers.effectiveCondition)
        case .age:
            VStack(spacing: 22) {
                WTSceneNumber(P.ageCoefficient(answers.age), caption: P.ageCaption, size: 56)
                WTAgeScale(segments: Self.ageSegments(answers.age), marker: answers.age.map(Self.agePosition),
                           ticks: Self.ageTicks)
            }
        case .weight:
            let range = P.weightRange(answers.massUnit)
            let value = model.weightValue
            VStack(spacing: 10) {
                WTScaleDial(fraction: Double(value - range.lowerBound) / Double(max(1, range.upperBound - range.lowerBound)))
                    .frame(maxWidth: 160)
                WTSceneNumber("\(value)", unit: P.weightUnit(value, answers.massUnit), caption: P.weightFormula(answers), size: 52)
            }
        case .activity:
            VStack(spacing: 14) {
                WTLearnEmoji(P.activityOptions.first { $0.value == answers.activity }?.glyph ?? "🚶")
                    .frame(maxWidth: 150)
                    .id(answers.activity)
                WTSceneBadge(P.activityBonus(answers.activity, answers.volumeUnit))
            }
        case .goal:
            let parts = P.goalParts(model.goalMl, answers.volumeUnit)
            VStack(spacing: 8) {
                WTLearnDrop(level: min(0.94, max(0.3, Double(model.goalMl) / 4000))).frame(maxWidth: 104)
                WTSceneNumber(parts.number, unit: parts.unit, caption: P.goalCaption, size: 56,
                              badge: model.mode == .revisit && !model.offersGoalChoice ? P.nowBadge : nil)
                    .accessibilityIdentifier("onboarding.goal.value")
            }
        case .day:
            VStack(spacing: 18) {
                WTSceneNumber(P.range(answers.week.weekday, answers.timeFormat), size: 40)
                WTSceneDayTrack(rows: Self.dayRows(answers, blocks: false), axis: Self.dayAxis)
            }
        case .rhythm:
            let scene = P.rhythmScene(answers.dayRhythm, blocks: answers.week.weekday.curve(goalMl: model.goalMl).goalBlocks().count)
            VStack(spacing: 18) {
                WTSceneNumber(scene.title, caption: scene.caption, size: 48)
                WTSceneDayTrack(rows: Self.dayRows(answers, blocks: true), axis: Self.dayAxis)
            }
        case .glass:
            // Більша склянка — більша картинка: 200 мл і 400 мл мають відрізнятися з першого погляду.
            // Не `WTStoryGlass`: її пунктир — «норма дня» зі звіту, тут він нічого не означав би.
            WTGlassIllustration(fraction: 0.75)
                .frame(height: 120 + CGFloat(answers.glassMl - 200) * 0.45)
                .animation(WTAnimation.sheet, value: answers.glassMl)
        case .reminders:
            WTLockScreenPreview(time: P.lockTime, date: P.lockDate, appName: "WaterTracker", stamp: "зараз",
                                title: P.previewTitle, message: P.previewBody(answers), actions: P.previewActions(answers))
        case .done:
            if model.mode == .firstRun {
                WTLearnDrop(level: 0.86)
                    .frame(maxWidth: 130)
                    .overlay(alignment: .center) { WTSceneCheck().offset(y: 18) }
            } else {
                let count = model.changes.count
                WTSceneNumber("\(count)", caption: P.changesCount(count), size: 64)
            }
        }
    }

    // MARK: - Доба

    /// «0 · 6 · 12 · 18 · 24» — годинами, без формату: на осі 12-годинні «дп / пп» не вмістилися б.
    static let dayAxis = ["0", "6", "12", "18", "24"]

    /// Будні й, якщо ввімкнено, вихідні. `blocks` — блоки цілей ранку, дня й вечора з тієї самої моделі, що в
    /// чекпоінтах і XP (`PaceCurve.goalBlocks()`), а не вигадані межі.
    static func dayRows(_ answers: OnboardingAnswers, blocks: Bool) -> [WTSceneDayTrack.Row] {
        let week = answers.week
        func row(_ day: DaySchedule, label: String?) -> WTSceneDayTrack.Row {
            let full = Double(24 * 60)
            let parts = blocks && answers.dayRhythm
                ? day.curve(goalMl: 2000).goalBlocks().map {
                    // «ранок і полудень» у вузький блок не влазить — досить першого слова.
                    WTSceneDayTrack.Block(title: String($0.title.split(separator: " ").first ?? ""),
                                          start: Double($0.fromMinute) / full, end: Double($0.toMinute) / full)
                }
                : []
            return WTSceneDayTrack.Row(label: label, wake: Double(day.wakeMinutes) / full, sleep: Double(day.sleepMinutes) / full,
                                       blocks: parts, windowTitle: blocks ? "норма за день" : nil)
        }
        guard week.weekendEnabled else { return [row(week.weekday, label: nil)] }
        return [row(week.weekday, label: "Будні"), row(week.weekend, label: "Вихідні")]
    }

    // MARK: - Вік

    private static let ageRange = OnboardingAnswers.ageRange

    static func agePosition(_ age: Int) -> Double {
        Double(age - ageRange.lowerBound) / Double(ageRange.upperBound - ageRange.lowerBound)
    }

    static func ageSegments(_ age: Int?) -> [WTAgeScale.Segment] {
        P.ageSegments.map { segment in
            WTAgeScale.Segment(label: segment.label, span: segment.range.count,
                               isOn: age.map(segment.range.contains) ?? false)
        }
    }

    /// Межі коефіцієнтів під шкалою: 14, 30, 55, 99.
    static var ageTicks: [(label: String, position: Double)] {
        let bounds = [ageRange.lowerBound] + P.ageSegments.map(\.range.upperBound)
        return bounds.map { bound in
            let position = bound == ageRange.lowerBound ? 0.03 : bound == ageRange.upperBound ? 0.97 : agePosition(bound) + 0.006
            return ("\(bound)", position)
        }
    }
}

import Foundation
import Core
import Metrics
import Gamification
import Notifications

extension AppServices {
    /// Крапка «нове» на кнопці «Знань» у шапці головного (SPEC-LEARN §3.1): до першого відкриття розділу й
    /// потім лише для історій, яких бібліотека ще не показувала (прийшли з оновленням).
    public var hasLearnNews: Bool {
        !learn.hasVisited || LearnCatalog.stories.contains { learn.progress($0.id) == nil }
    }

    /// Історію дочитано (SPEC-LEARN §6, §7): прогрес, події на шину — один `commit` на дію. Тост досягнень
    /// показує екран після закриття: поверх фінішу він ліг би на «Готово», як у звіті.
    func finishLearnStory(_ story: LearnStory) {
        learn.complete(story.id, at: calendar.now)
        var keys: [MetricKey] = [.learnCompleted]
        if let shelfKey = story.shelf.completionMetric { keys.append(shelfKey) }
        for key in keys {
            // Ref від історії: перечитана історія лічильник не збільшує — лічильник = різні історії.
            metrics.record(MetricEvent(name: key, value: 1, occurredAt: calendar.now,
                                       sourceRef: DeterministicID.uuid(from: "\(key.rawValue):\(story.id)")))
        }
        metrics.commit()
    }

    /// Живі значення для текстів історій (SPEC-LEARN §5.4).
    func learnContext() -> LearnContext {
        let profile = self.profile
        let today = calendar.today
        let schedule = profile.schedule(isWeekend: calendar.isWeekend(today))
        let goal = profiles.currentGoalMl(on: today)
        let blocks = schedule.curve(goalMl: goal).goalBlocks().map { block in
            LearnContext.Block(title: block.parts.first?.title ?? "", deadlineMinute: block.toMinute, targetMl: block.targetMl)
        }
        return LearnContext(
            goalMl: goal,
            blocks: blocks,
            wakeMinutes: schedule.wakeMinutes,
            sleepMinutes: schedule.sleepMinutes,
            dayRhythmEnabled: profile.dayRhythmEnabled,
            level: gamification.levelProgress().level,
            rules: gamification.xp.rules,
            presets: hydration.quickAddAmounts(),
            dailyCap: NotificationRules().dailyCap
        )
    }
}

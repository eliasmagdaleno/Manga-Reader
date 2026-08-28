import Foundation
import Testing
@testable import Manga_Reader

@Suite("Update scheduler")
struct UpdateSchedulerTests {
    @MainActor
    @Test("Registration is idempotent")
    func registrationHappensOnce() {
        let fake = FakeBackgroundScheduler()
        let scheduler = makeScheduler(backgroundTasks: fake)
        #expect(scheduler.register())
        #expect(scheduler.register())
        #expect(fake.registrations.count == 1)
    }

    @MainActor
    @Test("Scheduling requests the centralized earliest begin date")
    func scheduleNextUsesTuning() throws {
        let fake = FakeBackgroundScheduler()
        let scheduler = makeScheduler(backgroundTasks: fake)
        let now = Date(timeIntervalSince1970: 100)
        scheduler.scheduleNext(from: now)
        let submission = try #require(fake.submissions.first)
        #expect(submission.identifier == UpdateScheduler.identifier)
        #expect(submission.date == now.addingTimeInterval(UpdateTuning.backgroundRequestInterval))
    }

    @MainActor
    @Test("Handling submits the next request before running")
    func handlingResubmitsFirst() async {
        let fake = FakeBackgroundScheduler()
        let task = FakeBGTask()
        var submissionsSeenByRun = 0
        let scheduler = makeScheduler(backgroundTasks: fake, run: { _ in
            submissionsSeenByRun = fake.submissions.count
            return []
        })
        await scheduler.handle(task).value
        #expect(submissionsSeenByRun == 1)
        #expect(task.completions == [true])
    }

    @MainActor
    @Test("Expiration cancels the run and completes exactly once")
    func expirationCancelsAndCompletes() async throws {
        let fake = FakeBackgroundScheduler()
        let backgroundTask = FakeBGTask()
        var observedCancellation = false
        let scheduler = makeScheduler(backgroundTasks: fake, run: { _ in
            while !Task.isCancelled { await Task.yield() }
            observedCancellation = true
            return []
        })
        let runTask = scheduler.handle(backgroundTask)
        let expire = try #require(backgroundTask.expirationHandler)
        expire()
        await runTask.value
        #expect(observedCancellation)
        #expect(backgroundTask.completions == [false])
    }

    @MainActor
    @Test("A run without events schedules no notification and still flushes")
    func emptyRunDoesNotNotify() async {
        let fake = FakeBackgroundScheduler()
        let backgroundTask = FakeBGTask()
        var notificationCalls = 0
        var flushCalls = 0
        let scheduler = UpdateScheduler(
            backgroundTasks: fake,
            runRefresh: { _ in [] },
            notify: { _ in notificationCalls += 1 },
            flushStores: { flushCalls += 1 }
        )
        await scheduler.handle(backgroundTask).value
        #expect(notificationCalls == 0)
        #expect(flushCalls == 1)
        #expect(backgroundTask.completions == [true])
    }

    @MainActor
    private func makeScheduler(
        backgroundTasks: FakeBackgroundScheduler,
        run: @escaping UpdateScheduler.RefreshRun = { _ in [] }
    ) -> UpdateScheduler {
        UpdateScheduler(backgroundTasks: backgroundTasks, runRefresh: run, notify: { _ in })
    }
}

@MainActor
private final class FakeBackgroundScheduler: BackgroundTaskScheduling {
    struct Submission: Equatable {
        let identifier: String
        let date: Date
    }
    var registrations: [String] = []
    var submissions: [Submission] = []
    var cancelled: [String] = []

    func register(identifier: String, handler: @escaping (BGTaskLike) -> Void) -> Bool {
        registrations.append(identifier)
        return true
    }
    func submit(identifier: String, earliestBeginDate: Date) throws {
        submissions.append(.init(identifier: identifier, date: earliestBeginDate))
    }
    func cancel(identifier: String) { cancelled.append(identifier) }
}

@MainActor
private final class FakeBGTask: BGTaskLike {
    var expirationHandler: (() -> Void)?
    var completions: [Bool] = []
    func setTaskCompleted(success: Bool) { completions.append(success) }
}

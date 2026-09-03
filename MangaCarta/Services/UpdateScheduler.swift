import BackgroundTasks
import Foundation

@MainActor
protocol BGTaskLike: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

/// A main-actor box around `BGTask`. Conforming `BGTask` directly would need an
/// isolated conformance (`extension BGTask: @MainActor BGTaskLike`), which is
/// Swift 6.2 syntax that CI's Xcode 16 toolchain rejects. The box is created
/// inside `MainActor.assumeIsolated`, where the task is already ours to touch.
@MainActor
final class BGTaskBox: BGTaskLike {
    private let task: BGTask

    init(_ task: BGTask) { self.task = task }

    var expirationHandler: (() -> Void)? {
        get { task.expirationHandler }
        set { task.expirationHandler = newValue }
    }

    func setTaskCompleted(success: Bool) { task.setTaskCompleted(success: success) }
}

@MainActor
protocol BackgroundTaskScheduling {
    func register(identifier: String, handler: @escaping (BGTaskLike) -> Void) -> Bool
    func submit(identifier: String, earliestBeginDate: Date) throws
    func cancel(identifier: String)
}

struct BGTaskSchedulerAdapter: BackgroundTaskScheduling {
    private let scheduler: BGTaskScheduler

    init(scheduler: BGTaskScheduler = .shared) { self.scheduler = scheduler }

    func register(identifier: String, handler: @escaping (BGTaskLike) -> Void) -> Bool {
        scheduler.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { handler(BGTaskBox(task)) }
        }
    }

    func submit(identifier: String, earliestBeginDate: Date) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try scheduler.submit(request)
    }

    func cancel(identifier: String) {
        scheduler.cancel(taskRequestWithIdentifier: identifier)
    }
}

@MainActor
final class UpdateScheduler {
    static let identifier = "Elias-Magdaleno.Manga-Reader.libraryRefresh"
    typealias RefreshRun = (RefreshBudget) async -> [UpdateEvent]
    typealias Notify = ([UpdateEvent]) async -> Void

    private let backgroundTasks: BackgroundTaskScheduling
    private let runRefresh: RefreshRun
    private let notify: Notify
    private let flushStores: () -> Void
    private let now: () -> Date
    private var isRegistered = false

    init(backgroundTasks: BackgroundTaskScheduling? = nil,
         coordinator: LibraryRefreshCoordinator,
         notifier: UpdateNotifier,
         flushStores: @escaping () -> Void,
         now: @escaping () -> Date = Date.init) {
        self.backgroundTasks = backgroundTasks ?? BGTaskSchedulerAdapter()
        runRefresh = { await coordinator.run(budget: $0) }
        notify = { await notifier.schedule($0) }
        self.flushStores = flushStores
        self.now = now
    }

    init(backgroundTasks: BackgroundTaskScheduling,
         runRefresh: @escaping RefreshRun,
         notify: @escaping Notify,
         flushStores: @escaping () -> Void = {},
         now: @escaping () -> Date = Date.init) {
        self.backgroundTasks = backgroundTasks
        self.runRefresh = runRefresh
        self.notify = notify
        self.flushStores = flushStores
        self.now = now
    }

    @discardableResult
    func register() -> Bool {
        guard !isRegistered else { return true }
        let registered = backgroundTasks.register(identifier: Self.identifier) { [weak self] task in
            _ = self?.handle(task)
        }
        isRegistered = registered
        return registered
    }

    func scheduleNext(from date: Date) {
        // This is a no-earlier-than request to iOS, not a promised schedule.
        try? backgroundTasks.submit(
            identifier: Self.identifier,
            earliestBeginDate: date.addingTimeInterval(UpdateTuning.backgroundRequestInterval)
        )
    }

    @discardableResult
    func handle(_ backgroundTask: BGTaskLike) -> Task<Void, Never> {
        scheduleNext(from: now())
        let deadline = now().addingTimeInterval(UpdateTuning.backgroundRunDeadline)
        let runTask = Task { @MainActor [runRefresh, notify, flushStores] in
            let events = await runRefresh(.background(
                deadline: deadline,
                maxWorks: UpdateTuning.backgroundMaxWorks
            ))
            let succeeded = !Task.isCancelled
            if !events.isEmpty { await notify(events) }
            flushStores()
            backgroundTask.setTaskCompleted(success: succeeded)
        }
        backgroundTask.expirationHandler = { runTask.cancel() }
        return runTask
    }
}

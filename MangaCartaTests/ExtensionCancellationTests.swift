//
//  ExtensionCancellationTests.swift
//  MangaCartaTests
//
//  Acceptance criterion 7: "cancellation prevents every late callback from changing
//  invocation state."
//
//  The design's "Scheduling, budgets, and cancellation" section spells out what
//  cancellation must do: no new host-capability call is accepted, queued calls are
//  removed, active work is cancelled, and eventual JavaScript or WebKit callbacks are
//  *discarded*. "Discarded" is the testable word, so every test here builds the
//  adversarial case — an Extension whose callback fires after cancellation — and
//  asserts that firing it changes nothing. A test showing only that cancellation
//  returns promptly would demonstrate none of this.
//

import Foundation
import JavaScriptCore
import XCTest
@testable import MangaCarta

final class ExtensionCancellationTests: XCTestCase {

    /// Cancelling before the invocation starts must run no Extension code at all.
    func testCancellationBeforeInvocationRunsNoScript() async {
        let token = ExtensionCancellationToken()
        token.cancel()
        let runtime = makeRuntime(script: deferringEngine)
        let error = await invocationError(runtime, cancellation: token)
        XCTAssertEqual(error?.code, .cancelled)
        XCTAssertFalse(runtime.didEvaluateBundle)
    }

    func testCancellationSettlesTheInvocationAsCancelled() async throws {
        let capability = DeferringHostCapability()
        let token = ExtensionCancellationToken()
        let runtime = makeRuntime(script: deferringEngine, capabilities: [capability])

        async let outcome = invocationError(runtime, cancellation: token)
        try await capability.waitForPendingCall()
        token.cancel()

        let error = await outcome
        XCTAssertEqual(error?.code, .cancelled)
    }

    /// The criterion, stated directly. The engine parked a resolver; firing it after
    /// cancellation must not turn a cancelled invocation into a successful one.
    func testLateResolutionAfterCancellationCannotChangeTheResult() async throws {
        let capability = DeferringHostCapability()
        let token = ExtensionCancellationToken()
        let runtime = makeRuntime(script: deferringEngine, capabilities: [capability])

        async let outcome = invocationError(runtime, cancellation: token)
        try await capability.waitForPendingCall()
        token.cancel()

        // The site answers a moment too late, inside the grace period.
        let delivered = capability.fire(with: ["items": []])
        XCTAssertFalse(delivered, "a callback after cancellation must be discarded")
        let error = await outcome
        XCTAssertEqual(error?.code, .cancelled)
    }

    /// "no new host-capability call is accepted"
    func testHostCapabilityCallsAreRefusedAfterCancellation() async throws {
        let capability = DeferringHostCapability()
        let token = ExtensionCancellationToken()
        let runtime = makeRuntime(script: deferringEngine, capabilities: [capability])

        async let outcome = invocationError(runtime, cancellation: token)
        try await capability.waitForPendingCall()
        token.cancel()
        _ = await outcome

        XCTAssertNil(capability.admitCallDirectly(),
                     "a host call started after cancellation must not be admitted")
        XCTAssertEqual(capability.refusedAdmissions, 1)
    }

    /// "queued calls are removed, active URLSession work is cancelled" — the seam an
    /// in-flight capability uses to hear about it.
    func testInFlightHostCallsAreToldToCancelExactlyOnce() async throws {
        let capability = DeferringHostCapability()
        let token = ExtensionCancellationToken()
        let runtime = makeRuntime(script: deferringEngine, capabilities: [capability])

        async let outcome = invocationError(runtime, cancellation: token)
        try await capability.waitForPendingCall()
        XCTAssertEqual(capability.cancelledCallCount, 0)
        token.cancel()
        _ = await outcome

        XCTAssertEqual(capability.cancelledCallCount, 1)
        token.cancel()
        XCTAssertEqual(capability.cancelledCallCount, 1)
    }

    /// The engine can see its own signal flip, which is how a cooperative Extension
    /// stops early rather than being torn down.
    func testTheEngineObservesItsSignalAborting() async throws {
        let capability = DeferringHostCapability()
        let token = ExtensionCancellationToken()
        let runtime = makeRuntime(script: """
            registerEngine("madara", { invoke: function (operation, request, context) {
              globalThis.__before = context.signal.aborted;
              return new Promise(function (resolve) {
                context.host.probe.defer(function () {
                  resolve({ ok: true, value: { aborted: context.signal.aborted } });
                });
              });
            } });
        """, capabilities: [capability])

        async let outcome = invocationError(runtime, cancellation: token)
        try await capability.waitForPendingCall()
        XCTAssertEqual(capability.readSignalAborted(), false)
        token.cancel()
        _ = await outcome
        XCTAssertEqual(capability.readSignalAborted(), true)
    }

    /// "The runtime waits a short host-defined grace period, then destroys an
    /// uncooperative JavaScript context." Destruction is observable as the context
    /// going away once the host stops holding it.
    func testAnUncooperativeContextIsDestroyedAfterTheGracePeriod() async throws {
        let capability = DeferringHostCapability(retainsJavaScript: false)
        let token = ExtensionCancellationToken()
        let runtime = makeRuntime(script: deferringEngine,
                                  capabilities: [capability],
                                  gracePeriod: 0.05)

        async let outcome = invocationError(runtime, cancellation: token)
        try await capability.waitForPendingCall()
        token.cancel()
        _ = await outcome

        XCTAssertNotNil(runtime.activeContext, "the context survives the grace period")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(runtime.activeContext, "the context is released after the grace period")
        XCTAssertNil(capability.admitCallDirectly())
    }

    /// Swift's own cancellation reaches the invocation without a separate token.
    func testStructuredTaskCancellationCancelsTheInvocation() async throws {
        let capability = DeferringHostCapability()
        let runtime = makeRuntime(script: deferringEngine, capabilities: [capability])

        let task = Task { () -> ExtensionInvocationError? in
            do {
                _ = try await runtime.invoke(.search, request: [:])
                return nil
            } catch let error as ExtensionInvocationError {
                return error
            } catch {
                return nil
            }
        }
        try await capability.waitForPendingCall()
        task.cancel()
        let error = await task.value
        XCTAssertEqual(error?.code, .cancelled)
        XCTAssertFalse(capability.fire(with: ["items": []]))
    }

    /// Cancelling one invocation does not disturb another that is still running.
    func testCancellationIsScopedToOneInvocation() async throws {
        let first = DeferringHostCapability()
        let second = DeferringHostCapability()
        let firstToken = ExtensionCancellationToken()
        let firstRuntime = makeRuntime(script: deferringEngine, capabilities: [first])
        let secondRuntime = makeRuntime(script: deferringEngine, capabilities: [second])

        async let firstOutcome = invocationError(firstRuntime, cancellation: firstToken)
        async let secondValue: Any? = try? await secondRuntime.invoke(
            .search, request: [:], cancellation: ExtensionCancellationToken())

        try await first.waitForPendingCall()
        try await second.waitForPendingCall()
        firstToken.cancel()
        let firstError = await firstOutcome
        XCTAssertEqual(firstError?.code, .cancelled)

        XCTAssertTrue(second.fire(with: ["items": []]))
        let resolved = await secondValue
        let object = try XCTUnwrap(resolved as? [String: Any])
        XCTAssertNotNil(object["items"])
    }

    // MARK: - Helpers

    /// An engine that parks a resolver behind a host capability and never settles on
    /// its own — the shape §5 describes as uncooperative.
    private let deferringEngine = """
        registerEngine("madara", { invoke: function (operation, request, context) {
          return new Promise(function (resolve) {
            context.host.probe.defer(function (value) {
              resolve({ ok: true, value: value });
            });
          });
        } });
    """

    private func invocationError(
        _ runtime: ExtensionRuntime,
        cancellation: ExtensionCancellationToken
    ) async -> ExtensionInvocationError? {
        do {
            let value = try await runtime.invoke(.search, request: [:], cancellation: cancellation)
            XCTFail("expected a failure, got \(value)")
            return nil
        } catch let error as ExtensionInvocationError {
            return error
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
    }

    private func makeRuntime(script: String,
                             capabilities: [ExtensionHostCapability] = [],
                             gracePeriod: TimeInterval = 0.2) -> ExtensionRuntime {
        ExtensionRuntime(bundleScript: script,
                         declaration: ExtensionRuntimeFixtures.declaration(),
                         capabilities: capabilities,
                         cancellationGracePeriod: gracePeriod)
    }
}

/// Stands in for S5's asynchronous capabilities: it admits a host call, parks the
/// JavaScript callback, and lets a test fire it whenever it likes — including after
/// cancellation, which is the whole point.
final class DeferringHostCapability: ExtensionHostCapability {

    let hostName = "probe"

    private let lock = NSLock()
    private var scope: ExtensionInvocationScope?
    private var call: ExtensionHostCall?
    private var callback: JSValue?
    private var isPending = false
    private var cancelled = 0
    private var refused = 0
    private let retainsJavaScript: Bool

    init(retainsJavaScript: Bool = true) {
        self.retainsJavaScript = retainsJavaScript
    }

    var cancelledCallCount: Int { lock.withLock { cancelled } }
    var refusedAdmissions: Int { lock.withLock { refused } }

    func makeHostValue(in context: JSContext, scope: ExtensionInvocationScope) -> JSValue? {
        lock.withLock { self.scope = scope }
        guard let object = JSValue(newObjectIn: context) else { return nil }
        let park: @convention(block) (JSValue) -> Void = { [weak self] callback in
            self?.park(callback)
        }
        object.setObject(park, forKeyedSubscript: "defer" as NSString)
        return object
    }

    private func park(_ callback: JSValue) {
        guard let scope = lock.withLock({ scope }) else { return }
        guard let call = scope.admitHostCall(onCancel: { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.cancelled += 1 }
        }) else {
            lock.withLock { refused += 1 }
            return
        }
        lock.lock()
        self.call = call
        self.callback = retainsJavaScript ? callback : nil
        isPending = true
        lock.unlock()
    }

    /// Waits until the engine has parked a callback, so a test never cancels before
    /// there is anything to be late. Polled rather than continuation-based: a missed
    /// signal here would hang the whole bundle instead of failing one test.
    func waitForPendingCall(timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.withLock({ isPending }) { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        struct Timeout: Error {}
        throw Timeout()
    }

    /// Fires the parked JavaScript callback. Returns whether the runtime accepted it.
    @discardableResult
    func fire(with value: [String: Any]) -> Bool {
        let (call, callback) = lock.withLock { (self.call, self.callback) }
        guard let call, let callback else { return false }
        return call.deliver { context in
            guard let argument = JSValue(object: value, in: context) else { return }
            callback.call(withArguments: [argument])
        }
    }

    /// Asks for admission the way a capability would when the engine calls it again.
    func admitCallDirectly() -> ExtensionHostCall? {
        guard let scope = lock.withLock({ scope }) else { return nil }
        let call = scope.admitHostCall(onCancel: nil)
        if call == nil { lock.withLock { refused += 1 } }
        return call
    }

    /// Reads `context.signal.aborted` from inside the invocation's own context.
    func readSignalAborted() -> Bool? {
        guard let scope = lock.withLock({ scope }) else { return nil }
        return scope.readsSignalAbortedForTesting()
    }
}

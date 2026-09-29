//
//  RegressionTests.swift
//  Ice
//

import Cocoa
import Combine

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw CheckFailure(description: message)
    }
}

private final class EventSubscriber: Subscriber {
    typealias Input = NSEvent
    typealias Failure = Never

    var subscription: (any Subscription)?
    var receivedCount = 0
    var additionalDemand = Subscribers.Demand.none
    var onEvent: (() -> Void)?

    func receive(subscription: any Subscription) {
        self.subscription = subscription
    }

    func receive(_ input: NSEvent) -> Subscribers.Demand {
        receivedCount += 1
        onEvent?()
        return additionalDemand
    }

    func receive(completion: Subscribers.Completion<Never>) { }
}

private actor OperationProbe {
    var started = false
    var cancelled = false

    func run() async throws {
        started = true
        do {
            try await Task.sleep(for: .seconds(60))
        } catch is CancellationError {
            cancelled = true
            throw CancellationError()
        }
    }
}

@MainActor
private final class Suspension {
    private var continuation: CheckedContinuation<Void, Never>?

    var isWaiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@main
private enum RegressionTests {
    @MainActor
    static func main() async {
        // A failed cancellation regression must fail the script, rather than hang it.
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
            fputs("FAIL: regression checks timed out\n", stderr)
            exit(1)
        }
        NSApplication.shared.setActivationPolicy(.accessory)

        let tests: [(String, @MainActor () async throws -> Void)] = [
            ("mouse reads preserve queued tracking events", mouseQueue),
            ("mouse wait responds to cancellation", mouseCancellation),
            ("local publisher respects demand", localDemand),
            ("universal publisher respects demand", universalDemand),
            ("cancel during delivery prevents later callbacks", cancelDuringDelivery),
            ("all event subscriptions release their subscriber on cancel", subscriptionLifetime),
            ("successful timeout operation returns without waiting for timer", timeoutSuccess),
            ("operation errors propagate", operationFailure),
            ("timeout cancels its operation", timeoutCancellation),
            ("parent cancellation reaches timeout operation", parentCancellation),
            ("queued gestures include their cache and layout commit", serialTransactions),
            ("cancelled queued gesture never sends events", queuedCancellation),
            ("failed gesture releases the queue", serialFailure),
            ("active cancellation releases the queue", activeQueueCancellation),
            ("rapid gestures never overlap across suspension points", rapidSerialOperations),
        ]

        var failures = 0
        for (name, test) in tests {
            do {
                try await test()
                print("PASS: \(name)")
            } catch {
                failures += 1
                fputs("FAIL: \(name): \(error)\n", stderr)
            }
        }
        print("\(tests.count - failures)/\(tests.count) regression checks passed")
        exit(failures == 0 ? 0 : 1)
    }

    @MainActor
    private static func serialTransactions() async throws {
        let queue = AsyncSerialQueue()
        let suspension = Suspension()
        var trace = [String]()
        let first = Task {
            try await queue.run {
                trace.append("down-1")
                await suspension.wait()
                trace.append("up-1")
                await Task.yield()
                trace.append("cache-1")
                await Task.yield()
                trace.append("save-1")
            }
        }
        while !suspension.isWaiting { await Task.yield() }
        var submitted = false
        let second = Task {
            submitted = true
            try await queue.run { trace.append("down-2") }
        }
        while !submitted { await Task.yield() }
        await Task.yield()
        let beforeRelease = trace
        suspension.resume()
        try await first.value
        try await second.value
        try check(beforeRelease == ["down-1"], "A second gesture entered while the first was suspended")
        try check(trace == ["down-1", "up-1", "cache-1", "save-1", "down-2"], "A gesture interrupted the layout commit")
        try check(!queue.isRunning, "Queue stayed active after its last operation")
    }

    @MainActor
    private static func queuedCancellation() async throws {
        let queue = AsyncSerialQueue()
        let suspension = Suspension()
        let first = Task { try await queue.run { await suspension.wait() } }
        while !suspension.isWaiting { await Task.yield() }
        var submitted = false
        var sentEvent = false
        let cancelled = Task {
            submitted = true
            try await queue.run { sentEvent = true }
        }
        while !submitted { await Task.yield() }
        cancelled.cancel()
        do {
            try await cancelled.value
            throw CheckFailure(description: "Cancelled waiter completed successfully")
        } catch is CancellationError { }
        try check(!sentEvent, "A cancelled waiter sent an event")
        let next = Task { try await queue.run { 42 } }
        suspension.resume()
        try await first.value
        let result = try await next.value
        try check(result == 42 && !queue.isRunning, "Cancelled waiter blocked the following gesture")
    }

    @MainActor
    private static func serialFailure() async throws {
        struct ExpectedError: Error { }
        let queue = AsyncSerialQueue()
        do {
            try await queue.run { throw ExpectedError() }
            throw CheckFailure(description: "Operation error was lost")
        } catch is ExpectedError { }
        let result = try await queue.run { 7 }
        try check(result == 7 && !queue.isRunning, "Failure did not release the queue")
    }

    @MainActor
    private static func activeQueueCancellation() async throws {
        let queue = AsyncSerialQueue()
        var started = false
        let first = Task {
            try await queue.run {
                started = true
                try await Task.sleep(for: .seconds(60))
            }
        }
        while !started { await Task.yield() }
        let second = Task { try await queue.run { 9 } }
        first.cancel()
        do {
            try await first.value
            throw CheckFailure(description: "Active cancellation was lost")
        } catch is CancellationError { }
        let result = try await second.value
        try check(result == 9 && !queue.isRunning, "Active cancellation did not admit the next gesture")
    }

    @MainActor
    private static func rapidSerialOperations() async throws {
        let queue = AsyncSerialQueue()
        var active = 0
        var peak = 0
        var completed = 0
        let tasks = (0..<25).map { _ in
            Task {
                try await queue.run {
                    active += 1
                    peak = max(peak, active)
                    for _ in 0..<3 { await Task.yield() }
                    active -= 1
                    completed += 1
                }
            }
        }
        for task in tasks { try await task.value }
        try check(peak == 1 && completed == 25 && active == 0, "Rapid gestures interleaved or were dropped")
    }

    @MainActor
    private static func mouseEvent(_ type: NSEvent.EventType = .leftMouseUp) throws -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 31415,
            clickCount: 1,
            pressure: 0
        ) else {
            throw CheckFailure(description: "Could not create local test event")
        }
        return event
    }

    @MainActor
    private static func mouseQueue() throws {
        let app = NSApplication.shared
        let mask: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp]
        app.postEvent(try mouseEvent(.leftMouseUp), atStart: false)
        app.postEvent(try mouseEvent(.rightMouseUp), atStart: false)
        for _ in 0..<3 {
            _ = MouseState.isAnyButtonPressed
            _ = MouseState.secondsSinceLastMovement
            CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString), 0.01, false)
        }
        let first = app.nextEvent(matching: mask, until: .distantPast, inMode: .default, dequeue: true)
        let second = app.nextEvent(matching: mask, until: .distantPast, inMode: .default, dequeue: true)
        let extra = app.nextEvent(matching: mask, until: .distantPast, inMode: .default, dequeue: true)
        try check(
            first?.type == .leftMouseUp && second?.type == .rightMouseUp && extra == nil,
            "Mouse state reads consumed, duplicated, or reordered the queued mouse-up events"
        )
    }

    private static func mouseCancellation() async throws {
        let task = Task {
            try await MouseState.waitUntilStationary(for: 1_000_000_000)
        }
        task.cancel()
        do {
            try await task.value
            throw CheckFailure(description: "Cancelled mouse wait returned successfully")
        } catch is CancellationError { }
    }

    @MainActor
    private static func checkDemand<P: Publisher>(_ publisher: P) throws where P.Output == NSEvent, P.Failure == Never {
        let subscriber = EventSubscriber()
        publisher.subscribe(subscriber)
        defer { subscriber.subscription?.cancel() }
        let app = NSApplication.shared
        app.sendEvent(try mouseEvent())
        try check(subscriber.receivedCount == 0, "Delivered an event before demand was requested")
        subscriber.subscription?.request(.max(1))
        app.sendEvent(try mouseEvent())
        app.sendEvent(try mouseEvent())
        try check(subscriber.receivedCount == 1, "Delivered more than the requested demand")
        subscriber.additionalDemand = .max(1)
        subscriber.subscription?.request(.max(1))
        app.sendEvent(try mouseEvent())
        app.sendEvent(try mouseEvent())
        try check(subscriber.receivedCount == 3, "Demand returned by the subscriber was ignored")
    }

    @MainActor
    private static func localDemand() async throws {
        try checkDemand(LocalEventMonitor.publisher(for: .leftMouseUp))
    }

    @MainActor
    private static func universalDemand() async throws {
        try checkDemand(UniversalEventMonitor.publisher(for: .leftMouseUp))
    }

    @MainActor
    private static func cancelDuringDelivery() async throws {
        let subscriber = EventSubscriber()
        LocalEventMonitor.publisher(for: .leftMouseUp).subscribe(subscriber)
        subscriber.onEvent = { [weak subscriber] in subscriber?.subscription?.cancel() }
        subscriber.additionalDemand = .unlimited
        subscriber.subscription?.request(.max(1))
        NSApplication.shared.sendEvent(try mouseEvent())
        subscriber.subscription?.request(.unlimited)
        NSApplication.shared.sendEvent(try mouseEvent())
        try check(subscriber.receivedCount == 1, "Cancellation did not stop delivery")
    }

    @MainActor
    private static func subscriptionLifetime() async throws {
        let publishers = [
            LocalEventMonitor.publisher(for: .leftMouseUp).eraseToAnyPublisher(),
            GlobalEventMonitor.publisher(for: .leftMouseUp).eraseToAnyPublisher(),
            UniversalEventMonitor.publisher(for: .leftMouseUp).eraseToAnyPublisher(),
        ]
        for publisher in publishers {
            weak var weakSubscriber: EventSubscriber?
            let subscription: (any Subscription)? = {
                let subscriber = EventSubscriber()
                weakSubscriber = subscriber
                publisher.subscribe(subscriber)
                let subscription = subscriber.subscription
                subscription?.request(.unlimited)
                subscription?.cancel()
                return subscription
            }()
            try withExtendedLifetime(subscription) {
                try check(weakSubscriber == nil, "Cancelled subscription still retains its subscriber")
            }
        }
    }

    private static func timeoutSuccess() async throws {
        let value = try await Task<Int, Error>.withTimeout(.seconds(60)) { 42 }
        try check(value == 42, "Operation result was lost")
    }

    private static func operationFailure() async throws {
        do {
            _ = try await Task<Int, Error>.withTimeout(.seconds(60)) {
                throw CheckFailure(description: "expected")
            }
            throw CheckFailure(description: "Operation error was swallowed")
        } catch let error as CheckFailure {
            try check(error.description == "expected", "Wrong error propagated")
        }
    }

    private static func timeoutCancellation() async throws {
        let probe = OperationProbe()
        do {
            try await Task<Void, Error>.withTimeout(.milliseconds(30)) {
                try await probe.run()
            }
            throw CheckFailure(description: "Timeout did not fire")
        } catch is TaskTimeoutError { }
        try check(await probe.cancelled, "Timed-out operation was not cancelled")
    }

    private static func parentCancellation() async throws {
        let probe = OperationProbe()
        let task = Task {
            try await Task<Void, Error>.withTimeout(.seconds(60)) {
                try await probe.run()
            }
        }
        while await !probe.started {
            await Task.yield()
        }
        task.cancel()
        do {
            try await task.value
            throw CheckFailure(description: "Cancelled operation returned successfully")
        } catch is CancellationError { }
        try check(await probe.cancelled, "Parent cancellation did not reach the operation")
    }
}

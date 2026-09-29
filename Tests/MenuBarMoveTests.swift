//
//  MenuBarMoveTests.swift
//  Ice
//

import Cocoa

// The runner inserts the actual manager methods at the marker below. Only the
// WindowServer/event boundary is simulated; no input is sent to other processes.
private struct MenuBarItem {
    let windowID: Int
    let isMovable = true
    let ownerPID = getpid()
    var logString: String { "item-\(windowID)" }
}

private enum EventTap {
    enum Location {
        case pid(pid_t)
        case sessionEventTap
    }
}

private enum MoveEventType {
    case move(CGEventType)
}

private extension CGEvent {
    static func menuBarItemEvent(type: MoveEventType, location: CGPoint, item: MenuBarItem, pid: pid_t, source: CGEventSource) -> CGEvent? {
        switch type {
        case .move(let eventType):
            return CGEvent(mouseEventSource: source, mouseType: eventType, mouseCursorPosition: location, mouseButton: .left)
        }
    }
}

private struct Logger {
    static let itemManager = Logger()
    func debug(_ message: String) { }
    func info(_ message: String) { }
    func warning(_ message: String) { }
    func error(_ message: String) { }
}

private enum MouseCursor {
    static let locationCoreGraphics: CGPoint? = .zero
    static func hide() { }
    static func show() { }
    static func warp(to point: CGPoint) { }
}

private struct MockAppState {
    struct EventManager {
        func stopAll() { }
        func startAll() { }
    }
    let eventManager = EventManager()
}

@MainActor
private final class MoveHarness {
    enum MoveDestination {
        case leftOfItem(MenuBarItem)
        case rightOfItem(MenuBarItem)
        var logString: String { "test destination" }
    }

    struct EventError: Error {
        enum Code {
            case notMovable, invalidEventSource, eventCreationFailure, invalidItem
            case couldNotComplete, invalidAppState, invalidCursorLocation, otherTimeout
        }
        let code: Code
        let item: MenuBarItem
    }

    let item = MenuBarItem(windowID: 110)
    let target = MenuBarItem(windowID: 16309)
    var frames: [Int: CGRect] = [
        110: CGRect(x: -4100, y: 0, width: 28, height: 33),
        16309: CGRect(x: 1123, y: 0, width: 23, height: 33),
    ]
    var appState: MockAppState? = MockAppState()
    var itemMoveCount = 0
    var lastItemMoveStartDate: Date?
    var releases = [CGPoint]()
    var fallbackCount = 0
    var wakeCount = 0
    var onMouseDown: () -> Void = { }
    var onMouseUp: (CGPoint) -> Void = { _ in }

    func getCurrentFrame(for item: MenuBarItem) -> CGRect? { frames[item.windowID] }
    func waitForNoModifiersPressed() async throws { }
    func waitForMouseToStopMoving() async throws { }
    func wakeUpItem(_ item: MenuBarItem) async throws { wakeCount += 1 }
    func permitAllEvents(for state: CGEventSourceStateID, during states: [CGEventSuppressionState], suppressionInterval: TimeInterval, item: MenuBarItem) throws { }

    func scrombleEvent(_ event: CGEvent, from first: EventTap.Location, to second: EventTap.Location, waitingForFrameChangeOf item: MenuBarItem) async throws {
        if event.type == .leftMouseDown {
            onMouseDown()
        } else {
            releases.append(event.location)
            onMouseUp(event.location)
        }
        await Task.yield()
    }

    func postEventAndWaitToReceive(_ event: CGEvent, to location: EventTap.Location, item: MenuBarItem) async throws {
        fallbackCount += 1
    }

    func runGesture(to destination: MoveDestination) async throws {
        try await moveItemWithoutRestoringMouseLocation(item, to: destination)
    }

    func runMove(timeout: Duration) async throws {
        // PRODUCTION_MOVE_CALL
    }

    // PRODUCTION_MOVE_METHODS
}

private struct CheckFailure: Error {
    let message: String
}

private func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(message: message) }
}

@main
private enum MenuBarMoveTests {
    @MainActor
    static func main() async {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        let tests: [(String, @MainActor () async throws -> Void)] = [
            ("left drop uses target frame after mouse-down", { try await shiftedDestination(left: true) }),
            ("right drop uses target frame after mouse-down", { try await shiftedDestination(left: false) }),
            ("vanished target releases the mouse and reports failure", vanishedTarget),
            ("wrong position is retried before success", retryWrongPosition),
            ("exhausted moves never report success", exhaustedMove),
        ]
        var failures = 0
        for (name, test) in tests {
            do {
                try await test()
                print("PASS: \(name)")
            } catch {
                failures += 1
                print("FAIL: \(name): \(error)")
            }
        }
        print("\(tests.count - failures)/\(tests.count) movement checks passed")
        exit(failures == 0 ? 0 : 1)
    }

    @MainActor
    private static func shiftedDestination(left: Bool) async throws {
        let harness = MoveHarness()
        // The observed source is 28 pt wide. Removing it shifts the target left.
        harness.onMouseDown = {
            harness.frames[16309] = CGRect(x: 1095, y: 0, width: 23, height: 33)
        }
        let destination: MoveHarness.MoveDestination = left ? .leftOfItem(harness.target) : .rightOfItem(harness.target)
        try await harness.runGesture(to: destination)
        try check(harness.releases == [CGPoint(x: left ? 1095 : 1118, y: 16.5)], "Drop used the target's stale frame")
        try check(harness.itemMoveCount == 0, "Movement state was not released")
    }

    @MainActor
    private static func vanishedTarget() async throws {
        let harness = MoveHarness()
        harness.onMouseDown = { harness.frames.removeValue(forKey: 16309) }
        do {
            try await harness.runGesture(to: .leftOfItem(harness.target))
            throw CheckFailure(message: "Move to vanished target reported success")
        } catch let error as MoveHarness.EventError {
            try check(error.code == .invalidItem, "Unexpected failure for vanished target")
        }
        try check(harness.releases.isEmpty && harness.fallbackCount == 1, "Mouse was not released by the fallback")
        try check(harness.itemMoveCount == 0, "Failed gesture leaked movement state")
    }

    @MainActor
    private static func retryWrongPosition() async throws {
        let harness = MoveHarness()
        harness.onMouseUp = { point in
            // A changed frame alone is not success: the first attempt lands on
            // the wrong side, like the user's 19:59 reproduction.
            let x = harness.releases.count == 1 ? 1146 : point.x - 28
            harness.frames[110] = CGRect(x: x, y: 0, width: 28, height: 33)
        }
        try await harness.runMove(timeout: .milliseconds(10))
        try check(harness.releases.count == 2 && harness.wakeCount == 1, "Wrong-side placement was accepted as success")
        try check(harness.frames[110]?.maxX == harness.frames[16309]?.minX, "Final position is still wrong")
    }

    @MainActor
    private static func exhaustedMove() async throws {
        let harness = MoveHarness()
        harness.onMouseUp = { _ in
            harness.frames[110] = CGRect(x: 1146, y: 0, width: 28, height: 33)
        }
        do {
            try await harness.runMove(timeout: .milliseconds(10))
            throw CheckFailure(message: "Exhausted wrong-side moves reported success")
        } catch let error as MoveHarness.EventError {
            try check(error.code == .otherTimeout, "Expected position timeout")
        }
        try check(harness.releases.count == 5 && harness.itemMoveCount == 0, "Retry bound or cleanup failed")
    }
}

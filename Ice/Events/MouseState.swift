//
//  MouseState.swift
//  Ice
//

import Cocoa

/// Reads session mouse state without consuming events from AppKit's queue.
enum MouseState {
    static var isAnyButtonPressed: Bool {
        NSEvent.pressedMouseButtons != 0
    }

    /// Includes all drag types so that moving with any button held counts as activity.
    static var secondsSinceLastMovement: TimeInterval {
        [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }

    static func waitUntilStationary(for interval: TimeInterval) async throws {
        while true {
            try Task.checkCancellation()
            let remaining = interval - secondsSinceLastMovement
            guard remaining > 0 else {
                return
            }
            try await Task.sleep(for: .seconds(remaining))
        }
    }
}

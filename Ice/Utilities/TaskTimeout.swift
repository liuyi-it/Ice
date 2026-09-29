//
//  TaskTimeout.swift
//  Ice
//

import Foundation

extension Task where Failure == any Error {
    /// Runs the given throwing operation asynchronously as part of a new top-level task
    /// on behalf of the current actor.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///   - timeout: The amount of time to wait before throwing a ``TaskTimeoutError``.
    ///   - tolerance: The tolerance of the clock.
    ///   - clock: The clock to use in the timeout operation.
    ///   - operation: The operation to perform.
    @discardableResult
    init<C: Clock>(
        priority: TaskPriority? = nil,
        timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = ContinuousClock(),
        operation: @escaping @Sendable () async throws -> Success
    ) {
        self.init(priority: priority) {
            try await Task.withTimeout(timeout, tolerance: tolerance, clock: clock, operation: operation)
        }
    }

    /// Runs the given throwing operation asynchronously as part of a new top-level task.
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///   - timeout: The amount of time to wait before throwing a ``TaskTimeoutError``.
    ///   - tolerance: The tolerance of the clock.
    ///   - clock: The clock to use in the timeout operation.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: A reference to the task.
    @discardableResult
    static func detached<C: Clock>(
        priority: TaskPriority? = nil,
        timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = ContinuousClock(),
        operation: @escaping @Sendable () async throws -> Success
    ) -> Task {
        detached(priority: priority) {
            try await withTimeout(timeout, tolerance: tolerance, clock: clock, operation: operation)
        }
    }

    /// Runs within the caller's task so cancellation reaches the operation and timer.
    static func withTimeout<C: Clock>(
        _ timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = ContinuousClock(),
        operation: @escaping @Sendable () async throws -> Success
    ) async throws -> Success {
        try await withThrowingTaskGroup(of: Success.self) { group in
            defer { group.cancelAll() }
            try _Concurrency.Task.checkCancellation()
            group.addTask(operation: operation)
            group.addTask {
                try await _Concurrency.Task.sleep(for: timeout, tolerance: tolerance, clock: clock)
                throw TaskTimeoutError()
            }
            guard let success = try await group.next() else {
                throw _Concurrency.CancellationError()
            }
            return success
        }
    }
}

// MARK: - TaskTimeoutError

/// An error that indicates that a task timed out.
struct TaskTimeoutError: Error, CustomStringConvertible {
    let description = "Task timed out before completion"
}

// MARK: TaskTimeoutError: LocalizedError
extension TaskTimeoutError: LocalizedError {
    var errorDescription: String? { description }
}

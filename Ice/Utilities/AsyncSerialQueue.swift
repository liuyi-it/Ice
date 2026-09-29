//
//  AsyncSerialQueue.swift
//  Ice
//

import Foundation

/// Serializes main-actor operations across suspension points without blocking the run loop.
@MainActor
final class AsyncSerialQueue {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var waiters = [Waiter]()

    private(set) var isRunning = false

    /// Runs an entire operation before admitting the next caller. Operations must not reenter this queue.
    func run<T>(_ operation: @MainActor () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        guard isRunning else {
            isRunning = true
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { @MainActor in
                guard let index = self.waiters.firstIndex(where: { $0.id == id }) else {
                    return
                }
                self.waiters.remove(at: index).continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func release() {
        if waiters.isEmpty {
            isRunning = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }
}

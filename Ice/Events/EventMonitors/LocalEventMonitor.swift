//
//  LocalEventMonitor.swift
//  Ice
//

import Cocoa
import Combine

/// A type that monitors for events within the scope of the current process.
final class LocalEventMonitor {
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> NSEvent?
    private var monitor: Any?

    /// Creates an event monitor with the given event type mask and handler.
    ///
    /// - Parameters:
    ///   - mask: An event type mask specifying which events to monitor.
    ///   - handler: A handler to execute when the event monitor receives
    ///     an event corresponding to the event types in `mask`.
    init(mask: NSEvent.EventTypeMask, handler: @escaping (_ event: NSEvent) -> NSEvent?) {
        self.mask = mask
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// Starts monitoring for events.
    func start() {
        guard monitor == nil else {
            return
        }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: handler
        )
    }

    /// Stops monitoring for events.
    func stop() {
        guard let monitor else {
            return
        }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

extension LocalEventMonitor {
    /// A publisher that emits local events for an event type mask.
    struct LocalEventPublisher: Publisher {
        typealias Output = NSEvent
        typealias Failure = Never

        let mask: NSEvent.EventTypeMask

        func receive<S: Subscriber<Output, Failure>>(subscriber: S) {
            let subscription = LocalEventSubscription(mask: mask, subscriber: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }

    /// Returns a publisher that emits local events for the given event type mask.
    ///
    /// - Parameter mask: An event type mask specifying which events to publish.
    static func publisher(for mask: NSEvent.EventTypeMask) -> LocalEventPublisher {
        LocalEventPublisher(mask: mask)
    }
}

extension LocalEventMonitor.LocalEventPublisher {
    private final class LocalEventSubscription<S: Subscriber<Output, Failure>>: Subscription {
        private var subscriber: S?
        private var monitor: LocalEventMonitor?
        private var demand = Subscribers.Demand.none

        init(mask: NSEvent.EventTypeMask, subscriber: S) {
            self.subscriber = subscriber
            self.monitor = LocalEventMonitor(mask: mask) { [weak self] event in
                self?.receive(event)
                return event
            }
        }

        private func receive(_ event: NSEvent) {
            guard let subscriber, demand > .none else {
                return
            }
            demand -= 1
            let additionalDemand = subscriber.receive(event)
            if self.subscriber != nil {
                demand += additionalDemand
            }
        }

        func request(_ demand: Subscribers.Demand) {
            guard subscriber != nil, demand > .none else {
                return
            }
            self.demand += demand
            monitor?.start()
        }

        func cancel() {
            monitor?.stop()
            monitor = nil
            subscriber = nil
            demand = .none
        }
    }
}

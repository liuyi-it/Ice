//
//  HotkeyRegistry.swift
//  Ice
//

import Carbon.HIToolbox
import Cocoa
import Combine

/// 管理热键注册、存储和注销的对象。
final class HotkeyRegistry {
    /// 热键可以注册的事件类型。
    enum EventKind {
        case keyUp
        case keyDown

        fileprivate init?(event: EventRef) {
            switch Int(GetEventKind(event)) {
            case kEventHotKeyPressed:
                self = .keyDown
            case kEventHotKeyReleased:
                self = .keyUp
            default:
                return nil
            }
        }
    }

    /// 存储取消注册所需信息的对象。
    private final class Registration {
        let eventKind: EventKind
        let key: KeyCode
        let modifiers: Modifiers
        let hotKeyID: EventHotKeyID
        var hotKeyRef: EventHotKeyRef?
        let handler: () -> Void

        init(
            eventKind: EventKind,
            key: KeyCode,
            modifiers: Modifiers,
            hotKeyID: EventHotKeyID,
            hotKeyRef: EventHotKeyRef,
            handler: @escaping () -> Void
        ) {
            self.eventKind = eventKind
            self.key = key
            self.modifiers = modifiers
            self.hotKeyID = hotKeyID
            self.hotKeyRef = hotKeyRef
            self.handler = handler
        }
    }

    private let signature = OSType(1231250720) // OSType for Ice

    private var eventHandlerRef: EventHandlerRef?

    private var registrations = [UInt32: Registration]()

    private var cancellables = Set<AnyCancellable>()

    /// 安装全局事件处理程序引用（如果尚未安装）。
    private func installIfNeeded() -> OSStatus {
        guard eventHandlerRef == nil else {
            return noErr
        }

        NotificationCenter.default
            .publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in
                self?.unregisterAndRetainAll()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                self?.registerAllRetained()
            }
            .store(in: &cancellables)

        let handler: EventHandlerUPP = { _, event, userData in
            guard
                let event,
                let userData
            else {
                return OSStatus(eventNotHandledErr)
            }
            let registry = Unmanaged<HotkeyRegistry>.fromOpaque(userData).takeUnretainedValue()
            return registry.performEventHandler(for: event)
        }

        let eventTypes: [EventTypeSpec] = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        return InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            eventTypes.count,
            eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    /// 为给定的热键注册给定的事件类型，并在成功时返回注册的标识符。
    ///
    /// 返回的标识符可用于使用 ``unregister(_:)`` 函数注销热键。
    ///
    /// - Parameters:
    ///   - hotkey: 要注册处理程序的热键。
    ///   - eventKind: 要注册处理程序的事件类型。
    ///   - handler: 当 `hotkey` 通过 `eventKind` 指定的事件类型触发时要执行的处理程序。
    ///
    /// - Returns: 成功时返回注册的标识符，失败时返回 `nil`。
    func register(hotkey: Hotkey, eventKind: EventKind, handler: @escaping () -> Void) -> UInt32? {
        enum Context {
            static var currentID: UInt32 = 0
        }

        defer {
            Context.currentID += 1
        }

        guard let keyCombination = hotkey.keyCombination else {
            Logger.hotkeyRegistry.error("Hotkey does not have a valid key combination")
            return nil
        }

        var status = installIfNeeded()

        guard status == noErr else {
            Logger.hotkeyRegistry.error("Hotkey event handler installation failed with status \(status)")
            return nil
        }

        let id = Context.currentID

        guard registrations[id] == nil else {
            Logger.hotkeyRegistry.error("Hotkey already registered for id \(id)")
            return nil
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var hotKeyRef: EventHotKeyRef?
        status = RegisterEventHotKey(
            UInt32(keyCombination.key.rawValue),
            UInt32(keyCombination.modifiers.carbonFlags),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            Logger.hotkeyRegistry.error("Hotkey registration failed with status \(status)")
            return nil
        }

        guard let hotKeyRef else {
            Logger.hotkeyRegistry.error("Hotkey registration failed due to invalid EventHotKeyRef")
            return nil
        }

        let registration = Registration(
            eventKind: eventKind,
            key: keyCombination.key,
            modifiers: keyCombination.modifiers,
            hotKeyID: hotKeyID,
            hotKeyRef: hotKeyRef,
            handler: handler
        )
        registrations[id] = registration

        return id
    }

    /// 注销具有给定标识符的组合键，并将其注册保留在非活动状态。
    private func retainedUnregister(_ id: UInt32) {
        guard let registration = registrations[id] else {
            Logger.hotkeyRegistry.error("No registered key combination for id \(id)")
            return
        }
        let status = UnregisterEventHotKey(registration.hotKeyRef)
        guard status == noErr else {
            Logger.hotkeyRegistry.error("Hotkey unregistration failed with status \(status)")
            return
        }
        registration.hotKeyRef = nil
    }

    /// 注销具有给定标识符的组合键。
    ///
    /// - Parameter id: 从调用 ``register(hotkey:eventKind:handler:)`` 函数返回的标识符。
    func unregister(_ id: UInt32) {
        retainedUnregister(id)
        registrations.removeValue(forKey: id)
    }

    /// 注销所有组合键，将其注册保留在非活动状态。
    private func unregisterAndRetainAll() {
        for (id, _) in registrations {
            retainedUnregister(id)
        }
    }

    /// 注册在调用 ``retainedUnregister(_:)`` 期间保留的所有注册。
    private func registerAllRetained() {
        for registration in registrations.values {
            guard registration.hotKeyRef == nil else {
                continue
            }

            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(registration.key.rawValue),
                UInt32(registration.modifiers.carbonFlags),
                registration.hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )

            guard
                status == noErr,
                let hotKeyRef
            else {
                registrations.removeValue(forKey: registration.hotKeyID.id)
                Logger.hotkeyRegistry.error("Hotkey registration failed with status \(status)")
                continue
            }

            registration.hotKeyRef = hotKeyRef
        }
    }

    /// 获取并执行存储在指定事件标识符下的事件处理程序。
    private func performEventHandler(for event: EventRef?) -> OSStatus {
        guard let event else {
            return OSStatus(eventNotHandledErr)
        }

        // create a hot key id from the event
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        // make sure creation was successful
        guard status == noErr else {
            return status
        }

        // make sure the event signature matches our signature and
        // that an event handler is registered for the event
        guard
            hotKeyID.signature == signature,
            let registration = registrations[hotKeyID.id],
            registration.eventKind == EventKind(event: event)
        else {
            return OSStatus(eventNotHandledErr)
        }

        // all checks passed; perform the event handler
        registration.handler()

        return noErr
    }
}

// MARK: - Logger
private extension Logger {
    static let hotkeyRegistry = Logger(category: "HotkeyRegistry")
}

//
//  Hotkey.swift
//  Ice
//

import Combine

/// 组合键和修饰符，可用于在系统级按键按下或松开事件时触发操作。
final class Hotkey: ObservableObject {
    private weak var appState: AppState?

    private var listener: Listener?

    let action: HotkeyAction

    @Published var keyCombination: KeyCombination? {
        didSet {
            enable()
        }
    }

    var isEnabled: Bool {
        listener != nil
    }

    init(keyCombination: KeyCombination?, action: HotkeyAction) {
        self.keyCombination = keyCombination
        self.action = action
    }

    func assignAppState(_ appState: AppState) {
        self.appState = appState
        enable()
    }

    func enable() {
        disable()
        listener = Listener(hotkey: self, eventKind: .keyDown, appState: appState)
        if listener == nil, keyCombination != nil {
            // Registration failed (e.g. the key combination conflicts with
            // another hotkey). Log it, since the failure is otherwise silent.
            Logger.hotkey.warning("Failed to enable hotkey for action \(action)")
        }
    }

    func disable() {
        listener?.invalidate()
        listener = nil
    }
}

extension Hotkey {
    /// 管理热键监听器生命周期的对象。
    private final class Listener {
        private weak var appState: AppState?

        private var id: UInt32?

        var isValid: Bool {
            id != nil
        }

        init?(hotkey: Hotkey, eventKind: HotkeyRegistry.EventKind, appState: AppState?) {
            guard
                let appState,
                hotkey.keyCombination != nil
            else {
                return nil
            }
            let id = appState.hotkeyRegistry.register(
                hotkey: hotkey,
                eventKind: eventKind
            ) { [weak appState] in
                guard let appState else {
                    return
                }
                Task {
                    await hotkey.action.perform(appState: appState)
                }
            }
            guard let id else {
                return nil
            }
            self.appState = appState
            self.id = id
        }

        deinit {
            invalidate()
        }

        func invalidate() {
            guard isValid else {
                return
            }
            guard let appState else {
                Logger.hotkey.error("Error invalidating hotkey: Missing AppState")
                return
            }
            defer {
                id = nil
            }
            if let id {
                appState.hotkeyRegistry.unregister(id)
            }
        }
    }
}

// MARK: Hotkey: Codable
extension Hotkey: Codable {
    private enum CodingKeys: CodingKey {
        case keyCombination
        case action
    }

    convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            keyCombination: container.decode(KeyCombination?.self, forKey: .keyCombination),
            action: container.decode(HotkeyAction.self, forKey: .action)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCombination, forKey: .keyCombination)
        try container.encode(action, forKey: .action)
    }
}

// MARK: Hotkey: Equatable
extension Hotkey: Equatable {
    static func == (lhs: Hotkey, rhs: Hotkey) -> Bool {
        lhs.keyCombination == rhs.keyCombination &&
        lhs.action == rhs.action
    }
}

// MARK: Hotkey: Hashable
extension Hotkey: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCombination)
        hasher.combine(action)
    }
}

// MARK: - Logger
private extension Logger {
    static let hotkey = Logger(category: "Hotkey")
}

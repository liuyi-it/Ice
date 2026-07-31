//
//  HotkeyRecorderModel.swift
//  Ice
//

import Combine
import SwiftUI

@MainActor
final class HotkeyRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false

    @Published var isPresentingReservedByMacOSError = false

    let hotkey: Hotkey

    private lazy var monitor = LocalEventMonitor(mask: .keyDown) { [weak self] event in
        guard let self else {
            return event
        }
        handleKeyDown(event: event)
        return nil
    }

    private var cancellables = Set<AnyCancellable>()

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        hotkey.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }

    func startRecording() {
        guard !isRecording else {
            return
        }
        hotkey.disable()
        monitor.start()
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else {
            return
        }
        monitor.stop()
        hotkey.enable()
        isRecording = false
    }

    /// Key codes that are modifier keys themselves.
    ///
    /// Pressing ⌘ alone would otherwise be recorded as "⌘ + ⌘", which can
    /// never be triggered.
    private static let modifierKeyCodes: Set<KeyCode> = [
        .control, .option, .shift, .command, .capsLock, .function,
    ]

    /// Key codes that may be assigned without any modifiers.
    ///
    /// Function keys F13-F20 and media keys are commonly used without
    /// modifiers, unlike letter/number keys which need at least one modifier.
    private static let unmodifiedFunctionOrMediaKeyCodes: Set<KeyCode> = [
        .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
        .volumeUp, .volumeDown, .mute,
    ]

    private func handleKeyDown(event: NSEvent) {
        let keyCombination = KeyCombination(event: event)

        // Reject modifier keys themselves.
        if Self.modifierKeyCodes.contains(keyCombination.key) {
            NSSound.beep()
            return
        }

        if keyCombination.modifiers.isEmpty {
            if keyCombination.key == .escape {
                stopRecording()
            } else if Self.unmodifiedFunctionOrMediaKeyCodes.contains(keyCombination.key) {
                hotkey.keyCombination = keyCombination
                stopRecording()
            } else {
                NSSound.beep()
            }
            return
        }
        guard keyCombination.modifiers != .shift else {
            NSSound.beep()
            return
        }
        guard !keyCombination.isReservedBySystem else {
            isPresentingReservedByMacOSError = true
            return
        }
        hotkey.keyCombination = keyCombination
        stopRecording()
    }
}

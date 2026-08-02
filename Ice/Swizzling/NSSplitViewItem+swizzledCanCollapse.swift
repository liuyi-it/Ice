//
//  NSSplitViewItem+swizzledCanCollapse.swift
//  Ice
//

import Cocoa

extension NSSplitViewItem {
    @nonobjc private static let swizzler: () = {
        let originalCanCollapseSel = #selector(getter: canCollapse)
        let swizzledCanCollapseSel = #selector(getter: swizzledCanCollapse)

        guard
            let originalCanCollapseMethod = class_getInstanceMethod(NSSplitViewItem.self, originalCanCollapseSel),
            let swizzledCanCollapseMethod = class_getInstanceMethod(NSSplitViewItem.self, swizzledCanCollapseSel)
        else {
            Logger.splitViewItemSwizzle.warning("Failed to swizzle NSSplitViewItem.canCollapse: sidebar will be user-collapsible")
            return
        }

        method_exchangeImplementations(originalCanCollapseMethod, swizzledCanCollapseMethod)
    }()

    @objc private var swizzledCanCollapse: Bool {
        if
            let window = viewController.view.window,
            Self.settingsWindows.contains(window)
        {
            return false
        }
        return self.swizzledCanCollapse
    }

    /// The windows whose split view items must not be collapsible.
    ///
    /// Registered with the settings window instance (rather than matching a
    /// string identifier) so other windows are never affected. The table is
    /// weak: entries disappear when the window is released.
    private static let settingsWindows = NSHashTable<NSWindow>.weakObjects()

    /// Registers the given window as one whose split view items must not be
    /// collapsible.
    static func preventCollapse(in window: NSWindow) {
        settingsWindows.add(window)
    }

    static func swizzle() {
        _ = swizzler
    }
}

// MARK: - Logger

private extension Logger {
    static let splitViewItemSwizzle = Logger(category: "SplitViewItemSwizzle")
}

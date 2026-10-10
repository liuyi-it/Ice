//
//  WindowInfoTests.swift
//  Ice
//

import Cocoa

enum Bridging {
    static func isWindowOnActiveSpace(_ windowID: CGWindowID) -> Bool { true }
}

enum Predicates {
    static func wallpaperWindow(for display: CGDirectDisplayID) -> (WindowInfo) -> Bool { { _ in false } }
    static func menuBarWindow(for display: CGDirectDisplayID) -> (WindowInfo) -> Bool { { _ in false } }
}

// The runner compiles this extension in the same file as production WindowInfo
// so fixtures use its private dictionary parser without changing app visibility.
extension WindowInfo {
    static func fixture(owner: String?, title: String?, layer: Int = Int(kCGStatusWindowLevel)) -> WindowInfo {
        var values: [CFString: Any] = [
            kCGWindowNumber: 6423,
            kCGWindowBounds: CGRect(x: -3911, y: 0, width: 28, height: 33).dictionaryRepresentation,
            kCGWindowLayer: layer,
            kCGWindowAlpha: 1.0,
            kCGWindowOwnerPID: 401,
            kCGWindowSharingState: 0,
            kCGWindowStoreType: 1,
            kCGWindowMemoryUsage: 2368.0,
        ]
        values[kCGWindowOwnerName] = owner
        values[kCGWindowName] = title
        guard let window = WindowInfo(dictionary: values as CFDictionary) else {
            fatalError("Invalid test window dictionary")
        }
        return window
    }
}

@main
private enum WindowInfoTests {
    static func check(_ condition: Bool, _ name: String) {
        guard condition else {
            print("FAIL: \(name)")
            exit(EXIT_FAILURE)
        }
        print("PASS: \(name)")
    }

    static func main() {
        let clone = WindowInfo.fixture(owner: "Window Server", title: "System Status Item Clone")
        check(!clone.isMenuBarItem, "WindowServer status clones are excluded before caching or movement")
        let reparented = WindowInfo.fixture(owner: "控制中心", title: "Item-0")
        check(reparented.isMenuBarItem, "macOS 26 reparented third-party items remain eligible")
        let ice = WindowInfo.fixture(owner: "Ice", title: "SItem")
        check(ice.isMenuBarItem, "Ice section control items remain eligible")
        let redacted = WindowInfo.fixture(owner: nil, title: nil)
        check(redacted.isMenuBarItem, "missing optional metadata does not discard real status items")
        let ordinary = WindowInfo.fixture(owner: "Ice", title: "Settings", layer: 0)
        check(!ordinary.isMenuBarItem, "ordinary windows remain excluded")
    }
}

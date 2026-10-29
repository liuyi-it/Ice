//
//  WindowInfoTests.swift
//  Ice
//

import Cocoa

enum Constants {
    static let bundleIdentifier = "com.jordanbaird.Ice"
}

enum ControlItem {
    enum Identifier: String {
        case iceIcon = "SItem", hidden = "HItem", alwaysHidden = "AHItem"
    }
}

// Only the application lookup is simulated; window parsing and selection use
// production code. PID 401 represents Control Center in the recorded fixtures.
struct NSRunningApplication {
    let bundleIdentifier: String?

    init?(processIdentifier: pid_t) {
        bundleIdentifier = processIdentifier == 401 ? "com.apple.controlcenter" : "com.example.app"
    }
}

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
    static func fixture(
        owner: String?,
        title: String?,
        layer: Int = Int(kCGStatusWindowLevel),
        id: Int = 6423,
        pid: Int = 401,
        onScreen: Bool = false,
        frame: CGRect = CGRect(x: -3911, y: 0, width: 28, height: 33)
    ) -> WindowInfo {
        var values: [CFString: Any] = [
            kCGWindowNumber: id,
            kCGWindowBounds: frame.dictionaryRepresentation,
            kCGWindowLayer: layer,
            kCGWindowAlpha: 1.0,
            kCGWindowOwnerPID: pid,
            kCGWindowIsOnscreen: onScreen,
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

        let control = WindowInfo.fixture(owner: "控制中心", title: "BentoBox-0", id: 35, onScreen: true)
        let alias = WindowInfo.fixture(owner: "控制中心", title: "", id: 404)
        check(
            WindowInfo.menuBarItemWindows(from: [alias, control]).map(\.windowID) == [35],
            "on-screen control center window wins over its same-frame alias"
        )
        check(
            WindowInfo.menuBarItemWindows(from: [control, alias]).map(\.windowID) == [35],
            "duplicate filtering is independent of enumeration order"
        )
        let hidden = WindowInfo.fixture(owner: "控制中心", title: "Item-0", id: 6555)
        let registration = WindowInfo.fixture(owner: "控制中心", title: "com.Snipaste", id: 6556)
        check(
            WindowInfo.menuBarItemWindows(from: [registration, hidden]).map(\.windowID) == [6555],
            "hidden hosted item wins over its application registration window"
        )
        let otherOwner = WindowInfo.fixture(owner: "Other", title: "Item-0", id: 99, pid: 402)
        check(
            WindowInfo.menuBarItemWindows(from: [hidden, otherOwner, clone, ordinary]).map(\.windowID) == [6555, 99],
            "same-frame items from different owners remain distinct and invalid windows stay excluded"
        )
        let neighbor = WindowInfo.fixture(
            owner: "控制中心",
            title: "Item-0",
            id: 100,
            frame: CGRect(x: -3939, y: 0, width: 28, height: 33)
        )
        check(
            WindowInfo.menuBarItemWindows(from: [hidden, neighbor]).map(\.windowID) == [6555, 100],
            "separate hidden items with the same title and owner remain distinct"
        )
        check(
            MenuBarItemInfo.immovableItems.contains(MenuBarItemInfo(namespace: .controlCenter, title: "BentoBox-0")),
            "macOS 26 control center title is recognized as immovable"
        )
        if #available(macOS 26.0, *) {
            let staleRegistration = WindowInfo.fixture(
                owner: "控制中心",
                title: "com.Snipaste",
                id: 6556,
                frame: CGRect(x: 0, y: 0, width: 28, height: 33)
            )
            let bundleIDs: Set<String> = ["com.Snipaste", "com.example.app"]
            check(
                WindowInfo.menuBarItemWindows(
                    from: [hidden, staleRegistration], applicationBundleIdentifiers: bundleIDs
                ).map(\.windowID) == [6555],
                "off-screen application registration is excluded even when its frame is stale"
            )
            let visible = WindowInfo.fixture(owner: "控制中心", title: "com.Snipaste", id: 101, onScreen: true)
            check(
                WindowInfo.menuBarItemWindows(from: [visible], applicationBundleIdentifiers: bundleIDs).map(\.windowID) == [101],
                "on-screen bundle-titled status items remain eligible"
            )
            let native = WindowInfo.fixture(owner: "Other", title: "com.example.app", id: 102, pid: 402)
            check(
                WindowInfo.menuBarItemWindows(from: [native], applicationBundleIdentifiers: bundleIDs).map(\.windowID) == [102],
                "native hidden status items are not treated as Control Center registrations"
            )
        }
    }
}

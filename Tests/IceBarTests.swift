//
//  IceBarTests.swift
//  Ice
//

import Foundation
import CoreGraphics

// OS boundaries are simulated; the runner inserts the production methods.
private enum MenuBarSection {
    enum Name: CaseIterable { case visible, hidden, alwaysHidden }
}

private struct MenuBarItemInfo: Hashable {
    let value: Int
    static let hiddenControlItem = Self(value: -1)
}

private struct MenuBarItem {
    let windowID: Int
    let info: MenuBarItemInfo
    let frame: CGRect
    var isOnScreen = true
    static var snapshot = [Self]()
    static var queryCount = 0

    static func getMenuBarItems(onScreenOnly: Bool, activeSpaceOnly: Bool) -> [Self] {
        queryCount += 1
        return snapshot
    }
}

private struct NSScreen {
    static let screens = [Self()]
    static var displayFrames = [Int: CGRect]()
    var displayID = 1
    var frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    var frameOfNotch: CGRect?
}

private func CGDisplayBounds(_ displayID: Int) -> CGRect { NSScreen.displayFrames[displayID] ?? NSScreen().frame }

private struct ControlItem { let trailingEdge: CGFloat }
private struct Section { let controlItem: ControlItem }

private extension Array where Element == MenuBarItem {
    func firstIndex(matching info: MenuBarItemInfo) -> Int? { firstIndex { $0.info == info } }
    func firstIndex(matchingControlItem item: ControlItem) -> Int? {
        firstIndex { abs($0.frame.maxX - item.trailingEdge) <= 2 }
    }
    func uniquedByInfo() -> Self {
        var seen = Set<MenuBarItemInfo>()
        return filter { seen.insert($0.info).inserted }
    }
}

private enum Predicates {
    static func isInVisibleSection(hiddenControlItem: MenuBarItem) -> (MenuBarItem) -> Bool {
        { $0.frame.minX >= hiddenControlItem.frame.maxX }
    }
}

@MainActor
private final class Gate {
    private var isOpen = false
    private var waiters = [CheckedContinuation<Void, Never>]()

    func wait() async {
        if !isOpen {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func open() {
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

@MainActor
private final class NavigationState {
    var isIceBarPresented = false
    var isSearchPresented = false
    var isSettingsPresented = false
}

@MainActor
private final class ImageCache {
    weak var appState: AppState?
    var sections = [MenuBarSection.Name]()
    var updateTask: Task<Void, Never>?
    var pendingSections = Set<MenuBarSection.Name>()
    var captureGate = Gate()
    var captures = [[MenuBarSection.Name]]()
    var activeCaptures = 0
    var peakCaptures = 0

    init(appState: AppState? = nil) { self.appState = appState }

    // PRODUCTION_CACHE_DISPLAY_METHODS
    func updateCache(sections: [MenuBarSection.Name]) async { self.sections += sections }

    private func captureImages(sections: [MenuBarSection.Name]) async {
        activeCaptures += 1
        peakCaptures = max(peakCaptures, activeCaptures)
        captures.append(sections)
        await captureGate.wait()
        activeCaptures -= 1
    }

    // PRODUCTION_CACHE_METHODS
}

private enum ScreenCapture {
    static var permitted = true
    static func cachedCheckPermissions() -> Bool { permitted }
}

private final class SectionPanel { var currentSection: MenuBarSection.Name? = .hidden }

@MainActor
private final class MenuBarManager {
    let iceBarPanel = SectionPanel()
    var menuQueryCount = 0
    var applicationMenuFrame: CGRect?
    var controlItem = ControlItem(trailingEdge: 700)

    func section(withName: MenuBarSection.Name) -> Section? { Section(controlItem: controlItem) }
    func getApplicationMenuFrame(for displayID: Int) -> CGRect? {
        menuQueryCount += 1
        return applicationMenuFrame
    }
}

@MainActor
private final class AppState {
    let navigationState = NavigationState()
    lazy var imageCache = ImageCache(appState: self)
    let menuBarManager = MenuBarManager()
    lazy var itemManager = MenuBarItemManager(appState: self)
}

@MainActor
private final class MenuBarItemManager {
    struct ItemCache {
        var sections = [MenuBarSection.Name: [MenuBarItem]]()
        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] { sections[section, default: []] }
    }

    weak var appState: AppState?
    var itemCache = ItemCache()
    var cacheGate = Gate()
    var cacheRequests = 0

    init(appState: AppState) { self.appState = appState }

    func cacheItemsIfNeeded() async {
        cacheRequests += 1
        await cacheGate.wait()
    }

    // PRODUCTION_SELECTION_METHODS
}

@MainActor
private class Panel {
    var isVisible = false
    func close() { isVisible = false }
}

@MainActor
private final class ColorManager {
    func updateColorInfo(with frame: CGRect, screen: NSScreen) { }
    func updateAllProperties(with frame: CGRect, screen: NSScreen) { }
}

@MainActor
private final class IceBarHostingView {
    init(
        appState: AppState,
        panel: IceBarPanel? = nil,
        colorManager: ColorManager,
        screen: NSScreen,
        section: MenuBarSection.Name,
        closePanel: @escaping () -> Void
    ) { }
}

@MainActor
private final class IceBarPanel: Panel {
    weak var appState: AppState?
    var currentSection: MenuBarSection.Name?
    var isRefreshing = false
    var refreshTask: Task<Void, Never>?
    var presentationID: UUID?
    var contentView: IceBarHostingView?
    let colorManager = ColorManager()
    let frame = CGRect.zero

    init(appState: AppState) { self.appState = appState }
    func updateOrigin(for screen: NSScreen) { }
    func orderFrontRegardless() { isVisible = true }

    // PRODUCTION_PANEL_METHODS
}

@main
@MainActor
private enum IceBarTests {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition { failures += 1 }
        print("\(condition ? "PASS" : "FAIL"): \(message)")
    }

    static func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    static func item(_ id: Int, x: CGFloat, onScreen: Bool = true) -> MenuBarItem {
        MenuBarItem(
            windowID: id,
            info: MenuBarItemInfo(value: id),
            frame: CGRect(x: x, y: 0, width: 20, height: 24),
            isOnScreen: onScreen
        )
    }

    static func main() async throws {
        let state = AppState()
        let panel = IceBarPanel(appState: state)
        var returned = false
        let opening = Task { await panel.show(section: .hidden, on: NSScreen()); returned = true }
        await settle()
        check(returned && panel.isVisible && panel.isRefreshing, "panel opens before a delayed item cache completes")
        panel.close()
        state.itemManager.cacheGate.open()
        await opening.value
        await settle()
        check(
            !panel.isVisible && !state.navigationState.isIceBarPresented,
            "closing during refresh does not resurrect the panel"
        )
        check(state.imageCache.sections.isEmpty, "closing cancels pending image refresh")

        let nextGate = Gate()
        state.itemManager.cacheGate = nextGate
        let first = Task { await panel.show(section: .hidden, on: NSScreen()) }
        await settle()
        let lastGate = Gate()
        state.itemManager.cacheGate = lastGate
        panel.close()
        let second = Task { await panel.show(section: .hidden, on: NSScreen()) }
        await settle()
        nextGate.open()
        await first.value
        await settle()
        check(state.imageCache.sections.isEmpty, "obsolete refresh cannot affect a reopened identical section")
        lastGate.open()
        await second.value
        await settle()
        check(state.imageCache.sections == [.visible, .hidden], "only the current presentation requests images")
        check(!panel.isRefreshing, "loading state finishes with the current refresh")
        panel.close()

        let hidden = item(1, x: -100)
        let visible = [item(2, x: 800), item(3, x: 830), item(4, x: 860)]
        let delimiter = MenuBarItem(
            windowID: 99,
            info: .hiddenControlItem,
            frame: CGRect(x: 750, y: 0, width: 20, height: 24)
        )
        // The AppKit delimiter frame is stale and now matches a normal item.
        state.menuBarManager.controlItem = ControlItem(trailingEdge: 880)
        MenuBarItem.snapshot = [delimiter] + visible + [hidden]
        state.itemManager.itemCache.sections = [.visible: visible, .hidden: [hidden]]
        check(
            state.itemManager.itemIsDirectlyClickable(visible[0], on: NSScreen()),
            "stable delimiter identity takes precedence over a stale matching frame"
        )
        MenuBarItem.queryCount = 0
        state.menuBarManager.menuQueryCount = 0
        let selected = state.itemManager.iceBarItems(for: .hidden, on: NSScreen())
        check(selected.map(\.windowID) == [1], "visible icons are not duplicated into the hidden bar")
        check(
            MenuBarItem.queryCount == 1 && state.menuBarManager.menuQueryCount == 1,
            "a bar selection uses one window snapshot and one AX query"
        )

        MenuBarItem.snapshot = [delimiter, visible[0], item(3, x: -20), item(4, x: 860, onScreen: false), hidden]
        let overflow = state.itemManager.iceBarItems(for: .hidden, on: NSScreen())
        check(overflow.map(\.windowID) == [3, 4, 1], "inaccessible visible icons remain available before hidden icons")
        MenuBarItem.snapshot = [delimiter, visible[0], hidden]
        let remaining = state.itemManager.iceBarItems(for: .hidden, on: NSScreen())
        check(remaining.map(\.windowID) == [1], "disappeared items are omitted instead of showing stale images")

        state.menuBarManager.applicationMenuFrame = CGRect(x: 0, y: 0, width: 815, height: 24)
        let occluded = state.itemManager.iceBarItems(for: .hidden, on: NSScreen())
        check(occluded.map(\.windowID) == [2, 1], "icons covered by application menus remain accessible")
        state.menuBarManager.applicationMenuFrame = nil
        var notchedScreen = NSScreen()
        notchedScreen.frameOfNotch = CGRect(x: 790, y: 776, width: 40, height: 24)
        check(
            state.itemManager.iceBarItems(for: .hidden, on: notchedScreen).map(\.windowID) == [2, 1],
            "notch coordinates are converted from AppKit to WindowServer space"
        )
        let upperScreen = NSScreen(displayID: 2, frame: CGRect(x: 0, y: 800, width: 1000, height: 800))
        NSScreen.displayFrames[2] = CGRect(x: 0, y: -800, width: 1000, height: 800)
        let upperItem = MenuBarItem(
            windowID: 2,
            info: visible[0].info,
            frame: CGRect(x: 800, y: -800, width: 20, height: 24)
        )
        MenuBarItem.snapshot = [upperItem, hidden]
        check(
            state.itemManager.iceBarItems(for: .hidden, on: upperScreen).map(\.windowID) == [1],
            "visible items on a vertically arranged display use WindowServer coordinates"
        )
        state.itemManager.itemCache.sections[.alwaysHidden] = [hidden]
        MenuBarItem.queryCount = 0
        check(
            state.itemManager.iceBarItems(for: .alwaysHidden, on: NSScreen()).map(\.windowID) == [1] && MenuBarItem.queryCount == 0,
            "always-hidden selection requires no system query"
        )

        state.imageCache.sections = []
        state.navigationState.isIceBarPresented = true
        await state.imageCache.updateCache()
        check(state.imageCache.sections == [.visible, .hidden], "hidden bar refresh includes obscured visible icons")
        state.imageCache.sections = []
        state.menuBarManager.iceBarPanel.currentSection = .alwaysHidden
        await state.imageCache.updateCache()
        check(state.imageCache.sections == [.alwaysHidden], "always-hidden bar refreshes only its own section")

        let cache = ImageCache()
        let initial = Task { await cache.updateCacheWithoutChecks(sections: [.hidden]) }
        await settle()
        let requests = (0..<20).map { _ in
            Task { await cache.updateCacheWithoutChecks(sections: [.hidden, .alwaysHidden]) }
        }
        await settle()
        check(cache.captures.count == 1 && cache.peakCaptures == 1, "slow image capture admits only one worker")
        cache.captureGate.open()
        await initial.value
        for request in requests { await request.value }
        check(
            cache.captures == [[.hidden], [.hidden, .alwaysHidden]] && cache.peakCaptures == 1,
            "twenty concurrent refreshes coalesce and preserve every requested section"
        )
        check(cache.updateTask == nil && cache.pendingSections.isEmpty, "capture worker releases its state when finished")
        await cache.updateCacheWithoutChecks(sections: [.visible])
        check(cache.captures.last == [.visible], "refresh after worker completion starts a new capture")

        exit(failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}

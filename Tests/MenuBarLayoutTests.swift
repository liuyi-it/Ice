//
//  MenuBarLayoutTests.swift
//  Ice
//

import Cocoa
import Combine

// Simulated app, persistence and capture boundaries. The layout manager and
// configuration compiled by the runner are the unmodified production sources.
struct MenuBarItemInfo: Codable, Hashable, CustomStringConvertible {
    let value: String
    var description: String { value }
    var title: String { value }
    enum Namespace { case ice }
    var namespace: Namespace { .ice }
    static let iceIcon = Self(value: "Ice")
    static let newItems = Self(value: "NewItems")
}

struct MenuBarItem: Hashable {
    let info: MenuBarItemInfo
    var isMovable: Bool { !["Clock", "BentoBox-0"].contains(info.title) }
    var logString: String { info.description }
    static var currentItems = [MenuBarItem]()
    static func getMenuBarItems(onScreenOnly: Bool, activeSpaceOnly: Bool) -> [Self] { currentItems }
}

struct ControlItem {
    enum Identifier: String { case iceIcon = "Ice", hidden, alwaysHidden }
    let identifier: Identifier
}

struct MenuBarSection {
    enum Name: CaseIterable { case visible, hidden, alwaysHidden
        var logString: String { String(describing: self) }
    }
    let controlItem: ControlItem
}

extension Array where Element == MenuBarItem {
    func firstIndex(matchingControlItem control: ControlItem) -> Int? {
        firstIndex { $0.info.title == control.identifier.rawValue }
    }
}

@MainActor
final class MenuBarItemManager {
    struct ItemCache: Hashable {
        var items = [MenuBarSection.Name: [MenuBarItem]]()
        var managedItems: [MenuBarItem] { MenuBarSection.Name.allCases.flatMap { managedItems(for: $0) } }
        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] { items[section, default: []] }
        func section(for item: MenuBarItem) -> MenuBarSection.Name? {
            MenuBarSection.Name.allCases.first { items[$0, default: []].contains(item) }
        }
    }
    enum MoveDestination {
        case leftOfItem(MenuBarItem), rightOfItem(MenuBarItem)
        var logString: String { String(describing: self) }
    }
    @Published var itemCache = ItemCache()
    var isMovingItem = false
    var itemHasRecentlyMoved: Bool { Date.now < cooldownEnd }
    var cooldownEnd = Date.distantPast
    var moves = [MenuBarItem]()
    var shouldFailMoves = false
    var leavesLayoutUnchanged = false
    var failedItems = Set<MenuBarItem>()
    enum MoveError: Error { case unavailable }
    struct EventError: Error {
        enum Code { case couldNotComplete }
        let code: Code
        let item: MenuBarItem
    }
    func cacheItemsIfNeeded(force: Bool) async { itemCache = itemCache }
    func slowMove(item: MenuBarItem, to destination: MoveDestination, timeout: Duration) async throws {
        moves.append(item)
        if shouldFailMoves || failedItems.contains(item) {
            throw MoveError.unavailable
        }
        if leavesLayoutUnchanged { return }
        for section in MenuBarSection.Name.allCases { itemCache.items[section]?.removeAll { $0 == item } }
        let section: MenuBarSection.Name
        switch destination {
        case .leftOfItem(let target):
            section = target.info.title == "alwaysHidden" ? .alwaysHidden : .hidden
        case .rightOfItem:
            section = .visible
        }
        itemCache.items[section, default: []].append(item)
        cooldownEnd = .now.addingTimeInterval(1.3)
    }
}

@MainActor
final class ImageCache {
    @Published var images = [MenuBarItemInfo: CGImage]()
    var captureImages = [MenuBarItemInfo: CGImage]()
    var captureDelay = Duration.zero
    func captureImagesForIdentityResolution(items: [MenuBarItem]) async {
        try? await Task.sleep(for: captureDelay)
        images.merge(captureImages) { _, new in new }
    }
}

struct MenuBarManager {
    var isMenuBarHiddenBySystemUserDefaults = false
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        let identifier: ControlItem.Identifier = switch name {
        case .visible: .iceIcon
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
        return MenuBarSection(controlItem: ControlItem(identifier: identifier))
    }
}

struct NavigationState {
    enum Identifier { case menuBarLayout }
    var isSettingsPresented = false
    var settingsNavigationIdentifier: Identifier?
}

struct EventManager {
    var isDraggingMenuBarItem = false
    var lastUserDragEndDate: Date?
}

@MainActor
final class AppState {
    let itemManager = MenuBarItemManager()
    let imageCache = ImageCache()
    var menuBarManager = MenuBarManager()
    var navigationState = NavigationState()
    var eventManager = EventManager()
    lazy var layoutManager = MenuBarLayoutManager(appState: self)
}

enum Defaults {
    enum Key { case menuBarLayoutConfigurationV1 }
    static var storedData: Data?
    static func data(forKey: Key) -> Data? { storedData }
    static func set(_ data: Data, forKey: Key) { storedData = data }
}

enum ScreenCapture {
    static var permitted = true
    static func cachedCheckPermissions() -> Bool { permitted }
}

struct Logger {
    init(category: String) { }
    func error(_ message: String) { }
    func warning(_ message: String) { }
    func info(_ message: String) { }
}

@main
enum MenuBarLayoutTests {
    static func image(_ value: UInt8) -> CGImage {
        let data = Data([value, 100, 200, 255]) as CFData
        guard let provider = CGDataProvider(data: data), let image = CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { fatalError("Could not create test image") }
        return image
    }

    static func item(_ value: String) -> MenuBarItem { MenuBarItem(info: MenuBarItemInfo(value: value)) }

    /// The icon pixels are identical, but neighboring icons and row strides differ.
    static func croppedIcon(parentWidth: Int, neighbor: UInt8) -> CGImage {
        var pixels = [UInt8](repeating: neighbor, count: parentWidth * 3 * 4)
        for y in 1...2 {
            for x in 2...3 {
                let offset = (y * parentWidth + x) * 4
                pixels.replaceSubrange(offset..<(offset + 4), with: [30, 100, 200, 255])
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData), let parent = CGImage(
            width: parentWidth,
            height: 3,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: parentWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ), let cropped = parent.cropping(to: CGRect(x: 2, y: 1, width: 2, height: 2)) else {
            fatalError("Could not crop test icon")
        }
        return cropped
    }

    static func templateIcon(offset: Int) -> CGImage {
        // Match a 28 x 33 point status item captured on a Retina display.
        var pixels = [UInt8](repeating: 0, count: 56 * 66 * 4)
        for y in 16..<48 {
            for x in (offset * 2)..<((offset + 6) * 2) {
                pixels[(y * 56 + x) * 4 + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData), let image = CGImage(
            width: 56,
            height: 66,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 56 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { fatalError("Could not create template icon") }
        return image
    }

    @MainActor
    static func stored() throws -> MenuBarLayoutConfigurationV1 {
        guard let data = Defaults.storedData else { fatalError("Layout was not saved") }
        return try JSONDecoder().decode(MenuBarLayoutConfigurationV1.self, from: data)
    }

    @MainActor
    static func fixture() -> AppState {
        Defaults.storedData = nil
        ScreenCapture.permitted = true
        MenuBarItem.currentItems = [item("hidden"), item("alwaysHidden")]
        return AppState()
    }

    @MainActor
    static func pause(_ seconds: Double = 1.2) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    @MainActor
    static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            print("FAIL: \(message)")
            exit(EXIT_FAILURE)
        }
        print("PASS: \(message)")
    }

    @MainActor
    static func main() async throws {
        let scenario = CommandLine.arguments.dropFirst().first

        if scenario == nil || scenario == "legacy-fingerprint" {
            let old = MenuBarItemPersistentIdentity(info: item("Old").info, imageHash: "full-window")
            let fresh = MenuBarItemPersistentIdentity(info: item("Fresh").info, imageHash: "content")
            let canonical = MenuBarItemPersistentIdentity(info: item("Canonical").info, imageHash: "content")
            var configuration = MenuBarLayoutConfigurationV1(sections: [
                .init(name: .hidden, items: [old]),
                .init(name: .visible, items: [fresh]),
            ])
            _ = configuration.reconcileIdentities(
                [fresh], resolving: [fresh.info], legacyImageHashes: [fresh.info: "full-window"]
            )
            check(configuration.items(for: .hidden) == [fresh], "legacy full-window fingerprints migrate to content fingerprints")
            configuration = MenuBarLayoutConfigurationV1(sections: [
                .init(name: .hidden, items: [canonical]),
                .init(name: .alwaysHidden, items: [old]),
                .init(name: .visible, items: [fresh]),
            ])
            _ = configuration.reconcileIdentities(
                [fresh], resolving: [fresh.info], legacyImageHashes: [fresh.info: "full-window"]
            )
            check(configuration.items(for: .hidden) == [fresh], "canonical preference takes priority over a conflicting legacy fingerprint")
        }

        if scenario == nil || scenario == "capture-height" {
            let app = fixture()
            let old = item("Codex-hidden")
            let fresh = item("Codex-relaunched")
            let fullIcon = templateIcon(offset: 3)
            let height = Int(NSStatusBar.system.thickness * (NSScreen.main?.backingScaleFactor ?? 1))
            guard let croppedIcon = fullIcon.cropping(to: CGRect(
                x: 0,
                y: (fullIcon.height - height) / 2,
                width: fullIcon.width,
                height: height
            )) else { fatalError("Could not crop the status icon") }
            app.itemManager.itemCache.items = [.hidden: [old]]
            app.imageCache.images = [old.info: croppedIcon]
            app.layoutManager.recordCurrentLayout(reason: "individual hidden capture")
            app.itemManager.itemCache.items = [.visible: [fresh]]
            app.imageCache.images = [fresh.info: fullIcon]
            app.layoutManager.performSetup()
            try await pause()
            check(app.itemManager.moves.contains(fresh), "composite and individual capture heights identify the same relaunched icon")
        }

        if scenario == nil || scenario == "same-section-orphans" {
            let app = fixture()
            let first = item("Codex-older-window")
            let second = item("Codex-old-window")
            let fresh = item("Codex-relaunched")
            app.itemManager.itemCache.items = [.hidden: [first, second]]
            app.imageCache.images = [first.info: image(20), second.info: image(20)]
            app.layoutManager.recordCurrentLayout(reason: "historical hidden identities")
            app.itemManager.itemCache.items = [.visible: [fresh]]
            app.imageCache.images = [fresh.info: image(20)]
            app.layoutManager.performSetup()
            try await pause()
            check(app.itemManager.moves.contains(fresh), "orphan matches sharing one section restore their common preference")
            check(
                try stored().items(for: .hidden).map(\.info) == [first.info, second.info, fresh.info],
                "ambiguous identities retain their history without guessing which old app was replaced"
            )
        }

        if scenario == nil || scenario == "system-order" {
            let app = fixture()
            let control = item("BentoBox-0")
            let clock = item("Clock")
            let chat = item("ChatGPT")
            app.itemManager.itemCache.items = [.visible: [control, clock, chat]]
            app.layoutManager.recordCurrentLayout(reason: "legacy order after system items")
            app.itemManager.itemCache.items = [.visible: [chat, control, clock]]
            ScreenCapture.permitted = false
            app.layoutManager.performSetup()
            try await pause(2)
            check(app.itemManager.moves.isEmpty, "fixed system icons cannot start a repeating order restoration")
        }

        if scenario == nil || scenario == "section-priority" {
            let app = fixture()
            let first = item("Visible-first")
            let second = item("Visible-second")
            let chat = item("ChatGPT")
            app.itemManager.itemCache.items = [.visible: [first, second], .hidden: [chat]]
            app.layoutManager.recordCurrentLayout(reason: "hidden ChatGPT")
            app.itemManager.itemCache.items = [.visible: [second, first, chat]]
            app.itemManager.shouldFailMoves = true
            ScreenCapture.permitted = false
            app.layoutManager.performSetup()
            try await pause()
            check(app.itemManager.moves.first == chat, "section restoration precedes unrelated visible ordering")
        }

        if scenario == nil || scenario == "no-progress" {
            let app = fixture()
            let chat = item("ChatGPT")
            app.itemManager.itemCache.items = [.hidden: [chat]]
            app.layoutManager.recordCurrentLayout(reason: "hidden ChatGPT")
            app.itemManager.itemCache.items = [.visible: [chat]]
            app.itemManager.leavesLayoutUnchanged = true
            ScreenCapture.permitted = false
            app.layoutManager.performSetup()
            try await pause(2)
            let attemptsAtLimit = app.itemManager.moves.count
            try await pause(2)
            check(
                attemptsAtLimit == 3 && app.itemManager.moves.count == attemptsAtLimit,
                "successful gestures without layout progress stop at the failure limit"
            )
        }

        if scenario == nil || scenario == "failed-item" {
            let app = fixture()
            let stuck = item("Unmovable")
            let chat = item("ChatGPT")
            app.itemManager.itemCache.items = [.hidden: [stuck], .alwaysHidden: [chat]]
            app.layoutManager.recordCurrentLayout(reason: "preferred hidden sections")
            app.itemManager.itemCache.items = [.visible: [stuck, chat]]
            app.itemManager.failedItems = [stuck]
            ScreenCapture.permitted = false
            app.layoutManager.performSetup()
            try await pause(2.2)
            check(app.itemManager.itemCache.section(for: chat) == .alwaysHidden, "one exhausted item does not block another hidden section")
        }

        if scenario == nil || scenario == "failed-ice-icon" {
            let app = fixture()
            let icon = item("Ice")
            let other = item("Visible")
            let chat = item("Codex")
            app.itemManager.itemCache.items = [.visible: [icon, other], .hidden: [chat]]
            app.layoutManager.recordCurrentLayout(reason: "hidden Codex beside Ice")
            app.itemManager.itemCache.items = [.visible: [other, icon, chat]]
            app.itemManager.failedItems = [icon]
            ScreenCapture.permitted = false
            app.layoutManager.performSetup()
            try await pause(2.2)
            check(
                app.itemManager.moves.filter { $0 == icon }.count == 3
                    && app.itemManager.itemCache.section(for: chat) == .hidden,
                "Ice icon restoration obeys the failure limit and cannot block hidden apps"
            )
        }

        if scenario == nil || scenario == "template-icons" {
            let app = fixture()
            let old = item("Snipaste-old")
            let other = item("Other-app")
            let relaunched = item("Snipaste-new")
            app.itemManager.itemCache.items = [.hidden: [old], .visible: [other]]
            app.imageCache.images = [old.info: templateIcon(offset: 3), other.info: templateIcon(offset: 15)]
            app.layoutManager.recordCurrentLayout(reason: "distinct black template icons")
            let saved = try stored()
            check(
                saved.items(for: .hidden).first?.imageHash != saved.items(for: .visible).first?.imageHash,
                "black template icons with different alpha masks have distinct fingerprints"
            )
            app.itemManager.itemCache.items = [.visible: [relaunched, other]]
            app.imageCache.images[relaunched.info] = templateIcon(offset: 3)
            app.layoutManager.performSetup()
            try await pause()
            check(app.itemManager.moves.contains(relaunched), "template icon relaunch restores without matching a different live icon")
        }

        // Composite captures must fingerprint the cropped icon, not the parent
        // buffer that contains different neighbors after an application relaunch.
        if scenario == nil || scenario == "cropped-image" {
            let app = fixture()
            let old = item("Snipaste-old-window")
            let relaunched = item("Snipaste-new-window")
            app.itemManager.itemCache.items = [.hidden: [old]]
            app.imageCache.images = [old.info: croppedIcon(parentWidth: 6, neighbor: 20)]
            app.layoutManager.recordCurrentLayout(reason: "hidden Snipaste")
            app.itemManager.itemCache.items = [.visible: [relaunched]]
            app.imageCache.images = [relaunched.info: croppedIcon(parentWidth: 8, neighbor: 80)]
            app.layoutManager.performSetup()
            try await pause()
            check(app.itemManager.moves.contains(relaunched), "identical cropped icons restore despite different composite buffers")
            check(try stored().items(for: .hidden).map(\.info) == [relaunched.info], "cropped icon fingerprint retains the hidden section")
        }

        // A manual edit must retain apps that are currently closed, and hashes
        // must survive a recording made before the image cache is populated.
        if scenario == nil || scenario == "closed" {
            let app = fixture()
            let closed = item("ChatGPT-old-window")
            let live = item("Live")
            app.itemManager.itemCache.items = [.hidden: [closed], .visible: [live]]
            app.imageCache.images = [closed.info: image(1), live.info: image(2)]
            app.layoutManager.recordCurrentLayout(reason: "initial")
            let hash = try stored().items(for: .visible).first?.imageHash
            app.itemManager.itemCache.items = [.visible: [live]]
            app.imageCache.images = [:]
            app.layoutManager.recordCurrentLayout(reason: "edit while ChatGPT is closed")
            check(try stored().items(for: .hidden).map(\.info) == [closed.info], "manual edit retains a closed app's hidden section")
            check(try stored().items(for: .visible).first?.imageHash == hash, "recording retains known fingerprints")
        }

        // A delayed capture remaps the window identity without changing the
        // item cache. Restoration must be explicitly scheduled after remapping.
        if scenario == nil || scenario == "relaunch" {
            let app = fixture()
            let old = item("ChatGPT-old-window")
            let relaunched = item("ChatGPT-new-window")
            app.itemManager.itemCache.items = [.hidden: [old]]
            app.imageCache.images = [old.info: image(3)]
            app.layoutManager.recordCurrentLayout(reason: "hidden ChatGPT")
            app.itemManager.itemCache.items = [.visible: [relaunched]]
            app.imageCache.images = [:]
            app.imageCache.captureImages = [relaunched.info: image(3)]
            app.imageCache.captureDelay = .seconds(1)
            app.layoutManager.performSetup()
            try await pause(2.6)
            check(app.itemManager.moves.contains(relaunched), "delayed identity resolution restores relaunched ChatGPT")
            check(try stored().items(for: .hidden).map(\.info) == [relaunched.info], "relaunch replaces the hidden identity without a visible duplicate")
        }

        // The first launch must save a fingerprint without opening settings.
        if scenario == nil || scenario == "initial" {
            let app = fixture()
            let original = item("Initial-window")
            app.itemManager.itemCache.items = [.hidden: [original]]
            app.imageCache.captureImages = [original.info: image(4)]
            app.layoutManager.performSetup()
            try await pause()
            check(try stored().items(for: .hidden).first?.imageHash != nil, "initial layout captures fingerprints without opening UI")
        }

        // Ambiguous icons and existing live identities must not be reassigned.
        if scenario == nil || scenario == "identical" {
            let app = fixture()
            let closed = item("Closed")
            let existing = item("Existing")
            let fresh = item("New")
            app.itemManager.itemCache.items = [.hidden: [closed], .visible: [existing]]
            app.imageCache.images = [closed.info: image(5), existing.info: image(5)]
            app.layoutManager.recordCurrentLayout(reason: "identical icons")
            app.itemManager.itemCache.items = [.visible: [existing, fresh]]
            app.imageCache.images[fresh.info] = image(5)
            app.layoutManager.performSetup()
            try await pause()
            check(app.itemManager.moves.isEmpty, "identical live icons do not claim a closed app's hidden identity")
        }

        // Two orphan icons also cannot select the first hidden entry arbitrarily.
        if scenario == nil || scenario == "orphans" {
            let app = fixture()
            let first = item("Closed-1")
            let second = item("Closed-2")
            let fresh = item("New")
            app.itemManager.itemCache.items = [.hidden: [first], .alwaysHidden: [second]]
            app.imageCache.images = [first.info: image(6), second.info: image(6)]
            app.layoutManager.recordCurrentLayout(reason: "ambiguous orphans")
            app.itemManager.itemCache.items = [.visible: [fresh]]
            app.imageCache.images = [fresh.info: image(6)]
            app.layoutManager.performSetup()
            try await pause()
            check(app.itemManager.moves.isEmpty, "multiple orphan matches leave a new item visible")
        }

        // A failed first capture must be recoverable when images arrive later.
        if scenario == nil || scenario == "late-image" {
            let app = fixture()
            let old = item("Old")
            let relaunched = item("Relaunched")
            app.itemManager.itemCache.items = [.hidden: [old]]
            app.imageCache.images = [old.info: image(7)]
            app.layoutManager.recordCurrentLayout(reason: "preferred hidden")
            app.itemManager.itemCache.items = [.visible: [relaunched]]
            app.imageCache.images = [:]
            app.layoutManager.performSetup()
            try await pause()
            app.imageCache.images = [relaunched.info: image(7)]
            try await pause()
            check(app.itemManager.moves.contains(relaunched), "later image publication recovers an unavailable first capture")
        }

        // A user's manual choice during capture supersedes orphan resolution.
        if scenario == nil || scenario == "manual-during-capture" {
            let app = fixture()
            let old = item("Old")
            let relaunched = item("Relaunched")
            app.itemManager.itemCache.items = [.hidden: [old]]
            app.imageCache.images = [old.info: image(8)]
            app.layoutManager.recordCurrentLayout(reason: "preferred hidden")
            app.itemManager.itemCache.items = [.visible: [relaunched]]
            app.imageCache.images = [:]
            app.imageCache.captureDelay = .seconds(1)
            app.imageCache.captureImages = [relaunched.info: image(8)]
            app.layoutManager.performSetup()
            try await pause(0.8)
            app.layoutManager.recordCurrentLayout(reason: "keep relaunched item visible")
            try await pause(1.8)
            check(app.itemManager.moves.isEmpty, "manual layout choice during capture is preserved")
        }

        // Image refreshes must not reset the failed-move limit.
        if scenario == nil || scenario == "failure-limit" {
            let app = fixture()
            let icon = item("Unmovable")
            app.itemManager.itemCache.items = [.hidden: [icon]]
            app.imageCache.images = [icon.info: image(9)]
            app.layoutManager.recordCurrentLayout(reason: "preferred hidden")
            app.itemManager.itemCache.items = [.visible: [icon]]
            app.itemManager.shouldFailMoves = true
            app.layoutManager.performSetup()
            try await pause(1.5)
            app.imageCache.images = [icon.info: image(10)]
            try await pause()
            check(app.itemManager.moves.count == 3, "changing image hashes do not bypass the restore failure limit")
        }

        // Both hidden sections must finish restoring despite the movement
        // cooldown, even if the recache publishes an identical value.
        if scenario == nil || scenario == "cooldown" {
            let app = fixture()
            let first = item("Hidden")
            let second = item("AlwaysHidden")
            app.itemManager.itemCache.items = [.hidden: [first], .alwaysHidden: [second]]
            app.layoutManager.recordCurrentLayout(reason: "preferred sections")
            app.itemManager.itemCache.items = [.visible: [first, second]]
            app.itemManager.cooldownEnd = .now.addingTimeInterval(1.4)
            ScreenCapture.permitted = false
            app.layoutManager.performSetup()
            try await pause(5.5)
            check(app.itemManager.itemCache.section(for: first) == .hidden, "restoration resumes after cooldown with unchanged cache")
            check(app.itemManager.itemCache.section(for: second) == .alwaysHidden, "restoration continues to the always-hidden section")
        }
    }
}

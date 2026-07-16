//
//  MenuBarLayoutManager.swift
//  Ice
//

import Cocoa
import Combine

/// Persists and restores the user's preferred menu bar item layout.
@MainActor
final class MenuBarLayoutManager {
    /// The shared app state.
    private weak var appState: AppState?

    /// The persisted layout configuration.
    private var configuration: MenuBarLayoutConfigurationV1?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// JSON encoder for persistence.
    private let encoder = JSONEncoder()

    /// JSON decoder for persistence.
    private let decoder = JSONDecoder()

    /// A Boolean value that indicates whether the manager is restoring layout.
    private var isRestoringLayout = false

    /// Creates a manager with the given app state.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Sets up the manager.
    func performSetup() {
        loadInitialState()
        configureCancellables()
    }

    /// Loads the persisted layout configuration.
    private func loadInitialState() {
        guard let data = Defaults.data(forKey: .menuBarLayoutConfigurationV1) else {
            return
        }
        do {
            configuration = try decoder.decode(MenuBarLayoutConfigurationV1.self, from: data)
            moveNewItemMarkerToHiddenSectionIfNeeded()
        } catch {
            Logger.layoutManager.error("Error decoding menu bar layout configuration: \(error)")
        }
    }

    /// Keeps newly discovered menu bar items in the Ice Bar by default.
    private func moveNewItemMarkerToHiddenSectionIfNeeded() {
        guard var configuration else {
            return
        }

        for section in MenuBarSection.Name.allCases {
            var items = configuration.items(for: section)
            items.removeAll { identity in
                identity.isNewItemMarker || identity.info == .iceIcon
            }
            configuration.setItems(items, for: section)
        }

        var hiddenItems = configuration.items(for: .hidden)
        hiddenItems.append(.newItems)
        configuration.setItems(hiddenItems, for: .hidden)

        self.configuration = configuration
        save()
    }

    /// Configures internal observers.
    private func configureCancellables() {
        guard let appState else {
            return
        }

        var c = Set<AnyCancellable>()

        appState.itemManager.$itemCache
            .removeDuplicates()
            .debounce(for: 0.5, scheduler: DispatchQueue.main)
            .sink { [weak self] cache in
                self?.handleCacheUpdate(cache)
            }
            .store(in: &c)

        cancellables = c
    }

    /// Persists the current configuration.
    private func save() {
        do {
            let data = try encoder.encode(configuration)
            Defaults.set(data, forKey: .menuBarLayoutConfigurationV1)
        } catch {
            Logger.layoutManager.error("Error encoding menu bar layout configuration: \(error)")
        }
    }

    /// Handles item cache changes.
    private func handleCacheUpdate(_ cache: MenuBarItemManager.ItemCache) {
        guard !cache.managedItems.isEmpty else {
            return
        }

        if configuration == nil {
            configuration = .defaultConfiguration(from: cache, identityProvider: persistentIdentity(for:))
            save()
            return
        }

        addNewItemsIfNeeded(from: cache)
        scheduleRestore(from: cache)
    }

    /// Records the current item cache as the preferred layout.
    func recordCurrentLayout(reason: String) {
        guard
            let appState,
            !appState.itemManager.itemCache.managedItems.isEmpty
        else {
            return
        }

        Logger.layoutManager.info("Recording menu bar layout (\(reason))")
        configuration = .defaultConfiguration(
            from: appState.itemManager.itemCache,
            identityProvider: persistentIdentity(for:)
        )
        save()
    }

    /// Adds newly discovered items to the persisted layout.
    private func addNewItemsIfNeeded(from cache: MenuBarItemManager.ItemCache) {
        guard var configuration else {
            return
        }

        var didChange = false
        for item in cache.managedItems where
            item.info != .iceIcon
                && !configurationContains(item, configuration: configuration)
        {
            insertNewItem(item, into: &configuration)
            didChange = true
        }

        if didChange {
            self.configuration = configuration
            save()
        }
    }

    /// Inserts a new item at the new-item marker, defaulting to the hidden section.
    private func insertNewItem(_ item: MenuBarItem, into configuration: inout MenuBarLayoutConfigurationV1) {
        let identity = persistentIdentity(for: item)
        var hiddenItems = configuration.items(for: .hidden)
        let insertIndex = hiddenItems.firstIndex(where: \.isNewItemMarker) ?? hiddenItems.endIndex
        hiddenItems.insert(identity, at: insertIndex)
        configuration.setItems(hiddenItems, for: .hidden)
        Logger.layoutManager.info("Added new menu bar item to preferred layout: \(item.logString)")
    }

    /// Returns whether the configuration already contains a matching item.
    private func configurationContains(
        _ item: MenuBarItem,
        configuration: MenuBarLayoutConfigurationV1
    ) -> Bool {
        configuration.allItems.contains { identityMatches($0, item: item) }
    }

    /// Schedules layout restoration for the given cache.
    private func scheduleRestore(from cache: MenuBarItemManager.ItemCache) {
        guard canRestoreLayout else {
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            await restoreLayout(from: cache)
        }
    }

    /// A Boolean value that indicates whether layout restoration is currently allowed.
    private var canRestoreLayout: Bool {
        guard
            let appState,
            !isRestoringLayout,
            !appState.itemManager.isMovingItem,
            !appState.itemManager.itemHasRecentlyMoved,
            !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
            !appState.navigationState.isSettingsPresented
                || appState.navigationState.settingsNavigationIdentifier != .menuBarLayout
        else {
            return false
        }
        return true
    }

    /// Restores the preferred layout from the given cache.
    private func restoreLayout(from cache: MenuBarItemManager.ItemCache) async {
        guard
            canRestoreLayout,
            let appState,
            let configuration,
            let move = nextMove(for: configuration, cache: cache)
        else {
            return
        }

        isRestoringLayout = true
        defer {
            isRestoringLayout = false
        }

        do {
            Logger.layoutManager.info("Restoring \(move.item.logString) to \(move.destination.logString)")
            try await appState.itemManager.slowMove(item: move.item, to: move.destination, timeout: .seconds(2))
            await appState.itemManager.cacheItemsIfNeeded(force: true)
        } catch {
            Logger.layoutManager.error("Error restoring menu bar layout: \(error)")
        }
    }

    /// Returns the next move needed to restore the layout.
    private func nextMove(
        for configuration: MenuBarLayoutConfigurationV1,
        cache: MenuBarItemManager.ItemCache
    ) -> (item: MenuBarItem, destination: MenuBarItemManager.MoveDestination)? {
        let allItems = MenuBarItem.getMenuBarItems(onScreenOnly: false, activeSpaceOnly: true)

        if
            let iceIcon = cache.managedItems.first(where: { $0.info == .iceIcon }),
            cache.managedItems(for: .visible).first != iceIcon,
            let hiddenControlItem = controlItem(.hidden, in: allItems)
        {
            return (iceIcon, .rightOfItem(hiddenControlItem))
        }

        for section in MenuBarSection.Name.allCases {
            let desired = configuration.items(for: section).filter { !$0.isNewItemMarker }
            for identity in desired {
                guard let item = item(matching: identity, in: cache.managedItems) else {
                    continue
                }
                if cache.section(for: item) != section {
                    return destination(for: item, identity: identity, in: section, desired: desired, cache: cache, allItems: allItems)
                        .map { (item, $0) }
                }
            }

            guard let misordered = firstMisorderedItem(in: section, desired: desired, cache: cache) else {
                continue
            }
            guard let destination = destination(
                for: misordered.item,
                identity: misordered.identity,
                in: section,
                desired: desired,
                cache: cache,
                allItems: allItems
            ) else {
                continue
            }
            return (misordered.item, destination)
        }

        return nil
    }

    /// Returns the first item whose actual order differs from the preferred order.
    private func firstMisorderedItem(
        in section: MenuBarSection.Name,
        desired: [MenuBarItemPersistentIdentity],
        cache: MenuBarItemManager.ItemCache
    ) -> (identity: MenuBarItemPersistentIdentity, item: MenuBarItem)? {
        let desiredItems = desired.compactMap { identity in
            item(matching: identity, in: cache.managedItems(for: section)).map { (identity, $0) }
        }
        let actualItems = cache.managedItems(for: section).filter { item in
            desiredItems.contains { identityMatches($0.0, item: item) }
        }

        for (desiredPair, actualItem) in zip(desiredItems, actualItems) where desiredPair.1 != actualItem {
            return desiredPair
        }
        return nil
    }

    /// Returns the move destination for an item in a target section.
    private func destination(
        for item: MenuBarItem,
        identity: MenuBarItemPersistentIdentity,
        in section: MenuBarSection.Name,
        desired: [MenuBarItemPersistentIdentity],
        cache: MenuBarItemManager.ItemCache,
        allItems: [MenuBarItem]
    ) -> MenuBarItemManager.MoveDestination? {
        guard let desiredIndex = desired.firstIndex(of: identity) else {
            return nil
        }

        for nextIdentity in desired[(desiredIndex + 1)...] {
            if let target = self.item(matching: nextIdentity, in: cache.managedItems(for: section)) {
                return .leftOfItem(target)
            }
        }

        for previousIdentity in desired[..<desiredIndex].reversed() {
            if let target = self.item(matching: previousIdentity, in: cache.managedItems(for: section)) {
                return .rightOfItem(target)
            }
        }

        return emptySectionDestination(for: section, allItems: allItems)
    }

    /// Returns the destination used when a target section is empty.
    private func emptySectionDestination(
        for section: MenuBarSection.Name,
        allItems: [MenuBarItem]
    ) -> MenuBarItemManager.MoveDestination? {
        switch section {
        case .visible:
            return controlItem(.hidden, in: allItems).map { .rightOfItem($0) }
        case .hidden:
            return controlItem(.hidden, in: allItems).map { .leftOfItem($0) }
        case .alwaysHidden:
            return controlItem(.alwaysHidden, in: allItems).map { .leftOfItem($0) }
        }
    }

    /// Returns a control item in the current menu bar items.
    private func controlItem(
        _ identifier: ControlItem.Identifier,
        in items: [MenuBarItem]
    ) -> MenuBarItem? {
        guard let appState else {
            return nil
        }

        let sectionName: MenuBarSection.Name = switch identifier {
        case .iceIcon:
            .visible
        case .hidden:
            .hidden
        case .alwaysHidden:
            .alwaysHidden
        }

        let section = appState.menuBarManager.section(withName: sectionName)
        return section.flatMap { items.firstIndex(matchingControlItem: $0.controlItem).map { items[$0] } }
            ?? items.first { $0.info.title == identifier.rawValue && $0.info.namespace == .ice }
    }

    /// Returns the item matching the given identity.
    private func item(
        matching identity: MenuBarItemPersistentIdentity,
        in items: [MenuBarItem]
    ) -> MenuBarItem? {
        items.first { $0.info == identity.info }
            ?? items.first { identityMatches(identity, item: $0) }
    }

    /// Returns whether an identity matches a menu bar item.
    private func identityMatches(
        _ identity: MenuBarItemPersistentIdentity,
        item: MenuBarItem
    ) -> Bool {
        if identity.info == item.info {
            return true
        }
        guard let imageHash = identity.imageHash else {
            return false
        }
        return imageHash == self.imageHash(for: item)
    }

    /// Returns the persistent identity for a menu bar item.
    private func persistentIdentity(for item: MenuBarItem) -> MenuBarItemPersistentIdentity {
        MenuBarItemPersistentIdentity(info: item.info, imageHash: imageHash(for: item))
    }

    /// Returns a lightweight image hash for the given item.
    private func imageHash(for item: MenuBarItem) -> String? {
        guard
            let image = appState?.imageCache.images[item.info],
            let data = image.dataProvider?.data,
            let pointer = CFDataGetBytePtr(data)
        else {
            return nil
        }

        let length = CFDataGetLength(data)
        guard length > 0 else {
            return nil
        }

        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        let stride = max(1, length / 512)

        hash ^= UInt64(image.width)
        hash &*= prime
        hash ^= UInt64(image.height)
        hash &*= prime

        var index = 0
        while index < length {
            hash ^= UInt64(pointer[index])
            hash &*= prime
            index += stride
        }

        return String(hash, radix: 16)
    }
}

private extension MenuBarItemPersistentIdentity {
    /// A Boolean value that indicates whether the identity is the new-item marker.
    var isNewItemMarker: Bool {
        info == .newItems
    }
}

private extension Logger {
    static let layoutManager = Logger(category: "MenuBarLayoutManager")
}

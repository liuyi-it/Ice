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

    /// Coalesces pending restores before a move starts.
    private var scheduledRestoreTask: Task<Void, Never>?

    /// A Boolean value that indicates whether orphan identity resolution is in progress.
    private var isResolvingOrphans = false

    /// Newly discovered infos awaiting an image before being classified.
    private var pendingIdentityInfos = Set<MenuBarItemInfo>()

    /// Number of consecutive failed restore moves per current item info.
    ///
    /// Some items cannot be moved by the system (e.g. items whose owning app is
    /// not responding), which would otherwise make the restore loop retry the
    /// same move forever, repeatedly hiding and warping the mouse cursor.
    private var restoreFailureCounts = [MenuBarItemInfo: Int]()

    /// The maximum number of consecutive restore failures before an item is
    /// skipped until the user manually drags it (which resets the counts).
    private let maxRestoreFailures = 3

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
            moveNewItemMarkerToVisibleSectionIfNeeded()
        } catch {
            Logger.layoutManager.error("Error decoding menu bar layout configuration: \(error)")
        }
    }

    /// Keeps newly discovered menu bar items in the visible section by default.
    private func moveNewItemMarkerToVisibleSectionIfNeeded() {
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

        var visibleItems = configuration.items(for: .visible)
        visibleItems.append(.newItems)
        configuration.setItems(visibleItems, for: .visible)

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

        appState.imageCache.$images
            .debounce(for: 0.5, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let appState = self.appState else {
                    return
                }
                self.updateIdentityConfiguration(from: appState.itemManager.itemCache)
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
        }

        addNewItemsIfNeeded(from: cache)
        scheduleRestore()
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
            identityProvider: persistentIdentity(for:),
            retainingMissingItemsFrom: configuration
        )
        save()
        // A manual drag resets the restore failure counters.
        restoreFailureCounts.removeAll()
        pendingIdentityInfos.removeAll()
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
            pendingIdentityInfos.insert(item.info)
            insertNewItem(item, into: &configuration)
            didChange = true
        }

        if didChange {
            self.configuration = configuration
            save()
        }

        updateIdentityConfiguration(from: cache)

        // Capture fingerprints while the original windows still exist, even
        // when no layout or Ice Bar UI is open. Later image publications also
        // retry identities whose first capture was unavailable.
        let itemsNeedingImages = cache.managedItems.filter { imageHash(for: $0) == nil }
        guard !itemsNeedingImages.isEmpty, ScreenCapture.cachedCheckPermissions(), !isResolvingOrphans else {
            return
        }
        isResolvingOrphans = true
        Task { [weak self] in
            defer { self?.isResolvingOrphans = false }
            await self?.resolveOrphanIdentities(unconfiguredItems: itemsNeedingImages)
        }
    }

    /// Reconciles identities against the latest cache and schedules any restored layout.
    private func updateIdentityConfiguration(from cache: MenuBarItemManager.ItemCache) {
        guard var configuration else {
            return
        }
        let identities = cache.managedItems.map(persistentIdentity(for:))
        let legacyHashes = cache.managedItems.reduce(into: [MenuBarItemInfo: String]()) { hashes, item in
            guard pendingIdentityInfos.contains(item.info), let hash = imageHash(for: item, contentOnly: false) else {
                return
            }
            hashes[item.info] = hash
        }
        if configuration.reconcileIdentities(identities, resolving: pendingIdentityInfos, legacyImageHashes: legacyHashes) {
            self.configuration = configuration
            save()
            // Identity changes do not change ItemCache. Its removeDuplicates()
            // observer therefore cannot trigger restoration for us.
            scheduleRestore()
        }
        pendingIdentityInfos.subtract(identities.filter { $0.imageHash != nil }.map(\.info))
    }

    /// Resolves orphan identities by capturing images for unconfigured items and
    /// matching them against stale configuration entries.
    ///
    /// When a match is found, the orphan identity is replaced with the new identity
    /// in its original section, and the duplicate entry (inserted by
    /// ``insertNewItem(_:into:)``) is removed from the visible section.
    private func resolveOrphanIdentities(
        unconfiguredItems: [MenuBarItem]
    ) async {
        guard let appState, ScreenCapture.cachedCheckPermissions() else {
            return
        }
        await appState.imageCache.captureImagesForIdentityResolution(items: unconfiguredItems)
        // Both the cache and user preference can change during capture.
        updateIdentityConfiguration(from: appState.itemManager.itemCache)
    }

    /// Inserts a new item at the new-item marker, defaulting to the visible section.
    private func insertNewItem(_ item: MenuBarItem, into configuration: inout MenuBarLayoutConfigurationV1) {
        let identity = persistentIdentity(for: item)
        var visibleItems = configuration.items(for: .visible)
        let insertIndex = visibleItems.firstIndex(where: \.isNewItemMarker) ?? visibleItems.endIndex
        visibleItems.insert(identity, at: insertIndex)
        configuration.setItems(visibleItems, for: .visible)
        Logger.layoutManager.info("Added new menu bar item to preferred layout: \(item.logString)")
    }

    /// Returns whether the configuration already contains a matching item.
    private func configurationContains(
        _ item: MenuBarItem,
        configuration: MenuBarLayoutConfigurationV1
    ) -> Bool {
        configuration.allItems.contains { identityMatches($0, item: item) }
    }

    /// Restores from the latest cache after a burst of item changes settles.
    private func scheduleRestore(delay: Duration = .milliseconds(200)) {
        scheduledRestoreTask?.cancel()
        scheduledRestoreTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let appState else {
                return
            }
            scheduledRestoreTask = nil
            await restoreLayout(from: appState.itemManager.itemCache)
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
        // Suppress restoration while the user is dragging a menu bar item.
        // The cooldown below only covers the 2 seconds after the drag ends, so
        // without this check a restore could start mid-drag, wait for the
        // Command key to be released, and then undo the user's drag.
        guard !appState.eventManager.isDraggingMenuBarItem else {
            return false
        }
        // Suppress restoration while the user's manual drag is still settling.
        // This prevents the restore loop from undoing the drag before the new
        // layout is recorded.
        if let dragEndDate = appState.eventManager.lastUserDragEndDate,
           Date.now.timeIntervalSince(dragEndDate) <= 2
        {
            return false
        }
        return true
    }

    /// Restores the preferred layout from the given cache.
    private func restoreLayout(from cache: MenuBarItemManager.ItemCache) async {
        guard
            let appState,
            let configuration,
            let move = nextMove(for: configuration, cache: cache)
        else {
            return
        }
        guard canRestoreLayout else {
            // The cache may remain unchanged after a drag or while settings are
            // open. Keep the pending move until restoration is allowed again.
            scheduleRestore(delay: .seconds(1))
            return
        }

        isRestoringLayout = true
        defer {
            isRestoringLayout = false
        }

        let identity = persistentIdentity(for: move.item)
        let previousItems = MenuBarSection.Name.allCases.map { cache.managedItems(for: $0).map(\.info) }

        do {
            Logger.layoutManager.info("Restoring \(move.item.logString) to \(move.destination.logString)")
            try await appState.itemManager.slowMove(item: move.item, to: move.destination, timeout: .seconds(2))
            await appState.itemManager.cacheItemsIfNeeded(force: true)
            let currentItems = MenuBarSection.Name.allCases.map {
                appState.itemManager.itemCache.managedItems(for: $0).map(\.info)
            }
            guard currentItems != previousItems else {
                // An already-correct physical destination can still disagree
                // with a stale/duplicate logical order. Do not retry forever.
                throw MenuBarItemManager.EventError(code: .couldNotComplete, item: move.item)
            }
            restoreFailureCounts.removeValue(forKey: identity.info)
            scheduleRestore(delay: .seconds(1))
        } catch is CancellationError {
            return
        } catch {
            Logger.layoutManager.error("Error restoring menu bar layout: \(error)")
            let failures = (restoreFailureCounts[identity.info] ?? 0) + 1
            restoreFailureCounts[identity.info] = failures
            if failures >= maxRestoreFailures {
                Logger.layoutManager.warning(
                    "Giving up restoring \(move.item.logString) after \(failures) consecutive failures"
                )
            }
            // Reaching one item's limit must not strand the remaining items.
            scheduleRestore()
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
            !hasReachedRestoreFailureLimit(for: MenuBarItemPersistentIdentity(info: iceIcon.info)),
            cache.managedItems(for: .visible).first != iceIcon,
            let hiddenControlItem = controlItem(.hidden, in: allItems)
        {
            return (iceIcon, .rightOfItem(hiddenControlItem))
        }

        for section in MenuBarSection.Name.allCases {
            let desired = configuration.items(for: section).filter { !$0.isNewItemMarker }
            for identity in desired {
                // Skip identities that have repeatedly failed to restore.
                guard !hasReachedRestoreFailureLimit(for: identity) else {
                    continue
                }
                guard let item = item(matching: identity, in: cache.managedItems), item.isMovable else {
                    continue
                }
                if cache.section(for: item) != section {
                    return destination(for: item, identity: identity, in: section, desired: desired, cache: cache, allItems: allItems)
                        .map { (item, $0) }
                }
            }
        }

        // Restore section membership before spending time on within-section
        // ordering. A visible ordering problem must not strand hidden apps.
        for section in MenuBarSection.Name.allCases {
            let desired = configuration.items(for: section).filter { !$0.isNewItemMarker }
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
        let desiredItems = desired
            .filter { !hasReachedRestoreFailureLimit(for: $0) }
            .compactMap { identity in
                item(matching: identity, in: cache.managedItems(for: section))
                    .flatMap { $0.isMovable ? (identity, $0) : nil }
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
    }

    /// Returns whether an identity matches a menu bar item.
    private func identityMatches(
        _ identity: MenuBarItemPersistentIdentity,
        item: MenuBarItem
    ) -> Bool {
        identity.info == item.info
    }

    /// Returns the persistent identity for a menu bar item.
    private func persistentIdentity(for item: MenuBarItem) -> MenuBarItemPersistentIdentity {
        MenuBarItemPersistentIdentity(info: item.info, imageHash: imageHash(for: item))
    }

    /// Returns whether layout restoration should stop retrying the given item.
    private func hasReachedRestoreFailureLimit(for identity: MenuBarItemPersistentIdentity) -> Bool {
        (restoreFailureCounts[identity.info] ?? 0) >= maxRestoreFailures
    }

    /// Returns a lightweight image hash for the given item.
    private func imageHash(for item: MenuBarItem, contentOnly: Bool = true) -> String? {
        guard let capturedImage = appState?.imageCache.images[item.info] else {
            return nil
        }
        // Composite captures include the full status window (33 points on a
        // notched display), while individual captures use the 22-point status
        // item content. Hash the same centered content in both cases.
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let height = contentOnly ? min(capturedImage.height, Int(NSStatusBar.system.thickness * scale)) : capturedImage.height
        guard
            let image = capturedImage.cropping(to: CGRect(
                x: 0,
                y: (capturedImage.height - height) / 2,
                width: capturedImage.width,
                height: height
            )),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        // Cropped images can retain the composite capture's data provider and
        // row stride. Render only this icon into a canonical buffer so neighbors,
        // capture groups, and source pixel formats cannot change its identity.
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else {
            return nil
        }
        let length = context.bytesPerRow * image.height
        let pointer = data.bindMemory(to: UInt8.self, capacity: length)

        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        hash ^= UInt64(image.width)
        hash &*= prime
        hash ^= UInt64(image.height)
        hash &*= prime

        // Hash every RGBA channel. A byte sampling stride divisible by four
        // would read only red, making black template icons indistinguishable
        // because their shape is encoded in alpha. Ignore any row padding.
        for row in 0..<image.height {
            let start = row * context.bytesPerRow
            for index in start..<(start + image.width * 4) {
                hash ^= UInt64(pointer[index])
                hash &*= prime
            }
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

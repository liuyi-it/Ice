//
//  MenuBarLayoutConfiguration.swift
//  Ice
//

import Foundation

/// A persisted menu bar layout.
struct MenuBarLayoutConfigurationV1: Codable, Equatable {
    /// The ordered item identifiers for each section.
    var sections: [Section]
}

extension MenuBarLayoutConfigurationV1 {
    /// A persisted section layout.
    struct Section: Codable, Equatable {
        /// The section name.
        var name: MenuBarSection.Name

        /// The ordered item identifiers in the section.
        var items: [MenuBarItemPersistentIdentity]

        /// Creates a section with the given name and items.
        init(name: MenuBarSection.Name, items: [MenuBarItemPersistentIdentity]) {
            self.name = name
            self.items = items
        }
    }
}

/// A stable-enough identifier for a menu bar item across launches.
struct MenuBarItemPersistentIdentity: Codable, Equatable, Hashable {
    /// The item info reported by the current system.
    var info: MenuBarItemInfo

    /// A lightweight hash of the item's captured image, if available.
    var imageHash: String?

    /// Creates an identity with the given info and image hash.
    init(info: MenuBarItemInfo, imageHash: String? = nil) {
        self.info = info
        self.imageHash = imageHash
    }
}

extension MenuBarItemPersistentIdentity {
    /// The special identity that marks where new menu bar items should appear.
    static let newItems = MenuBarItemPersistentIdentity(info: .newItems)
}

// MARK: - MenuBarLayoutConfigurationV1 Helpers

extension MenuBarLayoutConfigurationV1 {
    /// Returns the items for the given section.
    func items(for section: MenuBarSection.Name) -> [MenuBarItemPersistentIdentity] {
        sections.first { $0.name == section }?.items ?? []
    }

    /// Sets the items for the given section.
    mutating func setItems(_ items: [MenuBarItemPersistentIdentity], for section: MenuBarSection.Name) {
        if let index = sections.firstIndex(where: { $0.name == section }) {
            sections[index].items = items
        } else {
            sections.append(Section(name: section, items: items))
        }
    }

    /// The item identifiers in all sections.
    var allItems: [MenuBarItemPersistentIdentity] {
        sections.flatMap(\.items)
    }

    /// A default configuration created from an item cache.
    static func defaultConfiguration(
        from cache: MenuBarItemManager.ItemCache,
        identityProvider: (MenuBarItem) -> MenuBarItemPersistentIdentity,
        retainingMissingItemsFrom previous: MenuBarLayoutConfigurationV1? = nil
    ) -> MenuBarLayoutConfigurationV1 {
        let sections = MenuBarSection.Name.allCases.map { section in
            var items = cache.managedItems(for: section)
                .filter { $0.info != .iceIcon }
                .map { item in
                    var identity = identityProvider(item)
                    if identity.imageHash == nil {
                        identity.imageHash = previous?.allItems.first { $0.info == identity.info }?.imageHash
                    }
                    return identity
                }
            if section == .visible {
                items.append(.newItems)
            }
            return Section(name: section, items: items)
        }
        var configuration = MenuBarLayoutConfigurationV1(sections: sections)
        let currentInfos = Set(configuration.allItems.map(\.info))
        if let previous {
            for section in MenuBarSection.Name.allCases {
                let oldItems = previous.items(for: section)
                var items = configuration.items(for: section)
                // Insert missing entries before their next surviving neighbor,
                // preserving the preferred section and relative order.
                for (index, identity) in oldItems.enumerated() where
                    identity.info != .newItems && identity.info != .iceIcon && !currentInfos.contains(identity.info)
                {
                    let nextInfos = Set(oldItems[(index + 1)...].map(\.info))
                    let insertionIndex = items.firstIndex { nextInfos.contains($0.info) }
                        ?? items.firstIndex { $0.info == .newItems }
                        ?? items.endIndex
                    items.insert(identity, at: insertionIndex)
                }
                configuration.setItems(items, for: section)
            }
        }
        return configuration
    }

    /// Refreshes known image hashes and transfers only unique orphan matches.
    /// Exact live infos take priority, even when two apps use identical icons.
    mutating func reconcileIdentities(
        _ current: [MenuBarItemPersistentIdentity],
        resolving pendingInfos: Set<MenuBarItemInfo>
    ) -> Bool {
        let previous = self
        let currentInfos = Set(current.map(\.info))
        let orphans = allItems.filter { $0.info != .newItems && !currentInfos.contains($0.info) }
        for identity in current {
            guard let imageHash = identity.imageHash else {
                continue
            }
            let matches = orphans.filter { $0.imageHash == imageHash }
            let liveMatches = current.filter { $0.imageHash == imageHash }
            if pendingInfos.contains(identity.info), matches.count == 1, liveMatches.count == 1,
               let orphan = matches.first
            {
                // Remove the provisional new-item entry before replacing the
                // original entry, including when both are in the same section.
                for index in sections.indices {
                    sections[index].items.removeAll { $0.info == identity.info }
                    if let orphanIndex = sections[index].items.firstIndex(of: orphan) {
                        sections[index].items[orphanIndex] = identity
                    }
                }
            } else {
                for sectionIndex in sections.indices {
                    for itemIndex in sections[sectionIndex].items.indices where
                        sections[sectionIndex].items[itemIndex].info == identity.info
                    {
                        sections[sectionIndex].items[itemIndex].imageHash = imageHash
                    }
                }
            }
        }
        return self != previous
    }
}

// MARK: - MenuBarSection.Name: Codable

extension MenuBarSection.Name: Codable {
    private enum CodingValue: String, Codable {
        case visible
        case hidden
        case alwaysHidden
    }

    private var codingValue: CodingValue {
        switch self {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(CodingValue.self) {
        case .visible:
            self = .visible
        case .hidden:
            self = .hidden
        case .alwaysHidden:
            self = .alwaysHidden
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(codingValue)
    }
}

//
//  SettingsView.swift
//  Ice
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var navigationState: AppNavigationState
    @Environment(\.sidebarRowSize) var sidebarRowSize

    // 强制 sidebar 始终展开：macOS 窗口状态恢复会把上次会话的折叠状态带回来，
    // 配合 canCollapse=false 的 swizzle 实现"永远展开、不可折叠"。
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var sidebarWidth: CGFloat {
        switch sidebarRowSize {
        case .small: 190
        case .medium: 210
        case .large: 230
        @unknown default: 210
        }
    }

    private var sidebarItemHeight: CGFloat {
        switch sidebarRowSize {
        case .small: 26
        case .medium: 32
        case .large: 34
        @unknown default: 32
        }
    }

    private var sidebarItemFontSize: CGFloat {
        switch sidebarRowSize {
        case .small: 13
        case .medium: 15
        case .large: 16
        @unknown default: 15
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle(navigationState.settingsNavigationIdentifier.localized)
        .onAppear {
            // 覆盖窗口状态恢复带回来的折叠状态。
            columnVisibility = .all
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $navigationState.settingsNavigationIdentifier) {
            Section {
                ForEach(SettingsNavigationIdentifier.allCases, id: \.self) { identifier in
                    sidebarItem(for: identifier)
                }
            } header: {
                Text("Ice")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.vertical, 5)
            }
            .collapsible(false)
        }
        .scrollDisabled(true)
        .removeSidebarToggle()
        .navigationSplitViewColumnWidth(sidebarWidth)
    }

    @ViewBuilder
    private var detailView: some View {
        switch navigationState.settingsNavigationIdentifier {
        case .general:
            GeneralSettingsPane()
        case .menuBarLayout:
            MenuBarLayoutSettingsPane()
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane()
        case .hotkeys:
            HotkeysSettingsPane()
        case .advanced:
            AdvancedSettingsPane()
        case .about:
            AboutSettingsPane()
        }
    }

    @ViewBuilder
    private func sidebarItem(for identifier: SettingsNavigationIdentifier) -> some View {
        Label {
            Text(identifier.localized)
                .font(.system(size: sidebarItemFontSize))
                .padding(.leading, 2)
        } icon: {
            icon(for: identifier).view
        }
        .frame(height: sidebarItemHeight)
    }

    private func icon(for identifier: SettingsNavigationIdentifier) -> IconResource {
        switch identifier {
        case .general: .systemSymbol("gearshape")
        case .menuBarLayout: .systemSymbol("rectangle.topthird.inset.filled")
        case .menuBarAppearance: .systemSymbol("swatchpalette")
        case .hotkeys: .systemSymbol("keyboard")
        case .advanced: .systemSymbol("gearshape.2")
        case .about: .assetCatalog(.iceCubeStroke)
        }
    }
}

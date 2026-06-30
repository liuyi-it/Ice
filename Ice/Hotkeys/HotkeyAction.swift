//
//  HotkeyAction.swift
//  Ice
//

enum HotkeyAction: String, Codable, CaseIterable {
    // 菜单栏分区
    case toggleHiddenSection = "ToggleHiddenSection"
    case toggleAlwaysHiddenSection = "ToggleAlwaysHiddenSection"

    // 菜单栏项目
    case searchMenuBarItems = "SearchMenuBarItems"

    // 其他
    case enableIceBar = "EnableIceBar"
    case showSectionDividers = "ShowSectionDividers"
    case toggleApplicationMenus = "ToggleApplicationMenus"

    @MainActor
    func perform(appState: AppState) async {
        switch self {
        case .toggleHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            section.toggle()
            // 防止分区在鼠标移动后自动重新隐藏。
            if !section.isHidden {
                appState.preventShowOnHover()
            }
        case .toggleAlwaysHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .alwaysHidden) else {
                return
            }
            section.toggle()
            // 防止分区在鼠标移动后自动重新隐藏。
            if !section.isHidden {
                appState.preventShowOnHover()
            }
        case .searchMenuBarItems:
            await appState.menuBarManager.searchPanel.toggle()
        case .enableIceBar:
            appState.settingsManager.generalSettingsManager.useIceBar.toggle()
        case .showSectionDividers:
            appState.settingsManager.advancedSettingsManager.showSectionDividers.toggle()
        case .toggleApplicationMenus:
            appState.menuBarManager.toggleApplicationMenus()
        }
    }
}

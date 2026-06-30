//
//  MenuBarSection.swift
//  Ice
//

import Cocoa

/// 菜单栏分区
@MainActor
final class MenuBarSection {
    /// 菜单栏分区名称
    enum Name: CaseIterable {
        case visible
        case hidden
        case alwaysHidden

        /// 界面显示字符串
        var displayString: String {
            switch self {
            case .visible: "显示"
            case .hidden: "隐藏"
            case .alwaysHidden: "始终隐藏"
            }
        }

        /// 日志用字符串
        var logString: String {
            switch self {
            case .visible: "visible section"
            case .hidden: "hidden section"
            case .alwaysHidden: "always-hidden section"
            }
        }
    }

    /// 分区名称
    let name: Name

    /// 分区控制项
    let controlItem: ControlItem

    /// 应用全局状态
    private weak var appState: AppState?

    /// 自动隐藏定时器
    private var rehideTimer: Timer?

    /// 事件监听器，当鼠标移出菜单栏时启动自动隐藏定时器
    private var rehideMonitor: UniversalEventMonitor?

    /// 是否使用 Ice Bar
    private var useIceBar: Bool {
        appState?.settingsManager.generalSettingsManager.useIceBar ?? false
    }

    /// 菜单栏管理器的 Ice Bar 面板弱引用
    private weak var iceBarPanel: IceBarPanel? {
        appState?.menuBarManager.iceBarPanel
    }

    /// 显示 Ice Bar 的最佳屏幕
    private weak var screenForIceBar: NSScreen? {
        guard let appState else {
            return nil
        }
        if appState.isActiveSpaceFullscreen {
            return NSScreen.screenWithMouse ?? NSScreen.main
        } else {
            return NSScreen.main
        }
    }

    /// 分区是否已隐藏
    var isHidden: Bool {
        if useIceBar {
            if controlItem.state == .showItems {
                return false
            }
            switch name {
            case .visible, .hidden:
                return iceBarPanel?.currentSection != .hidden
            case .alwaysHidden:
                return iceBarPanel?.currentSection != .alwaysHidden
            }
        }
        switch name {
        case .visible, .hidden:
            if iceBarPanel?.currentSection == .hidden {
                return false
            }
            return controlItem.state == .hideItems
        case .alwaysHidden:
            if iceBarPanel?.currentSection == .alwaysHidden {
                return false
            }
            return controlItem.state == .hideItems
        }
    }

    /// 分区是否已启用
    var isEnabled: Bool {
        if case .visible = name {
            // 显示分区始终启用
            return true
        }
        return controlItem.isAddedToMenuBar
    }

    /// 使用指定名称、控制项和应用状态创建分区
    init(name: Name, controlItem: ControlItem, appState: AppState) {
        self.name = name
        self.controlItem = controlItem
        self.appState = appState
    }

    /// 使用指定名称和应用状态创建分区
    convenience init(name: Name, appState: AppState) {
        let controlItem = switch name {
        case .visible:
            ControlItem(identifier: .iceIcon, appState: appState)
        case .hidden:
            ControlItem(identifier: .hidden, appState: appState)
        case .alwaysHidden:
            ControlItem(identifier: .alwaysHidden, appState: appState)
        }
        self.init(name: name, controlItem: controlItem, appState: appState)
    }

    /// 显示分区
    func show() {
        guard
            let appState,
            isHidden
        else {
            return
        }
        guard controlItem.isAddedToMenuBar else {
            // 分区已禁用
            // TODO: 可以用isEnabled来做这个检查吗？
            return
        }
        switch name {
        case .visible where useIceBar, .hidden where useIceBar:
            Task {
                if let screenForIceBar {
                    await iceBarPanel?.show(section: .hidden, on: screenForIceBar)
                }
                for section in appState.menuBarManager.sections {
                    section.controlItem.state = .hideItems
                }
            }
        case .alwaysHidden where useIceBar:
            Task {
                if let screenForIceBar {
                    await iceBarPanel?.show(section: .alwaysHidden, on: screenForIceBar)
                }
                for section in appState.menuBarManager.sections {
                    section.controlItem.state = .hideItems
                }
            }
        case .visible:
            iceBarPanel?.close()
            guard let hiddenSection = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            controlItem.state = .showItems
            hiddenSection.controlItem.state = .showItems
        case .hidden:
            iceBarPanel?.close()
            guard let visibleSection = appState.menuBarManager.section(withName: .visible) else {
                return
            }
            controlItem.state = .showItems
            visibleSection.controlItem.state = .showItems
        case .alwaysHidden:
            iceBarPanel?.close()
            guard
                let hiddenSection = appState.menuBarManager.section(withName: .hidden),
                let visibleSection = appState.menuBarManager.section(withName: .visible)
            else {
                return
            }
            controlItem.state = .showItems
            hiddenSection.controlItem.state = .showItems
            visibleSection.controlItem.state = .showItems
        }
        startRehideChecks()
    }

    /// 隐藏分区
    func hide() {
        guard
            let appState,
            !isHidden
        else {
            return
        }
        iceBarPanel?.close()
        switch name {
        case _ where useIceBar:
            for section in appState.menuBarManager.sections {
                section.controlItem.state = .hideItems
            }
        case .visible:
            guard
                let hiddenSection = appState.menuBarManager.section(withName: .hidden),
                let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
            else {
                return
            }
            controlItem.state = .hideItems
            hiddenSection.controlItem.state = .hideItems
            alwaysHiddenSection.controlItem.state = .hideItems
        case .hidden:
            guard
                let visibleSection = appState.menuBarManager.section(withName: .visible),
                let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
            else {
                return
            }
            controlItem.state = .hideItems
            visibleSection.controlItem.state = .hideItems
            alwaysHiddenSection.controlItem.state = .hideItems
        case .alwaysHidden:
            controlItem.state = .hideItems
        }
        appState.allowShowOnHover()
        stopRehideChecks()
    }

    /// 切换分区显示状态
    func toggle() {
        if isHidden {
            show()
        } else {
            hide()
        }
    }

    /// 启动自动隐藏检查
    private func startRehideChecks() {
        rehideTimer?.invalidate()
        rehideMonitor?.stop()

        guard
            let appState,
            appState.settingsManager.generalSettingsManager.autoRehide,
            case .timed = appState.settingsManager.generalSettingsManager.rehideStrategy
        else {
            return
        }

        rehideMonitor = UniversalEventMonitor(mask: .mouseMoved) { [weak self] event in
            guard
                let self,
                let screen = NSScreen.main
            else {
                return event
            }
            if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                if rehideTimer == nil {
                    rehideTimer = .scheduledTimer(
                        withTimeInterval: appState.settingsManager.generalSettingsManager.rehideInterval,
                        repeats: false
                    ) { [weak self] _ in
                        guard
                            let self,
                            let screen = NSScreen.main
                        else {
                            return
                        }
                        if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                            Task {
                                await self.hide()
                            }
                        } else {
                            Task {
                                await self.startRehideChecks()
                            }
                        }
                    }
                }
            } else {
                rehideTimer?.invalidate()
                rehideTimer = nil
            }
            return event
        }

        rehideMonitor?.start()
    }

    /// 停止自动隐藏检查
    private func stopRehideChecks() {
        rehideTimer?.invalidate()
        rehideMonitor?.stop()
        rehideTimer = nil
        rehideMonitor = nil
    }
}

// MARK: MenuBarSection: 绑定扩展
extension MenuBarSection: BindingExposable { }

// MARK: - 日志器
private extension Logger {
    static let menuBarSection = Logger(category: "MenuBarSection")
}

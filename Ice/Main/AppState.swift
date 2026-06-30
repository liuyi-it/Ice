//
//  AppState.swift
//  Ice
//

import Combine
import SwiftUI

/// 应用全局状态模型
@MainActor
final class AppState: ObservableObject {
    /// 当前工作区是否处于全屏模式
    @Published private(set) var isActiveSpaceFullscreen = Bridging.isSpaceFullscreen(Bridging.activeSpaceID)

    /// 菜单栏外观管理器
    private(set) lazy var appearanceManager = MenuBarAppearanceManager(appState: self)

    /// 应用事件管理器
    private(set) lazy var eventManager = EventManager(appState: self)

    /// 菜单栏项目管理器
    private(set) lazy var itemManager = MenuBarItemManager(appState: self)

    /// 菜单栏布局管理器
    private(set) lazy var layoutManager = MenuBarLayoutManager(appState: self)

    /// 菜单栏状态管理器
    private(set) lazy var menuBarManager = MenuBarManager(appState: self)

    /// 应用权限管理器
    private(set) lazy var permissionsManager = PermissionsManager(appState: self)

    /// 应用设置管理器
    private(set) lazy var settingsManager = SettingsManager(appState: self)

    /// 应用更新管理器
    private(set) lazy var updatesManager = UpdatesManager(appState: self)

    /// 用户通知管理器
    private(set) lazy var userNotificationManager = UserNotificationManager(appState: self)

    /// 菜单栏项目图标全局缓存
    private(set) lazy var imageCache = MenuBarItemImageCache(appState: self)

    /// 菜单栏项目间距管理器
    let spacingManager = MenuBarItemSpacingManager()

    /// 应用全局导航状态
    let navigationState = AppNavigationState()

    /// 应用快捷键注册表
    nonisolated let hotkeyRegistry = HotkeyRegistry()

    /// 应用代理
    private(set) weak var appDelegate: AppDelegate?

    /// 设置窗口
    private(set) weak var settingsWindow: NSWindow?

    /// 权限申请窗口
    private(set) weak var permissionsWindow: NSWindow?

    /// 是否禁止"悬停显示"功能
    private(set) var isShowOnHoverPrevented = false

    /// 内部观察者存储容器
    private var cancellables = Set<AnyCancellable>()

    /// 应用是否运行在SwiftUI预览模式下
    let isPreview: Bool = {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let key = "XCODE_RUNNING_FOR_PREVIEWS"
        return environment[key] != nil
        #else
        return false
        #endif
    }()

    /// 应用是否可以在后台设置光标样式
    var setsCursorInBackground: Bool {
        get { Bridging.getConnectionProperty(forKey: "SetsCursorInBackground") as? Bool ?? false }
        set { Bridging.setConnectionProperty(newValue, forKey: "SetsCursorInBackground") }
    }

    /// 配置应用状态的内部观察者
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        Publishers.Merge3(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                .mapToVoid(),
            // 最前端应用变化可能表示工作区在不同显示器之间切换，这种情况会被NSWorkspace.activeSpaceDidChangeNotification忽略
            NSWorkspace.shared
                .publisher(for: \.frontmostApplication)
                .mapToVoid(),
            // 从其他工作区点击进入全屏工作区的情况也会被忽略
            UniversalEventMonitor
                .publisher(for: .leftMouseDown)
                .delay(for: 0.1, scheduler: DispatchQueue.main)
                .mapToVoid()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else {
                return
            }
            isActiveSpaceFullscreen = Bridging.isSpaceFullscreen(Bridging.activeSpaceID)
        }
        .store(in: &c)

        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frontmostApplication in
                guard let self else {
                    return
                }
                navigationState.isAppFrontmost = frontmostApplication == .current
            }
            .store(in: &c)

        if let settingsWindow {
            settingsWindow.publisher(for: \.isVisible)
                .debounce(for: 0.05, scheduler: DispatchQueue.main)
                .sink { [weak self] isVisible in
                    guard let self else {
                        return
                    }
                    navigationState.isSettingsPresented = isVisible
                }
                .store(in: &c)
        }

        Publishers.Merge(
            navigationState.$isAppFrontmost,
            navigationState.$isSettingsPresented
        )
        .debounce(for: 0.1, scheduler: DispatchQueue.main)
        .sink { [weak self] shouldUpdate in
            guard
                let self,
                shouldUpdate
            else {
                return
            }
            Task.detached {
                if ScreenCapture.cachedCheckPermissions(reset: true) {
                    await self.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
                }
            }
        }
        .store(in: &c)

        menuBarManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        permissionsManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        settingsManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        updatesManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }

    /// 初始化应用状态
    func performSetup() {
        configureCancellables()
        permissionsManager.stopAllChecks()
        menuBarManager.performSetup()
        appearanceManager.performSetup()
        eventManager.performSetup()
        settingsManager.performSetup()
        itemManager.performSetup()
        layoutManager.performSetup()
        imageCache.performSetup()
        updatesManager.performSetup()
        userNotificationManager.performSetup()
    }

    /// 为应用状态设置代理
    func assignAppDelegate(_ appDelegate: AppDelegate) {
        guard self.appDelegate == nil else {
            Logger.appState.warning("Multiple attempts made to assign app delegate")
            return
        }
        self.appDelegate = appDelegate
    }

    /// 为应用状态设置设置窗口
    func assignSettingsWindow(_ window: NSWindow) {
        guard window.identifier?.rawValue == Constants.settingsWindowID else {
            Logger.appState.warning("Window \(window.identifier?.rawValue ?? "<NIL>") is not the settings window!")
            return
        }
        settingsWindow = window
        configureCancellables()
    }

    /// 为应用状态设置权限申请窗口
    func assignPermissionsWindow(_ window: NSWindow) {
        guard window.identifier?.rawValue == Constants.permissionsWindowID else {
            Logger.appState.warning("Window \(window.identifier?.rawValue ?? "<NIL>") is not the permissions window!")
            return
        }
        permissionsWindow = window
        configureCancellables()
    }

    /// 打开设置窗口
    func openSettingsWindow() {
        with(EnvironmentValues()) { environment in
            environment.openWindow(id: Constants.settingsWindowID)
        }
    }

    /// 关闭设置窗口
    func dismissSettingsWindow() {
        with(EnvironmentValues()) { environment in
            environment.dismissWindow(id: Constants.settingsWindowID)
        }
    }

    /// 打开权限申请窗口
    func openPermissionsWindow() {
        with(EnvironmentValues()) { environment in
            environment.openWindow(id: Constants.permissionsWindowID)
        }
    }

    /// 关闭权限申请窗口
    func dismissPermissionsWindow() {
        with(EnvironmentValues()) { environment in
            environment.dismissWindow(id: Constants.permissionsWindowID)
        }
    }

    /// 激活应用并设置激活策略
    func activate(withPolicy policy: NSApplication.ActivationPolicy) {
        // 在内部上下文中存储应用是否已经激活过的状态，保持隔离
        enum Context {
            static let hasActivated = ObjectStorage<Bool>()
        }

        func activate() {
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                NSRunningApplication.current.activate(from: frontApp)
            } else {
                NSApp.activate()
            }
            NSApp.setActivationPolicy(policy)
        }

        if Context.hasActivated.value(for: self) == true {
            activate()
        } else {
            Context.hasActivated.set(true, for: self)
            Logger.appState.debug("First time activating app, so going through Dock")
            // 特殊处理，确保应用首次能够正常激活
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                activate()
            }
        }
    }

    /// 停用应用并设置激活策略
    func deactivate(withPolicy policy: NSApplication.ActivationPolicy) {
        if let nextApp = NSWorkspace.shared.runningApplications.first(where: { $0 != .current }) {
            NSApp.yieldActivation(to: nextApp)
        } else {
            NSApp.deactivate()
        }
        NSApp.setActivationPolicy(policy)
    }

    /// 禁止"悬停显示"功能
    func preventShowOnHover() {
        isShowOnHoverPrevented = true
    }

    /// 允许"悬停显示"功能
    func allowShowOnHover() {
        isShowOnHoverPrevented = false
    }
}

// MARK: AppState: 绑定扩展
extension AppState: BindingExposable { }

// MARK: - 日志器
private extension Logger {
    /// 应用状态专用日志器
    static let appState = Logger(category: "AppState")
}

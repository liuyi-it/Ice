//
//  MenuBarAppearanceManager.swift
//  Ice
//

import Cocoa
import Combine

/// 菜单栏外观管理器
@MainActor
final class MenuBarAppearanceManager: ObservableObject {
    /// 当前菜单栏外观配置
    @Published var configuration: MenuBarAppearanceConfigurationV2 = .defaultConfiguration

    /// 当前预览的部分配置
    @Published var previewConfiguration: MenuBarAppearancePartialConfiguration?

    /// 应用全局状态
    private weak var appState: AppState?

    /// UserDefaults 编码器
    private let encoder = JSONEncoder()

    /// UserDefaults 解码器
    private let decoder = JSONDecoder()

    /// 内部观察者存储容器
    private var cancellables = Set<AnyCancellable>()

    /// 当前管理的菜单栏覆盖面板
    private(set) var overlayPanels = Set<MenuBarOverlayPanel>()

    /// 菜单栏缩进量（如果配置要求的话）
    let menuBarInsetAmount: CGFloat = 5

    /// 使用指定应用状态创建管理器
    init(appState: AppState) {
        self.appState = appState
    }

    /// 执行管理器初始化设置
    func performSetup() {
        loadInitialState()
        configureCancellables()
    }

    /// 加载配置初始值
    private func loadInitialState() {
        do {
            if let data = Defaults.data(forKey: .menuBarAppearanceConfigurationV2) {
                configuration = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: data)
            }
        } catch {
            Logger.appearanceManager.error("Error decoding configuration: \(error)")
        }
    }

    /// 配置管理器内部观察者
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                // Capture the old screen set before popping: the previous
                // comparison ran after the set was already emptied, making it
                // always true and needlessly recreating every panel.
                let oldScreens = Set(overlayPanels.map { $0.owningScreen })
                while let panel = overlayPanels.popFirst() {
                    panel.teardown()
                    panel.orderOut(self)
                }
                if oldScreens != Set(NSScreen.screens) {
                    configureOverlayPanels(with: configuration)
                }
            }
            .store(in: &c)

        $configuration
            .encode(encoder: encoder)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding configuration: \(error)")
                }
            } receiveValue: { data in
                Defaults.set(data, forKey: .menuBarAppearanceConfigurationV2)
            }
            .store(in: &c)

        $configuration
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] configuration in
                guard let self else {
                    return
                }
                // 覆盖面板可能还没有配置。由于管理器的一些属性可能需要它们，现在尝试配置。
                if overlayPanels.isEmpty {
                    configureOverlayPanels(with: configuration)
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// 检查指定配置是否需要覆盖面板
    private func needsOverlayPanels(for configuration: MenuBarAppearanceConfigurationV2) -> Bool {
        let current = configuration.current
        if current.hasShadow {
            return true
        }
        if current.hasBorder {
            return true
        }
        if configuration.shapeKind != .none {
            return true
        }
        if current.tintKind != .none {
            return true
        }
        return false
    }

    /// 根据配置要求配置管理器的覆盖面板
    private func configureOverlayPanels(with configuration: MenuBarAppearanceConfigurationV2) {
        guard
            let appState,
            needsOverlayPanels(for: configuration)
        else {
            while let panel = overlayPanels.popFirst() {
                panel.teardown()
                panel.close()
            }
            return
        }

        var overlayPanels = Set<MenuBarOverlayPanel>()
        for screen in NSScreen.screens {
            let panel = MenuBarOverlayPanel(appState: appState, owningScreen: screen)
            overlayPanels.insert(panel)
            panel.needsShow = true
        }

        self.overlayPanels = overlayPanels
    }

    /// 为所有覆盖面板设置是否正在拖拽菜单项的状态
    func setIsDraggingMenuBarItem(_ isDragging: Bool) {
        for panel in overlayPanels {
            panel.isDraggingMenuBarItem = isDragging
        }
    }
}

// MARK: MenuBarAppearanceManager: 绑定扩展
extension MenuBarAppearanceManager: BindingExposable { }

// MARK: - 日志器
private extension Logger {
    /// 菜单栏外观管理器专用日志器
    static let appearanceManager = Logger(category: "MenuBarAppearanceManager")
}

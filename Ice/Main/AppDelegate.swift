//
//  AppDelegate.swift
//  Ice
//

import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appState: AppState?

    // MARK: NSApplicationDelegate 代理方法

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let appState else {
            Logger.appDelegate.warning("Missing app state in applicationWillFinishLaunching")
            return
        }

        // 将代理赋值给共享应用状态
        appState.assignAppDelegate(self)

        // 允许应用在后台设置光标样式
        appState.setsCursorInBackground = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let appState else {
            Logger.appDelegate.warning("Missing app state in applicationDidFinishLaunching")
            return
        }

        // 关闭所有窗口
        appState.dismissSettingsWindow()
        appState.dismissPermissionsWindow()

        // 隐藏主菜单以节省菜单栏空间
        if let mainMenu = NSApp.mainMenu {
            for item in mainMenu.items {
                item.isHidden = true
            }
        }

        // 短暂延迟后执行初始化，确保设置窗口已完成赋值
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard !appState.isPreview else {
                return
            }
            appState.permissionsManager.refreshPermissions()
            // 如果已获得所需权限则初始化应用状态，否则打开权限申请窗口
            switch appState.permissionsManager.permissionsState {
            case .hasAllPermissions, .hasRequiredPermissions:
                appState.performSetup()
            case .missingPermissions:
                appState.activate(withPolicy: .regular)
                appState.openPermissionsWindow()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 所有窗口关闭时停用应用并设置为辅助程序模式
        appState?.deactivate(withPolicy: .accessory)
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        appState?.permissionsManager.refreshPermissions()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: 其他方法

    /// 为代理设置应用状态
    func assignAppState(_ appState: AppState) {
        guard self.appState == nil else {
            Logger.appDelegate.warning("Multiple attempts made to assign app state")
            return
        }
        self.appState = appState
    }

    /// 打开设置窗口并激活应用
    @objc func openSettingsWindow() {
        guard let appState else {
            Logger.appDelegate.error("Failed to open settings window")
            return
        }
        // 短暂延迟提升操作可靠性
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            appState.activate(withPolicy: .regular, throughDock: true) {
                appState.openSettingsWindow()
            }
        }
    }
}

// MARK: - 日志器
private extension Logger {
    static let appDelegate = Logger(category: "AppDelegate")
}

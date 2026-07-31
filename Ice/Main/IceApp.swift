//
//  IceApp.swift
//  Ice
//

import SwiftUI

@main
struct IceApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate
    // `@StateObject` (rather than `@ObservedObject`) keeps the same AppState
    // instance across App struct recreations. With `@ObservedObject`, a
    // recreation would silently replace the state with a fresh, never-set-up
    // instance, disabling all managers.
    @StateObject var appState = AppState()

    init() {
        NSSplitViewItem.swizzle()
        MigrationManager.migrateAll(appState: appState)
        appDelegate.assignAppState(appState)
    }

    var body: some Scene {
        SettingsWindow(appState: appState)
        PermissionsWindow(appState: appState)
    }
}

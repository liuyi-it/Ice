//
//  SettingsNavigationTests.swift
//  Ice
//

import Cocoa
import SwiftUI

// Pane contents are independent of sidebar selection. Exercise the production
// SettingsView, navigation model and sidebar modifier with lightweight panes.
struct GeneralSettingsPane: View { var body: some View { Text("General") } }
struct MenuBarLayoutSettingsPane: View { var body: some View { Text("Layout") } }
struct MenuBarAppearanceSettingsPane: View { var body: some View { Text("Appearance") } }
struct HotkeysSettingsPane: View { var body: some View { Text("Hotkeys") } }
struct AdvancedSettingsPane: View { var body: some View { Text("Advanced") } }
struct AboutSettingsPane: View { var body: some View { Text("About") } }

enum TestImageResource { case iceCubeStroke }
enum IconResource {
    case systemSymbol(String)
    case assetCatalog(TestImageResource)
    var view: some View { Image(systemName: "circle") }
}

@main
private enum SettingsNavigationTests {
    @MainActor
    static func settle() {
        RunLoop.current.run(until: .now.addingTimeInterval(0.2))
    }

    @MainActor
    static func table(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView {
            return table
        }
        return view.subviews.lazy.compactMap { table(in: $0) }.first
    }

    static func check(_ condition: Bool, _ name: String) {
        guard condition else {
            print("FAIL: \(name)")
            exit(EXIT_FAILURE)
        }
        print("PASS: \(name)")
    }

    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppNavigationState()
        model.settingsNavigationIdentifier = .advanced
        let host = NSHostingView(rootView: SettingsView().environmentObject(model))
        let window = NSWindow(
            contentRect: CGRect(x: -20000, y: -20000, width: 900, height: 625),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderBack(nil)
        settle()
        guard let sidebar = table(in: host) else { fatalError("Sidebar is missing") }
        let identifiers = SettingsNavigationIdentifier.allCases
        let offset = sidebar.numberOfRows - identifiers.count
        check(offset == 1, "sidebar contains every settings page")
        check(sidebar.selectedRow == offset + 4, "initial programmatic navigation selects advanced")
        for (index, identifier) in identifiers.enumerated() {
            sidebar.selectRowIndexes(IndexSet(integer: offset + index), byExtendingSelection: false)
            settle()
            check(model.settingsNavigationIdentifier == identifier, "sidebar selection publishes \(identifier.rawValue)")
        }
        model.settingsNavigationIdentifier = .menuBarLayout
        settle()
        check(sidebar.selectedRow == offset + 1, "programmatic navigation updates sidebar selection")
        window.setContentSize(NSSize(width: 825, height: 500))
        settle()
        check(model.settingsNavigationIdentifier == .menuBarLayout, "resizing preserves selection")
        window.orderOut(nil)
        window.orderBack(nil)
        settle()
        check(sidebar.selectedRow == offset + 1, "reopening preserves selection")
        window.orderOut(nil)
    }
}

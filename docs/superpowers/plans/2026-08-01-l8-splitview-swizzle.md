# L8 修复实施计划：用官方 API 替换 NSSplitViewItem swizzle

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **执行结果**：方案 A（零 swizzle，Task 1-3）已实施并在 macOS 26 上运行验证失败（`NavigationSplitView` 不尊重逐实例 `canCollapse = false`，sidebar 仍可折叠），按计划决策分支回退至 Task 4（加固版 swizzle）；另按用户确认追加了设置窗口强制展开的补充改动。Task 1-3 的代码已删除，实现过程保留在本文。

**Goal:** 用官方 API（逐实例设置 `NSSplitViewItem.canCollapse = false`）替换进程级 `NSSplitViewItem.canCollapse` 方法交换，消除 L8 脆弱性，保持设置窗口 sidebar 不可折叠的交互不变。

**Architecture:** 在 `SettingsView` 的 `NavigationSplitView` 上挂一个 `NSViewRepresentable`（`SplitViewItemCollapsePreventer`），运行时在设置窗口内查找 `NSSplitViewController`，将 sidebar 项的 `canCollapse` 设为 `false`（官方语义：用户不能通过拖拽/双击分隔条折叠该项——正是旧 swizzle 强制 false 的属性，`NSSplitViewItem.h:100`）。查找与设置幂等，在 `viewDidMoveToWindow` 与 `updateNSView` 中执行。验证成功后删除 swizzle 文件；若 `canCollapse = false` 不被 `NavigationSplitView` 尊重则回退加固版 swizzle（设计文档「兜底方案 B」）。

**Tech Stack:** Swift 5、SwiftUI（`NSViewRepresentable`）、AppKit（`NSSplitViewController`、`NSSplitViewItem.canCollapse`，macOS 10.10+）。

## Global Constraints

- 项目最低平台 macOS 14（`NSSplitViewItem.canCollapse` 为 macOS 10.10+ API，无需 `#available` 检查）。
- 无测试 target：验证手段为 `swiftlint --strict`（必须 0.65.0）+ Debug 构建（`CODE_SIGNING_ALLOWED=NO`）+ 人工运行验证；不要声称"测试通过"。
- 新 Swift 文件头必须严格匹配（SwiftLint `file_header` 规则）：`//` + `//  FileName.swift` + `//  Ice` + `//`。
- 4 空格缩进、禁用制表符；遵循 `.swiftlint.yml` modifier order；多行集合字面量保留尾随逗号。
- 日志使用 `Ice/Utilities/Logging.swift` 的 `Logger` + `private extension Logger` 的 category 静态属性；不使用 `print`。
- 不主动修改 `project.pbxproj`（文件系统同步 group 自动纳入新文件，若构建报"file not found"再检查）。
- 提交信息简洁；不提交 `build/`、临时文件。

---

### Task 1: 创建 `SplitViewItemCollapsePreventer.swift`

**Files:**
- Create: `Ice/UI/ViewModifiers/SplitViewItemCollapsePreventer.swift`

**Interfaces:**
- Produces: `View.preventSplitViewItemCollapse() -> some View`（Task 2 的 `SettingsView` 使用）。

- [ ] **Step 1: 创建文件**

创建 `Ice/UI/ViewModifiers/SplitViewItemCollapsePreventer.swift`，内容如下（文件头必须逐字符一致）：

```swift
//
//  SplitViewItemCollapsePreventer.swift
//  Ice
//

import SwiftUI

// MARK: - View Modifier

extension View {
    /// Prevents the user from collapsing the sidebar of a ``NavigationSplitView``.
    ///
    /// The settings window removes the sidebar toggle, so a collapsed sidebar
    /// could never be restored. This replaces the previous ``NSSplitViewItem``
    /// method swizzle by setting the sidebar items ``NSSplitViewItem.canCollapse`` property to ``false``.
    func preventSplitViewItemCollapse() -> some View {
        background(SplitViewItemCollapsePreventer())
    }
}

// MARK: - NSViewRepresentable

/// A view that prevents the sidebar of its enclosing ``NavigationSplitView``
/// from being collapsed by the user.
private struct SplitViewItemCollapsePreventer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = CollapsePreventerView()
        view.applyCollapsePrevention()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // SwiftUI may rebuild the split view items (e.g. after a layout
        // change); re-apply the collapse prevention so it stays effective.
        (nsView as? CollapsePreventerView)?.applyCollapsePrevention()
    }
}

// MARK: - Collapse Prevention View

/// A view that finds the ``NSSplitViewController`` of the enclosing window
/// and disables the sidebar item's ``NSSplitViewItem.canCollapse``.
private final class CollapsePreventerView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The window is only available once the view is attached to a window.
        applyCollapsePrevention()
    }

    /// Finds the sidebar split view item and disables user collapsing.
    func applyCollapsePrevention() {
        guard let window else {
            return
        }
        guard let splitViewController = Self.splitViewController(in: window) else {
            Logger.splitViewItemCollapsePreventer.warning(
                "No NSSplitViewController found in window \(window.identifier?.rawValue ?? "<nil>"); sidebar may be collapsible"
            )
            return
        }
        // In a NavigationSplitView the sidebar is always the first item.
        guard let sidebarItem = splitViewController.splitViewItems.first else {
            Logger.splitViewItemCollapsePreventer.warning("No split view items found; sidebar may be collapsible")
            return
        }
        if sidebarItem.canCollapse {
            Logger.splitViewItemCollapsePreventer.debug("Setting sidebar canCollapse to false")
            sidebarItem.canCollapse = false
        }
    }

    /// Recursively searches the window's view controllers for an
    /// ``NSSplitViewController``.
    private static func splitViewController(in window: NSWindow) -> NSSplitViewController? {
        guard let rootViewController = window.contentViewController else {
            return nil
        }
        var queue = [rootViewController]
        while let viewController = queue.popLast() {
            if let splitViewController = viewController as? NSSplitViewController {
                return splitViewController
            }
            queue.append(contentsOf: viewController.children)
        }
        return nil
    }
}

// MARK: - Logger

private extension Logger {
    static let splitViewItemCollapsePreventer = Logger(category: "SplitViewItemCollapsePreventer")
}
```

- [ ] **Step 2: SwiftLint 验证**

运行：`swiftlint --strict`
预期：`Found 0 violations, 0 serious in 119 files.`（118 → 119，新增 1 文件）。若出现 `file_header` 违规，逐字符核对文件头。

- [ ] **Step 3: Debug 构建验证（文件未被引用也能编译通过）**

运行：
```bash
xcodebuild \
  -project Ice.xcodeproj -scheme Ice -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD"
```
预期：`** BUILD SUCCEEDED **`，无 `error:`。
若报新文件缺失（`no such file`），检查 `Ice.xcodeproj` 的文件系统同步 group 是否包含该文件；不要手工编辑 `project.pbxproj`，先报告。

- [ ] **Step 4: 清理并提交**

```bash
rm -rf build
git add Ice/UI/ViewModifiers/SplitViewItemCollapsePreventer.swift
git commit -m "feat: add split view item collapse preventer view modifier"
```
预期：提交成功，`git status` 仅剩预期文件。

---

### Task 2: 接线 `SettingsView`、删除 swizzle

**Files:**
- Modify: `Ice/Settings/SettingsView.swift:40-46`（`NavigationSplitView` 的 body）
- Modify: `Ice/Main/IceApp.swift:13-18`（`init`）
- Delete: `Ice/Swizzling/NSSplitViewItem+swizzledCanCollapse.swift`

**Interfaces:**
- Consumes: `View.preventSplitViewItemCollapse()`（Task 1 产出）。

- [ ] **Step 1: 在 `SettingsView` 挂载 modifier**

将 `Ice/Settings/SettingsView.swift` 中 `NavigationSplitView` 的 body（当前第 39-46 行）改为：

```swift
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle(navigationState.settingsNavigationIdentifier.localized)
        .preventSplitViewItemCollapse()
    }
```

只新增最后一行 `.preventSplitViewItemCollapse()`，其余不动。

- [ ] **Step 2: 删除 `IceApp.swift` 中的 swizzle 调用**

将 `Ice/Main/IceApp.swift` 的 `init`（当前第 13-17 行）改为：

```swift
    init() {
        MigrationManager.migrateAll(appState: appState)
        appDelegate.assignAppState(appState)
    }
```

即删除 `NSSplitViewItem.swizzle()` 一行。

- [ ] **Step 3: 删除 swizzle 文件**

```bash
git rm Ice/Swizzling/NSSplitViewItem+swizzledCanCollapse.swift
```

- [ ] **Step 4: 全局检查残留引用**

运行：`grep -rn "NSSplitViewItem.swizzle\|swizzledCanCollapse" Ice/ --include="*.swift"`
预期：无输出（0 处残留）。

- [ ] **Step 5: SwiftLint 验证**

运行：`swiftlint --strict`
预期：`Found 0 violations, 0 serious in 118 files.`（回到 118 文件）。

- [ ] **Step 6: Debug 构建验证**

运行：
```bash
xcodebuild \
  -project Ice.xcodeproj -scheme Ice -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD"
```
预期：`** BUILD SUCCEEDED **`，无 `error:`。

- [ ] **Step 7: 清理并提交**

```bash
rm -rf build
git add Ice/Settings/SettingsView.swift Ice/Main/IceApp.swift
git commit -m "fix: replace NSSplitViewItem canCollapse swizzle with official API"
```

---

### Task 3: 运行验证 `canCollapse = false` 行为（关键决策点）

**Files:**
- 无代码改动（仅验证；验证失败才进入兜底分支）

**Interfaces:**
- Consumes: Task 1-2 的全部改动。

- [ ] **Step 1: 构建可运行产物并启动**

```bash
xcodebuild \
  -project Ice.xcodeproj -scheme Ice -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
open build/DerivedData/Build/Products/Debug/Ice.app
```

- [ ] **Step 2: 验证 sidebar 不可折叠**

1. 点击菜单栏 Ice 图标 → 「Ice 设置…」打开设置窗口。
2. **拖拽 sidebar 与内容区的分隔条向左收**（尝试折叠）——预期：sidebar 无法被拖拽折叠（宽度最小被侧边栏内容宽度限制，分隔条拖到最左后 sidebar 仍在）。
3. 确认设置窗口各导航项（通用/菜单栏布局/菜单栏外观/快捷键/高级/关于）切换正常。
4. 关闭设置窗口再打开（重建窗口），重复第 2 步——预期仍不可折叠。
5. 检查日志（`log show --predicate 'process == "Ice"' --last 2m`）——预期无 "No NSSplitViewController found" warning。

**决策分支：**
- **通过**（sidebar 不可折叠、无 warning）→ 方案 A 成立，跳到 Step 3。
- **失败**（sidebar 可折叠 或 出现 "No NSSplitViewController found" warning）→ 方案 A 不成立，执行 Task 4 兜底。

- [ ] **Step 3: 确认日志中 canCollapse 生效并收尾**

检查日志应出现（至少一次）`Setting sidebar canCollapse to false`，且无 `sidebar may be collapsible` warning。然后：

```bash
killall Ice 2>/dev/null || true
rm -rf build
```

- [ ] **Step 4: 汇报验证结果**

在最终报告中写明：构建配置、验证步骤、sidebar 折叠行为观察结果、日志中的 warning/canCollapse 记录。若环境不允许运行（无 GUI/无辅助功能权限），如实报告"未验证"并说明原因。

---

### Task 4（兜底，仅 Task 3 失败时执行）：加固版 swizzle

**Files:**
- Recreate: `Ice/Swizzling/NSSplitViewItem+swizzledCanCollapse.swift`（重建为加固版本）
- Modify: `Ice/Main/IceApp.swift`（恢复调用）
- Modify: `Ice/Settings/SettingsView.swift`（移除 `.preventSplitViewItemCollapse()`）
- Delete: `Ice/UI/ViewModifiers/SplitViewItemCollapsePreventer.swift`

**Interfaces:**
- 无跨任务接口（本任务为独立兜底路径）。

- [ ] **Step 1: 重建加固版 swizzle 文件**

创建 `Ice/Swizzling/NSSplitViewItem+swizzledCanCollapse.swift`：

```swift
//
//  NSSplitViewItem+swizzledCanCollapse.swift
//  Ice
//

import Cocoa

extension NSSplitViewItem {
    @nonobjc private static let swizzler: () = {
        let originalCanCollapseSel = #selector(getter: canCollapse)
        let swizzledCanCollapseSel = #selector(getter: swizzledCanCollapse)

        guard
            let originalCanCollapseMethod = class_getInstanceMethod(NSSplitViewItem.self, originalCanCollapseSel),
            let swizzledCanCollapseMethod = class_getInstanceMethod(NSSplitViewItem.self, swizzledCanCollapseSel)
        else {
            return
        }

        method_exchangeImplementations(originalCanCollapseMethod, swizzledCanCollapseMethod)
    }()

    @objc private var swizzledCanCollapse: Bool {
        if
            let window = viewController.view.window,
            Self.settingsWindows.contains(window)
        {
            return false
        }
        return self.swizzledCanCollapse
    }

    /// The windows whose split view items must not be collapsible.
    ///
    /// Registered with the settings window instance (rather than matching a
    /// string identifier) so other windows are never affected. The table is
    /// weak: entries disappear when the window is released.
    private static let settingsWindows = NSHashTable<NSWindow>.weakObjects()

    /// Registers the given window as one whose split view items must not be
    /// collapsible.
    static func preventCollapse(in window: NSWindow) {
        settingsWindows.add(window)
    }

    static func swizzle() {
        _ = swizzler
    }
}
```

- [ ] **Step 2: 注册设置窗口**

在 `Ice/Main/AppState.swift` 的 `assignSettingsWindow(_:)`（`settingsWindow = window` 之后）追加：

```swift
        NSSplitViewItem.preventCollapse(in: window)
```

- [ ] **Step 3: 恢复调用并移除方案 A 产物**

1. `Ice/Main/IceApp.swift` 的 `init` 中恢复 `NSSplitViewItem.swizzle()` 一行（Task 2 Step 2 删除的那行）。
2. `Ice/Settings/SettingsView.swift` 移除 `.preventSplitViewItemCollapse()` 一行。
3. `git rm Ice/UI/ViewModifiers/SplitViewItemCollapsePreventer.swift`。

- [ ] **Step 4: SwiftLint + 构建验证**

运行：`swiftlint --strict` → 预期 `0 violations, 0 serious`。
运行：
```bash
xcodebuild \
  -project Ice.xcodeproj -scheme Ice -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD"
```
预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 5: 运行验证 + 提交**

按 Task 3 的验证流程确认 sidebar 不可折叠。然后：

```bash
killall Ice 2>/dev/null || true
rm -rf build
git add -A Ice/
git commit -m "fix: keep split view sidebar non-collapsible via hardened swizzle fallback"
```

- [ ] **Step 6（补充，Task 4 之后追加）：设置窗口强制 sidebar 展开**

在 Task 4 完成后追加的补充改动（提交 6cde093）。背景与做法：

- 用户确认「去掉折叠功能」：sidebar 永久展开且不可折叠。
- 问题：macOS 窗口状态恢复（window-state restoration）可能在设置窗口重建时恢复此前被折叠的
  sidebar，而 `.removeSidebarToggle()` 已移除恢复按钮，折叠后难以重新展开。
- 修复：`SettingsView` 中新增 `@State columnVisibility: NavigationSplitViewVisibility = .all`，
  `NavigationSplitView` 改传 `columnVisibility: $columnVisibility`，并加
  `.onAppear { columnVisibility = .all }` 在每次出现时强制展开。
- 注意：该类型在 macOS 26.5 SDK 中已由 `NavigationSplitViewColumnVisibility` 重命名为
  `NavigationSplitViewVisibility`（旧名已废弃），此改动要求 Xcode 26+。

# L8 修复设计：用官方 API 替换 NSSplitViewItem canCollapse swizzle

日期：2026-08-01

> **实施结果**：方案 A 在 macOS 26 上验证失败，最终采用下文的加固版 swizzle 方案 B，并在窗口显示时强制展开 sidebar。

## 背景

`Ice/Swizzling/NSSplitViewItem+swizzledCanCollapse.swift` 通过 `method_exchangeImplementations`
在**进程级**替换了 `NSSplitViewItem.canCollapse` getter：当 `viewController.view.window?.identifier ==
Constants.settingsWindowID` 时返回 `false`（禁止折叠），否则走原实现。

**动机**：设置窗口（`SettingsView`）使用 `NavigationSplitView`，且通过 `.removeSidebarToggle()` 移除了
SwiftUI 的侧边栏恢复按钮——一旦用户折叠 sidebar，设置窗口导航永久失效。因此上游用 swizzle 强制
`canCollapse = false`。

**脆弱性（L8）**：

1. `method_exchangeImplementations` 是进程级、类级全局替换，影响所有 `NSSplitViewItem` 实例（即使
   条件不匹配，每次 getter 调用都经过被交换的方法）。
2. 判定依赖 `window.identifier == "SettingsWindow"` 字符串约定，未来其他窗口复用该 identifier 会误触发。
3. 与系统实现耦合：未来 macOS 若改变 `canCollapse` 实现（纯 Swift、新增 selector），swizzle 静默失效
   （安全失败但功能回归）。
4. 若未来 app 新增其他 split view 场景，行为会被意外影响。

## 目标

保持"设置窗口 sidebar 不可折叠"的交互不变，用 **macOS 14+ 官方 API** 替换 swizzle，实现零 swizzle。
验证无效时回退到加固版 swizzle（方案 B）。

## 设计

### 组件结构

**新增** `Ice/UI/ViewModifiers/SplitViewItemCollapsePreventer.swift`（一个文件内三部分）：

1. **View modifier**：`View.preventSplitViewItemCollapse()`，通过 `.background()` 挂载 representable。
2. **NSViewRepresentable**：`SplitViewItemCollapsePreventer`，`makeNSView` 创建 `CollapsePreventerView`，
   `updateNSView` 重复应用（幂等）。
3. **NSView 子类**：`CollapsePreventerView`，在 `viewDidMoveToWindow()` 中执行查找与设置。

**修改**：

- `Ice/Settings/SettingsView.swift`：`NavigationSplitView { ... }` 后追加 `.preventSplitViewItemCollapse()`。
- `Ice/Main/IceApp.swift`：删除 `NSSplitViewItem.swizzle()` 调用（第 18 行）。
- **删除** `Ice/Swizzling/NSSplitViewItem+swizzledCanCollapse.swift`。

### 查找逻辑（主线程同步）

1. `view.window` 取窗口（`viewDidMoveToWindow` 保证 window 已就绪；window 为 nil 时跳过，下次调用重试）。
2. 遍历窗口的 controller 层级找 `NSSplitViewController`：从 `window.contentViewController` 起递归
   `childViewControllers`，类型匹配 `NSSplitViewController`。
3. 取 `splitViewItems` 中 sidebar 项：`splitViewItems[0]`（NavigationSplitView 中 sidebar 恒为第一个 item）。
4. 设置 `splitViewItem.canCollapse = false`
   （官方 API，macOS 10.10+；`NSSplitViewItem.h:100`："Whether or not the child view controller is
   collapsible from user interaction - whether by dragging or double clicking a divider"，可写属性——
   正是旧 swizzle 强制为 false 的属性；按头文件注释该赋值还会重置
   `canCollapseFromWindowResize`，覆盖窗口缩放折叠路径）。
   **实现修正记录**：设计初稿引用的 `NSSplitViewItem.CollapseBehavior.keepVisible` 在 SDK 中
   **不存在**（已对照 macOS 26.5 SDK `NSSplitViewItem.h` 验证）；首轮实现改用
   `.preferResizingSiblingsWithFixedSplitView`，但审查确认 `collapseBehavior` 仅控制**程序化**折叠的
   尺寸分配（`NSSplitViewItem.h:102`），不阻止用户折叠——正确属性是逐实例设置
   `canCollapse = false`（保持零 swizzle，representable 在 `updateNSView` 中幂等重设，对抗 SwiftUI
   重建时重置）。`viewController` 在该 SDK 中为非 optional，直接在 `NSSplitViewItem` 上赋值。

### 更新时机

- `viewDidMoveToWindow`：window 挂载或变化时执行。
- `updateNSView`：SwiftUI 每次布局更新时重复设置，覆盖 SwiftUI 重建 split view item 的场景。
- 查找与设置均幂等，成本极低（2-4 次/窗口生命周期）。

### 错误处理

- 找不到 `NSSplitViewController` 或 split view item：`Logger` warning（新增 category），不崩溃。
  这是 macOS 26 结构变化的早期信号，也是触发方案 B 兜底的依据。

### 验证

1. `swiftlint --strict`（0.65.0）通过。
2. Debug 构建通过（`xcodebuild ... CODE_SIGNING_ALLOWED=NO build`）。
3. 运行验证：拖拽分隔条尝试折叠 sidebar → 应无法折叠；设置窗口导航正常；窗口关闭重开仍不可折叠。
4. 若第 3 步发现 `canCollapse = false` 被 `NavigationSplitView` 覆盖（仍可折叠）→ 回退方案 B。

### 兜底方案 B（仅当方案 A 验证失败时执行）

保留方法交换，但加固：

- 判定改为**窗口实例注册表**：维护 weak 集合（如 `NSHashTable<NSWindow>.weakObjects()`），
  `assignSettingsWindow` 时注册、`NSWindow.willClose` 时移除；swizzle 方法检查 `window` 是否在集合中，
  消除 identifier 字符串约定。实现采用 weak 表自动清理，窗口释放即自动移除条目，无需显式监听
  `NSWindow.willClose`（实现优于初稿设计，已简化）。
- 完整文档化风险、失败模式与未来 macOS 变更的观察方式。

## 风险与边界

| 风险 | 应对 |
|------|------|
| SwiftUI 内部结构变化（macOS 26） | 找不到 → warning 日志 + 方案 B 兜底；不崩溃 |
| `canCollapse = false` 不被 `NavigationSplitView` 尊重（布局时被重置） | 验证步骤 3 直接暴露；updateNSView 幂等重设；仍失败则回退方案 B |
| 性能 | 查找仅窗口挂载/布局更新时执行，属性设置幂等 |
| 其他 split view 不受影响 | 查找范围限定在设置窗口内，天然隔离 |

## 非目标

- 不改变"sidebar 不可折叠"的交互（用户确认保持）。
- 不引入自绘布局（方案 C 已排除）。
- 不修改其他 swizzle 文件（本仓库 `Swizzling/` 下仅此一个文件）。

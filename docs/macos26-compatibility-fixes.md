# macOS 26 (Tahoe) 兼容性修复记录

## 环境

- **macOS**: 26.5.1 (25F80) / Darwin 25.5.0
- **Xcode**: 26.3 (17C529)
- **SDK**: MacOSX26.2.sdk
- **Ice 版本**: 0.11.12
- **设备**: Mac14,9 (Apple Silicon)

## 问题列表

### 1. 应用闪退 — `EXC_BREAKPOINT` / `SIGTRAP`

**崩溃信息**:
```
Swift runtime failure: Not enough bits to represent the passed value
ControlItem.windowID.getter (ControlItem.swift:69)
→ IceBarPanel.updateOrigin(for:) (IceBar.swift:139)
→ IceBarPanel.show(section:on:) (IceBar.swift:173)
→ MenuBarSection.show() (MenuBarSection.swift:146)
```

**根因**: macOS 26 改变了 `NSWindow.windowNumber` 的返回值范围。`NSStatusBarWindow` 的 `windowNumber` 现在返回大于 `UInt32.max`（4,294,967,295）的值（实测约 68 亿），但 `CGWindowID` 仍定义为 `UInt32`。Swift 的 `CGWindowID(window.windowNumber)` 转换因值超出范围触发运行时 trap。

**修复**:

| 文件 | 修改 |
|------|------|
| `Ice/MenuBar/ControlItem/ControlItem.swift:65-77` | `windowID` getter 增加 `windowNumber >= 0 && windowNumber <= UInt32.max` 边界检查，超限时返回 `nil` 并记录日志 |
| `Ice/UI/IceBar/IceBar.swift:70-75` | 创建 `WindowInfo` 时用闭包替代 `flatMap`，增加同样的安全转换 |

**影响**: `windowID` 返回 nil 时，Ice Bar 回退到屏幕右侧显示（`originForRightOfScreen`）。自动隐藏菜单栏检测功能降级。

---

### 2. `WindowInfo` 初始化可能失败 — `kCGWindowNumber` CFNumber 类型变化

**根因**: macOS 26 中 `CGWindowListCopyWindowInfo` 返回的 `kCGWindowNumber` 字典值，其 `CFNumber` 内部类型可能从 `kCFNumberSInt32Type` 变为 `kCFNumberSInt64Type`，导致 `as? CGWindowID`（即 `as? UInt32`）转换失败。

**修复**: `Ice/Utilities/WindowInfo.swift:80`

改用 `NSNumber.uint64Value` 桥接，绕过 CFNumber 类型不匹配：

```swift
// 原代码
let windowID = info[kCGWindowNumber] as? CGWindowID,

// 修复后
let windowNumber = (info[kCGWindowNumber] as? NSNumber).map({ CGWindowID(truncatingIfNeeded: $0.uint64Value) }),
```

---

### 3. 菜单栏布局空白 — 控制项 title 匹配失效

**症状**: 设置 → 菜单栏布局中「显示分区」「隐藏分区」均为空白，无图标、无红色错误文字。菜单栏点击 Ice 图标无反应。

**根因**:

1. macOS 26 上 `NSStatusBarWindow` 的 `kCGWindowName` 可能返回 `nil`。`MenuBarItem.getMenuBarItems(activeSpaceOnly: true)` 原本会先过滤 `title == ""` 的窗口，导致 Ice 控制项在 frame 匹配执行前就被移除。
2. 基于 title 的控制项识别也会因此失效。
3. Control Center 可能重新挂载第三方状态项窗口，此时 Ice 控制项的 owner PID 不再是 Ice，因此不能用 `owningApplication == .current` 判断。
4. 控制项隐藏分区时窗口宽度会扩展到 `10_000`，WindowServer 可能裁剪其左侧边缘和实际宽度；midX 或同时比较左右边缘都会匹配失败，但右侧定位边缘保持稳定。
5. 原缓存流程在控制项匹配成功前就记录 `cachedItemWindowIDs`，且初始值为 `[]`。若首次窗口列表为空，或首次调用时 `ControlItem.windowFrame` 尚未就绪，后续调用会因窗口 ID 未变化而跳过，缓存无法恢复。
6. `ControlItem` 原先只在初始化时对当时存在的 `button.window` 建立 frame 监听。macOS 26 下状态项窗口可能延迟创建，导致监听根本没有建立，`windowFrame` 永远为 `nil`，frame 回退匹配无法执行。
7. macOS 26 会把第三方状态项窗口统一归属到 `com.apple.controlcenter`，并可能令 `kCGWindowName` 为 `nil` 或无区分度的通用标题 `Item-0`。旧版 `MenuBarItemInfo` 因此会把多个项目折叠成同一个身份键，导致布局项目消失、图像缓存互相覆盖，并在 Ice Bar 中重复显示同一图标。
8. 控制项窗口在启动和状态变化期间会短暂经过零尺寸或未稳定 frame。旧逻辑在这段时间匹配失败后立即清空已有缓存，造成布局图标闪现后消失。
9. Ice Bar 点击隐藏项目时，临时显示逻辑仍通过 `.ice:HItem` 查找隐藏控制项。macOS 26 重挂载后控制项曾被识别成 `com.apple.controlcenter:HItem`，查找失败后代码又对空数组调用 `removeFirst()`，触发闪退。

**修复**:

| 文件 | 修改 |
|------|------|
| `Ice/MenuBar/MenuBarItems/MenuBarItem.swift` | 保留 macOS 26 的无标题状态项；对无区分度窗口使用窗口 ID 构造会话内唯一身份；根据 `SItem/HItem/AHItem` 标题恢复 Ice 控制项 namespace |
| `Ice/Utilities/Extensions.swift` | `firstIndex(matchingControlItem:)` 使用 frame 右侧定位边缘精确匹配，不依赖 title、owner PID 或被 WindowServer 裁剪的宽度 |
| `Ice/MenuBar/ControlItem/ControlItem.swift` | 依次监听状态项 button、延迟创建的 window 和 frame，确保 `windowFrame` 能在 macOS 26 下更新 |
| `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift` | `cacheItemsIfNeeded()` 优先用 frame 匹配，回退到 title 匹配；仅在缓存成功后记录窗口 ID；控制项暂未就绪时保留上一轮有效缓存并重试；临时显示时安全处理缺失的隐藏控制项 |
| `Ice/MenuBar/MenuBarManager.swift:185-201` | 同样逻辑修复菜单栏项过滤 |
| `Ice/UI/IceBar/IceBar.swift` | 在菜单栏采样背景上叠加 85% 不透明的系统自适应窗口背景，提高 macOS 26 下浮窗可读性 |
| `Ice/UI/IceBar/IceBar.swift` | Ice 图标定位使用可靠的 `ControlItem.windowFrame`，不可用时回退鼠标位置，不再因 macOS 26 哨兵窗口号落到屏幕最右侧 |
| `Ice/Utilities/MigrationManager.swift` | 没有旧版外观配置时视为无需迁移，不再记录伪错误 |
| `Ice/Main/AppState.swift` | 设置窗口尚未创建属于正常启动时序，不再记录伪警告 |

**匹配逻辑**：

1. 计算候选菜单栏窗口与 `ControlItem.windowFrame` 的右侧定位边缘距离。
2. 选择距离最小的候选项。
3. 仅接受总误差不超过 2pt 的候选项，避免扩展宽度为 `10_000` 时误匹配其他状态项。
4. 若首次匹配失败，不更新 `cachedItemWindowIDs`，等待 frame 就绪后再次构建缓存。

---

## 构建与部署

### 构建 Release 包

```bash
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Release \
  -destination 'platform=macOS' build

# 输出: ~/Library/Developer/Xcode/DerivedData/Ice-xxx/Build/Products/Release/Ice.app
```

### 签名（必须）

由于项目 Release target 使用 ad-hoc 签名，而内嵌的 Sparkle.framework 保留了原开发者的 Team ID，需要统一重签名：

```bash
codesign --force --sign - --deep /path/to/Ice.app
```

### 部署到 /Applications

```bash
killall Ice 2>/dev/null
cp -a /path/to/Ice.app /Applications/Ice.app
open /Applications/Ice.app
```

---

## 上游相关 Issue

- [#947](https://github.com/jordanbaird/Ice/issues/947) — app crash after click in menubar (macOS 26.4)
- [#946](https://github.com/jordanbaird/Ice/issues/946) — MacOS Tahoe 26.5 update broke hidden elements
- [#951](https://github.com/jordanbaird/Ice/issues/951) — Can't view the icons on Menu Bar Layout (macOS 26.3)
- [#929](https://github.com/jordanbaird/Ice/issues/929) — Menu bar scaling and layout issues (macOS 26.4.1)

---

## 已知限制

1. 由于 `CGWindowID` 仍为 `UInt32`，无法从 `NSWindow.windowNumber` 获取有效的 `CGWindowID`。依赖 `ControlItem.windowID` 的功能回退到降级行为（如 Ice Bar 定位到屏幕右侧而非 Ice 图标旁）。
2. 控制项匹配的 frame 回退方案依赖 `ControlItem.windowFrame`（KVO 异步更新）；现在会监听延迟创建的状态项窗口，首次调用未就绪时也会在后续缓存周期重试。
3. ad-hoc 签名的 app 每次重新构建后需要 `--deep` 重签名才能运行。

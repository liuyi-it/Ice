# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目摘要

Ice 是一款 macOS 14+ 的菜单栏管理应用。仓库内已有的 `AGENTS.md` 已经涵盖详细的架构约定、代码风格、Release 打包与验证流程，**在本文件中以「见 AGENTS.md §X」形式引用，避免重复**。请同时阅读 `AGENTS.md`、`README.md`、`FREQUENT_ISSUES.md` 与 `docs/macos26-compatibility-fixes.md`。

## 关键事实

- 工程入口：`Ice.xcodeproj`（唯一 target 和 shared scheme 均名为 `Ice`）。
- 应用入口：`Ice/Main/IceApp.swift`。全局状态：`Ice/Main/AppState.swift`（`@MainActor` 的依赖容器）。
- bundle id：`com.jordanbaird.Ice`；Swift 5；最低运行平台 macOS 14。Xcode 26+ 工程（`NavigationSplitViewVisibility` 等 API 需要 macOS 26.5 SDK / Xcode 26+），使用文件系统同步 group。
- 没有任何测试 target；不要声明“测试通过”。
- 启用了 Accessibility、Screen Recording、事件监听、Sparkle 自动更新；未启用 App Sandbox；`Bridging/`、`Swizzling/` 涉及私有 API。

## 常用命令

打开工程：

```sh
open Ice.xcodeproj
```

Debug 构建（命令行）：

```sh
xcodebuild \
  -project Ice.xcodeproj \
  -scheme Ice \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Release 打包、签名、安装、清理的完整流程见 `AGENTS.md`「Release 打包、签名、替换与清理」一节（含 entitlements / Hardened Runtime / 架构与 `get-task-allow` 验收、清理 `build/` 与临时日志）。

Lint（必须与 CI 版本一致 `0.65.0`）：

```sh
swiftlint version      # 期望 0.65.0，否则 lint 结果与 CI 不对齐
swiftlint --strict
```

CI 仅跑 `swiftlint --strict`（参见 `.github/workflows/lint.yml`）。若需额外静态分析：

```sh
xcodebuild \
  -project Ice.xcodeproj -scheme Ice -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO analyze
```

## 架构速览

`AppState` 是 `@MainActor` 的全局依赖容器，每个 manager 都是 `private(set) lazy var`，通过 `performSetup()` 统一初始化并持有 `weak var appState: AppState?`。新增 manager 时沿用该模式并检查 `MigrationManager` 是否需要迁移。

主目录与职责（详见 `AGENTS.md`）：

```text
Ice/Main/             # IceApp、AppDelegate、AppState、Navigation
Ice/MenuBar/          # 分区（MenuBarSection）、项目管理、布局、外观、搜索、间距、ControlItem
Ice/Settings/         # SettingsWindow、各 Pane、各 Manager
Ice/Hotkeys/          # 全局快捷键模型、注册表、按键组合
Ice/UI/               # 通用 SwiftUI/AppKit 视图、IceBar、LayoutBar、Pickers、ViewModifiers
Ice/Events/           # EventManager、EventTap、Global/Local/Universal/RunLoopLocal 事件监听
Ice/Permissions/      # 权限检查与引导窗口
Ice/Updates/          # Sparkle 自动更新
Ice/UserNotifications/ # 用户通知
Ice/Utilities/        # 日志（Logger）、持久化（Defaults / StatusItemDefaults）、Migration、ScreenCapture、WindowInfo、扩展
Ice/Bridging/         # 系统/私有 API 桥接（Shims/Deprecated、Private）
Ice/Swizzling/        # AppKit 方法交换
Ice/Resources/        # 应用内文档资源
Ice/Assets.xcassets/  # 图标、颜色
Ice/Ice.entitlements  # 权限声明
```

## 关键约定（精炼版）

完整规则见 `AGENTS.md`。请特别注意：

- UI 与影响 UI 的状态运行在 `@MainActor`；跨 actor / detached task 修改前确认隔离边界。
- Combine 订阅的 `AnyCancellable` 保存在所属对象中，并使用 `[weak self]` 避免循环引用。
- 新 Swift 文件头必须严格匹配（否则 `file_header` SwiftLint 规则会失败）：
  ```swift
  //
  //  FileName.swift
  //  Ice
  //
  ```
- 4 空格缩进，禁用制表符；遵循 `.swiftlint.yml` 的 modifier order（`@objc` 后紧跟 `dynamic`）；多行集合字面量保留尾随逗号（`trailing_comma.mandatory_comma`）。
- 日志使用 `Ice/Utilities/Logging.swift` 的 `Logger` + 私有 category 扩展；不要散落 `print`。
- `project.pbxproj` 与 `Package.resolved` 不主动修改；新增文件 / target / 依赖时再更新工程配置，并核对无关 Xcode 元数据 diff。
- macOS 26 / Tahoe 上菜单栏布局、空标题状态项、`ControlItem.windowID`、`CGWindowID` 范围等问题已在 `docs/macos26-compatibility-fixes.md` 列出，处理相关代码前先查阅。

## 验证与提交

按改动范围选择验证手段，并在最终报告中说明执行了哪些步骤。详细场景见 `AGENTS.md`「验证要求」一节：

- Swift 改动：跑 `swiftlint --strict` + Debug 构建。
- 菜单栏显示/隐藏、分区、自动隐藏：验证 visible / hidden / always-hidden 分区与多显示器。
- UI / 设置：验证设置窗口、持久化、重启恢复、浅色 / 深色外观。
- 权限 / 事件 tap / 屏幕捕获：分别验证未授权、授权后、撤销三种状态。
- 快捷键：注册、冲突、设置更新、重启后的恢复。
- 更新流程：用 Sparkle 安全测试方式验证，避免触发真实发布。
- 改 `project.pbxproj`、entitlements 或依赖：同时检查 Release 配置与签名相关 diff。

提交前：

```sh
git status --short     # 保留用户已有改动
git diff --check       # 检查空白错误
```

不要提交 `build/`、`DerivedData`、用户级 Xcode 数据或临时文件；不要顺手修改与任务无关的格式、注释或工程元数据。提交信息应简洁，除非用户明确要求否则不主动创建提交。

## 用户语言

始终用中文回复用户；技术术语、代码标识符与文件路径保留原文。中文必须使用正字法，不要用 ASCII 近似字（如不要把 `lösch` 写作 `losch`）。

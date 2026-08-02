# AGENTS.md

本文件为在 Ice 仓库中工作的智能代理提供项目级约束。除非用户明确要求，否则只修改完成当前任务所需的文件，不处理工作区中已有的无关改动。

## 项目概览

- Ice 是 macOS 14+ 菜单栏管理应用，使用 Swift、SwiftUI、AppKit 和 Combine。
- 工程入口为 `Ice.xcodeproj`，唯一应用 target 和共享 scheme 均名为 `Ice`。
- 应用入口是 `Ice/Main/IceApp.swift`；`AppState` 持有并协调主要 manager。
- bundle identifier 为 `com.jordanbaird.Ice`，Swift 语言版本为 5。
- 工程由 Xcode 26+ 保存并使用文件系统同步 group；推荐使用 Xcode 26 或更高版本（`NavigationSplitViewVisibility` 等 API 需要 macOS 26.5 SDK / Xcode 26+）。
- 项目没有测试 target；验证以构建、SwiftLint 和针对性人工测试为主。
- 应用未启用 App Sandbox，并使用辅助功能、事件监听、屏幕录制及部分私有系统桥接能力。修改相关代码时必须评估权限与系统版本影响。

## 目录职责

```text
Ice/
├── Main/                 # 应用入口、AppDelegate、全局状态与导航
├── MenuBar/              # 菜单栏分区、项目管理、外观、搜索和间距
├── Settings/             # 设置窗口、设置页面和设置 manager
├── Hotkeys/              # 全局快捷键模型、注册与事件处理
├── UI/                   # 通用 SwiftUI/AppKit 视图与组件
├── Events/               # 全局/局部事件监听及事件 tap
├── Permissions/          # 辅助功能、屏幕录制等权限检查与引导
├── Updates/              # Sparkle 自动更新
├── UserNotifications/    # 用户通知
├── Utilities/            # 日志、持久化、屏幕捕获和通用扩展
├── Bridging/             # 系统 API 与私有 API 桥接
├── Swizzling/            # AppKit 运行时方法交换
├── Resources/            # 应用内文档资源
├── Assets.xcassets/      # 图片、图标和颜色资源
└── Ice.entitlements      # 应用权限配置
Resources/                 # README 媒体与设计源文件
```

其他关键文件：

- `.swiftlint.yml`：SwiftLint 规则。
- `.github/workflows/lint.yml`：CI lint 工作流。
- `Ice.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`：锁定 SwiftPM 依赖版本。
- `Ice/Info.plist`：应用信息及 Sparkle feed 配置。
- `README.md`：产品功能与路线图。
- `FREQUENT_ISSUES.md`：常见用户问题。

## 架构与实现约定

- `AppState` 是应用级依赖容器。新增跨功能 manager 时，遵循现有 lazy manager、弱引用 `appState` 和 `performSetup()` 生命周期模式。
- UI 与影响 UI 的状态通常运行在 `@MainActor`。跨 actor 或 detached task 修改状态前，先确认隔离边界。
- 使用 Combine 订阅时，将 cancellable 保存在所属对象中，并优先使用 `[weak self]` 避免循环引用。
- 用户设置通常通过现有 settings manager、`Defaults` 或 `StatusItemDefaults` 管理。新增或调整持久化字段时，检查 `MigrationManager` 是否需要迁移。
- 日志使用 `Ice/Utilities/Logging.swift` 中的 `Logger`，并沿用文件内私有 category 扩展；不要新增散落的 `print`。
- 菜单栏、窗口和屏幕坐标逻辑容易受多显示器、刘海、全屏 Space 和系统自动隐藏菜单栏影响；修改时覆盖这些场景。
- `Bridging/` 和 `Swizzling/` 涉及私有 API 或运行时行为。保持修改最小化，并验证目标 macOS 版本上的行为。
- 不要无故修改 `project.pbxproj` 或 `Package.resolved`。新增文件、target 或依赖时才更新工程配置，并检查 diff 中是否出现无关 Xcode 元数据变更。

## 代码风格

- 使用 4 个空格缩进，禁止制表符。
- 新 Swift 文件头必须匹配：

  ```swift
  //
  //  FileName.swift
  //  Ice
  //
  ```

- 多行集合字面量按 SwiftLint `trailing_comma.mandatory_comma` 规则保留尾随逗号。
- 遵循 `.swiftlint.yml` 中的 modifier order；`dynamic` 必须紧跟在 `@objc` 后。
- 遵循相邻代码的命名、访问控制、MARK 分区和 SwiftUI 组合方式。
- 优先使用已有工具类型和扩展，不为单一调用引入新抽象。
- 不要用 force unwrap 规避正常错误处理；SwiftLint 对 force unwrap 和 implicitly unwrapped optional 有额外检查。

## 依赖

SwiftPM 依赖由 Xcode 工程和 `Package.resolved` 管理：

- `AXSwift`：辅助功能 API 封装。
- `CompactSlider`：滑块 UI。
- `Ifrit`：图像处理。
- `LaunchAtLogin-Modern`：登录时启动。
- `Sparkle`：自动更新。

调整依赖前先确认现有依赖不能满足需求。不要手工编辑 `Package.resolved` 中的 revision。

## 构建与检查

推荐使用 Xcode 打开并运行：

```sh
open Ice.xcodeproj
```

命令行 Debug 构建：

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

运行与 CI 相同的 lint：

```sh
swiftlint version
swiftlint --strict
```

项目统一使用 SwiftLint `0.65.0`，GitHub Actions 通过官方 `ghcr.io/realm/swiftlint:0.65.0` 镜像固定此版本。本机验证前必须确认 `swiftlint version` 同样输出 `0.65.0`；版本不一致的 lint 结果不能作为 CI 验收依据。Xcode 工程内的构建阶段会在 SwiftLint 缺失时跳过，且不是 strict 模式，因此不能替代相同版本的 `swiftlint --strict`。当前 GitHub Actions 只执行 strict lint，不执行构建或静态分析。

需要额外静态检查时：

```sh
xcodebuild \
  -project Ice.xcodeproj \
  -scheme Ice \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  analyze
```

仓库当前没有测试套件，不要声称“测试通过”。应明确报告执行过的构建、lint、静态分析和人工验证。

## Release 打包、签名、替换与清理

用户要求构建并替换当前运行版本时，必须完整执行以下流程，不得用 Debug 产物代替 Release 产物，也不得仅以“构建成功”作为交付依据。

### 1. 确认签名身份

- 先运行 `security find-identity -v -p codesigning`，确认用户指定的证书是有效 identity（证书和私钥均可用）。
- 使用用户明确指定的签名证书和对应 `DEVELOPMENT_TEAM`，不要擅自改用 ad hoc 签名或其他 identity。
- `Apple Development` 可用于本机 Release 构建，但 Xcode 可能自动注入 `com.apple.security.get-task-allow=true`。即使编译配置是 Release，这也会被工具识别为可调试包，因此必须显式禁止注入并在安装前后检查 entitlements。
- 对外分发和公证应使用 `Developer ID Application`，不能把 `Apple Development` 签名误报为可分发、公证的正式签名。
- `CSSMERR_TP_NOT_TRUSTED`、`Authority=(unavailable)` 或找不到 identity 时，先检查命令是否有权限访问登录钥匙串、私钥和 WWDR 中间证书。不要通过关闭 Hardened Runtime 来绕过证书链或执行环境问题。

### 2. 构建真正的 Release 产物

清理旧的本次构建目录后，使用 Release 配置、Hardened Runtime 和禁止基础调试 entitlement 注入的设置构建：

```sh
rm -rf build
xcodebuild \
  -project Ice.xcodeproj \
  -scheme Ice \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/ReleaseDerivedData \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  DEVELOPMENT_TEAM='<用户的 Team ID>' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='<用户指定的签名 identity>' \
  build
```

不得在部署流程中使用 `build/.../Debug/Ice.app`。待安装产物必须来自：

```text
build/ReleaseDerivedData/Build/Products/Release/Ice.app
```

### 3. 安装前强制验收

替换应用前必须逐项确认：

- `codesign --verify --deep --strict --verbose=4 <Ice.app>` 成功。
- `codesign -dv --verbose=4 <Ice.app>` 显示正确的 `Authority`、`TeamIdentifier`，并包含 `flags=0x10000(runtime)`。
- `codesign -d --entitlements :- <Ice.app>` 中不存在 `com.apple.security.get-task-allow`，尤其不能为 `true`。
- `Contents/MacOS` 中只有 Release 主可执行文件，不存在 `Ice.debug.dylib` 或 `__preview.dylib`。
- 使用 `file Contents/MacOS/Ice` 核对目标架构；默认 Release 部署应保留工程生成的 Universal（arm64 + x86_64）产物，除非用户明确要求单一架构。
- 读取 `CFBundleShortVersionString` 和 `CFBundleVersion`，向用户准确报告版本；代码更新但未调整版本号时，不得声称版本号已升级。

任何一项不符合都不得替换当前应用。

### 4. 替换和启动验证

修改 `/Applications` 和终止当前进程前取得所需授权，然后执行：

```sh
killall Ice 2>/dev/null || true
rm -rf /Applications/Ice.app
ditto build/ReleaseDerivedData/Build/Products/Release/Ice.app /Applications/Ice.app
open /Applications/Ice.app
```

启动后必须从 `/Applications/Ice.app` 再次执行严格签名、Hardened Runtime、entitlements、架构和包内文件检查，不能复用安装前结果。使用 `pgrep` 确认新进程的可执行路径确实是 `/Applications/Ice.app/Contents/MacOS/Ice`，并检查近期系统日志和崩溃报告，确认没有即时启动失败。

### 5. 清理和最终报告

- 安装后验证全部完成，才能删除 `build/` 和本次流程在 `/private/tmp` 创建的已知构建日志；不要用宽泛通配符删除不属于本次任务的文件。
- 清理后确认 `build/` 不存在、Release 进程仍在运行，并执行 `git status -sb` 和 `git diff --check`。
- 最终报告必须明确写出：Release 配置、架构、版本号、签名 identity 类型、Hardened Runtime 状态、`get-task-allow` 已移除、严格签名结果、运行进程和构建产物清理结果。

## 验证要求

根据改动范围选择验证，并在完成时报告结果和环境阻塞。人工场景仅在环境允许时执行；无法执行时明确列出未验证场景和原因：

- 所有 Swift 修改：尽可能运行 `swiftlint --strict` 和 Debug 构建。
- 菜单栏显示/隐藏、分区和自动隐藏：验证 visible、hidden、always-hidden 分区及多显示器行为。
- UI 或设置：验证设置窗口、持久化、重启后恢复以及浅色/深色外观。
- 权限、事件 tap、屏幕捕获：分别验证权限未授予、授予后和权限被撤销的行为。
- 快捷键：验证注册、冲突、设置更新和应用重启后的恢复。
- 更新流程：避免触发真实发布；使用 Sparkle 的安全测试方式验证。
- 修改 `project.pbxproj`、entitlements 或依赖：同时检查 Release 配置和签名相关 diff。

若命令因沙箱、签名、钥匙串、权限、SwiftPM 网络访问或本机 Xcode 环境失败，应将环境问题与代码问题分开说明。

## 提交流程

- 开始前运行 `git status --short`，保留用户已有改动。
- 完成后检查 `git diff --check` 和相关文件 diff。
- 不提交构建产物、用户级 Xcode 数据或临时文件。
- 不修改与任务无关的格式、注释或工程元数据。
- 提交信息应简洁描述意图；除非用户明确要求，不主动创建提交。

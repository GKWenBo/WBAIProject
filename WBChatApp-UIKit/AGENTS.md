# 仓库指南

## 项目结构与模块组织

`WBChatApp-UIKit/` 是应用主 target。应用组装代码放在 `App/`，通用主题和交互反馈工具放在 `Common/`，基础设施放在 `Core/`，各页面的 MVVM 实现放在 `Features/`。网络、LLM 适配、持久化、Markdown 渲染、语音和安全能力分别位于 `Core/` 对应子目录。单元测试位于 `WBChatApp-UIKitTests/`，XCTest UI 测试位于 `WBChatApp-UIKitUITests/`。架构说明放在 `doc/`，设计与实施记录放在 `docs/superpowers/`。颜色和图标应添加到 `Assets.xcassets`，不要直接嵌入源码。

## 构建、测试与本地开发

使用 Xcode 26.5 或更高版本打开 `WBChatApp-UIKit.xcodeproj`。`WBChatApp-UIKit` scheme 在未配置凭据时会使用 `MockProvider`，可直接运行。

```bash
xcodebuild build -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:WBChatApp-UIKitTests
```

若本机没有 iOS 26.5 runtime，请替换为已安装的模拟器目标。调整 `swift-markdown` 或 GRDB 依赖时，同步提交 `Package.resolved`。

## 编码风格与命名约定

Swift 代码使用四个空格缩进，不使用 Tab。类型采用 `UpperCamelCase`，方法、属性和测试辅助方法采用 `lowerCamelCase`。ViewController 和 View 保持 `@MainActor` 隔离；`*ViewModel.swift` 不得导入 UIKit。Provider、Repository、时钟和节流器优先通过协议与依赖注入提供。遵循现有 MVVM 边界，将特定功能的 UI 留在对应 feature 目录。本仓库未配置统一格式化或 lint 工具，请遵循相邻代码风格，并运行 `git diff --check`。

## 测试规范

单元测试使用 Swift Testing（`import Testing`、`@Suite` 和描述性 `@Test` 名称）；UI 测试使用 XCTest 和 `test...` 方法命名。缺陷修复应在对应子系统附近增加聚焦的回归测试。只有必须启动 App 才能验证的交互流程才使用 UI 测试。开发过程中运行单元测试 target，提交 Pull Request 前运行完整 scheme。

## 提交与 Pull Request 规范

沿用简洁的中文提交格式，例如 `修复：...`、`文档：...`、`交互：...`、`语音：...` 或 `计划：...`。每个提交只处理一个明确主题，不添加 Agent 身份信息。Pull Request 应说明行为变化、列出实际执行的验证，并关联相关 issue 或设计文档。涉及可见 UI 变化时附截图或录屏；未验证的模拟器、真机、网络服务商或权限场景必须明确列出。

## 安全与配置

不要提交 API Key、Token、`.xcresult` 包或本地 DerivedData。服务商凭据只能通过 `KeychainStore` 保存；禁止在日志中输出密钥，也不要将密钥写入 UserDefaults。

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目简介

WBChatApp —— 接入 DeepSeek 的 AI 聊天 iOS App，作为面试作品。技术栈 SwiftUI + SwiftData + MVVM。唯一的三方依赖是 [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui)（SPM 引入），其余全部用系统框架实现。最低 iOS 17。完整功能清单与架构图见 `README.md`。

## 仓库结构说明

git 仓库根目录是**上级**目录（`WBAIProject/`），而非当前 app 目录。Xcode 工程在 `WBChatApp/WBChatApp.xcodeproj`。执行 `git` 命令请在仓库根目录，执行 `xcodebuild` 请在当前 `WBChatApp/` 目录（或显式传 `-project` 路径）。

## 常用命令

构建：
```bash
xcodebuild -project WBChatApp.xcodeproj -scheme WBChatApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

运行全部测试（单元 + UI）：
```bash
xcodebuild -project WBChatApp.xcodeproj -scheme WBChatApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

运行单个测试（Swift Testing 与 XCUITest 用同一个 `-only-testing` 选择器，格式 `Target/Suite/testName`）：
```bash
xcodebuild -project WBChatApp.xcodeproj -scheme WBChatApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WBChatAppUITests/WBChatAppUITests/testSendMessageStreamsMockReply test
```

工程使用 **fileSystemSynchronizedGroups**：在 `WBChatApp/` 下磁盘新增的文件会自动纳入 target —— 新增 Swift 文件无需改 `project.pbxproj`。工程已开启默认 MainActor 隔离。

## 架构

单向依赖：**View → ViewModel → Core（Network / Storage）**。状态管理用 Apple 的 Observation 框架（`@Observable`），不是 ObservableObject。

- `App/` —— 入口、`RootView`（抽屉 + 聊天页组合）、`DrawerContainerView`（手势驱动的抽屉）、`AppRouter`（抽屉/设置的导航状态）、`UITestSeeder`。
- `Features/` —— `Chat/`、`ConversationList/`、`VoiceInput/`、`Settings/`；View 与 ViewModel 就近放置。
- `Core/Network/` —— SSE 流式客户端、解析器、DTO、错误定义。
- `Core/Storage/` —— SwiftData `@Model`、`ChatStore` 仓储层、Keychain、`AppSettings`。

### 流式管道（App 的核心）

`ChatStreaming` 是协议，有两个实现：`DeepSeekClient`（真实，OpenAI 兼容的 `POST /chat/completions`，`stream: true`）和 `MockChatClient`（演示模式）。`ChatViewModel.makeClient()` 在 `settings.isConfigured` 为 false 时选用 Mock，因此无 API Key 也能离线跑完整交互。

`DeepSeekClient` 通过 `URLSession.bytes(for:).lines` 逐行读取 SSE 响应，交给纯函数 `SSEParser` 解析，再经 `AsyncThrowingStream` 吐出 `StreamChunk`。取消经由 `continuation.onTermination` → `task.cancel()` 传递。在 `ChatViewModel.stream` 中，`CancellationError` / `URLError.cancelled` 被刻意吞掉，以便用户主动「停止」时保留并落库已生成的部分内容。

流式期间 UI 刷新**按 50ms 节流**（`ChatViewModel.flushInterval`），避免每个 token 都重新解析 Markdown。生成中的正文存在 `streamingContent` / `streamingReasoning`，只有在 `finishStreaming` 才写入 SwiftData。

### 多版本消息

`Message.contents` 与 `Message.reasoningContents` 是按 `currentVersionIndex` 一一对应的平行数组。「重新生成」是追加新版本（`appendVersion`）而非覆盖，支撑 UI 上的 `< i/n >` 版本切换。重新生成时用的是目标 assistant 消息**之前**的历史（`payloads(for:before:)`）。

### 深度思考

「深度思考」开关不是走独立接口 —— `settings.requestConfig(deepThinking:)` 把模型切成 `deepseek-reasoner`，其响应包含推理流（`deltaReasoning`），渲染在可折叠区域里。

### 依赖注入的坑

- `ModelContext` 无法在 `init` 时拿到，因此 `ChatViewModel.configure(context:)` 在 `RootView.onAppear` 调用，用来懒构建 `ChatStore`。
- `RootView` 中，`.environment(router)` / `.environment(settings)` 放在 `.sheet(...)` **之后**，设置页（独立的 view tree）才能继承到它们。放在 `.sheet` 之前会触发 “No Observable object of type AppSettings found” 崩溃 —— 有回归 UI 测试（`testOpensSettingsSheet`）守护此点。

## 测试说明

- 单元测试用 **Swift Testing** 框架；UI 测试用 XCUITest。
- 启动参数 `--uitest-seed` 触发 `UITestSeeder`，它会**清空并重建**会话数据（克隆模拟器会残留旧数据，故需先清空），并预填一条草稿。`testCaptureReadmeScreenshots` 用它生成 README 截图（通过 `xcrun xcresulttool export attachments` 从结果包导出）。
- 关键无障碍标识符：`chat.input`、`chat.send`、`chat.menu`。

## 约定

- 注释与 commit message 用中文，与现有代码保持一致。
- **本仓库的 commit 不加任何 `Co-Authored-By` 尾行。**
- API Key 只存 Keychain —— 不进 UserDefaults，不进代码。

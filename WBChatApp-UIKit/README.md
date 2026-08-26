# WBChatApp-UIKit

用 UIKit + MVVM 实现的仿 iOS 端 ChatGPT 客户端，作为 iOS 开发面试作品。核心技术点：SSE 流式输出、Markdown 块级增量渲染（O(n²) → O(n)）、流式期间的滚动手势冲突处理、OpenAI/Anthropic 双协议适配、语音转文字。

同仓库还有一份 SwiftUI 实现 [`WBChatApp`](../WBChatApp)，两者对同一产品需求做了不同技术路线的实现，可对照阅读 `doc/00-架构总览.md` 最后一节的选型对比。

## 功能截图

截图存放于 `Screenshots/` 目录（当前仓库尚未创建该目录），建议覆盖以下场景并在此处以 Markdown 图片语法引用：聊天页流式输出、Markdown 代码块高亮、左侧会话抽屉、设置页服务商配置、语音输入浮层、深色模式。

## 最低系统与依赖

- **Deployment Target**：iOS 16.0
- **开发环境**：Xcode 26.5 / iOS 26.5 SDK（工程 `objectVersion = 77`，启用 `fileSystemSynchronizedGroups`）
- **语言/并发模型**：Swift 6，`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`（Core 层默认非隔离，ViewModel/ViewController/视图类显式标 `@MainActor`）
- **三方依赖**（Swift Package Manager，版本已在 `Package.resolved` 锁定）：
  - [`swift-markdown`](https://github.com/swiftlang/swift-markdown) 0.8.0（传递依赖 `swift-cmark` 0.8.0）
  - [`GRDB.swift`](https://github.com/groue/GRDB.swift) 7.11.1
- **系统框架**：UIKit、TextKit 2（`UITextView` 默认引擎）、Swift Concurrency、Speech、AVFoundation、Security（Keychain）

## 如何配置 API Key 跑起来

1. 用 Xcode 打开 `WBChatApp-UIKit.xcodeproj`，选择 `WBChatApp-UIKit` scheme，在真机或 iPhone 17 Pro 模拟器上运行。
2. 首次启动无需任何配置即可使用（自动进入演示模式，见下）。
3. 要接入真实模型：点击左上角菜单图标打开会话抽屉 → 点击右上角齿轮进入「设置」：
   - **服务商**：DeepSeek / OpenAI / Anthropic 三选一
   - **模型**：按所选服务商列出的可用模型
   - **接口地址**：默认填好各家官方 `baseURL`，如走中转/代理服务可自行修改
   - **API Key**：安全考虑不明文回显，输入框留空点确定表示「不修改现有 Key」；要清空需点专门的「清除 Key」按钮
   - **系统提示词**：默认给了一句通用提示词，可自定义
   - **测试连接**：发一条极短的请求验证 Key 与地址是否可用
4. API Key 只落 Keychain（`KeychainStore`，service 为 `com.wenbo.WBChatApp-UIKit`，每个服务商独立一条），不会出现在 UserDefaults 或任何日志里。

## 演示模式说明

未配置 API Key 时，`AppContainer.makeProvider()` 会自动注入 `MockProvider` 而不是真实网络请求（`Core/LLM/MockProvider.swift`），按固定节奏（每 3 字符一次、间隔 20ms）吐出一段内置的 Markdown 脚本，内容覆盖标题、段落、粗斜体、行内代码、有序/无序列表、代码块（语法高亮）、表格、分割线——刻意设计成能验证整条渲染管线（切块 → 渲染 → 缓存 → 复用池）的最小样本，保证 App 在没有任何网络/Key 配置的情况下依然开箱可用、可演示。

## 五篇技术文档索引

详细的架构决策与实现细节记录在 `doc/` 目录：

1. [`doc/00-架构总览.md`](doc/00-架构总览.md) —— 分层架构、模块职责、MVVM 契约、技术选型理由、与 SwiftUI 版对照
2. [`doc/01-流式链路与双协议适配.md`](doc/01-流式链路与双协议适配.md) —— SSE 协议解析、OpenAI/Anthropic 双协议帧格式、节流策略、取消与错误处理
3. [`doc/02-Markdown块级增量渲染.md`](doc/02-Markdown块级增量渲染.md) —— 全项目技术含量最高的部分：O(n²) → O(n) 的复杂度分析、切块状态机、TextKit 2 降级陷阱、高度策略、复用池设计
4. [`doc/03-滚动与自动贴底.md`](doc/03-滚动与自动贴底.md) —— pinned/detached 状态机、与 ChatGPT 行为逐条对照、程序化滚动与用户滚动的区分
5. [`doc/04-语音输入.md`](doc/04-语音输入.md) —— 权限双授权流程、音频管线（一路 tap 两用）、RMS 转波形算法、端上/在线识别取舍

## 测试

单元测试用 [Swift Testing](https://developer.apple.com/documentation/testing)（`import Testing`），UI 测试用 XCTest。当前基线：单元测试 236 条 + UI 冒烟测试 1 条，全绿。

全量测试（模拟器目标必须显式带 `OS=26.5`，省略会报 "Unable to find a device matching..."）：

```bash
xcodebuild test \
  -project WBChatApp-UIKit.xcodeproj \
  -scheme WBChatApp-UIKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

只跑单元测试 target（排除 UI 测试）：

```bash
xcodebuild test \
  -project WBChatApp-UIKit.xcodeproj \
  -scheme WBChatApp-UIKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:WBChatApp-UIKitTests
```

由于 `xcodebuild` 的人类可读日志在高输出量下会静默丢行，权威的用例计数与通过率建议从 xcresult 里核对：

```bash
RESULT=$(ls -dt ~/Library/Developer/Xcode/DerivedData/WBChatApp-UIKit-*/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool get test-results summary --path "$RESULT" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['totalTestCount'], d['passedTests'], d['failedTests'], d['skippedTests'])"
```

两条工程红线自查（详见 `doc/00-架构总览.md` 与 `doc/02-Markdown块级增量渲染.md`）：

```bash
# TextKit 2 降级扫描：预期无输出
grep -rn "layoutManager\|\.textStorage" WBChatApp-UIKit --include=*.swift

# ViewModel 纯净性扫描：预期无输出
grep -l "import UIKit" WBChatApp-UIKit/Features/*/[A-Za-z]*ViewModel.swift
```

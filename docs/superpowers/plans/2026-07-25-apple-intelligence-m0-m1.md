# WBAppleIntelligence Plan 1：骨架 + Foundation Models 四件套

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `WBAppleIntelligence` 从空模板做成一个可运行的端侧 AI 能力目录 App，完成 Foundation Models 四个核心 Demo（可用性探测 / 流式客服助手 / 结构化工单抽取 / 工具调用）与配套的 5 篇技术文档。

**Architecture:** 分层「AIKit（纯能力层，不 import SwiftUI）+ Features（@Observable ViewModel + View）+ DesignSystem（共用展示组件）」。AIKit 层的每个类型都能被单独单测与复制进真实项目；Features 层只做状态编排与展示。

**Tech Stack:** SwiftUI、Observation、FoundationModels、Swift Testing、Xcode 26.5 / iOS 26.5 SDK。

对应 spec：`docs/superpowers/specs/2026-07-25-apple-intelligence-sample-design.md`（M0 + M1）。

**与 spec 的一处有意偏差：** spec 的 M0 验收写的是「首页可导航到 7 个占位页」。本计划只建 4 个路由——spec 里的另外 3 个（单据数字化、语义知识库、会议纪要）属于 Plan 2 与 Plan 3，届时各自往 `DemoRoute` 里追加 case 即可，不需要预留占位。

## Global Constraints

以下约束适用于**每一个任务**，不再在单个任务里重复：

- Deployment target **iOS 26.5**；Xcode 26.5；`SWIFT_VERSION = 5.0`（Swift 5 语言模式）。
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 已开启。所有类型默认主线程隔离；需要脱离主线程的类型必须显式写 `nonisolated`。

  **`AIKit/` 下的纯值类型一律显式标 `nonisolated`。** 这一层被 actor 与 nonisolated 上下文消费（`Tool.call` 是 nonisolated 的），不标就会报
  `main actor-isolated conformance of 'X' to 'Equatable' cannot be used in nonisolated context; this is an error in the Swift 6 language mode`。

  **关键细节（Task 5 实测踩到并已验证）：extension 不继承类型声明上的 `nonisolated`，必须逐个 extension 单独标。** 例如：

  ```swift
  nonisolated enum ModelAvailability: Equatable { ... }
  nonisolated extension ModelAvailability.Reason { var title: String { ... } }
  ```

  已按此模式处理的既有类型（提交 `91e6d6a`）：`ModelAvailability`、`ModelAvailability.Reason`、`AIKitError`、`GenerationMetrics`、`MetricsTimer` 及其全部 extension。

  **这条规则优先于后文各任务代码块里的写法** —— 那些代码块是在本约束确立之前写的，凡与本条冲突处以本条为准。后续任务中必须补 `nonisolated` 的类型（各任务代码块中均未写）：

  | 任务 | 类型 |
  |---|---|
  | Task 7 | `TranscriptTrimmer` ✅ 已处理 |
  | Task 8 | `Prompts` ✅ 已处理、`ChatOutcome` ✅ 已处理 |
  | Task 10 | `ServiceTicket`、`TicketCategory`、`TicketPriority`、`TicketOutcome` 及三个 extension |
  | Task 12 | `MockEnterpriseBackend`（简报已写 `nonisolated`）、`InventoryQuery`、`OrderQuery` |
  | Task 13 | `ToolCallRecord`、`ToolCallOutcome` |

  `@MainActor` 标注的服务类（`StreamingChatService`、`TicketExtractionService`、`ToolCallingService`）**不要**改成 `nonisolated` —— 它们持有 `LanguageModelSession` 并由 SwiftUI 驱动，主线程隔离是有意为之。
- **正则字面量必须写成 `#/.../#`**。裸斜杠形式 `/.../` 在 Swift 5 语言模式下未启用，会报 `'/' is not a prefix unary operator`（已实测）。
- 源码文件一律放在 `WBAppleIntelligence/WBAppleIntelligence/` 下（`fileSystemSynchronizedGroups`，建文件即自动入 target，**不要手改 pbxproj 添加文件**）。
- 文档放在 `WBAppleIntelligence/Docs/`，位于同步组之外，不会被打进 App bundle。
- `AIKit/` 下的任何文件**禁止 `import SwiftUI`**。
- 注释、UI 文案、文档一律中文。注释解释「为什么」，不复述代码。
- 每个任务结束时必须 **0 error，且 0 个 Swift 编译器 warning**。

  唯一允许存在的例外是基线就有的一条工具链警告（已在 `2479c9c` 基线提交上实测确认，与本计划的任何改动无关）：

  ```
  appintentsmetadataprocessor: warning: Metadata extraction skipped. No AppIntents.framework dependency found.
  ```

  它由 `appintentsmetadataprocessor` 对任何未链接 AppIntents.framework 的 app target 发出，等 Plan 3 引入 App Intents 后会自然消失。**不要为了消掉它而改工程配置**。核验警告数用：

  ```bash
  xcodebuild -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' clean build 2>&1 | grep -E " warning: " | grep -v "No AppIntents.framework dependency found" | wc -l
  ```

  预期输出 `0`。

  **`clean` 不能省。** 增量构建不会重新编译未改动的模块，因此**跨文件的隔离类警告在增量构建下不会出现**。Task 5 实测踩到过：`main actor-isolated conformance of 'ModelAvailability.Reason' to 'Equatable' cannot be used in nonisolated context` 这条只在 `clean build` 下暴露，用增量 `build` 计数会得到假的 `0`。
- Git commit message 用中文，**不加任何 AI 协作署名尾行**（`Co-Authored-By` 等一律不要）。
- 所有命令都在 `/Users/wenbo/Desktop/WBAIProject/WBAppleIntelligence` 目录下执行。

**已实测通过的构建命令**（`OS=26.5` 不可省略——省略后 `OS:latest` 会解析到没有设备的 iOS 27.0 运行时，报 `Unable to find a device matching the provided destination specifier`）：

```bash
xcodebuild -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

**已实测通过的单元测试命令**：

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

**运行环境提醒：** 本机区域为 `zh_CN`，`SystemLanguageModel.default.availability` 返回 `unavailable(.deviceNotEligible)`，且模拟器的 Foundation Models 走宿主 Mac 的模型。因此**模拟器上所有 LLM Demo 只能验证「不可用引导」路径**，真实推理需在 iPhone 15 Pro+ 真机（区域美国、已开启 Apple Intelligence 并下载完模型）上验证。

**关于真机步骤的统一约定（覆盖后文所有任务中的「真机验收」条目）：** 实现者手上没有真机，**不要尝试执行任何标注为「真机验收」的步骤，也不要因为无法执行而阻塞或报 BLOCKED**。这些步骤由项目负责人在全部任务完成后统一走查。实现者只需：

1. 完成代码、单元测试与**模拟器**目视验收；
2. 文档中凡是需要真机实测数字的位置（首字延迟、token 速率、schema token 数、预热前后对比等），写成醒目的占位块，格式统一为：
   ```
   > **待真机实测**：<说明要测什么、怎么测>
   ```
   不要编造、估算或从别处引用数字。

Task 14 Step 5 是项目负责人执行的步骤，实现者跳过即可。

---

## File Structure

| 文件 | 职责 |
|---|---|
| `WBAppleIntelligence/App/WBAppleIntelligenceApp.swift` | App 入口，只负责挂载 `RootView` |
| `WBAppleIntelligence/App/DemoRoute.swift` | 能力目录的路由枚举，承载每个 Demo 的标题/场景/框架元信息 |
| `WBAppleIntelligence/App/RootView.swift` | 能力目录首页与导航分发 |
| `WBAppleIntelligence/AIKit/Core/ModelAvailability.swift` | 端侧模型可用性的领域表示与中文引导文案 |
| `WBAppleIntelligence/AIKit/Core/AIKitError.swift` | 统一错误域，映射 `GenerationError` 全部 9 个 case |
| `WBAppleIntelligence/AIKit/Core/GenerationMetrics.swift` | 生成指标数据结构与单调时钟采样器 |
| `WBAppleIntelligence/AIKit/Core/TranscriptTrimmer.swift` | Transcript 裁剪纯函数，供上下文超限恢复使用 |
| `WBAppleIntelligence/AIKit/Core/Prompts.swift` | 各 Demo 的 instructions 常量集中管理 |
| `WBAppleIntelligence/AIKit/Chat/StreamingChatService.swift` | 流式对话、指标采集、上下文超限自动恢复 |
| `WBAppleIntelligence/AIKit/Extraction/ServiceTicket.swift` | `@Generable` 工单模型与枚举 |
| `WBAppleIntelligence/AIKit/Extraction/TicketExtractionService.swift` | 结构化抽取，流式暴露 `PartiallyGenerated` |
| `WBAppleIntelligence/AIKit/Tools/MockEnterpriseBackend.swift` | 模拟企业内部系统的确定性数据源 |
| `WBAppleIntelligence/AIKit/Tools/EnterpriseTools.swift` | 两个 `Tool` 实现及其 `@Generable` 参数类型 |
| `WBAppleIntelligence/AIKit/Tools/ToolCallingService.swift` | 带工具的会话，暴露工具调用轨迹 |
| `WBAppleIntelligence/DesignSystem/ScenarioCard.swift` | Demo 顶部的场景与价值说明卡片 |
| `WBAppleIntelligence/DesignSystem/DemoScaffold.swift` | Demo 页面统一骨架 |
| `WBAppleIntelligence/DesignSystem/AvailabilityBanner.swift` | 可用性状态横幅 |
| `WBAppleIntelligence/DesignSystem/MetricsBar.swift` | 生成指标展示条 |
| `WBAppleIntelligence/DesignSystem/ErrorView.swift` | 统一错误展示 |
| `WBAppleIntelligence/Features/Availability/AvailabilityDemoView.swift` | Demo 1 |
| `WBAppleIntelligence/Features/Chat/ChatViewModel.swift` + `ChatDemoView.swift` | Demo 2 |
| `WBAppleIntelligence/Features/TicketExtraction/TicketExtractionViewModel.swift` + `TicketExtractionDemoView.swift` | Demo 3 |
| `WBAppleIntelligence/Features/ToolCalling/ToolCallingViewModel.swift` + `ToolCallingDemoView.swift` | Demo 4 |
| `WBAppleIntelligenceTests/*.swift` | Swift Testing 单测 |
| `Docs/README.md` + `Docs/01..04-*.md` | 技术文档 |

---

## Task 1: 工程骨架重组与权限配置

**Files:**
- Create: `WBAppleIntelligence/App/WBAppleIntelligenceApp.swift`
- Delete: `WBAppleIntelligence/WBAppleIntelligenceApp.swift`、`WBAppleIntelligence/ContentView.swift`
- Create: `WBAppleIntelligence/App/DemoRoute.swift`
- Modify: `WBAppleIntelligence.xcodeproj/project.pbxproj`（app target 的两处 `buildSettings`，Debug 与 Release 各一处）

**Interfaces:**
- Produces: `enum DemoRoute: String, CaseIterable, Identifiable, Hashable`，成员 `availability` / `streamingChat` / `ticketExtraction` / `toolCalling`，属性 `id: String`、`title: String`、`scenario: String`、`value: String`、`frameworks: String`、`systemImage: String`

- [ ] **Step 1: 建立 App 目录并移动入口文件**

```bash
mkdir -p WBAppleIntelligence/App
git mv WBAppleIntelligence/WBAppleIntelligenceApp.swift WBAppleIntelligence/App/WBAppleIntelligenceApp.swift
git rm WBAppleIntelligence/ContentView.swift
```

- [ ] **Step 2: 改写 App 入口**

写入 `WBAppleIntelligence/App/WBAppleIntelligenceApp.swift`：

```swift
import SwiftUI

@main
struct WBAppleIntelligenceApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

- [ ] **Step 3: 创建路由枚举**

写入 `WBAppleIntelligence/App/DemoRoute.swift`：

```swift
import Foundation

/// 能力目录的路由。
///
/// 用枚举而不是 `AnyView` 承载导航目标，一是保证类型安全，二是让每个 Demo 的
/// 「场景 / 价值 / 所用框架」这些元信息有唯一出处，首页列表与详情页头部共用同一份数据。
enum DemoRoute: String, CaseIterable, Identifiable, Hashable {
    case availability
    case streamingChat
    case ticketExtraction
    case toolCalling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .availability: "端侧可用性探测"
        case .streamingChat: "流式客服助手"
        case .ticketExtraction: "结构化工单抽取"
        case .toolCalling: "工具调用接内部系统"
        }
    }

    /// 这个能力在企业里对应的真实场景。
    var scenario: String {
        switch self {
        case .availability:
            "上线前判断当前设备能否使用端侧模型，决定走 AI 路径还是传统路径。"
        case .streamingChat:
            "内部知识客服：员工用自然语言提问，答案逐字流式呈现，全程不联网。"
        case .ticketExtraction:
            "服务台工单录入：把用户的口语描述实时抽取成强类型工单，边生成边填表。"
        case .toolCalling:
            "让模型调用库存、订单等内部系统接口，用自然语言完成原本要点五六个页面的查询。"
        }
    }

    /// 相比传统实现或云端方案的价值点。
    var value: String {
        switch self {
        case .availability:
            "端侧能力不是「有或没有」而是「按设备分布」，可用性探测是灰度策略的地基。"
        case .streamingChat:
            "对话内容不出设备，天然满足数据不出境与内部资料保密要求；无 token 费用，无网络延迟。"
        case .ticketExtraction:
            "结构化输出由 schema 强约束，解析不会失败；录入耗时从分钟级降到秒级。"
        case .toolCalling:
            "模型只拿到工具的返回值，业务数据的访问边界由你的代码控制，不需要把数据喂给云端模型。"
        }
    }

    var frameworks: String {
        "FoundationModels"
    }

    var systemImage: String {
        switch self {
        case .availability: "checkmark.seal"
        case .streamingChat: "bubble.left.and.text.bubble.right"
        case .ticketExtraction: "list.clipboard"
        case .toolCalling: "wrench.and.screwdriver"
        }
    }
}
```

- [ ] **Step 4: 添加权限文案到 pbxproj**

工程用 `GENERATE_INFOPLIST_FILE = YES`，没有实体 Info.plist，权限文案必须以 build setting 形式写入。

在 `WBAppleIntelligence.xcodeproj/project.pbxproj` 中找到 app target 的两个 `XCBuildConfiguration`（识别方法：`buildSettings` 里含 `PRODUCT_BUNDLE_IDENTIFIER = com.wb.WBAppleIntelligence;`，Debug 与 Release 各一处，**不要改 Tests 和 UITests 的**）。在每一处的 `INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;` 这一行**之前**插入下面四行（保持 tab 缩进与周围一致）：

```
				INFOPLIST_KEY_NSCameraUsageDescription = "拍摄纸质单据并在设备本地完成识别，图像不会离开这台设备。";
				INFOPLIST_KEY_NSMicrophoneUsageDescription = "录制会议音频并在设备本地转写，录音不会离开这台设备。";
				INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "从相册选择单据图片进行本地识别，图片不会离开这台设备。";
				INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "在设备本地把语音转成文字，音频不会上传到服务器。";
```

这四条现在就加齐，是因为 Plan 2 / Plan 3 会用到相机、相册与麦克风，权限配置属于一次性的工程设置，分散到后面反而容易漏。

- [ ] **Step 5: 建立占位 RootView**

Step 2 的入口引用了尚不存在的 `RootView`，必须先补上占位实现工程才能编译。写入 `WBAppleIntelligence/App/RootView.swift`（Task 5 会替换为正式实现）：

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("能力目录")
    }
}

#Preview {
    RootView()
}
```

- [ ] **Step 6: 验证构建**

```bash
xcodebuild -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

预期：末尾输出 `** BUILD SUCCEEDED **`。

- [ ] **Step 7: 验证权限文案已进入产物**

```bash
plutil -p "$(xcodebuild -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/WBAppleIntelligence.app/Info.plist" | grep -E "NSCamera|NSMicrophone|NSPhotoLibrary|NSSpeech"
```

预期：输出四行，分别是四条中文权限文案。若为空，说明插入位置进错了 target 的 buildSettings。

- [ ] **Step 8: 提交**

```bash
git add -A WBAppleIntelligence WBAppleIntelligence.xcodeproj
git commit -m "骨架：重组入口目录，新增能力目录路由与权限文案配置"
```

---

## Task 2: ModelAvailability 领域模型

**Files:**
- Create: `WBAppleIntelligence/AIKit/Core/ModelAvailability.swift`
- Test: `WBAppleIntelligenceTests/ModelAvailabilityTests.swift`

**Interfaces:**
- Produces: `enum ModelAvailability: Equatable`（`available` / `unavailable(Reason)`），嵌套 `enum Reason: Equatable`（`deviceNotEligible` / `appleIntelligenceNotEnabled` / `modelNotReady` / `unknown`）；`init(_ availability: SystemLanguageModel.Availability)`；`var isAvailable: Bool`；`static var current: ModelAvailability`；`Reason` 上的 `title` / `detail` / `recovery` 三个 `String` 属性

- [ ] **Step 1: 写失败的测试**

创建 `WBAppleIntelligenceTests/ModelAvailabilityTests.swift`：

```swift
import Testing
@testable import WBAppleIntelligence

struct ModelAvailabilityTests {

    @Test("可用状态的 isAvailable 为真")
    func availableIsAvailable() {
        #expect(ModelAvailability.available.isAvailable)
    }

    @Test("不可用状态的 isAvailable 为假")
    func unavailableIsNotAvailable() {
        #expect(!ModelAvailability.unavailable(.deviceNotEligible).isAvailable)
    }

    @Test("每种不可用原因都有非空的标题、说明与操作建议", arguments: [
        ModelAvailability.Reason.deviceNotEligible,
        .appleIntelligenceNotEnabled,
        .modelNotReady,
        .unknown
    ])
    func everyReasonHasCopy(_ reason: ModelAvailability.Reason) {
        #expect(!reason.title.isEmpty)
        #expect(!reason.detail.isEmpty)
        #expect(!reason.recovery.isEmpty)
    }

    @Test("四种原因的文案两两不同，避免复制粘贴时漏改")
    func reasonCopyIsDistinct() {
        let details = [
            ModelAvailability.Reason.deviceNotEligible,
            .appleIntelligenceNotEnabled,
            .modelNotReady,
            .unknown
        ].map(\.detail)
        #expect(Set(details).count == details.count)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：编译失败，报 `cannot find 'ModelAvailability' in scope`。

- [ ] **Step 3: 实现**

创建 `WBAppleIntelligence/AIKit/Core/ModelAvailability.swift`：

```swift
import FoundationModels

/// 端侧模型可用性的领域表示。
///
/// 把 `SystemLanguageModel.Availability` 翻译成可以直接呈现给用户的中文说明与操作建议。
/// 单独建这层是因为：`UnavailableReason` 是非 frozen 枚举，系统升级可能新增 case，
/// 集中在这里加 `@unknown default` 兜底，业务代码就不必到处处理未知情况。
enum ModelAvailability: Equatable {
    case available
    case unavailable(Reason)

    enum Reason: Equatable, Hashable, CaseIterable {
        /// 机型不满足要求，或设备区域 / 系统语言不在 Apple Intelligence 支持范围内。
        case deviceNotEligible
        /// 机型支持，但用户尚未在系统设置中开启 Apple Intelligence。
        case appleIntelligenceNotEnabled
        /// 已开启，但模型资源仍在下载或尚未就绪。
        case modelNotReady
        /// SDK 未来新增的原因。
        case unknown
    }

    init(_ availability: SystemLanguageModel.Availability) {
        switch availability {
        case .available:
            self = .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                self = .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                self = .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                self = .unavailable(.modelNotReady)
            @unknown default:
                self = .unavailable(.unknown)
            }
        }
    }

    /// 读取系统当前状态。
    ///
    /// 在 SwiftUI 的 `body` 里应改为访问 `SystemLanguageModel.default.availability`——
    /// 该类型遵循 `Observable`，这样用户在系统设置里开启 Apple Intelligence 后界面会自动刷新。
    static var current: ModelAvailability {
        ModelAvailability(SystemLanguageModel.default.availability)
    }

    var isAvailable: Bool {
        self == .available
    }

    var reason: Reason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

extension ModelAvailability.Reason {
    var title: String {
        switch self {
        case .deviceNotEligible: "此设备不支持端侧模型"
        case .appleIntelligenceNotEnabled: "尚未开启 Apple Intelligence"
        case .modelNotReady: "模型尚未就绪"
        case .unknown: "端侧模型当前不可用"
        }
    }

    var detail: String {
        switch self {
        case .deviceNotEligible:
            "需要 iPhone 15 Pro 及以上机型，且设备区域与系统语言需在 Apple Intelligence 支持范围内。中国大陆区域目前不在支持范围内。"
        case .appleIntelligenceNotEnabled:
            "设备支持端侧模型，但用户还没有在系统设置里打开 Apple Intelligence 开关。"
        case .modelNotReady:
            "开关已打开，但模型文件仍在下载或正在准备中。模型体积以 GB 计，首次启用需要时间与网络。"
        case .unknown:
            "系统返回了当前 App 尚未识别的不可用原因，可能来自更高版本的系统。"
        }
    }

    /// 给用户的下一步操作建议。企业 App 里这段文案直接决定了工单量。
    var recovery: String {
        switch self {
        case .deviceNotEligible:
            "请在支持的机型上使用，或继续使用不依赖端侧模型的常规功能。"
        case .appleIntelligenceNotEnabled:
            "请前往「设置 → Apple 智能与 Siri」开启 Apple Intelligence。"
        case .modelNotReady:
            "请保持网络连接并接入电源，稍后重试。"
        case .unknown:
            "请稍后重试；若持续出现，请升级 App 到最新版本。"
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：`** TEST SUCCEEDED **`。

- [ ] **Step 5: 提交**

```bash
git add WBAppleIntelligence/AIKit WBAppleIntelligenceTests/ModelAvailabilityTests.swift
git commit -m "AIKit：端侧模型可用性领域模型与中文引导文案"
```

---

## Task 3: AIKitError 统一错误域

**Files:**
- Create: `WBAppleIntelligence/AIKit/Core/AIKitError.swift`
- Test: `WBAppleIntelligenceTests/AIKitErrorTests.swift`

**Interfaces:**
- Consumes: `ModelAvailability.Reason`（Task 2）
- Produces: `enum AIKitError: LocalizedError, Equatable`，case 为 `modelUnavailable(ModelAvailability.Reason)` / `contextWindowExceeded` / `guardrailViolation` / `unsupportedLanguage` / `assetsUnavailable` / `rateLimited` / `concurrentRequests` / `refused` / `decodingFailure(String)` / `unsupportedGuide(String)` / `emptyResponse` / `underlying(String)`；`init(_ error: any Error)`

- [ ] **Step 1: 写失败的测试**

创建 `WBAppleIntelligenceTests/AIKitErrorTests.swift`：

```swift
import Foundation
import Testing
@testable import WBAppleIntelligence

struct AIKitErrorTests {

    @Test("非 FoundationModels 的错误被归入 underlying")
    func wrapsForeignError() {
        let foreign = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "网络断开"])
        let error = AIKitError(foreign)
        #expect(error == .underlying("网络断开"))
    }

    @Test("已经是 AIKitError 时原样返回，不会被重复包一层")
    func doesNotDoubleWrap() {
        let original = AIKitError.contextWindowExceeded
        #expect(AIKitError(original) == original)
    }

    @Test("每个 case 都有非空的描述与恢复建议", arguments: AIKitError.allCasesForCopyCheck)
    func everyCaseHasCopy(_ error: AIKitError) {
        #expect(!(error.errorDescription ?? "").isEmpty)
        #expect(!(error.recoverySuggestion ?? "").isEmpty)
    }

    @Test("上下文超限的建议里要明确提到会裁剪早期对话，避免用户以为数据丢了")
    func contextWindowCopyMentionsTrimming() {
        let suggestion = AIKitError.contextWindowExceeded.recoverySuggestion ?? ""
        #expect(suggestion.contains("裁剪"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：编译失败，报 `cannot find 'AIKitError' in scope`。

- [ ] **Step 3: 实现**

创建 `WBAppleIntelligence/AIKit/Core/AIKitError.swift`：

```swift
import Foundation
import FoundationModels

/// AIKit 的统一错误域。
///
/// 存在的意义是把 `LanguageModelSession.GenerationError` 这类框架错误一次性翻译成
/// 「用户看得懂的描述 + 能照做的建议」，避免每个 Demo 各写一遍 switch。
/// `GenerationError` 是非 frozen 枚举，映射集中在这里也便于系统升级时统一兜底。
enum AIKitError: LocalizedError, Equatable {
    case modelUnavailable(ModelAvailability.Reason)
    case contextWindowExceeded
    case guardrailViolation
    case unsupportedLanguage
    case assetsUnavailable
    case rateLimited
    case concurrentRequests
    case refused
    case decodingFailure(String)
    case unsupportedGuide(String)
    /// 流式响应一个增量都没产生就结束了。
    case emptyResponse
    case underlying(String)

    init(_ error: any Error) {
        if let alreadyMapped = error as? AIKitError {
            self = alreadyMapped
            return
        }
        guard let generation = error as? LanguageModelSession.GenerationError else {
            self = .underlying(error.localizedDescription)
            return
        }
        switch generation {
        case .exceededContextWindowSize:
            self = .contextWindowExceeded
        case .guardrailViolation:
            self = .guardrailViolation
        case .unsupportedLanguageOrLocale:
            self = .unsupportedLanguage
        case .assetsUnavailable:
            self = .assetsUnavailable
        case .rateLimited:
            self = .rateLimited
        case .concurrentRequests:
            self = .concurrentRequests
        case .refusal:
            self = .refused
        case .decodingFailure(let context):
            self = .decodingFailure(context.debugDescription)
        case .unsupportedGuide(let context):
            self = .unsupportedGuide(context.debugDescription)
        @unknown default:
            self = .underlying(generation.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): reason.title
        case .contextWindowExceeded: "对话内容超出了模型的上下文窗口"
        case .guardrailViolation: "内容被安全护栏拦截"
        case .unsupportedLanguage: "当前语言或地区不受支持"
        case .assetsUnavailable: "模型资源不可用"
        case .rateLimited: "请求过于频繁"
        case .concurrentRequests: "上一次生成尚未结束"
        case .refused: "模型拒绝回答本次请求"
        case .decodingFailure: "模型输出无法解析成目标结构"
        case .unsupportedGuide: "结构定义中存在模型不支持的约束"
        case .emptyResponse: "模型没有返回任何内容"
        case .underlying(let message): message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelUnavailable(let reason):
            reason.recovery
        case .contextWindowExceeded:
            "已自动裁剪早期对话后重试。若仍失败，请开启新会话——端侧模型上下文窗口仅 4096 token，长对话必须做裁剪。"
        case .guardrailViolation:
            "请调整措辞后重试。若这是正常业务内容被误拦，可考虑改用 permissiveContentTransformations 护栏级别。"
        case .unsupportedLanguage:
            "请把设备语言切换到模型支持的语言，或改用不依赖端侧模型的路径。"
        case .assetsUnavailable:
            "请检查网络与存储空间，等待系统完成模型下载后重试。"
        case .rateLimited:
            "请稍后再试。App 进入后台时系统会更严格地限流。"
        case .concurrentRequests:
            "请等待当前回答结束，或先取消当前生成。同一个会话不支持并发请求。"
        case .refused:
            "请换一种说法重试。可通过 refusal 的 explanation 获取模型给出的拒绝理由。"
        case .decodingFailure(let detail):
            "请简化结构定义或降低字段数量后重试。诊断信息：\(detail)"
        case .unsupportedGuide(let detail):
            "请检查 @Guide 约束是否被当前模型支持。诊断信息：\(detail)"
        case .emptyResponse:
            "请重试一次；若持续为空，请检查提示词是否为空或过短。"
        case .underlying:
            "请重试；若持续失败，请查看日志中的原始错误信息。"
        }
    }
}

extension AIKitError {
    /// 供测试遍历文案完整性使用。手写而非依赖 `CaseIterable`，
    /// 因为带关联值的 case 无法自动合成。
    static let allCasesForCopyCheck: [AIKitError] = [
        .modelUnavailable(.deviceNotEligible),
        .contextWindowExceeded,
        .guardrailViolation,
        .unsupportedLanguage,
        .assetsUnavailable,
        .rateLimited,
        .concurrentRequests,
        .refused,
        .decodingFailure("测试诊断"),
        .unsupportedGuide("测试诊断"),
        .emptyResponse,
        .underlying("测试原因")
    ]
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：`** TEST SUCCEEDED **`。

- [ ] **Step 5: 提交**

```bash
git add WBAppleIntelligence/AIKit/Core/AIKitError.swift WBAppleIntelligenceTests/AIKitErrorTests.swift
git commit -m "AIKit：统一错误域，覆盖 GenerationError 全部九种情况"
```

---

## Task 4: GenerationMetrics 与耗时采样

**Files:**
- Create: `WBAppleIntelligence/AIKit/Core/GenerationMetrics.swift`
- Test: `WBAppleIntelligenceTests/GenerationMetricsTests.swift`

**Interfaces:**
- Produces: `struct GenerationMetrics: Equatable, Sendable`，属性 `firstTokenLatency: TimeInterval?` / `totalDuration: TimeInterval?` / `promptTokenCount: Int?` / `responseTokenCount: Int?`，计算属性 `tokensPerSecond: Double?`，静态成员 `empty`；`struct MetricsTimer`，方法 `mutating func markFirstToken()` 与 `func finish(promptTokenCount: Int?, responseTokenCount: Int?) -> GenerationMetrics`；`extension Duration { var seconds: TimeInterval }`

- [ ] **Step 1: 写失败的测试**

创建 `WBAppleIntelligenceTests/GenerationMetricsTests.swift`：

```swift
import Foundation
import Testing
@testable import WBAppleIntelligence

struct GenerationMetricsTests {

    @Test("Duration 转秒：1.5 秒")
    func durationToSeconds() {
        let duration = Duration.milliseconds(1500)
        #expect(abs(duration.seconds - 1.5) < 0.000_001)
    }

    @Test("Duration 转秒：亚毫秒精度不被丢弃")
    func durationKeepsSubMillisecondPrecision() {
        let duration = Duration.microseconds(250)
        #expect(abs(duration.seconds - 0.000_25) < 0.000_000_1)
    }

    @Test("每秒 token 数按输出 token 与总耗时计算")
    func tokensPerSecond() {
        let metrics = GenerationMetrics(
            firstTokenLatency: 0.2,
            totalDuration: 4,
            promptTokenCount: 30,
            responseTokenCount: 120
        )
        #expect(metrics.tokensPerSecond == 30)
    }

    @Test("缺少输出 token 数时不给出速率，而不是给 0 误导人")
    func tokensPerSecondNeedsResponseCount() {
        let metrics = GenerationMetrics(totalDuration: 4)
        #expect(metrics.tokensPerSecond == nil)
    }

    @Test("总耗时为零时不做除法")
    func tokensPerSecondGuardsZeroDuration() {
        let metrics = GenerationMetrics(totalDuration: 0, responseTokenCount: 120)
        #expect(metrics.tokensPerSecond == nil)
    }

    @Test("采样器未标记首个增量时不给出首字延迟")
    func timerWithoutFirstToken() {
        let timer = MetricsTimer()
        let metrics = timer.finish(promptTokenCount: nil, responseTokenCount: nil)
        #expect(metrics.firstTokenLatency == nil)
        #expect(metrics.totalDuration != nil)
    }

    @Test("采样器只记录第一次标记，后续标记不覆盖")
    func timerKeepsFirstMark() async throws {
        var timer = MetricsTimer()
        timer.markFirstToken()
        let first = timer.finish(promptTokenCount: nil, responseTokenCount: nil).firstTokenLatency
        try await Task.sleep(for: .milliseconds(20))
        timer.markFirstToken()
        let second = timer.finish(promptTokenCount: nil, responseTokenCount: nil).firstTokenLatency
        #expect(first == second)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：编译失败，报 `cannot find 'GenerationMetrics' in scope`。

- [ ] **Step 3: 实现**

创建 `WBAppleIntelligence/AIKit/Core/GenerationMetrics.swift`：

```swift
import Foundation

extension Duration {
    /// 转成以秒为单位的浮点值。
    ///
    /// `components` 拆出的是秒与阿托秒（1e-18 秒）两段整数，直接相加才能保住亚毫秒精度；
    /// 只取 `components.seconds` 会把 200 毫秒的首字延迟四舍五入成 0。
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

/// 单次生成的性能指标。
///
/// 端侧推理的说服力集中在这几个数字上：首字延迟决定体感，token 速率决定长文本的等待时间，
/// token 数决定会不会撞上 4096 的上下文窗口。所以每个 Demo 都把它们显式展示出来。
struct GenerationMetrics: Equatable, Sendable {
    /// 从发起请求到收到第一个增量的耗时（秒）。非流式调用没有这个值。
    var firstTokenLatency: TimeInterval?
    /// 整次生成的总耗时（秒）。
    var totalDuration: TimeInterval?
    var promptTokenCount: Int?
    var responseTokenCount: Int?

    static let empty = GenerationMetrics()

    /// 输出速率。缺少任一输入时返回 nil 而不是 0——0 会被误读成「卡住了」。
    var tokensPerSecond: Double? {
        guard let responseTokenCount,
              let totalDuration,
              totalDuration > 0
        else { return nil }
        return Double(responseTokenCount) / totalDuration
    }
}

/// 生成过程的耗时采样器。
///
/// 用 `ContinuousClock` 而不是 `Date`：前者是单调时钟，不会因为用户改系统时间或
/// 系统对时而出现负数耗时。
struct MetricsTimer {
    private let start = ContinuousClock.now
    private var firstTokenAt: ContinuousClock.Instant?

    /// 标记收到首个增量。重复调用只有第一次生效。
    mutating func markFirstToken() {
        guard firstTokenAt == nil else { return }
        firstTokenAt = ContinuousClock.now
    }

    func finish(promptTokenCount: Int?, responseTokenCount: Int?) -> GenerationMetrics {
        GenerationMetrics(
            firstTokenLatency: firstTokenAt.map { ($0 - start).seconds },
            totalDuration: (ContinuousClock.now - start).seconds,
            promptTokenCount: promptTokenCount,
            responseTokenCount: responseTokenCount
        )
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：`** TEST SUCCEEDED **`。

- [ ] **Step 5: 提交**

```bash
git add WBAppleIntelligence/AIKit/Core/GenerationMetrics.swift WBAppleIntelligenceTests/GenerationMetricsTests.swift
git commit -m "AIKit：生成指标数据结构与单调时钟采样器"
```

---

## Task 5: DesignSystem 组件与能力目录首页

**Files:**
- Create: `WBAppleIntelligence/DesignSystem/ScenarioCard.swift`
- Create: `WBAppleIntelligence/DesignSystem/DemoScaffold.swift`
- Create: `WBAppleIntelligence/DesignSystem/AvailabilityBanner.swift`
- Create: `WBAppleIntelligence/DesignSystem/MetricsBar.swift`
- Create: `WBAppleIntelligence/DesignSystem/ErrorView.swift`
- Create: `WBAppleIntelligence/Features/Availability/AvailabilityDemoView.swift`（占位）
- Create: `WBAppleIntelligence/Features/Chat/ChatDemoView.swift`（占位）
- Create: `WBAppleIntelligence/Features/TicketExtraction/TicketExtractionDemoView.swift`（占位）
- Create: `WBAppleIntelligence/Features/ToolCalling/ToolCallingDemoView.swift`（占位）
- Modify: `WBAppleIntelligence/App/RootView.swift`（替换 Task 1 的占位实现）

**Interfaces:**
- Consumes: `DemoRoute`（Task 1）、`ModelAvailability`（Task 2）、`AIKitError`（Task 3）、`GenerationMetrics`（Task 4）
- Produces: `ScenarioCard(route:)`；`DemoScaffold(route:isScrollable:content:)`；`AvailabilityBanner(availability:)`；`MetricsBar(metrics:)`；`ErrorView(error:retry:)`；四个占位 View：`AvailabilityDemoView()` / `ChatDemoView()` / `TicketExtractionDemoView()` / `ToolCallingDemoView()`

- [ ] **Step 1: 场景说明卡片**

创建 `WBAppleIntelligence/DesignSystem/ScenarioCard.swift`：

```swift
import SwiftUI

/// 每个 Demo 顶部的说明卡片：这个能力对应什么企业场景、相比传统方案价值在哪、用到哪些框架。
///
/// 单独抽出来是因为「场景与价值」是这个示例工程的主线，不能散落在各页面里各写一遍。
struct ScenarioCard: View {
    let route: DemoRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(route.frameworks, systemImage: "cube.transparent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            row(title: "场景", text: route.scenario)
            row(title: "价值", text: route.value)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }

    private func row(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    ScenarioCard(route: .streamingChat)
        .padding()
}
```

- [ ] **Step 2: Demo 页面骨架**

创建 `WBAppleIntelligence/DesignSystem/DemoScaffold.swift`：

```swift
import SwiftUI

/// Demo 页面的统一骨架：顶部场景卡片 + 自定义内容区。
///
/// `isScrollable` 是必要的开关：抽取和工具调用这类页面内容会长过一屏，需要滚动；
/// 而对话页自己有一个撑满高度的消息列表，外层再套 ScrollView 会导致列表塌陷成零高度。
struct DemoScaffold<Content: View>: View {
    let route: DemoRoute
    var isScrollable: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if isScrollable {
                ScrollView { stack.padding() }
            } else {
                stack.padding()
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScenarioCard(route: route)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 3: 可用性横幅**

创建 `WBAppleIntelligence/DesignSystem/AvailabilityBanner.swift`：

```swift
import SwiftUI

/// 端侧模型可用性横幅。
///
/// 不可用时不隐藏功能入口，而是把原因和下一步操作讲清楚——
/// 企业 App 里「按钮点了没反应」产生的工单，比「明确告诉你为什么不能用」多得多。
struct AvailabilityBanner: View {
    let availability: ModelAvailability

    var body: some View {
        switch availability {
        case .available:
            Label("端侧模型已就绪，推理全程在本机完成", systemImage: "checkmark.seal.fill")
                .font(.footnote)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Label(reason.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(reason.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(reason.recovery)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        AvailabilityBanner(availability: .available)
        AvailabilityBanner(availability: .unavailable(.deviceNotEligible))
    }
    .padding()
}
```

- [ ] **Step 4: 指标条**

创建 `WBAppleIntelligence/DesignSystem/MetricsBar.swift`：

```swift
import SwiftUI

/// 生成指标展示条。没有任何指标时整体隐藏，避免首次进入页面显示一排「--」。
struct MetricsBar: View {
    let metrics: GenerationMetrics

    var body: some View {
        if hasAnyValue {
            HStack(spacing: 14) {
                if let latency = metrics.firstTokenLatency {
                    item("首字", String(format: "%.2f s", latency))
                }
                if let total = metrics.totalDuration {
                    item("总耗时", String(format: "%.2f s", total))
                }
                if let speed = metrics.tokensPerSecond {
                    item("速率", String(format: "%.0f tok/s", speed))
                }
                if let prompt = metrics.promptTokenCount {
                    item("输入", "\(prompt) tok")
                }
                if let response = metrics.responseTokenCount {
                    item("输出", "\(response) tok")
                }
            }
            .font(.caption2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hasAnyValue: Bool {
        metrics != .empty
    }

    private func item(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit().foregroundStyle(.primary)
        }
    }
}

#Preview {
    MetricsBar(metrics: GenerationMetrics(
        firstTokenLatency: 0.32,
        totalDuration: 4.1,
        promptTokenCount: 86,
        responseTokenCount: 124
    ))
    .padding()
}
```

- [ ] **Step 5: 错误展示**

创建 `WBAppleIntelligence/DesignSystem/ErrorView.swift`：

```swift
import SwiftUI

/// 统一错误展示。始终同时呈现「发生了什么」与「该怎么办」两段信息。
struct ErrorView: View {
    let error: AIKitError
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.errorDescription ?? "出错了", systemImage: "xmark.octagon.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let retry {
                Button("重试", action: retry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.red.opacity(0.1), in: .rect(cornerRadius: 10))
    }
}

#Preview {
    ErrorView(error: .contextWindowExceeded, retry: {})
        .padding()
}
```

- [ ] **Step 6: 建立四个占位 Demo 页面**

创建下面四个文件。每个都是同一形状，只是 `route` 不同——正式实现分别在 Task 6、9、11、13 中替换。

`WBAppleIntelligence/Features/Availability/AvailabilityDemoView.swift`：

```swift
import SwiftUI

struct AvailabilityDemoView: View {
    var body: some View {
        DemoScaffold(route: .availability) {
            Text("待实现")
                .foregroundStyle(.secondary)
        }
    }
}
```

`WBAppleIntelligence/Features/Chat/ChatDemoView.swift`：

```swift
import SwiftUI

struct ChatDemoView: View {
    var body: some View {
        DemoScaffold(route: .streamingChat) {
            Text("待实现")
                .foregroundStyle(.secondary)
        }
    }
}
```

`WBAppleIntelligence/Features/TicketExtraction/TicketExtractionDemoView.swift`：

```swift
import SwiftUI

struct TicketExtractionDemoView: View {
    var body: some View {
        DemoScaffold(route: .ticketExtraction) {
            Text("待实现")
                .foregroundStyle(.secondary)
        }
    }
}
```

`WBAppleIntelligence/Features/ToolCalling/ToolCallingDemoView.swift`：

```swift
import SwiftUI

struct ToolCallingDemoView: View {
    var body: some View {
        DemoScaffold(route: .toolCalling) {
            Text("待实现")
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 7: 正式的能力目录首页**

覆写 `WBAppleIntelligence/App/RootView.swift`：

```swift
import FoundationModels
import SwiftUI

/// 能力目录首页。
///
/// 直接在 body 里读 `SystemLanguageModel.default.availability`：该类型遵循 `Observable`，
/// 用户在系统设置中开启 Apple Intelligence 后，这里会自动刷新，无需重启 App，也无需自己监听通知。
struct RootView: View {
    private let model = SystemLanguageModel.default

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AvailabilityBanner(availability: ModelAvailability(model.availability))
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("能力") {
                    ForEach(DemoRoute.allCases) { route in
                        NavigationLink(value: route) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.title)
                                    Text(route.scenario)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            } icon: {
                                Image(systemName: route.systemImage)
                            }
                        }
                    }
                }
            }
            .navigationTitle("端侧 AI 能力")
            .navigationDestination(for: DemoRoute.self) { destination(for: $0) }
        }
    }

    @ViewBuilder
    private func destination(for route: DemoRoute) -> some View {
        switch route {
        case .availability: AvailabilityDemoView()
        case .streamingChat: ChatDemoView()
        case .ticketExtraction: TicketExtractionDemoView()
        case .toolCalling: ToolCallingDemoView()
        }
    }
}

#Preview {
    RootView()
}
```

- [ ] **Step 8: 构建并在模拟器上目视验证**

```bash
xcodebuild -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

预期：`** BUILD SUCCEEDED **`，0 warning。

然后用 iOS Simulator 工具启动并截图确认：
1. 先 `attach` 打开实时面板
2. 安装并 `launch` 上一步产物（`bundle_id` 为 `com.wb.WBAppleIntelligence`）
3. 截图确认：顶部橙色横幅显示「此设备不支持端侧模型」及说明与建议；下方「能力」分组有 4 行，每行有图标、标题与两行场景摘要
4. 逐个点进 4 个 Demo，确认标题正确、场景卡片有内容、正文显示「待实现」

模拟器上横幅显示橙色不可用是**预期结果**（本机 `zh_CN` 区域）。

- [ ] **Step 9: 提交**

```bash
git add WBAppleIntelligence/DesignSystem WBAppleIntelligence/Features WBAppleIntelligence/App/RootView.swift
git commit -m "界面：DesignSystem 五个共用组件与能力目录首页"
```

---

## Task 6: Demo 1 —— 端侧可用性探测页与文档 01

**Files:**
- Modify: `WBAppleIntelligence/Features/Availability/AvailabilityDemoView.swift`
- Create: `Docs/01-可用性探测与降级.md`

**Interfaces:**
- Consumes: `DemoScaffold`、`AvailabilityBanner`、`ModelAvailability`
- Produces: 无新的跨任务接口

- [ ] **Step 1: 实现可用性探测页**

覆写 `WBAppleIntelligence/Features/Availability/AvailabilityDemoView.swift`：

```swift
import FoundationModels
import SwiftUI

/// Demo 1：端侧模型可用性与能力探测。
///
/// 这一页刻意不放任何生成功能——它要回答的是上线前的第一个问题：
/// 「这台设备到底能不能用端侧模型，不能用是因为什么」。
struct AvailabilityDemoView: View {
    private let model = SystemLanguageModel.default

    var body: some View {
        DemoScaffold(route: .availability) {
            let availability = ModelAvailability(model.availability)

            AvailabilityBanner(availability: availability)

            section("模型能力") {
                keyValue("上下文窗口", "\(model.contextSize) token")
                keyValue("支持语言数", "\(model.supportedLanguages.count)")
                keyValue("支持当前地区", model.supportsLocale() ? "是" : "否")
                keyValue("当前地区标识", Locale.current.identifier)
            }

            section("支持的语言") {
                Text(supportedLanguageList)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("这一页为什么重要") {
                Text("""
                端侧能力在设备之间的分布是不均匀的：机型、系统版本、区域、语言、\
                用户是否开启、模型是否下载完，任何一环不满足都会让 availability 变成 unavailable。\
                所以「有没有 AI 功能」不能写死在代码里，必须在运行时探测并给出对应的降级路径。

                注意 supportedLanguages 与 availability 是两件事：\
                即使模型可用，用户的语言也可能不在支持列表里，那时调用会抛 unsupportedLanguageOrLocale。
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var supportedLanguageList: String {
        // maximalIdentifier 是非可选的 String，所以这里用 map 而不是 compactMap：
        // compactMap 会让读者以为存在一步过滤，而实际上一个元素都不会被滤掉。
        let names = model.supportedLanguages
            .map(\.maximalIdentifier)
            .sorted()
        return names.isEmpty ? "模型不可用时无法读取语言列表。" : names.joined(separator: "、")
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospacedDigit())
        }
    }
}

#Preview {
    NavigationStack {
        AvailabilityDemoView()
    }
}
```

- [ ] **Step 2: 构建并目视验证**

```bash
xcodebuild -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

预期 `** BUILD SUCCEEDED **`，0 warning。

在模拟器上启动 App 进入「端侧可用性探测」，截图确认：橙色横幅、上下文窗口显示 `4096 token`、当前地区标识显示 `zh_CN`。

`Locale.Language.maximalIdentifier` 在模型不可用时会返回空集合，这时语言列表区域显示兜底文案——这是预期行为，不是 bug。

- [ ] **Step 3: 写文档 01**

创建 `Docs/01-可用性探测与降级.md`，按下列结构写，每节的必备内容已列出：

1. **场景与价值**：企业 App 的 AI 功能必须能在不支持的设备上优雅退化。说明为什么「探测 + 降级」是 AI 功能的地基而不是收尾工作。
2. **API 讲解**：`SystemLanguageModel.default`、`availability`、`isAvailable`、`supportedLanguages`、`supportsLocale(_:)`、`contextSize`（值为 4096）、`SystemLanguageModel(useCase:guardrails:)`。说明 `UseCase.general` 与 `.contentTagging` 的区别。
3. **三种不可用原因**：逐个说明 `deviceNotEligible` / `appleIntelligenceNotEnabled` / `modelNotReady` 的真实成因与对应的用户引导，直接引用 `ModelAvailability.Reason` 的实现代码。
4. **Observable 驱动的自动恢复**：`SystemLanguageModel` 遵循 `Observation.Observable`，在 `body` 里读 `availability` 即可在用户开启开关后自动刷新。给出 `RootView` 的代码片段。
5. **踩坑记录**：必须写进去的三条实测结论——
   - 开发机区域为 `zh_CN` 时 `availability` 返回 `unavailable(.deviceNotEligible)`，即使硬件是 M4 Pro；
   - **iOS 模拟器的 Foundation Models 走宿主 Mac 的模型**，所以 iOS App 在模拟器里拿到的是 Mac 的可用性状态；
   - 不需要写 App 就能查状态：`printf 'import FoundationModels\nprint(SystemLanguageModel.default.availability)\n' | xcrun swift -`
6. **限制与降级**：`availability` 可用不代表调用一定成功，`supportedLanguages` 是另一道关；给出降级策略清单（走传统规则引擎 / 走云端 / 直接隐藏入口三种的取舍）。
7. **非 frozen 枚举与 `@unknown default`**：说明为什么要在 `ModelAvailability.init` 里加兜底分支。

- [ ] **Step 4: 提交**

```bash
git add WBAppleIntelligence/Features/Availability Docs/01-可用性探测与降级.md
git commit -m "Demo 1：端侧可用性与能力探测页，附配套文档"
```

---

## Task 7: TranscriptTrimmer 裁剪策略

**Files:**
- Create: `WBAppleIntelligence/AIKit/Core/TranscriptTrimmer.swift`
- Test: `WBAppleIntelligenceTests/TranscriptTrimmerTests.swift`

**Interfaces:**
- Produces: `enum TranscriptTrimmer`，静态方法 `static func trim(_ transcript: Transcript, keepingRecentEntries count: Int) -> Transcript`

- [ ] **Step 1: 写失败的测试**

创建 `WBAppleIntelligenceTests/TranscriptTrimmerTests.swift`：

```swift
import FoundationModels
import Testing
@testable import WBAppleIntelligence

struct TranscriptTrimmerTests {

    /// 造一条 instructions 条目。
    private func instructions(_ text: String) -> Transcript.Entry {
        .instructions(Transcript.Instructions(
            segments: [.text(Transcript.TextSegment(content: text))],
            toolDefinitions: []
        ))
    }

    /// 造一条提问条目。
    private func prompt(_ text: String) -> Transcript.Entry {
        .prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: text))]))
    }

    /// 造一条回答条目。
    private func response(_ text: String) -> Transcript.Entry {
        .response(Transcript.Response(
            assetIDs: [],
            segments: [.text(Transcript.TextSegment(content: text))]
        ))
    }

    /// 取出条目里的文本，便于断言。
    private func texts(_ transcript: Transcript) -> [String] {
        transcript.flatMap { entry -> [String] in
            let segments: [Transcript.Segment] = switch entry {
            case .instructions(let value): value.segments
            case .prompt(let value): value.segments
            case .response(let value): value.segments
            case .toolCalls, .toolOutput: []
            }
            return segments.compactMap { segment in
                if case .text(let text) = segment { return text.content }
                return nil
            }
        }
    }

    @Test("保留首条 instructions 与最近若干条对话")
    func keepsInstructionsAndRecentEntries() {
        let transcript = Transcript(entries: [
            instructions("系统提示"),
            prompt("问题一"), response("回答一"),
            prompt("问题二"), response("回答二"),
            prompt("问题三"), response("回答三")
        ])

        let trimmed = TranscriptTrimmer.trim(transcript, keepingRecentEntries: 4)

        #expect(texts(trimmed) == ["系统提示", "问题二", "回答二", "问题三", "回答三"])
    }

    @Test("条目数不足时原样保留，不会补空条目")
    func keepsAllWhenFewerThanLimit() {
        let transcript = Transcript(entries: [
            instructions("系统提示"),
            prompt("问题一"), response("回答一")
        ])

        let trimmed = TranscriptTrimmer.trim(transcript, keepingRecentEntries: 10)

        #expect(texts(trimmed) == ["系统提示", "问题一", "回答一"])
    }

    @Test("没有 instructions 时只保留最近条目")
    func worksWithoutInstructions() {
        let transcript = Transcript(entries: [
            prompt("问题一"), response("回答一"),
            prompt("问题二"), response("回答二")
        ])

        let trimmed = TranscriptTrimmer.trim(transcript, keepingRecentEntries: 2)

        #expect(texts(trimmed) == ["问题二", "回答二"])
    }

    @Test("只有第一条 instructions 被当作系统提示，后续同类条目按普通条目处理")
    func onlyFirstInstructionsIsPinned() {
        let transcript = Transcript(entries: [
            instructions("系统提示一"),
            prompt("问题一"),
            instructions("系统提示二"),
            prompt("问题二")
        ])

        let trimmed = TranscriptTrimmer.trim(transcript, keepingRecentEntries: 1)

        #expect(texts(trimmed) == ["系统提示一", "问题二"])
    }

    @Test("保留条数为负时按 0 处理，不会崩溃")
    func negativeCountIsClamped() {
        let transcript = Transcript(entries: [
            instructions("系统提示"),
            prompt("问题一")
        ])

        let trimmed = TranscriptTrimmer.trim(transcript, keepingRecentEntries: -3)

        #expect(texts(trimmed) == ["系统提示"])
    }

    @Test("空 Transcript 裁剪后仍为空")
    func emptyTranscript() {
        let trimmed = TranscriptTrimmer.trim(Transcript(), keepingRecentEntries: 4)
        #expect(trimmed.isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：编译失败，报 `cannot find 'TranscriptTrimmer' in scope`。

- [ ] **Step 3: 实现**

创建 `WBAppleIntelligence/AIKit/Core/TranscriptTrimmer.swift`：

```swift
import FoundationModels

/// Transcript 裁剪策略。
///
/// 端侧模型的上下文窗口只有 4096 token，长会话必然会撞上 `exceededContextWindowSize`。
/// 恢复办法是从旧会话的 Transcript 里挑出该留的条目重建一个新会话。
///
/// 之所以做成不依赖会话的纯函数：裁剪策略是最容易出错也最需要回归测试的一环，
/// 剥离掉 `LanguageModelSession` 之后它就能被完全确定性地单测。
enum TranscriptTrimmer {

    /// 保留首条 instructions（若有）与最近 `count` 条其他条目。
    ///
    /// instructions 必须钉住：它是模型的角色设定，裁掉之后模型行为会当场跑偏。
    /// 只钉第一条是因为一个会话的系统提示只应该有一份，后面出现的同类条目按普通条目处理。
    static func trim(_ transcript: Transcript, keepingRecentEntries count: Int) -> Transcript {
        var pinnedInstructions: [Transcript.Entry] = []
        var others: [Transcript.Entry] = []

        for entry in transcript {
            if case .instructions = entry, pinnedInstructions.isEmpty {
                pinnedInstructions.append(entry)
            } else {
                others.append(entry)
            }
        }

        let keep = max(0, count)
        return Transcript(entries: pinnedInstructions + others.suffix(keep))
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：`** TEST SUCCEEDED **`。

- [ ] **Step 5: 提交**

```bash
git add WBAppleIntelligence/AIKit/Core/TranscriptTrimmer.swift WBAppleIntelligenceTests/TranscriptTrimmerTests.swift
git commit -m "AIKit：Transcript 裁剪策略，为上下文超限恢复做准备"
```

---

## Task 8: Prompts 常量与 StreamingChatService

**Files:**
- Create: `WBAppleIntelligence/AIKit/Core/Prompts.swift`
- Create: `WBAppleIntelligence/AIKit/Chat/StreamingChatService.swift`

**Interfaces:**
- Consumes: `AIKitError`（Task 3）、`GenerationMetrics` / `MetricsTimer`（Task 4）、`TranscriptTrimmer`（Task 7）
- Produces: `enum Prompts`，静态常量 `helpdesk: String`、`ticketExtraction: String`、`toolCalling: String`；
  `final class StreamingChatService`，成员 `init(instructions: String = Prompts.helpdesk, recentEntriesToKeep: Int = 4)`、`var isResponding: Bool`、`func prewarm()`、`func reset()`、`func respond(to:options:onPartial:) async throws -> ChatOutcome`；
  `struct ChatOutcome: Equatable`，属性 `text: String`、`metrics: GenerationMetrics`、`didTrimContext: Bool`

- [ ] **Step 1: 集中管理提示词**

创建 `WBAppleIntelligence/AIKit/Core/Prompts.swift`：

```swift
/// 各 Demo 的 instructions 集中管理。
///
/// 单独成文件有两个原因：一是提示词是需要反复调的内容，散在各个 service 的 init 里不好比对；
/// 二是 Swift 不允许在 init 中读取尚未完成初始化的 self 的存储属性，
/// 把提示词做成类型外的静态常量可以让 service 在 init 里直接引用。
enum Prompts {

    static let helpdesk = """
    你是企业内部 IT 支持助手，服务对象是本公司员工。
    回答要求：
    1. 用中文回答，语气简洁专业，不寒暄。
    2. 步骤类问题用编号列表，每步不超过一行。
    3. 不确定的信息明确说不确定，不要编造内部系统的名称或地址。
    4. 涉及重置密码、权限变更等敏感操作时，提示员工需要走正式工单流程。
    """

    static let ticketExtraction = """
    你是企业 IT 服务台的工单录入助手。
    员工会用口语描述遇到的问题，你要把它抽取成一张结构化工单。
    抽取规则：
    1. 只使用描述中出现的信息，不要臆测或补充任何原文没有的内容。
    2. 无法判断受影响人数时填 1。
    3. 标题要具体，避免「电脑坏了」这类空泛表述。
    4. 关键实体只提取设备型号、系统名称、错误码这类可检索的词，不要放形容词。
    """

    static let toolCalling = """
    你是企业内部系统的查询助手。
    你可以调用工具查询物料库存与订单状态。
    要求：
    1. 需要查数据时必须调用工具，不要凭记忆回答具体数字。
    2. 工具返回「未查询到」时如实告知员工，并建议其核对编号。
    3. 拿到工具结果后用一句话总结，不要罗列原始数据。
    """
}
```

- [ ] **Step 2: 实现流式对话服务**

创建 `WBAppleIntelligence/AIKit/Chat/StreamingChatService.swift`：

```swift
import Foundation
import FoundationModels

/// 一次流式回答的结果。
struct ChatOutcome: Equatable {
    let text: String
    let metrics: GenerationMetrics
    /// 本次回答是否触发过上下文裁剪。UI 需要据此提示用户「早期对话已被裁剪」。
    let didTrimContext: Bool
}

/// 流式对话服务。
///
/// 负责三件事：会话生命周期、流式增量与指标采集、上下文超限时的自动恢复。
/// 有意不 import SwiftUI —— 这个类型可以整体复制进任何 iOS 26 工程。
@MainActor
final class StreamingChatService {

    private let instructions: String
    private let recentEntriesToKeep: Int
    private var session: LanguageModelSession

    init(instructions: String = Prompts.helpdesk, recentEntriesToKeep: Int = 4) {
        self.instructions = instructions
        self.recentEntriesToKeep = recentEntriesToKeep
        self.session = LanguageModelSession(model: .default, instructions: instructions)
    }

    var isResponding: Bool {
        session.isResponding
    }

    /// 预热。
    ///
    /// 首次调用要把模型权重载入内存，冷启动可能到秒级；在用户还在打字时提前预热，
    /// 能把这段开销从「首字延迟」里挪走。代价是一段时间的内存占用，所以只在用户
    /// 明确进入对话界面后才调，不在 App 启动时调。
    func prewarm() {
        session.prewarm()
    }

    /// 丢弃当前会话历史，回到初始状态。
    func reset() {
        session = LanguageModelSession(model: .default, instructions: instructions)
    }

    /// 流式回答。
    ///
    /// 每收到一次增量就用**累计到当前为止的完整文本**回调 `onPartial`——
    /// FoundationModels 的 snapshot 给的是累计值而不是增量差值，UI 直接赋值即可，不要做拼接。
    func respond(
        to prompt: String,
        options: GenerationOptions = GenerationOptions(),
        onPartial: (String) -> Void
    ) async throws -> ChatOutcome {
        do {
            let result = try await streamOnce(prompt, options: options, onPartial: onPartial)
            return ChatOutcome(text: result.text, metrics: result.metrics, didTrimContext: false)
        } catch let error as LanguageModelSession.GenerationError {
            guard case .exceededContextWindowSize = error else {
                throw AIKitError(error)
            }
            // 上下文撑爆了：裁掉早期对话、保住系统提示，用剩下的历史重建会话后重试一次。
            // 只重试一次——如果裁剪后仍然超限，说明单次提问本身就过长，重试没有意义。
            session = LanguageModelSession(
                model: .default,
                transcript: TranscriptTrimmer.trim(
                    session.transcript,
                    keepingRecentEntries: recentEntriesToKeep
                )
            )
            do {
                let result = try await streamOnce(prompt, options: options, onPartial: onPartial)
                return ChatOutcome(text: result.text, metrics: result.metrics, didTrimContext: true)
            } catch {
                throw AIKitError(error)
            }
        } catch {
            throw AIKitError(error)
        }
    }

    private func streamOnce(
        _ prompt: String,
        options: GenerationOptions,
        onPartial: (String) -> Void
    ) async throws -> (text: String, metrics: GenerationMetrics) {
        var timer = MetricsTimer()
        var latest = ""

        for try await snapshot in session.streamResponse(to: prompt, options: options) {
            timer.markFirstToken()
            latest = snapshot.content
            onPartial(latest)
        }

        guard !latest.isEmpty else { throw AIKitError.emptyResponse }

        // token 统计失败不应该让整次回答失败，所以这里用 try? 降级为 nil。
        let promptTokens = try? await SystemLanguageModel.default.tokenCount(for: prompt)
        let responseTokens = try? await SystemLanguageModel.default.tokenCount(for: latest)

        return (latest, timer.finish(
            promptTokenCount: promptTokens,
            responseTokenCount: responseTokens
        ))
    }
}
```

- [ ] **Step 3: 验证构建**

```bash
xcodebuild -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

预期：`** BUILD SUCCEEDED **`，0 warning。

- [ ] **Step 4: 提交**

```bash
git add WBAppleIntelligence/AIKit/Core/Prompts.swift WBAppleIntelligence/AIKit/Chat
git commit -m "AIKit：流式对话服务，含指标采集与上下文超限自动恢复"
```

---

## Task 9: Demo 2 —— 流式客服助手页与文档 02

**Files:**
- Create: `WBAppleIntelligence/Features/Chat/ChatViewModel.swift`
- Modify: `WBAppleIntelligence/Features/Chat/ChatDemoView.swift`
- Create: `Docs/02-流式对话与会话管理.md`

**Interfaces:**
- Consumes: `StreamingChatService` / `ChatOutcome`（Task 8）、`ModelAvailability`、`AIKitError`、`GenerationMetrics`、`DemoScaffold` / `AvailabilityBanner` / `MetricsBar` / `ErrorView`
- Produces: `@Observable final class ChatViewModel`；`struct ChatMessage: Identifiable, Equatable`

- [ ] **Step 1: 实现 ViewModel**

创建 `WBAppleIntelligence/Features/Chat/ChatViewModel.swift`：

```swift
import Foundation
import FoundationModels
import Observation

struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant }

    let id = UUID()
    let role: Role
    var text: String
}

/// 流式客服助手的状态编排。
///
/// 只做三件事：把用户输入交给 service、把流式增量写回消息、把错误与指标暴露给界面。
/// 所有与 FoundationModels 打交道的逻辑都在 `StreamingChatService` 里，这里不出现任何模型 API。
@Observable
final class ChatViewModel {

    private(set) var messages: [ChatMessage] = []
    private(set) var metrics: GenerationMetrics = .empty
    private(set) var error: AIKitError?
    private(set) var isResponding = false
    /// 上一次回答是否因为上下文超限而裁剪过历史。
    private(set) var didTrimContext = false

    var input = ""
    /// 采样温度。0 更稳定可复现，1 更发散——这个滑杆是为了让人直观看到差别。
    var temperature: Double = 0.3

    private let service = StreamingChatService()

    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    func prewarm() {
        service.prewarm()
    }

    func reset() {
        service.reset()
        messages = []
        metrics = .empty
        error = nil
        didTrimContext = false
    }

    func send() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }

        input = ""
        error = nil
        didTrimContext = false
        isResponding = true
        messages.append(ChatMessage(role: .user, text: prompt))

        // 先插入一条空的助手消息，后续增量直接改这一条，界面上就是逐字出现的效果。
        let replyIndex = messages.count
        messages.append(ChatMessage(role: .assistant, text: ""))

        do {
            let outcome = try await service.respond(
                to: prompt,
                options: GenerationOptions(temperature: temperature)
            ) { partial in
                messages[replyIndex].text = partial
            }
            messages[replyIndex].text = outcome.text
            metrics = outcome.metrics
            didTrimContext = outcome.didTrimContext
        } catch {
            self.error = AIKitError(error)
            messages.removeLast()   // 移除那条没能填上内容的空回复
        }

        isResponding = false
    }
}
```

- [ ] **Step 2: 实现界面**

覆写 `WBAppleIntelligence/Features/Chat/ChatDemoView.swift`：

```swift
import FoundationModels
import SwiftUI

/// Demo 2：流式客服助手。
///
/// 用 `DemoScaffold(isScrollable: false)`：消息列表自己要撑满剩余高度并独立滚动，
/// 外层再套一层 ScrollView 会让列表高度塌陷。
struct ChatDemoView: View {
    @State private var viewModel = ChatViewModel()
    private let model = SystemLanguageModel.default

    var body: some View {
        DemoScaffold(route: .streamingChat, isScrollable: false) {
            let availability = ModelAvailability(model.availability)

            AvailabilityBanner(availability: availability)

            messageList

            if viewModel.didTrimContext {
                Label("早期对话已被裁剪以腾出上下文空间", systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let error = viewModel.error {
                ErrorView(error: error)
            }

            MetricsBar(metrics: viewModel.metrics)

            temperatureSlider
            inputBar(isEnabled: availability.isAvailable)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新会话", systemImage: "arrow.counterclockwise") {
                    viewModel.reset()
                }
                .disabled(viewModel.isResponding)
            }
        }
        .task {
            // 用户已经进到对话界面了，这时预热的收益最大、浪费最小。
            viewModel.prewarm()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            List(viewModel.messages) { message in
                MessageRow(message: message)
                    .listRowSeparator(.hidden)
                    .id(message.id)
            }
            .listStyle(.plain)
            .frame(maxHeight: .infinity)
            .onChange(of: viewModel.messages.last?.text) {
                guard let lastID = viewModel.messages.last?.id else { return }
                withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
            }
        }
    }

    private var temperatureSlider: some View {
        HStack(spacing: 10) {
            Text("温度 \(viewModel.temperature, format: .number.precision(.fractionLength(1)))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(value: $viewModel.temperature, in: 0...1, step: 0.1)
        }
    }

    private func inputBar(isEnabled: Bool) -> some View {
        HStack(spacing: 8) {
            TextField("描述你遇到的问题", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(!isEnabled)

            Button {
                Task { await viewModel.send() }
            } label: {
                if viewModel.isResponding {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
            }
            .disabled(!isEnabled || !viewModel.canSend)
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text.isEmpty ? "思考中…" : message.text)
                .font(.callout)
                .foregroundStyle(message.text.isEmpty ? .secondary : .primary)
                .padding(10)
                .background(background, in: .rect(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var background: some ShapeStyle {
        message.role == .user ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.5))
    }
}

#Preview {
    NavigationStack {
        ChatDemoView()
    }
}
```

- [ ] **Step 3: 构建并目视验证**

```bash
xcodebuild -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

预期：`** BUILD SUCCEEDED **`，0 warning。

模拟器验收（不可用路径）：进入「流式客服助手」，截图确认橙色横幅显示、输入框与发送按钮均为禁用态、温度滑杆可拖动、右上角有「新会话」按钮。

**真机验收（必做，模拟器无法覆盖）**：在已开启 Apple Intelligence 的 iPhone 15 Pro+ 上运行，确认——
1. 横幅变绿；
2. 发送「我的 MacBook 连不上公司 Wi-Fi 怎么办」后文字逐字出现；
3. 回答结束后指标条出现首字延迟、总耗时、速率、输入/输出 token 数五项；
4. 把温度拖到 0 连问两次相同问题，回答基本一致；拖到 1 再问，回答明显发散；
5. 连续追问十轮以上直到触发上下文裁剪，确认出现「早期对话已被裁剪」提示且对话能继续。

- [ ] **Step 4: 写文档 02**

创建 `Docs/02-流式对话与会话管理.md`，按下列结构写：

1. **场景与价值**：内部知识客服。强调对话内容不出设备、无 token 费用、断网可用这三点在企业里分别对应什么具体的合规与成本诉求。
2. **流式 API**：`streamResponse(to:options:)` 返回 `ResponseStream`，`for try await snapshot in stream` 的用法。**必须写明：`snapshot.content` 是累计到当前为止的完整文本，不是增量差值**，UI 直接赋值，做拼接会得到重复内容。
3. **`prewarm()`**：作用、调用时机的取舍（进入对话界面时调、不在 App 启动时调）、代价是内存占用。给出真机实测的预热前后首字延迟对比数字。
4. **`GenerationOptions`**：`temperature`、`maximumResponseTokens`、`SamplingMode.greedy` / `.random(top:seed:)` / `.random(probabilityThreshold:seed:)`。说明 `seed` 参数对可复现性的意义（回归测试很需要）。
5. **上下文窗口管理**：`contextSize` 为 4096；`exceededContextWindowSize` 的捕获与恢复；引用 `TranscriptTrimmer` 的完整实现；强调为什么必须钉住 instructions 条目、为什么只重试一次、为什么要在 UI 上显式提示裁剪而不是静默处理。
6. **指标采集**：为什么用 `ContinuousClock` 而不是 `Date`；`Duration.components` 必须把 `attoseconds` 一起算进去，否则亚秒级延迟会被抹成 0；`tokenCount(for:)` 是 iOS 26.4+ 的 API，失败时降级为 nil 而不是让整次回答失败。
7. **踩坑记录**：`concurrentRequests` —— 同一个 session 不支持并发请求，必须用 `isResponding` 挡住重复发送；`rateLimited` —— App 在后台时限流更严格。
8. **性能数据**：真机实测的首字延迟、token 速率区间。

- [ ] **Step 5: 提交**

```bash
git add WBAppleIntelligence/Features/Chat Docs/02-流式对话与会话管理.md
git commit -m "Demo 2：流式客服助手，含温度调节与上下文裁剪提示"
```

---

## Task 10: ServiceTicket 结构化模型与抽取服务

**Files:**
- Create: `WBAppleIntelligence/AIKit/Extraction/ServiceTicket.swift`
- Create: `WBAppleIntelligence/AIKit/Extraction/TicketExtractionService.swift`
- Test: `WBAppleIntelligenceTests/ServiceTicketTests.swift`

**Interfaces:**
- Consumes: `Prompts`（Task 8）、`AIKitError`、`GenerationMetrics` / `MetricsTimer`
- Produces: `@Generable struct ServiceTicket`，字段 `title: String` / `category: TicketCategory` / `priority: TicketPriority` / `affectedPeople: Int` / `keywords: [String]` / `summary: String`；`@Generable enum TicketCategory`（`hardware` / `software` / `network` / `account` / `other`）；`@Generable enum TicketPriority`（`low` / `medium` / `high` / `urgent`）；两个枚举的 `displayName: String`；
  `final class TicketExtractionService`，方法 `func extract(from:onPartial:) async throws -> TicketOutcome`、`func reset()`；`struct TicketOutcome`，属性 `ticket: ServiceTicket`、`metrics: GenerationMetrics`

- [ ] **Step 1: 写失败的测试**

创建 `WBAppleIntelligenceTests/ServiceTicketTests.swift`：

```swift
import FoundationModels
import Testing
@testable import WBAppleIntelligence

struct ServiceTicketTests {

    @Test("schema 中包含全部六个字段名")
    func schemaContainsAllFields() throws {
        let description = ServiceTicket.generationSchema.debugDescription
        for field in ["title", "category", "priority", "affectedPeople", "keywords", "summary"] {
            #expect(description.contains(field), "schema 中缺少字段 \(field)")
        }
    }

    @Test("类别枚举每个 case 都有中文名", arguments: TicketCategory.allDisplayCases)
    func categoryHasDisplayName(_ category: TicketCategory) {
        #expect(!category.displayName.isEmpty)
    }

    @Test("优先级枚举每个 case 都有中文名", arguments: TicketPriority.allDisplayCases)
    func priorityHasDisplayName(_ priority: TicketPriority) {
        #expect(!priority.displayName.isEmpty)
    }

    @Test("能从 GeneratedContent 还原出完整工单")
    func decodesFromGeneratedContent() throws {
        let json = """
        {
          "title": "会议室投影仪无法连接",
          "category": "hardware",
          "priority": "medium",
          "affectedPeople": 8,
          "keywords": ["投影仪", "HDMI"],
          "summary": "三楼会议室的投影仪通过 HDMI 连接后没有信号。"
        }
        """
        let ticket = try ServiceTicket(GeneratedContent(json: json))

        #expect(ticket.title == "会议室投影仪无法连接")
        #expect(ticket.category == .hardware)
        #expect(ticket.priority == .medium)
        #expect(ticket.affectedPeople == 8)
        #expect(ticket.keywords == ["投影仪", "HDMI"])
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：编译失败，报 `cannot find 'ServiceTicket' in scope`。

- [ ] **Step 3: 实现结构化模型**

创建 `WBAppleIntelligence/AIKit/Extraction/ServiceTicket.swift`：

```swift
import FoundationModels

/// 从员工的自由文本描述中抽取出的一张 IT 服务工单。
///
/// 字段顺序不是随意排的：模型按声明顺序生成，流式填表时用户看到的填充次序就是这个顺序，
/// 所以把最能立刻确认「抽对了没有」的 title 放在最前面。
///
/// `@Generable` 会为该类型合成 `generationSchema`、`PartiallyGenerated` 以及
/// `init(_ content: GeneratedContent) throws`，schema 由框架强制约束模型输出，
/// 所以这里不需要写任何 JSON 解析与容错代码。
@Generable(description: "从员工的自由文本描述中抽取出的一张 IT 服务工单")
struct ServiceTicket: Equatable, Sendable {

    @Guide(description: "一句话工单标题，控制在 20 个汉字以内，要具体到设备或系统")
    var title: String

    @Guide(description: "工单类别")
    var category: TicketCategory

    @Guide(description: "紧急程度")
    var priority: TicketPriority

    @Guide(description: "受影响的人数，只影响描述者本人时填 1", .minimum(1), .maximum(100_000))
    var affectedPeople: Int

    @Guide(description: "可检索的关键实体，如设备型号、系统名称、错误码，不要放形容词", .maximumCount(5))
    var keywords: [String]

    @Guide(description: "对问题的客观复述，不要添加原文没有的信息")
    var summary: String
}

@Generable(description: "工单类别")
enum TicketCategory: Equatable, Sendable {
    case hardware
    case software
    case network
    case account
    case other
}

@Generable(description: "工单紧急程度")
enum TicketPriority: Equatable, Sendable {
    case low
    case medium
    case high
    case urgent
}

extension TicketCategory {
    var displayName: String {
        switch self {
        case .hardware: "硬件"
        case .software: "软件"
        case .network: "网络"
        case .account: "账号权限"
        case .other: "其他"
        }
    }

    /// 供测试与界面遍历使用。
    ///
    /// 不加 `CaseIterable`：`@Generable` 会给枚举合成成员，与 `CaseIterable` 的
    /// `allCases` 合成同时存在时容易产生歧义，手写一份反而更省心。
    static let allDisplayCases: [TicketCategory] = [.hardware, .software, .network, .account, .other]
}

extension TicketPriority {
    var displayName: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        case .urgent: "紧急"
        }
    }

    static let allDisplayCases: [TicketPriority] = [.low, .medium, .high, .urgent]
}
```

- [ ] **Step 4: 实现抽取服务**

创建 `WBAppleIntelligence/AIKit/Extraction/TicketExtractionService.swift`：

```swift
import Foundation
import FoundationModels

struct TicketOutcome: Equatable {
    let ticket: ServiceTicket
    let metrics: GenerationMetrics
}

/// 结构化工单抽取服务。
///
/// 与自由文本对话的关键差别：`streamResponse(to:generating:)` 的每个 snapshot 给的是
/// `ServiceTicket.PartiallyGenerated`——一个所有字段都是可选值的镜像类型，
/// 已生成的字段有值、未生成的为 nil。界面据此可以做到「边生成边填表」。
@MainActor
final class TicketExtractionService {

    private var session: LanguageModelSession

    init() {
        session = LanguageModelSession(model: .default, instructions: Prompts.ticketExtraction)
    }

    func reset() {
        session = LanguageModelSession(model: .default, instructions: Prompts.ticketExtraction)
    }

    /// 抽取工单。每次字段更新都会回调 `onPartial`。
    func extract(
        from text: String,
        onPartial: (ServiceTicket.PartiallyGenerated) -> Void
    ) async throws -> TicketOutcome {
        var timer = MetricsTimer()
        var lastRawContent: GeneratedContent?

        do {
            let stream = session.streamResponse(to: text, generating: ServiceTicket.self)
            for try await snapshot in stream {
                timer.markFirstToken()
                // 留住 rawContent 而不是 content：流结束后要用它还原成完整的 ServiceTicket，
                // PartiallyGenerated 的字段全是可选值，无法直接当最终结果用。
                lastRawContent = snapshot.rawContent
                onPartial(snapshot.content)
            }
        } catch {
            throw AIKitError(error)
        }

        guard let lastRawContent else { throw AIKitError.emptyResponse }

        let ticket: ServiceTicket
        do {
            ticket = try ServiceTicket(lastRawContent)
        } catch {
            throw AIKitError(error)
        }

        let promptTokens = try? await SystemLanguageModel.default.tokenCount(for: text)
        let schemaTokens = try? await SystemLanguageModel.default.tokenCount(
            for: ServiceTicket.generationSchema
        )

        return TicketOutcome(
            ticket: ticket,
            metrics: timer.finish(
                // schema 本身也要占提示词预算，把两部分加起来才是真实的输入开销。
                promptTokenCount: sum(promptTokens, schemaTokens),
                responseTokenCount: nil
            )
        )
    }

    private func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case (let l?, let r?): l + r
        case (let l?, nil): l
        case (nil, let r?): r
        case (nil, nil): nil
        }
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：`** TEST SUCCEEDED **`。

两个测试可能需要按实际输出微调，**但都不要删掉**——它们是 schema 与解码路径的唯一回归防线：

- `schemaContainsAllFields` 失败：说明 `GenerationSchema.debugDescription` 的格式与预期不同。用 `print(ServiceTicket.generationSchema.debugDescription)` 打出实际内容后调整断言中的字段匹配方式。若该属性根本不含字段名，改为断言 `GeneratedContent` 往返：构造一份完整 JSON、解码成 `ServiceTicket`、再取 `generatedContent.jsonString` 确认六个字段都在。
- `decodesFromGeneratedContent` 失败：说明 `@Generable` 枚举在 `GeneratedContent` 里的编码形式不是 case 名字符串。用 `print(GeneratedContent(TicketCategory.hardware).jsonString)` 打出实际编码后，把测试 JSON 里 `category` 与 `priority` 的值改成实际形式。

- [ ] **Step 6: 提交**

```bash
git add WBAppleIntelligence/AIKit/Extraction WBAppleIntelligenceTests/ServiceTicketTests.swift
git commit -m "AIKit：工单结构化模型与流式抽取服务"
```

---

## Task 11: Demo 3 —— 结构化抽取页与文档 03

**Files:**
- Create: `WBAppleIntelligence/Features/TicketExtraction/TicketExtractionViewModel.swift`
- Modify: `WBAppleIntelligence/Features/TicketExtraction/TicketExtractionDemoView.swift`
- Create: `Docs/03-结构化生成.md`

**Interfaces:**
- Consumes: `TicketExtractionService` / `TicketOutcome` / `ServiceTicket`（Task 10）及 DesignSystem 组件
- Produces: `@Observable final class TicketExtractionViewModel`

- [ ] **Step 1: 实现 ViewModel**

创建 `WBAppleIntelligence/Features/TicketExtraction/TicketExtractionViewModel.swift`：

```swift
import Observation

/// 结构化抽取的状态编排。
///
/// `partial` 是流式过程中的中间态，`ticket` 是最终结果。两者都保留是有意的：
/// 界面在生成中读 `partial` 做逐字段填充，生成完读 `ticket` 展示确定结果。
@Observable
final class TicketExtractionViewModel {

    private(set) var partial: ServiceTicket.PartiallyGenerated?
    private(set) var ticket: ServiceTicket?
    private(set) var metrics: GenerationMetrics = .empty
    private(set) var error: AIKitError?
    private(set) var isExtracting = false

    // 这里必须写全类型名而不是 Self：存储属性的初始化表达式里引用 Self 会报
    // “covariant 'Self' type cannot be referenced from a stored property initializer”。
    var input = TicketExtractionViewModel.sampleInput

    private let service = TicketExtractionService()

    /// 预置一段口语化描述，方便在没有键盘输入的场景下一键演示。
    static let sampleInput = """
    我们三楼会议室的投影仪今天早上开始就连不上了，HDMI 插上去没信号，\
    换了两根线都不行，笔记本是公司发的 ThinkPad X1。下午有个客户演示，\
    整个项目组八个人都等着用这个会议室。
    """

    var canExtract: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isExtracting
    }

    func reset() {
        service.reset()
        partial = nil
        ticket = nil
        metrics = .empty
        error = nil
    }

    func extract() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isExtracting else { return }

        isExtracting = true
        error = nil
        ticket = nil
        partial = nil

        do {
            let outcome = try await service.extract(from: text) { partial in
                self.partial = partial
            }
            ticket = outcome.ticket
            metrics = outcome.metrics
        } catch {
            self.error = AIKitError(error)
        }

        isExtracting = false
    }
}
```

- [ ] **Step 2: 实现界面**

覆写 `WBAppleIntelligence/Features/TicketExtraction/TicketExtractionDemoView.swift`：

```swift
import FoundationModels
import SwiftUI

/// Demo 3：结构化工单抽取。
///
/// 表格区域始终存在，字段值随生成过程从「等待中」逐个变成实际内容——
/// 这就是 `PartiallyGenerated` 的价值：用户不用盯着转圈等，能看到进度。
struct TicketExtractionDemoView: View {
    @State private var viewModel = TicketExtractionViewModel()
    private let model = SystemLanguageModel.default

    var body: some View {
        DemoScaffold(route: .ticketExtraction) {
            let availability = ModelAvailability(model.availability)

            AvailabilityBanner(availability: availability)

            Text("员工原话")
                .font(.subheadline.weight(.semibold))
            TextField("描述遇到的问题", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
                .disabled(viewModel.isExtracting)

            HStack {
                Button("抽取工单") {
                    Task { await viewModel.extract() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!availability.isAvailable || !viewModel.canExtract)

                Button("清空") { viewModel.reset() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isExtracting)

                if viewModel.isExtracting {
                    ProgressView().padding(.leading, 4)
                }
            }

            if let error = viewModel.error {
                ErrorView(error: error)
            }

            ticketForm

            MetricsBar(metrics: viewModel.metrics)
        }
    }

    private var ticketForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("结构化结果")
                .font(.subheadline.weight(.semibold))

            field("标题", viewModel.ticket?.title ?? viewModel.partial?.title)
            field("类别", (viewModel.ticket?.category ?? viewModel.partial?.category)?.displayName)
            field("优先级", (viewModel.ticket?.priority ?? viewModel.partial?.priority)?.displayName)
            field("影响人数", (viewModel.ticket?.affectedPeople ?? viewModel.partial?.affectedPeople).map { String($0) })
            field("关键词", (viewModel.ticket?.keywords ?? viewModel.partial?.keywords)?.joined(separator: "、"))
            field("摘要", viewModel.ticket?.summary ?? viewModel.partial?.summary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private func field(_ name: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value?.isEmpty == false ? value! : "等待生成…")
                .font(.callout)
                .foregroundStyle(value?.isEmpty == false ? .primary : .tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        TicketExtractionDemoView()
    }
}
```

- [ ] **Step 3: 构建并目视验证**

```bash
xcodebuild -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

预期：`** BUILD SUCCEEDED **`，0 warning。

若 `viewModel.partial?.keywords` 的类型不是 `[String]?` 而是 `[String?]?` 之类，编译会报错——此时用 `print(type(of:))` 或看编译器提示确认 `PartiallyGenerated` 里数组字段的实际类型后调整 `joined` 那一行，其余不动。

模拟器验收：进入「结构化工单抽取」，截图确认输入框已预填示例描述、「抽取工单」按钮为禁用态（模型不可用）、结构化结果区六个字段都显示「等待生成…」。

**真机验收（必做）**：点「抽取工单」，确认字段按 标题 → 类别 → 优先级 → 影响人数 → 关键词 → 摘要 的顺序**逐个**填充而不是一次性出现；最终 `affectedPeople` 为 8、`category` 为「硬件」、关键词包含「投影仪」或「HDMI」。

- [ ] **Step 4: 写文档 03**

创建 `Docs/03-结构化生成.md`，按下列结构写：

1. **场景与价值**：服务台工单录入。对比「让模型输出 JSON 再自己解析」的传统做法——那种做法必须处理模型输出不合法 JSON 的情况，而 `@Generable` 由框架在解码阶段强制约束 schema，解析层的容错代码可以整段删掉。
2. **`@Generable` 宏做了什么**：合成 `generationSchema`、`PartiallyGenerated`、`init(_:)`（`ConvertibleFromGeneratedContent`）与 `generatedContent`。给出 `ServiceTicket` 的完整代码。
3. **`@Guide` 全部约束类型**：`description`、`.constant`、`.anyOf`、`.pattern(Regex)`、`.minimum` / `.maximum` / `.range`（`Int` / `Float` / `Double` / `Decimal` 各有重载）、`.minimumCount` / `.maximumCount` / `.count` / `.element`。**必须写明：正则字面量在 Swift 5 语言模式下要用 `#/.../#`，裸斜杠 `/.../` 会报 `'/' is not a prefix unary operator`**（本工程 `SWIFT_VERSION = 5.0`，实测结论）。
4. **枚举作为字段类型**：`@Generable enum` 的写法；说明为什么不给它加 `CaseIterable`（与宏合成的成员容易打架），改为手写 `allDisplayCases`。
5. **流式填表**：`streamResponse(to:generating:)`、`Snapshot.content` 是 `PartiallyGenerated`（全可选字段镜像）、`Snapshot.rawContent` 是 `GeneratedContent`。**说明为什么最终结果要用最后一个 `rawContent` 还原而不是直接用 `PartiallyGenerated`**：后者字段全是可选值，拿不到确定结果。
6. **字段顺序的实际影响**：模型按声明顺序生成，所以最该先让用户确认的字段要放最前。
7. **schema 也要占预算**：`tokenCount(for: ServiceTicket.generationSchema)`；字段越多、描述越长，留给正文的窗口越小。给出真机实测的 schema token 数。
8. **踩坑记录**：`decodingFailure` 与 `unsupportedGuide` 分别在什么情况下出现；`includeSchemaInPrompt` 参数的取舍。
9. **性能数据**：真机实测的抽取总耗时与首字延迟。

- [ ] **Step 5: 提交**

```bash
git add WBAppleIntelligence/Features/TicketExtraction Docs/03-结构化生成.md
git commit -m "Demo 3：结构化工单抽取，流式逐字段填表"
```

---

## Task 12: 模拟企业后端与两个 Tool

**Files:**
- Create: `WBAppleIntelligence/AIKit/Tools/MockEnterpriseBackend.swift`
- Create: `WBAppleIntelligence/AIKit/Tools/EnterpriseTools.swift`
- Test: `WBAppleIntelligenceTests/MockEnterpriseBackendTests.swift`

**Interfaces:**
- Produces: `nonisolated struct MockEnterpriseBackend: Sendable`，嵌套 `StockRecord`（`item` / `warehouse` / `quantity`）与 `OrderRecord`（`orderID` / `status` / `expectedDelivery`），`static let shared`，方法 `func stock(forItem:warehouse:) -> [StockRecord]`、`func order(id:) -> OrderRecord?`；
  `@Generable struct InventoryQuery`（`item: String` / `warehouse: String?`）、`@Generable struct OrderQuery`（`orderID: String`）；
  `struct InventoryLookupTool: Tool`、`struct OrderStatusTool: Tool`，两者 `Output == String`

- [ ] **Step 1: 写失败的测试**

创建 `WBAppleIntelligenceTests/MockEnterpriseBackendTests.swift`：

```swift
import Testing
@testable import WBAppleIntelligence

struct MockEnterpriseBackendTests {

    private let backend = MockEnterpriseBackend.shared

    @Test("按物料名模糊查询能命中")
    func findsStockByFuzzyItemName() {
        let records = backend.stock(forItem: "ThinkPad", warehouse: nil)
        #expect(!records.isEmpty)
        #expect(records.allSatisfy { $0.item.contains("ThinkPad") })
    }

    @Test("物料名大小写不敏感")
    func itemNameIsCaseInsensitive() {
        let lower = backend.stock(forItem: "thinkpad", warehouse: nil)
        let upper = backend.stock(forItem: "THINKPAD", warehouse: nil)
        #expect(lower == upper)
        #expect(!lower.isEmpty)
    }

    @Test("指定仓库时只返回该仓库的记录")
    func filtersByWarehouse() {
        let all = backend.stock(forItem: "ThinkPad", warehouse: nil)
        let shanghai = backend.stock(forItem: "ThinkPad", warehouse: "SH01")
        #expect(shanghai.count < all.count)
        #expect(shanghai.allSatisfy { $0.warehouse == "SH01" })
    }

    @Test("查不到的物料返回空数组而不是崩溃")
    func unknownItemReturnsEmpty() {
        #expect(backend.stock(forItem: "不存在的物料", warehouse: nil).isEmpty)
    }

    @Test("按订单号能查到订单")
    func findsOrder() {
        #expect(backend.order(id: "SO-2026-0417") != nil)
    }

    @Test("订单号大小写不敏感")
    func orderIDIsCaseInsensitive() {
        #expect(backend.order(id: "so-2026-0417") != nil)
    }

    @Test("查不到的订单返回 nil")
    func unknownOrderReturnsNil() {
        #expect(backend.order(id: "SO-0000-0000") == nil)
    }

    @Test("库存工具查得到时返回含数量的中文描述")
    func inventoryToolReturnsReadableText() async throws {
        let tool = InventoryLookupTool()
        let output = try await tool.call(arguments: InventoryQuery(item: "ThinkPad", warehouse: "SH01"))
        #expect(output.contains("SH01"))
        #expect(output.contains("件"))
    }

    @Test("库存工具查不到时给出明确说明，而不是返回空串让模型自由发挥")
    func inventoryToolExplainsMiss() async throws {
        let tool = InventoryLookupTool()
        let output = try await tool.call(arguments: InventoryQuery(item: "不存在的物料", warehouse: nil))
        #expect(output.contains("未查询到"))
    }

    @Test("订单工具查不到时给出明确说明")
    func orderToolExplainsMiss() async throws {
        let tool = OrderStatusTool()
        let output = try await tool.call(arguments: OrderQuery(orderID: "SO-0000-0000"))
        #expect(output.contains("未查询到"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：编译失败，报 `cannot find 'MockEnterpriseBackend' in scope`。

- [ ] **Step 3: 实现模拟后端**

创建 `WBAppleIntelligence/AIKit/Tools/MockEnterpriseBackend.swift`：

```swift
/// 模拟企业内部系统的数据源。
///
/// 真实项目里这一层背后是 HTTP 客户端或本地数据库；这里用确定性的内存数据，
/// 好处是 Demo 完全离线可跑、单测可以直接断言具体数值。
///
/// 显式标 `nonisolated`：工程开启了默认 MainActor 隔离，而 `Tool.call` 是
/// nonisolated 的，若这里跟着默认走主线程隔离，工具实现里就访问不到 `shared`。
nonisolated struct MockEnterpriseBackend: Sendable {

    struct StockRecord: Equatable, Sendable {
        let item: String
        let warehouse: String
        let quantity: Int
    }

    struct OrderRecord: Equatable, Sendable {
        let orderID: String
        let status: String
        let expectedDelivery: String
    }

    static let shared = MockEnterpriseBackend()

    private let stockRecords: [StockRecord] = [
        StockRecord(item: "ThinkPad X1 Carbon", warehouse: "SH01", quantity: 42),
        StockRecord(item: "ThinkPad X1 Carbon", warehouse: "BJ02", quantity: 7),
        StockRecord(item: "ThinkPad T14", warehouse: "SH01", quantity: 0),
        StockRecord(item: "Dell U2723QE 显示器", warehouse: "SH01", quantity: 15),
        StockRecord(item: "HDMI 2.1 线缆 2 米", warehouse: "BJ02", quantity: 230)
    ]

    private let orderRecords: [OrderRecord] = [
        OrderRecord(orderID: "SO-2026-0417", status: "已发货", expectedDelivery: "2026-07-28"),
        OrderRecord(orderID: "SO-2026-0392", status: "备货中", expectedDelivery: "2026-08-03"),
        OrderRecord(orderID: "SO-2026-0355", status: "已签收", expectedDelivery: "2026-07-19")
    ]

    /// 按物料名模糊查询。
    ///
    /// 用模糊匹配是刻意的：模型从用户口语里提取出的物料名往往不完整
    /// （「联想那个笔记本」→「ThinkPad」），精确匹配会大面积查不到。
    func stock(forItem item: String, warehouse: String?) -> [StockRecord] {
        stockRecords.filter { record in
            guard record.item.localizedCaseInsensitiveContains(item) else { return false }
            guard let warehouse else { return true }
            return record.warehouse.caseInsensitiveCompare(warehouse) == .orderedSame
        }
    }

    func order(id: String) -> OrderRecord? {
        orderRecords.first { $0.orderID.caseInsensitiveCompare(id) == .orderedSame }
    }
}
```

- [ ] **Step 4: 实现两个工具**

创建 `WBAppleIntelligence/AIKit/Tools/EnterpriseTools.swift`：

```swift
import FoundationModels

@Generable(description: "库存查询参数")
struct InventoryQuery: Equatable, Sendable {
    @Guide(description: "物料名称或型号关键词，例如 ThinkPad、显示器、HDMI 线")
    var item: String

    @Guide(description: "仓库代码，如 SH01、BJ02。员工没有指定仓库时留空")
    var warehouse: String?
}

@Generable(description: "订单查询参数")
struct OrderQuery: Equatable, Sendable {
    @Guide(description: "销售订单号，形如 SO-2026-0417", .pattern(#/SO-\d{4}-\d{4}/#))
    var orderID: String
}

/// 库存查询工具。
///
/// `Tool` 的 `name` 与 `includesSchemaInInstructions` 协议本身有默认实现，
/// `parameters` 在 `Arguments` 遵循 `Generable` 时也会自动合成，所以这里只需要
/// 提供 `description` 与 `call`。`description` 写得越具体，模型越不容易漏调工具。
struct InventoryLookupTool: Tool {
    typealias Arguments = InventoryQuery
    typealias Output = String

    let name = "queryInventory"
    let description = "查询指定物料在各仓库的实时库存数量。需要具体库存数字时必须调用本工具。"

    func call(arguments: InventoryQuery) async throws -> String {
        let records = MockEnterpriseBackend.shared.stock(
            forItem: arguments.item,
            warehouse: arguments.warehouse
        )

        // 查不到时返回明确说明而不是空串：空串会让模型以为工具没生效，
        // 转而凭记忆编一个数字出来。
        guard !records.isEmpty else {
            let scope = arguments.warehouse.map { "仓库 \($0)" } ?? "所有仓库"
            return "未查询到「\(arguments.item)」在\(scope)的库存记录。"
        }

        return records
            .map { "\($0.warehouse) 仓：\($0.item)，库存 \($0.quantity) 件" }
            .joined(separator: "；")
    }
}

/// 订单状态查询工具。
struct OrderStatusTool: Tool {
    typealias Arguments = OrderQuery
    typealias Output = String

    let name = "queryOrderStatus"
    let description = "按销售订单号查询订单当前状态与预计送达日期。"

    func call(arguments: OrderQuery) async throws -> String {
        guard let order = MockEnterpriseBackend.shared.order(id: arguments.orderID) else {
            return "未查询到订单 \(arguments.orderID)。请核对订单号是否正确。"
        }
        return "订单 \(order.orderID) 当前状态：\(order.status)，预计送达 \(order.expectedDelivery)。"
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：`** TEST SUCCEEDED **`。

- [ ] **Step 6: 提交**

```bash
git add WBAppleIntelligence/AIKit/Tools WBAppleIntelligenceTests/MockEnterpriseBackendTests.swift
git commit -m "AIKit：模拟企业后端与库存、订单两个工具实现"
```

---

## Task 13: Demo 4 —— 工具调用页与文档 04

**Files:**
- Create: `WBAppleIntelligence/AIKit/Tools/ToolCallingService.swift`
- Create: `WBAppleIntelligence/Features/ToolCalling/ToolCallingViewModel.swift`
- Modify: `WBAppleIntelligence/Features/ToolCalling/ToolCallingDemoView.swift`
- Create: `Docs/04-工具调用.md`

**Interfaces:**
- Consumes: `InventoryLookupTool` / `OrderStatusTool`（Task 12）、`Prompts`、`AIKitError`、`GenerationMetrics`
- Produces: `final class ToolCallingService`，方法 `func ask(_:) async throws -> ToolCallOutcome`、`func reset()`；`struct ToolCallOutcome`，属性 `answer: String`、`toolCalls: [ToolCallRecord]`、`metrics: GenerationMetrics`；`struct ToolCallRecord: Identifiable, Equatable`，属性 `id: String`、`toolName: String`、`output: String`；`@Observable final class ToolCallingViewModel`

- [ ] **Step 1: 实现带工具的会话服务**

创建 `WBAppleIntelligence/AIKit/Tools/ToolCallingService.swift`：

```swift
import Foundation
import FoundationModels

/// 一次工具调用的记录，用于在界面上展示模型到底调了什么、拿到了什么。
struct ToolCallRecord: Identifiable, Equatable {
    let id: String
    let toolName: String
    let output: String
}

struct ToolCallOutcome: Equatable {
    let answer: String
    let toolCalls: [ToolCallRecord]
    let metrics: GenerationMetrics
}

/// 带工具的会话服务。
///
/// 工具调用是自动的：把 tools 交给 session 之后，模型自行决定何时调用、调用哪个、
/// 传什么参数，框架负责执行 `call` 并把结果回灌给模型。你的代码不需要写调度逻辑。
///
/// 这里额外做的一件事是从 `Transcript` 里把工具调用轨迹翻出来展示——
/// 企业场景里「模型到底查了什么」是必须可审计的，不能是黑箱。
@MainActor
final class ToolCallingService {

    private var session: LanguageModelSession

    init() {
        session = Self.makeSession()
    }

    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(
            model: .default,
            tools: [InventoryLookupTool(), OrderStatusTool()],
            instructions: Prompts.toolCalling
        )
    }

    func reset() {
        session = Self.makeSession()
    }

    func ask(_ question: String) async throws -> ToolCallOutcome {
        // 这里用 let 而不是 var：非流式调用不需要 markFirstToken，
        // 声明成 var 会触发「变量从未被修改」的编译器告警。
        let timer = MetricsTimer()

        let response: LanguageModelSession.Response<String>
        do {
            response = try await session.respond(to: question)
        } catch {
            throw AIKitError(error)
        }

        let promptTokens = try? await SystemLanguageModel.default.tokenCount(for: question)
        let answerTokens = try? await SystemLanguageModel.default.tokenCount(for: response.content)

        return ToolCallOutcome(
            answer: response.content,
            toolCalls: Self.toolCalls(in: response.transcriptEntries),
            metrics: timer.finish(
                promptTokenCount: promptTokens,
                responseTokenCount: answerTokens
            )
        )
    }

    /// 从本次响应产生的 Transcript 条目里提取工具输出。
    ///
    /// 只看 `.toolOutput` 而不看 `.toolCalls`：前者同时带着工具名与实际返回内容，
    /// 一条就能说明「调了谁、拿回什么」，展示所需的信息更完整。
    private static func toolCalls(
        in entries: ArraySlice<Transcript.Entry>
    ) -> [ToolCallRecord] {
        entries.compactMap { entry in
            guard case .toolOutput(let output) = entry else { return nil }
            let text = output.segments
                .compactMap { segment -> String? in
                    if case .text(let textSegment) = segment { return textSegment.content }
                    return nil
                }
                .joined(separator: "\n")
            return ToolCallRecord(id: output.id, toolName: output.toolName, output: text)
        }
    }
}
```

- [ ] **Step 2: 实现 ViewModel**

创建 `WBAppleIntelligence/Features/ToolCalling/ToolCallingViewModel.swift`：

```swift
import Observation

@Observable
final class ToolCallingViewModel {

    private(set) var answer: String = ""
    private(set) var toolCalls: [ToolCallRecord] = []
    private(set) var metrics: GenerationMetrics = .empty
    private(set) var error: AIKitError?
    private(set) var isAsking = false

    var input = ""

    /// 预置问题，方便快速演示三种典型情况：命中、按仓库过滤、查不到。
    static let samples = [
        "ThinkPad 现在还有多少库存？",
        "上海仓的 HDMI 线还有货吗？",
        "订单 SO-2026-0417 到哪了？"
    ]

    private let service = ToolCallingService()

    var canAsk: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAsking
    }

    func reset() {
        service.reset()
        answer = ""
        toolCalls = []
        metrics = .empty
        error = nil
    }

    func ask() async {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAsking else { return }

        isAsking = true
        error = nil
        answer = ""
        toolCalls = []

        do {
            let outcome = try await service.ask(question)
            answer = outcome.answer
            toolCalls = outcome.toolCalls
            metrics = outcome.metrics
        } catch {
            self.error = AIKitError(error)
        }

        isAsking = false
    }
}
```

- [ ] **Step 3: 实现界面**

覆写 `WBAppleIntelligence/Features/ToolCalling/ToolCallingDemoView.swift`：

```swift
import FoundationModels
import SwiftUI

/// Demo 4：工具调用接内部系统。
///
/// 界面上把「工具调用轨迹」单独列出来，是因为企业场景里这部分必须可审计——
/// 需要能回答「这个数字是模型编的还是真查出来的」。
struct ToolCallingDemoView: View {
    @State private var viewModel = ToolCallingViewModel()
    private let model = SystemLanguageModel.default

    var body: some View {
        DemoScaffold(route: .toolCalling) {
            let availability = ModelAvailability(model.availability)

            AvailabilityBanner(availability: availability)

            Text("试试这些问题")
                .font(.subheadline.weight(.semibold))
            ForEach(ToolCallingViewModel.samples, id: \.self) { sample in
                Button(sample) { viewModel.input = sample }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isAsking)
            }

            TextField("用自然语言提问", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(viewModel.isAsking)

            HStack {
                Button("提问") {
                    Task { await viewModel.ask() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!availability.isAvailable || !viewModel.canAsk)

                Button("清空") { viewModel.reset() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isAsking)

                if viewModel.isAsking {
                    ProgressView().padding(.leading, 4)
                }
            }

            if let error = viewModel.error {
                ErrorView(error: error)
            }

            if !viewModel.toolCalls.isEmpty {
                toolTrace
            }

            if !viewModel.answer.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("回答").font(.subheadline.weight(.semibold))
                    Text(viewModel.answer)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            MetricsBar(metrics: viewModel.metrics)
        }
    }

    private var toolTrace: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("工具调用轨迹", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.weight(.semibold))
            ForEach(viewModel.toolCalls) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.toolName)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(record.output)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        ToolCallingDemoView()
    }
}
```

- [ ] **Step 4: 构建并目视验证**

```bash
xcodebuild -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

预期：`** BUILD SUCCEEDED **`，0 warning。

模拟器验收：进入「工具调用接内部系统」，截图确认三个示例问题按钮可点、点击后填入输入框、「提问」按钮为禁用态。

**真机验收（必做）**：
1. 问「ThinkPad 现在还有多少库存？」——确认工具轨迹出现 `queryInventory`，输出里含 SH01 与 BJ02 两条，回答里的数字与工具输出一致；
2. 问「上海仓的 HDMI 线还有货吗？」——确认模型把仓库参数填成了 `SH01`；
3. 问「订单 SO-2026-0417 到哪了？」——确认调用的是 `queryOrderStatus`；
4. 问「订单 SO-9999-9999 到哪了？」——确认回答如实说未查询到，而不是编一个状态出来。

- [ ] **Step 5: 写文档 04**

创建 `Docs/04-工具调用.md`，按下列结构写：

1. **场景与价值**：把内部系统接口交给模型调度。重点说明端侧工具调用的独特价值——**业务数据始终留在设备内，模型拿到的只是你的代码返回的内容，访问边界完全由你控制**，这一点云端方案做不到。
2. **`Tool` 协议**：`Arguments`（必须是 `@Generable` 类型，用 `String`/`Int` 等基础类型会命中 `@available(*, unavailable)` 而编译失败）、`Output: PromptRepresentable`、`name`、`description`、`parameters`、`includesSchemaInInstructions`、`call(arguments:)`。**说明 `name`、`includesSchemaInInstructions` 有协议默认实现，`parameters` 在 `Arguments: Generable` 时自动合成**，所以实现一个工具只需写 `description` 与 `call`。
3. **调度是自动的**：把 tools 传给 `LanguageModelSession` 之后，何时调、调哪个、传什么参数都由模型决定，框架执行 `call` 并回灌结果，业务代码不需要写调度循环。
4. **可审计性**：如何从 `Response.transcriptEntries` 里提取 `.toolOutput` 还原调用轨迹；给出 `ToolCallingService.toolCalls(in:)` 的完整代码。说明为什么选 `.toolOutput` 而不是 `.toolCalls`。
5. **并发隔离的坑**：工程开启了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，而 `Tool.call` 是 nonisolated 的，所以工具依赖的共享数据源必须显式标 `nonisolated`，否则在 `call` 里访问会报跨隔离域错误。给出 `nonisolated struct MockEnterpriseBackend` 的写法。
6. **工具设计经验**：`description` 要具体到「什么情况下必须调用」；查不到时返回明确说明而不是空串，否则模型会转而凭记忆编数字；用模糊匹配而不是精确匹配，因为模型从口语里提取的关键词往往不完整。
7. **错误处理**：`ToolCallError` 包含 `tool` 与 `underlyingError`；工具内部抛错时的表现。
8. **踩坑记录**：`@Guide(.pattern(...))` 用于订单号约束时，正则字面量必须写 `#/.../#`。

- [ ] **Step 6: 提交**

```bash
git add WBAppleIntelligence/AIKit/Tools/ToolCallingService.swift WBAppleIntelligence/Features/ToolCalling Docs/04-工具调用.md
git commit -m "Demo 4：工具调用接内部系统，含可审计的调用轨迹"
```

---

## Task 14: 总览文档与全量验证

**Files:**
- Create: `Docs/README.md`
- Modify: `WBAppleIntelligenceTests/WBAppleIntelligenceTests.swift`（删除模板占位测试）

**Interfaces:**
- Consumes: 全部前置任务
- Produces: 无

- [ ] **Step 1: 删除模板占位测试**

`WBAppleIntelligenceTests/WBAppleIntelligenceTests.swift` 里的 `example()` 是 Xcode 模板留下的空测试，留着会让测试报告里一直有一条无意义的用例。删除整个文件：

```bash
git rm WBAppleIntelligenceTests/WBAppleIntelligenceTests.swift
```

- [ ] **Step 2: 写总览文档**

创建 `Docs/README.md`，按下列结构写：

1. **这个工程是什么**：一句话说明 + 四个 Demo 的一览表（能力 / 主用 API / 企业场景）。
2. **运行前置条件**：Xcode 26.5+、iOS 26.5+；**Foundation Models 需要 iPhone 15 Pro 及以上、设备区域与语言在支持范围内、已开启 Apple Intelligence 并完成模型下载**；写明中国大陆区域目前不在支持范围内。给出实测的构建与测试命令（含 `OS=26.5` 不可省略的原因）。
3. **模拟器的限制**：**iOS 模拟器的 Foundation Models 走宿主 Mac 的端侧模型**，宿主 Mac 不满足条件时模拟器里同样不可用。给出免写代码的查询命令：`printf 'import FoundationModels\nprint(SystemLanguageModel.default.availability)\n' | xcrun swift -`
4. **端侧 AI 的价值分析**（本文档的核心章节，要写透）：
   - **隐私与合规**：数据不出设备意味着什么。对比「把内部文档发给云端模型」在数据出境、商业秘密、个人信息保护上的合规成本。
   - **成本**：端侧推理零 token 费用。用工单抽取场景算一笔账：假设日均 N 次调用，云端按 token 计费一年是多少，端侧是零。
   - **离线与延迟**：工厂车间、地下仓库、出差途中等弱网场景；端侧首字延迟不受网络波动影响。
   - **边界**：端侧模型不是万能的——上下文窗口仅 4096 token、知识面窄于大模型、复杂推理能力有限。给出「什么时候该用端侧、什么时候该走云端」的判断依据。
5. **工程结构导读**：分层说明（AIKit 不 import SwiftUI 的理由）、目录树、每层的职责。
6. **文档索引**：链接到 01–04 四篇。
7. **已知限制**：模拟器不能真实推理；本工程只覆盖 Foundation Models，Vision / NaturalLanguage / Speech 三个模块在后续计划中。

- [ ] **Step 3: 全量测试**

```bash
xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
```

预期：`** TEST SUCCEEDED **`，且测试报告中包含 `ModelAvailabilityTests`、`AIKitErrorTests`、`GenerationMetricsTests`、`TranscriptTrimmerTests`、`ServiceTicketTests`、`MockEnterpriseBackendTests` 六个套件。

- [ ] **Step 4: 确认零警告**

```bash
xcodebuild -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' clean build 2>&1 | grep -c " warning: "
```

预期：输出 `0`。若不为 0，逐条修掉后重跑——**不要用编译器指令屏蔽警告**。

- [ ] **Step 5: 真机端到端走查**

在已开启 Apple Intelligence 的 iPhone 15 Pro+ 上安装运行，逐页确认：

| 页面 | 确认项 |
|---|---|
| 首页 | 横幅为绿色「端侧模型已就绪」 |
| 可用性探测 | 上下文窗口 4096、支持语言列表非空、支持当前地区为「是」 |
| 流式客服助手 | 逐字输出；指标条五项齐全；温度 0 与 1 的回答差异明显；长对话触发裁剪提示后仍能继续 |
| 结构化抽取 | 六个字段按声明顺序逐个填充；示例描述抽出的影响人数为 8、类别为「硬件」 |
| 工具调用 | 三个示例问题都触发对应工具；工具轨迹中的数字与回答一致；不存在的订单号如实回答未查到 |

把真机实测到的首字延迟、token 速率、schema token 数填回 `Docs/02` 与 `Docs/03` 的性能数据章节——**这几篇文档里的性能数字必须是实测值，不能是估算**。

- [ ] **Step 6: 提交**

```bash
git add Docs/README.md WBAppleIntelligenceTests
git commit -m "文档：端侧 AI 总览与价值分析，移除模板占位测试"
```

---

## 完成标准

**实现阶段（subagent 负责，全部完成后本计划即视为实现完毕）：**

- [ ] `xcodebuild build` 零 error 零 warning
- [ ] `xcodebuild test -only-testing:WBAppleIntelligenceTests` 全绿，五个测试套件齐全（`ModelAvailabilityTests`、`AIKitErrorTests`、`GenerationMetricsTests`、`TranscriptTrimmerTests`、`ServiceTicketTests`、`MockEnterpriseBackendTests`）
- [ ] 模拟器上四个 Demo 均可进入，不可用状态有明确中文引导，无崩溃无空白
- [ ] `Docs/` 下 5 篇文档齐全，所有需要真机数据的位置均为统一格式的「待真机实测」占位，无编造数字
- [ ] `AIKit/` 下无任何文件 `import SwiftUI`（核验：`grep -rl "import SwiftUI" WBAppleIntelligence/AIKit` 应无输出）

**验收阶段（项目负责人在真机上执行）：**

- [ ] 真机上四个 Demo 均能真实推理，Task 14 Step 5 的走查表全部确认
- [ ] 把实测数字回填进 `Docs/02` 与 `Docs/03` 的「待真机实测」占位

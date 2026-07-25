# WBAppleIntelligence 端侧 AI 示例工程 —— 设计文档

- 日期：2026-07-25
- 状态：已确认
- 工程路径：`/Users/wenbo/Desktop/WBAIProject/WBAppleIntelligence`

## 1. 背景与目标

`WBAppleIntelligence` 目前是一个 Xcode 26 新建的空模板工程（只有 `ContentView` 的 Hello World）。目标是把它做成一个**面向企业开发的苹果端侧 AI 能力示例工程**，配套一套可独立阅读的中文技术文档。

要解决的问题：市面上 Apple Intelligence 的示例大多停留在「调通 API」层面，缺少两样东西 —— 一是**企业落地视角**（端侧推理在隐私合规、离线可用、零调用成本上到底值多少钱），二是**工程化细节**（可用性探测、降级、上下文窗口管理、并发隔离、错误分类恢复）。这个工程要把这两样补上。

用途：作为求职面试的作品集项目，需要能被逐个模块指着讲清楚。

硬性要求：**工程必须真实可编译、可运行、无 bug**。

## 2. 环境与既有约束（已实测确认）

| 项 | 值 |
|---|---|
| Xcode | 26.5 (17F42) |
| Swift | 6.3.2 |
| iOS SDK | 26.5 |
| Deployment Target | iOS 26.5 |
| 工程格式 | `objectVersion = 77`，`fileSystemSynchronizedGroups`（磁盘建文件自动入 target） |
| 并发 | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`、`SWIFT_APPROACHABLE_CONCURRENCY = YES`、`SWIFT_VERSION = 5.0` |
| Info.plist | `GENERATE_INFOPLIST_FILE = YES`，无实体 plist 文件 |
| 本地化 | `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` |
| 设备族 | `TARGETED_DEVICE_FAMILY = "1,2"`（iPhone + iPad） |

**关键运行约束**：开发机（Mac mini M4 Pro / macOS 26.5）区域为 `zh_CN`，`SystemLanguageModel.default.availability` 实测返回 `unavailable(.deviceNotEligible)`。模拟器的 Foundation Models 走宿主 Mac 的模型，因此**模拟器上无法真实推理**。

已确认的验证路径：使用 **iPhone 15 Pro 及以上真机**，区域改为美国并开启 Apple Intelligence、下载完模型后运行。工程仍保留完整的可用性探测与降级分支——那本身就是企业代码必须处理的部分。

两条推论写进实现约束：
1. 所有 LLM 相关 UI 必须在 `.unavailable` 状态下仍可进入、可读、有明确的中文引导，不得崩溃或空白。
2. 不依赖 Apple Intelligence 的能力（Vision / NaturalLanguage / Speech）在模拟器上就要能真跑，用于日常开发自测。

## 3. 已核实的 API 清单

以下 API 均通过读取 iOS 26.5 SDK 的 `.swiftinterface` / 头文件确认存在，非推测：

**FoundationModels**
- `SystemLanguageModel.default` / `.availability` / `.isAvailable` / `.supportedLanguages` / `.supportsLocale(_:)` / `.contextSize`（4096）
- `SystemLanguageModel.Availability.UnavailableReason`：`deviceNotEligible` / `appleIntelligenceNotEnabled` / `modelNotReady`
- `SystemLanguageModel(useCase:guardrails:)`，`UseCase.general` / `.contentTagging`，`Guardrails.default` / `.permissiveContentTransformations`
- `SystemLanguageModel.tokenCount(for:)`（iOS 26.4+，多个重载：prompt / instructions / tools / schema / transcriptEntries）
- `LanguageModelSession(model:tools:instructions:)`、`.prewarm(promptPrefix:)`、`.isResponding`、`.respond(...)`、`.streamResponse(...)`
- `LanguageModelSession(model:tools:transcript:)` —— 用于从裁剪后的 Transcript 重建会话
- `LanguageModelSession.Response<Content>`：`content` / `rawContent` / `transcriptEntries`
- `LanguageModelSession.ResponseStream<Content>.Snapshot`：`content`（`PartiallyGenerated`）/ `rawContent`
- `GenerationError` 全部 9 个 case：`exceededContextWindowSize` / `assetsUnavailable` / `guardrailViolation` / `unsupportedGuide` / `unsupportedLanguageOrLocale` / `decodingFailure` / `rateLimited` / `concurrentRequests` / `refusal`
- `GenerationOptions(sampling:temperature:maximumResponseTokens:)`，`SamplingMode.greedy` / `.random(top:seed:)` / `.random(probabilityThreshold:seed:)`
- 宏：`@Generable(description:)`、`@Guide(description:_:)`
- `GenerationGuide`：`.constant` / `.anyOf` / `.pattern(Regex)` / `.minimum` / `.maximum` / `.range` / `.minimumCount` / `.maximumCount` / `.count` / `.element`
- `Tool` 协议：`associatedtype Arguments: ConvertibleFromGeneratedContent`、`associatedtype Output: PromptRepresentable`、`name` / `description` / `parameters` / `includesSchemaInInstructions` / `call(arguments:)`
- `Transcript` 及其 `Entry` / `Segment` / `Instructions` / `Prompt` / `ToolCalls` / `ResponseFormat`
- `SystemLanguageModel` conform `Observation.Observable`

**Vision**
- `RecognizeDocumentsRequest(_ revision:)`，`Result = [DocumentObservation]`
- `TextRecognitionOptions`：`recognitionLanguages` / `automaticallyDetectLanguage` / `useLanguageCorrection` / `customWords` / `minimumTextHeightFraction` / `maximumCandidateCount`
- `BarcodeDetectionOptions`：`symbologies` / `enabled`
- `DocumentObservation.Container`：`text` / `paragraphs` / `tables` / `lists`，`Container.Text.transcript`
- `perform(on:orientation:)` 的 async 重载（`CGImage` / `CIImage` / `CVPixelBuffer` / `URL` / `Data` / `CMSampleBuffer`）

**NaturalLanguage**
- `NLContextualEmbedding.contextualEmbedding(language:)` / `(script:)`，`load()` / `unload()` / `hasAvailableAssets` / `requestAssets()` / `embeddingResult(for:language:)` / `dimension` / `maximumSequenceLength`
- `NLEmbedding.sentenceEmbedding(for:)`（降级路径）
- `NLLanguageRecognizer`、`NLTokenizer`

**Speech**
- `SpeechAnalyzer`（actor）：`setModules(_:)` / `start(inputSequence:)` / `analyzeSequence(_:)` / `analyzeSequence(from:)` / `finalizeAndFinishThroughEndOfInput()` / `cancelAndFinishNow()`
- `SpeechTranscriber(locale:preset:)`，`Preset.transcription` / `.progressiveTranscription` 等，`results`（AsyncSequence）、`Result.text: AttributedString` / `isFinal`
- `SpeechTranscriber.isAvailable` / `.supportedLocales` / `.installedLocales` / `.supportedLocale(equivalentTo:)`
- `AssetInventory.status(forModules:)` / `.assetInstallationRequest(supporting:)` / `.reserve(locale:)`
- `AnalyzerInput(buffer:)`

## 4. 架构

### 4.1 分层原则

采用**分层 + 能力即服务**：`AIKit/` 是纯业务能力层，**不 import SwiftUI**；`Features/` 是 UI 层，每个 Demo 一个 `@Observable` ViewModel + View。

选择理由：AIKit 层不依赖 UI，意味着每个能力都能被独立单测、独立讲解、整层复制进真实公司项目。这直接服务于「企业开发中具有真实应用价值」这个目标。

明确否决的两个方案：
- **单一 `AIService` 门面**：调用方便，但必然长成上帝对象，文件巨大且无法分模块讲解。
- **本地 SPM 多 module**：边界最硬，但会丢掉 Xcode 26「磁盘建文件自动入 target」的便利，构建配置复杂度对示例工程不划算。

### 4.2 目录结构

```
WBAppleIntelligence/                    ← 工程目录（.xcodeproj 所在）
├── Docs/                               ← 技术文档；刻意放在同步组之外，不会被打进 App 包
├── WBAppleIntelligence/                ← fileSystemSynchronizedGroup 根
│   ├── App/
│   │   ├── WBAppleIntelligenceApp.swift
│   │   └── RootView.swift              ← 能力目录首页
│   ├── AIKit/                          ← 不 import SwiftUI
│   │   ├── Core/
│   │   │   ├── ModelAvailability.swift
│   │   │   ├── AIKitError.swift
│   │   │   ├── SessionFactory.swift
│   │   │   └── GenerationMetrics.swift
│   │   ├── Chat/StreamingChatService.swift
│   │   ├── Extraction/
│   │   │   ├── ServiceTicket.swift
│   │   │   └── TicketExtractionService.swift
│   │   ├── Tools/
│   │   │   ├── MockEnterpriseBackend.swift
│   │   │   ├── InventoryLookupTool.swift
│   │   │   └── OrderStatusTool.swift
│   │   ├── Document/
│   │   │   ├── DocumentScanService.swift
│   │   │   └── Invoice.swift
│   │   ├── Knowledge/
│   │   │   ├── TextEmbedder.swift          ← 协议
│   │   │   ├── ContextualEmbedder.swift
│   │   │   ├── LegacyEmbedder.swift
│   │   │   ├── VectorIndex.swift
│   │   │   └── KnowledgeStore.swift
│   │   └── Speech/
│   │       ├── TranscriptionService.swift
│   │       └── MeetingMinutes.swift
│   ├── Features/                       ← 7 个 Demo，各自 VM + View
│   │   ├── Availability/
│   │   ├── Chat/
│   │   ├── TicketExtraction/
│   │   ├── ToolCalling/
│   │   ├── DocumentPipeline/
│   │   ├── Knowledge/
│   │   └── Meeting/
│   ├── Intents/
│   │   ├── SubmitTicketIntent.swift
│   │   └── AppShortcuts.swift
│   ├── DesignSystem/
│   │   ├── AvailabilityBanner.swift
│   │   ├── MetricsBar.swift
│   │   └── DemoScaffold.swift
│   ├── SampleData/                     ← 种子知识库文档、示例单据图、示例音频
│   └── Assets.xcassets
└── WBAppleIntelligenceTests/
```

`Docs/` 放在同步组之外是有意为之：`fileSystemSynchronizedGroups` 会把同步组内的未知类型文件当作资源打进 App bundle，Markdown 文档不应进包。

## 5. 模块清单

| # | Demo | 主用 API | 企业场景 |
|---|---|---|---|
| 1 | 端侧可用性与能力探测 | `SystemLanguageModel.availability` / `supportedLanguages` / `contextSize` | 灰度发布与降级策略制定 |
| 2 | 流式客服助手 | `streamResponse` / `prewarm()` / `GenerationOptions` / 上下文超限恢复 | 内部知识客服 |
| 3 | 结构化工单抽取 | `@Generable` + `@Guide` + `PartiallyGenerated` 流式填表 | 自由文本 → 强类型工单，直接入库 |
| 4 | 工具调用接内部系统 | `Tool` 协议 + 自定义 `Arguments` | LLM 调用库存 / 订单 / 审批接口 |
| 5 | 单据数字化流水线 | `RecognizeDocumentsRequest` → `@Generable` 抽取 | 拍照录入发票 / 合同 / 巡检单 |
| 6 | 端侧语义知识库（RAG） | `NLContextualEmbedding` + 本地向量检索 → LLM 作答 | 制度文档离线问答，数据不出端 |
| 7 | 会议纪要 | `SpeechAnalyzer` + `SpeechTranscriber` → LLM 生成纪要与待办 | 现场录音转结构化纪要 |

外加 **App Intents 集成**：把「提交工单」暴露给 Siri / Spotlight / 快捷指令。

## 6. 关键技术决策

### 6.1 可用性驱动 UI

`SystemLanguageModel` conform `Observation.Observable`，SwiftUI 可直接观测其可用性变化——用户在系统设置里开启 Apple Intelligence 后，App 无需重启即自动恢复。

`ModelAvailability` 把三种 `UnavailableReason` 映射为中文原因 + 可操作建议：

| Reason | 含义 | 引导 |
|---|---|---|
| `deviceNotEligible` | 机型不支持，或区域 / 语言不在支持范围 | 说明机型要求与区域限制 |
| `appleIntelligenceNotEnabled` | 用户未开启 | 引导至系统设置 |
| `modelNotReady` | 模型正在下载 / 未就绪 | 提示稍后重试 |

### 6.2 上下文窗口超限的真实恢复

`contextSize` 仅 4096 token。捕获 `GenerationError.exceededContextWindowSize` 后，从旧 session 的 `Transcript` 中保留首条 `Instructions` entry + 最近 4 条对话 entry（即最近两轮问答），用 `LanguageModelSession(model:tools:transcript:)` 重建会话并重发当次 prompt。裁剪策略独立成纯函数 `TranscriptTrimmer.trim(_:keepingRecentEntries:)`，可单测；UI 上明确提示「已裁剪早期对话以继续」，不静默丢失上下文。

### 6.3 并发隔离

工程默认 `MainActor` 隔离，因此重活必须显式移出主线程：

- `ContextualEmbedder` / `LegacyEmbedder`：`actor`，模型 load 与向量计算全在 actor 内
- `DocumentScanService`：`nonisolated` 方法 + Vision 的 `perform(on:orientation:)` async 重载
- `TranscriptionService`：`SpeechAnalyzer` 本身是 actor；`AVAudioEngine` 的 tap 回调在音频线程，经 `AsyncStream` 汇入 `AnalyzerInput` 序列
- `VectorIndex`：纯值类型 + `nonisolated` 计算函数，便于单测

### 6.4 Embedding 双实现 + 自动降级

`TextEmbedder` 协议定义 `func embed(_ text: String) async throws -> [Double]` 与 `dimension`。

- 首选 `ContextualEmbedder`：`NLContextualEmbedding`，需 `requestAssets()` 下载
- 降级 `LegacyEmbedder`：`NLEmbedding.sentenceEmbedding(for:)`，iOS 14 起即有，无需下载

注意：`NLContextualEmbeddingResult` 只提供 **token 级**向量（`enumerateTokenVectors(in:using:)` / `tokenVector(at:tokenRange:)`，Swift 中为 `[Double]`），**没有现成的句向量**。`ContextualEmbedder` 需自行做**均值池化**把 token 向量聚合成句向量，并做 L2 归一化。这是实现上的必要步骤，也是文档 `06` 的一个讲解点。`NLEmbedding.sentenceEmbedding` 则直接给句向量，两者的这一差异也是双实现值得对比的原因之一。

`KnowledgeStore` 启动时探测并选择实现，UI 上显示当前使用哪一种。这样任何设备都能跑通检索流程，同时文档可横向对比两代 embedding 的召回质量差异。

### 6.5 生成指标可见

`GenerationMetrics` 记录首 token 延迟、总耗时、输入 / 输出 token 数（`SystemLanguageModel.tokenCount(for:)`，iOS 26.4+，target 26.5 满足）。每个 LLM Demo 页面底部用 `MetricsBar` 展示。端侧 AI 的说服力集中在这些数字上——文档中会给出真机实测数据。

### 6.6 错误处理

统一 `AIKitError: LocalizedError`，把 `GenerationError` 全部 9 个 case 映射为中文 `errorDescription` + `recoverySuggestion`，各 Demo 共用同一套错误展示组件。文档中逐个说明每个 case 在什么真实情况下会触发。

### 6.7 权限配置

因 `GENERATE_INFOPLIST_FILE = YES`，权限文案以 `INFOPLIST_KEY_*` 形式写入 `project.pbxproj` 的 app target build settings：

- `INFOPLIST_KEY_NSCameraUsageDescription`（单据拍照）
- `INFOPLIST_KEY_NSPhotoLibraryUsageDescription`（从相册选单据）
- `INFOPLIST_KEY_NSMicrophoneUsageDescription`（会议录音）
- `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription`（语音转写）

## 7. 文档

`Docs/` 目录下 Markdown，共 8 篇：

| 文件 | 内容 |
|---|---|
| `README.md` | 总览：端侧 AI 全景图、框架选型决策树、隐私 / 成本 / 离线三维价值分析、工程结构导读、运行前置条件 |
| `01-可用性探测与降级.md` | 三种不可用原因的真实成因、灰度策略、Observable 驱动的自动恢复 |
| `02-流式对话与会话管理.md` | `streamResponse` 机制、`prewarm` 收益实测、`GenerationOptions` 调参对比、上下文窗口管理 |
| `03-结构化生成.md` | `@Generable` / `@Guide` 全部 guide 类型、`PartiallyGenerated` 流式填表、schema 设计经验 |
| `04-工具调用.md` | `Tool` 协议实现、如何安全地把内部系统接口暴露给模型、失败处理 |
| `05-文档识别流水线.md` | `RecognizeDocumentsRequest` vs `RecognizeTextRequest`、表格 / 列表结构提取、OCR → LLM 串联 |
| `06-端侧语义检索.md` | 两代 embedding 对比、向量检索实现、端侧 RAG 的边界与适用规模 |
| `07-语音转写与纪要.md` | `SpeechAnalyzer` 架构、资产下载管理、长音频与实时两种模式、音频线程与并发 |

每篇统一结构：**场景与价值 → API 讲解 → 完整代码 → 踩坑记录 → 性能数据 → 限制与降级**。

「端侧相关功能的应用场景及价值」这一要求主要由 `README.md` 的价值分析章节和每篇的「场景与价值」章节承载。

## 8. 测试

Swift Testing（`import Testing`）。只测确定性逻辑，不测 LLM 输出（非确定、依赖设备状态）：

- `VectorIndex`：余弦相似度计算、top-K 排序、空索引 / 维度不匹配的边界
- Transcript 裁剪策略：保留 instructions、保留最近 N 条、裁剪后条目顺序
- `ModelAvailability`：三种 reason → 文案映射
- `GenerationSchema` 构造：各 `@Generable` 类型的 schema 能正常构造不抛错
- OCR 结果归一化：金额 / 日期 / 编号的文本清洗函数

## 9. 实施里程碑

每个里程碑结束时工程必须干净编译（`xcodebuild build` 零 error 零 warning）。

| M | 内容 | 验收 |
|---|---|---|
| M0 | 骨架：目录结构、`INFOPLIST_KEY_*`、DesignSystem 三组件、能力目录首页 | 编译通过，首页可导航到 7 个占位页 |
| M1 | Foundation Models 四件套：可用性 / 流式对话 / 结构化抽取 / 工具调用 | 模拟器上展示不可用引导；真机上四个 Demo 全部真实推理 |
| M2 | Vision 单据数字化流水线 | 模拟器上用内置示例图跑通 OCR → 结构化 |
| M3 | NaturalLanguage 端侧语义知识库 | 模拟器上跑通向量入库与检索，含降级路径 |
| M4 | Speech 会议纪要 | 真机录音转写；模拟器用内置音频文件 |
| M5 | App Intents 系统集成 | 真机上通过 Spotlight / 快捷指令触发 |
| M6 | Docs 8 篇 + 单元测试 + 真机端到端验证 | 全部测试通过，真机逐页走查 |

## 10. 明确不做（YAGNI）

- **LoRA Adapter 微调**（`SystemLanguageModel.Adapter`）：需要训练产物，与「示例工程可运行」冲突
- **Core ML 自定义模型**：需要额外模型文件，体积大，且与 Apple Intelligence 主题关联弱
- **Translation / ImagePlayground / Writing Tools**：偏消费级，企业价值弱于已选模块
- **云端模型对比实现**：本工程主题是端侧，云端对比在文档中以数据说明即可
- **多语言 UI**：工程 UI 与文档统一中文

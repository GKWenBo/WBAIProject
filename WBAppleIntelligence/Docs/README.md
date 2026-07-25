# WBAppleIntelligence 端侧 AI 能力示例工程

这是一个基于 Apple `FoundationModels` 框架的端侧 AI 能力示例工程：用四个贴近企业场景的 Demo，展示端侧模型能替代云端方案做哪些事、要付出什么代价、边界又在哪里。

## 1. 这个工程是什么

一句话：在 iOS App 里接入端侧大语言模型时会遇到的四类典型问题——「能不能用」「怎么流式对话」「怎么拿到结构化数据」「怎么让模型安全地查内部系统」——本工程各用一个 Demo 给出可运行的答案。

| Demo | 能力 | 主用 API | 企业场景 |
|---|---|---|---|
| 端侧可用性探测 | 判断当前设备能否使用端侧模型，给出对应的降级引导 | `SystemLanguageModel.availability`、`supportedLanguages`、`contextSize` | 上线前灰度判断：这台设备该走 AI 路径还是传统路径 |
| 流式客服助手 | 逐字流式生成回答，支持温度调节，长对话自动裁剪上下文 | `LanguageModelSession.streamResponse(to:options:)`、`GenerationOptions`、`TranscriptTrimmer` | 企业内部 IT 知识客服，员工用自然语言提问 |
| 结构化工单抽取 | 把一段自由文本抽取成 schema 强约束的结构化数据，边生成边填表 | `@Generable`、`@Guide`、`streamResponse(to:generating:)` | 服务台工单录入：口语描述实时变成一张强类型工单 |
| 工具调用接内部系统 | 模型自主决定要不要调用工具、调用哪个、传什么参数，查询内部系统数据 | `Tool` 协议、`LanguageModelSession(tools:)`、`Transcript.Entry.toolOutput` | 库存 / 订单查询：一句自然语言完成原本要点五六个页面的操作 |

四个 Demo 依次建立在同一套地基上：可用性探测是入口（第 1 个），流式对话建立起基础的会话与指标能力（第 2 个），结构化抽取和工具调用（第 3、4 个）都复用了前两个 Demo 里已经跑通的会话管理与错误处理模式。

## 2. 运行前置条件

- **Xcode 26.5 及以上**，构建与测试目标 **iOS 26.5 及以上**。
- Foundation Models 要真正跑起来（即 `SystemLanguageModel.default.availability` 返回 `.available`），需要同时满足：
  - 机型达标：iPhone 15 Pro 及以上；
  - 设备区域与系统语言落在 Apple Intelligence 的支持范围内——**中国大陆区域目前不在支持范围内**（详见 [01-可用性探测与降级.md](01-可用性探测与降级.md) 第 5 节的实测记录）；
  - 用户已在系统设置「Apple 智能与 Siri」里手动开启 Apple Intelligence；
  - 模型资源已经下载完成（体积以 GB 计，下载时机由系统根据网络、电量、系统负载自动决定，App 无法主动触发）。

  以上任意一环不满足，`availability` 都会是 `.unavailable`，具体原因与对应的用户引导见 [01-可用性探测与降级.md](01-可用性探测与降级.md)。

- 本工程实测使用的构建与测试命令：

  ```
  xcodebuild -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' clean build
  ```

  ```
  xcodebuild test -project WBAppleIntelligence.xcodeproj -scheme WBAppleIntelligence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WBAppleIntelligenceTests
  ```

  `-destination` 里的 `OS=26.5` 不可省略：省略后 `xcodebuild` 不会退化成用某个默认版本，而是直接报错「Unable to find a device matching the provided destination specifier」，必须显式指定一个本机已安装的模拟器运行时版本。

## 3. 模拟器的限制

**iOS 模拟器里的 Foundation Models 走的是宿主 Mac 的端侧模型**，不是模拟器独立模拟出来的一套设备状态。也就是说：宿主 Mac 的 Apple Intelligence 状态如果不满足条件（机型、区域、开关、模型下载任一环节），在模拟器里运行本工程同样会看到不可用，而且模拟器内部没有独立的开关可以切换——唯一的切换方式是去改宿主 Mac 系统设置本身（详见 [01-可用性探测与降级.md](01-可用性探测与降级.md) 第 5 节第 2 条）。

不需要写一行 Swift 代码、不需要跑起完整 App，一条命令就能查询宿主环境当前的可用性状态：

```
printf 'import FoundationModels\nprint(SystemLanguageModel.default.availability)\n' | xcrun swift -
```

这条命令在联调「为什么模拟器里横幅总是橙色」这类问题时很有用：可以先排除是不是宿主环境本身就不可用，再去看 App 代码。本工程的开发机处于 `zh_CN` 区域，实测这条命令的输出是不可用状态（完整记录见 [01-可用性探测与降级.md](01-可用性探测与降级.md) 第 5 节第 1 条）。这也是为什么本工程所有和真实推理相关的性能数据都以统一格式的「待真机实测」占位，而不是拿本机随手跑出来的一个数字充数——本机环境本来就跑不出真实的端侧推理结果。

## 4. 端侧 AI 的价值分析

### 4.1 隐私与合规

端侧推理的核心承诺是：从用户输入到模型输出，数据从来没有离开过这台设备。这句话背后对应的是一套具体的合规成本对比。

把「把内部文档 / 员工对话发给云端模型做一次问答」这件事拆开看，它构成的是一次「数据出企业网络」的事件，进一步细分包含三类现实的合规压力：

- **数据出境**：如果云端模型的服务地部署在境外，这次调用往往同时构成一次数据跨境传输，需要走对应的合规评估与审批流程，很多行业（金融、政务、涉密单位）对此有明确的前置限制。
- **商业秘密**：客服问答里经常夹带内部系统名称、报错信息、故障现象；工单描述里经常带着设备型号、故障位置、影响范围；工具调用场景里模型要用到的是库存数量、订单状态这类业务数据本身。这些内容一旦被序列化发送给第三方服务，就脱离了企业对这些信息的直接控制边界。
- **个人信息保护**：员工的账号、工号、设备信息、对话内容本身都可能落入个人信息保护相关法规的规制范围，发给第三方处理通常需要额外的告知与授权机制。

端侧推理把这三类问题从「怎么脱敏、怎么审批、怎么和供应商签数据处理协议」变成「不存在」——因为数据从来没有产生过要离开设备的那一步。[02-流式对话与会话管理.md](02-流式对话与会话管理.md) 第 1 节和 [04-工具调用.md](04-工具调用.md) 第 1 节分别针对客服对话与工具调用两个场景展开了这一点：前者强调对话内容不出设备满足数据不出境与内部资料保密要求，后者强调业务数据的访问边界由业务代码控制，不需要把数据喂给云端模型。

### 4.2 成本

云端方案的账单由三个变量决定：**单价**（每百万 token 或每次调用的价格，由所选云端模型和服务商定价决定）、**单次调用消耗的 token 数**（提示词 + 系统指令 + 回答，结构化场景还要算上 schema 本身，见 [03-结构化生成.md](03-结构化生成.md) 第 7 节）、**调用频次**（企业内该功能的员工规模与人均调用次数决定的日 / 月调用量）。三者相乘，再乘以统计周期，就是这个功能在这个周期内的云端账单。

以工单抽取场景为例，可以把这笔账写成一个通用公式，具体数字留给读者按自己企业的真实情况代入：

```
年成本（云端）= 日均调用次数 × 365 × 单次调用消耗的 token 数（提示词 + schema + 回答）× 每 token 单价
```

本文档不为任何具体的云端模型标注单价——公开定价会随时间和服务商调整，写死一个数字既不准确也很快过期，请读者用自己实际选用的云端模型报价去代入这个公式，得到符合自己业务规模的真实数字。

唯一不需要真机测试、也不需要任何外部报价就能确定的一点是：上面公式里，单价、单次 token 数、调用频次无论取什么值，**端侧推理对应的按 token 计费这一项恒为零**——模型权重和推理算力都在设备本地，不存在按次结算的账单。调用频次越高（比如把这个功能铺给全体员工），云端方案的账单会随调用量线性增长，而端侧方案不会因为调用次数增加而多出一笔可计价的费用——这是端侧方案在「规模化」这个维度上相比云端方案最结构性的优势，也是为什么工单抽取、客服问答这类高频、长尾的场景特别适合优先考虑端侧路径。

但这不等于端侧推理没有成本，只是成本换了个地方结算，且不是本文档能替读者标出具体数字的部分。每一次推理仍然要消耗设备电量、产生发热，这是真实存在的边际成本，只是不会体现在账单上（[02-流式对话与会话管理.md](02-流式对话与会话管理.md) 第 1 节的说法更准确：端侧模型的计算成本已经摊在硬件里）。更进一步，这份「摊在硬件里」的成本本身有一道门槛——本文档第 2 节写明的机型要求（iPhone 15 Pro 及以上）意味着企业要让员工用上端侧方案，前提是设备本身已经达标或愿意为此升级，这是一笔实实在在需要摊到设备采购与更新周期里的成本，只是不体现为每次调用的账单，而是体现为设备资产本身。

### 4.3 离线与延迟

企业场景里有相当一部分员工的工作环境本身就是弱网或无网：工厂车间、地下仓库、跨区域出差途中、部分企业内网对公网访问做了限制的场景。如果 AI 功能依赖联网才能使用，恰恰会在最需要它的场景里失效——[02-流式对话与会话管理.md](02-流式对话与会话管理.md) 第 1 节举的例子很直接：员工要问的问题本身可能就是「连不上公司 Wi-Fi 怎么办」，如果客服机器人也要联网才能回答，这个场景就自相矛盾了。

端侧推理的整条链路（`SystemLanguageModel` → `LanguageModelSession` → `streamResponse`）不依赖网络，断网时功能不受影响；首字延迟也不会因为网络状况波动——不存在「上传请求 → 排队 → 云端返回」这段本质上不可控的网络往返时间，延迟只取决于设备本身的算力与模型加载状态（[02-流式对话与会话管理.md](02-流式对话与会话管理.md) 第 3 节讨论的 `prewarm()` 就是针对模型加载这一段做的优化）。真实的首字延迟与生成速率数值目前尚未在真机上测量，[02-流式对话与会话管理.md](02-流式对话与会话管理.md) 与 [03-结构化生成.md](03-结构化生成.md) 各自的性能数据章节留了对应的「待真机实测」占位。

### 4.4 边界

端侧模型不是云端大模型的免费替代品，它有几条明确的边界，讲清楚这些边界才是这份文档可信的地方：

- **上下文窗口是硬限制。** `SystemLanguageModel.contextSize` 是框架报告的固定常量，值为 **4096**，输入提示词与生成内容加在一起不能超过这个数字（详见 [01-可用性探测与降级.md](01-可用性探测与降级.md) 第 2 节、[02-流式对话与会话管理.md](02-流式对话与会话管理.md) 第 5 节）。长对话、长文档摘要这类需要大上下文的场景，端侧模型天然吃亏。
- **知识面窄于云端大模型。** 端侧模型为了能装进一台手机的存储与内存预算，模型规模必然远小于跑在数据中心里的云端大模型，训练数据覆盖的知识广度也相应更窄，这是模型体量决定的结构性差异，不是某个版本的临时短板。
- **复杂推理能力有限。** 多步骤、跨领域、需要长链路推理的任务（复杂的代码生成、多轮严谨的逻辑推导），端侧模型的表现通常不如参数规模大得多的云端模型，这也是模型体量决定的能力上限差异。
- **可用性本身不是恒定的。** [01-可用性探测与降级.md](01-可用性探测与降级.md) 第 3 节记录的三种不可用原因（机型不达标、开关未开启、模型未就绪）加上区域/语言限制说明，端侧能力是「按设备、按用户设置分布」的，不是「装了 App 就一定能用」的确定能力——这也是为什么可用性探测被放在第一个 Demo，是所有后续能力的地基。

基于这几条边界，一个大致可用的判断依据是：**数据敏感、调用频繁、任务本身相对简单直接（问答、抽取、少量工具查询）、或者需要离线可用** 的场景，优先考虑端侧；**需要广博的通用知识、需要长上下文、需要复杂多步推理，或者目标用户设备/地区本身就不满足端侧可用性条件** 的场景，应该考虑云端方案，或者按 [01-可用性探测与降级.md](01-可用性探测与降级.md) 第 6 节说的三种降级策略组合使用——现实项目里往往是「优先端侧 → 端侧不可用降级到规则引擎 → 关键路径可选云端兜底」的组合，不是非此即彼的单选题。

## 5. 工程结构导读

```
WBAppleIntelligence/WBAppleIntelligence/     内层源码组
├── App/                        入口与导航：WBAppleIntelligenceApp、RootView、DemoRoute
├── AIKit/                      框架封装与业务逻辑层，不 import SwiftUI
│   ├── Core/                   ModelAvailability、AIKitError、GenerationMetrics、Prompts、TranscriptTrimmer
│   ├── Chat/                   StreamingChatService
│   ├── Extraction/             ServiceTicket、TicketExtractionService
│   └── Tools/                  EnterpriseTools、MockEnterpriseBackend、ToolCallingService
├── Features/                   各 Demo 的 SwiftUI 视图（三个驱动模型的 Demo 还各带一个视图模型）
│   ├── Availability/            仅 AvailabilityDemoView，无视图模型
│   ├── Chat/
│   ├── TicketExtraction/
│   └── ToolCalling/
└── DesignSystem/                跨 Demo 复用的 UI 组件：AvailabilityBanner、MetricsBar、ErrorView、ScenarioCard、DemoScaffold
```

上面这棵树的根是仓库里的内层源码组 `WBAppleIntelligence/WBAppleIntelligence/`；外层的 `WBAppleIntelligence/` 才是仓库根目录，`WBAppleIntelligenceTests/` 与这个内层源码组同级（都直接挂在仓库根下），测试文件与被测的 `AIKit` 类型一一对应（`ModelAvailabilityTests`、`AIKitErrorTests`、`GenerationMetricsTests`、`TranscriptTrimmerTests`、`ServiceTicketTests`、`MockEnterpriseBackendTests`）。`Docs/` 与 `WBAppleIntelligence.xcodeproj` 同样与内层源码组平级、在源码组之外，Markdown 文档不会被打进 App 包。

四层各自的职责：

- **`App`**：组合根。持有 `SystemLanguageModel` 单例、渲染能力目录首页、负责导航到四个 Demo，本身不包含任何生成逻辑。
- **`AIKit`**：对 `FoundationModels` 框架的封装与企业场景所需的业务逻辑（可用性判断、错误翻译、指标采集、上下文裁剪、结构化模型、工具实现）。这一层被刻意设计成不 import SwiftUI——它只依赖 `Foundation` 与 `FoundationModels`，理由有两条：一是保证这层逻辑可以脱离 UI 环境单独做单元测试（六个测试套件测的正是这一层，全程不需要渲染任何 View）；二是把「和模型打交道的逻辑」与「怎么把结果画出来」彻底分开，这层代码未来要复用到别的 UI 框架、命令行工具，甚至非 UI 的后台任务里，都不需要改动。这条约束不是靠人工审查维持的，而是有一条可重复执行的核验命令：
  ```
  grep -rn "^import SwiftUI" WBAppleIntelligence/AIKit/
  ```
  这条命令在本工程当前代码上没有任何输出。
- **`Features`**：每个 Demo 一个子目录。`Chat`、`TicketExtraction`、`ToolCalling` 这三个会驱动模型生成的 Demo，都是 `XxxDemoView`（SwiftUI 视图）+ `XxxViewModel`（`@Observable`，持有对应的 `AIKit` service）配对，负责把 `AIKit` 层的结果画成界面、处理用户交互。`Availability/` 是唯一的例外，目录里只有 `AvailabilityDemoView`，没有 `AvailabilityViewModel`——这个 Demo 只做可用性判断与降级引导，刻意不包含任何生成逻辑（详见 [01-可用性探测与降级.md](01-可用性探测与降级.md)），因此不需要 `@Observable` 视图模型去持有 `AIKit` service。
- **`DesignSystem`**：跨 Demo 复用的展示组件——`AvailabilityBanner`（可用性横幅）、`MetricsBar`（首字延迟/总耗时/速率/输入输出 token 这五项指标的展示条）、`ErrorView`（统一的错误展示，同时呈现「发生了什么」与「该怎么办」）、`ScenarioCard`（每个 Demo 顶部的场景/价值说明卡片）、`DemoScaffold`（Demo 页面的统一骨架）。抽出这一层是为了让「一个 Demo 页面长什么样」不必在四个 Demo 里各写一遍。

## 6. 文档索引

- [01-可用性探测与降级.md](01-可用性探测与降级.md)——`SystemLanguageModel` 的可用性判断、三种不可用原因、Observable 驱动的自动刷新、三种降级策略、非 frozen 枚举的处理方式。
- [02-流式对话与会话管理.md](02-流式对话与会话管理.md)——`streamResponse` 流式 API 的正确用法、`prewarm()`、`GenerationOptions`、4096 token 上下文窗口与超限后的自动裁剪重试、`ContinuousClock` 指标采集。
- [03-结构化生成.md](03-结构化生成.md)——`@Generable` / `@Guide` 宏的工作原理与全部约束类型、`PartiallyGenerated` 驱动的流式填表、字段声明顺序对产品体验的影响、schema 本身占用的 token 预算。
- [04-工具调用.md](04-工具调用.md)——`Tool` 协议、模型自主决定调用时机与参数的自动调度、基于 `Transcript.Entry.toolOutput` 的可审计调用轨迹、并发隔离踩坑、工具设计的三条经验。

## 7. 已知限制

- **模拟器无法在本工程当前的开发环境下完成真实推理验证。** 不是因为模拟器本身不支持真实推理（第 3 节说过，它走的是宿主 Mac 的端侧模型），而是本工程的宿主 Mac 处于 `zh_CN` 区域、不满足 Apple Intelligence 的资格条件。在这样的环境里，模拟器只能验证「不可用」路径下的界面表现，无法验证真实生成结果——真机走查是目前唯一能验证真实推理效果、也是唯一能拿到真实性能数据的途径，[02-流式对话与会话管理.md](02-流式对话与会话管理.md)、[03-结构化生成.md](03-结构化生成.md)、[04-工具调用.md](04-工具调用.md) 三篇文档里合计五处「待真机实测」占位都是在等这一步（本文档不含性能数据，没有这类占位）。
- **本工程目前只覆盖 `FoundationModels` 一个框架。** Apple 端侧 AI 能力矩阵里的 Vision（图像理解）、NaturalLanguage（文本分析）、Speech（语音识别）三个框架均未涉及，如果要覆盖更完整的端侧 AI 能力，这是待补的方向。

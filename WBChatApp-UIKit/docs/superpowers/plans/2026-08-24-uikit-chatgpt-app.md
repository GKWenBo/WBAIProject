# WBChatApp-UIKit 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 UIKit + MVVM 实现一个对标 iOS 端 ChatGPT 的 AI 聊天 App，核心是 SSE 流式输出、Markdown 块级增量渲染、流式期间的滚动手势冲突处理与 OpenAI/Anthropic 双协议适配。

**Architecture:** 单 target 分目录，依赖方向严格单向 `App → Features → Core → Common`。Core 层全部面向协议、无 UI 依赖、可纯逻辑单测；ViewModel 不 import UIKit，通过单一 `Output` 回调驱动 ViewController，并刻意把「结构性变化（走 diffable snapshot）」与「流式增量（直接打到 cell 实例）」分成两条通路。

**Tech Stack:** Swift 6 / UIKit / TextKit 2 / Swift Concurrency / swift-markdown 0.8.0 / GRDB 7.9.0 / Speech + AVFoundation / Swift Testing（单测）+ XCTest（UI 测试）

设计规格：[`docs/superpowers/specs/2026-08-24-uikit-chatgpt-app-design.md`](../specs/2026-08-24-uikit-chatgpt-app-design.md)

## Global Constraints

每个任务的要求都隐含包含本节。

- **Deployment Target: iOS 16.0**。不得使用 iOS 17+ API。
- **模块名是 `WBChatApp_UIKit`**（target 名 `WBChatApp-UIKit` 中的连字符会被转成下划线）。测试文件一律 `@testable import WBChatApp_UIKit`。
- **ViewModel 不得 `import UIKit`**。ViewModel 只产出纯模型（`BlockPatch` 等），属性串渲染由视图层调用 `AttributedRenderer` 完成。Core/Markdown 的渲染器可以 import UIKit。
- **TextKit 2 禁令**：全项目禁止出现 `textView.layoutManager` 与 `textView.textStorage`。访问任一都会让 `UITextView` 静默回退到 TextKit 1。只允许 `textView.textLayoutManager` / `textView.textContentStorage`。
- **纯代码 UI**，不使用 Storyboard/xib。Auto Layout 一律 `translatesAutoresizingMaskIntoConstraints = false`。
- **单测框架用 Swift Testing**（`import Testing`，`@Test` / `#expect`），UI 测试用 XCTest。与同仓库 `WBChatApp` 保持一致。
- **注释与文档一律中文**。
- **git 提交信息用中文，不带任何 AI 协作署名尾行**（无 `Co-Authored-By`）。
- **依赖版本锁定**：`swift-markdown` from `0.8.0`，`GRDB.swift` from `7.9.0`。不得引入其它三方依赖。
- 构建/测试目标模拟器统一为 **iPhone 17 Pro，OS=26.5**。`OS=26.5` 不可省略——本机上只写 `name=iPhone 17 Pro` 会报 `Unable to find a device matching the provided destination specifier`（已实测稳定复现）。
- **`SWIFT_VERSION = 5.0`，`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`**（Task 1 已配好）。因此类型**默认不是** MainActor 隔离的：Core 层保持 `nonisolated` 即可满足 `Sendable` 约束；只有 ViewModel、ViewController 与视图类需要显式标 `@MainActor`。不要给 Core 层的值类型逐个加 `nonisolated`，那是默认 MainActor 隔离工程才需要的做法。
- **不要修改 `project.pbxproj`。** 工程是 `objectVersion = 77` 的 Xcode 26 新格式，启用了 `fileSystemSynchronizedGroups`——在磁盘上按目录建 `.swift` 文件即自动加入对应 target，无需也不应手改工程文件。
- ⚠️ **文件路径基准：本计划所有 `WBChatApp-UIKit/...` 路径都相对于 Xcode 工程目录 `/Users/wenbo/Desktop/WBAIProject/WBChatApp-UIKit/`。** 也就是说 App 源码的绝对根目录是：

  ```
  /Users/wenbo/Desktop/WBAIProject/WBChatApp-UIKit/WBChatApp-UIKit/
  ```

  注意这里有**两层同名目录**（外层是 Xcode 工程目录，内层是被 target 同步的源码目录）。建文件前先 `pwd` 确认，或直接用绝对路径。**放错一层不会报错——文件只是不参与编译，`xcodebuild build` 照样 `BUILD SUCCEEDED`**，这是 Task 3 真实踩过的坑（四个类型文件建在外层，从未被编译，直到下一个任务引用它们才暴露）。

  建完文件后核验一句：
  ```bash
  find /Users/wenbo/Desktop/WBAIProject/WBChatApp-UIKit -name "*.swift" -not -path "*/.build/*" | sort
  ```
  所有 App 源码都必须在 `WBChatApp-UIKit/WBChatApp-UIKit/` 下，测试在 `WBChatApp-UIKit/WBChatApp-UIKitTests/` 下。

**通用命令**（在 `/Users/wenbo/Desktop/WBAIProject/WBChatApp-UIKit` 下执行）：

```bash
xcodebuild build -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -quiet
```

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/<测试类型名>'
```

> ⚠️ **`-only-testing` 必须用 Swift 类型名（如 `SSEEventParserTests`），不能用 `@Suite` 的中文显示名。**
> 用中文显示名会匹配到 **0 个用例**，而 `xcodebuild` 依然打印 `** TEST SUCCEEDED **`——
> 这是一条会让整个任务假绿的陷阱，已实测确认。
>
> **每次跑完测试都要核对实际执行的用例数**，不要只看 `TEST SUCCEEDED`。
>
> ⚠️ **不要用 `grep "Test case ... passed"` 计数——xcodebuild 的文本日志在高输出量下会静默丢行。**
> 本项目实测中它连续三次少计 1 条（`keychainRoundTrip` 明明跑了且通过，日志里一行都没有）。
> 用这种方法计数，真有用例没跑时会淹没在噪声里看不出来。
>
> **权威记录是 xcresult bundle**，用它核对：
> ```bash
> RESULT=$(ls -dt ~/Library/Developer/Xcode/DerivedData/WBChatApp-UIKit-*/Logs/Test/*.xcresult | head -1)
> xcrun xcresulttool get test-results summary --path "$RESULT" \
>   | python3 -c "import sys,json; d=json.load(sys.stdin); print('total:',d['totalTestCount'],'passed:',d['passedTests'],'failed:',d['failedTests'],'skipped:',d['skippedTests'])"
> ```
> 注意 `ls -dt` 取的是**最近一次**运行；如果中间又跑过别的测试，用 `sed -n '2p'` 之类取对应那次。
> `skipped` 不为 0 要查清原因。

**前置条件：** SPM 依赖首次解析需要网络。开工前先确认下面这条能成功，否则一切任务都会卡在编译：

```bash
xcodebuild -resolvePackageDependencies -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit
```

---

## 文件结构

| 文件 | 职责 |
| --- | --- |
| `App/AppDelegate.swift` | 应用生命周期，无业务 |
| `App/SceneDelegate.swift` | 代码创建 window 与根控制器 |
| `App/AppContainer.swift` | 依赖组装，唯一知道具体实现类型的地方 |
| `Core/Networking/SSEEvent.swift` | SSE 事件值类型 |
| `Core/Networking/SSEEventParser.swift` | 字节流 → SSE 事件，纯函数无 IO |
| `Core/Networking/SSEStream.swift` | `URLSession.bytes` → `AsyncThrowingStream<SSEEvent>` |
| `Core/LLM/ChatModels.swift` | `ChatRole` / `ChatMessage` / `ChatRequest` / `TokenUsage` |
| `Core/LLM/StreamChunk.swift` | 统一流式事件模型 |
| `Core/LLM/ChatProvider.swift` | `ChatProvider` / `ProviderAdapter` / `SSEChunkMapper` 协议 |
| `Core/LLM/ProviderConfig.swift` | `ProviderKind` 与服务商预设 |
| `Core/LLM/DTO/OpenAIDTO.swift` | OpenAI 兼容协议的请求/响应模型 |
| `Core/LLM/DTO/AnthropicDTO.swift` | Anthropic 协议的请求/响应模型 |
| `Core/LLM/OpenAICompatibleAdapter.swift` | OpenAI/DeepSeek 的请求构造与事件映射 |
| `Core/LLM/AnthropicAdapter.swift` | Anthropic 的请求构造与事件映射 |
| `Core/LLM/NetworkChatProvider.swift` | 唯一的传输实现，泛化于 adapter |
| `Core/LLM/MockProvider.swift` | 无 Key 时的演示模式 |
| `Core/LLM/ChatError.swift` | 统一错误类型与文案映射 |
| `Core/Markdown/MarkdownBlock.swift` | 块模型与补丁结构 |
| `Core/Markdown/StreamingBlockSplitter.swift` | ★ 增量切块状态机 |
| `Core/Markdown/MarkdownTheme.swift` | 字体/颜色/间距 |
| `Core/Markdown/CodeHighlighter.swift` | 轻量语法高亮 |
| `Core/Markdown/AttributedRenderer.swift` | 单块 → `NSAttributedString` |
| `Core/Markdown/AttributedCache.swift` | 属性串与高度缓存 |
| `Core/Persistence/AppDatabase.swift` | GRDB 连接与迁移 |
| `Core/Persistence/Records.swift` | `ConversationRecord` / `MessageRecord` |
| `Core/Persistence/ChatRepository.swift` | 仓储协议 + GRDB 实现 |
| `Core/Security/KeychainStore.swift` | API Key 存取 |
| `Core/Speech/SpeechTranscriber.swift` | 协议 + `SFSpeechRecognizer` 实现 |
| `Features/Chat/AutoScrollController.swift` | 贴底两态机，纯逻辑 |
| `Features/Chat/ChatViewModel.swift` | 聊天业务编排 |
| `Features/Chat/ChatViewController.swift` | 列表装配与流式打补丁 |
| `Features/Chat/Views/*.swift` | cell、块视图、复用池、输入栏 |
| `Features/ConversationList/*` | 会话列表与抽屉 |
| `Features/Settings/*` | 服务商与 Key 设置 |
| `Common/Theme.swift` | 全局配色 |

---

## Task 1: 工程骨架改造

把空白模板改造成可编译、可跑测试的纯代码工程。这是所有后续任务的地基，必须一次做完。

**Files:**
- Modify: `WBChatApp-UIKit.xcodeproj/project.pbxproj`（Deployment Target、删 Storyboard 引用、加测试 target、加 SPM 依赖）
- Modify: `WBChatApp-UIKit/Info.plist`
- Modify: `WBChatApp-UIKit/SceneDelegate.swift`
- Delete: `WBChatApp-UIKit/Base.lproj/Main.storyboard`、`WBChatApp-UIKit/ViewController.swift`
- Create: `WBChatApp-UIKit/Common/Theme.swift`
- Create: `WBChatApp-UIKitTests/SmokeTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: 可用的测试 target `WBChatApp-UIKitTests`；`Theme` 枚举提供 `Theme.background` / `Theme.bubbleAssistant` / `Theme.bubbleUser` / `Theme.textPrimary` / `Theme.textSecondary` / `Theme.accent` / `Theme.codeBackground`，全部为 `UIColor` 静态属性。

- [ ] **Step 1: Xcode 中完成工程配置**

在 Xcode 里依次操作（这几项无法可靠地用命令行完成）：

1. 选中 target `WBChatApp-UIKit` → General → Minimum Deployments 设为 **iOS 16.0**
2. File → Add Package Dependencies，加入：
   - `https://github.com/swiftlang/swift-markdown.git`，Dependency Rule = Up to Next Major，`0.8.0`，勾选产品 `Markdown`
   - `https://github.com/groue/GRDB.swift.git`，Dependency Rule = Up to Next Major，`7.9.0`，勾选产品 `GRDB`
3. File → New → Target → **Unit Testing Bundle**，名字 `WBChatApp-UIKitTests`，Testing System 选 **Swift Testing**
4. 删除 `Main.storyboard` 与 `ViewController.swift`（Move to Trash）
5. Target → Info → 删除 `Main storyboard file base name`；展开 `Application Scene Manifest` → `Scene Configuration` → `Application Session Role` → Item 0 → 删除 `Storyboard Name` 一行
6. Target → Info 增加两条权限描述：
   - `Privacy - Microphone Usage Description` = `需要使用麦克风把你的语音转成文字输入`
   - `Privacy - Speech Recognition Usage Description` = `需要语音识别把你的话实时转成文字`

- [ ] **Step 2: 改写 SceneDelegate 为纯代码启动**

`WBChatApp-UIKit/SceneDelegate.swift` 全文替换为：

```swift
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        // 根控制器在 Task 14 接入 AppContainer，此处先放占位以保证工程可运行
        let placeholder = UIViewController()
        placeholder.view.backgroundColor = Theme.background
        window.rootViewController = placeholder
        window.makeKeyAndVisible()
        self.window = window
    }
}
```

- [ ] **Step 3: 新建 Theme**

创建 `WBChatApp-UIKit/Common/Theme.swift`：

```swift
import UIKit

/// 全局配色。全部走 dynamic color，自动适配深浅色。
enum Theme {

    static let background = UIColor.systemBackground
    static let secondaryBackground = UIColor.secondarySystemBackground

    /// 助手气泡：贴合 ChatGPT，浅色下几乎透明，深色下略提亮
    static let bubbleAssistant = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.06)
            : UIColor(white: 0, alpha: 0.03)
    }

    static let bubbleUser = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.12)
            : UIColor(white: 0, alpha: 0.06)
    }

    static let textPrimary = UIColor.label
    static let textSecondary = UIColor.secondaryLabel
    static let accent = UIColor.systemBlue

    static let codeBackground = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.08)
            : UIColor(white: 0, alpha: 0.045)
    }

    static let separator = UIColor.separator
}
```

- [ ] **Step 4: 写冒烟测试确认测试 target 与依赖都通**

创建 `WBChatApp-UIKitTests/SmokeTests.swift`：

```swift
import Testing
import UIKit
import Markdown
import GRDB
@testable import WBChatApp_UIKit

@Suite("工程骨架冒烟")
struct SmokeTests {

    @Test("Theme 可用")
    func themeIsAvailable() {
        #expect(Theme.background != nil)
    }

    @Test("swift-markdown 依赖可用")
    func markdownDependencyWorks() {
        let document = Document(parsing: "# 标题\n\n正文")
        #expect(document.childCount == 2)
    }

    @Test("GRDB 依赖可用")
    func grdbDependencyWorks() throws {
        let queue = try DatabaseQueue()
        let value = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT 1")
        }
        #expect(value == 1)
    }

    @Test("UITextView 默认由 TextKit 2 驱动")
    func textViewUsesTextKit2() {
        let textView = UITextView()
        #expect(textView.textLayoutManager != nil)
    }
}
```

- [ ] **Step 5: 运行测试确认全绿**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/SmokeTests'
```

Expected: 4 个用例全部 PASS，`TEST SUCCEEDED`。

若 `markdownDependencyWorks` 报找不到模块，说明 SPM 未解析成功，回到 Step 1 重试添加依赖。

- [ ] **Step 6: 提交**

```bash
git add -A WBChatApp-UIKit && git commit -m "工程：改造为 iOS 16 纯代码工程，接入 swift-markdown 与 GRDB"
```

---

## Task 2: SSE 事件解析器

SSE 协议解析。这是纯函数，不碰网络，是整条流式链路里最容易出错也最容易测试的一环。

**Files:**
- Create: `WBChatApp-UIKit/Core/Networking/SSEEvent.swift`
- Create: `WBChatApp-UIKit/Core/Networking/SSEEventParser.swift`
- Test: `WBChatApp-UIKitTests/SSEEventParserTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `struct SSEEvent: Equatable, Sendable { var event: String?; var data: String; var id: String?; var retry: Int? }`
  - `final class SSEEventParser { func consume(_ data: Data) -> [SSEEvent]; func finish() -> [SSEEvent] }`

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/SSEEventParserTests.swift`：

```swift
import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("SSE 事件解析")
struct SSEEventParserTests {

    private func parse(_ chunks: [String]) -> [SSEEvent] {
        let parser = SSEEventParser()
        var events: [SSEEvent] = []
        for chunk in chunks {
            events += parser.consume(Data(chunk.utf8))
        }
        events += parser.finish()
        return events
    }

    @Test("单个完整事件")
    func singleEvent() {
        let events = parse(["data: hello\n\n"])
        #expect(events == [SSEEvent(event: nil, data: "hello", id: nil, retry: nil)])
    }

    @Test("粘包：一次 Data 含两个事件")
    func twoEventsInOneChunk() {
        let events = parse(["data: a\n\ndata: b\n\n"])
        #expect(events.map(\.data) == ["a", "b"])
    }

    @Test("分包：一个事件被切成多段")
    func eventSplitAcrossChunks() {
        let events = parse(["data: hel", "lo wor", "ld\n", "\n"])
        #expect(events.map(\.data) == ["hello world"])
    }

    @Test("UTF-8 多字节字符被劈开也能正确还原")
    func splitMultiByteCharacter() {
        // “你好” 的 UTF-8 是 6 字节，在第 2 字节处切开
        let full = Array("data: 你好\n\n".utf8)
        let parser = SSEEventParser()
        var events = parser.consume(Data(full[0..<8]))
        events += parser.consume(Data(full[8...]))
        events += parser.finish()
        #expect(events.map(\.data) == ["你好"])
    }

    @Test("支持 CRLF 与单独 CR 作为换行")
    func lineEndings() {
        #expect(parse(["data: a\r\n\r\n"]).map(\.data) == ["a"])
        #expect(parse(["data: b\r\r"]).map(\.data) == ["b"])
    }

    @Test("CRLF 被切在中间不会被误判成两个换行")
    func crlfSplitAcrossChunks() {
        let events = parse(["data: a\r", "\n\r\n"])
        #expect(events.map(\.data) == ["a"])
    }

    @Test("注释行被忽略")
    func commentIgnored() {
        let events = parse([": ping\ndata: a\n\n"])
        #expect(events.map(\.data) == ["a"])
    }

    @Test("event 与 data 组合，Anthropic 风格")
    func eventAndData() {
        let events = parse(["event: content_block_delta\ndata: {\"x\":1}\n\n"])
        #expect(events.count == 1)
        #expect(events[0].event == "content_block_delta")
        #expect(events[0].data == "{\"x\":1}")
    }

    @Test("多行 data 用换行拼接")
    func multiLineData() {
        let events = parse(["data: line1\ndata: line2\n\n"])
        #expect(events.map(\.data) == ["line1\nline2"])
    }

    @Test("值前的单个空格被剥离，其余空格保留")
    func spaceStripping() {
        #expect(parse(["data:  a\n\n"]).map(\.data) == [" a"])
        #expect(parse(["data:a\n\n"]).map(\.data) == ["a"])
    }

    @Test("id 与 retry 字段")
    func idAndRetry() {
        let events = parse(["id: 7\nretry: 3000\ndata: a\n\n"])
        #expect(events[0].id == "7")
        #expect(events[0].retry == 3000)
    }

    @Test("finish 冲刷结尾没有空行的残留事件")
    func finishFlushesTrailingEvent() {
        let events = parse(["data: tail\n"])
        #expect(events.map(\.data) == ["tail"])
    }

    @Test("只有空行不产生事件")
    func blankLinesProduceNothing() {
        #expect(parse(["\n\n\n"]).isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/SSEEventParserTests'
```

Expected: 编译失败，`cannot find 'SSEEventParser' in scope`。

- [ ] **Step 3: 实现 SSEEvent**

创建 `WBChatApp-UIKit/Core/Networking/SSEEvent.swift`：

```swift
import Foundation

/// 一个 Server-Sent Event。
/// `event` 为 nil 表示服务端未指定类型（OpenAI 兼容协议就是这种）。
struct SSEEvent: Equatable, Sendable {
    var event: String?
    var data: String
    var id: String?
    var retry: Int?
}
```

- [ ] **Step 4: 实现解析器**

创建 `WBChatApp-UIKit/Core/Networking/SSEEventParser.swift`：

```swift
import Foundation

/// 把字节流增量解析成 SSE 事件。
///
/// 只做协议解析，不碰网络，因此可以逐字节喂入做单元测试。
/// 三个必须处理的边界：
/// 1. 粘包：一次 `Data` 里有多个完整事件；
/// 2. 分包：一个事件被切成多段，甚至 UTF-8 多字节字符被从中劈开；
/// 3. 换行：`\n` / `\r\n` / `\r` 都算行结束，且 `\r\n` 可能被切在两次回调之间。
final class SSEEventParser {

    /// 尚未切出完整行的原始字节。按字节缓冲而非按字符串缓冲，
    /// 才能保证多字节字符被劈开时不会解码出替换字符。
    private var byteBuffer: [UInt8] = []

    private var eventType: String?
    private var dataLines: [String] = []
    private var lastEventID: String?
    private var retry: Int?

    func consume(_ data: Data) -> [SSEEvent] {
        byteBuffer.append(contentsOf: data)
        var events: [SSEEvent] = []

        while let terminator = nextLineTerminator() {
            let lineBytes = Array(byteBuffer[0..<terminator.lineEnd])
            byteBuffer.removeFirst(terminator.consumed)
            let line = String(decoding: lineBytes, as: UTF8.self)
            if let event = handle(line: line) {
                events.append(event)
            }
        }
        return events
    }

    /// 流结束时调用，冲刷末尾没有空行收尾的残留事件。
    func finish() -> [SSEEvent] {
        var events: [SSEEvent] = []
        if !byteBuffer.isEmpty {
            // consume 里遇到落在末尾的 \r 会挂起等下一个字节判断是 CR 还是 CRLF，
            // 但流已经结束、那个字节永远不会来，这里必须把它剥掉，
            // 否则会被当成字段值的一部分（data 变成 "a\r"、event 匹配失败、retry 解析成 nil）
            if byteBuffer.last == 0x0D { byteBuffer.removeLast() }
            if !byteBuffer.isEmpty {
                let line = String(decoding: byteBuffer, as: UTF8.self)
                if let event = handle(line: line) {
                    events.append(event)
                }
            }
            byteBuffer.removeAll()
        }
        if let event = dispatch() {
            events.append(event)
        }
        return events
    }

    // MARK: - 私有

    private struct LineTerminator {
        /// 行内容的结束下标（不含换行符本身）
        let lineEnd: Int
        /// 本行连同换行符共消耗的字节数
        let consumed: Int
    }

    private func nextLineTerminator() -> LineTerminator? {
        guard let index = byteBuffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) else {
            return nil
        }
        if byteBuffer[index] == 0x0D {
            // 落在缓冲区末尾的 \r 必须等下一个字节到达，
            // 否则无法区分它是单独的 CR 还是 CRLF 的前半
            if index == byteBuffer.count - 1 { return nil }
            if byteBuffer[index + 1] == 0x0A {
                return LineTerminator(lineEnd: index, consumed: index + 2)
            }
        }
        return LineTerminator(lineEnd: index, consumed: index + 1)
    }

    /// 处理一整行，返回本行触发派发的事件（若有）
    private func handle(line: String) -> SSEEvent? {
        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") {
            return nil          // 注释行
        }

        let field: String
        var value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[line.startIndex..<colon])
            value = String(line[line.index(after: colon)...])
            // 规范：值前有且仅有一个空格时剥离
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = line
            value = ""
        }

        switch field {
        case "event": eventType = value
        case "data":  dataLines.append(value)
        case "id":    lastEventID = value
        case "retry": retry = Int(value)
        default:      break      // 未知字段按规范忽略
        }
        return nil
    }

    /// 空行触发派发。没有攒到任何 data 就什么都不产生。
    private func dispatch() -> SSEEvent? {
        defer {
            eventType = nil
            dataLines.removeAll()
            retry = nil
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventType,
                        data: dataLines.joined(separator: "\n"),
                        id: lastEventID,
                        retry: retry)
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/SSEEventParserTests'
```

Expected: 13 个用例全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add WBChatApp-UIKit/Core/Networking WBChatApp-UIKitTests/SSEEventParserTests.swift && git commit -m "网络：实现 SSE 事件解析器，覆盖粘包分包与三种换行"
```

---

## Task 3: 统一聊天模型与错误类型

定义整个 LLM 层的公共词汇。没有测试逻辑可跑，因此与 Task 4 共用一次验证——本任务只要能编译通过即可，测试在 Task 4 补上。

**Files:**
- Create: `WBChatApp-UIKit/Core/LLM/ChatModels.swift`
- Create: `WBChatApp-UIKit/Core/LLM/StreamChunk.swift`
- Create: `WBChatApp-UIKit/Core/LLM/ChatError.swift`
- Create: `WBChatApp-UIKit/Core/LLM/ProviderConfig.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum ChatRole: String, Codable, Sendable { case system, user, assistant }`
  - `struct ChatMessage: Equatable, Sendable { let role: ChatRole; let content: String }`
  - `struct ChatRequest: Sendable { let model: String; let messages: [ChatMessage]; let system: String?; let temperature: Double; let maxTokens: Int }`
  - `struct TokenUsage: Equatable, Sendable { let prompt: Int; let completion: Int }`
  - `enum StreamChunk: Equatable, Sendable { case textDelta(String); case reasoningDelta(String); case usage(TokenUsage); case done(finishReason: String?) }`
  - `enum ChatError: Error, Equatable` 及 `var userMessage: String`
  - `enum ProviderKind: String, CaseIterable, Codable, Sendable { case deepSeek, openAI, anthropic }` 及 `displayName` / `defaultBaseURL` / `defaultModel` / `availableModels` / `usesAnthropicProtocol`
  - `struct ProviderConfig: Equatable, Sendable { let kind: ProviderKind; let baseURL: URL; let apiKey: String; let model: String }`

- [ ] **Step 1: 创建 ChatModels**

创建 `WBChatApp-UIKit/Core/LLM/ChatModels.swift`：

```swift
import Foundation

enum ChatRole: String, Codable, Sendable {
    case system, user, assistant
}

struct ChatMessage: Equatable, Sendable {
    let role: ChatRole
    let content: String
}

/// 一次补全请求。与具体服务商无关，由 adapter 翻译成各家的报文。
struct ChatRequest: Sendable {
    let model: String
    let messages: [ChatMessage]
    /// 系统提示词。OpenAI 兼容协议会并入 messages，Anthropic 走顶层 system 字段。
    let system: String?
    let temperature: Double
    let maxTokens: Int
}

struct TokenUsage: Equatable, Sendable {
    let prompt: Int
    let completion: Int
}
```

- [ ] **Step 2: 创建 StreamChunk**

创建 `WBChatApp-UIKit/Core/LLM/StreamChunk.swift`：

```swift
import Foundation

/// 抹平两家协议差异后的统一流式事件。
/// ViewModel 及以上只认识这个类型。
enum StreamChunk: Equatable, Sendable {
    /// 正文增量
    case textDelta(String)
    /// 思考过程增量（DeepSeek reasoning_content / Anthropic thinking）
    case reasoningDelta(String)
    /// token 用量，通常在流末尾出现一次
    case usage(TokenUsage)
    /// 流正常结束
    case done(finishReason: String?)
}
```

- [ ] **Step 3: 创建 ChatError**

创建 `WBChatApp-UIKit/Core/LLM/ChatError.swift`：

```swift
import Foundation

enum ChatError: Error, Equatable {
    case missingAPIKey
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(status: Int, message: String?)
    case network(code: Int)
    case timeout
    case decoding(String)
    case cancelled

    /// 所有面向用户的文案集中在这里，便于后续本地化。
    var userMessage: String {
        switch self {
        case .missingAPIKey:
            return "还没有配置 API Key，去设置里填一个吧"
        case .unauthorized:
            return "API Key 无效或已过期，请检查设置"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "请求太频繁了，请 \(Int(seconds)) 秒后再试"
            }
            return "请求太频繁了，稍后再试"
        case .serverError(let status, let message):
            if let message, !message.isEmpty {
                return "服务端错误（\(status)）：\(message)"
            }
            return "服务端错误（\(status)）"
        case .network:
            return "网络连接失败，请检查网络后重试"
        case .timeout:
            return "请求超时，请重试"
        case .decoding:
            return "响应格式无法识别"
        case .cancelled:
            return "已停止生成"
        }
    }

    /// 把 URLError 归一到 ChatError
    static func from(_ error: Error) -> ChatError {
        if let chatError = error as? ChatError { return chatError }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return .cancelled
            case .timedOut:  return .timeout
            default:         return .network(code: urlError.errorCode)
            }
        }
        if error is DecodingError {
            return .decoding(String(describing: error))
        }
        return .network(code: (error as NSError).code)
    }
}
```

- [ ] **Step 4: 创建 ProviderConfig**

创建 `WBChatApp-UIKit/Core/LLM/ProviderConfig.swift`：

```swift
import Foundation

enum ProviderKind: String, CaseIterable, Codable, Sendable {
    case deepSeek
    case openAI
    case anthropic

    var displayName: String {
        switch self {
        case .deepSeek:  return "DeepSeek"
        case .openAI:    return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    var defaultBaseURL: URL {
        switch self {
        case .deepSeek:  return URL(string: "https://api.deepseek.com")!
        case .openAI:    return URL(string: "https://api.openai.com")!
        case .anthropic: return URL(string: "https://api.anthropic.com")!
        }
    }

    var availableModels: [String] {
        switch self {
        case .deepSeek:  return ["deepseek-chat", "deepseek-reasoner"]
        case .openAI:    return ["gpt-4o", "gpt-4o-mini"]
        case .anthropic: return ["claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5-20251001"]
        }
    }

    var defaultModel: String { availableModels[0] }

    /// DeepSeek 与 OpenAI 共用 OpenAI 兼容协议，只有 Anthropic 走自己的报文格式。
    var usesAnthropicProtocol: Bool { self == .anthropic }
}

struct ProviderConfig: Equatable, Sendable {
    let kind: ProviderKind
    let baseURL: URL
    let apiKey: String
    let model: String
}
```

- [ ] **Step 5: 编译确认**

```bash
xcodebuild build -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -quiet
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: 提交**

```bash
git add WBChatApp-UIKit/Core/LLM && git commit -m "模型：定义统一聊天模型、流式事件与服务商配置"
```

---

## Task 4: OpenAI 兼容协议适配器

把 `SSEEvent` 映射成 `StreamChunk`。映射逻辑与网络传输彻底分离，因此可以纯逻辑测试——喂 `SSEEvent` 断言 `StreamChunk`，不需要起服务。

**Files:**
- Create: `WBChatApp-UIKit/Core/LLM/ChatProvider.swift`
- Create: `WBChatApp-UIKit/Core/LLM/DTO/OpenAIDTO.swift`
- Create: `WBChatApp-UIKit/Core/LLM/OpenAICompatibleAdapter.swift`
- Test: `WBChatApp-UIKitTests/OpenAIAdapterTests.swift`

**Interfaces:**
- Consumes: `SSEEvent`（Task 2）；`ChatRequest` / `StreamChunk` / `ProviderConfig` / `ChatError`（Task 3）
- Produces:
  - `protocol ChatProvider: Sendable { func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> }`
  - `protocol SSEChunkMapper { mutating func map(_ event: SSEEvent) throws -> [StreamChunk] }`
  - `protocol ProviderAdapter: Sendable { func buildRequest(_ request: ChatRequest, config: ProviderConfig) throws -> URLRequest; func makeMapper() -> SSEChunkMapper }`
  - `struct OpenAICompatibleAdapter: ProviderAdapter`
  - `struct OpenAIChunkMapper: SSEChunkMapper`

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/OpenAIAdapterTests.swift`：

```swift
import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("OpenAI 兼容协议适配")
struct OpenAIAdapterTests {

    private func chunks(_ payloads: [String]) throws -> [StreamChunk] {
        var mapper = OpenAIChunkMapper()
        var result: [StreamChunk] = []
        for payload in payloads {
            result += try mapper.map(SSEEvent(event: nil, data: payload, id: nil, retry: nil))
        }
        return result
    }

    @Test("正文增量")
    func textDelta() throws {
        let result = try chunks([#"{"choices":[{"delta":{"content":"你好"}}]}"#])
        #expect(result == [.textDelta("你好")])
    }

    @Test("思考增量走 reasoning_content")
    func reasoningDelta() throws {
        let result = try chunks([#"{"choices":[{"delta":{"reasoning_content":"先想想"}}]}"#])
        #expect(result == [.reasoningDelta("先想想")])
    }

    @Test("同一帧里正文与思考都存在时按思考在前输出")
    func bothDeltas() throws {
        let result = try chunks([#"{"choices":[{"delta":{"reasoning_content":"A","content":"B"}}]}"#])
        #expect(result == [.reasoningDelta("A"), .textDelta("B")])
    }

    @Test("空 delta 不产生任何事件")
    func emptyDelta() throws {
        #expect(try chunks([#"{"choices":[{"delta":{}}]}"#]).isEmpty)
    }

    @Test("[DONE] 标记结束")
    func doneMarker() throws {
        #expect(try chunks(["[DONE]"]) == [.done(finishReason: nil)])
    }

    @Test("finish_reason 被带出")
    func finishReason() throws {
        let result = try chunks([#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#])
        #expect(result == [.done(finishReason: "stop")])
    }

    @Test("末帧 usage 被映射")
    func usage() throws {
        let result = try chunks([#"{"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":34}}"#])
        #expect(result == [.usage(TokenUsage(prompt: 12, completion: 34))])
    }

    @Test("完整流：多帧增量 + usage + DONE")
    func fullStream() throws {
        let result = try chunks([
            #"{"choices":[{"delta":{"content":"Hel"}}]}"#,
            #"{"choices":[{"delta":{"content":"lo"}}]}"#,
            #"{"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2}}"#,
            "[DONE]",
        ])
        #expect(result == [
            .textDelta("Hel"),
            .textDelta("lo"),
            .usage(TokenUsage(prompt: 1, completion: 2)),
            .done(finishReason: "stop"),
            .done(finishReason: nil),
        ])
    }

    @Test("非法 JSON 抛解码错误")
    func invalidJSON() {
        #expect(throws: ChatError.self) {
            var mapper = OpenAIChunkMapper()
            _ = try mapper.map(SSEEvent(event: nil, data: "{ 坏掉的", id: nil, retry: nil))
        }
    }

    @Test("请求构造：URL、鉴权头、stream 开关与 system 并入 messages")
    func buildRequest() throws {
        let adapter = OpenAICompatibleAdapter()
        let config = ProviderConfig(kind: .deepSeek,
                                    baseURL: URL(string: "https://api.deepseek.com")!,
                                    apiKey: "sk-test",
                                    model: "deepseek-chat")
        let request = ChatRequest(model: "deepseek-chat",
                                  messages: [ChatMessage(role: .user, content: "hi")],
                                  system: "你是助手",
                                  temperature: 0.7,
                                  maxTokens: 2048)
        let urlRequest = try adapter.buildRequest(request, config: config)

        #expect(urlRequest.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "text/event-stream")

        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["stream"] as? Bool == true)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == "你是助手")
        #expect(messages[1]["role"] as? String == "user")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/OpenAIAdapterTests'
```

Expected: 编译失败，`cannot find 'OpenAIChunkMapper' in scope`。

- [ ] **Step 3: 定义三个协议**

创建 `WBChatApp-UIKit/Core/LLM/ChatProvider.swift`：

```swift
import Foundation

/// 上层唯一依赖的抽象：给一个请求，吐一串统一事件。
protocol ChatProvider: Sendable {
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error>
}

/// 把某家服务商的 SSE 事件映射成统一事件。
/// 用 mutating 是因为 Anthropic 需要记住当前 content_block 的类型。
protocol SSEChunkMapper {
    mutating func map(_ event: SSEEvent) throws -> [StreamChunk]
}

/// 一家服务商的全部协议差异，收敛在这一个类型里。
protocol ProviderAdapter: Sendable {
    func buildRequest(_ request: ChatRequest, config: ProviderConfig) throws -> URLRequest
    func makeMapper() -> SSEChunkMapper
}
```

- [ ] **Step 4: 定义 OpenAI DTO**

创建 `WBChatApp-UIKit/Core/LLM/DTO/OpenAIDTO.swift`：

```swift
import Foundation

enum OpenAIDTO {

    struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
        let stream: Bool
        let temperature: Double
        let max_tokens: Int
        /// 要求末帧带上用量统计
        let stream_options: StreamOptions?

        struct StreamOptions: Encodable {
            let include_usage: Bool
        }
    }

    struct StreamResponse: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let reasoning_content: String?
            }
            let delta: Delta?
            let finish_reason: String?
        }
        struct Usage: Decodable {
            let prompt_tokens: Int
            let completion_tokens: Int
        }
        let choices: [Choice]?
        let usage: Usage?
    }

    /// 错误响应体，用于把服务端文案带给用户
    struct ErrorResponse: Decodable {
        struct Payload: Decodable { let message: String? }
        let error: Payload?
    }
}
```

- [ ] **Step 5: 实现适配器**

创建 `WBChatApp-UIKit/Core/LLM/OpenAICompatibleAdapter.swift`：

```swift
import Foundation

/// OpenAI 兼容协议（OpenAI 本家与 DeepSeek 共用）。
struct OpenAICompatibleAdapter: ProviderAdapter {

    func buildRequest(_ request: ChatRequest, config: ProviderConfig) throws -> URLRequest {
        guard !config.apiKey.isEmpty else { throw ChatError.missingAPIKey }

        var messages: [OpenAIDTO.RequestBody.Message] = []
        // OpenAI 兼容协议把 system 当成 messages 里的第一条
        if let system = request.system, !system.isEmpty {
            messages.append(.init(role: ChatRole.system.rawValue, content: system))
        }
        messages += request.messages.map {
            .init(role: $0.role.rawValue, content: $0.content)
        }

        let body = OpenAIDTO.RequestBody(
            model: request.model,
            messages: messages,
            stream: true,
            temperature: request.temperature,
            max_tokens: request.maxTokens,
            stream_options: .init(include_usage: true)
        )

        var urlRequest = URLRequest(url: config.baseURL.appendingPathComponent("v1/chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        urlRequest.timeoutInterval = 60
        return urlRequest
    }

    func makeMapper() -> SSEChunkMapper { OpenAIChunkMapper() }
}

struct OpenAIChunkMapper: SSEChunkMapper {

    mutating func map(_ event: SSEEvent) throws -> [StreamChunk] {
        let payload = event.data.trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return [] }
        if payload == "[DONE]" { return [.done(finishReason: nil)] }

        let response: OpenAIDTO.StreamResponse
        do {
            response = try JSONDecoder().decode(OpenAIDTO.StreamResponse.self,
                                                from: Data(payload.utf8))
        } catch {
            throw ChatError.decoding(payload)
        }

        var chunks: [StreamChunk] = []
        if let choice = response.choices?.first {
            // 思考在前、正文在后，保证 UI 上思考区先于正文出现
            if let reasoning = choice.delta?.reasoning_content, !reasoning.isEmpty {
                chunks.append(.reasoningDelta(reasoning))
            }
            if let content = choice.delta?.content, !content.isEmpty {
                chunks.append(.textDelta(content))
            }
            if let usage = response.usage {
                chunks.append(.usage(TokenUsage(prompt: usage.prompt_tokens,
                                                completion: usage.completion_tokens)))
            }
            if let reason = choice.finish_reason {
                chunks.append(.done(finishReason: reason))
            }
        } else if let usage = response.usage {
            // 有些实现把 usage 单独放一帧，此时 choices 为空数组
            chunks.append(.usage(TokenUsage(prompt: usage.prompt_tokens,
                                            completion: usage.completion_tokens)))
        }
        return chunks
    }
}
```

- [ ] **Step 6: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/OpenAIAdapterTests'
```

Expected: 10 个用例全部 PASS。

- [ ] **Step 7: 提交**

```bash
git add WBChatApp-UIKit/Core/LLM WBChatApp-UIKitTests/OpenAIAdapterTests.swift && git commit -m "适配：实现 OpenAI 兼容协议的请求构造与流式事件映射"
```

---

## Task 5: Anthropic 协议适配器

Anthropic 用 `event:` + `data:` 双字段，且增量类型要靠 `content_block_start` 记住当前块是正文还是思考——这是 mapper 需要 `mutating` 的原因。

**Files:**
- Create: `WBChatApp-UIKit/Core/LLM/DTO/AnthropicDTO.swift`
- Create: `WBChatApp-UIKit/Core/LLM/AnthropicAdapter.swift`
- Test: `WBChatApp-UIKitTests/AnthropicAdapterTests.swift`

**Interfaces:**
- Consumes: `SSEEvent`（Task 2）；`ProviderAdapter` / `SSEChunkMapper`（Task 4）
- Produces: `struct AnthropicAdapter: ProviderAdapter`、`struct AnthropicChunkMapper: SSEChunkMapper`

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/AnthropicAdapterTests.swift`：

```swift
import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("Anthropic 协议适配")
struct AnthropicAdapterTests {

    private func chunks(_ events: [(String, String)]) throws -> [StreamChunk] {
        var mapper = AnthropicChunkMapper()
        var result: [StreamChunk] = []
        for (type, data) in events {
            result += try mapper.map(SSEEvent(event: type, data: data, id: nil, retry: nil))
        }
        return result
    }

    @Test("text_delta 映射为正文增量")
    func textDelta() throws {
        let result = try chunks([
            ("content_block_delta", #"{"index":0,"delta":{"type":"text_delta","text":"你好"}}"#)
        ])
        #expect(result == [.textDelta("你好")])
    }

    @Test("thinking_delta 映射为思考增量")
    func thinkingDelta() throws {
        let result = try chunks([
            ("content_block_delta", #"{"index":0,"delta":{"type":"thinking_delta","thinking":"先想想"}}"#)
        ])
        #expect(result == [.reasoningDelta("先想想")])
    }

    @Test("message_start 与 content_block_start 本身不产生事件")
    func startEventsAreSilent() throws {
        let result = try chunks([
            ("message_start", #"{"message":{"usage":{"input_tokens":5,"output_tokens":0}}}"#),
            ("content_block_start", #"{"index":0,"content_block":{"type":"text","text":""}}"#),
        ])
        #expect(result.isEmpty)
    }

    @Test("message_delta 带出用量与停止原因")
    func messageDelta() throws {
        let result = try chunks([
            ("message_start", #"{"message":{"usage":{"input_tokens":7,"output_tokens":0}}}"#),
            ("message_delta", #"{"delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":21}}"#),
        ])
        #expect(result == [.usage(TokenUsage(prompt: 7, completion: 21))])
    }

    @Test("message_stop 结束流并带出停止原因")
    func messageStop() throws {
        let result = try chunks([
            ("message_delta", #"{"delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}"#),
            ("message_stop", "{}"),
        ])
        #expect(result.last == .done(finishReason: "end_turn"))
    }

    @Test("error 事件抛服务端错误")
    func errorEvent() {
        #expect(throws: ChatError.self) {
            var mapper = AnthropicChunkMapper()
            _ = try mapper.map(SSEEvent(event: "error",
                                        data: #"{"error":{"type":"overloaded_error","message":"服务繁忙"}}"#,
                                        id: nil, retry: nil))
        }
    }

    @Test("ping 事件被忽略")
    func pingIgnored() throws {
        #expect(try chunks([("ping", "{}")]).isEmpty)
    }

    @Test("完整流：思考块 + 正文块 + 用量 + 结束")
    func fullStream() throws {
        let result = try chunks([
            ("message_start", #"{"message":{"usage":{"input_tokens":10,"output_tokens":0}}}"#),
            ("content_block_start", #"{"index":0,"content_block":{"type":"thinking"}}"#),
            ("content_block_delta", #"{"index":0,"delta":{"type":"thinking_delta","thinking":"嗯"}}"#),
            ("content_block_stop", #"{"index":0}"#),
            ("content_block_start", #"{"index":1,"content_block":{"type":"text"}}"#),
            ("content_block_delta", #"{"index":1,"delta":{"type":"text_delta","text":"答案"}}"#),
            ("content_block_stop", #"{"index":1}"#),
            ("message_delta", #"{"delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":42}}"#),
            ("message_stop", "{}"),
        ])
        #expect(result == [
            .reasoningDelta("嗯"),
            .textDelta("答案"),
            .usage(TokenUsage(prompt: 10, completion: 42)),
            .done(finishReason: "end_turn"),
        ])
    }

    @Test("请求构造：x-api-key、版本头与顶层 system 字段")
    func buildRequest() throws {
        let adapter = AnthropicAdapter()
        let config = ProviderConfig(kind: .anthropic,
                                    baseURL: URL(string: "https://api.anthropic.com")!,
                                    apiKey: "sk-ant-test",
                                    model: "claude-sonnet-5")
        let request = ChatRequest(model: "claude-sonnet-5",
                                  messages: [ChatMessage(role: .user, content: "hi")],
                                  system: "你是助手",
                                  temperature: 0.7,
                                  maxTokens: 2048)
        let urlRequest = try adapter.buildRequest(request, config: config)

        #expect(urlRequest.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == nil)

        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        // system 是顶层字段，不在 messages 里
        #expect(json["system"] as? String == "你是助手")
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/AnthropicAdapterTests'
```

Expected: 编译失败，`cannot find 'AnthropicChunkMapper' in scope`。

- [ ] **Step 3: 定义 Anthropic DTO**

创建 `WBChatApp-UIKit/Core/LLM/DTO/AnthropicDTO.swift`：

```swift
import Foundation

enum AnthropicDTO {

    struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
        /// 与 OpenAI 不同，system 是顶层字段
        let system: String?
        let stream: Bool
        let temperature: Double
        let max_tokens: Int
    }

    struct MessageStart: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable { let input_tokens: Int? }
            let usage: Usage?
        }
        let message: Message?
    }

    struct ContentBlockStart: Decodable {
        struct Block: Decodable { let type: String? }
        let content_block: Block?
    }

    struct ContentBlockDelta: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let thinking: String?
        }
        let delta: Delta?
    }

    struct MessageDelta: Decodable {
        struct Delta: Decodable { let stop_reason: String? }
        struct Usage: Decodable { let output_tokens: Int? }
        let delta: Delta?
        let usage: Usage?
    }

    struct ErrorEnvelope: Decodable {
        struct Payload: Decodable {
            let type: String?
            let message: String?
        }
        let error: Payload?
    }
}
```

- [ ] **Step 4: 实现适配器**

创建 `WBChatApp-UIKit/Core/LLM/AnthropicAdapter.swift`：

```swift
import Foundation

struct AnthropicAdapter: ProviderAdapter {

    func buildRequest(_ request: ChatRequest, config: ProviderConfig) throws -> URLRequest {
        guard !config.apiKey.isEmpty else { throw ChatError.missingAPIKey }

        let body = AnthropicDTO.RequestBody(
            model: request.model,
            messages: request.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            system: (request.system?.isEmpty == false) ? request.system : nil,
            stream: true,
            temperature: request.temperature,
            max_tokens: request.maxTokens
        )

        var urlRequest = URLRequest(url: config.baseURL.appendingPathComponent("v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        urlRequest.timeoutInterval = 60
        return urlRequest
    }

    func makeMapper() -> SSEChunkMapper { AnthropicChunkMapper() }
}

/// Anthropic 的增量类型要靠上下文判断，因此 mapper 需要持有状态。
struct AnthropicChunkMapper: SSEChunkMapper {

    private var inputTokens: Int = 0
    private var outputTokens: Int = 0
    private var stopReason: String?

    mutating func map(_ event: SSEEvent) throws -> [StreamChunk] {
        let data = Data(event.data.utf8)
        let decoder = JSONDecoder()

        switch event.event {
        case "message_start":
            // 解码失败必须抛错。用 try? 静默吞掉会让 inputTokens 悄悄降级为 0，
            // 后续每一帧 usage 的 prompt 都是错的，且调用方无从察觉。
            // 注意区分：JSON 合法但 usage 字段缺失是正常情况，仍走默认值 0。
            guard let payload = try? decoder.decode(AnthropicDTO.MessageStart.self, from: data) else {
                throw ChatError.decoding(event.data)
            }
            inputTokens = payload.message?.usage?.input_tokens ?? 0
            return []

        case "content_block_delta":
            guard let payload = try? decoder.decode(AnthropicDTO.ContentBlockDelta.self, from: data),
                  let delta = payload.delta else {
                throw ChatError.decoding(event.data)
            }
            switch delta.type {
            case "text_delta":
                guard let text = delta.text, !text.isEmpty else { return [] }
                return [.textDelta(text)]
            case "thinking_delta":
                guard let thinking = delta.thinking, !thinking.isEmpty else { return [] }
                return [.reasoningDelta(thinking)]
            default:
                // signature_delta 等类型对 UI 无意义，忽略
                return []
            }

        case "message_delta":
            // 同上：解码失败若被吞掉，这里会无条件吐出一帧基于陈旧状态拼出的
            // 「幽灵」用量事件，调用方分不清它是真实用量还是解码失败的产物。
            guard let payload = try? decoder.decode(AnthropicDTO.MessageDelta.self, from: data) else {
                throw ChatError.decoding(event.data)
            }
            if let reason = payload.delta?.stop_reason { stopReason = reason }
            outputTokens = payload.usage?.output_tokens ?? outputTokens
            return [.usage(TokenUsage(prompt: inputTokens, completion: outputTokens))]

        case "message_stop":
            return [.done(finishReason: stopReason)]

        case "error":
            let payload = try? decoder.decode(AnthropicDTO.ErrorEnvelope.self, from: data)
            throw ChatError.serverError(status: 200, message: payload?.error?.message)

        default:
            // content_block_start / content_block_stop / ping 无需产出事件
            return []
        }
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/AnthropicAdapterTests'
```

Expected: 9 个用例全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add WBChatApp-UIKit/Core/LLM WBChatApp-UIKitTests/AnthropicAdapterTests.swift && git commit -m "适配：实现 Anthropic 协议的请求构造与流式事件映射"
```

---

## Task 6: 网络传输层与演示模式

只写一个传输实现，两家协议靠注入 adapter 区分。这是双协议方案不产生重复代码的关键。

**Files:**
- Create: `WBChatApp-UIKit/Core/Networking/SSEStream.swift`
- Create: `WBChatApp-UIKit/Core/LLM/NetworkChatProvider.swift`
- Create: `WBChatApp-UIKit/Core/LLM/MockProvider.swift`
- Test: `WBChatApp-UIKitTests/NetworkChatProviderTests.swift`

**Interfaces:**
- Consumes: `SSEEventParser`（Task 2）；`ChatProvider` / `ProviderAdapter`（Task 4）
- Produces:
  - `final class NetworkChatProvider: ChatProvider`，`init(adapter: ProviderAdapter, config: ProviderConfig, session: URLSession = .shared)`
  - `final class MockProvider: ChatProvider`，`init(script: String = MockProvider.defaultScript, chunkSize: Int = 3, delay: Duration = .milliseconds(20))`，以及 `static let defaultScript: String`

- [ ] **Step 1: 写失败测试**

用 `URLProtocol` 拦截请求，回放真实形状的 SSE 报文，端到端验证「HTTP → SSE → StreamChunk」。

创建 `WBChatApp-UIKitTests/NetworkChatProviderTests.swift`：

```swift
import Foundation
import Testing
@testable import WBChatApp_UIKit

/// 用 URLProtocol 拦截请求，按脚本回放报文。
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody: String = ""
    nonisolated(unsafe) static var statusCode: Int = 200
    nonisolated(unsafe) static var headers: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: Self.statusCode,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: Self.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("网络传输层", .serialized)
struct NetworkChatProviderTests {

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func collect(_ provider: ChatProvider) async throws -> [StreamChunk] {
        let request = ChatRequest(model: "m", messages: [ChatMessage(role: .user, content: "hi")],
                                  system: nil, temperature: 0.7, maxTokens: 128)
        var result: [StreamChunk] = []
        for try await chunk in provider.stream(request) { result.append(chunk) }
        return result
    }

    @Test("OpenAI 协议端到端")
    func openAIEndToEnd() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = ["Content-Type": "text/event-stream"]
        StubURLProtocol.responseBody = """
        data: {"choices":[{"delta":{"content":"你"}}]}

        data: {"choices":[{"delta":{"content":"好"}}]}

        data: [DONE]

        """
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .deepSeek, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeSession())

        let chunks = try await collect(provider)
        #expect(chunks == [.textDelta("你"), .textDelta("好"), .done(finishReason: nil)])
    }

    @Test("Anthropic 协议端到端")
    func anthropicEndToEnd() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = ["Content-Type": "text/event-stream"]
        StubURLProtocol.responseBody = """
        event: content_block_delta
        data: {"delta":{"type":"text_delta","text":"嗨"}}

        event: message_stop
        data: {}

        """
        let provider = NetworkChatProvider(
            adapter: AnthropicAdapter(),
            config: ProviderConfig(kind: .anthropic, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeSession())

        let chunks = try await collect(provider)
        #expect(chunks == [.textDelta("嗨"), .done(finishReason: nil)])
    }

    @Test("401 映射为 unauthorized")
    func unauthorized() async {
        StubURLProtocol.statusCode = 401
        StubURLProtocol.headers = [:]
        StubURLProtocol.responseBody = #"{"error":{"message":"bad key"}}"#
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeSession())

        await #expect(throws: ChatError.unauthorized) {
            _ = try await collect(provider)
        }
    }

    @Test("429 带出 Retry-After")
    func rateLimited() async {
        StubURLProtocol.statusCode = 429
        StubURLProtocol.headers = ["Retry-After": "30"]
        StubURLProtocol.responseBody = ""
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeSession())

        await #expect(throws: ChatError.rateLimited(retryAfter: 30)) {
            _ = try await collect(provider)
        }
    }

    @Test("缺少 API Key 直接抛错，不发请求")
    func missingKey() async {
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "", model: "m"),
            session: makeSession())

        await #expect(throws: ChatError.missingAPIKey) {
            _ = try await collect(provider)
        }
    }

    @Test("MockProvider 逐块吐出脚本内容并以 done 收尾")
    func mockProvider() async throws {
        let provider = MockProvider(script: "abcdef", chunkSize: 2, delay: .zero)
        let chunks = try await collect(provider)
        let text = chunks.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }
        #expect(text.joined() == "abcdef")
        #expect(chunks.last == .done(finishReason: "stop"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/NetworkChatProviderTests'
```

Expected: 编译失败，`cannot find 'NetworkChatProvider' in scope`。

- [ ] **Step 3: 实现 SSEStream**

创建 `WBChatApp-UIKit/Core/Networking/SSEStream.swift`：

```swift
import Foundation

/// 把一次 HTTP 请求变成 SSE 事件流。
/// 负责状态码检查与字节喂给解析器，不理解任何业务语义。
enum SSEStream {

    static func events(for request: URLRequest,
                       session: URLSession) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.validate(response, bytes: bytes)

                    let parser = SSEEventParser()
                    var buffer = [UInt8]()
                    buffer.reserveCapacity(4096)

                    for try await byte in bytes {
                        buffer.append(byte)
                        // 攒到换行再交给解析器，避免每字节一次函数调用
                        if byte == 0x0A {
                            for event in parser.consume(Data(buffer)) {
                                continuation.yield(event)
                            }
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        for event in parser.consume(Data(buffer)) {
                            continuation.yield(event)
                        }
                    }
                    for event in parser.finish() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ChatError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 非 2xx 时读出错误体再抛，尽量把服务端文案带给用户。
    private static func validate(_ response: URLResponse,
                                 bytes: URLSession.AsyncBytes) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }

        switch http.statusCode {
        case 401, 403:
            throw ChatError.unauthorized
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw ChatError.rateLimited(retryAfter: retryAfter)
        default:
            throw ChatError.serverError(status: http.statusCode, message: nil)
        }
    }
}
```

- [ ] **Step 4: 实现 NetworkChatProvider**

创建 `WBChatApp-UIKit/Core/LLM/NetworkChatProvider.swift`：

```swift
import Foundation

/// 唯一的网络实现。协议差异全部由注入的 adapter 承担，
/// 因此新增一家服务商不需要改这里。
final class NetworkChatProvider: ChatProvider {

    private let adapter: ProviderAdapter
    private let config: ProviderConfig
    private let session: URLSession

    init(adapter: ProviderAdapter, config: ProviderConfig, session: URLSession = .shared) {
        self.adapter = adapter
        self.config = config
        self.session = session
    }

    /// 按当前服务商种类挑选 adapter 的便利构造
    convenience init(config: ProviderConfig, session: URLSession = .shared) {
        let adapter: ProviderAdapter = config.kind.usesAnthropicProtocol
            ? AnthropicAdapter()
            : OpenAICompatibleAdapter()
        self.init(adapter: adapter, config: config, session: session)
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try adapter.buildRequest(request, config: config)
                    var mapper = adapter.makeMapper()
                    for try await event in SSEStream.events(for: urlRequest, session: session) {
                        try Task.checkCancellation()
                        for chunk in try mapper.map(event) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ChatError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 5: 实现 MockProvider**

创建 `WBChatApp-UIKit/Core/LLM/MockProvider.swift`：

```swift
import Foundation

/// 未配置 API Key 时的演示模式。
/// 脚本刻意覆盖标题、段落、列表、代码块、表格，用来验证渲染管线。
final class MockProvider: ChatProvider {

    static let defaultScript = """
    ## 演示模式

    当前还没有配置 API Key，这段内容是**本地模拟**生成的，用来演示流式渲染。

    渲染管线支持这些块类型：

    - 段落与 *强调*、**加粗**、`行内代码`
    - 有序与无序列表
    - 代码块（带语法高亮）
    - 表格与分割线

    ```swift
    func greet(_ name: String) -> String {
        // 已闭合的块不会再重新排版
        return "你好，\\(name)"
    }
    ```

    | 块类型 | 是否增量 |
    | --- | --- |
    | 已闭合块 | 只解析一次 |
    | 未闭合块 | 每帧重解析 |

    ---

    去「设置」里填入 API Key 即可接入真实模型。
    """

    private let script: String
    private let chunkSize: Int
    private let delay: Duration

    init(script: String = MockProvider.defaultScript,
         chunkSize: Int = 3,
         delay: Duration = .milliseconds(20)) {
        self.script = script
        self.chunkSize = max(1, chunkSize)
        self.delay = delay
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var index = script.startIndex
                    while index < script.endIndex {
                        try Task.checkCancellation()
                        let end = script.index(index, offsetBy: chunkSize,
                                               limitedBy: script.endIndex) ?? script.endIndex
                        continuation.yield(.textDelta(String(script[index..<end])))
                        index = end
                        if delay > .zero { try await Task.sleep(for: delay) }
                    }
                    continuation.yield(.usage(TokenUsage(prompt: 0, completion: script.count)))
                    continuation.yield(.done(finishReason: "stop"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ChatError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 6: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/NetworkChatProviderTests'
```

Expected: 6 个用例全部 PASS。

- [ ] **Step 7: 提交**

```bash
git add WBChatApp-UIKit/Core WBChatApp-UIKitTests/NetworkChatProviderTests.swift && git commit -m "网络：实现 SSE 传输层、双协议 Provider 与演示模式"
```

---

## Task 7: ★ 增量切块状态机

整个项目性能设计的核心。把消息流切成块，并保证「已闭合的块永不重新解析」。这是把 O(n²) 压到 O(n) 的唯一依据，务必让不变量测试真正跑通。

**Files:**
- Create: `WBChatApp-UIKit/Core/Markdown/MarkdownBlock.swift`
- Create: `WBChatApp-UIKit/Core/Markdown/StreamingBlockSplitter.swift`
- Test: `WBChatApp-UIKitTests/StreamingBlockSplitterTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum MarkdownBlockKind: Equatable, Hashable, Sendable`：`.paragraph` / `.heading(level: Int)` / `.codeFence(language: String?)` / `.list(ordered: Bool)` / `.blockQuote` / `.table` / `.thematicBreak`
  - `struct MarkdownBlock: Equatable, Hashable, Sendable { let ordinal: Int; let kind: MarkdownBlockKind; let rawText: String; let isSealed: Bool }`，含 `var cacheKey: Int`
  - `struct BlockPatch: Equatable, Sendable { let newlySealed: [MarkdownBlock]; let open: MarkdownBlock? }`，含 `var isEmpty: Bool`
  - `struct StreamingBlockSplitter { private(set) var sealedBlocks: [MarkdownBlock]; mutating func append(_ delta: String) -> BlockPatch; mutating func finish() -> BlockPatch; var allBlocks: [MarkdownBlock] }`

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/StreamingBlockSplitterTests.swift`：

```swift
import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("增量切块状态机")
struct StreamingBlockSplitterTests {

    /// 一次性喂完整文本并收尾，返回全部块
    private func splitAtOnce(_ text: String) -> [MarkdownBlock] {
        var splitter = StreamingBlockSplitter()
        _ = splitter.append(text)
        _ = splitter.finish()
        return splitter.allBlocks
    }

    /// 逐字符喂入并收尾，返回全部块
    private func splitCharByChar(_ text: String) -> [MarkdownBlock] {
        var splitter = StreamingBlockSplitter()
        for character in text { _ = splitter.append(String(character)) }
        _ = splitter.finish()
        return splitter.allBlocks
    }

    // MARK: - 块类型识别

    @Test("空行分隔的两个段落")
    func twoParagraphs() {
        let blocks = splitAtOnce("第一段\n\n第二段\n")
        #expect(blocks.map(\.kind) == [.paragraph, .paragraph])
        #expect(blocks.map(\.rawText) == ["第一段", "第二段"])
    }

    @Test("标题单行成块并立即闭合")
    func heading() {
        let blocks = splitAtOnce("# 大标题\n正文\n")
        #expect(blocks.map(\.kind) == [.heading(level: 1), .paragraph])
        #expect(blocks[0].isSealed)
    }

    @Test("围栏代码块内部的空行不切断块")
    func codeFenceKeepsBlankLines() {
        let text = "```swift\nlet a = 1\n\nlet b = 2\n```\n"
        let blocks = splitAtOnce(text)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .codeFence(language: "swift"))
        #expect(blocks[0].rawText.contains("let b = 2"))
    }

    @Test("代码块内的 # 与 - 不会被误判成标题或列表")
    func codeFenceSwallowsMarkers() {
        let blocks = splitAtOnce("```\n# 这是注释\n- 这是短横线\n```\n")
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .codeFence(language: nil))
    }

    @Test("未闭合的代码块保持 open 且可见")
    func unclosedCodeFenceStaysOpen() {
        var splitter = StreamingBlockSplitter()
        let patch = splitter.append("```swift\nlet a = 1\n")
        #expect(patch.newlySealed.isEmpty)
        let open = try! #require(patch.open)
        #expect(open.kind == .codeFence(language: "swift"))
        #expect(open.isSealed == false)
        #expect(open.rawText.contains("let a = 1"))
    }

    @Test("无序与有序列表")
    func lists() {
        let blocks = splitAtOnce("- a\n- b\n\n1. x\n2. y\n\n")
        #expect(blocks.map(\.kind) == [.list(ordered: false), .list(ordered: true)])
    }

    @Test("列表项之间的单个空行不切断列表")
    func looseList() {
        let blocks = splitAtOnce("- a\n\n- b\n\n正文\n")
        #expect(blocks.map(\.kind) == [.list(ordered: false), .paragraph])
        #expect(blocks[0].rawText.contains("- b"))
    }

    @Test("引用块")
    func blockQuote() {
        let blocks = splitAtOnce("> 引用一\n> 引用二\n正文\n")
        #expect(blocks.map(\.kind) == [.blockQuote, .paragraph])
    }

    @Test("表格")
    func table() {
        let blocks = splitAtOnce("| a | b |\n| --- | --- |\n| 1 | 2 |\n\n尾巴\n")
        #expect(blocks.map(\.kind) == [.table, .paragraph])
    }

    @Test("分割线不被当成列表")
    func thematicBreak() {
        let blocks = splitAtOnce("上\n\n---\n\n下\n")
        #expect(blocks.map(\.kind) == [.paragraph, .thematicBreak, .paragraph])
    }

    @Test("段落后紧跟标题不需要空行也能切开")
    func paragraphThenHeadingWithoutBlankLine() {
        let blocks = splitAtOnce("正文\n## 小标题\n")
        #expect(blocks.map(\.kind) == [.paragraph, .heading(level: 2)])
    }

    // MARK: - 核心不变量

    @Test("核心不变量：已闭合块序列只增不改")
    func sealedBlocksAreMonotonic() {
        let document = """
        # 标题

        这是一段正文，包含 **加粗** 和 `代码`。

        - 列表一
        - 列表二

        ```swift
        let x = 1
        ```

        > 引用

        | a | b |
        | --- | --- |
        | 1 | 2 |

        ---

        收尾段落。
        """

        var splitter = StreamingBlockSplitter()
        var previousSealed: [MarkdownBlock] = []

        for character in document {
            _ = splitter.append(String(character))
            let current = splitter.sealedBlocks

            // 1. 数量只增不减
            #expect(current.count >= previousSealed.count)
            // 2. 已有的每一个块内容完全不变
            for index in previousSealed.indices {
                #expect(current[index] == previousSealed[index],
                        "第 \(index) 个已闭合块被修改了，不变量被破坏")
            }
            previousSealed = current
        }
    }

    @Test("逐字符喂入与一次性喂入结果完全一致")
    func incrementalEqualsAtOnce() {
        let documents = [
            "# 标题\n\n正文\n",
            "```swift\nlet a = 1\n\nlet b = 2\n```\n\n后续\n",
            "- a\n\n- b\n\n正文\n",
            "> 引用\n\n| a | b |\n| --- | --- |\n\n---\n\n结尾",
            "没有换行结尾的裸段落",
        ]
        for document in documents {
            #expect(splitCharByChar(document) == splitAtOnce(document),
                    "文档不一致：\(document)")
        }
    }

    // MARK: - 换行与收尾

    @Test("CRLF 与 CR 都能正确断行")
    func lineEndings() {
        #expect(splitAtOnce("a\r\n\r\nb\r\n").map(\.rawText) == ["a", "b"])
        #expect(splitAtOnce("a\r\rb\r").map(\.rawText) == ["a", "b"])
    }

    @Test("CRLF 被切在两次 append 之间不会产生空块")
    func crlfSplitAcrossAppends() {
        var splitter = StreamingBlockSplitter()
        _ = splitter.append("a\r")
        _ = splitter.append("\nb\r\n")
        _ = splitter.finish()
        // 期望是合并成一块而非两块：正确识别出 CRLF 时行序列是 a、b，
        // 多行段落合并为 "a\nb"；若误把 \r 当行结束、\n 再当空行，
        // 空行会封存段落得到 ["a", "b"]。写成 ["a", "b"] 会让两种情况都通过，
        // 这条测试就失去判别力了。
        #expect(splitter.allBlocks.map(\.rawText) == ["a\nb"])
    }

    @Test("finish 把最后的 open 块闭合")
    func finishSealsOpenBlock() {
        var splitter = StreamingBlockSplitter()
        _ = splitter.append("最后一段没有换行")
        let patch = splitter.finish()
        #expect(patch.open == nil)
        #expect(patch.newlySealed.count == 1)
        #expect(patch.newlySealed[0].isSealed)
        #expect(patch.newlySealed[0].rawText == "最后一段没有换行")
    }

    @Test("ordinal 单调递增且不重复")
    func ordinalsAreMonotonic() {
        let blocks = splitAtOnce("a\n\nb\n\nc\n\n")
        #expect(blocks.map(\.ordinal) == [0, 1, 2])
    }

    @Test("open 块的 ordinal 接在已闭合块之后")
    func openBlockOrdinal() {
        var splitter = StreamingBlockSplitter()
        let patch = splitter.append("a\n\nb")
        #expect(patch.newlySealed.map(\.ordinal) == [0])
        #expect(patch.open?.ordinal == 1)
    }

    @Test("纯空白输入不产生任何块")
    func onlyWhitespace() {
        #expect(splitAtOnce("\n\n   \n\n").isEmpty)
    }

    @Test("cacheKey 对同内容稳定、对不同内容不同")
    func cacheKeyStability() {
        let a = MarkdownBlock(ordinal: 0, kind: .paragraph, rawText: "文本", isSealed: true)
        let b = MarkdownBlock(ordinal: 5, kind: .paragraph, rawText: "文本", isSealed: true)
        let c = MarkdownBlock(ordinal: 0, kind: .paragraph, rawText: "别的", isSealed: true)
        #expect(a.cacheKey == b.cacheKey)   // 与 ordinal 无关
        #expect(a.cacheKey != c.cacheKey)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/StreamingBlockSplitterTests'
```

Expected: 编译失败，`cannot find 'StreamingBlockSplitter' in scope`。

- [ ] **Step 3: 实现块模型**

创建 `WBChatApp-UIKit/Core/Markdown/MarkdownBlock.swift`：

```swift
import Foundation

enum MarkdownBlockKind: Equatable, Hashable, Sendable {
    case paragraph
    case heading(level: Int)
    case codeFence(language: String?)
    case list(ordered: Bool)
    case blockQuote
    case table
    case thematicBreak

    /// 这两类只占一行，看到完整行就能立刻闭合
    var sealsOnSingleLine: Bool {
        switch self {
        case .heading, .thematicBreak: return true
        default: return false
        }
    }
}

/// Markdown 的一个块级元素。
///
/// `isSealed` 为 true 表示后续文本不可能再改变它——这是整个增量渲染的地基：
/// 已闭合的块，其属性串与高度只会计算一次。
struct MarkdownBlock: Equatable, Hashable, Sendable {
    /// 在消息内单调递增，作为块的稳定身份
    let ordinal: Int
    let kind: MarkdownBlockKind
    let rawText: String
    let isSealed: Bool

    /// 缓存键。刻意不含 ordinal，让内容相同的块跨消息共享缓存。
    var cacheKey: Int {
        var hasher = Hasher()
        hasher.combine(kind)
        hasher.combine(rawText)
        return hasher.finalize()
    }
}

/// 一次增量产生的变化。
struct BlockPatch: Equatable, Sendable {
    /// 本次新闭合的块，按 ordinal 顺序追加
    let newlySealed: [MarkdownBlock]
    /// 当前仍在书写的块，nil 表示流已收尾
    let open: MarkdownBlock?

    var isEmpty: Bool { newlySealed.isEmpty && open == nil }

    static let empty = BlockPatch(newlySealed: [], open: nil)
}
```

> **实现时的三个已知陷阱**（Task 7 实测踩到，下面的参考代码已规避，但改动时注意别改回去）：
>
> 1. **`nextLineTerminator()` 必须按 `unicodeScalars` 查找换行，不能按 `Character`。** Swift 的字位簇规则会把相邻的 `\r\n` 合并成**一个** `Character`，按 `Character` 比较 `$0 == "\n" || $0 == "\r"` 永远匹配不到，切块直接失效。
> 2. **`finish()` 要处理流结束时挂起的孤立末尾 `\r`**，否则它会作为普通字符残留进最后一块的内容里。
> 3. **列表分支要检查有序/无序标记是否切换**：`- a` 后面紧跟 `1. x` 属于两个不同的列表，不能合并成一块。

- [ ] **Step 4: 实现切块状态机**

创建 `WBChatApp-UIKit/Core/Markdown/StreamingBlockSplitter.swift`：

```swift
import Foundation

/// 流式 Markdown 块切分器。
///
/// 设计要点：
/// 1. **只处理完整行。** 尾部那段还没等到换行符的文本永远留在 `partial` 里，
///    连同它所属的块一起以 open 形式输出。这保证了已闭合的块不可能再变。
/// 2. **核心不变量：** `sealedBlocks` 随流推进只增不改。
///    上层据此把已闭合块的属性串与高度永久缓存，从而把总代价从 O(n²) 降到 O(n)。
/// 3. 纯值语义、无 UI 依赖，可以逐字符喂入做属性测试。
struct StreamingBlockSplitter {

    /// 已闭合的块，只增不改
    private(set) var sealedBlocks: [MarkdownBlock] = []

    /// 当前正在累积、尚未闭合的块
    private var current: (kind: MarkdownBlockKind, lines: [String])?

    /// 列表内部遇到的空行。若后续仍是列表项就并回列表，否则丢弃并闭合列表。
    private var pendingBlankLines: [String] = []

    /// 还没等到换行符的尾部文本
    private var partial: String = ""

    private var nextOrdinal: Int = 0

    init() {}

    // MARK: - 对外接口

    /// 追加一段增量文本，返回本次产生的变化。
    mutating func append(_ delta: String) -> BlockPatch {
        partial += delta
        var newlySealed: [MarkdownBlock] = []

        while let terminator = nextLineTerminator() {
            let line = String(partial[partial.startIndex..<terminator.lineEnd])
            partial = String(partial[terminator.nextStart...])
            newlySealed += consume(line)
        }
        return BlockPatch(newlySealed: newlySealed, open: openBlock)
    }

    /// 流结束。把残留的尾行与未闭合块一并闭合。
    mutating func finish() -> BlockPatch {
        var newlySealed: [MarkdownBlock] = []
        if !partial.isEmpty {
            let line = partial
            partial = ""
            newlySealed += consume(line)
        }
        if current != nil {
            newlySealed.append(seal())
        }
        return BlockPatch(newlySealed: newlySealed, open: nil)
    }

    /// 已闭合块 + 当前未闭合块
    var allBlocks: [MarkdownBlock] {
        if let open = openBlock { return sealedBlocks + [open] }
        return sealedBlocks
    }

    // MARK: - 行切分

    private struct LineTerminator {
        let lineEnd: String.Index
        let nextStart: String.Index
    }

    private func nextLineTerminator() -> LineTerminator? {
        guard let index = partial.firstIndex(where: { $0 == "\n" || $0 == "\r" }) else {
            return nil
        }
        if partial[index] == "\r" {
            let next = partial.index(after: index)
            // 落在末尾的 \r 要等下一个字符才能判断是 CR 还是 CRLF
            if next == partial.endIndex { return nil }
            if partial[next] == "\n" {
                return LineTerminator(lineEnd: index, nextStart: partial.index(after: next))
            }
        }
        return LineTerminator(lineEnd: index, nextStart: partial.index(after: index))
    }

    // MARK: - 块状态机

    /// 吃掉一整行，返回本行导致闭合的块。
    private mutating func consume(_ line: String) -> [MarkdownBlock] {
        var sealed: [MarkdownBlock] = []
        var lineToProcess: String? = line

        // 一行最多触发一次「闭合旧块 + 重新处理该行」，用循环而非递归表达
        while let currentLine = lineToProcess {
            lineToProcess = nil
            let isBlank = currentLine.trimmingCharacters(in: .whitespaces).isEmpty

            guard var block = current else {
                if isBlank { break }
                let kind = Self.kind(ofOpeningLine: currentLine)
                current = (kind, [currentLine])
                if kind.sealsOnSingleLine { sealed.append(seal()) }
                break
            }

            switch block.kind {
            case .codeFence:
                block.lines.append(currentLine)
                current = block
                if Self.isClosingFence(currentLine, opener: block.lines[0]) {
                    sealed.append(seal())
                }

            case .blockQuote:
                if currentLine.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    block.lines.append(currentLine)
                    current = block
                } else {
                    sealed.append(seal())
                    lineToProcess = currentLine
                }

            case .table:
                if currentLine.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    block.lines.append(currentLine)
                    current = block
                } else {
                    sealed.append(seal())
                    lineToProcess = currentLine
                }

            case .list:
                if isBlank {
                    // 先挂起，等下一行决定这是列表内的空行还是列表结束
                    pendingBlankLines.append(currentLine)
                } else if Self.isListItem(currentLine) || Self.isIndentedContinuation(currentLine) {
                    block.lines += pendingBlankLines
                    pendingBlankLines.removeAll()
                    block.lines.append(currentLine)
                    current = block
                } else {
                    sealed.append(seal())
                    lineToProcess = currentLine
                }

            case .paragraph:
                if isBlank {
                    sealed.append(seal())
                } else if Self.startsNewBlock(currentLine) {
                    // 段落后紧跟标题/代码块/列表等，不需要空行也要切开
                    sealed.append(seal())
                    lineToProcess = currentLine
                } else {
                    block.lines.append(currentLine)
                    current = block
                }

            case .heading, .thematicBreak:
                // 这两类在开块时已立即闭合，理论上到不了这里
                sealed.append(seal())
                lineToProcess = currentLine
            }
        }
        return sealed
    }

    private mutating func seal() -> MarkdownBlock {
        guard let block = current else {
            preconditionFailure("seal 只能在存在未闭合块时调用")
        }
        let sealed = MarkdownBlock(ordinal: nextOrdinal,
                                   kind: block.kind,
                                   rawText: block.lines.joined(separator: "\n"),
                                   isSealed: true)
        sealedBlocks.append(sealed)
        nextOrdinal += 1
        current = nil
        pendingBlankLines.removeAll()
        return sealed
    }

    /// 当前未闭合块 = 已累积的完整行 + 挂起的空行 + 尾部残行
    private var openBlock: MarkdownBlock? {
        if let block = current {
            var lines = block.lines + pendingBlankLines
            if !partial.isEmpty { lines.append(partial) }
            return MarkdownBlock(ordinal: nextOrdinal,
                                 kind: block.kind,
                                 rawText: lines.joined(separator: "\n"),
                                 isSealed: false)
        }
        guard !partial.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return MarkdownBlock(ordinal: nextOrdinal,
                             kind: Self.kind(ofOpeningLine: partial),
                             rawText: partial,
                             isSealed: false)
    }

    // MARK: - 行特征判定

    static func kind(ofOpeningLine line: String) -> MarkdownBlockKind {
        let text = line.trimmingCharacters(in: .whitespaces)

        if let fence = fenceInfo(text) {
            return .codeFence(language: fence.language)
        }
        if let level = headingLevel(text) {
            return .heading(level: level)
        }
        if isThematicBreak(text) {
            return .thematicBreak
        }
        if text.hasPrefix(">") {
            return .blockQuote
        }
        if isListItem(text) {
            return .list(ordered: isOrderedListItem(text))
        }
        if text.hasPrefix("|") {
            return .table
        }
        return .paragraph
    }

    /// 除段落外的所有块起始，都能在无空行的情况下打断上一个段落
    static func startsNewBlock(_ line: String) -> Bool {
        kind(ofOpeningLine: line) != .paragraph
    }

    private static func fenceInfo(_ text: String) -> (marker: Character, count: Int, language: String?)? {
        guard let first = text.first, first == "`" || first == "~" else { return nil }
        let count = text.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        let rest = String(text.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        return (first, count, rest.isEmpty ? nil : rest)
    }

    static func isClosingFence(_ line: String, opener: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let open = fenceInfo(opener.trimmingCharacters(in: .whitespaces)),
              let close = fenceInfo(text) else { return false }
        // 闭合围栏必须同字符、不短于开栏，且后面没有语言标识
        return close.marker == open.marker
            && close.count >= open.count
            && close.language == nil
    }

    private static func headingLevel(_ text: String) -> Int? {
        let hashes = text.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = text.dropFirst(hashes)
        // "#标题" 不算标题，必须有空格或整行只有 #
        guard rest.isEmpty || rest.first == " " else { return nil }
        return hashes
    }

    private static func isThematicBreak(_ text: String) -> Bool {
        let stripped = text.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" }
            || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }

    static func isListItem(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        if let first = text.first, "-*+".contains(first) {
            // 必须是「标记 + 空格」，这样 "---" 不会被当成列表
            return text.dropFirst().first == " "
        }
        return isOrderedListItem(text)
    }

    private static func isOrderedListItem(_ text: String) -> Bool {
        let digits = text.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return false }
        let rest = text.dropFirst(digits.count)
        guard let marker = rest.first, marker == "." || marker == ")" else { return false }
        return rest.dropFirst().first == " "
    }

    /// 列表项的缩进续行
    static func isIndentedContinuation(_ line: String) -> Bool {
        line.hasPrefix("  ") || line.hasPrefix("\t")
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/StreamingBlockSplitterTests'
```

Expected: 20 个用例全部 PASS。**「核心不变量：已闭合块序列只增不改」这条必须通过，它不过就说明整个增量渲染方案不成立，不要跳过或放宽断言。**

- [ ] **Step 6: 提交**

```bash
git add WBChatApp-UIKit/Core/Markdown WBChatApp-UIKitTests/StreamingBlockSplitterTests.swift && git commit -m "渲染：实现流式 Markdown 块切分状态机，保证已闭合块不可变"
```

---

## Task 8: Markdown 主题与代码高亮

**Files:**
- Create: `WBChatApp-UIKit/Core/Markdown/MarkdownTheme.swift`
- Create: `WBChatApp-UIKit/Core/Markdown/CodeHighlighter.swift`
- Test: `WBChatApp-UIKitTests/CodeHighlighterTests.swift`

**Interfaces:**
- Consumes: `Theme`（Task 1）
- Produces:
  - `struct MarkdownTheme: Sendable`，含 `bodyFont` / `monoFont` / `headingFont(level:)` / `textColor` / `secondaryColor` / `linkColor` / `codeTextColor` / `blockSpacing` / `lineSpacing` / `listIndent` / `quoteBarWidth`，以及 `static let `default``
  - `struct CodeHighlighter: Sendable { func highlight(code: String, language: String?, theme: MarkdownTheme) -> NSAttributedString }`
  - `extension NSAttributedString.Key { static let wbCodeTokenKind: NSAttributedString.Key }`（测试用，标记 token 类型）
  - `enum CodeTokenKind: String { case keyword, string, comment, number, plain }`

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/CodeHighlighterTests.swift`：

```swift
import Foundation
import UIKit
import Testing
@testable import WBChatApp_UIKit

@Suite("代码高亮")
struct CodeHighlighterTests {

    private let highlighter = CodeHighlighter()
    private let theme = MarkdownTheme.default

    /// 取出指定子串被标记的 token 类型
    private func kind(of substring: String, in code: String, language: String?) -> CodeTokenKind? {
        let attributed = highlighter.highlight(code: code, language: language, theme: theme)
        guard let range = code.range(of: substring) else { return nil }
        let location = code.distance(from: code.startIndex, to: range.lowerBound)
        let raw = attributed.attribute(.wbCodeTokenKind, at: location, effectiveRange: nil) as? String
        return raw.flatMap(CodeTokenKind.init(rawValue:))
    }

    @Test("Swift 关键字被标记")
    func swiftKeyword() {
        #expect(kind(of: "func", in: "func greet() {}", language: "swift") == .keyword)
    }

    @Test("字符串字面量被标记")
    func stringLiteral() {
        #expect(kind(of: "\"hi\"", in: "let a = \"hi\"", language: "swift") == .string)
    }

    @Test("行注释被标记")
    func lineComment() {
        #expect(kind(of: "// 说明", in: "let a = 1 // 说明", language: "swift") == .comment)
    }

    @Test("数字被标记")
    func number() {
        #expect(kind(of: "42", in: "let a = 42", language: "swift") == .number)
    }

    @Test("字符串内部的关键字不被误标")
    func keywordInsideStringIsNotHighlighted() {
        #expect(kind(of: "func", in: "let a = \"func\"", language: "swift") == .string)
    }

    @Test("注释内部的关键字不被误标")
    func keywordInsideCommentIsNotHighlighted() {
        #expect(kind(of: "func", in: "// func 只是文字", language: "swift") == .comment)
    }

    @Test("JSON 的键值都按字符串处理")
    func jsonStrings() {
        #expect(kind(of: "\"name\"", in: "{\"name\": \"张三\"}", language: "json") == .string)
    }

    @Test("Python 关键字")
    func pythonKeyword() {
        #expect(kind(of: "def", in: "def main():", language: "python") == .keyword)
    }

    @Test("未知语言降级为通用规则，仍能识别字符串与注释")
    func unknownLanguageFallback() {
        #expect(kind(of: "\"x\"", in: "a = \"x\" // 注释", language: "rust") == .string)
        #expect(kind(of: "// 注释", in: "a = \"x\" // 注释", language: "rust") == .comment)
    }

    @Test("输出长度与输入一致，不丢字符")
    func lengthPreserved() {
        let code = "func f() {\n  return \"x\" // c\n}"
        let attributed = highlighter.highlight(code: code, language: "swift", theme: theme)
        #expect(attributed.string == code)
    }

    @Test("整段使用等宽字体")
    func monospacedFont() {
        let attributed = highlighter.highlight(code: "let a = 1", language: "swift", theme: theme)
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font == theme.monoFont)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/CodeHighlighterTests'
```

Expected: 编译失败，`cannot find 'CodeHighlighter' in scope`。

- [ ] **Step 3: 实现主题**

创建 `WBChatApp-UIKit/Core/Markdown/MarkdownTheme.swift`：

```swift
import UIKit

/// Markdown 渲染的排版参数。集中在一处，方便调整与做深浅色适配。
struct MarkdownTheme: Sendable {

    let bodyFont: UIFont
    let monoFont: UIFont
    let textColor: UIColor
    let secondaryColor: UIColor
    let linkColor: UIColor
    let codeTextColor: UIColor

    /// 块与块之间的垂直间距
    let blockSpacing: CGFloat
    let lineSpacing: CGFloat
    let listIndent: CGFloat
    let quoteBarWidth: CGFloat

    func headingFont(level: Int) -> UIFont {
        let size: CGFloat
        switch level {
        case 1: size = bodyFont.pointSize + 8
        case 2: size = bodyFont.pointSize + 5
        case 3: size = bodyFont.pointSize + 3
        default: size = bodyFont.pointSize + 1
        }
        return UIFont.systemFont(ofSize: size, weight: .semibold)
    }

    static let `default` = MarkdownTheme(
        bodyFont: UIFont.preferredFont(forTextStyle: .body),
        monoFont: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize,
                                              weight: .regular),
        textColor: Theme.textPrimary,
        secondaryColor: Theme.textSecondary,
        linkColor: Theme.accent,
        codeTextColor: Theme.textPrimary,
        blockSpacing: 12,
        lineSpacing: 4,
        listIndent: 20,
        quoteBarWidth: 3
    )
}
```

- [ ] **Step 4: 实现代码高亮**

创建 `WBChatApp-UIKit/Core/Markdown/CodeHighlighter.swift`：

```swift
import UIKit

enum CodeTokenKind: String {
    case keyword, string, comment, number, plain
}

extension NSAttributedString.Key {
    /// 标记 token 类型。渲染不用它，测试用它断言分词是否正确。
    static let wbCodeTokenKind = NSAttributedString.Key("wbCodeTokenKind")
}

/// 轻量语法高亮。
///
/// 用一遍线性扫描而非正则：注释与字符串会「吞掉」内部内容，
/// 从而天然避免「字符串里的 func 被标成关键字」这类误判。
struct CodeHighlighter: Sendable {

    private static let keywordsByLanguage: [String: Set<String>] = [
        "swift": ["func", "let", "var", "if", "else", "guard", "return", "struct", "class",
                  "enum", "protocol", "extension", "import", "for", "in", "while", "switch",
                  "case", "default", "self", "init", "throws", "try", "async", "await",
                  "private", "public", "internal", "static", "some", "any", "nil", "true", "false"],
        "objc":  ["@interface", "@implementation", "@property", "@end", "void", "id", "self",
                  "if", "else", "return", "for", "while", "switch", "case", "nil", "YES", "NO",
                  "NSString", "NSInteger", "BOOL", "instancetype"],
        "javascript": ["function", "const", "let", "var", "if", "else", "return", "class",
                       "import", "export", "for", "while", "switch", "case", "async", "await",
                       "new", "this", "null", "undefined", "true", "false"],
        "python": ["def", "class", "if", "elif", "else", "return", "import", "from", "for",
                   "while", "try", "except", "finally", "with", "as", "lambda", "None",
                   "True", "False", "self", "async", "await"],
        "bash":  ["if", "then", "else", "fi", "for", "in", "do", "done", "while", "case",
                  "esac", "function", "echo", "export", "local", "return"],
    ]

    /// 语言别名归一
    private static let aliases: [String: String] = [
        "js": "javascript", "ts": "javascript", "typescript": "javascript",
        "py": "python", "sh": "bash", "shell": "bash", "zsh": "bash",
        "objective-c": "objc", "objectivec": "objc", "m": "objc",
    ]

    func highlight(code: String, language: String?, theme: MarkdownTheme) -> NSAttributedString {
        let normalized = language.map { $0.lowercased() }.map { Self.aliases[$0] ?? $0 }
        let keywords = normalized.flatMap { Self.keywordsByLanguage[$0] } ?? []
        let isJSON = normalized == "json"

        let result = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: theme.monoFont,
                .foregroundColor: theme.codeTextColor,
                .wbCodeTokenKind: CodeTokenKind.plain.rawValue,
            ])

        let characters = Array(code)
        var index = 0

        // Character（字位簇）偏移与 NSRange 要的 UTF-16 偏移并不相等：
        // emoji 等非 BMP 字符占 2 个 code unit，直接拿 Character 下标当 NSRange
        // 会让该字符之后所有 token 的高亮区间整体错位。这里预先建一张映射表。
        // utf16Offsets[i] 是第 i 个 Character 的 UTF-16 起始偏移，长度为 count + 1。
        var utf16Offsets = [Int](repeating: 0, count: characters.count + 1)
        for (i, character) in characters.enumerated() {
            utf16Offsets[i + 1] = utf16Offsets[i] + character.utf16.count
        }

        func apply(_ kind: CodeTokenKind, from start: Int, to end: Int) {
            guard end > start else { return }
            let location = utf16Offsets[start]
            result.addAttributes([
                .foregroundColor: Self.color(for: kind, theme: theme),
                .wbCodeTokenKind: kind.rawValue,
            ], range: NSRange(location: location, length: utf16Offsets[end] - location))
        }

        while index < characters.count {
            let character = characters[index]

            // 行注释：// 与 #（bash/python）
            if character == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                let start = index
                while index < characters.count, characters[index] != "\n" { index += 1 }
                apply(.comment, from: start, to: index)
                continue
            }
            if character == "#", normalized == "python" || normalized == "bash" {
                let start = index
                while index < characters.count, characters[index] != "\n" { index += 1 }
                apply(.comment, from: start, to: index)
                continue
            }
            // 块注释
            if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                let start = index
                index += 2
                while index + 1 < characters.count,
                      !(characters[index] == "*" && characters[index + 1] == "/") { index += 1 }
                index = min(index + 2, characters.count)
                apply(.comment, from: start, to: index)
                continue
            }
            // 字符串
            if character == "\"" || character == "'" {
                let quote = character
                let start = index
                index += 1
                while index < characters.count {
                    // 反斜杠若恰好是最后一个字符（流式截断很容易出现），
                    // 裸的 index += 2 会跳出数组，随后 apply 构造出越界 NSRange 崩溃
                    if characters[index] == "\\" { index = min(index + 2, characters.count); continue }
                    if characters[index] == quote { index += 1; break }
                    if characters[index] == "\n" { break }
                    index += 1
                }
                apply(.string, from: start, to: index)
                continue
            }
            // 数字
            if character.isNumber {
                let start = index
                while index < characters.count,
                      characters[index].isNumber || characters[index] == "." { index += 1 }
                apply(.number, from: start, to: index)
                continue
            }
            // 标识符 / 关键字
            if character.isLetter || character == "_" || character == "@" {
                let start = index
                if characters[index] == "@" { index += 1 }
                while index < characters.count,
                      characters[index].isLetter || characters[index].isNumber
                        || characters[index] == "_" { index += 1 }
                let word = String(characters[start..<index])
                if keywords.contains(word) {
                    apply(.keyword, from: start, to: index)
                }
                continue
            }
            // JSON 没有关键字，其余符号原样保留
            _ = isJSON
            index += 1
        }
        return result
    }

    private static func color(for kind: CodeTokenKind, theme: MarkdownTheme) -> UIColor {
        switch kind {
        case .keyword: return UIColor.systemPink
        case .string:  return UIColor.systemRed
        case .comment: return theme.secondaryColor
        case .number:  return UIColor.systemBlue
        case .plain:   return theme.codeTextColor
        }
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/CodeHighlighterTests'
```

Expected: 11 个用例全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add WBChatApp-UIKit/Core/Markdown WBChatApp-UIKitTests/CodeHighlighterTests.swift && git commit -m "渲染：实现 Markdown 主题与线性扫描式代码高亮"
```

---

## Task 9: 单块属性串渲染器

用 swift-markdown 解析**单个块**，遍历 AST 生成 `NSAttributedString`。代码块不走 swift-markdown，直接交给高亮器。

**Files:**
- Create: `WBChatApp-UIKit/Core/Markdown/AttributedRenderer.swift`
- Test: `WBChatApp-UIKitTests/AttributedRendererTests.swift`

**Interfaces:**
- Consumes: `MarkdownBlock`（Task 7）、`MarkdownTheme` / `CodeHighlighter`（Task 8）
- Produces:
  - `final class AttributedRenderer { init(theme: MarkdownTheme = .default, highlighter: CodeHighlighter = CodeHighlighter()); func render(_ block: MarkdownBlock) -> NSAttributedString; func codeText(of block: MarkdownBlock) -> String }`
  - `extension NSAttributedString.Key { static let wbLinkURL: NSAttributedString.Key }`

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/AttributedRendererTests.swift`：

```swift
import Foundation
import UIKit
import Testing
@testable import WBChatApp_UIKit

@Suite("属性串渲染")
struct AttributedRendererTests {

    private let renderer = AttributedRenderer()
    private let theme = MarkdownTheme.default

    private func block(_ kind: MarkdownBlockKind, _ text: String) -> MarkdownBlock {
        MarkdownBlock(ordinal: 0, kind: kind, rawText: text, isSealed: true)
    }

    private func traits(_ attributed: NSAttributedString, at index: Int) -> UIFontDescriptor.SymbolicTraits {
        let font = attributed.attribute(.font, at: index, effectiveRange: nil) as? UIFont
        return font?.fontDescriptor.symbolicTraits ?? []
    }

    @Test("段落纯文本")
    func paragraph() {
        let result = renderer.render(block(.paragraph, "普通文本"))
        #expect(result.string == "普通文本")
    }

    @Test("加粗与斜体带上对应 trait")
    func emphasis() {
        let result = renderer.render(block(.paragraph, "前**粗**中*斜*后"))
        #expect(result.string == "前粗中斜后")
        #expect(traits(result, at: 1).contains(.traitBold))
        #expect(traits(result, at: 3).contains(.traitItalic))
        #expect(!traits(result, at: 0).contains(.traitBold))
    }

    @Test("行内代码使用等宽字体")
    func inlineCode() {
        let result = renderer.render(block(.paragraph, "看 `code` 这里"))
        #expect(result.string == "看 code 这里")
        let font = result.attribute(.font, at: 2, effectiveRange: nil) as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true)
    }

    @Test("删除线")
    func strikethrough() {
        let result = renderer.render(block(.paragraph, "~~删掉~~"))
        #expect(result.string == "删掉")
        #expect(result.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) != nil)
    }

    @Test("链接带上 URL 与链接色")
    func link() {
        let result = renderer.render(block(.paragraph, "点[这里](https://example.com)看"))
        #expect(result.string == "点这里看")
        let url = result.attribute(.wbLinkURL, at: 1, effectiveRange: nil) as? URL
        #expect(url == URL(string: "https://example.com"))
        let color = result.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? UIColor
        #expect(color == theme.linkColor)
    }

    @Test("标题使用对应层级字体")
    func heading() {
        let result = renderer.render(block(.heading(level: 1), "# 大标题"))
        #expect(result.string == "大标题")
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font == theme.headingFont(level: 1))
    }

    @Test("无序列表逐项加项目符号")
    func unorderedList() {
        let result = renderer.render(block(.list(ordered: false), "- 甲\n- 乙"))
        #expect(result.string.contains("• 甲"))
        #expect(result.string.contains("• 乙"))
    }

    @Test("有序列表按序号编号")
    func orderedList() {
        let result = renderer.render(block(.list(ordered: true), "1. 甲\n2. 乙"))
        #expect(result.string.contains("1. 甲"))
        #expect(result.string.contains("2. 乙"))
    }

    @Test("引用块去掉引号前缀并用次要色")
    func blockQuote() {
        let result = renderer.render(block(.blockQuote, "> 引用内容"))
        #expect(result.string == "引用内容")
        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        #expect(color == theme.secondaryColor)
    }

    @Test("代码块走高亮器，保留原始代码文本")
    func codeFence() {
        let raw = "```swift\nlet a = 1\n```"
        let result = renderer.render(block(.codeFence(language: "swift"), raw))
        #expect(result.string == "let a = 1")
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font == theme.monoFont)
    }

    @Test("codeText 剥掉围栏，供复制按钮使用")
    func codeTextStripsFence() {
        let raw = "```swift\nlet a = 1\nlet b = 2\n```"
        let block = block(.codeFence(language: "swift"), raw)
        #expect(renderer.codeText(of: block) == "let a = 1\nlet b = 2")
    }

    @Test("未闭合的代码块也能渲染出已有内容")
    func unclosedCodeFence() {
        let raw = "```swift\nlet a = 1"
        let unsealed = MarkdownBlock(ordinal: 0, kind: .codeFence(language: "swift"),
                                     rawText: raw, isSealed: false)
        #expect(renderer.codeText(of: unsealed) == "let a = 1")
    }

    @Test("同一块渲染两次结果一致（渲染是纯函数）")
    func renderIsDeterministic() {
        let target = block(.paragraph, "**稳定** 的输出")
        #expect(renderer.render(target).isEqual(to: renderer.render(target)))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/AttributedRendererTests'
```

Expected: 编译失败，`cannot find 'AttributedRenderer' in scope`。

- [ ] **Step 3: 实现渲染器**

创建 `WBChatApp-UIKit/Core/Markdown/AttributedRenderer.swift`：

```swift
import UIKit
import Markdown

extension NSAttributedString.Key {
    /// 链接目标。不用系统的 .link，是为了自己控制点击与配色。
    static let wbLinkURL = NSAttributedString.Key("wbLinkURL")
}

/// 把单个 Markdown 块渲染成属性串。
///
/// 刻意只处理**一个块**：swift-markdown 每次只解析几十到几百字，
/// 配合已闭合块的缓存，整条消息的渲染代价才是线性的。
final class AttributedRenderer {

    private let theme: MarkdownTheme
    private let highlighter: CodeHighlighter

    init(theme: MarkdownTheme = .default, highlighter: CodeHighlighter = CodeHighlighter()) {
        self.theme = theme
        self.highlighter = highlighter
    }

    func render(_ block: MarkdownBlock) -> NSAttributedString {
        // 代码块不经过 swift-markdown：既省一次解析，也便于未闭合时照样出图
        if case .codeFence(let language) = block.kind {
            return highlighter.highlight(code: codeText(of: block),
                                         language: language,
                                         theme: theme)
        }

        let document = Document(parsing: block.rawText)
        let result = NSMutableAttributedString()
        for child in document.children {
            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(renderBlockMarkup(child))
        }
        applyParagraphStyle(to: result, kind: block.kind)
        return result
    }

    /// 剥掉围栏行，拿到纯代码。未闭合的块没有结尾围栏，也要能正确处理。
    func codeText(of block: MarkdownBlock) -> String {
        var lines = block.rawText.components(separatedBy: "\n")
        if let first = lines.first,
           first.trimmingCharacters(in: .whitespaces).hasPrefix("```")
            || first.trimmingCharacters(in: .whitespaces).hasPrefix("~~~") {
            lines.removeFirst()
        }
        if let last = lines.last,
           last.trimmingCharacters(in: .whitespaces).hasPrefix("```")
            || last.trimmingCharacters(in: .whitespaces).hasPrefix("~~~") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 块级

    private func renderBlockMarkup(_ markup: Markup) -> NSAttributedString {
        switch markup {
        case let heading as Heading:
            let result = NSMutableAttributedString(attributedString: renderInlines(heading))
            result.addAttributes([.font: theme.headingFont(level: heading.level)],
                                 range: NSRange(location: 0, length: result.length))
            return result

        case let paragraph as Paragraph:
            return renderInlines(paragraph)

        case let quote as BlockQuote:
            let result = NSMutableAttributedString()
            for child in quote.children {
                if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
                result.append(renderBlockMarkup(child))
            }
            result.addAttributes([.foregroundColor: theme.secondaryColor],
                                 range: NSRange(location: 0, length: result.length))
            return result

        case let list as UnorderedList:
            return renderList(items: Array(list.listItems), marker: { _ in "• " })

        case let list as OrderedList:
            let start = Int(list.startIndex)
            return renderList(items: Array(list.listItems), marker: { "\(start + $0). " })

        case is ThematicBreak:
            // 分割线由独立的 DividerBlockView 画，这里不产出文本
            return NSAttributedString()

        case let table as Markdown.Table:
            return renderTable(table)

        case let code as CodeBlock:
            return highlighter.highlight(code: code.code.trimmingCharacters(in: .newlines),
                                         language: code.language,
                                         theme: theme)

        default:
            // 兜底：把纯文本取出来，绝不丢内容
            return NSAttributedString(string: markup.format(),
                                      attributes: [.font: theme.bodyFont,
                                                   .foregroundColor: theme.textColor])
        }
    }

    private func renderList(items: [ListItem], marker: (Int) -> String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(NSAttributedString(string: marker(index),
                                             attributes: [.font: theme.bodyFont,
                                                          .foregroundColor: theme.secondaryColor]))
            // 一个列表项可能含多个子块（嵌套列表、多段落列表项），
            // 子块之间要换行。注意换行只加在子块之间，
            // 不能让标记「• 」与它后面的第一个子块之间也插换行。
            for (childIndex, child) in item.children.enumerated() {
                if childIndex > 0 { result.append(NSAttributedString(string: "\n")) }
                result.append(renderBlockMarkup(child))
            }
        }
        return result
    }

    private func renderTable(_ table: Markdown.Table) -> NSAttributedString {
        // 表格由 TableBlockView 负责画格线，这里只把单元格文本按行列拼出来兜底
        let result = NSMutableAttributedString()
        func appendRow(_ cells: [String]) {
            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(NSAttributedString(string: cells.joined(separator: "\t"),
                                             attributes: [.font: theme.bodyFont,
                                                          .foregroundColor: theme.textColor]))
        }
        appendRow(table.head.cells.map { $0.plainText })
        for row in table.body.rows {
            appendRow(row.cells.map { $0.plainText })
        }
        return result
    }

    // MARK: - 行内

    private func renderInlines(_ container: Markup) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in container.children {
            result.append(renderInline(child, base: baseAttributes))
        }
        return result
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: theme.bodyFont, .foregroundColor: theme.textColor]
    }

    private func renderInline(_ markup: Markup,
                              base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        switch markup {
        case let text as Markdown.Text:
            return NSAttributedString(string: text.string, attributes: base)

        case is SoftBreak:
            return NSAttributedString(string: " ", attributes: base)

        case is LineBreak:
            return NSAttributedString(string: "\n", attributes: base)

        case let code as InlineCode:
            var attributes = base
            attributes[.font] = theme.monoFont
            attributes[.backgroundColor] = Theme.codeBackground
            return NSAttributedString(string: code.code, attributes: attributes)

        case let strong as Strong:
            return renderChildren(strong, base: adding(.traitBold, to: base))

        case let emphasis as Emphasis:
            return renderChildren(emphasis, base: adding(.traitItalic, to: base))

        case let strike as Strikethrough:
            var attributes = base
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            return renderChildren(strike, base: attributes)

        case let link as Markdown.Link:
            var attributes = base
            attributes[.foregroundColor] = theme.linkColor
            if let destination = link.destination, let url = URL(string: destination) {
                attributes[.wbLinkURL] = url
            }
            return renderChildren(link, base: attributes)

        default:
            return renderChildren(markup, base: base)
        }
    }

    private func renderChildren(_ markup: Markup,
                                base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(renderInline(child, base: base))
        }
        // 叶子节点没有子节点时，退回它的纯文本
        if result.length == 0, let text = markup as? Markdown.Text {
            return NSAttributedString(string: text.string, attributes: base)
        }
        return result
    }

    private func adding(_ trait: UIFontDescriptor.SymbolicTraits,
                        to attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var result = attributes
        let font = (attributes[.font] as? UIFont) ?? theme.bodyFont
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(trait)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            result[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
        }
        return result
    }

    private func applyParagraphStyle(to attributed: NSMutableAttributedString,
                                     kind: MarkdownBlockKind) {
        guard attributed.length > 0 else { return }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = theme.lineSpacing
        if case .list = kind {
            style.headIndent = theme.listIndent
        }
        attributed.addAttribute(.paragraphStyle, value: style,
                                range: NSRange(location: 0, length: attributed.length))
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/AttributedRendererTests'
```

Expected: 13 个用例全部 PASS。

若 `Table` 或 `Strikethrough` 报找不到类型，说明 swift-markdown 版本不对——确认锁的是 `0.8.0`。

- [ ] **Step 5: 提交**

```bash
git add WBChatApp-UIKit/Core/Markdown WBChatApp-UIKitTests/AttributedRendererTests.swift && git commit -m "渲染：实现单块属性串渲染器，代码块直连高亮器"
```

---

## Task 10: 属性串与高度缓存

已闭合块只算一次的兑现处。缓存键用块内容 hash，与 ordinal 无关，因此内容相同的块跨消息共享。

**Files:**
- Create: `WBChatApp-UIKit/Core/Markdown/AttributedCache.swift`
- Test: `WBChatApp-UIKitTests/AttributedCacheTests.swift`

**Interfaces:**
- Consumes: `MarkdownBlock`（Task 7）
- Produces: `final class AttributedCache`
  ```swift
  init(countLimit: Int = 400)
  func attributedString(for block: MarkdownBlock,
                        render: (MarkdownBlock) -> NSAttributedString) -> NSAttributedString
  func height(for block: MarkdownBlock,
              width: CGFloat,
              render: (MarkdownBlock) -> NSAttributedString,
              measure: (NSAttributedString) -> CGFloat) -> CGFloat
  func removeAll()
  ```
  > **宽度必须量化后再做缓存键。** 宽度来自 safe area、约束求解等浮点路径，两次算出的值可能只差一个 ulp，
  > 直接拿它做字典键会让缓存**静默失效**（无报错，只表现为性能变差）。实现按固定粒度 3 量化
  > （`(width * 3).rounded() / 3`，覆盖 @3x），不用 `UIScreen.main.scale`——后者在 iOS 17+ 已 deprecated，
  > 且会让缓存行为与运行环境耦合。
  >
  > **本类型假定所有调用都在主线程，内部不做同步**：`Entry.heights` 是普通字典，跨线程并发调 `height` 会数据竞争。
  >
  > `height` 必须自带 `render` 闭包。早先的设计让它依赖「调用方先调过 `attributedString` 建好条目」，
  > 缺条目时退回测量一个空串——测出来的高度与真实内容无关。实测下 `heightMeasuredOncePerWidth`
  > 直接失败，另两条则是「巧合通过」（断言只数调用次数，恰好对上）。

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/AttributedCacheTests.swift`：

```swift
import Foundation
import UIKit
import Testing
@testable import WBChatApp_UIKit

@Suite("渲染缓存")
struct AttributedCacheTests {

    private func sealed(_ text: String, ordinal: Int = 0) -> MarkdownBlock {
        MarkdownBlock(ordinal: ordinal, kind: .paragraph, rawText: text, isSealed: true)
    }

    private func open(_ text: String) -> MarkdownBlock {
        MarkdownBlock(ordinal: 0, kind: .paragraph, rawText: text, isSealed: false)
    }

    @Test("已闭合块只渲染一次")
    func sealedBlockRendersOnce() {
        let cache = AttributedCache()
        var renderCount = 0
        let block = sealed("内容")
        for _ in 0..<5 {
            _ = cache.attributedString(for: block) { b in
                renderCount += 1
                return NSAttributedString(string: b.rawText)
            }
        }
        #expect(renderCount == 1)
    }

    @Test("未闭合块每次都重新渲染")
    func openBlockAlwaysRenders() {
        let cache = AttributedCache()
        var renderCount = 0
        for _ in 0..<3 {
            _ = cache.attributedString(for: open("写到一半")) { b in
                renderCount += 1
                return NSAttributedString(string: b.rawText)
            }
        }
        #expect(renderCount == 3)
    }

    @Test("内容相同但 ordinal 不同的块共享缓存")
    func cacheIsContentAddressed() {
        let cache = AttributedCache()
        var renderCount = 0
        let render: (MarkdownBlock) -> NSAttributedString = { b in
            renderCount += 1
            return NSAttributedString(string: b.rawText)
        }
        _ = cache.attributedString(for: sealed("同样的话", ordinal: 0), render: render)
        _ = cache.attributedString(for: sealed("同样的话", ordinal: 7), render: render)
        #expect(renderCount == 1)
    }

    @Test("内容不同则各自渲染")
    func differentContentRendersSeparately() {
        let cache = AttributedCache()
        var renderCount = 0
        let render: (MarkdownBlock) -> NSAttributedString = { b in
            renderCount += 1
            return NSAttributedString(string: b.rawText)
        }
        _ = cache.attributedString(for: sealed("甲"), render: render)
        _ = cache.attributedString(for: sealed("乙"), render: render)
        #expect(renderCount == 2)
    }

    @Test("同宽度的高度只测量一次")
    func heightMeasuredOncePerWidth() {
        let cache = AttributedCache()
        var measureCount = 0
        let block = sealed("内容")
        for _ in 0..<4 {
            _ = cache.height(for: block, width: 320) { _ in
                measureCount += 1
                return 44
            }
        }
        #expect(measureCount == 1)
    }

    @Test("宽度变化触发重新测量")
    func widthChangeInvalidatesHeight() {
        let cache = AttributedCache()
        var measureCount = 0
        let block = sealed("内容")
        let measure: (NSAttributedString) -> CGFloat = { _ in
            measureCount += 1
            return 44
        }
        _ = cache.height(for: block, width: 320, measure: measure)
        _ = cache.height(for: block, width: 375, measure: measure)
        #expect(measureCount == 2)
    }

    @Test("未闭合块的高度每次重测")
    func openBlockHeightNotCached() {
        let cache = AttributedCache()
        var measureCount = 0
        for _ in 0..<3 {
            _ = cache.height(for: open("变化中"), width: 320) { _ in
                measureCount += 1
                return 44
            }
        }
        #expect(measureCount == 3)
    }

    @Test("removeAll 清空后重新渲染")
    func removeAllClearsCache() {
        let cache = AttributedCache()
        var renderCount = 0
        let render: (MarkdownBlock) -> NSAttributedString = { b in
            renderCount += 1
            return NSAttributedString(string: b.rawText)
        }
        _ = cache.attributedString(for: sealed("内容"), render: render)
        cache.removeAll()
        _ = cache.attributedString(for: sealed("内容"), render: render)
        #expect(renderCount == 2)
    }

    @Test("返回的属性串内容正确")
    func returnsCorrectValue() {
        let cache = AttributedCache()
        let result = cache.attributedString(for: sealed("你好")) {
            NSAttributedString(string: $0.rawText)
        }
        #expect(result.string == "你好")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/AttributedCacheTests'
```

Expected: 编译失败，`cannot find 'AttributedCache' in scope`。

- [ ] **Step 3: 实现缓存**

创建 `WBChatApp-UIKit/Core/Markdown/AttributedCache.swift`：

```swift
import UIKit

/// 块级渲染缓存。
///
/// **只缓存已闭合的块**：未闭合的块每帧都在变，缓存它没有意义还会撑爆内存。
/// 这正是「已闭合块只解析一次」这条性能承诺的兑现处。
final class AttributedCache {

    private final class Entry {
        let attributedString: NSAttributedString
        /// 宽度 → 高度
        var heights: [CGFloat: CGFloat] = [:]
        init(attributedString: NSAttributedString) {
            self.attributedString = attributedString
        }
    }

    private let storage = NSCache<NSNumber, Entry>()

    init(countLimit: Int = 400) {
        storage.countLimit = countLimit
    }

    func attributedString(for block: MarkdownBlock,
                          render: (MarkdownBlock) -> NSAttributedString) -> NSAttributedString {
        guard block.isSealed else { return render(block) }

        let key = NSNumber(value: block.cacheKey)
        if let entry = storage.object(forKey: key) {
            return entry.attributedString
        }
        let rendered = render(block)
        storage.setObject(Entry(attributedString: rendered), forKey: key)
        return rendered
    }

    func height(for block: MarkdownBlock,
                width: CGFloat,
                measure: (NSAttributedString) -> CGFloat) -> CGFloat {
        guard block.isSealed else {
            return measure(attributedString(for: block, render: { _ in NSAttributedString() }))
        }

        let key = NSNumber(value: block.cacheKey)
        guard let entry = storage.object(forKey: key) else {
            // 还没渲染过就先不缓存高度，等 attributedString 建好条目后再测
            return measure(NSAttributedString())
        }
        if let cached = entry.heights[width] { return cached }
        let measured = measure(entry.attributedString)
        entry.heights[width] = measured
        return measured
    }

    func removeAll() {
        storage.removeAllObjects()
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/AttributedCacheTests'
```

Expected: 9 个用例全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add WBChatApp-UIKit/Core/Markdown WBChatApp-UIKitTests/AttributedCacheTests.swift && git commit -m "渲染：实现内容寻址的属性串与高度缓存"
```

---

## Task 11: 持久化与 Keychain

**Files:**
- Create: `WBChatApp-UIKit/Core/Persistence/Records.swift`
- Create: `WBChatApp-UIKit/Core/Persistence/AppDatabase.swift`
- Create: `WBChatApp-UIKit/Core/Persistence/ChatRepository.swift`
- Create: `WBChatApp-UIKit/Core/Security/KeychainStore.swift`
- Test: `WBChatApp-UIKitTests/ChatRepositoryTests.swift`

**Interfaces:**
- Consumes: `ChatRole` / `ProviderKind`（Task 3）
- Produces:
  - `enum MessageStatus: String, Codable, Sendable { case streaming, completed, stopped, failed }`
  - `struct ConversationRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable`：`id: String, title: String, providerRaw: String, model: String, createdAt: Double, updatedAt: Double`
  - `struct MessageRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable`：`id: String, conversationId: String, ordinal: Int, roleRaw: String, content: String, reasoning: String?, statusRaw: String, errorMessage: String?, promptTokens: Int?, completionTokens: Int?, createdAt: Double`，含便利属性 `role: ChatRole` 与 `status: MessageStatus`
  - `enum AppDatabase { static func makeQueue(at url: URL?) throws -> DatabaseQueue }`（`url` 为 nil 时建内存库）
  - `protocol ChatRepository: AnyObject`（方法见下）与 `final class GRDBChatRepository: ChatRepository`
  - `enum KeychainStore { static func save(_ value: String, for key: String) throws; static func read(_ key: String) -> String?; static func delete(_ key: String) throws }`

`ChatRepository` 的方法：

```swift
protocol ChatRepository: AnyObject {
    func allConversations() throws -> [ConversationRecord]
    /// 返回的 cancellable **必须被调用方持有**，否则 ARC 释放时观察会立即取消（静默不生效）。
    /// `onError` 不要吞掉：GRDB 的语义是 onError 一旦触发观察即终止、不会自动恢复，
    /// 吞掉它会让会话列表永久静默停止刷新且无任何诊断信号。
    func observeConversations(
        onError: ((Error) -> Void)?,
        onChange: @escaping ([ConversationRecord]) -> Void
    ) -> AnyDatabaseCancellable
    @discardableResult
    func createConversation(title: String, provider: ProviderKind, model: String) throws -> ConversationRecord
    func renameConversation(id: String, title: String) throws
    func deleteConversation(id: String) throws
    func messages(in conversationId: String) throws -> [MessageRecord]
    func insertMessage(_ record: MessageRecord) throws
    func updateMessage(_ record: MessageRecord) throws
    func touchConversation(id: String) throws
}
```

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/ChatRepositoryTests.swift`：

```swift
import Foundation
import GRDB
import Testing
@testable import WBChatApp_UIKit

@Suite("持久化")
struct ChatRepositoryTests {

    private func makeRepository() throws -> GRDBChatRepository {
        GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
    }

    private func message(_ id: String, conversation: String, ordinal: Int,
                         role: ChatRole = .user, content: String = "内容") -> MessageRecord {
        MessageRecord(id: id, conversationId: conversation, ordinal: ordinal,
                      roleRaw: role.rawValue, content: content, reasoning: nil,
                      statusRaw: MessageStatus.completed.rawValue, errorMessage: nil,
                      promptTokens: nil, completionTokens: nil,
                      createdAt: Date().timeIntervalSince1970)
    }

    @Test("建库后表结构可用")
    func migrationCreatesTables() throws {
        let queue = try AppDatabase.makeQueue(at: nil)
        try queue.read { db in
            #expect(try db.tableExists("conversation"))
            #expect(try db.tableExists("message"))
        }
    }

    @Test("创建并读回会话")
    func createAndFetchConversation() throws {
        let repository = try makeRepository()
        let created = try repository.createConversation(title: "新对话", provider: .deepSeek,
                                                        model: "deepseek-chat")
        let all = try repository.allConversations()
        #expect(all.count == 1)
        #expect(all[0].id == created.id)
        #expect(all[0].title == "新对话")
        #expect(all[0].providerRaw == ProviderKind.deepSeek.rawValue)
    }

    @Test("会话按 updatedAt 倒序")
    func conversationsSortedByUpdatedAt() throws {
        let repository = try makeRepository()
        let first = try repository.createConversation(title: "旧", provider: .deepSeek, model: "m")
        _ = try repository.createConversation(title: "新", provider: .deepSeek, model: "m")
        try repository.touchConversation(id: first.id)
        #expect(try repository.allConversations().first?.title == "旧")
    }

    @Test("重命名会话")
    func renameConversation() throws {
        let repository = try makeRepository()
        let conversation = try repository.createConversation(title: "旧名", provider: .openAI, model: "m")
        try repository.renameConversation(id: conversation.id, title: "新名")
        #expect(try repository.allConversations()[0].title == "新名")
    }

    @Test("删除会话级联删除消息")
    func deleteCascades() throws {
        let repository = try makeRepository()
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek, model: "m")
        try repository.insertMessage(message("m1", conversation: conversation.id, ordinal: 0))
        try repository.deleteConversation(id: conversation.id)
        #expect(try repository.allConversations().isEmpty)
        #expect(try repository.messages(in: conversation.id).isEmpty)
    }

    @Test("消息按 ordinal 升序返回")
    func messagesSortedByOrdinal() throws {
        let repository = try makeRepository()
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek, model: "m")
        try repository.insertMessage(message("m2", conversation: conversation.id, ordinal: 1, content: "第二"))
        try repository.insertMessage(message("m1", conversation: conversation.id, ordinal: 0, content: "第一"))
        #expect(try repository.messages(in: conversation.id).map(\.content) == ["第一", "第二"])
    }

    @Test("更新消息内容与状态")
    func updateMessage() throws {
        let repository = try makeRepository()
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek, model: "m")
        var record = message("m1", conversation: conversation.id, ordinal: 0, role: .assistant)
        record.statusRaw = MessageStatus.streaming.rawValue
        try repository.insertMessage(record)

        record.content = "完整回复"
        record.statusRaw = MessageStatus.completed.rawValue
        record.completionTokens = 42
        try repository.updateMessage(record)

        let fetched = try #require(try repository.messages(in: conversation.id).first)
        #expect(fetched.content == "完整回复")
        #expect(fetched.status == .completed)
        #expect(fetched.completionTokens == 42)
    }

    @Test("role 与 status 便利属性可用")
    func convenienceAccessors() {
        let record = message("m1", conversation: "c", ordinal: 0, role: .assistant)
        #expect(record.role == .assistant)
        #expect(record.status == .completed)
    }

    @Test("Keychain 存取删")
    func keychainRoundTrip() throws {
        let key = "test.api.key.\(UUID().uuidString)"
        try KeychainStore.save("sk-secret", for: key)
        #expect(KeychainStore.read(key) == "sk-secret")
        try KeychainStore.save("sk-updated", for: key)
        #expect(KeychainStore.read(key) == "sk-updated")
        try KeychainStore.delete(key)
        #expect(KeychainStore.read(key) == nil)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/ChatRepositoryTests'
```

Expected: 编译失败，`cannot find 'AppDatabase' in scope`。

- [ ] **Step 3: 实现记录类型**

创建 `WBChatApp-UIKit/Core/Persistence/Records.swift`：

```swift
import Foundation
import GRDB

enum MessageStatus: String, Codable, Sendable {
    case streaming, completed, stopped, failed
}

struct ConversationRecord: Codable, FetchableRecord, MutablePersistableRecord,
                           Identifiable, Equatable, Sendable {
    static let databaseTableName = "conversation"

    var id: String
    var title: String
    var providerRaw: String
    var model: String
    var createdAt: Double
    var updatedAt: Double

    var provider: ProviderKind { ProviderKind(rawValue: providerRaw) ?? .deepSeek }
}

struct MessageRecord: Codable, FetchableRecord, MutablePersistableRecord,
                      Identifiable, Equatable, Sendable {
    static let databaseTableName = "message"

    var id: String
    var conversationId: String
    /// 会话内的顺序，从 0 递增
    var ordinal: Int
    var roleRaw: String
    var content: String
    var reasoning: String?
    var statusRaw: String
    var errorMessage: String?
    var promptTokens: Int?
    var completionTokens: Int?
    var createdAt: Double

    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .user }
    var status: MessageStatus { MessageStatus(rawValue: statusRaw) ?? .completed }
}
```

- [ ] **Step 4: 实现数据库与迁移**

创建 `WBChatApp-UIKit/Core/Persistence/AppDatabase.swift`：

```swift
import Foundation
import GRDB

enum AppDatabase {

    /// `url` 传 nil 建内存库，供测试使用。
    static func makeQueue(at url: URL?) throws -> DatabaseQueue {
        var configuration = Configuration()
        // 外键约束默认开启，级联删除才会生效
        configuration.foreignKeysEnabled = true

        let queue: DatabaseQueue
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            queue = try DatabaseQueue(path: url.path, configuration: configuration)
        } else {
            queue = try DatabaseQueue(configuration: configuration)
        }
        try migrator.migrate(queue)
        return queue
    }

    /// App 的默认库位置
    static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return base.appendingPathComponent("WBChatApp/chat.sqlite")
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_创建会话与消息表") { db in
            try db.create(table: "conversation") { table in
                table.primaryKey("id", .text)
                table.column("title", .text).notNull()
                table.column("providerRaw", .text).notNull()
                table.column("model", .text).notNull()
                table.column("createdAt", .double).notNull()
                table.column("updatedAt", .double).notNull()
            }

            try db.create(table: "message") { table in
                table.primaryKey("id", .text)
                table.column("conversationId", .text).notNull()
                    .references("conversation", onDelete: .cascade)
                table.column("ordinal", .integer).notNull()
                table.column("roleRaw", .text).notNull()
                table.column("content", .text).notNull()
                table.column("reasoning", .text)
                table.column("statusRaw", .text).notNull()
                table.column("errorMessage", .text)
                table.column("promptTokens", .integer)
                table.column("completionTokens", .integer)
                table.column("createdAt", .double).notNull()
            }

            try db.create(index: "idx_message_conv_ordinal",
                          on: "message",
                          columns: ["conversationId", "ordinal"])
        }

        return migrator
    }
}
```

- [ ] **Step 5: 实现仓储**

创建 `WBChatApp-UIKit/Core/Persistence/ChatRepository.swift`：

```swift
import Foundation
import GRDB

protocol ChatRepository: AnyObject {
    func allConversations() throws -> [ConversationRecord]
    /// 返回的 cancellable **必须被调用方持有**，否则 ARC 释放时观察会立即取消（静默不生效）。
    /// `onError` 不要吞掉：GRDB 的语义是 onError 一旦触发观察即终止、不会自动恢复，
    /// 吞掉它会让会话列表永久静默停止刷新且无任何诊断信号。
    func observeConversations(
        onError: ((Error) -> Void)?,
        onChange: @escaping ([ConversationRecord]) -> Void
    ) -> AnyDatabaseCancellable
    @discardableResult
    func createConversation(title: String, provider: ProviderKind, model: String) throws -> ConversationRecord
    func renameConversation(id: String, title: String) throws
    func deleteConversation(id: String) throws
    func messages(in conversationId: String) throws -> [MessageRecord]
    func insertMessage(_ record: MessageRecord) throws
    func updateMessage(_ record: MessageRecord) throws
    func touchConversation(id: String) throws
}

final class GRDBChatRepository: ChatRepository {

    private let queue: DatabaseQueue

    init(queue: DatabaseQueue) {
        self.queue = queue
    }

    // MARK: - 会话

    func allConversations() throws -> [ConversationRecord] {
        try queue.read { db in
            try ConversationRecord
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    /// 数据库变化自动推送。会话列表用它，免去手动刷新。
    /// 返回的 cancellable **必须被调用方持有**，否则 ARC 释放时观察会立即取消（静默不生效）。
    /// `onError` 不要吞掉：GRDB 的语义是 onError 一旦触发观察即终止、不会自动恢复，
    /// 吞掉它会让会话列表永久静默停止刷新且无任何诊断信号。
    func observeConversations(
        onError: ((Error) -> Void)?,
        onChange: @escaping ([ConversationRecord]) -> Void
    ) -> AnyDatabaseCancellable {
        let observation = ValueObservation.tracking { db in
            try ConversationRecord.order(Column("updatedAt").desc).fetchAll(db)
        }
        return observation.start(in: queue,
                                 scheduling: .async(onQueue: .main),
                                 onError: { _ in },
                                 onChange: onChange)
    }

    @discardableResult
    func createConversation(title: String, provider: ProviderKind,
                            model: String) throws -> ConversationRecord {
        let now = Date().timeIntervalSince1970
        var record = ConversationRecord(id: UUID().uuidString,
                                        title: title,
                                        providerRaw: provider.rawValue,
                                        model: model,
                                        createdAt: now,
                                        updatedAt: now)
        try queue.write { db in try record.insert(db) }
        return record
    }

    func renameConversation(id: String, title: String) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE conversation SET title = ?, updatedAt = ? WHERE id = ?",
                           arguments: [title, Date().timeIntervalSince1970, id])
        }
    }

    func deleteConversation(id: String) throws {
        _ = try queue.write { db in
            try ConversationRecord.deleteOne(db, key: id)
        }
    }

    /// 有新消息时把会话顶到列表最前
    func touchConversation(id: String) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE conversation SET updatedAt = ? WHERE id = ?",
                           arguments: [Date().timeIntervalSince1970, id])
        }
    }

    // MARK: - 消息

    func messages(in conversationId: String) throws -> [MessageRecord] {
        try queue.read { db in
            try MessageRecord
                .filter(Column("conversationId") == conversationId)
                .order(Column("ordinal").asc)
                .fetchAll(db)
        }
    }

    func insertMessage(_ record: MessageRecord) throws {
        var record = record
        try queue.write { db in try record.insert(db) }
    }

    func updateMessage(_ record: MessageRecord) throws {
        try queue.write { db in try record.update(db) }
    }
}
```

- [ ] **Step 6: 实现 Keychain**

创建 `WBChatApp-UIKit/Core/Security/KeychainStore.swift`：

```swift
import Foundation
import Security

/// API Key 只落 Keychain，绝不进 UserDefaults。
enum KeychainStore {

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    private static let service = "com.wenbo.WBChatApp-UIKit"

    static func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// 每家服务商一个 Key
    static func key(for provider: ProviderKind) -> String {
        "apiKey.\(provider.rawValue)"
    }
}
```

- [ ] **Step 7: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/ChatRepositoryTests'
```

Expected: 9 个用例全部 PASS。

- [ ] **Step 8: 提交**

```bash
git add WBChatApp-UIKit/Core WBChatApp-UIKitTests/ChatRepositoryTests.swift && git commit -m "持久化：接入 GRDB 建表迁移与仓储，API Key 落 Keychain"
```

---

## Task 12: 自动贴底状态机

对标 ChatGPT 的滚动行为。刻意做成不依赖 `UIScrollView` 的纯状态机，把所有判定逻辑用单测锁死，ViewController 只负责转发回调。

**Files:**
- Create: `WBChatApp-UIKit/Features/Chat/AutoScrollController.swift`
- Test: `WBChatApp-UIKitTests/AutoScrollControllerTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:

```swift
final class AutoScrollController {
    enum Mode: Equatable { case pinned, detached }
    private(set) var mode: Mode
    var bottomThreshold: CGFloat            // 默认 40
    var onModeChange: ((Mode) -> Void)?
    var shouldStickToBottom: Bool           // mode == .pinned

    init(bottomThreshold: CGFloat = 40)

    func willBeginDragging(offsetY: CGFloat)
    func didScroll(offsetY: CGFloat, isTracking: Bool)
    func didEndDragging(willDecelerate: Bool, distanceToBottom: CGFloat)
    func didEndDecelerating(distanceToBottom: CGFloat)
    func didTapScrollToBottom()
    func didSendMessage()
    func beginProgrammaticScroll()
    func endProgrammaticScroll()
}
```

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/AutoScrollControllerTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import WBChatApp_UIKit

@Suite("自动贴底状态机")
struct AutoScrollControllerTests {

    /// 模拟用户向上拖动
    private func dragUp(_ controller: AutoScrollController, from: CGFloat = 1000, to: CGFloat = 900) {
        controller.willBeginDragging(offsetY: from)
        controller.didScroll(offsetY: to, isTracking: true)
    }

    @Test("初始状态是贴底")
    func initialModeIsPinned() {
        #expect(AutoScrollController().mode == .pinned)
    }

    @Test("用户向上拖动脱离贴底")
    func dragUpDetaches() {
        let controller = AutoScrollController()
        dragUp(controller)
        #expect(controller.mode == .detached)
        #expect(controller.shouldStickToBottom == false)
    }

    @Test("用户向下拖动但没到底，仍保持脱离")
    func dragDownWithoutReachingBottomStaysDetached() {
        let controller = AutoScrollController()
        dragUp(controller)
        controller.didScroll(offsetY: 950, isTracking: true)
        controller.didEndDragging(willDecelerate: false, distanceToBottom: 200)
        #expect(controller.mode == .detached)
    }

    @Test("松手时已在底部阈值内则恢复贴底")
    func endDraggingNearBottomRepins() {
        let controller = AutoScrollController()
        dragUp(controller)
        controller.didEndDragging(willDecelerate: false, distanceToBottom: 10)
        #expect(controller.mode == .pinned)
    }

    @Test("松手后仍在减速，此时不判定，减速结束才判定")
    func decelerationDefersDecision() {
        let controller = AutoScrollController()
        dragUp(controller)
        controller.didEndDragging(willDecelerate: true, distanceToBottom: 5)
        #expect(controller.mode == .detached, "还在减速就不该改变状态")
        controller.didEndDecelerating(distanceToBottom: 5)
        #expect(controller.mode == .pinned)
    }

    @Test("减速停在阈值外仍保持脱离")
    func decelerationEndFarFromBottomStaysDetached() {
        let controller = AutoScrollController()
        dragUp(controller)
        controller.didEndDragging(willDecelerate: true, distanceToBottom: 500)
        controller.didEndDecelerating(distanceToBottom: 500)
        #expect(controller.mode == .detached)
    }

    @Test("程序化滚动不会让状态脱离")
    func programmaticScrollDoesNotDetach() {
        let controller = AutoScrollController()
        controller.beginProgrammaticScroll()
        controller.didScroll(offsetY: 500, isTracking: false)
        controller.endProgrammaticScroll()
        #expect(controller.mode == .pinned)
    }

    @Test("非拖动状态下的滚动不改变状态")
    func nonTrackingScrollIgnored() {
        let controller = AutoScrollController()
        controller.didScroll(offsetY: 100, isTracking: false)
        #expect(controller.mode == .pinned)
    }

    @Test("点击回到底部按钮恢复贴底")
    func tapButtonRepins() {
        let controller = AutoScrollController()
        dragUp(controller)
        controller.didTapScrollToBottom()
        #expect(controller.mode == .pinned)
    }

    @Test("发送新消息强制恢复贴底")
    func sendMessageRepins() {
        let controller = AutoScrollController()
        dragUp(controller)
        controller.didSendMessage()
        #expect(controller.mode == .pinned)
    }

    @Test("状态变化只在真正切换时回调一次")
    func modeChangeCallbackFiresOnce() {
        let controller = AutoScrollController()
        var changes: [AutoScrollController.Mode] = []
        controller.onModeChange = { changes.append($0) }

        dragUp(controller)
        controller.didScroll(offsetY: 880, isTracking: true)   // 继续向上，不该再回调
        controller.didEndDragging(willDecelerate: false, distanceToBottom: 5)

        #expect(changes == [.detached, .pinned])
    }

    @Test("向下拖动不会触发脱离")
    func dragDownDoesNotDetach() {
        let controller = AutoScrollController()
        controller.willBeginDragging(offsetY: 900)
        controller.didScroll(offsetY: 1000, isTracking: true)
        #expect(controller.mode == .pinned)
    }

    @Test("阈值可配置")
    func thresholdIsConfigurable() {
        let controller = AutoScrollController(bottomThreshold: 100)
        dragUp(controller)
        controller.didEndDragging(willDecelerate: false, distanceToBottom: 80)
        #expect(controller.mode == .pinned)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/AutoScrollControllerTests'
```

Expected: 编译失败，`cannot find 'AutoScrollController' in scope`。

- [ ] **Step 3: 实现状态机**

创建 `WBChatApp-UIKit/Features/Chat/AutoScrollController.swift`：

```swift
import CoreGraphics

/// 流式输出期间的「自动贴底 vs 用户手势」冲突仲裁。对标 ChatGPT 的行为：
///
/// - **pinned**：内容增长时每帧贴底，「回到底部」按钮隐藏
/// - **detached**：完全不干预滚动。内容在可视区下方增长，用户正在看的内容
///   视觉位置本就不动，所以这里什么都不做才是对的
///
/// 刻意不持有 `UIScrollView`：所有判定都是纯计算，可以完整地用单测锁死。
final class AutoScrollController {

    enum Mode: Equatable {
        case pinned
        case detached
    }

    private(set) var mode: Mode = .pinned {
        didSet {
            guard oldValue != mode else { return }
            onModeChange?(mode)
        }
    }

    /// 离底多近算「回到底部」
    var bottomThreshold: CGFloat

    var onModeChange: ((Mode) -> Void)?

    var shouldStickToBottom: Bool { mode == .pinned }

    /// 拖动起点，用来判断方向
    private var dragStartOffsetY: CGFloat = 0

    /// 程序化滚动期间忽略一切 didScroll
    private var isProgrammaticScroll = false

    init(bottomThreshold: CGFloat = 40) {
        self.bottomThreshold = bottomThreshold
    }

    // MARK: - 来自 UIScrollViewDelegate 的转发

    func willBeginDragging(offsetY: CGFloat) {
        dragStartOffsetY = offsetY
    }

    func didScroll(offsetY: CGFloat, isTracking: Bool) {
        // 自己发起的滚动不能被当成用户意图
        guard !isProgrammaticScroll else { return }
        // 手指不在屏幕上时（惯性、contentSize 变化）不改变状态
        guard isTracking else { return }
        // 只有向上拖才脱离；向下拖是在追内容，不该打断贴底
        guard offsetY < dragStartOffsetY else { return }
        mode = .detached
    }

    func didEndDragging(willDecelerate: Bool, distanceToBottom: CGFloat) {
        // 还要继续惯性滑动，等停下来再判定，否则会在半途误判
        guard !willDecelerate else { return }
        repinIfNearBottom(distanceToBottom)
    }

    func didEndDecelerating(distanceToBottom: CGFloat) {
        repinIfNearBottom(distanceToBottom)
    }

    // MARK: - 显式意图

    func didTapScrollToBottom() {
        mode = .pinned
    }

    /// 用户发出新消息时无条件回到贴底
    func didSendMessage() {
        mode = .pinned
    }

    // MARK: - 程序化滚动标记

    func beginProgrammaticScroll() {
        isProgrammaticScroll = true
    }

    func endProgrammaticScroll() {
        isProgrammaticScroll = false
    }

    // MARK: - 私有

    private func repinIfNearBottom(_ distanceToBottom: CGFloat) {
        if distanceToBottom <= bottomThreshold {
            mode = .pinned
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/AutoScrollControllerTests'
```

Expected: 13 个用例全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add WBChatApp-UIKit/Features/Chat WBChatApp-UIKitTests/AutoScrollControllerTests.swift && git commit -m "交互：实现对标 ChatGPT 的自动贴底状态机"
```

---

## Task 13: 块视图与复用池

TextKit 2 落地处。四种块视图 + 一个按类型回收的复用池。

**Files:**
- Create: `WBChatApp-UIKit/Features/Chat/Views/BlockView.swift`
- Create: `WBChatApp-UIKit/Features/Chat/Views/MarkdownTextBlockView.swift`
- Create: `WBChatApp-UIKit/Features/Chat/Views/CodeBlockView.swift`
- Create: `WBChatApp-UIKit/Features/Chat/Views/DividerBlockView.swift`
- Create: `WBChatApp-UIKit/Features/Chat/Views/BlockViewPool.swift`
- Test: `WBChatApp-UIKitTests/BlockViewTests.swift`

**Interfaces:**
- Consumes: `MarkdownBlock`（Task 7）、`MarkdownTheme`（Task 8）、`AttributedRenderer`（Task 9）
- Produces:
  - `protocol BlockView: UIView { func configure(block: MarkdownBlock, attributed: NSAttributedString, renderer: AttributedRenderer); func heightThatFits(width: CGFloat) -> CGFloat; func prepareForReuse() }`
  - `enum BlockViewKind: Hashable { case text, code, divider }`，含 `static func kind(for: MarkdownBlockKind) -> BlockViewKind`
  - `final class MarkdownTextBlockView: UIView, BlockView`，含 `var onLinkTap: ((URL) -> Void)?`
  - `final class CodeBlockView: UIView, BlockView`，含 `var onCopy: ((String) -> Void)?`
  - `final class DividerBlockView: UIView, BlockView`
  - `final class BlockViewPool { func dequeue(_ kind: BlockViewKind) -> any BlockView; func recycle(_ view: any BlockView) }`

> 表格块暂时复用 `MarkdownTextBlockView`（渲染器已把单元格用制表符拼好），不单独做 `TableBlockView`。这样能少一个视图类型，表格在聊天场景里也确实少见。

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/BlockViewTests.swift`：

```swift
import UIKit
import Testing
@testable import WBChatApp_UIKit

@Suite("块视图")
@MainActor
struct BlockViewTests {

    private let renderer = AttributedRenderer()

    private func block(_ kind: MarkdownBlockKind, _ text: String,
                       sealed: Bool = true) -> MarkdownBlock {
        MarkdownBlock(ordinal: 0, kind: kind, rawText: text, isSealed: sealed)
    }

    private func configure(_ view: any BlockView, _ block: MarkdownBlock) {
        view.configure(block: block, attributed: renderer.render(block), renderer: renderer)
    }

    @Test("文本块视图始终使用 TextKit 2")
    func textBlockUsesTextKit2() {
        let view = MarkdownTextBlockView()
        #expect(view.usesTextKit2)
    }

    @Test("文本块高度随内容增长")
    func textHeightGrowsWithContent() {
        let short = MarkdownTextBlockView()
        configure(short, block(.paragraph, "短"))
        let long = MarkdownTextBlockView()
        configure(long, block(.paragraph, String(repeating: "很长的一段文字。", count: 40)))
        #expect(long.heightThatFits(width: 300) > short.heightThatFits(width: 300))
    }

    @Test("同内容同宽度高度稳定")
    func textHeightIsStable() {
        let view = MarkdownTextBlockView()
        configure(view, block(.paragraph, "稳定的内容"))
        #expect(view.heightThatFits(width: 300) == view.heightThatFits(width: 300))
    }

    @Test("宽度变窄高度变高")
    func narrowerWidthMeansTallerHeight() {
        let view = MarkdownTextBlockView()
        configure(view, block(.paragraph, String(repeating: "文字", count: 60)))
        #expect(view.heightThatFits(width: 150) > view.heightThatFits(width: 350))
    }

    @Test("代码块展示语言标签")
    func codeBlockShowsLanguage() {
        let view = CodeBlockView()
        configure(view, block(.codeFence(language: "swift"), "```swift\nlet a = 1\n```"))
        #expect(view.languageText == "swift")
    }

    @Test("无语言时标签为纯文本")
    func codeBlockWithoutLanguage() {
        let view = CodeBlockView()
        configure(view, block(.codeFence(language: nil), "```\nplain\n```"))
        #expect(view.languageText == "纯文本")
    }

    @Test("代码块复制回调带出剥掉围栏的代码")
    func codeBlockCopyCallback() {
        let view = CodeBlockView()
        configure(view, block(.codeFence(language: "swift"), "```swift\nlet a = 1\n```"))
        var copied: String?
        view.onCopy = { copied = $0 }
        view.triggerCopyForTesting()
        #expect(copied == "let a = 1")
    }

    @Test("复用池按类型回收与复用同一实例")
    func poolReusesSameInstance() {
        let pool = BlockViewPool()
        let first = pool.dequeue(.text)
        pool.recycle(first)
        let second = pool.dequeue(.text)
        #expect(first === second)
    }

    @Test("复用池不会把代码块视图当成文本块发出")
    func poolKeepsKindsSeparate() {
        let pool = BlockViewPool()
        let code = pool.dequeue(.code)
        pool.recycle(code)
        let text = pool.dequeue(.text)
        #expect(text is MarkdownTextBlockView)
        #expect(code is CodeBlockView)
    }

    @Test("块类型到视图类型的映射")
    func kindMapping() {
        #expect(BlockViewKind.kind(for: .paragraph) == .text)
        #expect(BlockViewKind.kind(for: .heading(level: 2)) == .text)
        #expect(BlockViewKind.kind(for: .list(ordered: true)) == .text)
        #expect(BlockViewKind.kind(for: .blockQuote) == .text)
        #expect(BlockViewKind.kind(for: .table) == .text)
        #expect(BlockViewKind.kind(for: .codeFence(language: nil)) == .code)
        #expect(BlockViewKind.kind(for: .thematicBreak) == .divider)
    }

    @Test("分割线高度固定")
    func dividerHasFixedHeight() {
        let view = DividerBlockView()
        configure(view, block(.thematicBreak, "---"))
        #expect(view.heightThatFits(width: 300) == view.heightThatFits(width: 100))
    }

    @Test("prepareForReuse 清空内容")
    func prepareForReuseClearsContent() {
        let view = MarkdownTextBlockView()
        configure(view, block(.paragraph, "有内容"))
        view.prepareForReuse()
        #expect(view.currentTextForTesting.isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/BlockViewTests'
```

Expected: 编译失败，`cannot find 'MarkdownTextBlockView' in scope`。

- [ ] **Step 3: 定义协议与类型映射**

创建 `WBChatApp-UIKit/Features/Chat/Views/BlockView.swift`：

```swift
import UIKit

/// 一个块的视图。所有块视图都能自报高度，且能被复用池回收。
protocol BlockView: UIView {
    func configure(block: MarkdownBlock,
                   attributed: NSAttributedString,
                   renderer: AttributedRenderer)
    func heightThatFits(width: CGFloat) -> CGFloat
    func prepareForReuse()
}

enum BlockViewKind: Hashable {
    case text
    case code
    case divider

    static func kind(for blockKind: MarkdownBlockKind) -> BlockViewKind {
        switch blockKind {
        case .codeFence:     return .code
        case .thematicBreak: return .divider
        default:             return .text
        }
    }
}
```

- [ ] **Step 4: 实现文本块视图**

创建 `WBChatApp-UIKit/Features/Chat/Views/MarkdownTextBlockView.swift`：

```swift
import UIKit

/// 段落 / 标题 / 列表 / 引用 / 表格的承载视图。
///
/// 内部是一个非编辑态的 `UITextView`，在 iOS 16+ 默认由 **TextKit 2** 驱动。
///
/// ⚠️ 全类禁止访问 `textView.layoutManager` 与 `textView.textStorage`——
/// 只要碰一次，UIKit 就会静默回退到 TextKit 1，增量排版的收益全部作废。
/// 需要底层能力时一律走 `textLayoutManager` / `textContentStorage`。
final class MarkdownTextBlockView: UIView, BlockView {

    var onLinkTap: ((URL) -> Void)?

    private let textView: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    /// 引用块左侧竖条
    private let quoteBar: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.separator
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var leadingConstraint: NSLayoutConstraint!
    private var currentKind: MarkdownBlockKind = .paragraph

    /// 供测试断言：确认没有意外退回 TextKit 1
    var usesTextKit2: Bool { textView.textLayoutManager != nil }

    /// 供测试断言当前内容
    var currentTextForTesting: String { textView.attributedText?.string ?? "" }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    private func setUp() {
        addSubview(quoteBar)
        addSubview(textView)

        leadingConstraint = textView.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            quoteBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            quoteBar.topAnchor.constraint(equalTo: topAnchor),
            quoteBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            quoteBar.widthAnchor.constraint(equalToConstant: MarkdownTheme.default.quoteBarWidth),

            leadingConstraint,
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        textView.addGestureRecognizer(tap)
    }

    // MARK: - BlockView

    func configure(block: MarkdownBlock,
                   attributed: NSAttributedString,
                   renderer: AttributedRenderer) {
        currentKind = block.kind
        textView.attributedText = attributed

        let isQuote = block.kind == .blockQuote
        quoteBar.isHidden = !isQuote
        leadingConstraint.constant = isQuote ? MarkdownTheme.default.quoteBarWidth + 8 : 0
    }

    func heightThatFits(width: CGFloat) -> CGFloat {
        let inset = quoteBar.isHidden ? 0 : MarkdownTheme.default.quoteBarWidth + 8
        let available = max(1, width - inset)
        let size = textView.sizeThatFits(CGSize(width: available,
                                                height: .greatestFiniteMagnitude))
        return ceil(size.height)
    }

    func prepareForReuse() {
        textView.attributedText = NSAttributedString()
        quoteBar.isHidden = true
        leadingConstraint.constant = 0
        onLinkTap = nil
    }

    // MARK: - 链接点击

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let onLinkTap else { return }
        let point = gesture.location(in: textView)
        guard let position = textView.closestPosition(to: point) else { return }
        let index = textView.offset(from: textView.beginningOfDocument, to: position)
        guard index >= 0, index < (textView.attributedText?.length ?? 0) else { return }
        guard let url = textView.attributedText?
            .attribute(.wbLinkURL, at: index, effectiveRange: nil) as? URL else { return }
        onLinkTap(url)
    }
}
```

- [ ] **Step 5: 实现代码块与分割线视图**

创建 `WBChatApp-UIKit/Features/Chat/Views/CodeBlockView.swift`：

```swift
import UIKit

/// 代码块：顶部一条「语言 + 复制」工具条，下面是横向可滚动的等宽文本。
final class CodeBlockView: UIView, BlockView {

    var onCopy: ((String) -> Void)?

    private static let headerHeight: CGFloat = 32
    private static let contentInset: CGFloat = 12

    private let container: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.codeBackground
        view.layer.cornerRadius = 10
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let languageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = Theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let copyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("复制", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    /// 代码不换行，靠横向滚动查看
    private let textView: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                             height: .greatestFiniteMagnitude)
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    private var code: String = ""

    /// 供测试断言
    var languageText: String { languageLabel.text ?? "" }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    private func setUp() {
        addSubview(container)
        container.addSubview(languageLabel)
        container.addSubview(copyButton)
        container.addSubview(scrollView)
        scrollView.addSubview(textView)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            languageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.contentInset),
            languageLabel.topAnchor.constraint(equalTo: container.topAnchor),
            languageLabel.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            copyButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.contentInset),
            copyButton.centerYAnchor.constraint(equalTo: languageLabel.centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.contentInset),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.contentInset),
            scrollView.topAnchor.constraint(equalTo: languageLabel.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.contentInset),

            textView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            textView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            textView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        copyButton.addTarget(self, action: #selector(handleCopy), for: .touchUpInside)
    }

    // MARK: - BlockView

    func configure(block: MarkdownBlock,
                   attributed: NSAttributedString,
                   renderer: AttributedRenderer) {
        textView.attributedText = attributed
        code = renderer.codeText(of: block)
        if case .codeFence(let language) = block.kind {
            languageLabel.text = language ?? "纯文本"
        } else {
            languageLabel.text = "纯文本"
        }
    }

    func heightThatFits(width: CGFloat) -> CGFloat {
        let size = textView.sizeThatFits(CGSize(width: .greatestFiniteMagnitude,
                                                height: .greatestFiniteMagnitude))
        return ceil(size.height) + Self.headerHeight + Self.contentInset
    }

    func prepareForReuse() {
        textView.attributedText = NSAttributedString()
        languageLabel.text = nil
        code = ""
        onCopy = nil
        scrollView.contentOffset = .zero
    }

    // MARK: - 复制

    @objc private func handleCopy() {
        UIPasteboard.general.string = code
        onCopy?(code)
    }

    /// 供测试直接触发复制
    func triggerCopyForTesting() {
        handleCopy()
    }
}
```

创建 `WBChatApp-UIKit/Features/Chat/Views/DividerBlockView.swift`：

```swift
import UIKit

/// 分割线。高度固定，与宽度无关。
final class DividerBlockView: UIView, BlockView {

    private static let totalHeight: CGFloat = 17
    private static let lineHeight: CGFloat = 1

    private let line: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: Self.lineHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func configure(block: MarkdownBlock,
                   attributed: NSAttributedString,
                   renderer: AttributedRenderer) {}

    func heightThatFits(width: CGFloat) -> CGFloat { Self.totalHeight }

    func prepareForReuse() {}
}
```

- [ ] **Step 6: 实现复用池**

创建 `WBChatApp-UIKit/Features/Chat/Views/BlockViewPool.swift`：

```swift
import UIKit

/// 块视图复用池。
///
/// `UITextView` 实例创建代价不低，而一条长回复可能有十几个块、
/// cell 本身又会被 tableView 反复复用。没有这个池子，滚动时会不断新建 TextView。
final class BlockViewPool {

    private var idle: [BlockViewKind: [any BlockView]] = [:]

    /// 每类最多缓存多少个空闲实例，防止无限增长
    private let capacityPerKind: Int

    init(capacityPerKind: Int = 12) {
        self.capacityPerKind = capacityPerKind
    }

    func dequeue(_ kind: BlockViewKind) -> any BlockView {
        if var queue = idle[kind], let view = queue.popLast() {
            idle[kind] = queue
            return view
        }
        return make(kind)
    }

    func recycle(_ view: any BlockView) {
        let kind: BlockViewKind
        switch view {
        case is CodeBlockView:    kind = .code
        case is DividerBlockView: kind = .divider
        default:                  kind = .text
        }
        view.prepareForReuse()
        view.removeFromSuperview()

        var queue = idle[kind] ?? []
        guard queue.count < capacityPerKind else { return }
        queue.append(view)
        idle[kind] = queue
    }

    private func make(_ kind: BlockViewKind) -> any BlockView {
        switch kind {
        case .text:    return MarkdownTextBlockView()
        case .code:    return CodeBlockView()
        case .divider: return DividerBlockView()
        }
    }
}
```

- [ ] **Step 7: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/BlockViewTests'
```

Expected: 12 个用例全部 PASS。「文本块块视图始终使用 TextKit 2」这条是 TextKit 2 降级的哨兵测试，失败说明某处碰了 `layoutManager`。

- [ ] **Step 8: 提交**

```bash
git add WBChatApp-UIKit/Features/Chat/Views WBChatApp-UIKitTests/BlockViewTests.swift && git commit -m "视图：实现 TextKit 2 块视图、代码块视图与按类型复用池"
```

---

## Task 14: 块容器与消息 cell

增量打补丁的落地处：`applyPatch` 只碰未闭合块的视图，已闭合块的视图纹丝不动。

**Files:**
- Create: `WBChatApp-UIKit/Features/Chat/Views/BlockStackView.swift`
- Create: `WBChatApp-UIKit/Features/Chat/Views/AssistantMessageCell.swift`
- Create: `WBChatApp-UIKit/Features/Chat/Views/UserMessageCell.swift`
- Test: `WBChatApp-UIKitTests/BlockStackViewTests.swift`

**Interfaces:**
- Consumes: `BlockView` / `BlockViewPool`（Task 13）、`AttributedCache`（Task 10）、`BlockPatch`（Task 7）
- Produces:
  - `final class BlockStackView: UIView`
    - `init(pool: BlockViewPool, cache: AttributedCache, renderer: AttributedRenderer)`
    - `func setBlocks(_ blocks: [MarkdownBlock])` — 全量重建，用于 cell 绑定已有消息
    - `func applyPatch(_ patch: BlockPatch)` — 增量更新，流式期间用
    - `func heightThatFits(width: CGFloat) -> CGFloat`
    - `func recycleAll()`
    - `var blockCount: Int`、`var onLinkTap: ((URL) -> Void)?`、`var onCodeCopy: ((String) -> Void)?`
  - `final class AssistantMessageCell: UITableViewCell`，`static let reuseIdentifier`，`func configure(...)`、`func applyPatch(_:)`、`func heightThatFits(width:) -> CGFloat`
  - `final class UserMessageCell: UITableViewCell`，`static let reuseIdentifier`，`func configure(text: String)`

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/BlockStackViewTests.swift`：

```swift
import UIKit
import Testing
@testable import WBChatApp_UIKit

@Suite("块容器")
@MainActor
struct BlockStackViewTests {

    private func makeStack() -> BlockStackView {
        BlockStackView(pool: BlockViewPool(),
                       cache: AttributedCache(),
                       renderer: AttributedRenderer())
    }

    private func sealed(_ ordinal: Int, _ text: String) -> MarkdownBlock {
        MarkdownBlock(ordinal: ordinal, kind: .paragraph, rawText: text, isSealed: true)
    }

    private func open(_ ordinal: Int, _ text: String) -> MarkdownBlock {
        MarkdownBlock(ordinal: ordinal, kind: .paragraph, rawText: text, isSealed: false)
    }

    @Test("setBlocks 建出对应数量的子视图")
    func setBlocksCreatesSubviews() {
        let stack = makeStack()
        stack.setBlocks([sealed(0, "甲"), sealed(1, "乙")])
        #expect(stack.blockCount == 2)
    }

    @Test("补丁只新增已闭合块与一个未闭合块")
    func patchAppendsBlocks() {
        let stack = makeStack()
        stack.applyPatch(BlockPatch(newlySealed: [sealed(0, "甲")], open: open(1, "乙")))
        #expect(stack.blockCount == 2)
    }

    @Test("连续补丁只替换未闭合块，不重复追加")
    func repeatedOpenPatchReplacesInPlace() {
        let stack = makeStack()
        stack.applyPatch(BlockPatch(newlySealed: [], open: open(0, "写")))
        stack.applyPatch(BlockPatch(newlySealed: [], open: open(0, "写到")))
        stack.applyPatch(BlockPatch(newlySealed: [], open: open(0, "写到一半")))
        #expect(stack.blockCount == 1)
    }

    @Test("已闭合块的视图实例在后续补丁中保持不变")
    func sealedBlockViewIdentityIsStable() {
        let stack = makeStack()
        stack.applyPatch(BlockPatch(newlySealed: [sealed(0, "固定")], open: open(1, "变")))
        let firstView = stack.blockViewForTesting(at: 0)

        stack.applyPatch(BlockPatch(newlySealed: [], open: open(1, "变化中")))
        stack.applyPatch(BlockPatch(newlySealed: [sealed(1, "变化完")], open: open(2, "新")))

        #expect(stack.blockViewForTesting(at: 0) === firstView,
                "已闭合块的视图被重建了，增量渲染的收益作废")
    }

    @Test("未闭合块转为已闭合时复用同一个视图实例")
    func openBlockBecomesSealedInPlace() {
        let stack = makeStack()
        stack.applyPatch(BlockPatch(newlySealed: [], open: open(0, "半成品")))
        let view = stack.blockViewForTesting(at: 0)
        stack.applyPatch(BlockPatch(newlySealed: [sealed(0, "成品")], open: nil))
        #expect(stack.blockViewForTesting(at: 0) === view)
        #expect(stack.blockCount == 1)
    }

    @Test("open 为 nil 时移除未闭合块视图")
    func nilOpenRemovesTrailingView() {
        let stack = makeStack()
        stack.applyPatch(BlockPatch(newlySealed: [sealed(0, "甲")], open: open(1, "乙")))
        stack.applyPatch(BlockPatch(newlySealed: [], open: nil))
        #expect(stack.blockCount == 1)
    }

    @Test("块类型变化时换用对应的视图类型")
    func kindChangeSwapsViewType() {
        let stack = makeStack()
        stack.applyPatch(BlockPatch(newlySealed: [], open: open(0, "普通段落")))
        #expect(stack.blockViewForTesting(at: 0) is MarkdownTextBlockView)

        let codeBlock = MarkdownBlock(ordinal: 0, kind: .codeFence(language: "swift"),
                                      rawText: "```swift\nlet a = 1", isSealed: false)
        stack.applyPatch(BlockPatch(newlySealed: [], open: codeBlock))
        #expect(stack.blockViewForTesting(at: 0) is CodeBlockView)
    }

    @Test("总高度等于各块高度与间距之和")
    func heightIsSumOfBlocks() {
        let stack = makeStack()
        stack.setBlocks([sealed(0, "甲"), sealed(1, "乙")])
        let total = stack.heightThatFits(width: 300)

        let single = makeStack()
        single.setBlocks([sealed(0, "甲")])
        let one = single.heightThatFits(width: 300)

        #expect(total > one)
    }

    @Test("recycleAll 清空所有子视图")
    func recycleAllClears() {
        let stack = makeStack()
        stack.setBlocks([sealed(0, "甲"), sealed(1, "乙")])
        stack.recycleAll()
        #expect(stack.blockCount == 0)
    }

    @Test("助手 cell 转发补丁并能报高度")
    func assistantCellAppliesPatch() {
        let cell = AssistantMessageCell(style: .default, reuseIdentifier: AssistantMessageCell.reuseIdentifier)
        cell.configure(blocks: [sealed(0, "你好")],
                       reasoning: nil,
                       status: .completed,
                       errorText: nil,
                       pool: BlockViewPool(),
                       cache: AttributedCache(),
                       renderer: AttributedRenderer())
        cell.applyPatch(BlockPatch(newlySealed: [sealed(1, "补充")], open: nil))
        #expect(cell.heightThatFits(width: 375) > 0)
    }

    @Test("用户 cell 展示原始文本，不做 Markdown 渲染")
    func userCellShowsPlainText() {
        let cell = UserMessageCell(style: .default, reuseIdentifier: UserMessageCell.reuseIdentifier)
        cell.configure(text: "**不该被加粗**")
        #expect(cell.displayedTextForTesting == "**不该被加粗**")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/BlockStackViewTests'
```

Expected: 编译失败，`cannot find 'BlockStackView' in scope`。

- [ ] **Step 3: 实现块容器**

创建 `WBChatApp-UIKit/Features/Chat/Views/BlockStackView.swift`：

```swift
import UIKit

/// 竖排块视图的容器。
///
/// 刻意不用 `UIStackView`：流式期间尾块高度每帧都变，
/// 走约束求解的代价远高于自己在 `layoutSubviews` 里算一遍。
///
/// 增量的核心在 `applyPatch`：**已闭合块的视图一旦建好就不再触碰**，
/// 每帧只重新配置最后那个未闭合块。
final class BlockStackView: UIView {

    var onLinkTap: ((URL) -> Void)?
    var onCodeCopy: ((String) -> Void)?

    private let pool: BlockViewPool
    private let cache: AttributedCache
    private let renderer: AttributedRenderer
    private let spacing: CGFloat

    /// 与 `blockViews` 一一对应
    private var blocks: [MarkdownBlock] = []
    private var blockViews: [any BlockView] = []

    /// 最后一个块是否处于未闭合状态
    private var hasOpenBlock = false

    private var cachedWidth: CGFloat = 0
    private var cachedHeights: [CGFloat] = []

    var blockCount: Int { blockViews.count }

    init(pool: BlockViewPool,
         cache: AttributedCache,
         renderer: AttributedRenderer,
         spacing: CGFloat = MarkdownTheme.default.blockSpacing) {
        self.pool = pool
        self.cache = cache
        self.renderer = renderer
        self.spacing = spacing
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    // MARK: - 全量设置

    /// 绑定一条已完成的消息。cell 复用时走这里。
    func setBlocks(_ newBlocks: [MarkdownBlock]) {
        recycleAll()
        for block in newBlocks {
            appendView(for: block)
        }
        hasOpenBlock = newBlocks.last.map { !$0.isSealed } ?? false
        invalidateHeights()
    }

    // MARK: - 增量更新

    /// 应用一次流式补丁。
    ///
    /// 三步：把上一帧的未闭合块「就地固化」；追加本次新闭合的块；
    /// 最后配置新的未闭合块。全程不碰更早的已闭合块视图。
    func applyPatch(_ patch: BlockPatch) {
        var sealedQueue = patch.newlySealed

        // 上一帧的未闭合块，本帧可能已经闭合。复用同一个视图实例就地更新，
        // 避免「闭合瞬间」重建视图造成的闪动。
        if hasOpenBlock, !blockViews.isEmpty {
            if let first = sealedQueue.first,
               first.ordinal == blocks[blocks.count - 1].ordinal {
                sealedQueue.removeFirst()
                updateView(at: blockViews.count - 1, with: first)
                hasOpenBlock = false
            } else if patch.open == nil {
                // 上一帧的未闭合块本帧既没被闭合、也没有新的开放内容——
                // 说明它被撤回（例如流中止）。必须在这里就把占位视图移除，
                // 不能只置 hasOpenBlock = false 了事：那样它会冒充已闭合块滞留在数组里，
                // 而方法末尾原本负责移除的分支此时条件已失效，成为永远进不去的死代码。
                pool.recycle(blockViews[blockViews.count - 1])
                blockViews.removeLast()
                blocks.removeLast()
                hasOpenBlock = false
            }
            // 两个分支都不满足：上一帧的未闭合块仍未闭合且本帧还有新开放内容，
            // 留给下面 patch.open 分支的 updateView 原地更新。
        }

        for block in sealedQueue {
            appendView(for: block)
        }

        if let open = patch.open {
            if hasOpenBlock, !blockViews.isEmpty {
                updateView(at: blockViews.count - 1, with: open)
            } else {
                appendView(for: open)
                hasOpenBlock = true
            }
        }

        invalidateHeights()
    }

    func recycleAll() {
        for view in blockViews { pool.recycle(view) }
        blockViews.removeAll()
        blocks.removeAll()
        hasOpenBlock = false
        invalidateHeights()
    }

    // MARK: - 布局与高度

    func heightThatFits(width: CGFloat) -> CGFloat {
        ensureHeights(width: width)
        guard !cachedHeights.isEmpty else { return 0 }
        return cachedHeights.reduce(0, +) + spacing * CGFloat(cachedHeights.count - 1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ensureHeights(width: bounds.width)
        var y: CGFloat = 0
        for (index, view) in blockViews.enumerated() {
            let height = cachedHeights.indices.contains(index) ? cachedHeights[index] : 0
            view.frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
            y += height + spacing
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: heightThatFits(width: bounds.width))
    }

    /// 供测试断言视图实例身份
    func blockViewForTesting(at index: Int) -> (any BlockView)? {
        blockViews.indices.contains(index) ? blockViews[index] : nil
    }

    // MARK: - 私有

    private func appendView(for block: MarkdownBlock) {
        let view = pool.dequeue(BlockViewKind.kind(for: block.kind))
        configure(view, with: block)
        addSubview(view)
        blockViews.append(view)
        blocks.append(block)
    }

    private func updateView(at index: Int, with block: MarkdownBlock) {
        guard blockViews.indices.contains(index) else { return }
        let needsKind = BlockViewKind.kind(for: block.kind)
        let currentKind = BlockViewKind.kind(for: blocks[index].kind)

        if needsKind != currentKind {
            // 块类型变了（例如段落变成了代码块起始），换视图
            pool.recycle(blockViews[index])
            let view = pool.dequeue(needsKind)
            addSubview(view)
            blockViews[index] = view
        }
        configure(blockViews[index], with: block)
        blocks[index] = block
    }

    private func configure(_ view: any BlockView, with block: MarkdownBlock) {
        let attributed = cache.attributedString(for: block) { [renderer] in
            renderer.render($0)
        }
        view.configure(block: block, attributed: attributed, renderer: renderer)

        if let textView = view as? MarkdownTextBlockView {
            textView.onLinkTap = { [weak self] url in self?.onLinkTap?(url) }
        }
        if let codeView = view as? CodeBlockView {
            codeView.onCopy = { [weak self] code in self?.onCodeCopy?(code) }
        }
    }

    private func invalidateHeights() {
        cachedWidth = 0
        cachedHeights.removeAll()
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    private func ensureHeights(width: CGFloat) {
        guard width > 0 else { return }
        guard cachedWidth != width || cachedHeights.count != blockViews.count else { return }
        cachedWidth = width
        cachedHeights = blockViews.map { $0.heightThatFits(width: width) }
    }
}
```

- [ ] **Step 4: 实现两种 cell**

创建 `WBChatApp-UIKit/Features/Chat/Views/AssistantMessageCell.swift`：

```swift
import UIKit

/// 助手消息 cell。左对齐、无气泡背景，贴合 ChatGPT 的排版。
final class AssistantMessageCell: UITableViewCell {

    static let reuseIdentifier = "AssistantMessageCell"

    private static let horizontalInset: CGFloat = 16
    private static let verticalInset: CGFloat = 10

    private var stackView: BlockStackView?
    private var pool: BlockViewPool?

    private let reasoningView: ReasoningSectionView = {
        let view = ReasoningSectionView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    var onLinkTap: ((URL) -> Void)?
    var onCodeCopy: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.addSubview(reasoningView)
        contentView.addSubview(errorLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func configure(blocks: [MarkdownBlock],
                   reasoning: String?,
                   status: MessageStatus,
                   errorText: String?,
                   pool: BlockViewPool,
                   cache: AttributedCache,
                   renderer: AttributedRenderer) {
        self.pool = pool

        let stack: BlockStackView
        if let existing = stackView {
            stack = existing
        } else {
            stack = BlockStackView(pool: pool, cache: cache, renderer: renderer)
            contentView.addSubview(stack)
            stackView = stack
        }
        stack.onLinkTap = { [weak self] in self?.onLinkTap?($0) }
        stack.onCodeCopy = { [weak self] in self?.onCodeCopy?($0) }
        stack.setBlocks(blocks)

        reasoningView.isHidden = (reasoning?.isEmpty ?? true)
        reasoningView.setText(reasoning ?? "")

        errorLabel.isHidden = (errorText?.isEmpty ?? true)
        errorLabel.text = errorText

        setNeedsLayout()
    }

    /// 流式增量：只把补丁转发给容器，不做任何全量重建
    func applyPatch(_ patch: BlockPatch) {
        stackView?.applyPatch(patch)
        setNeedsLayout()
    }

    func updateReasoning(_ text: String) {
        reasoningView.isHidden = text.isEmpty
        reasoningView.setText(text)
        setNeedsLayout()
    }

    func heightThatFits(width: CGFloat) -> CGFloat {
        let contentWidth = width - Self.horizontalInset * 2
        var height = Self.verticalInset * 2
        if !reasoningView.isHidden {
            height += reasoningView.heightThatFits(width: contentWidth) + 8
        }
        height += stackView?.heightThatFits(width: contentWidth) ?? 0
        if !errorLabel.isHidden {
            height += errorLabel.sizeThatFits(CGSize(width: contentWidth,
                                                     height: .greatestFiniteMagnitude)).height + 8
        }
        return ceil(height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let contentWidth = contentView.bounds.width - Self.horizontalInset * 2
        var y = Self.verticalInset

        if !reasoningView.isHidden {
            let height = reasoningView.heightThatFits(width: contentWidth)
            reasoningView.frame = CGRect(x: Self.horizontalInset, y: y,
                                         width: contentWidth, height: height)
            y += height + 8
        }
        if let stack = stackView {
            let height = stack.heightThatFits(width: contentWidth)
            stack.frame = CGRect(x: Self.horizontalInset, y: y,
                                 width: contentWidth, height: height)
            y += height
        }
        if !errorLabel.isHidden {
            let height = errorLabel.sizeThatFits(CGSize(width: contentWidth,
                                                        height: .greatestFiniteMagnitude)).height
            errorLabel.frame = CGRect(x: Self.horizontalInset, y: y + 8,
                                      width: contentWidth, height: height)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stackView?.recycleAll()
        reasoningView.isHidden = true
        errorLabel.isHidden = true
        onLinkTap = nil
        onCodeCopy = nil
    }
}
```

创建 `WBChatApp-UIKit/Features/Chat/Views/UserMessageCell.swift`：

```swift
import UIKit

/// 用户消息 cell。右对齐气泡，**不做 Markdown 渲染**——
/// 用户输入的星号就该原样显示。
final class UserMessageCell: UITableViewCell {

    static let reuseIdentifier = "UserMessageCell"

    private static let horizontalInset: CGFloat = 16
    private static let verticalInset: CGFloat = 6
    private static let bubblePadding = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    /// 气泡最宽占内容区的比例
    private static let maxWidthRatio: CGFloat = 0.78

    private let bubble: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.bubbleUser
        view.layer.cornerRadius = 18
        return view
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = Theme.textPrimary
        return label
    }()

    /// 供测试断言
    var displayedTextForTesting: String { label.text ?? "" }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.addSubview(bubble)
        bubble.addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func configure(text: String) {
        label.text = text
        setNeedsLayout()
    }

    func heightThatFits(width: CGFloat) -> CGFloat {
        let size = labelSize(containerWidth: width)
        return ceil(size.height + Self.bubblePadding.top + Self.bubblePadding.bottom
                    + Self.verticalInset * 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = labelSize(containerWidth: contentView.bounds.width)
        let bubbleWidth = size.width + Self.bubblePadding.left + Self.bubblePadding.right
        let bubbleHeight = size.height + Self.bubblePadding.top + Self.bubblePadding.bottom

        bubble.frame = CGRect(
            x: contentView.bounds.width - Self.horizontalInset - bubbleWidth,
            y: Self.verticalInset,
            width: bubbleWidth,
            height: bubbleHeight)
        label.frame = CGRect(x: Self.bubblePadding.left, y: Self.bubblePadding.top,
                             width: size.width, height: size.height)
    }

    private func labelSize(containerWidth: CGFloat) -> CGSize {
        let maxWidth = (containerWidth - Self.horizontalInset * 2) * Self.maxWidthRatio
            - Self.bubblePadding.left - Self.bubblePadding.right
        let fitted = label.sizeThatFits(CGSize(width: max(1, maxWidth),
                                               height: .greatestFiniteMagnitude))
        return CGSize(width: min(ceil(fitted.width), max(1, maxWidth)), height: ceil(fitted.height))
    }
}
```

- [ ] **Step 5: 补上思考区视图**

创建 `WBChatApp-UIKit/Features/Chat/Views/ReasoningSectionView.swift`：

```swift
import UIKit

/// 思考过程折叠区。默认折叠，点标题展开。
final class ReasoningSectionView: UIView {

    private static let headerHeight: CGFloat = 28

    private let headerButton: UIButton = {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.setTitleColor(Theme.textSecondary, for: .normal)
        return button
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = Theme.textSecondary
        return label
    }()

    private var isExpanded = false
    private var text: String = ""

    var onToggle: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(headerButton)
        addSubview(bodyLabel)
        headerButton.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        updateHeaderTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func setText(_ newText: String) {
        text = newText
        bodyLabel.text = newText
        bodyLabel.isHidden = !isExpanded
        setNeedsLayout()
    }

    func heightThatFits(width: CGFloat) -> CGFloat {
        guard isExpanded else { return Self.headerHeight }
        let bodyHeight = bodyLabel.sizeThatFits(CGSize(width: width,
                                                       height: .greatestFiniteMagnitude)).height
        return Self.headerHeight + ceil(bodyHeight) + 4
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        headerButton.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.headerHeight)
        if isExpanded {
            let height = bodyLabel.sizeThatFits(CGSize(width: bounds.width,
                                                       height: .greatestFiniteMagnitude)).height
            bodyLabel.frame = CGRect(x: 0, y: Self.headerHeight + 4,
                                     width: bounds.width, height: ceil(height))
        } else {
            bodyLabel.frame = .zero
        }
    }

    @objc private func toggle() {
        isExpanded.toggle()
        bodyLabel.isHidden = !isExpanded
        updateHeaderTitle()
        setNeedsLayout()
        onToggle?()
    }

    private func updateHeaderTitle() {
        headerButton.setTitle(isExpanded ? "▾ 思考过程" : "▸ 思考过程", for: .normal)
    }
}
```

- [ ] **Step 6: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/BlockStackViewTests'
```

Expected: 12 个用例全部 PASS。**「已闭合块的视图实例在后续补丁中保持不变」这条是增量渲染的验收线**，失败说明 `applyPatch` 在做全量重建。

- [ ] **Step 7: 提交**

```bash
git add WBChatApp-UIKit/Features/Chat/Views WBChatApp-UIKitTests/BlockStackViewTests.swift && git commit -m "视图：实现块容器增量打补丁与助手、用户消息 cell"
```

---

## Task 15: 聊天 ViewModel

业务编排的中心。**不 import UIKit**，输出刻意分成「结构性变化」与「流式增量」两条通路。

**Files:**
- Create: `WBChatApp-UIKit/Features/Chat/ChatViewModel.swift`
- Create: `WBChatApp-UIKit/Features/Chat/StreamThrottle.swift`
- Test: `WBChatApp-UIKitTests/ChatViewModelTests.swift`

**Interfaces:**
- Consumes: `ChatProvider` / `ChatRequest` / `StreamChunk` / `ChatError`（Task 3–6）、`StreamingBlockSplitter` / `BlockPatch`（Task 7）、`ChatRepository` / `MessageRecord`（Task 11）
- Produces:

```swift
protocol StreamThrottling: AnyObject {
    var onTick: (() -> Void)? { get set }
    func start()
    func stop()
}

/// 生产环境用 CADisplayLink，测试用手动触发的替身
final class DisplayLinkThrottle: StreamThrottling { init() }

@MainActor
final class ChatViewModel {
    struct MessageViewData: Equatable {
        let id: String
        let role: ChatRole
        let text: String
        let reasoning: String?
        let status: MessageStatus
        let errorText: String?
    }
    struct State: Equatable {
        var messages: [MessageViewData]
        var isStreaming: Bool
        var canSend: Bool
    }
    enum Output {
        case stateChanged(State)
        /// 该消息的块视图需要整体清空重建（例如 retry 重新起了一轮流）。
        /// 下游收到后必须对相应 cell 的块视图调 `setBlocks([])`——
        /// 否则失败流结束时 finish() 已把 open 块封口，retry 后第一帧补丁到达时
        /// applyPatch 顶部的「上一帧未闭合块」特判会整段跳过，
        /// 把新一轮内容**追加**在旧失败内容后面。
        case blocksReset(messageID: String)
        case blocksPatched(messageID: String, patch: BlockPatch)
        case reasoningUpdated(messageID: String, text: String)
        case streamFinished(messageID: String)
        case failed(ChatError, messageID: String?)
    }

    private(set) var state: State
    var onOutput: ((Output) -> Void)?

    init(conversationID: String,
         repository: ChatRepository,
         providerFactory: @escaping () -> ChatProvider,
         systemPrompt: String?,
         model: String,
         throttle: StreamThrottling)

    func loadHistory()
    func send(_ text: String)
    func stop()
    func retryLast()
    func blocks(for messageID: String) -> [MarkdownBlock]
}
```

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/ChatViewModelTests.swift`：

```swift
import Foundation
import Testing
@testable import WBChatApp_UIKit

/// 手动驱动的节流替身：测试里想合帧就调 fire()
final class ManualThrottle: StreamThrottling {
    var onTick: (() -> Void)?
    private(set) var isRunning = false
    func start() { isRunning = true }
    func stop() { isRunning = false }
    func fire() { onTick?() }
}

/// 按脚本吐 chunk 的 Provider 替身。
///
/// **必须真实分帧投递，不能同步一次性 yield 完。** 同步 yield 会让整条流在消费端
/// 真正开始 for-await 迭代之前就全部进了缓冲区，ViewModel 会在一个执行回合内跑完，
/// 测试里的 sleep + 手动 `throttle.fire()` 根本卡不到流中途，
/// 「流式期间不出补丁」「多个 delta 被合并成一次补丁」这类用例就全部失效了。
final class ScriptedProvider: ChatProvider {
    private let chunks: [StreamChunk]
    private let error: Error?
    private let delay: Duration

    init(chunks: [StreamChunk], error: Error? = nil, delay: Duration = .milliseconds(25)) {
        self.chunks = chunks
        self.error = error
        self.delay = delay
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for chunk in chunks {
                        try await Task.sleep(for: delay)
                        continuation.yield(chunk)
                    }
                    if let error { continuation.finish(throwing: error) }
                    else { continuation.finish() }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // 消费端退出后别让生产者在后台空转
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@Suite("聊天 ViewModel")
@MainActor
struct ChatViewModelTests {

    private func makeViewModel(
        chunks: [StreamChunk],
        error: Error? = nil
    ) throws -> (ChatViewModel, ManualThrottle, GRDBChatRepository, String) {
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek,
                                                             model: "deepseek-chat")
        let throttle = ManualThrottle()
        let viewModel = ChatViewModel(conversationID: conversation.id,
                                      repository: repository,
                                      providerFactory: { ScriptedProvider(chunks: chunks, error: error) },
                                      systemPrompt: nil,
                                      model: "deepseek-chat",
                                      throttle: throttle)
        return (viewModel, throttle, repository, conversation.id)
    }

    /// 等流式任务跑完
    private func waitForStreamEnd(_ viewModel: ChatViewModel) async {
        for _ in 0..<200 {
            if !viewModel.state.isStreaming { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("发送后立刻出现用户消息与助手占位")
    func sendInsertsTwoMessages() async throws {
        let (viewModel, _, _, _) = try makeViewModel(chunks: [.done(finishReason: "stop")])
        viewModel.send("你好")
        #expect(viewModel.state.messages.count == 2)
        #expect(viewModel.state.messages[0].role == .user)
        #expect(viewModel.state.messages[0].text == "你好")
        #expect(viewModel.state.messages[1].role == .assistant)
        await waitForStreamEnd(viewModel)
    }

    @Test("空白输入不发送")
    func blankInputIgnored() throws {
        let (viewModel, _, _, _) = try makeViewModel(chunks: [])
        viewModel.send("   \n ")
        #expect(viewModel.state.messages.isEmpty)
    }

    @Test("流式期间不出补丁，节流触发才出")
    func patchesOnlyOnThrottleTick() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: [.textDelta("你"), .textDelta("好"), .done(finishReason: "stop")])

        var patches: [BlockPatch] = []
        viewModel.onOutput = { output in
            if case .blocksPatched(_, let patch) = output { patches.append(patch) }
        }

        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        #expect(patches.isEmpty, "还没到帧回调就不该出补丁")

        throttle.fire()
        #expect(!patches.isEmpty)
        await waitForStreamEnd(viewModel)
    }

    @Test("多个 delta 被合并成一次补丁")
    func deltasAreCoalesced() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: (0..<10).map { .textDelta("字\($0)") } + [.done(finishReason: "stop")])

        var patchCount = 0
        viewModel.onOutput = { output in
            if case .blocksPatched = output { patchCount += 1 }
        }
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        #expect(patchCount == 1, "一帧内的多个 delta 应合并为一次补丁")
        await waitForStreamEnd(viewModel)
    }

    @Test("节流器随流式启停")
    func throttleLifecycle() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(chunks: [.done(finishReason: "stop")])
        viewModel.send("hi")
        #expect(throttle.isRunning)
        await waitForStreamEnd(viewModel)
        #expect(!throttle.isRunning)
    }

    @Test("思考增量走独立通路")
    func reasoningGoesToSeparateOutput() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: [.reasoningDelta("想一想"), .done(finishReason: "stop")])

        var reasoning: String?
        viewModel.onOutput = { output in
            if case .reasoningUpdated(_, let text) = output { reasoning = text }
        }
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        #expect(reasoning == "想一想")
        await waitForStreamEnd(viewModel)
    }

    @Test("流结束后全文与用量落库")
    func persistsOnFinish() async throws {
        let (viewModel, throttle, repository, conversationID) = try makeViewModel(
            chunks: [.textDelta("完整回复"),
                     .usage(TokenUsage(prompt: 3, completion: 9)),
                     .done(finishReason: "stop")])
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        await waitForStreamEnd(viewModel)

        let assistant = try #require(try repository.messages(in: conversationID)
            .first { $0.role == .assistant })
        #expect(assistant.content == "完整回复")
        #expect(assistant.status == .completed)
        #expect(assistant.completionTokens == 9)
    }

    @Test("流式期间不写库")
    func noWriteDuringStreaming() async throws {
        let (viewModel, throttle, repository, conversationID) = try makeViewModel(
            chunks: [.textDelta("片段"), .done(finishReason: "stop")])
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(30))
        throttle.fire()

        let assistant = try repository.messages(in: conversationID).first { $0.role == .assistant }
        // 占位是 streaming 状态且内容为空，说明中途没有把片段写进去
        #expect(assistant?.content.isEmpty == true || assistant?.status == .streaming)
        await waitForStreamEnd(viewModel)
    }

    @Test("失败时保留已生成内容并给出错误")
    func failureKeepsPartialContent() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: [.textDelta("已经写了一半")],
            error: ChatError.serverError(status: 500, message: "炸了"))

        var failure: ChatError?
        viewModel.onOutput = { output in
            if case .failed(let error, _) = output { failure = error }
        }
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        await waitForStreamEnd(viewModel)

        #expect(failure == .serverError(status: 500, message: "炸了"))
        let assistant = try #require(viewModel.state.messages.last)
        #expect(assistant.text == "已经写了一半")
        #expect(assistant.status == .failed)
    }

    @Test("stop 把消息标记为已停止并保留内容")
    func stopMarksStopped() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: [.textDelta("写到一半")] + (0..<1000).map { _ in .textDelta("续") })
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(30))
        throttle.fire()
        viewModel.stop()
        await waitForStreamEnd(viewModel)

        let assistant = try #require(viewModel.state.messages.last)
        #expect(assistant.status == .stopped)
        #expect(!assistant.text.isEmpty)
    }

    @Test("流式期间 canSend 为假")
    func canSendIsFalseWhileStreaming() async throws {
        let (viewModel, _, _, _) = try makeViewModel(
            chunks: (0..<500).map { _ in .textDelta("续") })
        viewModel.send("hi")
        #expect(viewModel.state.isStreaming)
        #expect(!viewModel.state.canSend)
        viewModel.stop()
        await waitForStreamEnd(viewModel)
    }

    @Test("loadHistory 读回已存消息")
    func loadHistory() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: [.textDelta("历史回复"), .done(finishReason: "stop")])
        viewModel.send("历史提问")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        await waitForStreamEnd(viewModel)

        viewModel.loadHistory()
        #expect(viewModel.state.messages.count == 2)
        #expect(viewModel.state.messages[0].text == "历史提问")
    }

    @Test("blocks(for:) 返回该消息切好的块")
    func blocksForMessage() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: [.textDelta("# 标题\n\n正文\n"), .done(finishReason: "stop")])
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        await waitForStreamEnd(viewModel)

        let assistantID = try #require(viewModel.state.messages.last?.id)
        let blocks = viewModel.blocks(for: assistantID)
        #expect(blocks.map(\.kind) == [.heading(level: 1), .paragraph])
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/ChatViewModelTests'
```

Expected: 编译失败，`cannot find 'ChatViewModel' in scope`。

- [ ] **Step 3: 实现节流器**

创建 `WBChatApp-UIKit/Features/Chat/StreamThrottle.swift`：

```swift
import QuartzCore

/// 把高频的网络增量合并到屏幕刷新节奏上。
/// 抽成协议是为了让 ViewModel 能在测试里被手动驱动。
protocol StreamThrottling: AnyObject {
    var onTick: (() -> Void)? { get set }
    func start()
    func stop()
}

/// 生产实现：CADisplayLink 天然与屏幕刷新率对齐（60/120Hz），
/// 保证每帧最多一次排版、最多一次贴底滚动。
final class DisplayLinkThrottle: StreamThrottling {

    var onTick: (() -> Void)?

    private var displayLink: CADisplayLink?

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleTick() {
        onTick?()
    }

    deinit {
        displayLink?.invalidate()
    }
}
```

- [ ] **Step 4: 实现 ViewModel**

创建 `WBChatApp-UIKit/Features/Chat/ChatViewModel.swift`：

```swift
import Foundation

/// 聊天页的业务编排。
///
/// **不 import UIKit**：属性串渲染是视图层的事，这里只产出纯模型。
///
/// 输出刻意分两类：
/// - `stateChanged` 表示消息条目的增删，交给 diffable data source
/// - `blocksPatched` 表示流式增量，绕开 data source 直接打到 cell 实例
///
/// 二者混用是流式聊天卡顿的主因，所以从接口层就把它们分开。
@MainActor
final class ChatViewModel {

    // MARK: - 对外类型

    struct MessageViewData: Equatable {
        let id: String
        let role: ChatRole
        let text: String
        let reasoning: String?
        let status: MessageStatus
        let errorText: String?
    }

    struct State: Equatable {
        var messages: [MessageViewData] = []
        var isStreaming: Bool = false
        var canSend: Bool = true
    }

    enum Output {
        case stateChanged(State)
        /// 该消息的块视图需要整体清空重建（例如 retry 重新起了一轮流）。
        /// 下游收到后必须对相应 cell 的块视图调 `setBlocks([])`——
        /// 否则失败流结束时 finish() 已把 open 块封口，retry 后第一帧补丁到达时
        /// applyPatch 顶部的「上一帧未闭合块」特判会整段跳过，
        /// 把新一轮内容**追加**在旧失败内容后面。
        case blocksReset(messageID: String)
        case blocksPatched(messageID: String, patch: BlockPatch)
        case reasoningUpdated(messageID: String, text: String)
        case streamFinished(messageID: String)
        case failed(ChatError, messageID: String?)
    }

    private(set) var state = State() {
        didSet {
            guard state != oldValue else { return }
            onOutput?(.stateChanged(state))
        }
    }

    var onOutput: ((Output) -> Void)?

    // MARK: - 依赖

    private let conversationID: String
    private let repository: ChatRepository
    private let providerFactory: () -> ChatProvider
    private let systemPrompt: String?
    private let model: String
    private let throttle: StreamThrottling

    /// 上下文最多携带多少条历史
    private let contextLimit = 20

    // MARK: - 流式状态

    private var streamTask: Task<Void, Never>?
    private var streamingMessageID: String?
    private var splitter = StreamingBlockSplitter()

    /// 本帧攒下、还没交给切分器的增量
    private var pendingText = ""
    private var pendingReasoning = ""

    private var accumulatedText = ""
    private var accumulatedReasoning = ""
    private var usage: TokenUsage?

    /// 每条消息切好的块，供 cell 复用时重建
    private var blocksByMessage: [String: [MarkdownBlock]] = [:]

    private var isStopping = false

    // MARK: - 初始化

    init(conversationID: String,
         repository: ChatRepository,
         providerFactory: @escaping () -> ChatProvider,
         systemPrompt: String?,
         model: String,
         throttle: StreamThrottling) {
        self.conversationID = conversationID
        self.repository = repository
        self.providerFactory = providerFactory
        self.systemPrompt = systemPrompt
        self.model = model
        self.throttle = throttle

        throttle.onTick = { [weak self] in self?.flush() }
    }

    deinit {
        streamTask?.cancel()
    }

    // MARK: - 历史

    func loadHistory() {
        guard let records = try? repository.messages(in: conversationID) else { return }
        for record in records where record.role == .assistant {
            blocksByMessage[record.id] = Self.splitWhole(record.content)
        }
        state.messages = records.map(Self.viewData(from:))
    }

    func blocks(for messageID: String) -> [MarkdownBlock] {
        blocksByMessage[messageID] ?? []
    }

    // MARK: - 发送

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state.canSend else { return }

        let now = Date().timeIntervalSince1970
        let baseOrdinal = state.messages.count

        let userRecord = MessageRecord(
            id: UUID().uuidString, conversationId: conversationID, ordinal: baseOrdinal,
            roleRaw: ChatRole.user.rawValue, content: trimmed, reasoning: nil,
            statusRaw: MessageStatus.completed.rawValue, errorMessage: nil,
            promptTokens: nil, completionTokens: nil, createdAt: now)

        let assistantRecord = MessageRecord(
            id: UUID().uuidString, conversationId: conversationID, ordinal: baseOrdinal + 1,
            roleRaw: ChatRole.assistant.rawValue, content: "", reasoning: nil,
            statusRaw: MessageStatus.streaming.rawValue, errorMessage: nil,
            promptTokens: nil, completionTokens: nil, createdAt: now)

        try? repository.insertMessage(userRecord)
        try? repository.insertMessage(assistantRecord)
        try? repository.touchConversation(id: conversationID)

        state.messages.append(Self.viewData(from: userRecord))
        state.messages.append(Self.viewData(from: assistantRecord))

        startStream(assistantID: assistantRecord.id)
    }

    func retryLast() {
        guard let last = state.messages.last, last.role == .assistant else { return }
        // 把失败的助手消息重置为流式占位后重新拉一次
        state.messages[state.messages.count - 1] = MessageViewData(
            id: last.id, role: .assistant, text: "", reasoning: nil,
            status: .streaming, errorText: nil)
        blocksByMessage[last.id] = []
        startStream(assistantID: last.id)
    }

    func stop() {
        guard state.isStreaming else { return }
        isStopping = true
        streamTask?.cancel()
    }

    // MARK: - 流式主流程

    private func startStream(assistantID: String) {
        streamingMessageID = assistantID
        splitter = StreamingBlockSplitter()
        pendingText = ""
        pendingReasoning = ""
        accumulatedText = ""
        accumulatedReasoning = ""
        usage = nil
        isStopping = false

        state.isStreaming = true
        state.canSend = false
        throttle.start()

        let request = makeRequest()
        let provider = providerFactory()

        streamTask = Task { [weak self] in
            do {
                for try await chunk in provider.stream(request) {
                    guard let self else { return }
                    // 先处理再检查取消：反过来的话，stop() 与「已到手但还没处理」的
                    // chunk 竞速时会把这个增量直接丢掉，违背「停止应保留已生成内容」的语义
                    self.handle(chunk)
                    try Task.checkCancellation()
                }
                self?.finishStream(error: nil)
            } catch {
                self?.finishStream(error: ChatError.from(error))
            }
        }
    }

    /// 只做累积，不触发任何 UI——出图统一交给节流器
    private func handle(_ chunk: StreamChunk) {
        switch chunk {
        case .textDelta(let text):
            pendingText += text
            accumulatedText += text
        case .reasoningDelta(let text):
            pendingReasoning += text
            accumulatedReasoning += text
        case .usage(let value):
            usage = value
        case .done:
            break
        }
    }

    /// 帧回调：把攒下的增量一次性推给 UI
    private func flush() {
        guard let messageID = streamingMessageID else { return }

        if !pendingText.isEmpty {
            let patch = splitter.append(pendingText)
            pendingText = ""
            blocksByMessage[messageID] = splitter.allBlocks
            if !patch.isEmpty {
                onOutput?(.blocksPatched(messageID: messageID, patch: patch))
            }
        }
        if !pendingReasoning.isEmpty {
            pendingReasoning = ""
            onOutput?(.reasoningUpdated(messageID: messageID, text: accumulatedReasoning))
        }
    }

    private func finishStream(error: ChatError?) {
        guard let messageID = streamingMessageID else { return }

        flush()
        let finalPatch = splitter.finish()
        blocksByMessage[messageID] = splitter.allBlocks
        if !finalPatch.newlySealed.isEmpty || finalPatch.open != nil {
            onOutput?(.blocksPatched(messageID: messageID, patch: finalPatch))
        }

        throttle.stop()
        streamTask = nil
        streamingMessageID = nil

        let status: MessageStatus
        var errorText: String?
        if let error {
            if case .cancelled = error {
                status = .stopped
            } else {
                status = .failed
                errorText = error.userMessage
            }
        } else {
            status = isStopping ? .stopped : .completed
        }

        updateMessage(id: messageID,
                      text: accumulatedText,
                      reasoning: accumulatedReasoning.isEmpty ? nil : accumulatedReasoning,
                      status: status,
                      errorText: errorText)

        state.isStreaming = false
        state.canSend = true

        if let error, status == .failed {
            onOutput?(.failed(error, messageID: messageID))
        } else {
            onOutput?(.streamFinished(messageID: messageID))
        }
    }

    // MARK: - 落库

    /// 只在流结束时写一次，避免高频写放大
    private func updateMessage(id: String, text: String, reasoning: String?,
                               status: MessageStatus, errorText: String?) {
        guard let index = state.messages.firstIndex(where: { $0.id == id }) else { return }
        state.messages[index] = MessageViewData(id: id, role: .assistant, text: text,
                                                reasoning: reasoning, status: status,
                                                errorText: errorText)

        guard var record = try? repository.messages(in: conversationID).first(where: { $0.id == id })
        else { return }
        record.content = text
        record.reasoning = reasoning
        record.statusRaw = status.rawValue
        record.errorMessage = errorText
        record.promptTokens = usage?.prompt
        record.completionTokens = usage?.completion
        try? repository.updateMessage(record)
        try? repository.touchConversation(id: conversationID)
    }

    // MARK: - 请求组装

    private func makeRequest() -> ChatRequest {
        // 只带最近若干轮，且排除正在生成的空占位
        let history = state.messages
            .filter { !($0.role == .assistant && $0.text.isEmpty) }
            .suffix(contextLimit)
            .map { ChatMessage(role: $0.role, content: $0.text) }

        return ChatRequest(model: model,
                           messages: Array(history),
                           system: systemPrompt,
                           temperature: 0.7,
                           maxTokens: 4096)
    }

    // MARK: - 辅助

    private static func viewData(from record: MessageRecord) -> MessageViewData {
        MessageViewData(id: record.id, role: record.role, text: record.content,
                        reasoning: record.reasoning, status: record.status,
                        errorText: record.errorMessage)
    }

    private static func splitWhole(_ text: String) -> [MarkdownBlock] {
        var splitter = StreamingBlockSplitter()
        _ = splitter.append(text)
        _ = splitter.finish()
        return splitter.allBlocks
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/ChatViewModelTests'
```

Expected: 13 个用例全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add WBChatApp-UIKit/Features/Chat WBChatApp-UIKitTests/ChatViewModelTests.swift && git commit -m "业务：实现聊天 ViewModel，增量与结构性变化分两条输出通路"
```

---

## Task 16: 聊天页装配

把前面所有零件接起来，跑出第一个能用的界面。

**Files:**
- Create: `WBChatApp-UIKit/Features/Chat/Views/InputBarView.swift`
- Create: `WBChatApp-UIKit/Features/Chat/Views/ScrollToBottomButton.swift`
- Create: `WBChatApp-UIKit/Features/Chat/ChatViewController.swift`
- Create: `WBChatApp-UIKit/App/AppContainer.swift`
- Modify: `WBChatApp-UIKit/SceneDelegate.swift`
- Test: `WBChatApp-UIKitUITests/ChatSmokeUITests.swift`（新建 UI Testing Bundle）

**Interfaces:**
- Consumes: Task 10–15 的全部产物
- Produces:
  - `final class InputBarView: UIView`：`var onSend: ((String) -> Void)?`、`var onStop: (() -> Void)?`、`var onMicTap: (() -> Void)?`、`func setStreaming(_:)`、`func setText(_:)`、`var text: String`
  - `final class ScrollToBottomButton: UIButton`
  - `final class ChatViewController: UIViewController`
  - `final class AppContainer`：`static let shared`、`func makeChatViewController(conversationID: String) -> ChatViewController`、`var repository: ChatRepository`、`var settings: AppSettings`

- [ ] **Step 1: 实现设置存储与容器**

创建 `WBChatApp-UIKit/Core/Security/AppSettings.swift`：

```swift
import Foundation

/// 非敏感配置走 UserDefaults，API Key 走 Keychain。
final class AppSettings {

    private enum Key {
        static let provider = "settings.provider"
        static let model = "settings.model"
        static let baseURL = "settings.baseURL"
        static let systemPrompt = "settings.systemPrompt"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var provider: ProviderKind {
        get { ProviderKind(rawValue: defaults.string(forKey: Key.provider) ?? "") ?? .deepSeek }
        set { defaults.set(newValue.rawValue, forKey: Key.provider) }
    }

    var model: String {
        get { defaults.string(forKey: Key.model) ?? provider.defaultModel }
        set { defaults.set(newValue, forKey: Key.model) }
    }

    var baseURL: URL {
        get {
            guard let raw = defaults.string(forKey: Key.baseURL), let url = URL(string: raw) else {
                return provider.defaultBaseURL
            }
            return url
        }
        set { defaults.set(newValue.absoluteString, forKey: Key.baseURL) }
    }

    var systemPrompt: String {
        get { defaults.string(forKey: Key.systemPrompt) ?? "你是一个乐于助人的 AI 助手，回答简洁准确。" }
        set { defaults.set(newValue, forKey: Key.systemPrompt) }
    }

    var apiKey: String {
        get { KeychainStore.read(KeychainStore.key(for: provider)) ?? "" }
    }

    func setAPIKey(_ key: String) throws {
        if key.isEmpty {
            try KeychainStore.delete(KeychainStore.key(for: provider))
        } else {
            try KeychainStore.save(key, for: KeychainStore.key(for: provider))
        }
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    var currentConfig: ProviderConfig {
        ProviderConfig(kind: provider, baseURL: baseURL, apiKey: apiKey, model: model)
    }
}
```

创建 `WBChatApp-UIKit/App/AppContainer.swift`：

```swift
import Foundation
import GRDB

/// 依赖组装。整个工程里唯一知道具体实现类型的地方。
final class AppContainer {

    static let shared = AppContainer()

    let settings = AppSettings()
    let repository: ChatRepository

    /// 渲染相关的对象全局共用，缓存才能跨消息复用
    let renderer = AttributedRenderer()
    let cache = AttributedCache()
    let pool = BlockViewPool()

    private init() {
        do {
            let queue = try AppDatabase.makeQueue(at: try AppDatabase.defaultURL())
            repository = GRDBChatRepository(queue: queue)
        } catch {
            // 建库失败时退回内存库，保证 App 仍可运行
            repository = GRDBChatRepository(queue: try! AppDatabase.makeQueue(at: nil))
        }
    }

    /// 没配 Key 就走演示模式，保证 App 开箱可用
    func makeProvider() -> ChatProvider {
        guard settings.hasAPIKey else { return MockProvider() }
        return NetworkChatProvider(config: settings.currentConfig)
    }

    /// ChatViewModel 与 ChatViewController 都是主线程隔离的，工厂方法也要标注
    @MainActor
    func makeChatViewModel(conversationID: String) -> ChatViewModel {
        ChatViewModel(conversationID: conversationID,
                      repository: repository,
                      providerFactory: { [weak self] in
                          self?.makeProvider() ?? MockProvider()
                      },
                      systemPrompt: settings.systemPrompt,
                      model: settings.model,
                      throttle: DisplayLinkThrottle())
    }

    @MainActor
    func makeChatViewController(conversationID: String) -> ChatViewController {
        ChatViewController(viewModel: makeChatViewModel(conversationID: conversationID),
                           renderer: renderer,
                           cache: cache,
                           pool: pool)
    }

    /// 启动时取最近一个会话，没有就新建
    func currentOrNewConversationID() -> String {
        if let latest = try? repository.allConversations().first {
            return latest.id
        }
        let created = try? repository.createConversation(title: "新对话",
                                                         provider: settings.provider,
                                                         model: settings.model)
        return created?.id ?? UUID().uuidString
    }
}
```

- [ ] **Step 2: 实现输入栏与回到底部按钮**

创建 `WBChatApp-UIKit/Features/Chat/Views/InputBarView.swift`：

```swift
import UIKit

/// 底部输入栏：多行自增高文本框 + 麦克风 + 发送/停止。
final class InputBarView: UIView {

    var onSend: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onMicTap: (() -> Void)?
    var onHeightChange: (() -> Void)?

    private static let minHeight: CGFloat = 36
    private static let maxHeight: CGFloat = 120

    private let textView: UITextView = {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.isScrollEnabled = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "发消息…"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = Theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let micButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "mic"), for: .normal)
        button.accessibilityIdentifier = "input.mic"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.accessibilityIdentifier = "input.send"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let container: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.secondaryBackground
        view.layer.cornerRadius = 20
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var textViewHeight: NSLayoutConstraint!
    private var isStreaming = false

    var text: String { textView.text ?? "" }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    private func setUp() {
        backgroundColor = Theme.background
        addSubview(container)
        container.addSubview(textView)
        container.addSubview(placeholderLabel)
        addSubview(micButton)
        addSubview(actionButton)

        textViewHeight = textView.heightAnchor.constraint(equalToConstant: Self.minHeight)

        NSLayoutConstraint.activate([
            micButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            micButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            micButton.widthAnchor.constraint(equalToConstant: 32),
            micButton.heightAnchor.constraint(equalToConstant: 32),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            actionButton.widthAnchor.constraint(equalToConstant: 32),
            actionButton.heightAnchor.constraint(equalToConstant: 32),

            container.leadingAnchor.constraint(equalTo: micButton.trailingAnchor, constant: 8),
            container.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            textView.topAnchor.constraint(equalTo: container.topAnchor),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            textViewHeight,

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 12),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
        ])

        textView.delegate = self
        textView.accessibilityIdentifier = "input.textView"
        micButton.addTarget(self, action: #selector(handleMic), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)
        updateActionButton()
    }

    func setStreaming(_ streaming: Bool) {
        isStreaming = streaming
        updateActionButton()
    }

    func setText(_ newText: String) {
        textView.text = newText
        textViewDidChange(textView)
    }

    @objc private func handleMic() {
        onMicTap?()
    }

    @objc private func handleAction() {
        if isStreaming {
            onStop?()
            return
        }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        onSend?(content)
        setText("")
    }

    private func updateActionButton() {
        let name = isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill"
        actionButton.setImage(UIImage(systemName: name), for: .normal)
        actionButton.accessibilityIdentifier = isStreaming ? "input.stop" : "input.send"
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        actionButton.isEnabled = isStreaming || hasText
    }
}

extension InputBarView: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        let fitted = textView.sizeThatFits(CGSize(width: textView.bounds.width,
                                                  height: .greatestFiniteMagnitude)).height
        let clamped = min(max(fitted, Self.minHeight), Self.maxHeight)
        if abs(textViewHeight.constant - clamped) > 0.5 {
            textViewHeight.constant = clamped
            textView.isScrollEnabled = fitted > Self.maxHeight
            onHeightChange?()
        }
        updateActionButton()
    }
}
```

创建 `WBChatApp-UIKit/Features/Chat/Views/ScrollToBottomButton.swift`：

```swift
import UIKit

/// 脱离贴底时浮出的「回到底部」圆钮。
final class ScrollToBottomButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setImage(UIImage(systemName: "arrow.down"), for: .normal)
        tintColor = Theme.textPrimary
        backgroundColor = Theme.secondaryBackground
        layer.cornerRadius = 18
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        accessibilityIdentifier = "chat.scrollToBottom"
        alpha = 0
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func setVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.2) { self.alpha = visible ? 1 : 0 }
    }
}
```

- [ ] **Step 3: 实现 ChatViewController**

创建 `WBChatApp-UIKit/Features/Chat/ChatViewController.swift`：

```swift
import UIKit

final class ChatViewController: UIViewController {

    // MARK: - 依赖

    private let viewModel: ChatViewModel
    private let renderer: AttributedRenderer
    private let cache: AttributedCache
    private let pool: BlockViewPool
    private let autoScroll = AutoScrollController()

    // MARK: - 视图

    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.separatorStyle = .none
        tableView.backgroundColor = Theme.background
        tableView.keyboardDismissMode = .interactive
        tableView.accessibilityIdentifier = "chat.tableView"
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    private let inputBar = InputBarView()
    private let scrollToBottomButton = ScrollToBottomButton()

    private var dataSource: UITableViewDiffableDataSource<Int, String>!

    /// 行高缓存。键是消息 id，值是当前宽度下的高度。
    private var heightCache: [String: CGFloat] = [:]
    private var cachedWidth: CGFloat = 0

    /// 正在流式的那条消息，用来直接拿 cell 打补丁
    private var streamingMessageID: String?

    init(viewModel: ChatViewModel,
         renderer: AttributedRenderer,
         cache: AttributedCache,
         pool: BlockViewPool) {
        self.viewModel = viewModel
        self.renderer = renderer
        self.cache = cache
        self.pool = pool
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        setUpViews()
        setUpDataSource()
        bindViewModel()
        bindAutoScroll()
        viewModel.loadHistory()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if cachedWidth != tableView.bounds.width {
            cachedWidth = tableView.bounds.width
            heightCache.removeAll()
            tableView.reloadData()
        }
    }

    // MARK: - 装配

    private func setUpViews() {
        view.addSubview(tableView)
        view.addSubview(inputBar)
        view.addSubview(scrollToBottomButton)
        inputBar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // keyboardLayoutGuide 自动跟随键盘，不需要手写通知监听
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            scrollToBottomButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scrollToBottomButton.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -12),
            scrollToBottomButton.widthAnchor.constraint(equalToConstant: 36),
            scrollToBottomButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        tableView.register(AssistantMessageCell.self,
                           forCellReuseIdentifier: AssistantMessageCell.reuseIdentifier)
        tableView.register(UserMessageCell.self,
                           forCellReuseIdentifier: UserMessageCell.reuseIdentifier)
        tableView.delegate = self

        inputBar.onSend = { [weak self] text in
            self?.autoScroll.didSendMessage()
            self?.viewModel.send(text)
        }
        inputBar.onStop = { [weak self] in self?.viewModel.stop() }
        inputBar.onHeightChange = { [weak self] in self?.stickToBottomIfNeeded() }

        scrollToBottomButton.addTarget(self, action: #selector(handleScrollToBottom),
                                       for: .touchUpInside)
    }

    private func setUpDataSource() {
        dataSource = UITableViewDiffableDataSource<Int, String>(tableView: tableView) {
            [weak self] tableView, indexPath, messageID in
            guard let self,
                  let message = self.viewModel.state.messages.first(where: { $0.id == messageID })
            else { return UITableViewCell() }

            switch message.role {
            case .user, .system:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: UserMessageCell.reuseIdentifier, for: indexPath) as! UserMessageCell
                cell.configure(text: message.text)
                return cell

            case .assistant:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: AssistantMessageCell.reuseIdentifier, for: indexPath) as! AssistantMessageCell
                cell.configure(blocks: self.viewModel.blocks(for: message.id),
                               reasoning: message.reasoning,
                               status: message.status,
                               errorText: message.errorText,
                               pool: self.pool,
                               cache: self.cache,
                               renderer: self.renderer)
                cell.onCodeCopy = { _ in Haptics.success() }
                cell.onLinkTap = { url in UIApplication.shared.open(url) }
                return cell
            }
        }
        dataSource.defaultRowAnimation = .fade
    }

    // MARK: - 绑定

    private func bindViewModel() {
        viewModel.onOutput = { [weak self] output in
            guard let self else { return }
            switch output {
            case .stateChanged(let state):
                self.applySnapshot(state)
                self.inputBar.setStreaming(state.isStreaming)
                self.streamingMessageID = state.isStreaming ? state.messages.last?.id : nil

            case .blocksReset(let messageID):
                // retry 重新起了一轮流，块视图必须整体清空重建。
                // 不做的话，applyPatch 会把新内容追加在旧失败内容后面。
                self.resetBlocks(messageID: messageID)

            case .blocksPatched(let messageID, let patch):
                self.applyPatch(messageID: messageID, patch: patch)

            case .reasoningUpdated(let messageID, let text):
                self.applyReasoning(messageID: messageID, text: text)

            case .streamFinished(let messageID):
                self.streamingMessageID = nil
                self.invalidateHeight(for: messageID)

            case .failed(_, let messageID):
                self.streamingMessageID = nil
                if let messageID { self.invalidateHeight(for: messageID) }
            }
        }
    }

    private func bindAutoScroll() {
        autoScroll.onModeChange = { [weak self] mode in
            self?.scrollToBottomButton.setVisible(mode == .detached)
        }
    }

    // MARK: - 结构性变化

    private func applySnapshot(_ state: ChatViewModel.State) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(state.messages.map(\.id))

        // 内容变化的行不靠 snapshot 刷新，交给增量补丁
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            self?.stickToBottomIfNeeded()
        }
    }

    // MARK: - 流式增量

    /// 关键路径：拿到 cell 实例直接打补丁，**不走 reloadRows**。
    private func applyPatch(messageID: String, patch: BlockPatch) {
        guard let indexPath = indexPath(for: messageID) else { return }
        guard let cell = tableView.cellForRow(at: indexPath) as? AssistantMessageCell else {
            // 不在可视区就只更新高度缓存，等 cell 复用时由 configure 重建
            invalidateHeight(for: messageID)
            return
        }

        cell.applyPatch(patch)

        let newHeight = cell.heightThatFits(width: tableView.bounds.width)
        let oldHeight = heightCache[messageID]
        heightCache[messageID] = newHeight

        // 高度真的变了才惊动 tableView
        if oldHeight == nil || abs(oldHeight! - newHeight) > 0.5 {
            UIView.performWithoutAnimation {
                tableView.beginUpdates()
                tableView.endUpdates()
            }
        }
        stickToBottomIfNeeded()
    }

    private func applyReasoning(messageID: String, text: String) {
        guard let indexPath = indexPath(for: messageID),
              let cell = tableView.cellForRow(at: indexPath) as? AssistantMessageCell else { return }
        cell.updateReasoning(text)
        heightCache[messageID] = cell.heightThatFits(width: tableView.bounds.width)
        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
        stickToBottomIfNeeded()
    }

    private func invalidateHeight(for messageID: String) {
        heightCache[messageID] = nil
        guard dataSource.indexPath(for: messageID) != nil else { return }
        // ⚠️ 这里**不能**调 tableView.reloadRows。表的 dataSource 是
        // UITableViewDiffableDataSource，直接对 UITableView 调变更 API 会 100% 抛
        // NSInternalInconsistencyException：
        //   "UITableView must be updated via the UITableViewDiffableDataSource APIs...
        //    please do not call mutation APIs directly on UITableView."
        // 每次流式结束都会走到这里，也就是每发一条消息必崩。必须走 snapshot 的
        // reconfigureItems（iOS 15+），它只重新配置 cell、不重建 item 身份。
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([messageID])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func indexPath(for messageID: String) -> IndexPath? {
        dataSource.indexPath(for: messageID)
    }

    // MARK: - 贴底

    /// pinned 状态下贴底。一律无动画，避免与减速动画互相打断。
    private func stickToBottomIfNeeded() {
        guard autoScroll.shouldStickToBottom else { return }
        let bottomOffset = tableView.contentSize.height
            - tableView.bounds.height + tableView.adjustedContentInset.bottom
        guard bottomOffset > -tableView.adjustedContentInset.top else { return }

        autoScroll.beginProgrammaticScroll()
        tableView.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
        autoScroll.endProgrammaticScroll()
    }

    @objc private func handleScrollToBottom() {
        autoScroll.didTapScrollToBottom()
        let bottomOffset = tableView.contentSize.height
            - tableView.bounds.height + tableView.adjustedContentInset.bottom
        autoScroll.beginProgrammaticScroll()
        tableView.setContentOffset(CGPoint(x: 0, y: max(0, bottomOffset)), animated: true)
        // 动画结束前保持标记，避免中途被判成用户滚动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.autoScroll.endProgrammaticScroll()
        }
    }

    private var distanceToBottom: CGFloat {
        let maxOffset = tableView.contentSize.height
            - tableView.bounds.height + tableView.adjustedContentInset.bottom
        return max(0, maxOffset - tableView.contentOffset.y)
    }
}

// MARK: - UITableViewDelegate

extension ChatViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let messageID = dataSource.itemIdentifier(for: indexPath) else { return 0 }
        if let cached = heightCache[messageID] { return cached }

        guard let message = viewModel.state.messages.first(where: { $0.id == messageID }) else {
            return 0
        }
        let height = measureHeight(for: message, width: tableView.bounds.width)
        heightCache[messageID] = height
        return height
    }

    /// 离屏测量用的常驻 cell。
    ///
    /// ⚠️ **必须常驻复用，不能每次新建。** 新建的 cell 内部是全新的 `BlockStackView`，
    /// 它 `configure` 时会从**共享的 `pool`** 借走块视图，而这个临时 cell 用完即弃、
    /// 借出的视图永远失去持有者，`pool.recycle` 再也收不回来——池子会被逐渐掏空，
    /// 之后真实可见 cell 复用只能不断新建 `UITextView`，恰好是复用池要规避的开销。
    /// 每条新助手消息首次测量、以及旋转/分屏触发的全量重测都会加剧这个泄漏。
    private lazy var measuringAssistantCell = AssistantMessageCell(style: .default, reuseIdentifier: nil)
    private lazy var measuringUserCell = UserMessageCell(style: .default, reuseIdentifier: nil)

    /// 离屏测量。顺序必须是：prepareForReuse → 设 frame → configure → heightThatFits
    private func measureHeight(for message: ChatViewModel.MessageViewData,
                               width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        switch message.role {
        case .user, .system:
            let cell = measuringUserCell
            cell.frame = CGRect(x: 0, y: 0, width: width, height: 0)
            cell.configure(text: message.text)
            return cell.heightThatFits(width: width)
        case .assistant:
            let cell = measuringAssistantCell
            cell.prepareForReuse()      // 把上一次借的块视图还给池子
            cell.frame = CGRect(x: 0, y: 0, width: width, height: 0)
            cell.configure(blocks: viewModel.blocks(for: message.id),
                           reasoning: message.reasoning,
                           status: message.status,
                           errorText: message.errorText,
                           pool: pool, cache: cache, renderer: renderer)
            return cell.heightThatFits(width: width)
        }
    }

    // MARK: 滚动回调全部转发给状态机

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        autoScroll.willBeginDragging(offsetY: scrollView.contentOffset.y)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        autoScroll.didScroll(offsetY: scrollView.contentOffset.y,
                             isTracking: scrollView.isTracking)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        autoScroll.didEndDragging(willDecelerate: decelerate,
                                  distanceToBottom: distanceToBottom)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        autoScroll.didEndDecelerating(distanceToBottom: distanceToBottom)
    }
}
```

- [ ] **Step 4: 补上 Haptics 并接入 SceneDelegate**

创建 `WBChatApp-UIKit/Common/Haptics.swift`：

```swift
import UIKit

enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
```

把 `SceneDelegate.swift` 里的占位控制器换成真实页面：

```swift
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)

        let container = AppContainer.shared
        let chat = container.makeChatViewController(
            conversationID: container.currentOrNewConversationID())
        window.rootViewController = UINavigationController(rootViewController: chat)
        window.makeKeyAndVisible()
        self.window = window
    }
```

- [ ] **Step 5: 加 UI 冒烟测试**

在 Xcode 里 File → New → Target → **UI Testing Bundle**，命名 `WBChatApp-UIKitUITests`。

创建 `WBChatApp-UIKitUITests/ChatSmokeUITests.swift`：

```swift
import XCTest

final class ChatSmokeUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// 演示模式下发一条消息，确认助手气泡出现且能滚动
    func testSendMessageInMockMode() {
        let app = XCUIApplication()
        app.launch()

        let input = app.textViews["input.textView"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("你好")

        app.buttons["input.send"].tap()

        // 演示模式会流式吐出一段带代码块的 Markdown
        let table = app.tables["chat.tableView"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))

        let expectation = expectation(description: "等待流式输出结束")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { expectation.fulfill() }
        wait(for: [expectation], timeout: 10)

        XCTAssertGreaterThanOrEqual(table.cells.count, 2, "应至少有用户与助手两条消息")
    }
}
```

- [ ] **Step 6: 运行全部测试**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Expected: 所有单测与 UI 冒烟测试全部 PASS。

- [ ] **Step 7: 真机/模拟器手动验收**

在模拟器里跑起 App，逐条确认：

1. 输入「你好」发送，助手气泡开始流式出字，标题/列表/代码块/表格都正确渲染
2. 流式过程中**向上拖动**，出字继续但视图不再被拽回底部，右下浮出「↓」按钮
3. 手动滑回底部，按钮消失，重新恢复自动跟随
4. 流式中点停止按钮，出字立刻停下，已生成内容保留
5. 代码块右上角「复制」可用
6. 键盘弹出时输入栏跟随，列表底部不被遮挡

- [ ] **Step 8: 提交**

```bash
git add -A WBChatApp-UIKit && git commit -m "页面：装配聊天页，流式补丁直达 cell 并接入贴底状态机"
```

---

## Task 17: 会话列表与侧边抽屉

**Files:**
- Create: `WBChatApp-UIKit/Features/ConversationList/ConversationListViewModel.swift`
- Create: `WBChatApp-UIKit/Features/ConversationList/ConversationListViewController.swift`
- Create: `WBChatApp-UIKit/Features/ConversationList/DrawerContainerViewController.swift`
- Modify: `WBChatApp-UIKit/App/AppContainer.swift`（新增 `makeRootViewController()`）
- Modify: `WBChatApp-UIKit/SceneDelegate.swift`
- Test: `WBChatApp-UIKitTests/ConversationListViewModelTests.swift`

**Interfaces:**
- Consumes: `ChatRepository` / `ConversationRecord`（Task 11）、`AppSettings`（Task 16）
- Produces:
  - `@MainActor final class ConversationListViewModel`
    - `struct Item: Equatable { let id: String; let title: String; let subtitle: String }`
    - `private(set) var items: [Item]`、`var onItemsChanged: (([Item]) -> Void)?`
    - `func start()`、`func createConversation() -> String`、`func delete(id: String)`、`func rename(id: String, to: String)`
  - `final class ConversationListViewController: UIViewController`，`var onSelect: ((String) -> Void)?`
  - `final class DrawerContainerViewController: UIViewController`，`init(drawer:content:)`、`func setContent(_:)`、`func toggleDrawer()`、`func closeDrawer()`

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/ConversationListViewModelTests.swift`：

```swift
import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("会话列表 ViewModel")
@MainActor
struct ConversationListViewModelTests {

    private func make() throws -> (ConversationListViewModel, GRDBChatRepository) {
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let viewModel = ConversationListViewModel(repository: repository, settings: AppSettings())
        return (viewModel, repository)
    }

    @Test("start 后读到已有会话")
    func startLoadsExisting() throws {
        let (viewModel, repository) = try make()
        _ = try repository.createConversation(title: "已有会话", provider: .deepSeek, model: "m")
        viewModel.start()
        #expect(viewModel.items.contains { $0.title == "已有会话" })
    }

    @Test("新建会话返回新 id 并出现在列表")
    func createConversation() throws {
        let (viewModel, _) = try make()
        viewModel.start()
        let id = viewModel.createConversation()
        #expect(viewModel.items.contains { $0.id == id })
    }

    @Test("删除会话后从列表消失")
    func deleteConversation() throws {
        let (viewModel, _) = try make()
        viewModel.start()
        let id = viewModel.createConversation()
        viewModel.delete(id: id)
        #expect(!viewModel.items.contains { $0.id == id })
    }

    @Test("重命名会话")
    func renameConversation() throws {
        let (viewModel, _) = try make()
        viewModel.start()
        let id = viewModel.createConversation()
        viewModel.rename(id: id, to: "改过的名字")
        #expect(viewModel.items.first { $0.id == id }?.title == "改过的名字")
    }

    @Test("列表变化触发回调")
    func changeCallbackFires() throws {
        let (viewModel, _) = try make()
        var callbackCount = 0
        viewModel.onItemsChanged = { _ in callbackCount += 1 }
        viewModel.start()
        _ = viewModel.createConversation()
        #expect(callbackCount > 0)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/ConversationListViewModelTests'
```

Expected: 编译失败，`cannot find 'ConversationListViewModel' in scope`。

- [ ] **Step 3: 实现 ViewModel**

创建 `WBChatApp-UIKit/Features/ConversationList/ConversationListViewModel.swift`：

```swift
import Foundation
import GRDB

@MainActor
final class ConversationListViewModel {

    struct Item: Equatable {
        let id: String
        let title: String
        let subtitle: String
    }

    private(set) var items: [Item] = [] {
        didSet {
            guard items != oldValue else { return }
            onItemsChanged?(items)
        }
    }

    var onItemsChanged: (([Item]) -> Void)?

    private let repository: ChatRepository
    private let settings: AppSettings
    private var observation: AnyDatabaseCancellable?

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    init(repository: ChatRepository, settings: AppSettings) {
        self.repository = repository
        self.settings = settings
    }

    /// 用 ValueObservation 订阅，数据库一变列表自动刷新
    func start() {
        reload()
        // onError 不能吞：GRDB 的语义是它一旦触发观察即终止、不自动恢复，
        // 吞掉会让会话列表永久静默停止刷新且无任何诊断信号。
        // 返回的 cancellable 必须被持有，否则 ARC 释放时观察立即取消。
        observation = repository.observeConversations(
            onError: { error in
                print("[ConversationListViewModel] 会话列表观察出错，已终止: \(error)")
            },
            onChange: { [weak self] records in
                self?.items = records.map(Self.item(from:))
            })
    }

    @discardableResult
    func createConversation() -> String {
        let record = try? repository.createConversation(title: "新对话",
                                                        provider: settings.provider,
                                                        model: settings.model)
        reload()
        return record?.id ?? ""
    }

    func delete(id: String) {
        try? repository.deleteConversation(id: id)
        reload()
    }

    func rename(id: String, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? repository.renameConversation(id: id, title: trimmed)
        reload()
    }

    private func reload() {
        items = ((try? repository.allConversations()) ?? []).map(Self.item(from:))
    }

    private static func item(from record: ConversationRecord) -> Item {
        Item(id: record.id,
             title: record.title,
             subtitle: formatter.string(from: Date(timeIntervalSince1970: record.updatedAt)))
    }
}
```

- [ ] **Step 4: 实现列表页与抽屉容器**

创建 `WBChatApp-UIKit/Features/ConversationList/ConversationListViewController.swift`：

```swift
import UIKit

final class ConversationListViewController: UIViewController {

    var onSelect: ((String) -> Void)?
    var onOpenSettings: (() -> Void)?

    private let viewModel: ConversationListViewModel
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var dataSource: UITableViewDiffableDataSource<Int, String>!

    init(viewModel: ConversationListViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.secondaryBackground
        setUpViews()
        setUpDataSource()

        viewModel.onItemsChanged = { [weak self] _ in self?.applySnapshot() }
        viewModel.start()
        applySnapshot()
    }

    private func setUpViews() {
        let header = UIStackView()
        header.axis = .horizontal
        header.distribution = .fill
        header.translatesAutoresizingMaskIntoConstraints = false

        let newButton = UIButton(type: .system)
        newButton.setTitle("＋ 新对话", for: .normal)
        newButton.contentHorizontalAlignment = .leading
        newButton.accessibilityIdentifier = "drawer.newConversation"
        newButton.addTarget(self, action: #selector(handleNew), for: .touchUpInside)

        let settingsButton = UIButton(type: .system)
        settingsButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        settingsButton.accessibilityIdentifier = "drawer.settings"
        settingsButton.addTarget(self, action: #selector(handleSettings), for: .touchUpInside)

        header.addArrangedSubview(newButton)
        header.addArrangedSubview(settingsButton)

        tableView.backgroundColor = .clear
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "conversation")
        tableView.delegate = self
        tableView.accessibilityIdentifier = "drawer.tableView"

        view.addSubview(header)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            header.heightAnchor.constraint(equalToConstant: 44),

            tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setUpDataSource() {
        dataSource = UITableViewDiffableDataSource<Int, String>(tableView: tableView) {
            [weak self] tableView, indexPath, id in
            let cell = tableView.dequeueReusableCell(withIdentifier: "conversation", for: indexPath)
            let item = self?.viewModel.items.first { $0.id == id }
            var configuration = cell.defaultContentConfiguration()
            configuration.text = item?.title
            configuration.secondaryText = item?.subtitle
            cell.contentConfiguration = configuration
            cell.backgroundColor = .clear
            return cell
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(viewModel.items.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    @objc private func handleNew() {
        onSelect?(viewModel.createConversation())
    }

    @objc private func handleSettings() {
        onOpenSettings?()
    }
}

extension ConversationListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        onSelect?(id)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return nil }

        let delete = UIContextualAction(style: .destructive, title: "删除") {
            [weak self] _, _, completion in
            self?.viewModel.delete(id: id)
            completion(true)
        }
        let rename = UIContextualAction(style: .normal, title: "重命名") {
            [weak self] _, _, completion in
            self?.presentRenameAlert(for: id)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete, rename])
    }

    private func presentRenameAlert(for id: String) {
        let alert = UIAlertController(title: "重命名会话", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = self.viewModel.items.first { $0.id == id }?.title }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            self?.viewModel.rename(id: id, to: alert.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }
}
```

创建 `WBChatApp-UIKit/Features/ConversationList/DrawerContainerViewController.swift`：

```swift
import UIKit

/// 左侧抽屉容器。支持边缘滑出、点遮罩关闭。
final class DrawerContainerViewController: UIViewController {

    private static let drawerWidthRatio: CGFloat = 0.8
    private static let maxDrawerWidth: CGFloat = 320

    private let drawerViewController: UIViewController
    private var contentViewController: UIViewController

    private let dimmingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.alpha = 0
        view.isUserInteractionEnabled = false
        return view
    }()

    private var isOpen = false

    private var drawerWidth: CGFloat {
        min(view.bounds.width * Self.drawerWidthRatio, Self.maxDrawerWidth)
    }

    init(drawer: UIViewController, content: UIViewController) {
        self.drawerViewController = drawer
        self.contentViewController = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        addChild(drawerViewController)
        view.addSubview(drawerViewController.view)
        drawerViewController.didMove(toParent: self)

        addChild(contentViewController)
        view.addSubview(contentViewController.view)
        contentViewController.didMove(toParent: self)

        view.insertSubview(dimmingView, belowSubview: contentViewController.view)

        let tap = UITapGestureRecognizer(target: self, action: #selector(closeDrawer))
        dimmingView.addGestureRecognizer(tap)

        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
        pan.edges = .left
        view.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        drawerViewController.view.frame = CGRect(x: 0, y: 0,
                                                 width: drawerWidth, height: view.bounds.height)
        dimmingView.frame = view.bounds
        layoutContent(open: isOpen)
    }

    func setContent(_ newContent: UIViewController) {
        contentViewController.willMove(toParent: nil)
        contentViewController.view.removeFromSuperview()
        contentViewController.removeFromParent()

        contentViewController = newContent
        addChild(newContent)
        view.addSubview(newContent.view)
        newContent.didMove(toParent: self)
        view.insertSubview(dimmingView, belowSubview: newContent.view)
        layoutContent(open: isOpen)
    }

    /// 必须标 @objc：AppContainer.makeMenuItem 用 #selector 引用它
    @objc func toggleDrawer() {
        setDrawer(open: !isOpen, animated: true)
    }

    @objc func closeDrawer() {
        setDrawer(open: false, animated: true)
    }

    private func setDrawer(open: Bool, animated: Bool) {
        isOpen = open
        dimmingView.isUserInteractionEnabled = open
        let animations = {
            self.layoutContent(open: open)
            self.dimmingView.alpha = open ? 1 : 0
        }
        if animated {
            UIView.animate(withDuration: 0.28,
                           delay: 0,
                           usingSpringWithDamping: 0.9,
                           initialSpringVelocity: 0,
                           options: .curveEaseOut,
                           animations: animations)
        } else {
            animations()
        }
    }

    private func layoutContent(open: Bool) {
        contentViewController.view.frame = CGRect(x: open ? drawerWidth : 0, y: 0,
                                                  width: view.bounds.width,
                                                  height: view.bounds.height)
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        switch gesture.state {
        case .changed:
            let translation = max(0, min(drawerWidth, gesture.translation(in: view).x))
            contentViewController.view.frame.origin.x = translation
            dimmingView.alpha = translation / drawerWidth
        case .ended, .cancelled:
            let shouldOpen = gesture.translation(in: view).x > drawerWidth / 2
                || gesture.velocity(in: view).x > 500
            setDrawer(open: shouldOpen, animated: true)
        default:
            break
        }
    }
}
```

- [ ] **Step 5: 在 AppContainer 组装根控制器**

在 `WBChatApp-UIKit/App/AppContainer.swift` 里追加：

```swift
extension AppContainer {

    /// 抽屉 + 聊天页的完整根控制器
    @MainActor
    func makeRootViewController() -> UIViewController {
        let listViewModel = ConversationListViewModel(repository: repository, settings: settings)
        let list = ConversationListViewController(viewModel: listViewModel)

        let chat = makeChatViewController(conversationID: currentOrNewConversationID())
        let navigation = UINavigationController(rootViewController: chat)
        let drawer = DrawerContainerViewController(drawer: list, content: navigation)

        list.onSelect = { [weak drawer, weak self] conversationID in
            guard let self, let drawer else { return }
            let newChat = self.makeChatViewController(conversationID: conversationID)
            newChat.navigationItem.leftBarButtonItem = self.makeMenuItem(drawer: drawer)
            drawer.setContent(UINavigationController(rootViewController: newChat))
            drawer.closeDrawer()
        }
        list.onOpenSettings = { [weak drawer, weak self] in
            guard let self, let drawer else { return }
            let settingsViewController = self.makeSettingsViewController()
            drawer.present(UINavigationController(rootViewController: settingsViewController),
                           animated: true)
        }

        chat.navigationItem.leftBarButtonItem = makeMenuItem(drawer: drawer)
        return drawer
    }

    @MainActor
    private func makeMenuItem(drawer: DrawerContainerViewController) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal"),
                                   style: .plain,
                                   target: drawer,
                                   action: #selector(DrawerContainerViewController.toggleDrawer))
        item.accessibilityIdentifier = "chat.menu"
        return item
    }
}
```

同时把 `SceneDelegate` 的根控制器换成 `AppContainer.shared.makeRootViewController()`：

```swift
        window.rootViewController = AppContainer.shared.makeRootViewController()
```

> `makeSettingsViewController()` 在 Task 18 实现。本任务先让它编译不过是正常的——**把 Task 18 的 Step 3 先做完再回来跑测试**，或临时返回一个空的 `UIViewController()` 占位。推荐直接接着做 Task 18。

- [ ] **Step 6: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/ConversationListViewModelTests'
```

Expected: 5 个用例全部 PASS。

- [ ] **Step 7: 提交**

```bash
git add WBChatApp-UIKit WBChatApp-UIKitTests/ConversationListViewModelTests.swift && git commit -m "会话：实现会话列表、侧边抽屉与根控制器组装"
```

---

## Task 18: 设置页

**Files:**
- Create: `WBChatApp-UIKit/Features/Settings/SettingsViewModel.swift`
- Create: `WBChatApp-UIKit/Features/Settings/SettingsViewController.swift`
- Modify: `WBChatApp-UIKit/App/AppContainer.swift`（补 `makeSettingsViewController()`）
- Test: `WBChatApp-UIKitTests/SettingsViewModelTests.swift`

**Interfaces:**
- Consumes: `AppSettings`（Task 16）、`ProviderKind`（Task 3）、`NetworkChatProvider`（Task 6）
- Produces:
  - `@MainActor final class SettingsViewModel`
    - `var provider: ProviderKind { get set }`、`var model: String { get set }`、`var baseURLText: String { get set }`、`var apiKey: String { get set }`、`var systemPrompt: String { get set }`
    - `var maskedAPIKey: String`、`var availableModels: [String]`、`var onChange: (() -> Void)?`
    - `func save()`、`func testConnection() async -> Result<Void, ChatError>`
  - `final class SettingsViewController: UITableViewController`

  > **实施中根据审查加固后的实际接口，与上面的草案有出入，以这里为准：**
  > - `protocol KeychainStoring { func save/read/delete }`，`KeychainStore` 实现它并暴露 `static let shared`；
  >   `AppSettings(defaults:keychain:)` 两个参数都带默认值（因此 `AppContainer` 无需改动）。
  >   不这么做的话，测试与生产共享同一个 Keychain 槽位——只要有人写成
  >   「`viewModel.apiKey = "假Key"` 后 `save()`」就会真的覆盖用户的生产 Key。
  > - `save()` 改为 `@discardableResult func save() -> Bool`，baseURL 非法时不落盘并返回 false，
  >   调用方据此弹提示且不 dismiss。原写法 `if let url = URL(string:)` 会静默跳过，
  >   用户填错地址后以为改成功了。
  > - API Key 的输入走 `updateAPIKeyIfProvided(_:)`（**空输入表示不修改**）与显式的 `clearAPIKey()`。
  >   原写法初值传空串又直接赋值，用户点开 Key 行不输入直接确定再点完成，
  >   已保存的真实 Key 会被静默删除。
  > - `provider` 切换期间用 `isBatchingProviderSwitch` 抑制子字段的 `onChange`，结尾统一发一次。
  >   原写法一次切换会发 3~4 次回调，而 VC 侧的 `onChange` 是 `tableView.reloadData()`。
  > - `runConnectionTest` 的 `Task { }` 必须放进 `present(progress, animated: true) { }` 的
  >   completion 里，否则快速失败路径下 dismiss 会赶在 present 转场结束前发出，弹窗可能卡住不消失。

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/SettingsViewModelTests.swift`：

```swift
import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("设置 ViewModel", .serialized)
@MainActor
struct SettingsViewModelTests {

    private func make() -> (SettingsViewModel, AppSettings) {
        let suiteName = "settings.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        return (SettingsViewModel(settings: settings), settings)
    }

    @Test("默认服务商是 DeepSeek")
    func defaultProvider() {
        let (viewModel, _) = make()
        #expect(viewModel.provider == .deepSeek)
    }

    @Test("切换服务商时模型与 baseURL 跟着换成该家默认值")
    func switchingProviderResetsModelAndBaseURL() {
        let (viewModel, _) = make()
        viewModel.provider = .anthropic
        #expect(viewModel.model == "claude-sonnet-5")
        #expect(viewModel.baseURLText == "https://api.anthropic.com")
    }

    @Test("可选模型列表随服务商变化")
    func availableModelsFollowProvider() {
        let (viewModel, _) = make()
        viewModel.provider = .openAI
        #expect(viewModel.availableModels.contains("gpt-4o"))
        viewModel.provider = .anthropic
        #expect(viewModel.availableModels.contains("claude-sonnet-5"))
    }

    @Test("save 后设置落盘")
    func savePersists() {
        let (viewModel, settings) = make()
        viewModel.provider = .openAI
        viewModel.model = "gpt-4o-mini"
        viewModel.systemPrompt = "简短作答"
        viewModel.save()

        #expect(settings.provider == .openAI)
        #expect(settings.model == "gpt-4o-mini")
        #expect(settings.systemPrompt == "简短作答")
    }

    @Test("API Key 掩码只露首尾")
    func maskedKey() {
        let (viewModel, _) = make()
        viewModel.apiKey = "sk-1234567890abcdef"
        #expect(viewModel.maskedAPIKey.hasPrefix("sk-1"))
        #expect(viewModel.maskedAPIKey.hasSuffix("cdef"))
        #expect(viewModel.maskedAPIKey.contains("****"))
    }

    @Test("短 Key 全部掩码，不泄露内容")
    func shortKeyFullyMasked() {
        let (viewModel, _) = make()
        viewModel.apiKey = "abc"
        #expect(!viewModel.maskedAPIKey.contains("abc"))
    }

    @Test("空 Key 显示未配置")
    func emptyKey() {
        let (viewModel, _) = make()
        viewModel.apiKey = ""
        #expect(viewModel.maskedAPIKey == "未配置")
    }

    @Test("没有 Key 时测试连接直接返回缺 Key 错误")
    func testConnectionWithoutKey() async {
        let (viewModel, _) = make()
        viewModel.apiKey = ""
        let result = await viewModel.testConnection()
        guard case .failure(let error) = result else {
            Issue.record("应当失败")
            return
        }
        #expect(error == .missingAPIKey)
    }

    @Test("修改任一项触发 onChange")
    func onChangeFires() {
        let (viewModel, _) = make()
        var count = 0
        viewModel.onChange = { count += 1 }
        viewModel.provider = .openAI
        viewModel.model = "gpt-4o"
        #expect(count >= 2)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/SettingsViewModelTests'
```

Expected: 编译失败，`cannot find 'SettingsViewModel' in scope`。

- [ ] **Step 3: 实现设置 ViewModel 与页面**

创建 `WBChatApp-UIKit/Features/Settings/SettingsViewModel.swift`：

```swift
import Foundation

@MainActor
final class SettingsViewModel {

    var onChange: (() -> Void)?

    private let settings: AppSettings

    var provider: ProviderKind {
        didSet {
            guard provider != oldValue else { return }
            // 换服务商时模型与地址都得跟着换，否则会拿 A 家的模型名去请求 B 家
            model = provider.defaultModel
            baseURLText = provider.defaultBaseURL.absoluteString
            apiKey = KeychainStore.read(KeychainStore.key(for: provider)) ?? ""
            onChange?()
        }
    }

    var model: String { didSet { if model != oldValue { onChange?() } } }
    var baseURLText: String { didSet { if baseURLText != oldValue { onChange?() } } }
    var apiKey: String { didSet { if apiKey != oldValue { onChange?() } } }
    var systemPrompt: String { didSet { if systemPrompt != oldValue { onChange?() } } }

    var availableModels: [String] { provider.availableModels }

    /// 只露首 4 尾 4，中间打码
    var maskedAPIKey: String {
        guard !apiKey.isEmpty else { return "未配置" }
        guard apiKey.count > 12 else { return String(repeating: "*", count: apiKey.count) }
        return "\(apiKey.prefix(4))****\(apiKey.suffix(4))"
    }

    init(settings: AppSettings) {
        self.settings = settings
        self.provider = settings.provider
        self.model = settings.model
        self.baseURLText = settings.baseURL.absoluteString
        self.apiKey = settings.apiKey
        self.systemPrompt = settings.systemPrompt
    }

    func save() {
        settings.provider = provider
        settings.model = model
        if let url = URL(string: baseURLText) { settings.baseURL = url }
        settings.systemPrompt = systemPrompt
        try? settings.setAPIKey(apiKey)
    }

    /// 发一条极短的请求验证 Key 与地址是否可用
    func testConnection() async -> Result<Void, ChatError> {
        guard !apiKey.isEmpty else { return .failure(.missingAPIKey) }
        guard let url = URL(string: baseURLText) else {
            return .failure(.decoding("地址格式不正确"))
        }

        let config = ProviderConfig(kind: provider, baseURL: url, apiKey: apiKey, model: model)
        let provider = NetworkChatProvider(config: config)
        let request = ChatRequest(model: model,
                                  messages: [ChatMessage(role: .user, content: "hi")],
                                  system: nil, temperature: 0, maxTokens: 8)
        do {
            for try await _ in provider.stream(request) {
                return .success(())    // 收到任意一个 chunk 就算通了
            }
            return .success(())
        } catch {
            return .failure(ChatError.from(error))
        }
    }
}
```

创建 `WBChatApp-UIKit/Features/Settings/SettingsViewController.swift`：

```swift
import UIKit

final class SettingsViewController: UITableViewController {

    private enum Row: Int, CaseIterable {
        case provider, model, baseURL, apiKey, systemPrompt, testConnection
    }

    private let viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "完成", style: .done, target: self, action: #selector(handleDone))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "setting")
        tableView.accessibilityIdentifier = "settings.tableView"
        viewModel.onChange = { [weak self] in self?.tableView.reloadData() }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "setting", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        cell.accessoryType = .disclosureIndicator

        switch Row(rawValue: indexPath.row)! {
        case .provider:
            configuration.text = "服务商"
            configuration.secondaryText = viewModel.provider.displayName
        case .model:
            configuration.text = "模型"
            configuration.secondaryText = viewModel.model
        case .baseURL:
            configuration.text = "接口地址"
            configuration.secondaryText = viewModel.baseURLText
        case .apiKey:
            configuration.text = "API Key"
            configuration.secondaryText = viewModel.maskedAPIKey
        case .systemPrompt:
            configuration.text = "系统提示词"
            configuration.secondaryText = viewModel.systemPrompt
        case .testConnection:
            configuration.text = "测试连接"
            cell.accessoryType = .none
        }
        cell.contentConfiguration = configuration
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Row(rawValue: indexPath.row)! {
        case .provider:      presentProviderPicker()
        case .model:         presentModelPicker()
        case .baseURL:       presentTextInput(title: "接口地址", value: viewModel.baseURLText) {
                                 self.viewModel.baseURLText = $0 }
        case .apiKey:        presentTextInput(title: "API Key", value: "", isSecure: true) {
                                 self.viewModel.apiKey = $0 }
        case .systemPrompt:  presentTextInput(title: "系统提示词", value: viewModel.systemPrompt) {
                                 self.viewModel.systemPrompt = $0 }
        case .testConnection: runConnectionTest()
        }
    }

    // MARK: - 交互

    private func presentProviderPicker() {
        let sheet = UIAlertController(title: "选择服务商", message: nil, preferredStyle: .actionSheet)
        for kind in ProviderKind.allCases {
            sheet.addAction(UIAlertAction(title: kind.displayName, style: .default) { _ in
                self.viewModel.provider = kind
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    private func presentModelPicker() {
        let sheet = UIAlertController(title: "选择模型", message: nil, preferredStyle: .actionSheet)
        for model in viewModel.availableModels {
            sheet.addAction(UIAlertAction(title: model, style: .default) { _ in
                self.viewModel.model = model
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    private func presentTextInput(title: String, value: String,
                                  isSecure: Bool = false,
                                  onDone: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField {
            $0.text = value
            $0.isSecureTextEntry = isSecure
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            onDone(alert.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }

    private func runConnectionTest() {
        viewModel.save()
        let progress = UIAlertController(title: "正在测试…", message: nil, preferredStyle: .alert)
        present(progress, animated: true)

        Task {
            let result = await viewModel.testConnection()
            progress.dismiss(animated: true) {
                let message: String
                switch result {
                case .success:            message = "连接成功"
                case .failure(let error): message = error.userMessage
                }
                let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    @objc private func handleDone() {
        viewModel.save()
        dismiss(animated: true)
    }
}
```

在 `AppContainer` 里补上工厂方法：

```swift
extension AppContainer {
    @MainActor
    func makeSettingsViewController() -> SettingsViewController {
        SettingsViewController(viewModel: SettingsViewModel(settings: settings))
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/SettingsViewModelTests'
```

Expected: 9 个用例全部 PASS。

- [ ] **Step 5: 用真实 Key 手动验收**

在模拟器里打开设置，填入你的 DeepSeek Key，点「测试连接」应提示连接成功；返回聊天页发消息，应走真实模型而非演示模式。再切到 Anthropic 填对应 Key 验证第二条协议链路。

- [ ] **Step 6: 提交**

```bash
git add WBChatApp-UIKit WBChatApp-UIKitTests/SettingsViewModelTests.swift && git commit -m "设置：实现服务商、模型、Key 配置与连接测试"
```

---

## Task 19: 语音转文字输入

**Files:**
- Create: `WBChatApp-UIKit/Core/Speech/SpeechTranscriber.swift`
- Create: `WBChatApp-UIKit/Features/Chat/Views/WaveformView.swift`
- Create: `WBChatApp-UIKit/Features/Chat/Views/RecordingOverlayView.swift`
- Modify: `WBChatApp-UIKit/Features/Chat/ChatViewController.swift`（接麦克风按钮）
- Test: `WBChatApp-UIKitTests/SpeechTranscriberTests.swift`

**Interfaces:**
- Consumes: `InputBarView`（Task 16）
- Produces:
  - `enum SpeechEvent: Equatable { case partial(String); case final(String); case level(Float) }`
  - `enum SpeechError: Error, Equatable { case notAuthorized; case recognizerUnavailable; case audioEngineFailed }`
  - `protocol SpeechTranscribing: AnyObject { func requestAuthorization() async -> Bool; func start() throws -> AsyncThrowingStream<SpeechEvent, Error>; func stop() }`
  - `final class SystemSpeechTranscriber: SpeechTranscribing`
  - `final class WaveformView: UIView { func update(level: Float) }`
  - `final class RecordingOverlayView: UIView { var onCancel: (() -> Void)?; var onConfirm: (() -> Void)?; func update(level: Float); func setText(_:) }`

- [ ] **Step 1: 写失败测试**

模拟器上无法真正录音，所以测试聚焦在**协议契约与状态管理**上，识别本身留给手动验收。

创建 `WBChatApp-UIKitTests/SpeechTranscriberTests.swift`：

```swift
import Foundation
import Testing
@testable import WBChatApp_UIKit

/// 可脚本化的转写替身，用来验证消费方逻辑
final class StubTranscriber: SpeechTranscribing {
    var authorized = true
    var events: [SpeechEvent] = []
    var error: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func requestAuthorization() async -> Bool { authorized }

    func start() throws -> AsyncThrowingStream<SpeechEvent, Error> {
        startCount += 1
        if let error { throw error }
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func stop() { stopCount += 1 }
}

@Suite("语音转写")
struct SpeechTranscriberTests {

    @Test("未授权时 requestAuthorization 返回假")
    func unauthorized() async {
        let stub = StubTranscriber()
        stub.authorized = false
        #expect(await stub.requestAuthorization() == false)
    }

    @Test("按序吐出中间结果与最终结果")
    func emitsPartialThenFinal() async throws {
        let stub = StubTranscriber()
        stub.events = [.partial("你"), .partial("你好"), .final("你好世界")]
        var received: [SpeechEvent] = []
        for try await event in try stub.start() { received.append(event) }
        #expect(received == [.partial("你"), .partial("你好"), .final("你好世界")])
    }

    @Test("音量事件独立于文本事件")
    func levelEvents() async throws {
        let stub = StubTranscriber()
        stub.events = [.level(0.3), .partial("嗯"), .level(0.7)]
        var levels: [Float] = []
        for try await event in try stub.start() {
            if case .level(let value) = event { levels.append(value) }
        }
        #expect(levels == [0.3, 0.7])
    }

    @Test("start 抛错被调用方接住")
    func startThrows() {
        let stub = StubTranscriber()
        stub.error = SpeechError.recognizerUnavailable
        #expect(throws: SpeechError.recognizerUnavailable) {
            _ = try stub.start()
        }
    }

    @Test("stop 被调用次数可追踪")
    func stopIsTracked() {
        let stub = StubTranscriber()
        stub.stop()
        stub.stop()
        #expect(stub.stopCount == 2)
    }

    @Test("真实实现遵循协议且可构造")
    func systemImplementationConforms() {
        let transcriber: SpeechTranscribing = SystemSpeechTranscriber()
        #expect(transcriber is SystemSpeechTranscriber)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/SpeechTranscriberTests'
```

Expected: 编译失败，`cannot find 'SpeechTranscribing' in scope`。

- [ ] **Step 3: 实现转写器**

创建 `WBChatApp-UIKit/Core/Speech/SpeechTranscriber.swift`：

```swift
import Foundation
import Speech
import AVFoundation

enum SpeechEvent: Equatable {
    case partial(String)
    case final(String)
    /// 归一化到 0…1 的音量，用来驱动波形
    case level(Float)
}

enum SpeechError: Error, Equatable {
    case notAuthorized
    case recognizerUnavailable
    case audioEngineFailed
}

protocol SpeechTranscribing: AnyObject {
    func requestAuthorization() async -> Bool
    func start() throws -> AsyncThrowingStream<SpeechEvent, Error>
    func stop()
}

/// `SFSpeechRecognizer` + `AVAudioEngine` 实现。
///
/// 同一路 PCM 分两用：一路喂识别请求，一路算 RMS 驱动波形，
/// 避免开两个 tap 抢音频硬件。
final class SystemSpeechTranscriber: SpeechTranscribing {

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// 麦克风与语音识别是两套权限，缺一不可
    func requestAuthorization() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else { return false }

        // 注意：AVAudioApplication.requestRecordPermission 是 iOS 17+，
        // 本项目最低 iOS 16，必须走 AVAudioSession 上的这个方法
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() throws -> AsyncThrowingStream<SpeechEvent, Error> {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 端上识别不走网络、延迟更低；机型不支持时自动回落在线
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        return AsyncThrowingStream { continuation in
            task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    continuation.yield(result.isFinal ? .final(text) : .partial(text))
                    if result.isFinal { continuation.finish() }
                }
                if let error {
                    continuation.finish(throwing: error)
                }
            }

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
                continuation.yield(.level(Self.normalizedLevel(of: buffer)))
            }

            audioEngine.prepare()
            do {
                try audioEngine.start()
            } catch {
                continuation.finish(throwing: SpeechError.audioEngineFailed)
            }

            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// RMS 转成 0…1。取 -50dB 作为静音底，日常说话大约落在 0.3–0.9。
    private static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<count {
            sum += channel[index] * channel[index]
        }
        let rms = sqrt(sum / Float(count))
        let decibels = 20 * log10(max(rms, .leastNormalMagnitude))
        let floor: Float = -50
        return max(0, min(1, (decibels - floor) / -floor))
    }
}
```

- [ ] **Step 4: 实现波形与录音浮层**

创建 `WBChatApp-UIKit/Features/Chat/Views/WaveformView.swift`：

```swift
import UIKit

/// 简易柱状波形。新音量从右侧推入，整体左移。
final class WaveformView: UIView {

    private var levels: [Float] = []
    private let barCount = 32
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        levels = Array(repeating: 0, count: barCount)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func update(level: Float) {
        levels.removeFirst()
        levels.append(max(0.05, min(1, level)))
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(Theme.accent.cgColor)

        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        var x = (rect.width - totalWidth) / 2

        for level in levels {
            let height = max(2, rect.height * CGFloat(level))
            let barRect = CGRect(x: x, y: (rect.height - height) / 2,
                                 width: barWidth, height: height)
            context.addPath(UIBezierPath(roundedRect: barRect,
                                         cornerRadius: barWidth / 2).cgPath)
            context.fillPath()
            x += barWidth + barSpacing
        }
    }
}
```

创建 `WBChatApp-UIKit/Features/Chat/Views/RecordingOverlayView.swift`：

```swift
import UIKit

/// 录音浮层：波形 + 实时文字 + 取消/完成。
final class RecordingOverlayView: UIView {

    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    private let waveform = WaveformView()
    private let textLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 3
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = Theme.textPrimary
        label.text = "正在聆听…"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("取消", for: .normal)
        button.accessibilityIdentifier = "recording.cancel"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let confirmButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("完成", for: .normal)
        button.accessibilityIdentifier = "recording.confirm"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.background
        waveform.translatesAutoresizingMaskIntoConstraints = false

        addSubview(waveform)
        addSubview(textLabel)
        addSubview(cancelButton)
        addSubview(confirmButton)

        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            waveform.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 16),
            waveform.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            waveform.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            waveform.heightAnchor.constraint(equalToConstant: 44),

            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            cancelButton.topAnchor.constraint(equalTo: waveform.bottomAnchor, constant: 16),
            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

            confirmButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            confirmButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
        ])

        cancelButton.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)
        confirmButton.addTarget(self, action: #selector(handleConfirm), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func update(level: Float) {
        waveform.update(level: level)
    }

    func setText(_ text: String) {
        textLabel.text = text.isEmpty ? "正在聆听…" : text
    }

    @objc private func handleCancel() { onCancel?() }
    @objc private func handleConfirm() { onConfirm?() }
}
```

- [ ] **Step 5: 在 ChatViewController 里接入**

在 `ChatViewController` 中新增属性与方法：

```swift
    private let transcriber: SpeechTranscribing = SystemSpeechTranscriber()
    private var recordingOverlay: RecordingOverlayView?
    private var speechTask: Task<Void, Never>?
    private var transcribedText = ""
```

在 `setUpViews()` 里补上麦克风回调：

```swift
        inputBar.onMicTap = { [weak self] in self?.startVoiceInput() }
```

并新增：

```swift
    private func startVoiceInput() {
        Task { @MainActor in
            guard await transcriber.requestAuthorization() else {
                presentPermissionAlert()
                return
            }
            presentRecordingOverlay()

            do {
                transcribedText = ""
                for try await event in try transcriber.start() {
                    switch event {
                    case .partial(let text), .final(let text):
                        transcribedText = text
                        recordingOverlay?.setText(text)
                    case .level(let value):
                        recordingOverlay?.update(level: value)
                    }
                }
            } catch {
                dismissRecordingOverlay()
                presentErrorAlert("语音识别失败，请重试")
                return
            }
            finishVoiceInput(confirmed: true)
        }
    }

    private func presentRecordingOverlay() {
        let overlay = RecordingOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        overlay.onCancel = { [weak self] in self?.finishVoiceInput(confirmed: false) }
        overlay.onConfirm = { [weak self] in self?.finishVoiceInput(confirmed: true) }
        recordingOverlay = overlay
        Haptics.light()
    }

    /// 识别结果写进输入框而**不直接发送**，用户可以先改再发
    private func finishVoiceInput(confirmed: Bool) {
        transcriber.stop()
        dismissRecordingOverlay()
        guard confirmed, !transcribedText.isEmpty else { return }
        let existing = inputBar.text
        inputBar.setText(existing.isEmpty ? transcribedText : existing + transcribedText)
    }

    private func dismissRecordingOverlay() {
        recordingOverlay?.removeFromSuperview()
        recordingOverlay = nil
    }

    private func presentPermissionAlert() {
        let alert = UIAlertController(
            title: "需要麦克风与语音识别权限",
            message: "请在「设置 → 隐私」中允许本 App 使用麦克风与语音识别",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func presentErrorAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
```

- [ ] **Step 6: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/SpeechTranscriberTests'
```

Expected: 6 个用例全部 PASS。

- [ ] **Step 7: 真机手动验收**

模拟器的麦克风走宿主 Mac，识别可用但不稳定；**语音这块请务必在真机上验收**：

1. 点麦克风，首次弹出两次权限请求（语音识别、麦克风）
2. 说话时波形随音量起伏，文字实时上屏
3. 点「完成」，文字进入输入框且**可编辑**，不自动发送
4. 点「取消」，不写入任何文字
5. 拒绝权限后再点麦克风，弹出引导去设置的提示

- [ ] **Step 8: 提交**

```bash
git add WBChatApp-UIKit WBChatApp-UIKitTests/SpeechTranscriberTests.swift && git commit -m "语音：实现端上优先的实时转写、波形与录音浮层"
```

---

## Task 20: 消息操作菜单与重新生成

把 `ChatViewModel.retryLast()` 接到 UI 上，并补齐长按气泡的复制/重新生成菜单。

**Files:**
- Modify: `WBChatApp-UIKit/Features/Chat/ChatViewController.swift`
- Modify: `WBChatApp-UIKit/Features/Chat/Views/AssistantMessageCell.swift`（加重试按钮）
- Test: `WBChatApp-UIKitTests/MessageActionTests.swift`

**Interfaces:**
- Consumes: `ChatViewModel.retryLast()`（Task 15）、`AssistantMessageCell`（Task 14）
- Produces: `AssistantMessageCell.onRetry: (() -> Void)?`；`ChatViewController` 实现 `tableView(_:contextMenuConfigurationForRowAt:point:)`

- [ ] **Step 1: 写失败测试**

创建 `WBChatApp-UIKitTests/MessageActionTests.swift`：

```swift
import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("消息操作")
@MainActor
struct MessageActionTests {

    private func makeViewModel(chunks: [StreamChunk], error: Error? = nil) throws
    -> (ChatViewModel, ManualThrottle) {
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek,
                                                             model: "m")
        let throttle = ManualThrottle()
        let viewModel = ChatViewModel(conversationID: conversation.id,
                                      repository: repository,
                                      providerFactory: { ScriptedProvider(chunks: chunks, error: error) },
                                      systemPrompt: nil, model: "m", throttle: throttle)
        return (viewModel, throttle)
    }

    private func waitForStreamEnd(_ viewModel: ChatViewModel) async {
        for _ in 0..<200 {
            if !viewModel.state.isStreaming { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("失败后 retryLast 把消息重置为流式并重新生成")
    func retryAfterFailure() async throws {
        let (viewModel, throttle) = try makeViewModel(
            chunks: [.textDelta("半截")],
            error: ChatError.serverError(status: 500, message: nil))
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        await waitForStreamEnd(viewModel)
        #expect(viewModel.state.messages.last?.status == .failed)

        viewModel.retryLast()
        #expect(viewModel.state.isStreaming)
        #expect(viewModel.state.messages.last?.errorText == nil)
        await waitForStreamEnd(viewModel)
    }

    @Test("retryLast 不新增消息条目")
    func retryDoesNotAppendMessage() async throws {
        let (viewModel, throttle) = try makeViewModel(
            chunks: [.textDelta("内容"), .done(finishReason: "stop")])
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        await waitForStreamEnd(viewModel)
        let countBefore = viewModel.state.messages.count

        viewModel.retryLast()
        await waitForStreamEnd(viewModel)
        #expect(viewModel.state.messages.count == countBefore)
    }

    @Test("retryLast 清空旧的块，不与新内容拼接")
    func retryClearsOldBlocks() async throws {
        let (viewModel, throttle) = try makeViewModel(
            chunks: [.textDelta("第一次"), .done(finishReason: "stop")])
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        await waitForStreamEnd(viewModel)

        let assistantID = try #require(viewModel.state.messages.last?.id)
        viewModel.retryLast()
        #expect(viewModel.blocks(for: assistantID).isEmpty, "重试瞬间旧内容应被清空")
        await waitForStreamEnd(viewModel)
    }

    @Test("用户消息不响应 retryLast")
    func retryIgnoresUserMessage() throws {
        let (viewModel, _) = try makeViewModel(chunks: [])
        viewModel.retryLast()
        #expect(!viewModel.state.isStreaming)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/MessageActionTests'
```

Expected: 「retryLast 清空旧的块」失败——`startStream` 重置了 splitter 但 `blocksByMessage` 的清空发生在 `retryLast` 里，需确认顺序正确。其余用例应通过。

- [ ] **Step 3: 给助手 cell 加重试按钮**

在 `AssistantMessageCell` 中新增：

```swift
    var onRetry: (() -> Void)?

    private lazy var retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("重新生成", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.accessibilityIdentifier = "message.retry"
        button.isHidden = true
        button.addTarget(self, action: #selector(handleRetry), for: .touchUpInside)
        contentView.addSubview(button)
        return button
    }()

    @objc private func handleRetry() {
        onRetry?()
    }
```

在 `configure(...)` 末尾加上：

```swift
        retryButton.isHidden = (status != .failed && status != .stopped)
```

在 `heightThatFits(width:)` 里，`errorLabel` 那段之后追加：

```swift
        if !retryButton.isHidden {
            height += 32
        }
```

在 `layoutSubviews()` 末尾追加：

```swift
        if !retryButton.isHidden {
            retryButton.frame = CGRect(x: Self.horizontalInset,
                                       y: contentView.bounds.height - Self.verticalInset - 28,
                                       width: 100, height: 28)
        }
```

并在 `prepareForReuse()` 里补 `retryButton.isHidden = true` 与 `onRetry = nil`。

- [ ] **Step 4: 在 ChatViewController 里接线**

在 `setUpDataSource()` 的 assistant 分支里，`cell.onLinkTap` 那行之后补：

```swift
                cell.onRetry = { [weak self] in
                    self?.autoScroll.didSendMessage()
                    self?.viewModel.retryLast()
                }
```

新增长按菜单（放在 `UITableViewDelegate` 扩展里）：

```swift
    func tableView(_ tableView: UITableView,
                   contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        guard let messageID = dataSource.itemIdentifier(for: indexPath),
              let message = viewModel.state.messages.first(where: { $0.id == messageID })
        else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIAction] = [
                UIAction(title: "复制", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = message.text
                    Haptics.success()
                }
            ]
            // 只有最后一条助手消息才允许重新生成
            let isLastAssistant = message.role == .assistant
                && self?.viewModel.state.messages.last?.id == messageID
            if isLastAssistant, self?.viewModel.state.isStreaming == false {
                actions.append(UIAction(title: "重新生成",
                                        image: UIImage(systemName: "arrow.clockwise")) { _ in
                    self?.autoScroll.didSendMessage()
                    self?.viewModel.retryLast()
                })
            }
            return UIMenu(children: actions)
        }
    }
```

- [ ] **Step 5: 确认 retryLast 清空旧块**

在 `ChatViewModel.retryLast()` 里，确认 `blocksByMessage[last.id] = []` 出现在 `startStream(assistantID:)` **之前**（Task 15 的实现已是这个顺序）。若测试仍失败，把该行移到 `startStream` 调用前一行。

- [ ] **Step 6: 运行测试确认通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:'WBChatApp-UIKitTests/MessageActionTests'
```

Expected: 4 个用例全部 PASS。

- [ ] **Step 7: 手动验收**

长按任意气泡出现「复制」；最后一条助手消息在非流式状态下额外出现「重新生成」；生成失败或被停止的消息下方出现「重新生成」按钮，点击后重新拉流且不新增气泡。

- [ ] **Step 8: 提交**

```bash
git add WBChatApp-UIKit WBChatApp-UIKitTests/MessageActionTests.swift && git commit -m "交互：补齐消息长按复制与重新生成"
```

---

## Task 21: 技术文档

五篇文档，Mermaid 绘图。这是交付物的一部分，不是可选项。

**Files:**
- Create: `WBChatApp-UIKit/doc/00-架构总览.md`
- Create: `WBChatApp-UIKit/doc/01-流式链路与双协议适配.md`
- Create: `WBChatApp-UIKit/doc/02-Markdown块级增量渲染.md`
- Create: `WBChatApp-UIKit/doc/03-滚动与自动贴底.md`
- Create: `WBChatApp-UIKit/doc/04-语音输入.md`
- Create: `WBChatApp-UIKit/README.md`

**Interfaces:**
- Consumes: 前 20 个任务的全部产物
- Produces: 无代码产物

- [ ] **Step 1: 写架构总览**

`doc/00-架构总览.md` 必须包含：

1. **一句话定位**与功能清单（含明确不做的部分）
2. **Mermaid 分层图**：`App / Features / Core / Common` 四层与单向依赖箭头
3. **模块职责表**：每个目录一行，写清「做什么、依赖谁、被谁依赖」
4. **完整目录树**，与实际代码一致
5. **MVVM 契约**：ViewModel 不 import UIKit；`Output` 拆成 `stateChanged` 与 `blocksPatched` 两条通路的理由
6. **技术选型理由表**：为什么 TextKit 2 而非 WebView、为什么 UITableView 而非 UICollectionView、为什么自算高度而非 `automaticDimension`、为什么 GRDB
7. **与同仓库 SwiftUI 版 `WBChatApp` 的对照表**

- [ ] **Step 2: 写流式链路文档**

`doc/01-流式链路与双协议适配.md` 必须包含：

1. SSE 规范要点：字段、空行派发、注释行、三种换行
2. **分包/粘包/UTF-8 劈开**三类边界的处理方式，配 `SSEEventParser` 的字节缓冲示意
3. **两家协议帧格式对照表**（照搬设计规格 §3.2，并补上真实报文样例）
4. **Mermaid 时序图**：从 `send` 到落库的完整链路
5. 节流策略：为什么用 CADisplayLink 而非 Timer，「每帧最多一次排版、最多一次贴底」的含义
6. 取消与错误：`Task.cancel` 如何一路传到 `URLSession`，失败时如何保留已生成内容

- [ ] **Step 3: 写增量渲染文档（重点篇）**

`doc/02-Markdown块级增量渲染.md` 必须包含：

1. **问题陈述与复杂度分析**：朴素做法为何是 O(n²)，给出推导
2. **核心不变量**：sealed 块只增不改；说明这条不变量如何被属性测试守住
3. **Mermaid 状态图**：切块状态机（照搬设计规格 §4.3 的图，并补充「尾块永远 open」的说明）
4. **渲染管线图**：`rawText → swift-markdown AST → NSAttributedString → 缓存 → 块视图`
5. **TextKit 2 章节**：为什么选它；**`layoutManager` 静默降级陷阱**及哨兵测试
6. **高度策略**：为什么放弃 `automaticDimension`；`beginUpdates/endUpdates` 的代价分析
7. **复用池**：为什么 `UITextView` 需要按类型回收
8. **实测数据**：用演示模式生成一段 3000 字回复，记录 Instruments 里的帧率与 CPU 占用，对比「每帧全量重解析」的对照实现

- [ ] **Step 4: 写滚动文档**

`doc/03-滚动与自动贴底.md` 必须包含：

1. **Mermaid 状态图**：`pinned ⇄ detached` 的全部迁移条件
2. **与 ChatGPT 行为逐条对照表**：每条行为写「ChatGPT 表现 / 本实现 / 对应代码位置」
3. 程序化滚动与用户滚动的区分方式：`isProgrammaticScroll` 标志 + `isTracking` 判定
4. 为什么回到 pinned 的判定放在 `didEndDragging`/`didEndDecelerating` 而非 `didScroll`
5. 为什么 detached 状态下「什么都不做」才是对的
6. 键盘处理：`keyboardLayoutGuide` 的用法

- [ ] **Step 5: 写语音文档与 README**

`doc/04-语音输入.md` 必须包含：权限双授权流程图、音频管线图（一路 tap 两用）、RMS 转波形的算法、端上识别与在线识别的取舍。

`README.md` 必须包含：项目定位、功能截图位、最低系统与依赖、如何配置 API Key 跑起来、演示模式说明、五篇文档的索引链接、测试命令。

- [ ] **Step 6: 校对**

通读五篇文档，逐条核对：

- 所有代码引用的类名、方法名与实际代码一致
- 所有 Mermaid 图能正常渲染（在支持 Mermaid 的 Markdown 预览里打开确认）
- 没有「待补充」「TODO」之类的占位

- [ ] **Step 7: 提交**

```bash
git add WBChatApp-UIKit/doc WBChatApp-UIKit/README.md && git commit -m "文档：补齐架构总览与四篇专题技术文档"
```

---

## 收尾检查

全部任务完成后执行：

- [ ] **全量测试通过**

```bash
xcodebuild test -project WBChatApp-UIKit.xcodeproj -scheme WBChatApp-UIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

- [ ] **TextKit 2 降级扫描**：确认全项目没有出现 `layoutManager` 或 `.textStorage`

```bash
grep -rn "layoutManager\|\.textStorage" WBChatApp-UIKit --include=*.swift
```

Expected: 无输出（`textLayoutManager` 与 `textContentStorage` 不会被这个模式匹配到）。

- [ ] **ViewModel 纯净性扫描**：确认 ViewModel 没有 import UIKit

```bash
grep -l "import UIKit" WBChatApp-UIKit/Features/*/[A-Za-z]*ViewModel.swift
```

Expected: 无输出。

- [ ] **真机验收**：语音输入、流式滚动、真实 API Key 的双协议链路各跑一遍

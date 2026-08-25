# AiChat 打字机效果 CADisplayLink 重构方案

> 涉及文件：`Module/AiChat/Model/SWAiChatTypewriter.swift`（新增）· `SWAiChatViewController.swift` · `Model/SWAiChatMessage.swift` · `View/SWAiChatMessageCell.swift` · `Model/SWAiChatSSEClient.swift`
> 一句话：**串行队列 + 信号量 + 每 chunk 一个 Timer** → **单字符缓冲区 + 一条 CADisplayLink**，逻辑全部收归主线程，保序由数据结构天然保证，UI 刷新按帧合并。

---

## 一、为什么要改

原实现（`SWAiChatViewController.swift` 改造前 :530-557）用三个并发原语拼出"多 chunk 顺序播放"：

| 原语 | 原职责 |
|---|---|
| `typingQueues[taskId]` 串行队列 | 让多个 chunk 按到达顺序排队 |
| `DispatchSemaphore(value: 0)` | 阻塞队列线程，等主线程 Timer 打完当前 chunk |
| 每 chunk 一个 `Timer`（0.03s） | 主线程逐字追加 |

代价：

1. **后台线程被长期阻塞**。一个 100 字的 chunk 会让串行队列线程 `semaphore.wait()` 阻塞约 3 秒，期间 GCD 只能新建线程处理其它任务；密集会话下有线程膨胀风险。
2. **清理路径分散**。`typingQueues`、`SWAiChatMessage.currentTimer`、semaphore 三者要在"停止生成 / workflow_finished / onError"三条路径上分别处理，漏一处就会出现"已结束仍在追加字符"。
3. **调试困难**。Timer 回调在主线程、`wait()` 在后台线程，出问题时调用栈割裂。
4. **性能**。
   - Timer 固定 0.03s 与屏幕 vsync 不对齐，节奏有细微抖动；
   - 每追加 **1 个字符**就跑一次全量 `content.boundingRect`，长回答是 O(n²)；
   - 每个字符还要调用一次 `scrollToRow`，且无论用户是否正在上翻查看历史，都会被强制拉回底部。

---

## 二、新方案

### 2.1 结构

```
SSE text_chunk (主线程)
   └─ typewriter.append(text)     所有 chunk 进同一个缓冲区，先到先入
                                        ↓
        [ pending: [Character] + cursor ]
                                        ↓ CADisplayLink 每帧消费一次
   onOutput("本帧应追加的若干字符")  →  message.appendContent(chunk)
                                     →  updateLastCell(高度是否变化)
   workflow_finished
   └─ typewriter.finish() → 缓冲排空 → onDrained → finishAnswer
```

**保序性**：所有 chunk 都在主线程按 `append` 调用顺序写入同一个数组，消费端是单一游标顺序读取——顺序由数据结构本身保证，不再需要队列与信号量。

### 2.2 出字节奏：按帧预算 + 自适应提速

```swift
let duration = max(link.targetTimestamp - link.timestamp, 0)   // 兼容 60/120Hz
let speed = baseSpeed * min(maxSpeedMultiplier, max(1, Double(remaining) / backlogThreshold))
budget += duration * speed
let count = min(Int(budget), remaining)                        // 本帧出几个字
budget -= Double(count)
```

- `baseSpeed = 33` 字/秒，与改造前 0.03s/字 的观感一致；
- 积压超过 `backlogThreshold = 40` 字开始提速，上限 6 倍：长回答不会在流结束后还要慢慢打很久，缓冲也不会无限堆积；
- 不足 1 个字符的预算留到下一帧，节奏均匀且与 vsync 对齐；
- iOS 15+ 用 `CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)`，避免 ProMotion 上 120Hz 空转。

### 2.3 每帧只刷一次 UI

`onOutput` 每帧最多回调一次，把本帧的 N 个字符**拼成一个字符串**一次性交给上层。因此一帧内至多：

- 一次 `content` 赋值 → 一次 `boundingRect`
- 一次 `cell.configure`
- 一次 `beginUpdates/endUpdates`（仅当气泡高度变化）
- 一次 `scrollToRow`（仅当高度变化且用户仍在底部）

这是相对旧实现的主要性能收益：旧实现是"每字符一次全量测量 + 一次滚动"，新实现在流速快时会自动合并。

### 2.4 生命周期

`CADisplayLink` 会强引用 target，引擎内部用私有 `SWAiChatDisplayLinkProxy`（弱引用 target）转发，`deinit` 中 `invalidate()`。缓冲空且未收到结束信号时 link 保留但不出字，`cancel()` / 排空后 `invalidate()` 并复位。

调用方三条收尾路径各自只需要一行：

| 场景 | 处理 |
|---|---|
| `workflow_finished` | `onDrained = { finishAnswer }` + `finish()`（把已收到的字符打完再收尾） |
| 用户点"停止生成" | `cancel()`（立即停字并丢弃缓冲） |
| `onError` | `finish()`（不丢弃已收到内容），排空后走兜底文案 |
| 页面退出 / deinit | `cancel()` |

---

## 三、顺带修复

### 3.1 `messageQueue` 是计算属性（读写保护完全失效）

```swift
// 改造前：每次访问都新建一个 concurrent 队列
private var messageQueue: DispatchQueue {
    DispatchQueue(label: "com.swaichat.message.queue", attributes: .concurrent)
}
```

每条 SSE 消息、每次落库都会新建一个队列并触发一次线程调度，且 `.barrier` 保护的是各自不同的队列——对 `messageList` 的读写保护实际上不存在。改为 stored 属性，`.barrier` 才真正生效。同时删掉从未被使用的 `uiQueue`。

### 3.2 SSE buffer 跨包丢字符

```swift
// 改造前：每次 didReceive 末尾无条件清空
buffer = Data()   // 一行 JSON 被网络分包截断时，首段被整段丢弃 → 丢字
```

改为按 `\n` 只消费**完整行**，末尾不完整的一行留在 buffer 里等待下一个数据包；顺带兼容 `\r\n`，并把"单行解析失败就 `return` 中断整包"改成跳过该行继续处理。

### 3.3 流式过程中的富文本构造

`SWAiChatMessageCell.updateContent` 在流式阶段（`linkStr` 恒为空）不再每帧构造 `NSMutableAttributedString`，直接赋 `text` + `textColor`；只有带链接的终态才走富文本分支。

---

## 四、改造前后对比

| 维度 | 改造前 | 改造后 |
|---|---|---|
| 并发原语 | 串行队列 × taskId + Semaphore + Timer × chunk | 无（单条 CADisplayLink） |
| 线程 | 主线程 + 每个 taskId 一条被阻塞的后台线程 | 全部主线程 |
| 保序机制 | 队列排队 + 信号量阻塞 | 单缓冲区 + 游标（数据结构保证） |
| 定时器对象数 | 每个 chunk 一个 Timer | 全程 1 条 DisplayLink |
| 与 vsync 对齐 | 否（固定 0.03s） | 是（按帧预算） |
| 每字符 UI 工作 | 1 次全量测量 + 1 次 scrollToRow | 每帧 ≤1 次测量；滚动仅在换行且用户在底部时 |
| 出字速度 | 恒定 33 字/秒 | 33 字/秒起，积压时最高 6× |
| 停止清理 | timer.invalidate + 队列置 nil + 信号量自然消亡 | `cancel()` |
| 用户上滑查看历史 | 每字符被强制拉回底部 | 保持在用户位置，回到底部自动恢复锁底 |

---

## 五、验证

### 5.1 编译

主工程在本机存在两处环境限制，需要说明：

- Podfile 对 `iphonesimulator` 排除了 arm64，本机是 Apple Silicon + Xcode 26（无 Rosetta 模拟器），**主工程无法在模拟器运行**；
- 本机未安装 watchOS 运行时，`-scheme SinaWeather` 会在调度阶段直接报 `This scheme builds an embedded Apple Watch app. watchOS 26.5 must be installed`，无法进入编译。

因此按"先构建 Pods 聚合目标，再以 `-target` 方式构建 App 目标"的方式做真机 SDK 编译验证：

```bash
xcodebuild -project Pods/Pods.xcodeproj -target Pods-SinaWeather -sdk iphoneos -configuration Debug \
  SYMROOT=/tmp/swverify/Products OBJROOT=/tmp/swverify/Intermediates CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SinaWeather.xcodeproj -target SinaWeather -sdk iphoneos -configuration Debug \
  SYMROOT=/tmp/swverify/Products OBJROOT=/tmp/swverify/Intermediates CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

结果：861 个编译任务全部通过，`SWAiChatTypewriter.o` / `SWAiChatViewController.o` 均产出，App 可执行文件链接成功（`Ld … SinaWeather.app/SinaWeather` 通过，产物 138MB）。唯一失败步骤是最后的 `Embed Watch Content` 拷贝（验证时临时摘掉了 WatchKitApp 依赖，验证后已还原 pbxproj，`shasum` 与备份一致）——与本次改动无关。

### 5.2 UI 交互验证

主工程无法在模拟器运行，因此把 `SWAiChatTypewriter.swift` **原文件**放进一个临时最小工程，配上模拟 SSE 的 chunk 发生器（随机 2-18 字一片、随机 10-450ms 间隔，文本含中英文与 emoji）和复刻 `updateLastCell` 策略的 UITableView 页面，在 iPhone 17 Pro 模拟器上跑：

| 场景 | 结果 |
|---|---|
| 常速流 188 字 / 752 字 | ✅ 输出与推送文本**完全一致**，无乱序、无丢字；emoji（🥵 ⛈️ 🚴‍♀️）未被从中间切断 |
| 快流（10-50ms 一片）752 字 | ✅ 内容一致，UI 刷新 **341 次 / 336 次**（对比常速 752 次），自适应合并省掉约 55% 的刷新 |
| 流式中上滑到顶部 | ✅ 期间新增 93 字，列表 offset 保持在 0 未被拉回 |
| 上滑后再滑回底部 | ✅ 自动锁底恢复 |
| 流式中 `cancel()` | ✅ 立即停在 22 字，1.5s 内无残留追加，缓冲已清空 |
| 打字进行中释放引擎 | ✅ 1s 后 weak 引用为 nil，CADisplayLink 无强引用泄漏 |

验证完成后临时工程已删除。

### 5.3 待真机人工回归（demo 覆盖不到的集成部分）

- loading 三点动画 → 首个字符出现时的切换是否自然；
- 换行时行高刷新无跳动、气泡宽度稳定；
- `workflow_finished` 后功能区（赞/踩/复制）与相关问题正常出现；
- 点"停止生成"后文案、发送按钮状态正确；
- 网络中断（onError）时兜底文案正确；
- 退出页面后历史消息落库正常。

---

## 六、可继续优化的方向

1. `content.boundingRect` 仍是全量测量，长回答下随字数线性增长。若后续出现长文本卡顿，可改用常驻 `NSTextStorage + NSLayoutManager` 做增量排版（注意与 UILabel 的排版结果对齐，需回归行高）。
2. `forceStopTask` 仍是非原子 Bool，理论上存在数据竞争；`messageQueue` 修好后影响已很小，彻底解决需要用锁或统一到主线程访问。
3. 出字速度参数（33 字/秒、积压阈值 40、上限 6×）目前是常量，后续可下发到 `SWAiChatConfig` 做线上调参。

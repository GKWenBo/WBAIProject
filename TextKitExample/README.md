# TextKitExample

TextKit 在真实 iOS 项目里的 10 个典型用法，共 11 个案例（增量更新分 TextKit 1 / TextKit 2 两版对照），每个案例一页，可直接运行。

设计原则是**最小实现 + 可复用**：每个案例把能复用的那段逻辑抽成独立类型放在 `Core/`，页面只负责把它用起来。想用到自己项目里，直接拷 `Core/` 下对应的文件即可，它们不依赖本工程的任何控制器。

## 案例一览

| # | 案例 | 解决什么问题 | 可复用组件 | 选型 |
|---|---|---|---|---|
| 1 | 文本高度预计算 | 列表（IM / Feed / AI 对话）滑动不掉帧，高度后台算好并缓存 | `TextHeightCalculator` | TextKit 2 |
| 2 | UILabel 字符级点击 | 链接、@、话题、"展开全文"的精确命中 | `AttributedLabel` | TextKit 1 |
| 3 | 自定义背景装饰 | 代码块整行底色、引用竖线、行内圆角高亮 | `DecoratingLayoutManager`、`TextDecoration` | TextKit 1 |
| 4 | 文字环绕 | 杂志式图文混排，文字绕开任意形状 | 无（直接用 `textContainer.exclusionPaths`） | TextKit 1 |
| 5 | 分页 / 多栏 | 阅读器翻页、多栏排版 | `PaginatedTextRenderer` + 自绘页视图 | TextKit 1 |
| 6 | 语法高亮编辑器 | 代码 / Markdown 编辑器的实时增量高亮 | `HighlightTextStorage` | TextKit 1 |
| 7 | 截断与「…展开」 | 精确判断第 N 行截在哪，再拼展开按钮 | `TruncationProbe` | TextKit 1 |
| 8 | 行信息与选区 | 行号栏、选区高亮、查词浮层 | `LineMetricsProbe` | TextKit 1 |
| 9 | 增量更新文本 | AI 对话 / 日志的流式输出，只追加、不重设 | `TextKit1IncrementalRenderer`、`StreamingTextSource` | TextKit 1 |
| 10 | 增量更新文本 | 同上，与案例 9 对照 | `TextKit2IncrementalRenderer`、`StreamingTextSource` | TextKit 2 |
| 11 | Markdown 流式渲染 | AI 回答边生成边渲染 Markdown，半截语法也不丢属性 | `MarkdownStreamSession`、`MarkdownBlockSplitter`、`MarkdownRenderer` | TextKit 2 |

## 为什么大多数案例用 TextKit 1

iOS 15 之后 `UITextView` 默认走 TextKit 2，但两套会长期共存，因为有些能力只有 TextKit 1 有：

- **多容器**：`NSTextLayoutManager` 只支持一个 `NSTextContainer`，分页和多栏（案例 5）只能用 TextKit 1。
- **截断查询**：`truncatedGlyphRange(inLineFragmentForGlyphAt:)` 在 TextKit 2 没有等价物（案例 7）。
- **自定义 NSTextStorage**：TextKit 2 的内容层是 `NSTextContentStorage`，`NSTextStorage` 子类的 `processEditing()` 不会被调用（案例 6）。
- **坐标换算和背景绘制**：TextKit 1 一个方法搞定的事（案例 2、3、8），TextKit 2 要绕 `NSTextLayoutFragment`。
- **文字环绕**：`exclusionPaths` 两套 API 上都有，但 iOS 27 实测 TextKit 2 的 `UITextView` 不响应它
  （显式调 `NSTextLayoutManager.invalidateLayout(for:)` 也没用），降回 TextKit 1 才正常（案例 4）。

反过来，测高（案例 1）用 TextKit 2，因为 `UITextView` 本身就是 TextKit 2 驱动的，**用同一个引擎量，一致性是结构性的**。

增量更新（案例 9 / 10）两套都能做，增量的粒度不同，所以各给一版对照，见下一节。
Markdown 流式渲染（案例 11）建立在同一个渲染器协议上，演示用的是 TextKit 2。

需要强制使用 TextKit 1 时有两种写法：

```swift
// 用系统默认外观，只是把排版引擎换回 TextKit 1
let textView = UITextView(usingTextLayoutManager: false)

// 需要自定义 layoutManager / textStorage 时，手工组装三件套
let layoutManager = DecoratingLayoutManager()
storage.addLayoutManager(layoutManager)
let container = NSTextContainer(size: ...)
layoutManager.addTextContainer(container)
let textView = UITextView(frame: .zero, textContainer: container)
```

## 增量更新文本（案例 9 / 10）

流式输出最直觉的写法是每收到一块就 `textView.text = 到目前为止的全文`，这会让排版引擎每次从头排一遍，
总代价 O(n²)。正确做法是**只往 text storage 末尾追加**，引擎只重排受影响的尾部。

两个案例由 `Timer`（每 50ms 一块）驱动同一段文本，页面上可以在「增量追加」和「全量替换」之间切换，
实时显示每块的重排量和累计重排量。两套渲染器实现同一个协议 `IncrementalTextRenderer`：

| | TextKit 1（案例 9） | TextKit 2（案例 10） |
|---|---|---|
| 追加写法 | `beginEditing()` → `replaceCharacters(in: 末尾, with:)` → `endEditing()` | `performEditingTransaction { textStorage.append(...) }` |
| 增量粒度 | 行：只重排新字符所在的行 | 段落：最后一段整段重新生成 `NSTextLayoutFragment` |
| 怎么统计 | 重写 `NSLayoutManager.processEditing(for:edited:range:changeInLength:invalidatedRange:)`，记下失效范围 | 实现 `NSTextLayoutManagerDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)`，数新建了几个 fragment |

同一段 395 字符、4 段正文的文本（TextKit 2 里连同段间空行共 7 个段落元素），模拟器（iPhone 18 Pro / iOS 27）上的实测：

| | 每块重排量 | 整篇吐完的累计重排量 |
|---|---|---|
| TextKit 1 · 增量追加 | 新增的几个字符，1 行 | ≈ 1 倍文本长度 |
| TextKit 2 · 增量追加 | 当前最后一段的全部字符，1 段 | ≈ 16 倍文本长度 |
| 全量替换（两套都一样） | 全文，所有行 / 段 | ≈ 60 倍文本长度，随长度平方增长 |

TextKit 2 的累计量高于 TextKit 1，是因为它的增量粒度是段落 —— 一段越长，每块重排得越多。
所以在 TextKit 2 上做流式输出，段落不宜过长；如果是一大段不换行的输出，TextKit 1 的行级增量更省。
但两者都和全量替换差了一个数量级以上，**只追加、不重设**才是关键。

两个实践细节：

- **统计用的 `ensureLayout` 只为演示。** 渲染器在每次更新后立即排完整篇，好拿到确定的数字；
  真实项目里交给 `UITextView` 按视口按需排版即可。
- **滚到底部要等排版完。** 先 `layoutIfNeeded()` 让 text view 同步内容尺寸，再改 `contentOffset`，
  否则拿到的还是上一块的高度。

另一个实测踩坑：起初用 `NSLayoutManager.firstUnlaidCharacterIndex()` 判断 TextKit 1 的失效起点，
iOS 27 上 `endEditing()` 返回时它已经等于全文长度，拿不到中间状态，所以改用 `processEditing` 钩子。

## Markdown 流式渲染（案例 11）

案例 9 / 10 追加的是纯文本，新字符不会改变旧字符的样子。Markdown 不行：`**加粗` 要等闭合才生效，
围栏代码块一打开后面全是代码，段落写着写着可能变成列表——**新到的字符会改写同一块里旧文本的渲染结果**。
所以不能只 `append` 新字符，也不该每块都全文重渲染。做法是：

1. **切块**：`MarkdownBlockSplitter` 以空行为界把原文分成「已闭合的块」和「开放尾块」。
   围栏代码块里的空行不算边界（带一个围栏状态机）；只有以换行结尾的完整行参与判断，最后半行永远属于尾块。
2. **冻结**：已闭合的块渲染一次就固定下来，之后不再解析、不再重排。
3. **只换尾块**：每来一块新文本，把尾块的**完整原文**从块起点重新渲染，再用
   `replaceTail(from:with:)` 替换 storage 里从尾块起点到文末的内容。尾块整体重建，半截的 `**`、
   刚打开的围栏也不会出现属性残缺或沿用上一个字符的属性。

调度由 `MarkdownStreamSession` 负责。有一个容易错的地方：**原文和渲染结果不等长**
（`#`、围栏行、`**` 渲染后都消失了），不能拿原文偏移当 storage 偏移。所以要分别记两个冻结边界——
原文里已冻结的长度（用来切出尾块原文）、storage 里已冻结的长度（告诉 `replaceTail` 从哪里开始替换），
冻结某段原文时同步推进两者，而且边界只往后走。

`MarkdownRenderer` 是一个够演示用的**纯函数**渲染器（标题、一层列表、围栏代码块、粗体、行内代码）：
同样的原文永远渲染出同样的结果，这是「冻结 + 重渲染尾块」拼起来与一次性渲染全文逐字符、逐属性一致的前提，
单元测试守着这一条。

同样用 `Timer` 驱动，页面可以在「只替换尾块」和「全量重渲染」之间切换。示例文本原文 340 字符、
渲染后 305 字符，切成 104 块，TextKit 2 渲染器上的结果：

| | 单块最多重排 | 整篇吐完的累计重排量 |
|---|---|---|
| 只替换尾块 | 105 字符 · 5 段（还没闭合的那个代码块整块重建） | ≈ 11 倍渲染结果长度 |
| 全量重渲染 | 305 字符 · 15 段（每块都重建全部段落） | ≈ 51 倍，随长度平方增长 |

尾块越大，单块的代价越高——代码块在闭合之前整块都是尾块，所以超长的代码块是这套方案的最坏情况。

已知局限（写在 `MarkdownBlockSplitter` 的注释里）：Setext 标题（`标题\n===`）、表格分隔行、列表延续行
这类**回溯型语法**会让「已闭合」判断过早，真实项目里可以把最后两个块都当作开放块来兜底；
另外只识别 `\n` 换行，`\r\n` 需要调用方先归一化。

## 目录结构

```
TextKitExample/
├── App/        入口、案例目录（CaseCatalog 是唯一的案例注册处）
├── Common/     TextStyle（样式与容器配置约定）、SampleText、案例页基类
├── Core/       ← 可复用层，各案例的核心逻辑，不依赖任何 ViewController
├── Cases/      演示层，一个案例一个 ViewController（案例 9 / 10 / 11 共用 StreamingTextViewController）
└── Resources/  Assets 与启动图
```

## 几条贯穿全工程的经验

**一、测量栈和视图栈的参数必须一致。** `NSTextContainer.lineFragmentPadding` 默认是 5，
`UITextView.textContainerInset` 默认上下 8，只改一边就会出现"算出来的高度和实际排版差一点"，
表现为列表行底部多一截空白或最后一行被切掉。本工程把这两项收口到 `TextStyle.configure(_:...)`，
所有测量和展示都走它。

**二、别把自己管理的 `NSTextContainer` 交给 `UITextView`。** `UITextView(frame:textContainer:)`
会按自己的 bounds 和 `textContainerInset` 回写容器尺寸并触发重排 —— 分页在视图挂上去之后悄悄变了，
表现为相邻两页内容重叠。容器的几何由谁管就由谁管到底，页面自绘只要两行
（`drawBackground` + `drawGlyphs`），见案例 5 的 `PageView`。

**三、`NSTextStorage` 持有 layout manager，反向只是弱引用。** 临时搭一套栈做离屏测量时，
如果 storage 是个局部变量，它可能在测量完成前就被释放，layout manager 就没有文本可排，
结果静默变成"0 行、没有截断"。`TruncationProbe` 和 `LineMetricsProbe` 里用
`withExtendedLifetime(storage)` 守住这一点。

## 运行与测试

```bash
xcodebuild build -project TextKitExample.xcodeproj -scheme TextKitExample \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'
```

```bash
xcodebuild test -project TextKitExample.xcodeproj -scheme TextKitExample \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'
```

本机没有 iOS 27 runtime 时替换成已安装的模拟器目标即可。

单元测试（Swift Testing）只覆盖 `Core/` 里的纯逻辑：测高结果与 `UITextView` 实际排版逐一相等、
高度缓存确实命中、点击坐标换算、截断探测、分页范围连续且覆盖全文、流式文本按字素簇切分、
两套增量渲染器追加后全文正确且只重排尾部（全量替换则重排全部）、Markdown 切块边界（含围栏内空行、
UTF-16 偏移）、逐块增量渲染与一次性渲染全文逐字符逐属性一致。UI 交互靠跑模拟器验证。

## 未覆盖的场景

真机、iPad 多栏布局、RTL 文本、Dynamic Type 变化后的重排。

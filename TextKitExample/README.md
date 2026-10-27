# TextKitExample

TextKit 在真实 iOS 项目里的 8 个典型用法，每个案例一页，可直接运行。

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

## 为什么大多数案例用 TextKit 1

iOS 15 之后 `UITextView` 默认走 TextKit 2，但两套会长期共存，因为有些能力只有 TextKit 1 有：

- **多容器**：`NSTextLayoutManager` 只支持一个 `NSTextContainer`，分页和多栏（案例 5）只能用 TextKit 1。
- **截断查询**：`truncatedGlyphRange(inLineFragmentForGlyphAt:)` 在 TextKit 2 没有等价物（案例 7）。
- **自定义 NSTextStorage**：TextKit 2 的内容层是 `NSTextContentStorage`，`NSTextStorage` 子类的 `processEditing()` 不会被调用（案例 6）。
- **坐标换算和背景绘制**：TextKit 1 一个方法搞定的事（案例 2、3、8），TextKit 2 要绕 `NSTextLayoutFragment`。
- **文字环绕**：`exclusionPaths` 两套 API 上都有，但 iOS 27 实测 TextKit 2 的 `UITextView` 不响应它
  （显式调 `NSTextLayoutManager.invalidateLayout(for:)` 也没用），降回 TextKit 1 才正常（案例 4）。

反过来，测高（案例 1）用 TextKit 2，因为 `UITextView` 本身就是 TextKit 2 驱动的，**用同一个引擎量，一致性是结构性的**。

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

## 目录结构

```
TextKitExample/
├── App/        入口、案例目录（CaseCatalog 是唯一的案例注册处）
├── Common/     TextStyle（样式与容器配置约定）、SampleText、案例页基类
├── Core/       ← 可复用层，8 个案例的核心逻辑，不依赖任何 ViewController
├── Cases/      演示层，一个案例一个 ViewController
└── Resources/  Assets 与启动图
```

## 两条贯穿全工程的经验

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
高度缓存确实命中、点击坐标换算、截断探测、分页范围连续且覆盖全文。UI 交互靠跑模拟器验证。

## 未覆盖的场景

真机、iPad 多栏布局、RTL 文本、Dynamic Type 变化后的重排。

//
//  MessageListView.swift
//  WBChatApp
//

import SwiftUI

/// 消息列表：List 复用容器 + 流式期间「提问置顶」跟随（对齐 ChatGPT / Claude / DeepSeek）
///
/// 容器选型：
/// - `List` 底层是 UICollectionView，离屏行进入系统复用池回收重建，内存不随浏览深度增长；
///   此前的 ScrollView + LazyVStack 只有「按需懒创建」没有「离屏回收」，长会话翻历史内存只增不减。
/// - `ScrollViewReader`、`onScrollGeometryChange` / `onScrollPhaseChange`、`scrollDismissesKeyboard`
///   等滚动控制在 List 上同样可用，跟随逻辑无需改变。
/// - 复用带来的重建成本由 `MessageBubbleView` 的 Markdown 解析缓存对冲（按消息 id + 版本缓存解析结果）。
///
/// 回合展示策略：
/// - 每次回合（发送 / 重新生成）开始时，在内容底部预留一屏空间（`bottomReserve`），
///   并把本回合的用户提问滚到视口顶部——无论上一条回答多长，都从提问处重新开始展示，
///   答案在其下方流式生成。这样解决了「旧长回答折叠后底部大片留白、偏移量没处理」的问题。
/// - 答案未超出一屏时不自动跟随（`distanceFromBottom > 0` 门控），提问保持置顶；
///   答案超出一屏后才跟随底部，始终展示最新 token。
///
/// 跟随/交互策略：
/// - `isFollowing` 是流式期间执行程序滚动的开关；用户滚动期间（拖动 + 惯性）一律不程序滚动。
/// - 用户任何真实位移的拖动都立即解除跟随——包括置顶等待阶段（此时距底距离为负，
///   不能用「距离超过阈值」判定，否则拖动无法解除、内容长过一屏后视口会被拽回）；
///   点按、长按选择文本没有位移，不影响跟随。
/// - 滚动落定时仅当停在距真实内容底部 ±`followThreshold` 内才恢复跟随；
///   置顶位置距离是大负值，不会被误判为「在底部」而重新拽走视口。
/// - 距离与交互阶段在 iOS 18+ 用 `onScrollGeometryChange` / `onScrollPhaseChange` 从滚动系统直接读取；
///   iOS 17 用 GeometryReader + PreferenceKey 兜底（配合手势识别拖动状态）。
/// - 距底距离一律扣除 `bottomReserve`，得到「距真实内容底部」的距离。
struct MessageListView: View {

    let conversation: Conversation
    @Bindable var viewModel: ChatViewModel

    /// 抽屉横向拖动中：暂时禁用本列表滚动，避免上下滑与抽屉手势冲突
    @Environment(\.isDrawerInteracting) private var isDrawerInteracting

    private static let bottomAnchorID = "bottom-anchor"
    private static let coordinateSpace = "message-scroll"
    /// 底部跟随阈值：滚动落定时距真实内容底部的绝对距离小于该值才保持/恢复自动跟随（单位 pt）
    private static let followThreshold: CGFloat = 80
    /// 顶部留白：置顶提问与导航栏之间的呼吸空间（单位 pt）
    private static let topInset: CGFloat = 12

    /// 是否自动跟随底部——流式期间执行程序滚动的唯一开关
    @State private var isFollowing = true
    /// 用户是否正在滚动（含手指拖动与松手后的惯性减速），期间禁止程序滚动
    @State private var isUserScrolling = false
    /// 视口底边距「真实内容底部」的距离（已扣除预留）：>0 表示答案超出一屏
    @State private var distanceFromBottom: CGFloat = 0
    /// 流式回合底部预留高度：让本回合提问能滚到视口顶部，答案在其下方生成
    @State private var bottomReserve: CGFloat = 0
    /// 本回合流式期间是否真正触发过底部跟随（即答案曾超出一屏）。
    /// 用于回合结束、消息落库（尾部多出操作栏）后决定是否补滚一次露出操作栏
    @State private var didFollowThisTurn = false
    /// （iOS 17 兜底）拖动代次：任何新的拖动都会作废之前的延迟落定任务
    @State private var legacyDragToken = 0

    var body: some View {
        // 整个 body 只做一次排序：ForEach 数据与「最后一条 assistant」的判断共用这份结果。
        // 旧写法在每个可见行的闭包里访问计算属性触发各自的全量排序，行数 × O(n log n)
        let messages = conversation.sortedMessages
        let lastAssistantID = messages.last { $0.role == .assistant }?.id

        ScrollViewReader { proxy in
            GeometryReader { outerGeo in
                List {
                    ForEach(messages) { message in
                        // 重新生成中的消息：原地替换为流式气泡，旧内容立即让位给新结果
                        Group {
                            if message.id == viewModel.regeneratingMessageID {
                                StreamingBubbleView(viewModel: viewModel)
                            } else {
                                MessageBubbleView(
                                    message: message,
                                    isLastAssistantMessage: message.id == lastAssistantID,
                                    viewModel: viewModel
                                )
                            }
                        }
                        .id(message.id)
                        .chatRowStyle()
                    }

                    // 仅新消息生成时在底部追加流式气泡；重新生成已在原位渲染
                    if viewModel.isStreaming && viewModel.regeneratingMessageID == nil {
                        StreamingBubbleView(viewModel: viewModel)
                            .chatRowStyle()
                    }

                    // 程序滚动的目标锚点行：标记「真实内容底部」，其下是预留空间。
                    // （iOS 17 兜底）在锚点行上自测与视口底边的距离——锚点行被 List
                    // 回收离屏时偏好值回落到默认 infinity（语义「远离底部」），
                    // 恢复跟随的判定（|距离| ≤ 阈值）不会被停更的读数误触发
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                        .background(
                            GeometryReader { anchorGeo in
                                Color.clear.preference(
                                    key: BottomDistanceKey.self,
                                    value: anchorGeo.frame(in: .named(Self.coordinateSpace)).maxY
                                        - outerGeo.size.height
                                )
                            }
                        )
                        .chatRowStyle(insets: EdgeInsets())

                    // 回合预留空间行：让提问能被顶到视口顶部，答案向下填充
                    if bottomReserve > 0 {
                        Color.clear
                            .frame(height: bottomReserve)
                            .chatRowStyle(insets: EdgeInsets())
                    }
                }
                .listStyle(.plain)
                // 锚点行只有 1pt：解除 List 默认行高下限（约 44pt）的约束
                .environment(\.defaultMinListRowHeight, 1)
                .scrollContentBackground(.hidden)
                .coordinateSpace(name: Self.coordinateSpace)
                // 顶部留白：置顶提问被滚到视口顶端时，与导航栏之间留出呼吸空间，
                // 避免贴边显示不全（尤其提问上方还有历史消息、内容顶 padding 已滚出屏幕时）
                .contentMargins(.top, Self.topInset, for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
                .scrollDisabled(isDrawerInteracting)
                // iOS 18+：从滚动系统读取权威的距底距离与交互阶段（距离已扣除预留）
                .modifier(
                    ScrollFollowTracking(
                        isFollowing: $isFollowing,
                        isUserScrolling: $isUserScrolling,
                        distanceFromBottom: $distanceFromBottom,
                        reserve: bottomReserve,
                        threshold: Self.followThreshold
                    )
                )
                // iOS 17 兜底：手势识别拖动状态（18+ 上处理器直接返回，不与新 API 抢状态）
                .simultaneousGesture(legacyDragGesture)
                .onPreferenceChange(BottomDistanceKey.self) { distance in
                    if #unavailable(iOS 18.0) {
                        distanceFromBottom = distance
                    }
                }
                // 流式跟随触发器：对 streamingContent / streamingReasoning 的观察被隔离在
                // 这个零尺寸视图里。若直接在本视图 onChange 这两个属性，body 会依赖它们，
                // 导致 50ms 节流刷新时整个列表重排序、重 diff；隔离后每次刷新只重算触发器
                .background(
                    StreamingFollowTrigger(viewModel: viewModel) {
                        followStreaming(proxy)
                    }
                )
                .onChange(of: viewModel.isStreaming) { _, streaming in
                    if streaming {
                        beginTurn(proxy: proxy, viewport: outerGeo.size.height)
                    } else {
                        // 回合结束：回收预留空间
                        bottomReserve = 0
                        // 落库后消息尾部多出操作栏（比流式气泡高）。若本回合答案曾超出一屏
                        // 并仍处跟随态，补一次滚动把操作栏带入视口；短答案（从未跟随、仍置顶）不动。
                        if didFollowThisTurn && isFollowing && !isUserScrolling {
                            withAnimation {
                                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: conversation.id) {
                    // 切换会话：重置状态并定位到底部
                    isFollowing = true
                    isUserScrolling = false
                    bottomReserve = 0
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Turn / Follow Logic

    /// 回合开始：预留底部空间，并把本回合用户提问滚到视口顶部
    private func beginTurn(proxy: ScrollViewProxy, viewport: CGFloat) {
        bottomReserve = viewport
        didFollowThisTurn = false
        // 保持跟随开启：短答案由 followStreaming 的「distanceFromBottom > 0」门控自动维持置顶，
        // 长答案超出一屏后自动跟随底部。不依赖 .idle 相位回调恢复跟随——置顶滚动无位移时
        // 相位可能不触发，会使 isFollowing 卡在 false 导致长答案不跟随。
        isFollowing = true
        guard let anchor = lastUserMessageID else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// 流式 chunk 到达时跟随底部：仅在「跟随开启、用户未在滚动、且答案已超出一屏」时执行。
    /// 未超出一屏时不滚动，保持提问置顶（ChatGPT/Claude/DeepSeek 一致）。
    private func followStreaming(_ proxy: ScrollViewProxy) {
        guard isFollowing, !isUserScrolling, distanceFromBottom > 0 else { return }
        didFollowThisTurn = true
        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
    }

    /// iOS 17 兜底：用手势近似「用户正在滚动」，松手后延迟落定再按距离决定是否恢复跟随。
    /// 手势有真实位移才会回调（minimumDistance: 1），因此拖动一律立即解除跟随；
    /// 恢复同样要求落定在距真实底部 ±阈值内，置顶阶段（距离为大负值）不会误恢复
    private var legacyDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { _ in
                if #available(iOS 18.0, *) { return }
                // 每次移动都递增代次，确保作废任何待执行的落定任务
                legacyDragToken += 1
                isUserScrolling = true
                isFollowing = false
            }
            .onEnded { _ in
                if #available(iOS 18.0, *) { return }
                legacyDragToken += 1
                let token = legacyDragToken
                Task {
                    // 等惯性大致结束后再落定（旧系统拿不到滚动阶段，只能估时）
                    try? await Task.sleep(for: .milliseconds(400))
                    guard token == legacyDragToken else { return }
                    isUserScrolling = false
                    isFollowing = abs(distanceFromBottom) <= Self.followThreshold
                }
            }
    }

    /// 本回合的用户提问：置顶锚点。重新生成时即被重生答案之前那条 user 消息。
    /// 每回合只调用一次，此处的排序开销可忽略；行级判断用的是 body 内共享的那份排序结果
    private var lastUserMessageID: UUID? {
        conversation.sortedMessages.last { $0.role == .user }?.id
    }
}

// MARK: - 流式跟随触发器

/// 零尺寸视图：唯一职责是观察流式正文/思考的变化并回调滚动跟随。
/// 把对高频变化属性的读取收拢到这里，`MessageListView` 的 body 便不依赖它们——
/// 流式期间每次节流刷新只失效本视图与 `StreamingBubbleView`，列表整体不重排
private struct StreamingFollowTrigger: View {

    let viewModel: ChatViewModel
    let onTick: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: viewModel.streamingContent) { onTick() }
            .onChange(of: viewModel.streamingReasoning) { onTick() }
    }
}

// MARK: - iOS 18+ 滚动跟踪

/// 用 `onScrollGeometryChange` / `onScrollPhaseChange` 驱动跟随状态：
/// 距离与交互阶段均来自滚动系统本身，滚动全程持续回调，不存在读数冻结问题。
/// 距离扣除 `reserve`（回合预留），得到「距真实内容底部」的距离。
///
/// 解除/恢复跟随的判定：
/// - 以触摸起点的偏移位移（超过 `dragSlop`）判定「真实拖动」，一旦发生立即解除跟随。
///   不能用「距离超过阈值」判定：置顶等待阶段距离为负，永远不越过阈值，拖动将无法解除跟随。
/// - 用户拖动落定（.idle）时，仅当停在距真实底部 ±threshold 内才恢复跟随；
///   点按（无位移）与程序滚动（.animating 或未经用户相位）不改变跟随状态，
///   避免置顶阶段的点按/动画落定把 `isFollowing` 误翻转。
private struct ScrollFollowTracking: ViewModifier {

    @Binding var isFollowing: Bool
    @Binding var isUserScrolling: Bool
    @Binding var distanceFromBottom: CGFloat
    let reserve: CGFloat
    let threshold: CGFloat

    /// 判定「真实拖动」的位移下限：小于该值视为点按/手指抖动（单位 pt）
    private static let dragSlop: CGFloat = 8

    /// 本次触摸交互的起始偏移；nil 表示当前不在用户触摸交互中
    @State private var dragStartOffset: CGFloat?
    /// 本次触摸交互中是否发生过真实位移
    @State private var didDragThisInteraction = false

    /// 距离 + 偏移一起从滚动几何读出：距离驱动跟随门控，偏移用于判定拖动位移
    private struct Metrics: Equatable {
        var distance: CGFloat
        var offset: CGFloat
    }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: Metrics.self) { geometry in
                    Metrics(
                        distance: geometry.contentSize.height - reserve
                            - geometry.contentOffset.y - geometry.containerSize.height,
                        offset: geometry.contentOffset.y
                    )
                } action: { _, metrics in
                    distanceFromBottom = metrics.distance
                    // 用位移而非距离判定拖动：流式内容增长也会触发几何回调，
                    // 但只会改变 contentSize（距离），不会改变偏移，不会误判
                    if let start = dragStartOffset, abs(metrics.offset - start) > Self.dragSlop {
                        didDragThisInteraction = true
                        isFollowing = false
                    }
                }
                .onScrollPhaseChange { _, newPhase, context in
                    switch newPhase {
                    case .tracking, .interacting:
                        // 触摸开始：记录起始偏移；tracking → interacting 的相位推进不重置起点
                        if dragStartOffset == nil {
                            dragStartOffset = context.geometry.contentOffset.y
                            didDragThisInteraction = false
                        }
                        isUserScrolling = true
                    case .decelerating:
                        // 惯性减速仍属用户滚动
                        isUserScrolling = true
                    case .idle:
                        let didDrag = didDragThisInteraction
                        let wasUserScroll = isUserScrolling
                        isUserScrolling = false
                        dragStartOffset = nil
                        didDragThisInteraction = false
                        // 仅用户真实拖动后的落定才重新评估跟随；
                        // 点按与程序滚动落定不改变跟随状态
                        if wasUserScroll && didDrag {
                            isFollowing = abs(distanceFromBottom) <= threshold
                        }
                    case .animating:
                        // 程序触发的动画滚动，不影响用户交互状态
                        break
                    @unknown default:
                        break
                    }
                }
        } else {
            content
        }
    }
}

/// （iOS 17 兜底）底部锚点距视口底边的距离：≈0 表示已滚到底，越大表示越往上滚。
/// 默认值 infinity 表示锚点行未被布局（被 List 回收离屏），语义为「远离底部」——
/// 若用 0 作默认值，行被回收瞬间会被误判为「已在底部」而错误恢复跟随
private struct BottomDistanceKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - List 行样式

private extension View {
    /// 消息列表行的统一样式：隐藏分隔线、透明行背景。
    /// 默认行内边距对齐旧版气泡布局：上下 inset 之和即行间距 20，左右 16
    func chatRowStyle(
        insets: EdgeInsets = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    ) -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowInsets(insets)
            .listRowBackground(Color.clear)
    }
}

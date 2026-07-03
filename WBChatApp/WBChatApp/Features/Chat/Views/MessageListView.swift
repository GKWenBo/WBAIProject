//
//  MessageListView.swift
//  WBChatApp
//

import SwiftUI

/// 消息列表：懒加载 + 流式期间「提问置顶」跟随（对齐 ChatGPT / Claude / DeepSeek）
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
    /// 底部跟随阈值：滚动落定时距内容底部小于该值才保持/恢复自动跟随（单位 pt）
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
    /// （iOS 17 兜底）拖动代次：任何新的拖动都会作废之前的延迟落定任务
    @State private var legacyDragToken = 0

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { outerGeo in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(conversation.sortedMessages) { message in
                            // 重新生成中的消息：原地替换为流式气泡，旧内容立即让位给新结果
                            if message.id == viewModel.regeneratingMessageID {
                                StreamingBubbleView(viewModel: viewModel)
                                    .id(message.id)
                            } else {
                                MessageBubbleView(
                                    message: message,
                                    isLastAssistantMessage: message.id == lastAssistantMessageID,
                                    viewModel: viewModel
                                )
                                .id(message.id)
                            }
                        }

                        // 仅新消息生成时在底部追加流式气泡；重新生成已在原位渲染
                        if viewModel.isStreaming && viewModel.regeneratingMessageID == nil {
                            StreamingBubbleView(viewModel: viewModel)
                        }

                        // 程序滚动的目标锚点：标记「真实内容底部」，其下是预留空间
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)

                        // 回合预留空间：让提问能被顶到视口顶部，答案向下填充
                        Color.clear
                            .frame(height: bottomReserve)
                    }
                    .padding(16)
                    // （iOS 17 兜底）用整段内容的 background 测距，扣除预留得到真实内容底部距离。
                    // 不能测 LazyVStack 内部的底部锚点——它在懒加载视口外时不渲染，读数会停更。
                    .background(
                        GeometryReader { contentGeo in
                            Color.clear.preference(
                                key: BottomDistanceKey.self,
                                value: contentGeo.frame(in: .named(Self.coordinateSpace)).maxY
                                    - bottomReserve - outerGeo.size.height
                            )
                        }
                    )
                }
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
                .onChange(of: viewModel.streamingContent) {
                    followStreaming(proxy)
                }
                .onChange(of: viewModel.streamingReasoning) {
                    followStreaming(proxy)
                }
                .onChange(of: viewModel.isStreaming) { _, streaming in
                    if streaming {
                        beginTurn(proxy: proxy, viewport: outerGeo.size.height)
                    } else {
                        // 回合结束：回收预留空间
                        bottomReserve = 0
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
        // 先不跟随，避免首个 token 把刚置顶的提问又拽走；答案超出一屏后由 followStreaming 接管
        isFollowing = false
        guard let anchor = lastUserMessageID else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// 流式 chunk 到达时跟随底部：仅在「跟随开启、用户未在滚动、且答案已超出一屏」时执行。
    /// 未超出一屏时不滚动，保持提问置顶（ChatGPT/Claude/DeepSeek 一致）。
    private func followStreaming(_ proxy: ScrollViewProxy) {
        guard isFollowing, !isUserScrolling, distanceFromBottom > 0 else { return }
        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
    }

    /// iOS 17 兜底：用手势近似「用户正在滚动」，松手后延迟落定再按距离决定是否恢复跟随
    private var legacyDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { _ in
                if #available(iOS 18.0, *) { return }
                // 每次移动都递增代次，确保作废任何待执行的落定任务
                legacyDragToken += 1
                isUserScrolling = true
                if distanceFromBottom > Self.followThreshold {
                    isFollowing = false
                }
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
                    isFollowing = distanceFromBottom <= Self.followThreshold
                }
            }
    }

    /// 本回合的用户提问：置顶锚点。重新生成时即被重生答案之前那条 user 消息
    private var lastUserMessageID: UUID? {
        conversation.sortedMessages.last { $0.role == .user }?.id
    }

    private var lastAssistantMessageID: UUID? {
        conversation.sortedMessages.last { $0.role == .assistant }?.id
    }
}

// MARK: - iOS 18+ 滚动跟踪

/// 用 `onScrollGeometryChange` / `onScrollPhaseChange` 驱动跟随状态：
/// 距离与交互阶段均来自滚动系统本身，滚动全程持续回调，不存在读数冻结问题。
/// 距离扣除 `reserve`（回合预留），得到「距真实内容底部」的距离。
private struct ScrollFollowTracking: ViewModifier {

    @Binding var isFollowing: Bool
    @Binding var isUserScrolling: Bool
    @Binding var distanceFromBottom: CGFloat
    let reserve: CGFloat
    let threshold: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height - reserve
                        - geometry.contentOffset.y - geometry.containerSize.height
                } action: { _, distance in
                    distanceFromBottom = distance
                    // 用户滚动中一旦越过阈值，立即解除跟随
                    if isUserScrolling && distance > threshold {
                        isFollowing = false
                    }
                }
                .onScrollPhaseChange { _, newPhase in
                    switch newPhase {
                    case .tracking, .interacting, .decelerating:
                        // 手指按下 / 拖动 / 惯性减速：全程视为用户滚动
                        isUserScrolling = true
                    case .idle:
                        // 滚动落定：按距底距离决定是否跟随
                        isUserScrolling = false
                        isFollowing = distanceFromBottom <= threshold
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

/// （iOS 17 兜底）底部锚点距视口底边的距离：≈0 表示已滚到底，越大表示越往上滚
private struct BottomDistanceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

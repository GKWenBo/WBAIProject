//
//  MessageListView.swift
//  WBChatApp
//

import SwiftUI

/// 消息列表：懒加载 + 流式期间自动跟随底部
///
/// 跟随策略：
/// - 自动跟随由 `isFollowing` 单一开关控制；用户滚动期间（拖动 + 惯性减速）一律不执行程序滚动。
/// - 用户滚动中距底部超过 `followThreshold` 即解除跟随；滚动落定（idle）时距底部在阈值内才恢复跟随。
///   因此上翻查看历史后松手，视口保持不动；拖回底部附近松手，自动恢复跟随。
/// - 距离与交互状态在 iOS 18+ 用 `onScrollGeometryChange` / `onScrollPhaseChange` 从滚动系统直接读取。
///   注意：不要退回 GeometryReader + PreferenceKey 测滚动偏移的方案——在新系统的 ScrollView 实现上
///   滚动过程中不保证持续上报，读数会冻结在旧值，这正是早前跟随逻辑失效的根因；
///   该方案仅在 iOS 17 上作兜底（配合手势识别拖动状态）。
struct MessageListView: View {

    let conversation: Conversation
    @Bindable var viewModel: ChatViewModel

    private static let bottomAnchorID = "bottom-anchor"
    private static let coordinateSpace = "message-scroll"
    /// 底部跟随阈值：滚动落定时距内容底部小于该值才保持/恢复自动跟随（单位 pt）
    private static let followThreshold: CGFloat = 80

    /// 是否自动跟随底部——流式期间执行程序滚动的唯一开关
    @State private var isFollowing = true
    /// 用户是否正在滚动（含手指拖动与松手后的惯性减速），期间禁止程序滚动
    @State private var isUserScrolling = false
    /// 视口底边距内容底部的距离：≈0 表示在底部，越往上翻越大
    @State private var distanceFromBottom: CGFloat = 0
    /// （iOS 17 兜底）拖动代次：任何新的拖动都会作废之前的延迟落定任务
    @State private var legacyDragToken = 0

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { outerGeo in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(conversation.sortedMessages) { message in
                            MessageBubbleView(
                                message: message,
                                isLastAssistantMessage: message.id == lastAssistantMessageID,
                                viewModel: viewModel
                            )
                            .id(message.id)
                        }

                        if viewModel.isStreaming {
                            StreamingBubbleView(viewModel: viewModel)
                        }

                        // 程序滚动的目标锚点
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)
                    }
                    .padding(16)
                    // （iOS 17 兜底）用整段内容的 background 测距。不能测 LazyVStack 内部的
                    // 底部锚点——它在懒加载视口外时不渲染，读数会停更。
                    .background(
                        GeometryReader { contentGeo in
                            Color.clear.preference(
                                key: BottomDistanceKey.self,
                                value: contentGeo.frame(in: .named(Self.coordinateSpace)).maxY
                                    - outerGeo.size.height
                            )
                        }
                    )
                }
                .coordinateSpace(name: Self.coordinateSpace)
                .scrollDismissesKeyboard(.interactively)
                // iOS 18+：从滚动系统读取权威的距底距离与交互阶段
                .modifier(
                    ScrollFollowTracking(
                        isFollowing: $isFollowing,
                        isUserScrolling: $isUserScrolling,
                        distanceFromBottom: $distanceFromBottom,
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
                .onChange(of: conversation.messages.count) {
                    // 用户发送新消息：强制恢复跟随并滚到底部；
                    // 助手消息落库（流式结束）：仅在跟随状态下滚动，不打扰正在翻看历史的用户
                    if conversation.sortedMessages.last?.role == .user {
                        isFollowing = true
                        withAnimation {
                            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                        }
                    } else if isFollowing && !isUserScrolling {
                        withAnimation {
                            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: conversation.id) {
                    // 切换会话：重置跟随状态并定位到底部
                    isFollowing = true
                    isUserScrolling = false
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Follow Logic

    /// 流式 chunk 到达时跟随底部：仅在「跟随开启且用户未在滚动」时执行
    private func followStreaming(_ proxy: ScrollViewProxy) {
        guard isFollowing, !isUserScrolling else { return }
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

    private var lastAssistantMessageID: UUID? {
        conversation.sortedMessages.last { $0.role == .assistant }?.id
    }
}

// MARK: - iOS 18+ 滚动跟踪

/// 用 `onScrollGeometryChange` / `onScrollPhaseChange` 驱动跟随状态：
/// 距离与交互阶段均来自滚动系统本身，滚动全程持续回调，不存在读数冻结问题。
private struct ScrollFollowTracking: ViewModifier {

    @Binding var isFollowing: Bool
    @Binding var isUserScrolling: Bool
    @Binding var distanceFromBottom: CGFloat
    let threshold: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
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

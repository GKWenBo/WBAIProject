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

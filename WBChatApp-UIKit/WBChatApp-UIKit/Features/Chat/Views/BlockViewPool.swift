import UIKit

/// 块视图复用池。
///
/// `UITextView` 实例创建代价不低，而一条长回复可能有十几个块、
/// cell 本身又会被 tableView 反复复用。没有这个池子，滚动时会不断新建 TextView。
final class BlockViewPool {

    /// 按分类存放的空闲视图
    private var idle: [BlockViewKind: [any BlockView]] = [:]

    /// 每类最多缓存多少个空闲实例，防止无限增长
    private let capacityPerKind: Int

    init(capacityPerKind: Int = 12) {
        self.capacityPerKind = capacityPerKind
    }

    /// 借出一个视图，池空时新建
    func dequeue(_ kind: BlockViewKind) -> any BlockView {
        if var queue = idle[kind], let view = queue.popLast() {
            idle[kind] = queue
            return view
        }
        return make(kind)
    }

    /// 归还视图：清理并移出视图层级，超过容量直接丢弃
    func recycle(_ view: any BlockView) {
        let kind = type(of: view).viewKind
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

    /// 供测试断言某类型空闲队列的长度，验证「借出去的最终都还回来了」
    func idleCountForTesting(_ kind: BlockViewKind) -> Int {
        idle[kind]?.count ?? 0
    }
}

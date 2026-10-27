//
//  PaginationViewController.swift
//  TextKitExample
//

import UIKit

/// 案例 5：横向翻页阅读器。N 个 `UITextView` 共用同一个 `NSLayoutManager`，
/// 各自挂一个容器，文字自动从上一页流到下一页。
final class PaginationViewController: CaseViewController {

    override var caseTitle: String { "分页 / 多栏" }
    override var caseBadge: String { "TextKit 1 · 案例 5" }
    override var casePoints: [String] {
        ["一个 NSLayoutManager 挂多个 NSTextContainer，排满一个自动流到下一个",
         "每个容器配一个自绘视图就是一页；交给 UITextView 会被回写容器尺寸，导致页间重叠",
         "TextKit 2 的 NSTextLayoutManager 只支持单容器，这个场景只能用 TextKit 1"]
    }

    private let scrollView = UIScrollView()
    private let pageLabel = UILabel()
    private let renderer = PaginatedTextRenderer(text: SampleText.articleAttributed())

    private var pageViews: [PageView] = []
    private var paginatedSize: CGSize = .zero

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self

        pageLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        pageLabel.textColor = .secondaryLabel
        pageLabel.textAlignment = .center
        pageLabel.numberOfLines = 2

        for subview in [scrollView, pageLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            pageLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            pageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            pageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            pageLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    override func layoutDidSettle() {
        rebuildPagesIfNeeded()
    }

    // MARK: - 分页

    /// 每页左右留白，顺便让翻页时能看出页与页的边界。
    private static let pageInset = UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)

    private func rebuildPagesIfNeeded() {
        let viewport = scrollView.bounds.size
        guard viewport.width > 0, viewport.height > 0, viewport != paginatedSize else { return }
        paginatedSize = viewport

        let pageSize = CGSize(width: viewport.width - Self.pageInset.left - Self.pageInset.right,
                              height: viewport.height - Self.pageInset.top - Self.pageInset.bottom)
        let pageCount = renderer.paginate(pageSize: pageSize)

        pageViews.forEach { $0.removeFromSuperview() }
        pageViews = renderer.containers.enumerated().map { index, container in
            // 每页一个自绘视图，共用 renderer 的那一个 layoutManager，各自只画自己的容器。
            let pageView = PageView(layoutManager: renderer.layoutManager, container: container)
            pageView.frame = CGRect(x: CGFloat(index) * viewport.width + Self.pageInset.left,
                                    y: Self.pageInset.top,
                                    width: pageSize.width,
                                    height: pageSize.height)
            scrollView.addSubview(pageView)
            return pageView
        }

        scrollView.contentSize = CGSize(width: viewport.width * CGFloat(pageCount), height: viewport.height)
        scrollView.contentOffset = .zero
        updatePageLabel()
    }

    private func updatePageLabel() {
        let pageCount = max(renderer.containers.count, 1)
        let index = min(max(0, Int(round(scrollView.contentOffset.x / max(1, scrollView.bounds.width)))),
                        pageCount - 1)
        let range = renderer.characterRange(forPage: index)
        pageLabel.text = String(format: "第 %d / %d 页 · 本页字符 %@ · 左右滑动翻页",
                                index + 1, pageCount, NSStringFromRange(range))
    }
}

// MARK: - 单页视图

/// 一页：只负责把自己那个容器里的内容画出来。
///
/// 有了排好版的 `NSLayoutManager`，"显示一页文本"就是两行绘制调用，
/// 不需要 `UITextView`，也就不会有视图反过来改动容器的问题。
private final class PageView: UIView {

    private let layoutManager: NSLayoutManager
    private let container: NSTextContainer

    init(layoutManager: NSLayoutManager, container: NSTextContainer) {
        self.layoutManager = layoutManager
        self.container = container
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现，本工程不使用 storyboard")
    }

    override func draw(_ rect: CGRect) {
        let glyphRange = layoutManager.glyphRange(for: container)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
    }
}

// MARK: - UIScrollViewDelegate

extension PaginationViewController: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updatePageLabel()
    }
}

//
//  LineMetricsViewController.swift
//  TextKitExample
//

import UIKit

/// 案例 8：自绘文本 + 行号栏 + 拖拽选区，全靠 `NSLayoutManager` 给的行信息。
final class LineMetricsViewController: CaseViewController {

    override var caseTitle: String { "行信息与选区" }
    override var caseBadge: String { "TextKit 1 · 案例 8" }
    override var casePoints: [String] {
        ["enumerateLineFragments 给出每行的 rect、字符范围和基线",
         "fragmentRect 含行距、铺满宽度；usedRect 才是文字实际占的地方",
         "在文字上横向拖动可以选区，高亮矩形来自 enumerateEnclosingRects"]
    }

    private let metricsView = LineMetricsView()
    private let infoLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        infoLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        infoLabel.textColor = .secondaryLabel
        infoLabel.numberOfLines = 2
        infoLabel.text = "在文字上拖动试试"

        metricsView.text = SampleText.articleAttributed()
        metricsView.onSelectionChange = { [weak self] range, lineIndex in
            guard let range else {
                self?.infoLabel.text = "在文字上拖动试试"
                return
            }
            self?.infoLabel.text = "选中字符 \(NSStringFromRange(range))\n起点在第 \(lineIndex + 1) 行"
        }

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true

        for subview in [infoLabel, scrollView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        metricsView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(metricsView)

        NSLayoutConstraint.activate([
            infoLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            infoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            metricsView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            metricsView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            metricsView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            metricsView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            metricsView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }
}

// MARK: - 自绘文本视图

/// 自己画文本、行框、行号和选区的视图。
///
/// 这里不用 `UITextView`，就是为了展示有了 TextKit 栈之后"自绘一个文本视图"并不复杂：
/// 排版交给 `NSLayoutManager`，自己只负责画。
private final class LineMetricsView: UIView {

    /// 左侧行号栏宽度。
    private static let gutterWidth: CGFloat = 34
    private static let padding: CGFloat = 12

    var text: NSAttributedString = NSAttributedString() {
        didSet {
            storage.setAttributedString(text)
            selectedRange = nil
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    /// 选区变化回调：字符范围与起点所在行号。
    var onSelectionChange: ((NSRange?, Int) -> Void)?

    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer()

    private var selectedRange: NSRange?
    private var dragAnchorIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        isOpaque = false

        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现，本工程不使用 storyboard")
    }

    /// 文本原点：行号栏之后。
    private var textOrigin: CGPoint {
        CGPoint(x: Self.gutterWidth + Self.padding, y: Self.padding)
    }

    private var textWidth: CGFloat {
        max(1, bounds.width - textOrigin.x - Self.padding)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        TextStyle.configure(container, width: textWidth)
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        TextStyle.configure(container, width: textWidth)
        layoutManager.ensureLayout(for: container)
        return CGSize(width: UIView.noIntrinsicMetric,
                      height: ceil(layoutManager.usedRect(for: container).height) + Self.padding * 2)
    }

    // MARK: - 绘制

    override func draw(_ rect: CGRect) {
        TextStyle.configure(container, width: textWidth)
        layoutManager.ensureLayout(for: container)

        let origin = textOrigin
        let lines = LineMetricsProbe.lines(in: layoutManager, container: container)

        drawSelection(origin: origin)
        drawLineBoxes(lines, origin: origin)

        // 文字最后画，盖在底色之上。
        let glyphRange = layoutManager.glyphRange(for: container)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)

        drawLineNumbers(lines, origin: origin)
    }

    private func drawLineBoxes(_ lines: [TextLineMetrics], origin: CGPoint) {
        for line in lines {
            // 行片段：虚线框，能看出它含行距、铺满容器宽度。
            let fragment = line.fragmentRect.offsetBy(dx: origin.x, dy: origin.y)
            let path = UIBezierPath(rect: fragment.insetBy(dx: 0.25, dy: 0.25))
            path.lineWidth = 0.5
            path.setLineDash([3, 3], count: 2, phase: 0)
            UIColor.separator.setStroke()
            path.stroke()

            // 基线：实线，标出文字真正坐在哪。
            let baseline = UIBezierPath()
            baseline.move(to: CGPoint(x: fragment.minX, y: origin.y + line.baseline))
            baseline.addLine(to: CGPoint(x: fragment.minX + line.usedRect.width, y: origin.y + line.baseline))
            baseline.lineWidth = 0.5
            UIColor.systemBlue.withAlphaComponent(0.25).setStroke()
            baseline.stroke()
        }
    }

    private func drawLineNumbers(_ lines: [TextLineMetrics], origin: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        for line in lines {
            let number = NSAttributedString(string: "\(line.index + 1)", attributes: attributes)
            let size = number.size()
            number.draw(at: CGPoint(x: Self.gutterWidth - size.width,
                                    y: origin.y + line.fragmentRect.minY))
        }
    }

    private func drawSelection(origin: CGPoint) {
        guard let selectedRange, selectedRange.length > 0 else { return }
        UIColor.systemBlue.withAlphaComponent(0.25).setFill()
        for rect in LineMetricsProbe.selectionRects(for: selectedRange,
                                                    in: layoutManager,
                                                    container: container) {
            UIBezierPath(roundedRect: rect.offsetBy(dx: origin.x, dy: origin.y), cornerRadius: 2).fill()
        }
    }

    // MARK: - 拖拽选区

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        guard let index = characterIndex(at: point) else { return }

        switch gesture.state {
        case .began:
            dragAnchorIndex = index
            updateSelection(from: index, to: index)
        case .changed:
            guard let anchor = dragAnchorIndex else { return }
            updateSelection(from: anchor, to: index)
        default:
            dragAnchorIndex = nil
        }
    }

    private func updateSelection(from anchor: Int, to index: Int) {
        let range = NSRange(location: min(anchor, index), length: abs(index - anchor))
        selectedRange = range

        let lines = LineMetricsProbe.lines(in: layoutManager, container: container)
        let lineIndex = lines.firstIndex { NSLocationInRange(range.location, $0.characterRange) } ?? 0
        onSelectionChange?(range.length > 0 ? range : nil, lineIndex)
        setNeedsDisplay()
    }

    private func characterIndex(at point: CGPoint) -> Int? {
        let origin = textOrigin
        let located = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(for: located,
                                                  in: container,
                                                  fractionOfDistanceThroughGlyph: &fraction)
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }
}

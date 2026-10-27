//
//  LabelHitTestViewController.swift
//  TextKitExample
//

import UIKit

/// 案例 2：在 `UILabel` 上做字符级点击检测。
///
/// 顶部的对齐方式切换是故意留的：换成居中或右对齐后命中依然准确，
/// 说明换算用的是排版结果而不是"从左上角按字宽估算"。
final class LabelHitTestViewController: CaseViewController {

    override var caseTitle: String { "UILabel 字符级点击" }
    override var caseBadge: String { "TextKit 1 · 案例 2" }
    override var casePoints: [String] {
        ["点下面蓝色的 @、话题、链接试试，灰字部分点了不会命中",
         "坐标 → 字符索引靠 glyphIndex(for:in:fractionOfDistanceThroughGlyph:)",
         "Label 会把文本垂直居中，换算前要减掉这段偏移；行尾空白要用 usedRect 剔除"]
    }

    private let label = AttributedLabel()
    private let resultLabel = UILabel()
    private let alignmentControl = UISegmentedControl(items: ["自然", "居中", "右对齐"])

    private var alignment: NSTextAlignment = .natural

    override func viewDidLoad() {
        super.viewDidLoad()

        label.numberOfLines = 0
        label.onTapToken = { [weak self] token, range in
            self?.show("命中 \(token.kind.rawValue)：\(token.payload)\n范围 \(NSStringFromRange(range))",
                       color: .systemGreen)
        }
        label.onTapMiss = { [weak self] index in
            if let index {
                self?.show("这个位置没有标记（字符索引 \(index)）", color: .secondaryLabel)
            } else {
                self?.show("点在文本之外", color: .secondaryLabel)
            }
        }

        resultLabel.numberOfLines = 0
        resultLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultLabel.textColor = .secondaryLabel
        resultLabel.text = "点一下上面的文本"

        alignmentControl.selectedSegmentIndex = 0
        alignmentControl.addTarget(self, action: #selector(alignmentChanged), for: .valueChanged)

        let stack = UIStackView(arrangedSubviews: [alignmentControl, label, resultLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])

        applyAlignment()
    }

    // MARK: - 交互

    @objc private func alignmentChanged() {
        alignment = [.natural, .center, .right][alignmentControl.selectedSegmentIndex]
        applyAlignment()
    }

    private func applyAlignment() {
        let attributed = NSMutableAttributedString(attributedString: SampleText.social())
        attributed.addAttribute(.paragraphStyle,
                                value: TextStyle.paragraphStyle(alignment: alignment),
                                range: NSRange(location: 0, length: attributed.length))
        label.attributedText = attributed
    }

    private func show(_ text: String, color: UIColor) {
        resultLabel.text = text
        resultLabel.textColor = color
    }
}

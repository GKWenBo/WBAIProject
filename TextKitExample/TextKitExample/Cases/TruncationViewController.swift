//
//  TruncationViewController.swift
//  TextKitExample
//

import UIKit

/// 案例 7：收起时在精确的截断位置拼"… 展开"，点击切换展开 / 收起。
final class TruncationViewController: CaseViewController {

    override var caseTitle: String { "截断与「…展开」" }
    override var caseBadge: String { "TextKit 1 · 案例 7" }
    override var casePoints: [String] {
        ["truncatedGlyphRange 告诉你最后一行截在哪个字形，换成字符索引就是该截的位置",
         "尾巴本身也占宽度，所以要从截断点往回退几个字符，拼完才不会多出一行",
         "点文末的「展开 / 收起」切换，上面会显示探测结果"]
    }

    private static let collapsedLines = 3

    private let label = AttributedLabel()
    private let infoLabel = UILabel()
    private var isExpanded = false
    private var fullText = SampleText.articleAttributed()

    override func viewDidLoad() {
        super.viewDidLoad()

        infoLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        infoLabel.textColor = .secondaryLabel
        infoLabel.numberOfLines = 0

        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.onTapToken = { [weak self] token, _ in
            guard token.kind == .expand else { return }
            self?.isExpanded.toggle()
            self?.render()
        }

        // 展开后文字会超出一屏，得能滚动才看得到末尾的「收起」。
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true

        for subview in [infoLabel, scrollView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(label)

        NSLayoutConstraint.activate([
            infoLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            infoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            label.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            label.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            label.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private var renderedWidth: CGFloat = 0

    override func layoutDidSettle() {
        guard label.bounds.width > 0, label.bounds.width != renderedWidth else { return }
        renderedWidth = label.bounds.width
        render()
    }

    private func render() {
        let width = renderedWidth
        guard width > 0 else { return }

        let probe = TruncationProbe.probe(fullText, width: width, maxLines: Self.collapsedLines)
        infoLabel.text = String(format: "限 %d 行 · 排了 %d 行 · %@",
                                Self.collapsedLines,
                                probe.lineCount,
                                probe.truncationCharacterIndex.map { "截断于字符 \($0)" } ?? "未截断")

        if isExpanded {
            label.attributedText = appending(suffix(title: "  收起"), to: fullText)
        } else {
            label.attributedText = TruncationProbe.collapsed(fullText,
                                                             suffix: suffix(title: "… 展开"),
                                                             width: width,
                                                             maxLines: Self.collapsedLines)
        }
    }

    /// 可点击的尾巴，复用案例 2 的 `.tapToken` 机制。
    private func suffix(title: String) -> NSAttributedString {
        var attributes = TextStyle.body
        attributes[.foregroundColor] = UIColor.systemBlue
        attributes[.tapToken] = TextTapToken(kind: .expand, payload: title)
        return NSAttributedString(string: title, attributes: attributes)
    }

    private func appending(_ suffix: NSAttributedString, to text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        result.append(suffix)
        return result
    }
}

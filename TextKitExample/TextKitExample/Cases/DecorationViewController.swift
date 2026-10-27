//
//  DecorationViewController.swift
//  TextKitExample
//

import UIKit

/// 案例 3：代码块底色、引用竖线、行内圆角高亮。
///
/// 上面的开关可以切到 `.backgroundColor` 对照组 —— 一眼能看出原生属性画不出整行底色、
/// 画不出竖线、也没有圆角。
final class DecorationViewController: CaseViewController {

    override var caseTitle: String { "自定义背景装饰" }
    override var caseBadge: String { "TextKit 1 · 案例 3" }
    override var casePoints: [String] {
        ["继承 NSLayoutManager 重写 drawBackground(forGlyphRange:at:)，底色天然在文字下面",
         "行矩形靠 enumerateEnclosingRects 取，跨行高亮会自动拆成多段",
         "必须手工组装 TextKit 1 栈，否则 UITextView 走 TextKit 2，这个子类不会被调用"]
    }

    private let segmented = UISegmentedControl(items: ["自定义装饰", ".backgroundColor"])
    private var textView: UITextView!
    private let storage = NSTextStorage()

    override func viewDidLoad() {
        super.viewDidLoad()

        textView = makeTextKit1TextView()
        textView.isEditable = false
        // 这个案例要留出左右留白，底色才像个代码块，所以不走 TextStyle.configure(_:)。
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear

        segmented.selectedSegmentIndex = 0
        segmented.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        let stack = UIStackView(arrangedSubviews: [segmented, textView])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        modeChanged()
    }

    /// 手工组装 TextKit 1 三件套。
    ///
    /// 关键是两点：`NSLayoutManager` 用自己的子类，以及用
    /// `UITextView(frame:textContainer:)` 这个初始化方法 —— 传入容器就意味着走 TextKit 1。
    /// 需要系统默认外观时也可以用 `UITextView(usingTextLayoutManager: false)`。
    private func makeTextKit1TextView() -> UITextView {
        let layoutManager = DecoratingLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        return UITextView(frame: .zero, textContainer: container)
    }

    @objc private func modeChanged() {
        let decorated = SampleText.decorated()
        storage.setAttributedString(segmented.selectedSegmentIndex == 0
                                    ? decorated
                                    : Self.backgroundColorVariant(of: decorated))
    }

    /// 对照组：把自定义装饰换成原生的 `.backgroundColor`。
    private static func backgroundColorVariant(of text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let fullRange = NSRange(location: 0, length: result.length)

        result.enumerateAttribute(.textDecoration, in: fullRange) { value, range, _ in
            guard let decoration = value as? TextDecoration else { return }
            result.removeAttribute(.textDecoration, range: range)
            result.addAttribute(.backgroundColor, value: decoration.color, range: range)
        }
        return result
    }
}

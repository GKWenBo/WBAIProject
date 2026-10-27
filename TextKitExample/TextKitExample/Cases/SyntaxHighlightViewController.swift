//
//  SyntaxHighlightViewController.swift
//  TextKitExample
//

import UIKit

/// 案例 6：可编辑的语法高亮编辑器，底部实时显示本次重算了哪几行。
final class SyntaxHighlightViewController: CaseViewController {

    override var caseTitle: String { "语法高亮编辑器" }
    override var caseBadge: String { "TextKit 1 · 案例 6" }
    override var casePoints: [String] {
        ["继承 NSTextStorage，在 processEditing 里只给 editedRange 所在的行重新上色",
         "子类必须实现 string / attributes / replaceCharacters / setAttributes 四个方法",
         "直接编辑下面的代码，底部会显示这次实际重算的字符范围"]
    }

    private let storage = HighlightTextStorage()
    private var textView: UITextView!
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        textView = makeTextKit1TextView()
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.delegate = self
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 10
        textView.layer.cornerCurve = .continuous

        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: SampleText.swiftSnippet)
        storage.highlightAll()

        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2
        statusLabel.text = "改几个字看看"

        let stack = UIStackView(arrangedSubviews: [textView, statusLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            textView.heightAnchor.constraint(equalToConstant: 320)
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "收起键盘",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(dismissKeyboard))
    }

    /// 自定义 `NSTextStorage` 必须配 TextKit 1 栈：TextKit 2 的内容层是
    /// `NSTextContentStorage`，不会走这个子类的 `processEditing()`。
    private func makeTextKit1TextView() -> UITextView {
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        return UITextView(frame: .zero, textContainer: container)
    }

    @objc private func dismissKeyboard() {
        textView.resignFirstResponder()
    }
}

// MARK: - UITextViewDelegate

extension SyntaxHighlightViewController: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        let range = storage.lastHighlightedRange
        let lineNumber = (storage.string as NSString)
            .substring(to: min(range.location, storage.length))
            .components(separatedBy: "\n").count
        statusLabel.text = String(format: "本次重算：第 %d 行起 · 字符范围 %@ · 共 %d 字符（全文 %d）",
                                  lineNumber,
                                  NSStringFromRange(range),
                                  range.length,
                                  storage.length)
    }
}

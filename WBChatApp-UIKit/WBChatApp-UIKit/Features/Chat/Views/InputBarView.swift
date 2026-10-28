import UIKit

/// 底部输入栏：多行自增高文本框 + 麦克风 + 发送/停止。
final class InputBarView: UIView {

    /// 发送；返回 true 表示已被接受，此时清空输入框
    var onSend: ((String) async -> Bool)?
    /// 文本变化，用于同步草稿
    var onTextChanged: ((String) -> Void)?
    /// 生成中点按钮 = 停止
    var onStop: (() -> Void)?
    var onMicTap: (() -> Void)?
    /// 输入框高度变化，聊天页据此重新贴底
    var onHeightChange: (() -> Void)?

    /// 文本框高度范围，超过上限后改为内部滚动
    private static let minHeight: CGFloat = 36
    private static let maxHeight: CGFloat = 120

    private let textView: UITextView = {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.isScrollEnabled = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "发消息…"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = Theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let micButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "mic"), for: .normal)
        button.accessibilityIdentifier = "input.mic"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.accessibilityIdentifier = "input.send"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let container: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.secondaryBackground
        view.layer.cornerRadius = 20
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var textViewHeight: NSLayoutConstraint!
    /// 生成中：按钮显示为停止
    private var isStreaming = false
    /// onSend 尚未返回，防止重复点击
    private var isSending = false
    /// 外部是否允许发送（如落库失败时禁止）
    private var canSend = true

    var text: String { textView.text ?? "" }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    private func setUp() {
        backgroundColor = Theme.background
        addSubview(container)
        container.addSubview(textView)
        container.addSubview(placeholderLabel)
        addSubview(micButton)
        addSubview(actionButton)

        textViewHeight = textView.heightAnchor.constraint(equalToConstant: Self.minHeight)

        NSLayoutConstraint.activate([
            micButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            micButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            micButton.widthAnchor.constraint(equalToConstant: 32),
            micButton.heightAnchor.constraint(equalToConstant: 32),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            actionButton.widthAnchor.constraint(equalToConstant: 32),
            actionButton.heightAnchor.constraint(equalToConstant: 32),

            container.leadingAnchor.constraint(equalTo: micButton.trailingAnchor, constant: 8),
            container.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            textView.topAnchor.constraint(equalTo: container.topAnchor),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            textViewHeight,

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 12),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
        ])

        textView.delegate = self
        textView.accessibilityIdentifier = "input.textView"
        micButton.addTarget(self, action: #selector(handleMic), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)
        updateActionButton()
    }

    func setCanSend(_ enabled: Bool) { canSend = enabled; updateActionButton() }

    func setStreaming(_ streaming: Bool) {
        isStreaming = streaming
        updateActionButton()
    }

    func setText(_ newText: String) {
        textView.text = newText
        textViewDidChange(textView)
    }

    @objc private func handleMic() {
        onMicTap?()
    }

    /// 发送/停止按钮：生成中则停止，否则发送；发送成功且期间内容未改才清空
    @objc private func handleAction() {
        if isStreaming {
            onStop?()
            return
        }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        guard !isSending, canSend else { return }
        isSending = true
        updateActionButton()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let accepted = await self.onSend?(content) ?? false
            if accepted && self.text.trimmingCharacters(in: .whitespacesAndNewlines) == content { self.setText("") }
            self.isSending = false
            self.updateActionButton()
        }
    }

    private func updateActionButton() {
        let name = isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill"
        actionButton.setImage(UIImage(systemName: name), for: .normal)
        actionButton.accessibilityIdentifier = isStreaming ? "input.stop" : "input.send"
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        actionButton.isEnabled = isStreaming || (hasText && canSend && !isSending)
    }
}

extension InputBarView: UITextViewDelegate {

    /// 同步草稿、占位符，并按内容自增高
    func textViewDidChange(_ textView: UITextView) {
        onTextChanged?(text)
        placeholderLabel.isHidden = !textView.text.isEmpty
        let fitted = textView.sizeThatFits(CGSize(width: textView.bounds.width,
                                                  height: .greatestFiniteMagnitude)).height
        let clamped = min(max(fitted, Self.minHeight), Self.maxHeight)
        if abs(textViewHeight.constant - clamped) > 0.5 {
            textViewHeight.constant = clamped
            textView.isScrollEnabled = fitted > Self.maxHeight
            onHeightChange?()
        }
        updateActionButton()
    }
}

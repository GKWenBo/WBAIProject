import UIKit

/// 代码块：顶部一条「语言 + 复制」工具条，下面是横向可滚动的等宽文本。
final class CodeBlockView: UIView, BlockView {

    static let viewKind: BlockViewKind = .code

    var onCopy: ((String) -> Void)?

    private static let headerHeight: CGFloat = 32
    private static let contentInset: CGFloat = 12

    private let container: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.codeBackground
        view.layer.cornerRadius = 10
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let languageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = Theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let copyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("复制", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    /// 代码不换行，靠横向滚动查看
    private let textView: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                             height: .greatestFiniteMagnitude)
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    private var code: String = ""

    /// 供测试断言
    var languageText: String { languageLabel.text ?? "" }

    /// 供测试断言/设置：读取当前剥掉围栏的代码，或直接写入滚动位置以模拟横向滚动
    var codeForTesting: String { code }
    var contentOffsetForTesting: CGPoint {
        get { scrollView.contentOffset }
        set { scrollView.contentOffset = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    private func setUp() {
        addSubview(container)
        container.addSubview(languageLabel)
        container.addSubview(copyButton)
        container.addSubview(scrollView)
        scrollView.addSubview(textView)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            languageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.contentInset),
            languageLabel.topAnchor.constraint(equalTo: container.topAnchor),
            languageLabel.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            copyButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.contentInset),
            copyButton.centerYAnchor.constraint(equalTo: languageLabel.centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.contentInset),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.contentInset),
            scrollView.topAnchor.constraint(equalTo: languageLabel.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.contentInset),

            textView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            textView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            textView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        copyButton.addTarget(self, action: #selector(handleCopy), for: .touchUpInside)
    }

    // MARK: - BlockView

    func configure(block: MarkdownBlock,
                   attributed: NSAttributedString,
                   renderer: AttributedRenderer) {
        textView.attributedText = attributed
        code = renderer.codeText(of: block)
        if case .codeFence(let language) = block.kind {
            languageLabel.text = language ?? "纯文本"
        } else {
            languageLabel.text = "纯文本"
        }
    }

    func heightThatFits(width: CGFloat) -> CGFloat {
        let size = textView.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                height: .greatestFiniteMagnitude))
        return ceil(size.height) + Self.headerHeight + Self.contentInset
    }

    func prepareForReuse() {
        textView.attributedText = NSAttributedString()
        languageLabel.text = nil
        code = ""
        onCopy = nil
        scrollView.contentOffset = .zero
    }

    // MARK: - 复制

    @objc private func handleCopy() {
        UIPasteboard.general.string = code
        onCopy?(code)
    }

    /// 供测试直接触发复制
    func triggerCopyForTesting() {
        handleCopy()
    }
}

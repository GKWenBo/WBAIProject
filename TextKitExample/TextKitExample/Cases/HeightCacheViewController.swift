//
//  HeightCacheViewController.swift
//  TextKitExample
//

import UIKit

/// 案例 1：列表测高走后台 TextKit 栈 + 缓存，并和 `boundingRect` 对比误差。
final class HeightCacheViewController: CaseViewController {

    override var caseTitle: String { "文本高度预计算" }
    override var caseBadge: String { "TextKit 2 · 案例 1" }
    override var casePoints: [String] {
        ["高度在后台用独立 TextKit 栈算好并缓存，主线程只负责展示",
         "和 UITextView 同一个排版引擎，结果一致；boundingRect 会差 0~3pt",
         "前提：测量栈与视图栈的 lineFragmentPadding、textContainerInset 必须一致"]
    }

    // MARK: - 布局常量

    /// 气泡内文字左右内边距，决定测量宽度。
    private static let textInset: CGFloat = 12
    /// 气泡相对列表的左右外边距。
    private static let bubbleMargin: CGFloat = 12
    /// 气泡内文字上下内边距。
    private static let verticalInset: CGFloat = 10
    /// 每行底部那条对比信息的高度。
    private static let footerHeight: CGFloat = 18

    private let calculator = TextHeightCalculator()
    private let tableView = UITableView()
    private let statusLabel = UILabel()

    private lazy var messages: [NSAttributedString] = {
        // 重复几遍：内容重复的行会命中缓存，排版次数就明显少于行数。
        (0..<3).flatMap { _ in SampleText.messages }
            .map { NSAttributedString(string: $0, attributes: TextStyle.body) }
    }()

    /// 文字的可用宽度。测量和布局都用它，两边才对得上。
    private var textWidth: CGFloat {
        tableView.bounds.width - (Self.bubbleMargin + Self.textInset) * 2
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.text = "等待布局…"

        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseID)

        for subview in [statusLabel, tableView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    override func layoutDidSettle() {
        prewarmHeightsIfNeeded()
    }

    // MARK: - 后台预热

    private var prewarmedWidth: CGFloat = 0
    /// 高度全部备好之前列表不出数据，`heightForRowAt` 就不会在错误宽度下白算一遍。
    private var isReady = false

    /// 宽度确定后把所有行的高度在后台算一遍，之后 `heightForRowAt` 全是缓存命中。
    ///
    /// 真实项目里这一步通常发生在消息到达或数据入库时，而不是等到即将显示。
    private func prewarmHeightsIfNeeded() {
        let width = textWidth
        guard width > 0, width != prewarmedWidth else { return }
        prewarmedWidth = width
        isReady = false
        calculator.invalidateCache()

        let total = messages.count
        var finished = 0
        statusLabel.text = "后台测高中…"

        for message in messages {
            calculator.height(of: message, width: width) { [weak self] _ in
                guard let self else { return }
                finished += 1
                guard finished == total else { return }
                self.isReady = true
                self.tableView.reloadData()
                self.updateStatus()
            }
        }
    }

    private func updateStatus() {
        statusLabel.text = String(format: "%d 行 · 缓存 %d 条 · 实际排版 %d 次",
                                  messages.count,
                                  calculator.cachedCount,
                                  calculator.measureCountForTesting)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension HeightCacheViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isReady ? messages.count : 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseID,
                                                 for: indexPath) as! MessageCell
        let message = messages[indexPath.row]
        let width = textWidth
        cell.configure(with: message,
                       textKitHeight: calculator.height(of: message, width: width),
                       boundingRectHeight: Self.boundingRectHeight(of: message, width: width),
                       layout: MessageCell.Layout(bubbleMargin: Self.bubbleMargin,
                                                  textInset: Self.textInset,
                                                  verticalInset: Self.verticalInset,
                                                  footerHeight: Self.footerHeight))
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // 这里是缓存命中，不触发排版 —— 滑动再快也不会卡在测高上。
        calculator.height(of: messages[indexPath.row], width: textWidth)
            + Self.verticalInset * 2 + Self.footerHeight + 10
    }

    /// 对照组：`boundingRect` 的测量结果。
    private static func boundingRectHeight(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading],
                          context: nil).height
    }
}

// MARK: - 消息气泡

private final class MessageCell: UITableViewCell {

    struct Layout {
        let bubbleMargin: CGFloat
        let textInset: CGFloat
        let verticalInset: CGFloat
        let footerHeight: CGFloat
    }

    static let reuseID = "MessageCell"

    private let bubble = UIView()
    private let textView = UITextView()
    private let footer = UILabel()

    private var layout = Layout(bubbleMargin: 12, textInset: 12, verticalInset: 10, footerHeight: 18)
    private var textHeight: CGFloat = 0

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        bubble.backgroundColor = .secondarySystemBackground
        bubble.layer.cornerRadius = 10
        bubble.layer.cornerCurve = .continuous

        // 展示侧的容器配置必须与测量侧一致，这是高度能对上的前提。
        TextStyle.configure(textView)
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = false

        footer.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        footer.textColor = .tertiaryLabel

        contentView.addSubview(bubble)
        bubble.addSubview(textView)
        contentView.addSubview(footer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现，本工程不使用 storyboard")
    }

    func configure(with text: NSAttributedString,
                   textKitHeight: CGFloat,
                   boundingRectHeight: CGFloat,
                   layout: Layout) {
        textView.attributedText = text
        textHeight = textKitHeight
        self.layout = layout
        footer.text = String(format: "TextKit %.1f   boundingRect %.1f   差 %+.1f",
                             textKitHeight,
                             boundingRectHeight,
                             boundingRectHeight - textKitHeight)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 直接按测好的高度布局，不让 textView 自己 sizeToFit —— 这正是测高器存在的意义。
        bubble.frame = CGRect(x: layout.bubbleMargin,
                              y: 4,
                              width: bounds.width - layout.bubbleMargin * 2,
                              height: textHeight + layout.verticalInset * 2)
        textView.frame = CGRect(x: layout.textInset,
                                y: layout.verticalInset,
                                width: bubble.bounds.width - layout.textInset * 2,
                                height: textHeight)
        footer.frame = CGRect(x: layout.bubbleMargin + 4,
                              y: bubble.frame.maxY + 2,
                              width: bounds.width - (layout.bubbleMargin + 4) * 2,
                              height: layout.footerHeight)
    }
}

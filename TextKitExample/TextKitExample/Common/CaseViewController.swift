//
//  CaseViewController.swift
//  TextKitExample
//

import UIKit

/// 案例页基类：顶部一张要点说明卡，下面是子类自己填的 `contentView`。
///
/// 说明卡存在的意义是让这个工程能当讲解材料用 —— 打开某页就能看到"解决什么问题、
/// 关键 API 是哪个、哪里容易踩坑"。
class CaseViewController: UIViewController {

    /// 子类往这里加自己的视图。
    let contentView = UIView()

    // 元数据用「重写属性」而不是「自定义 init」提供：子类就不必各自补一遍
    // required init?(coder:) 的样板代码。
    /// 子类重写：导航栏标题。
    var caseTitle: String { "" }
    /// 子类重写：这个案例用的是哪套 TextKit。
    var caseBadge: String { "" }
    /// 子类重写：要点，每条一行。
    var casePoints: [String] { [] }

    /// 布局尺寸可用之后的回调，会被调用多次，子类自己做幂等判断。
    ///
    /// 为什么不直接用 `viewDidLayoutSubviews`：它第一次触发时子视图的 bounds 可能还是 0，
    /// 而之后的布局不一定会再回调到控制器这一层，于是"等宽度确定再算"的逻辑就永远不执行。
    /// 这里补上 `viewDidAppear` 这条路径，两个入口都走同一个方法。
    func layoutDidSettle() {}

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutDidSettle()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        layoutDidSettle()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = caseTitle

        let header = makeHeaderCard()
        header.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        view.addSubview(contentView)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),

            contentView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            contentView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        ])
    }

    private func makeHeaderCard() -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 10
        card.layer.cornerCurve = .continuous

        let badgeLabel = UILabel()
        badgeLabel.text = caseBadge
        badgeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        badgeLabel.textColor = .systemBlue

        let pointsLabel = UILabel()
        pointsLabel.numberOfLines = 0
        pointsLabel.font = .systemFont(ofSize: 13)
        pointsLabel.textColor = .secondaryLabel
        pointsLabel.attributedText = NSAttributedString(
            string: casePoints.map { "· \($0)" }.joined(separator: "\n"),
            attributes: [.font: UIFont.systemFont(ofSize: 13),
                         .foregroundColor: UIColor.secondaryLabel,
                         .paragraphStyle: TextStyle.paragraphStyle(lineSpacing: 3)])

        let stack = UIStackView(arrangedSubviews: [badgeLabel, pointsLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        // 说明卡的高度只由文字决定。少了这几行，卡片高度和下面 contentView 的高度之间
        // 就是一道有多个解的方程，子类里出现固定高度的视图时，多余的空间可能被塞进卡片里。
        for label in [badgeLabel, pointsLabel] {
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        card.setContentHuggingPriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
        ])
        return card
    }
}

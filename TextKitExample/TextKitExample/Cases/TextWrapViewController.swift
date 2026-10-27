//
//  TextWrapViewController.swift
//  TextKitExample
//

import UIKit

/// 案例 4：文字环绕。拖动那个圆形头像，文字会实时绕开它。
///
/// 代码上这是 8 个案例里最省事的一个：不用继承任何类，往
/// `textContainer.exclusionPaths` 放一组 `UIBezierPath` 就行。
/// 唯一的坑是排版引擎的选择，见下。
final class TextWrapViewController: CaseViewController {

    override var caseTitle: String { "文字环绕" }
    override var caseBadge: String { "TextKit 1 · 案例 4" }
    override var casePoints: [String] {
        ["textContainer.exclusionPaths 接受任意 UIBezierPath，不限于矩形",
         "路径是容器坐标系：视图坐标要减掉 textContainerInset",
         "实测 iOS 27：TextKit 2 的 UITextView 不响应 exclusionPaths，要降回 TextKit 1"]
    }

    /// 实测 iOS 27：TextKit 2 的 `UITextView` 不响应 `textContainer.exclusionPaths`
    /// （显式 `invalidateLayout(for:)` 也没用），把排版引擎降回 TextKit 1 就正常。
    private let textView = UITextView(usingTextLayoutManager: false)
    private let avatar = UIView()
    private let infoLabel = UILabel()

    /// 文字与图形之间的留白。直接用图形自身的路径会让文字贴得太紧。
    private static let wrapPadding: CGFloat = 8

    override func viewDidLoad() {
        super.viewDidLoad()

        TextStyle.configure(textView)
        textView.isEditable = false
        textView.attributedText = SampleText.articleAttributed(alignment: .justified)
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

        avatar.backgroundColor = .systemBlue.withAlphaComponent(0.85)
        avatar.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
        avatar.layer.cornerRadius = 48
        avatar.isUserInteractionEnabled = true
        avatar.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan)))

        let avatarLabel = UILabel()
        avatarLabel.text = "拖我"
        avatarLabel.textColor = .white
        avatarLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        avatarLabel.sizeToFit()
        avatarLabel.center = CGPoint(x: 48, y: 48)
        avatar.addSubview(avatarLabel)

        infoLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        infoLabel.textColor = .secondaryLabel
        infoLabel.textAlignment = .center

        for subview in [textView, infoLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        textView.addSubview(avatar)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            infoLabel.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 8),
            infoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            infoLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    private var didPlaceAvatar = false

    override func layoutDidSettle() {
        guard !didPlaceAvatar, textView.bounds.width > 0 else { return }
        didPlaceAvatar = true
        avatar.center = CGPoint(x: textView.bounds.width - 70, y: 110)
        updateExclusionPath()
    }

    // MARK: - 拖动

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: textView)
        avatar.center = CGPoint(x: avatar.center.x + translation.x,
                                y: avatar.center.y + translation.y)
        gesture.setTranslation(.zero, in: textView)
        updateExclusionPath()
    }

    /// 把头像的位置换算成容器坐标，再交给 `exclusionPaths`。
    private func updateExclusionPath() {
        let inset = textView.textContainerInset
        // 容器原点在 inset 之后，而且 avatar 在 textView 的内容坐标系里，所以只减 inset。
        let frameInContainer = avatar.frame
            .insetBy(dx: -Self.wrapPadding, dy: -Self.wrapPadding)
            .offsetBy(dx: -inset.left, dy: -inset.top)

        // 圆形路径：文字会贴着圆弧绕，而不是绕一个方框 —— 这是 exclusionPaths 的价值所在。
        textView.textContainer.exclusionPaths = [UIBezierPath(ovalIn: frameInContainer)]

        infoLabel.text = String(format: "排除区域：(%.0f, %.0f) %.0f×%.0f",
                                frameInContainer.minX, frameInContainer.minY,
                                frameInContainer.width, frameInContainer.height)
    }
}

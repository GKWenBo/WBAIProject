//
//  AttributedLabel.swift
//  TextKitExample
//
//  案例 2：UILabel 上的字符级点击检测（链接 / @ / 话题 / "展开全文"）
//

import UIKit

extension NSAttributedString.Key {
    /// 自定义点击标记，value 为 `TextTapToken`。
    static let tapToken = NSAttributedString.Key("TextKitExample.tapToken")
}

/// 一处可点击文本的标记。
///
/// 做成 `NSObject` 子类而不是 struct：属性串的值会被 `NSTextStorage` 反复拷贝，
/// 用 ObjC 对象在相等性判断和归档上都更省心。
final class TextTapToken: NSObject {

    enum Kind: String {
        case link, mention, hashtag, expand
    }

    let kind: Kind
    let payload: String

    init(kind: Kind, payload: String) {
        self.kind = kind
        self.payload = payload
    }

    override var description: String { "\(kind.rawValue)(\(payload))" }
}

/// 支持字符级点击检测的 `UILabel`。
///
/// `UILabel` 只告诉你"点到了这个 Label"，不告诉你点到了第几个字。这里额外养一套
/// TextKit 1 栈，把点击坐标换算成字符索引，再查该位置的 `.tapToken` 属性判断点中了什么。
///
/// 关键 API：`NSLayoutManager.glyphIndex(for:in:fractionOfDistanceThroughGlyph:)`。
/// 选 TextKit 1 是因为这条坐标 → 字形的换算在 TextKit 1 里是一行调用，
/// TextKit 2 要先定位 `NSTextLayoutFragment` 再往下找 line fragment，绕得多。
///
/// ## 容易踩的坑
///
/// - 自建栈的参数必须和 Label 对齐：`numberOfLines`、`lineBreakMode`、容器宽度、
///   `lineFragmentPadding = 0`，少同步一项就会整体偏移。
/// - `UILabel` 会把整块文本在自身高度里**垂直居中**，换算前要减掉这段偏移。
/// - 点在行尾空白处时 `glyphIndex(for:)` 仍会返回该行最后一个字形，必须再用
///   `lineFragmentUsedRect` 做一次包含判断，否则点右边空白也会"命中"最后一个字。
/// - 对齐方式写在属性串的 `paragraphStyle` 里最稳妥；只设了 `label.textAlignment`
///   时这里会自动补一份同样的段落样式。
final class AttributedLabel: UILabel {

    /// 命中回调：点中的标记与它在文本里的范围。
    var onTapToken: ((TextTapToken, NSRange) -> Void)?

    /// 没命中任何标记时的回调，参数是点到的字符索引（点在文本之外为 `nil`）。
    ///
    /// 有这个回调，调用方就不必再往 Label 上挂第二个手势 —— 同一个视图上的两个
    /// `UITapGestureRecognizer` 默认只有一个能识别，另一个会被静默吞掉。
    var onTapMiss: ((Int?) -> Void)?

    // 这套栈只用于命中检测，不参与绘制，所以不挂到任何视图上。
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if let (token, range) = token(at: point) {
            onTapToken?(token, range)
        } else {
            onTapMiss?(characterIndex(at: point))
        }
    }

    // MARK: - 命中检测

    /// 点击坐标对应的字符索引，点在文本之外时返回 `nil`。
    func characterIndex(at point: CGPoint) -> Int? {
        guard bounds.width > 0, let attributed = effectiveAttributedText(), attributed.length > 0 else {
            return nil
        }

        syncStack(with: attributed)
        layoutManager.ensureLayout(for: textContainer)

        // UILabel 垂直居中整块文本，把点换算回排版坐标系。
        let used = layoutManager.usedRect(for: textContainer)
        var located = point
        located.y -= (bounds.height - used.height) / 2 - used.minY

        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(for: located,
                                                  in: textContainer,
                                                  fractionOfDistanceThroughGlyph: &fraction)

        // usedRect 是这一行文字真实占据的范围（已含对齐偏移），用它剔除行尾空白的误命中。
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        guard lineRect.contains(located) else { return nil }

        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }

    /// 点击坐标处的 `.tapToken` 标记及其范围。
    func token(at point: CGPoint) -> (TextTapToken, NSRange)? {
        guard let index = characterIndex(at: point), index < textStorage.length else { return nil }

        // 用 longestEffectiveRange 而不是 effectiveRange：UILabel 会给 attributedText
        // 补一轮自己的默认属性，可能把同一个标记切成几段 run，只取 effectiveRange 会拿到半截。
        var range = NSRange()
        let whole = NSRange(location: 0, length: textStorage.length)
        guard let token = textStorage.attribute(.tapToken,
                                                at: index,
                                                longestEffectiveRange: &range,
                                                in: whole) as? TextTapToken
        else { return nil }

        return (token, range)
    }

    // MARK: - 与 Label 参数同步

    /// 每次命中检测前重新同步，省掉监听一堆属性 setter 的麻烦，代价只是一次排版。
    private func syncStack(with attributed: NSAttributedString) {
        TextStyle.configure(textContainer,
                            width: bounds.width,
                            maximumNumberOfLines: numberOfLines,
                            lineBreakMode: lineBreakMode)
        textStorage.setAttributedString(attributed)
    }

    /// 取 Label 当前的属性串，并给缺少段落样式的区间补一份与 Label 属性一致的。
    ///
    /// `attributedText` 对 `text = "..."` 这种纯文本赋值同样有效，所以只看它就够了。
    private func effectiveAttributedText() -> NSAttributedString? {
        guard let attributed = attributedText else { return nil }

        let result = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: result.length)
        let fallback = TextStyle.paragraphStyle(alignment: textAlignment, lineBreakMode: lineBreakMode)

        result.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            guard value == nil else { return }
            result.addAttribute(.paragraphStyle, value: fallback, range: range)
        }
        return result
    }
}

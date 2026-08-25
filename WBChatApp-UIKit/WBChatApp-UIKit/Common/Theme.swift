import UIKit

/// 全局配色。全部走 dynamic color，自动适配深浅色。
enum Theme {

    static let background = UIColor.systemBackground
    static let secondaryBackground = UIColor.secondarySystemBackground

    /// 助手气泡：贴合 ChatGPT，浅色下几乎透明，深色下略提亮
    static let bubbleAssistant = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.06)
            : UIColor(white: 0, alpha: 0.03)
    }

    static let bubbleUser = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.12)
            : UIColor(white: 0, alpha: 0.06)
    }

    static let textPrimary = UIColor.label
    static let textSecondary = UIColor.secondaryLabel
    static let accent = UIColor.systemBlue

    static let codeBackground = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.08)
            : UIColor(white: 0, alpha: 0.045)
    }

    static let separator = UIColor.separator
}

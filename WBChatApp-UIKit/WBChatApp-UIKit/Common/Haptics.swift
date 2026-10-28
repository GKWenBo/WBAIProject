import UIKit

/// 触感反馈的统一入口
enum Haptics {
    /// 操作成功（如复制完成）
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    /// 轻触（如按钮点击、开始录音）
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

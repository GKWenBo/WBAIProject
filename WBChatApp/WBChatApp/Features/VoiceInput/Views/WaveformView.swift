//
//  WaveformView.swift
//  WBChatApp
//

import SwiftUI

/// 录音波形：根据音量电平序列用 Canvas 绘制圆角竖条
struct WaveformView: View {

    let levels: [Float]

    var body: some View {
        Canvas { context, size in
            let barCount = levels.count
            guard barCount > 0 else { return }
            let spacing: CGFloat = 3
            let barWidth = (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)

            for (index, level) in levels.enumerated() {
                let height = max(barWidth, CGFloat(level) * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + spacing),
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(.white)
                )
            }
        }
    }
}

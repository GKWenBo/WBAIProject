//
//  RecordingOverlayView.swift
//  WBChatApp
//

import SwiftUI

/// 录音浮层：实时识别文字 + 波形动画 + 操作提示
struct RecordingOverlayView: View {

    let levels: [Float]
    let transcript: String

    var body: some View {
        VStack(spacing: 16) {
            if !transcript.isEmpty {
                Text(transcript)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }

            WaveformView(levels: levels)
                .frame(width: 200, height: 48)

            Text("松开结束，识别文字自动填入输入框")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(28)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 36)
    }
}

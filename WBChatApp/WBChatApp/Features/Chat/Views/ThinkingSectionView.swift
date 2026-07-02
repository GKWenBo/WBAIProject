//
//  ThinkingSectionView.swift
//  WBChatApp
//

import SwiftUI

/// 深度思考的推理过程：可折叠的灰色小字区块
struct ThinkingSectionView: View {

    let reasoning: String
    let isInitiallyExpanded: Bool

    @State private var isExpanded: Bool

    init(reasoning: String, isInitiallyExpanded: Bool) {
        self.reasoning = reasoning
        self.isInitiallyExpanded = isInitiallyExpanded
        _isExpanded = State(initialValue: isInitiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb.min")
                    Text("思考过程")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(reasoning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.quaternary)
                            .frame(width: 2)
                    }
            }
        }
    }
}

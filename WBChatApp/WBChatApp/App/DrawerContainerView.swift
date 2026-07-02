//
//  DrawerContainerView.swift
//  WBChatApp
//

import SwiftUI

/// 抽屉容器：左侧抽屉常驻，主内容随手势平移，展开时带圆角与遮罩
struct DrawerContainerView<Drawer: View, Content: View>: View {

    @Binding var isOpen: Bool
    @ViewBuilder let drawer: () -> Drawer
    @ViewBuilder let content: () -> Content

    /// 手势进行中的临时位移
    @GestureState private var dragTranslation: CGFloat = 0

    /// 抽屉占屏宽比例
    private static var drawerWidthRatio: CGFloat { 0.82 }

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = proxy.size.width * Self.drawerWidthRatio
            let baseOffset = isOpen ? drawerWidth : 0
            let offset = min(max(baseOffset + dragTranslation, 0), drawerWidth)
            let progress = offset / drawerWidth

            ZStack(alignment: .leading) {
                drawer()
                    .frame(width: drawerWidth)
                    .offset(x: (progress - 1) * 40)

                content()
                    .clipShape(RoundedRectangle(cornerRadius: progress * 28))
                    .overlay {
                        // 展开时点击主内容收起抽屉
                        if isOpen {
                            Color.black.opacity(0.08 * progress)
                                .clipShape(RoundedRectangle(cornerRadius: progress * 28))
                                .onTapGesture { close() }
                        }
                    }
                    .shadow(color: .black.opacity(0.15 * progress), radius: 16, x: -4, y: 0)
                    .offset(x: offset)
            }
            // 主内容被 clipShape 裁掉了安全区的背景延伸，安全区露出的是这里的容器底色：
            // 关闭时保持与主内容一致的白色，随抽屉拖出渐变为灰色，避免上下出现色差分层
            .background {
                ZStack {
                    Color(.systemBackground)
                    Color(.secondarySystemBackground).opacity(progress)
                }
                .ignoresSafeArea()
            }
            .gesture(dragGesture(drawerWidth: drawerWidth))
        }
        .ignoresSafeArea(.keyboard, edges: isOpen ? .bottom : [])
    }

    // MARK: - Gesture

    private func dragGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                // 只响应横向为主的拖动，避免抢消息列表的纵向滚动
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.width
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if isOpen {
                        if predicted < -drawerWidth / 3 { isOpen = false }
                    } else {
                        if predicted > drawerWidth / 3 { isOpen = true }
                    }
                }
            }
    }

    private func close() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isOpen = false
        }
    }
}

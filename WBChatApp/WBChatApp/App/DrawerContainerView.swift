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

    /// 手势进行中的位移。用 @State 而非 @GestureState：
    /// @GestureState 在松手瞬间会无动画地重置为 0（界面先跳回再播动画），
    /// @State 才能让位移与 isOpen 在同一个动画里从当前位置一起归位
    @State private var dragTranslation: CGFloat = 0
    /// 灰色底是否点亮：开合动画期间保持全不透明，避免安全区露出白底
    @State private var showsBackdrop = false

    /// 抽屉占屏宽比例
    private static var drawerWidthRatio: CGFloat { 0.82 }
    private static var settleAnimation: Animation { .spring(response: 0.35, dampingFraction: 0.85) }

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
                        // 遮罩常驻以便随 progress 平滑淡入淡出；仅展开时拦截点击用于收起
                        Color.black.opacity(0.08 * progress)
                            .clipShape(RoundedRectangle(cornerRadius: progress * 28))
                            .allowsHitTesting(isOpen)
                            .onTapGesture { settle(open: false) }
                    }
                    .shadow(color: .black.opacity(0.15 * progress), radius: 16, x: -4, y: 0)
                    .offset(x: offset)
            }
            .background {
                // 主内容被 clipShape 裁掉了安全区的背景延伸，安全区露出的是这里的底色。
                // 灰色不做渐变：打开瞬间点亮、收起动画结束后才熄灭，
                // 两个切换时机主内容都恰好铺满全屏，因此开合动画全程不会露白
                ZStack {
                    Color(.systemBackground)
                    Color(.secondarySystemBackground)
                        .opacity(showsBackdrop ? 1 : 0)
                        .transaction { $0.animation = nil }
                }
                .ignoresSafeArea()
            }
            .gesture(dragGesture(drawerWidth: drawerWidth))
        }
        .ignoresSafeArea(.keyboard, edges: isOpen ? .bottom : [])
        .onAppear {
            showsBackdrop = isOpen
        }
        .onChange(of: isOpen) { _, newValue in
            // 兼容外部开合（菜单按钮、选中会话）：开灯要立即，熄灯要等动画结束
            if newValue {
                showsBackdrop = true
            } else {
                dismissBackdropAfterSettle()
            }
        }
    }

    // MARK: - Gesture

    private func dragGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                // 只响应横向为主的拖动，避免抢消息列表的纵向滚动
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragTranslation = value.translation.width
                showsBackdrop = true
            }
            .onEnded { value in
                guard dragTranslation != 0 else { return }
                let predicted = value.predictedEndTranslation.width
                let shouldOpen = isOpen
                    ? predicted >= -drawerWidth / 3
                    : predicted > drawerWidth / 3
                settle(open: shouldOpen)
            }
    }

    // MARK: - Settle

    /// 从当前位置动画到目标状态：isOpen 与拖拽位移在同一个动画里归位
    private func settle(open: Bool) {
        withAnimation(Self.settleAnimation) {
            isOpen = open
            dragTranslation = 0
        }
        if !open {
            dismissBackdropAfterSettle()
        }
    }

    /// 收起动画结束后再熄灭灰色底（提前熄会在卡片滑回途中露白）
    private func dismissBackdropAfterSettle() {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !isOpen && dragTranslation == 0 {
                showsBackdrop = false
            }
        }
    }
}

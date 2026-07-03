//
//  DrawerContainerView.swift
//  WBChatApp
//

import SwiftUI

/// 抽屉容器：左侧抽屉常驻，主内容随手势平移，展开时带圆角与阴影（ChatGPT 风格）
struct DrawerContainerView<Drawer: View, Content: View>: View {

    @Binding var isOpen: Bool
    @ViewBuilder let drawer: () -> Drawer
    @ViewBuilder let content: () -> Content

    /// 手势进行中的位移。用 @State 而非 @GestureState：
    /// @GestureState 在松手瞬间会无动画地重置为 0（界面先跳回再播动画），
    /// @State 才能让位移与 isOpen 在同一个动画里从当前位置一起归位
    @State private var dragTranslation: CGFloat = 0
    /// 手势激活首帧的位移基准：DragGesture 有 24pt 启动阈值，
    /// 首帧 translation 已带上这段位移，扣除后拖动才能从 0 开始跟手不跳变
    @State private var dragBaseX: CGFloat?
    /// 本次手势锁定的方向：首帧判定后保持到手势结束，横竖只响应其一。
    /// 横向 → 拖抽屉并禁用列表滚动；纵向 → 交给列表滚动，抽屉全程不动
    private enum DragAxis { case horizontal, vertical }
    @State private var dragAxis: DragAxis?

    private var isHorizontalDragging: Bool { dragAxis == .horizontal }

    private static var drawerWidthRatio: CGFloat { 0.82 }
    private static var maxCornerRadius: CGFloat { 40 }
    private static var settleAnimation: Animation { .spring(response: 0.35, dampingFraction: 0.85) }

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = proxy.size.width * Self.drawerWidthRatio
            let baseOffset = isOpen ? drawerWidth : 0
            let offset = min(max(baseOffset + dragTranslation, 0), drawerWidth)
            let progress = offset / drawerWidth
            // 含安全区的整屏尺寸：让圆角出现在屏幕物理四角而非安全区边缘
            let fullSize = CGSize(
                width: proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            )
            let maskCenterOffsetY = (proxy.safeAreaInsets.bottom - proxy.safeAreaInsets.top) / 2

            ZStack(alignment: .leading) {
                drawer()
                    .frame(width: drawerWidth)
                    .offset(x: (progress - 1) * 40)
                    // 横向拖抽屉期间，同样禁用抽屉里会话列表的纵向滚动
                    .environment(\.isDrawerInteracting, isHorizontalDragging)

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 横向拖抽屉期间，禁用主内容里的纵向滚动，避免上下滑与抽屉手势打架
                    .environment(\.isDrawerInteracting, isHorizontalDragging)
                    // 圆角随进度放大：关闭时为 0，无需切角，不会露出下层背景
                    .mask {
                        RoundedRectangle(cornerRadius: Self.maxCornerRadius, style: .continuous)
                            .frame(width: fullSize.width, height: fullSize.height)
                            .offset(y: maskCenterOffsetY)
                    }
                    .overlay {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .allowsHitTesting(isOpen)
                            .onTapGesture { settle(open: false) }
                    }
                    .shadow(color: .black.opacity(0.15 * progress), radius: 16, x: -4, y: 0)
                    .offset(x: offset)
            }
            .background(Color(.secondarySystemBackground).ignoresSafeArea())
            .simultaneousGesture(dragGesture(drawerWidth: drawerWidth))
        }
        .ignoresSafeArea(.keyboard, edges: isOpen ? .bottom : [])
    }

    // MARK: - Gesture

    private func dragGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                // 首帧按位移占优判定方向并锁定到手势结束：
                // 判定为纵向后即使中途横向占优也不再接管，保证同一时刻只响应一个方向
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height)
                        ? .horizontal : .vertical
                }
                guard dragAxis == .horizontal else { return }
                let base = dragBaseX ?? value.translation.width
                dragBaseX = base
                dragTranslation = value.translation.width - base
            }
            .onEnded { value in
                dragAxis = nil
                guard let base = dragBaseX else { return }
                dragBaseX = nil
                let predicted = value.predictedEndTranslation.width - base
                let shouldOpen = isOpen
                    ? predicted >= -drawerWidth / 3
                    : predicted > drawerWidth / 3
                settle(open: shouldOpen)
            }
    }

    // MARK: - Settle

    private func settle(open: Bool) {
        withAnimation(Self.settleAnimation) {
            isOpen = open
            dragTranslation = 0
        }
    }
}

// MARK: - Environment

private struct DrawerInteractingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 抽屉正在被横向拖动。主内容里的滚动视图据此临时禁用滚动，解决上下滑与抽屉手势的冲突
    var isDrawerInteracting: Bool {
        get { self[DrawerInteractingKey.self] }
        set { self[DrawerInteractingKey.self] = newValue }
    }
}

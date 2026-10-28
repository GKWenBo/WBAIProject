import UIKit

/// 左侧抽屉容器（ChatGPT 风格）：抽屉常驻底层，主内容浮在上层随手势平移，
/// 展开过程中长出圆角、阴影与上下留白，抽屉自身带轻微视差。
///
/// 三个不直观的约束写在各自位置，改动前先看一眼：
/// - 手势必须与列表滚动共存，靠方向锁仲裁（`handlePan`）；
/// - 圆角与阴影必须挂在不同 layer（`contentContainerView`）；
/// - 遮罩必须与卡片逐像素重合，否则圆角缺口会被压出直角暗块（`dimmingView`）。
final class DrawerContainerViewController: UIViewController {

    // MARK: - 几何与手感参数

    private static let drawerWidthRatio: CGFloat = 0.82
    private static let maxDrawerWidth: CGFloat = 320
    /// 展开态圆角，按进度收敛到 0——关闭态不切角、不露下层背景
    private static let maxCornerRadius: CGFloat = 38
    /// 抽屉视差：关闭态左移这么多 pt 随进度归位。
    private static let drawerParallax: CGFloat = 24
    /// 展开态卡片上下各让出的高度，关闭态为 0（占满全高）。
    /// 遮罩与阴影都要跟着内缩，否则缝里会压着一层灰
    private static let maxVerticalInset: CGFloat = 12
    /// 容器比卡片左右各宽出的余量：归位弹簧会轻微过冲，
    /// 卡片贴着屏幕边缘时，过冲会在边缘露出一条容器底色
    private static let overshootMargin: CGFloat = 8
    private static let maxDimmingAlpha: CGFloat = 0.15
    private static let shadowRadius: CGFloat = 14
    private static let shadowOpacity: Float = 0.12
    /// 方向锁启动阈值：太小会被手指落下的抖动误判，太大有一段不跟手的死区
    private static let axisLockThreshold: CGFloat = 12
    /// 关闭态允许「右滑拉开抽屉」的起手区（占屏宽比例）。
    /// 展开态不限——此时任意位置左滑都该能收起
    private static let openGestureZoneRatio: CGFloat = 0.35
    private static let settleDuration: TimeInterval = 0.35
    /// 超过它直接按甩动方向吸附，不再看松手位置
    private static let flickVelocityThreshold: CGFloat = 500

    private enum DragAxis { case horizontal, vertical }

    // MARK: - 视图

    private let drawerViewController: UIViewController
    private var contentViewController: UIViewController

    /// 主内容容器，负责平移与投影。
    /// 阴影只能挂这一层：内层要 `masksToBounds = true` 才切得出圆角，
    /// 而同一 layer 上 masksToBounds 会把阴影一起裁掉，只好拆成两层
    private let contentContainerView = UIView()

    /// 压暗卡片的遮罩，形状必须与卡片完全重合：同起点、同圆角、同上下内缩。
    /// 旧实现是矩形，它那条直角边正好切在圆角缺口上，把缺口压成一块直角暗块
    private let dimmingView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.alpha = 0
        view.isUserInteractionEnabled = false
        // 右侧两角在屏幕外，圆角化反而会在屏幕右缘切出缺口
        view.layer.cornerCurve = .continuous
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var panGesture: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        return pan
    }()

    // MARK: - 状态

    private var isOpen = false
    /// 主内容当前的 x 偏移，拖动、动画、布局共用的唯一真源
    private var contentX: CGFloat = 0

    /// 手指正在拖动
    private var isDragging = false
    /// 松手后的归位动画进行中
    private var isSettling = false
    /// 归位动画代数，用来让被打断的旧动画 completion 失效
    private var settleGeneration = 0

    /// 手势开始那一刻的 contentX，拖动增量要叠加在它上面。
    /// 展开态下它是 `drawerWidth` 而非 0：不记下起点，抽屉会「开着往右拖先闪回关闭态」
    private var dragStartX: CGFloat = 0
    /// 方向锁定那一帧已发生的横向位移，扣掉它拖动才能从 0 开始跟手
    private var dragBaseX: CGFloat?
    /// 本次手势锁定的方向，判定后保持到手势结束
    private var dragAxis: DragAxis?
    /// 被本次手势临时关掉的滚动视图，松手精准还原（无脑全开会误开本来就 disabled 的）
    private var disabledScrollViews: [UIScrollView] = []

    // MARK: - 生命周期

    init(drawer: UIViewController, content: UIViewController) {
        self.drawerViewController = drawer
        self.contentViewController = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.secondaryBackground

        addChild(drawerViewController)
        view.addSubview(drawerViewController.view)
        drawerViewController.didMove(toParent: self)

        contentContainerView.backgroundColor = .clear
        setUpShadow()
        view.addSubview(contentContainerView)
        installContent(contentViewController)

        // 遮罩留在最顶层：它只盖卡片露出的部分，从不叠到抽屉区，避免吞掉抽屉的触摸事件
        view.addSubview(dimmingView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(closeDrawer))
        dimmingView.addGestureRecognizer(tap)

        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 归位动画中不要碰 frame，否则会把动画打断在半路
        guard !isSettling else { return }
        // 拖动中同理，否则键盘弹出等布局事件会把抽屉拽回去
        if !isDragging { contentX = isOpen ? drawerWidth : 0 }
        applyLayout()
    }

    // MARK: - 装配

    private func installContent(_ viewController: UIViewController) {
        addChild(viewController)
        // 当场给 frame：随后那次布局可能被 `isSettling` 挡掉，
        // 新内容会先按自己的默认尺寸闪一帧（高度对不上卡片）
        viewController.view.frame = CGRect(x: Self.overshootMargin, y: 0,
                                           width: cardFrame.width, height: cardFrame.height)
        contentContainerView.addSubview(viewController.view)
        viewController.didMove(toParent: self)
    }

    private func setUpShadow() {
        let layer = contentContainerView.layer
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = Self.shadowRadius
        layer.shadowOffset = CGSize(width: -6, height: 0)
        layer.shadowOpacity = 0
    }

    // MARK: - 布局

    private var drawerWidth: CGFloat {
        min(view.bounds.width * Self.drawerWidthRatio, Self.maxDrawerWidth)
    }

    /// 展开进度 0...1
    private var progress: CGFloat {
        guard drawerWidth > 0 else { return 0 }
        return min(max(contentX / drawerWidth, 0), 1)
    }

    private func applyLayout() {
        layoutDrawer()
        layoutContent()
        layoutDimming()
    }

    private func layoutDrawer() {
        // 视差只改变位置；加宽会让右侧按钮和列表落到主卡片下方。
        let width = drawerWidth
        let x = -Self.drawerParallax * (1 - progress)
        drawerViewController.view.frame = CGRect(x: x, y: 0,
                                                 width: width, height: view.bounds.height)
    }

    /// 卡片当前上下各让出的高度。量化到 0.5pt：拖动中进度是连续量，
    /// 不量化会每帧产生亚像素的高度变化，反复唤醒卡片内部的 Auto Layout
    private var currentVerticalInset: CGFloat {
        (Self.maxVerticalInset * progress * 2).rounded() / 2
    }

    /// 卡片在屏幕上的可见 frame。布局、遮罩、测试断言都读它，
    /// 避免各处自己去拼「contentX + 上下留缝」，也绕开容器那圈防过冲余量
    private var cardFrame: CGRect {
        let inset = currentVerticalInset
        return CGRect(x: contentX, y: inset,
                      width: view.bounds.width,
                      height: max(0, view.bounds.height - inset * 2))
    }

    private func layoutContent() {
        let radius = Self.maxCornerRadius * progress
        let card = cardFrame

        contentContainerView.frame = CGRect(x: card.minX - Self.overshootMargin, y: card.minY,
                                            width: card.width + Self.overshootMargin * 2,
                                            height: card.height)
        contentViewController.view.frame = CGRect(x: Self.overshootMargin, y: 0,
                                                  width: card.width, height: card.height)

        let contentLayer = contentViewController.view.layer
        contentLayer.cornerRadius = radius
        contentLayer.cornerCurve = .continuous
        // 恒为 true：关闭态圆角是 0 裁不掉任何东西，放开会在展开瞬间闪一下方角
        contentLayer.masksToBounds = true

        let containerLayer = contentContainerView.layer
        containerLayer.shadowOpacity = Self.shadowOpacity * Float(progress)
        // 显式 shadowPath：圆角每帧都在变，让系统自己从内容推导阴影形状太贵。
        // 用卡片那块矩形，不能图省事用容器 bounds——容器含防过冲余量，阴影会偏
        containerLayer.shadowPath = UIBezierPath(
            roundedRect: CGRect(x: Self.overshootMargin, y: 0,
                                width: card.width, height: card.height),
            cornerRadius: radius).cgPath
    }

    /// 与卡片逐像素重合：同起点、同圆角、同上下内缩
    private func layoutDimming() {
        let card = cardFrame
        dimmingView.frame = CGRect(x: card.minX, y: card.minY,
                                   width: max(0, view.bounds.width - card.minX) + Self.overshootMargin,
                                   height: card.height)
        dimmingView.layer.cornerRadius = Self.maxCornerRadius * progress
        dimmingView.alpha = Self.maxDimmingAlpha * progress
    }

    // MARK: - 外部接口

    /// 换掉主内容（切换会话）。新内容插进 `contentContainerView`，
    /// 遮罩始终在最外层，层级不变式不受影响。
    func setContent(_ newContent: UIViewController) {
        let suspendScrolling = dragAxis == .horizontal || isSettling
        setInnerScrollEnabled(true)
        contentViewController.willMove(toParent: nil)
        contentViewController.view.removeFromSuperview()
        contentViewController.removeFromParent()

        contentViewController = newContent
        installContent(newContent)
        // 同步应用圆角和尺寸，动画中换会话也不能闪出方角。
        applyLayout()
        if suspendScrolling { setInnerScrollEnabled(false) }
    }

    @objc func toggleDrawer() {
        setDrawer(open: !isOpen, animated: true)
    }

    @objc func closeDrawer() {
        setDrawer(open: false, animated: true)
    }

    // MARK: - 开合

    private func setDrawer(open: Bool, animated: Bool) {
        isOpen = open
        dimmingView.isUserInteractionEnabled = open
        if open { view.endEditing(true) }

        let targetX = open ? drawerWidth : 0
        guard animated else {
            cancelRunningAnimation()
            contentX = targetX
            applyLayout()
            setInnerScrollEnabled(true)
            return
        }
        animate(to: targetX)
    }

    private func animate(to targetX: CGFloat) {
        cancelRunningAnimation()
        contentX = targetX
        isSettling = true
        setInnerScrollEnabled(false)
        // 动画被打断时旧 completion 会以 finished=false 触发；只有最后一次
        // 归位有权清标记并补布局，否则会把新动画或新布局错认成「已结束」
        settleGeneration += 1
        let generation = settleGeneration
        UIView.animate(
            withDuration: Self.settleDuration,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0,
            // allowUserInteraction：动画途中仍可再次按下拖动；
            // beginFromCurrentState：从被打断那一刻接续，不跳到终点
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
            animations: { self.applyLayout() },
            completion: { [weak self] _ in
                guard let self, self.settleGeneration == generation else { return }
                self.isSettling = false
                // 动画期间可能换过 bounds（旋转/分屏），而布局是被 isSettling 挡掉的，
                // 这里必须补一次，否则几何会一直停在旧尺寸上
                self.contentX = self.isOpen ? self.drawerWidth : 0
                self.applyLayout()
                self.setInnerScrollEnabled(true)
            }
        )
    }

    /// 动画被下一次拖动打断时，先把 model layer 对齐到用户此刻看到的位置
    /// （presentation layer）再移除动画。顺序反了会先跳到终点再跟手。
    private func cancelRunningAnimation() {
        guard isSettling else { return }
        // 必须先作废旧 completion，再移除动画，避免旧回调干扰新手势。
        settleGeneration += 1
        isSettling = false
        let presentationX = contentContainerView.layer.presentation()?.frame.minX

        contentContainerView.layer.removeAllAnimations()
        contentViewController.view.layer.removeAllAnimations()
        drawerViewController.view.layer.removeAllAnimations()
        dimmingView.layer.removeAllAnimations()

        // 动画闭包是同步执行的，model layer 早就停在终态（上下留缝、遮罩 x、
        // 抽屉视差都已是终点值）。只把 x 改回去会留下一个「x 在半路、
        // 其余在终点」的错位，所以拿到 x 后要让一切从同一个 x 重新推导
        if let x = presentationX {
            contentX = x + Self.overshootMargin
        }
        applyLayout()
    }

    // MARK: - 手势

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        handlePan(state: gesture.state,
                  translationX: translation.x,
                  translationY: translation.y,
                  velocityX: gesture.velocity(in: view).x)
    }

    /// 与 `UIGestureRecognizer` 解耦：手势对象在单测里不便构造
    /// （`translation(in:)` / `velocity(in:)` 无法注入），测试走 `simulatePanForTesting`
    private func handlePan(state: UIGestureRecognizer.State,
                           translationX: CGFloat,
                           translationY: CGFloat,
                           velocityX: CGFloat) {
        switch state {
        case .began:
            cancelRunningAnimation()
            isDragging = true
            dragStartX = contentX
            dragBaseX = nil
            dragAxis = nil
            setInnerScrollEnabled(true)
            fallthrough

        case .changed:
            guard isDragging else { return }
            if dragAxis == nil {
                // 位移还不够判定方向时按兵不动，别在手指刚落下就抢走列表的滚动
                guard max(abs(translationX), abs(translationY)) >= Self.axisLockThreshold
                else { return }
                dragAxis = abs(translationX) > abs(translationY) ? .horizontal : .vertical
                if dragAxis == .horizontal {
                    dragBaseX = translationX
                    setInnerScrollEnabled(false)
                }
            }
            guard dragAxis == .horizontal else { return }
            contentX = clamp(dragStartX + (translationX - (dragBaseX ?? 0)), 0, drawerWidth)
            applyLayout()

        // .failed 也要走收尾：只处理 .ended/.cancelled 的话，手势被系统判失败时
        // 临时禁用的滚动不会被还原，列表从此再也滚不动
        case .ended, .cancelled, .failed:
            guard isDragging else { return }
            isDragging = false
            let axis = dragAxis
            dragAxis = nil
            dragBaseX = nil
            guard axis == .horizontal else {
                // 起手打断动画后即使没有锁定横向，也要回到完整开合状态。
                if contentX != (isOpen ? drawerWidth : 0) {
                    setDrawer(open: isOpen, animated: true)
                }
                return
            }
            settleAfterDrag(velocityX: state == .ended ? velocityX : 0)

        default:
            break
        }
    }

    /// 松手后决定吸附到开还是关
    private func settleAfterDrag(velocityX: CGFloat) {
        let shouldOpen: Bool
        if velocityX > Self.flickVelocityThreshold {
            shouldOpen = true
        } else if velocityX < -Self.flickVelocityThreshold {
            shouldOpen = false
        } else {
            // 速度不足以判定时按位置兜底：过半才算数
            shouldOpen = contentX > drawerWidth / 2
        }
        setDrawer(open: shouldOpen, animated: true)
    }

    private func clamp(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }

    // MARK: - 与列表滚动共存

    /// 横向拖动期间关掉两侧滚动。抽屉手势与 scrollView 的 pan 是同时识别的，
    /// 不关掉的话斜着划会一边拖抽屉一边滚列表
    private func setInnerScrollEnabled(_ enabled: Bool) {
        if enabled {
            disabledScrollViews.forEach { $0.isScrollEnabled = true }
            disabledScrollViews.removeAll()
            return
        }
        guard disabledScrollViews.isEmpty else { return }
        disabledScrollViews = scrollViews(in: drawerViewController.view)
            + scrollViews(in: contentContainerView)
        disabledScrollViews.forEach { $0.isScrollEnabled = false }
    }

    /// 只收集本来就是 enabled 的，还原时才不会误开业务关掉的那些
    private func scrollViews(in root: UIView) -> [UIScrollView] {
        var result: [UIScrollView] = []
        if let scrollView = root as? UIScrollView, scrollView.isScrollEnabled {
            result.append(scrollView)
        }
        for subview in root.subviews {
            result.append(contentsOf: scrollViews(in: subview))
        }
        return result
    }
}

// MARK: - UIGestureRecognizerDelegate

extension DrawerContainerViewController: UIGestureRecognizerDelegate {

    /// 关闭态只认屏幕左侧区域的右滑，中间和右侧留给内容自己的交互；展开态不限
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture else { return true }
        if isOpen { return true }
        return panGesture.location(in: view).x <= view.bounds.width * Self.openGestureZoneRatio
    }

    /// 只有列表自己的纵向滚动能与抽屉共存，其余横向手势抽屉一律让位。
    ///
    /// 无脑允许共存时，行左滑（swipe action）会一边划出删除按钮一边把抽屉收走：
    /// 两个 pan 同时识别，方向锁判横向，抽屉就跟着一起动了。
    /// 挂在滚动视图上但**不是它自己的滚动手势**的那些（行左滑的 swipe action）也不算，
    /// 否则列表自己的滚动手势和行左滑会被混为一谈。
    private func isVerticalScrollPan(_ gesture: UIGestureRecognizer) -> Bool {
        guard let scrollView = gesture.view as? UIScrollView else { return false }
        // 横向可滚的（代码块）交给它自己
        guard scrollView.contentSize.width <= scrollView.bounds.width + 1 else { return false }
        return gesture === scrollView.panGestureRecognizer
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer)
    -> Bool {
        // 列表纵向滚动必须同时响应，否则滑不动列表；由方向锁决定谁真正动作
        isVerticalScrollPan(otherGestureRecognizer)
    }

    /// 其余横向手势（行左滑、代码块横向滚动、系统侧滑返回）先给它们机会，
    /// 抽屉等它们失败后再接管。只拒绝共存是不够的——那样变成两边抢，
    /// 实测下来是抽屉抢赢，行左滑就彻底划不出来了
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer)
    -> Bool {
        guard otherGestureRecognizer is UIPanGestureRecognizer else { return false }
        return !isVerticalScrollPan(otherGestureRecognizer)
    }
}

// MARK: - 测试入口

extension DrawerContainerViewController {

    /// 主内容在屏幕上的真实位置。它被包进 `contentContainerView` 后自己的
    /// `frame.origin.x` 只是容器内的偏移，断言抽屉位置要读这个
    var contentOriginXForTesting: CGFloat { cardFrame.minX }

    var contentCornerRadiusForTesting: CGFloat { contentViewController.view.layer.cornerRadius }

    /// 卡片当前上下各让出的高度（展开态 `maxVerticalInset`，关闭态 0）
    var contentVerticalInsetForTesting: CGFloat { cardFrame.minY }

    /// 卡片与遮罩的 frame，两者必须逐像素重合
    var cardFrameForTesting: CGRect { cardFrame }

    var dimmingFrameForTesting: CGRect { dimmingView.frame }

    var dimmingCornerRadiusForTesting: CGFloat { dimmingView.layer.cornerRadius }

    var isOpenForTesting: Bool { isOpen }

    /// 无动画地摆到开/关态搭前置条件。走 `toggleDrawer()` 会留一个正在跑的动画，
    /// 紧接着的 `.began` 会按「从当前可见位置接续」把起点算成动画起点
    func setDrawerForTesting(open: Bool) {
        setDrawer(open: open, animated: false)
    }

    /// 供测试驱动一次完整的拖动手势，参数与 `handlePan` 一一对应
    func simulatePanForTesting(state: UIGestureRecognizer.State,
                               translationX: CGFloat,
                               translationY: CGFloat = 0,
                               velocityX: CGFloat = 0) {
        handlePan(state: state,
                  translationX: translationX,
                  translationY: translationY,
                  velocityX: velocityX)
    }

}

import UIKit

/// 左侧抽屉容器。支持边缘滑出、点遮罩关闭。
final class DrawerContainerViewController: UIViewController {

    private static let drawerWidthRatio: CGFloat = 0.8
    private static let maxDrawerWidth: CGFloat = 320

    private let drawerViewController: UIViewController
    private var contentViewController: UIViewController

    private let dimmingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.alpha = 0
        view.isUserInteractionEnabled = false
        return view
    }()

    private var isOpen = false

    private var drawerWidth: CGFloat {
        min(view.bounds.width * Self.drawerWidthRatio, Self.maxDrawerWidth)
    }

    init(drawer: UIViewController, content: UIViewController) {
        self.drawerViewController = drawer
        self.contentViewController = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        addChild(drawerViewController)
        view.addSubview(drawerViewController.view)
        drawerViewController.didMove(toParent: self)

        addChild(contentViewController)
        view.addSubview(contentViewController.view)
        contentViewController.didMove(toParent: self)

        // dimmingView 必须在最顶层：它只覆盖 content 被平移后露出的那部分矩形，
        // 从不叠在 drawer 区域上，drawer 区域自己的 UI 才不会被遮罩吞掉触摸事件。
        view.addSubview(dimmingView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(closeDrawer))
        dimmingView.addGestureRecognizer(tap)

        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
        pan.edges = .left
        view.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        drawerViewController.view.frame = CGRect(x: 0, y: 0,
                                                 width: drawerWidth, height: view.bounds.height)
        layoutContent(open: isOpen)
    }

    func setContent(_ newContent: UIViewController) {
        contentViewController.willMove(toParent: nil)
        contentViewController.view.removeFromSuperview()
        contentViewController.removeFromParent()

        contentViewController = newContent
        addChild(newContent)
        // 插在 dimmingView 下面，保证遮罩始终在最顶层
        view.insertSubview(newContent.view, belowSubview: dimmingView)
        newContent.didMove(toParent: self)
        layoutContent(open: isOpen)
    }

    @objc func toggleDrawer() {
        setDrawer(open: !isOpen, animated: true)
    }

    @objc func closeDrawer() {
        setDrawer(open: false, animated: true)
    }

    private func setDrawer(open: Bool, animated: Bool) {
        isOpen = open
        dimmingView.isUserInteractionEnabled = open
        let animations = {
            self.layoutContent(open: open)
            self.dimmingView.alpha = open ? 1 : 0
        }
        if animated {
            UIView.animate(withDuration: 0.28,
                           delay: 0,
                           usingSpringWithDamping: 0.9,
                           initialSpringVelocity: 0,
                           options: .curveEaseOut,
                           animations: animations)
        } else {
            animations()
        }
    }

    private func layoutContent(open: Bool) {
        let x = open ? drawerWidth : 0
        contentViewController.view.frame = CGRect(x: x, y: 0,
                                                  width: view.bounds.width,
                                                  height: view.bounds.height)
        updateDimmingFrame(contentX: x)
    }

    /// 遮罩只覆盖 content 被平移后露出的那块矩形（x 从 contentX 到屏幕右边缘），
    /// 永远不会盖到 [0, contentX) 这段 drawer 自己的区域，避免吞掉抽屉的触摸事件。
    private func updateDimmingFrame(contentX x: CGFloat) {
        dimmingView.frame = CGRect(x: x, y: 0,
                                   width: max(0, view.bounds.width - x),
                                   height: view.bounds.height)
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        switch gesture.state {
        case .changed:
            let translation = max(0, min(drawerWidth, gesture.translation(in: view).x))
            contentViewController.view.frame.origin.x = translation
            dimmingView.alpha = translation / drawerWidth
            updateDimmingFrame(contentX: translation)
        case .ended, .cancelled:
            let shouldOpen = gesture.translation(in: view).x > drawerWidth / 2
                || gesture.velocity(in: view).x > 500
            setDrawer(open: shouldOpen, animated: true)
        default:
            break
        }
    }
}

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

        view.insertSubview(dimmingView, belowSubview: contentViewController.view)

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
        dimmingView.frame = view.bounds
        layoutContent(open: isOpen)
    }

    func setContent(_ newContent: UIViewController) {
        contentViewController.willMove(toParent: nil)
        contentViewController.view.removeFromSuperview()
        contentViewController.removeFromParent()

        contentViewController = newContent
        addChild(newContent)
        view.addSubview(newContent.view)
        newContent.didMove(toParent: self)
        view.insertSubview(dimmingView, belowSubview: newContent.view)
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
        contentViewController.view.frame = CGRect(x: open ? drawerWidth : 0, y: 0,
                                                  width: view.bounds.width,
                                                  height: view.bounds.height)
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        switch gesture.state {
        case .changed:
            let translation = max(0, min(drawerWidth, gesture.translation(in: view).x))
            contentViewController.view.frame.origin.x = translation
            dimmingView.alpha = translation / drawerWidth
        case .ended, .cancelled:
            let shouldOpen = gesture.translation(in: view).x > drawerWidth / 2
                || gesture.velocity(in: view).x > 500
            setDrawer(open: shouldOpen, animated: true)
        default:
            break
        }
    }
}

import UIKit

/// 场景入口：先挂占位页，异步打开数据库后换成真正的根控制器，并把前后台切换转给生成协调器。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    /// 依赖容器，数据库打开成功后才有值
    private var container: AppContainer?
    /// 防止"重试"连点导致重复打开数据库
    private var loading = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: scene)
        window?.rootViewController = UIViewController()
        window?.rootViewController?.view.backgroundColor = .systemBackground
        window?.makeKeyAndVisible()
        openStore()
    }

    /// 后台线程打开数据库并恢复中断的生成；失败时弹窗允许重试，不降级到临时存储
    private func openStore() {
        guard !loading else { return }
        loading = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.loading = false }
            do {
                let container = try await AppContainer.open()
                self.container = container
                self.window?.rootViewController = try container.makeRootViewController()
                if self.window?.windowScene?.activationState == .background { container.generations.enterBackground() }
            } catch {
                let screen = UIViewController()
                screen.view.backgroundColor = .systemBackground
                self.window?.rootViewController = screen
                let alert = UIAlertController(title: "无法打开聊天记录", message: "本地存储暂时不可用，未切换到临时存储。请重试。", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in self?.openStore() })
                screen.present(alert, animated: true)
            }
        }
    }

    /// 前后台切换：进后台申请后台时间收尾生成，回前台恢复
    func sceneDidEnterBackground(_ scene: UIScene) { container?.generations.enterBackground() }
    func sceneWillEnterForeground(_ scene: UIScene) { container?.generations.enterForeground() }
}

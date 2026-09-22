import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var container: AppContainer?
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
    func sceneDidEnterBackground(_ scene: UIScene) { container?.generations.enterBackground() }
    func sceneWillEnterForeground(_ scene: UIScene) { container?.generations.enterForeground() }
}

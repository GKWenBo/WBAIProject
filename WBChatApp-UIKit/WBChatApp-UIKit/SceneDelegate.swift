import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        // 根控制器在 Task 16 接入 AppContainer，此处先放占位以保证工程可运行
        let placeholder = UIViewController()
        placeholder.view.backgroundColor = Theme.background
        window.rootViewController = placeholder
        window.makeKeyAndVisible()
        self.window = window
    }
}

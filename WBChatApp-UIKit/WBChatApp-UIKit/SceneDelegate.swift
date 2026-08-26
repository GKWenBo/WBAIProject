import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)

        let container = AppContainer.shared
        let chat = container.makeChatViewController(
            conversationID: container.currentOrNewConversationID())
        window.rootViewController = UINavigationController(rootViewController: chat)
        window.makeKeyAndVisible()
        self.window = window
    }
}

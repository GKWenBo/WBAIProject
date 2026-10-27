//
//  SceneDelegate.swift
//  TextKitExample
//

import UIKit

/// 纯代码建窗，工程里没有 Main.storyboard。
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: CaseListViewController())
        window.makeKeyAndVisible()
        self.window = window
    }
}

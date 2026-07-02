//
//  AppRouter.swift
//  WBChatApp
//

import Observation
import SwiftUI

/// 全局导航状态：抽屉开合、设置页弹出
@Observable
final class AppRouter {

    var isDrawerOpen = false
    var isSettingsPresented = false

    func openDrawer() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isDrawerOpen = true
        }
    }

    func closeDrawer() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isDrawerOpen = false
        }
    }
}

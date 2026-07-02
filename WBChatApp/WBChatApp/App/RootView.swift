//
//  RootView.swift
//  WBChatApp
//

import SwiftData
import SwiftUI

/// 根容器：抽屉（会话列表）+ 主内容（聊天页）
struct RootView: View {

    @Environment(\.modelContext) private var modelContext

    @State private var router = AppRouter()
    @State private var settings: AppSettings
    @State private var chatViewModel: ChatViewModel

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _chatViewModel = State(initialValue: ChatViewModel(settings: settings))
    }

    var body: some View {
        DrawerContainerView(isOpen: drawerBinding) {
            DrawerView(chatViewModel: chatViewModel)
        } content: {
            ChatView(viewModel: chatViewModel)
        }
        .sheet(isPresented: settingsBinding) {
            SettingsView()
        }
        // environment 放在 sheet 之外，弹出层才能继承到这两个对象
        .environment(router)
        .environment(settings)
        .onAppear {
            chatViewModel.configure(context: modelContext)
        }
    }

    private var drawerBinding: Binding<Bool> {
        Binding(
            get: { router.isDrawerOpen },
            set: { router.isDrawerOpen = $0 }
        )
    }

    private var settingsBinding: Binding<Bool> {
        Binding(
            get: { router.isSettingsPresented },
            set: { router.isSettingsPresented = $0 }
        )
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Conversation.self, Message.self], inMemory: true)
}

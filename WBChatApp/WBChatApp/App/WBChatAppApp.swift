//
//  WBChatAppApp.swift
//  WBChatApp
//

import SwiftData
import SwiftUI

@main
struct WBChatAppApp: App {

    private let modelContainer: ModelContainer = {
        let schema = Schema([Conversation.self, Message.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法创建 ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}

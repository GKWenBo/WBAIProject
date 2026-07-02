//
//  UITestSeeder.swift
//  WBChatApp
//

#if DEBUG
import Foundation
import SwiftData

/// UI 测试/截图专用的种子数据：`--uitest-seed` 启动参数触发
enum UITestSeeder {

    static let launchArgument = "--uitest-seed"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// 预填输入框草稿，并在库为空时插入几条带时间分组的历史会话
    static func seed(context: ModelContext, chatViewModel: ChatViewModel) {
        chatViewModel.draft = "写一个快速排序 Swift"

        let count = (try? context.fetchCount(FetchDescriptor<Conversation>())) ?? 0
        guard count == 0 else { return }

        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
        let seeds: [(title: String, date: Date)] = [
            ("Claude Code 定时任务设置", yesterday),
            ("招聘旺季月份", makeDate(calendar, 2026, 6, 20)),
            ("龙爪菊药用功效", makeDate(calendar, 2026, 6, 15)),
            ("各国汇率如何确定", makeDate(calendar, 2026, 6, 10)),
            ("Mac mini 外接触摸屏", makeDate(calendar, 2026, 6, 5)),
        ]
        for seed in seeds {
            let conversation = Conversation(title: seed.title, createdAt: seed.date)
            context.insert(conversation)
            let question = Message(role: .user, content: seed.title, createdAt: seed.date)
            context.insert(question)
            question.conversation = conversation
        }
        try? context.save()
    }

    private static func makeDate(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }
}
#endif

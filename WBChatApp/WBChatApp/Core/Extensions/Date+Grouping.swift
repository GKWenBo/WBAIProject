//
//  Date+Grouping.swift
//  WBChatApp
//

import Foundation

extension Date {

    /// 会话列表的时间分组标题：今天 / 昨天 / 2026年6月
    nonisolated var conversationSectionTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "今天" }
        if calendar.isDateInYesterday(self) { return "昨天" }
        let components = calendar.dateComponents([.year, .month], from: self)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }
}

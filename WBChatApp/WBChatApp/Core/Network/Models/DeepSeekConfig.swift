//
//  DeepSeekConfig.swift
//  WBChatApp
//

import Foundation

/// 单次请求所需的 DeepSeek 接入配置
nonisolated struct DeepSeekConfig: Equatable, Sendable {
    var baseURL: URL
    var apiKey: String
    var model: String
    var temperature: Double
}

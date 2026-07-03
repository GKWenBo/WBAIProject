//
//  AppSettings.swift
//  WBChatApp
//

import Foundation
import Observation

/// DeepSeek 配置入口：API Key 存钥匙串，其余偏好存 UserDefaults
@Observable
final class AppSettings {

    private enum Keys {
        static let baseURL = "settings.baseURL"
        static let chatModel = "settings.chatModel"
        static let temperature = "settings.temperature"
        static let apiKeyAccount = "com.wb.WBChatApp.deepseek.apiKey"
    }

    static let defaultBaseURL = "https://api.deepseek.com"
    static let defaultChatModel = "deepseek-v4-flash"

    var apiKey: String {
        didSet { KeychainHelper.set(apiKey, forKey: Keys.apiKeyAccount) }
    }

    var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: Keys.baseURL) }
    }

    var chatModel: String {
        didSet { defaults.set(chatModel, forKey: Keys.chatModel) }
    }

    var temperature: Double {
        didSet { defaults.set(temperature, forKey: Keys.temperature) }
    }

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiKey = KeychainHelper.string(forKey: Keys.apiKeyAccount) ?? ""
        self.baseURLString = defaults.string(forKey: Keys.baseURL) ?? Self.defaultBaseURL
        self.chatModel = defaults.string(forKey: Keys.chatModel) ?? Self.defaultChatModel
        self.temperature = defaults.object(forKey: Keys.temperature) as? Double ?? 1.0
    }

    /// 生成一次请求的配置；`deepThinking` 开启时切换到推理模型
    func requestConfig(deepThinking: Bool = true) throws -> DeepSeekConfig {
        guard let url = URL(string: baseURLString), url.scheme != nil else {
            throw APIError.invalidURL
        }
        return DeepSeekConfig(
            baseURL: url,
            apiKey: apiKey,
            model: chatModel,
            temperature: temperature
        )
    }
}

//
//  APIError.swift
//  WBChatApp
//

import Foundation

nonisolated enum APIError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "尚未配置 API Key，请前往设置填写"
        case .invalidURL:
            return "接口地址无效，请检查设置中的 Base URL"
        case .invalidResponse:
            return "服务器返回了无法识别的数据"
        case .server(let statusCode, let message):
            return message ?? "服务器错误（\(statusCode)）"
        }
    }
}

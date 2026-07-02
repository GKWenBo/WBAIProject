//
//  SettingsView.swift
//  WBChatApp
//

import SwiftUI

/// 设置页：DeepSeek 接入配置（API Key 存钥匙串）与生成参数
struct SettingsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    SecureField("API Key（sk-…）", text: $settings.apiKey)
                        .textContentType(.password)
                    TextField("Base URL", text: $settings.baseURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("默认模型", selection: $settings.chatModel) {
                        Text("deepseek-chat").tag("deepseek-chat")
                    }
                } header: {
                    Text("DeepSeek API")
                } footer: {
                    Text("API Key 保存在系统钥匙串。未配置时使用内置演示数据。开启「深度思考」后自动切换为 deepseek-reasoner。可前往 platform.deepseek.com 申请 Key。")
                }
                .listRowBackground(Color(.secondarySystemBackground))

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("温度")
                            Spacer()
                            Text(String(format: "%.1f", settings.temperature))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.temperature, in: 0...2, step: 0.1)
                    }
                } header: {
                    Text("生成参数")
                } footer: {
                    Text("值越高回答越发散，代码类任务建议 0.0，通用对话建议 1.0。")
                }
                .listRowBackground(Color(.secondarySystemBackground))

                Section("关于") {
                    LabeledContent("版本", value: "1.0")
                    LabeledContent(
                        "状态",
                        value: settings.isConfigured ? "已配置 API Key" : "演示模式"
                    )
                }
                .listRowBackground(Color(.secondarySystemBackground))
            }
            // 与聊天页统一为白底，分组卡片用与输入栏一致的灰色，避免弹出时背景分层
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
}

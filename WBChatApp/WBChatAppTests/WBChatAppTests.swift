//
//  WBChatAppTests.swift
//  WBChatAppTests
//

import Foundation
import Testing
@testable import WBChatApp

// MARK: - SSEParser

struct SSEParserTests {

    @Test("解析正文增量")
    func parsesContentDelta() {
        let line = #"data: {"choices":[{"delta":{"content":"你好"}}]}"#
        let event = SSEParser.parse(line: line)
        #expect(event == .chunk(StreamChunk(deltaContent: "你好")))
    }

    @Test("解析深度思考的推理增量")
    func parsesReasoningDelta() {
        let line = #"data: {"choices":[{"delta":{"reasoning_content":"先分析"}}]}"#
        let event = SSEParser.parse(line: line)
        #expect(event == .chunk(StreamChunk(deltaReasoning: "先分析")))
    }

    @Test("解析结束原因")
    func parsesFinishReason() {
        let line = #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        let event = SSEParser.parse(line: line)
        #expect(event == .chunk(StreamChunk(finishReason: "stop")))
    }

    @Test("识别 [DONE] 结束标记")
    func detectsDoneMarker() {
        #expect(SSEParser.parse(line: "data: [DONE]") == .done)
    }

    @Test("忽略空行与非 data 行")
    func ignoresBlankAndCommentLines() {
        #expect(SSEParser.parse(line: "") == nil)
        #expect(SSEParser.parse(line: ": keep-alive") == nil)
        #expect(SSEParser.parse(line: "event: message") == nil)
        #expect(SSEParser.parse(line: "data:") == nil)
    }

    @Test("忽略非法 JSON")
    func ignoresMalformedPayload() {
        #expect(SSEParser.parse(line: "data: {not-json}") == nil)
        #expect(SSEParser.parse(line: #"data: {"choices":[]}"#) == nil)
    }

    @Test("容忍行首空白与 data: 后多余空格")
    func toleratesWhitespace() {
        let line = #"  data:  {"choices":[{"delta":{"content":"a"}}]}"#
        #expect(SSEParser.parse(line: line) == .chunk(StreamChunk(deltaContent: "a")))
    }
}

// MARK: - 默认标题

struct DefaultTitleTests {

    @Test("取首条消息前 16 个字符")
    func truncatesLongText() {
        let text = "请帮我写一个归并排序的 Swift 实现，要求支持泛型"
        #expect(ChatStore.defaultTitle(from: text) == String(text.prefix(16)))
    }

    @Test("换行折叠为空格，空文本回退默认标题")
    func handlesNewlinesAndEmptyText() {
        #expect(ChatStore.defaultTitle(from: "第一行\n第二行") == "第一行 第二行")
        #expect(ChatStore.defaultTitle(from: "   \n  ") == "新对话")
    }
}

// MARK: - 时间分组

struct DateGroupingTests {

    @Test("今天与昨天")
    func groupsTodayAndYesterday() {
        let calendar = Calendar.current
        #expect(Date.now.conversationSectionTitle == "今天")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        #expect(yesterday.conversationSectionTitle == "昨天")
    }

    @Test("更早的日期按年月分组")
    func groupsOlderDatesByMonth() {
        let calendar = Calendar.current
        let old = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        #expect(old.conversationSectionTitle == "2026年3月")
    }
}

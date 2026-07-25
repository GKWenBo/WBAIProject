import FoundationModels
import Testing
@testable import WBAppleIntelligence

struct TranscriptTrimmerTests {

    /// 造一条 instructions 条目。
    private func instructions(_ text: String) -> Transcript.Entry {
        .instructions(Transcript.Instructions(
            segments: [.text(Transcript.TextSegment(content: text))],
            toolDefinitions: []
        ))
    }

    /// 造一条提问条目。
    private func prompt(_ text: String) -> Transcript.Entry {
        .prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: text))]))
    }

    /// 造一条回答条目。
    private func response(_ text: String) -> Transcript.Entry {
        .response(Transcript.Response(
            assetIDs: [],
            segments: [.text(Transcript.TextSegment(content: text))]
        ))
    }

    /// 取出条目里的文本，便于断言。
    private func texts(_ transcript: Transcript) -> [String] {
        transcript.flatMap { entry -> [String] in
            let segments: [Transcript.Segment] = switch entry {
            case .instructions(let value): value.segments
            case .prompt(let value): value.segments
            case .response(let value): value.segments
            case .toolCalls, .toolOutput: []
            }
            return segments.compactMap { segment in
                if case .text(let text) = segment { return text.content }
                return nil
            }
        }
    }

    @Test("保留首条 instructions 与最近若干条对话")
    func keepsInstructionsAndRecentEntries() {
        let transcript = Transcript(entries: [
            instructions("系统提示"),
            prompt("问题一"), response("回答一"),
            prompt("问题二"), response("回答二"),
            prompt("问题三"), response("回答三")
        ])

        let trimmed = TranscriptTrimmer.trim(transcript, keepingRecentEntries: 4)

        #expect(texts(trimmed) == ["系统提示", "问题二", "回答二", "问题三", "回答三"])
    }

    @Test("条目数不足时原样保留，不会补空条目")
    func keepsAllWhenFewerThanLimit() {
        let transcript = Transcript(entries: [
            instructions("系统提示"),
            prompt("问题一"), response("回答一")
        ])

        let trimmed = TranscriptTrimmer.trim(transcript, keepingRecentEntries: 10)

        #expect(texts(trimmed) == ["系统提示", "问题一", "回答一"])
    }

    @Test("没有 instructions 时只保留最近条目")
    func worksWithoutInstructions() {
        let transcript = Transcript(entries: [
            prompt("问题一"), response("回答一"),
            prompt("问题二"), response("回答二")
        ])

        let trimmed = TranscriptTrimmer.trim(transcript, keepingRecentEntries: 2)

        #expect(texts(trimmed) == ["问题二", "回答二"])
    }

    @Test("只有第一条 instructions 被当作系统提示，后续同类条目按普通条目处理")
    func onlyFirstInstructionsIsPinned() {
        let transcript = Transcript(entries: [
            instructions("系统提示一"),
            prompt("问题一"),
            instructions("系统提示二"),
            prompt("问题二")
        ])

        let trimmed = TranscriptTrimmer.trim(transcript, keepingRecentEntries: 1)

        #expect(texts(trimmed) == ["系统提示一", "问题二"])
    }

    @Test("保留条数为负时按 0 处理，不会崩溃")
    func negativeCountIsClamped() {
        let transcript = Transcript(entries: [
            instructions("系统提示"),
            prompt("问题一")
        ])

        let trimmed = TranscriptTrimmer.trim(transcript, keepingRecentEntries: -3)

        #expect(texts(trimmed) == ["系统提示"])
    }

    @Test("空 Transcript 裁剪后仍为空")
    func emptyTranscript() {
        let trimmed = TranscriptTrimmer.trim(Transcript(), keepingRecentEntries: 4)
        #expect(trimmed.isEmpty)
    }
}

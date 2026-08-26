import Foundation
import Testing
@testable import WBChatApp_UIKit

/// 可脚本化的转写替身，用来验证消费方逻辑
final class StubTranscriber: SpeechTranscribing {
    var authorized = true
    var events: [SpeechEvent] = []
    var error: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func requestAuthorization() async -> Bool { authorized }

    func start() throws -> AsyncThrowingStream<SpeechEvent, Error> {
        startCount += 1
        if let error { throw error }
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func stop() { stopCount += 1 }
}

@Suite("语音转写")
struct SpeechTranscriberTests {

    @Test("未授权时 requestAuthorization 返回假")
    func unauthorized() async {
        let stub = StubTranscriber()
        stub.authorized = false
        #expect(await stub.requestAuthorization() == false)
    }

    @Test("按序吐出中间结果与最终结果")
    func emitsPartialThenFinal() async throws {
        let stub = StubTranscriber()
        stub.events = [.partial("你"), .partial("你好"), .final("你好世界")]
        var received: [SpeechEvent] = []
        for try await event in try stub.start() { received.append(event) }
        #expect(received == [.partial("你"), .partial("你好"), .final("你好世界")])
    }

    @Test("音量事件独立于文本事件")
    func levelEvents() async throws {
        let stub = StubTranscriber()
        stub.events = [.level(0.3), .partial("嗯"), .level(0.7)]
        var levels: [Float] = []
        for try await event in try stub.start() {
            if case .level(let value) = event { levels.append(value) }
        }
        #expect(levels == [0.3, 0.7])
    }

    @Test("start 抛错被调用方接住")
    func startThrows() {
        let stub = StubTranscriber()
        stub.error = SpeechError.recognizerUnavailable
        #expect(throws: SpeechError.recognizerUnavailable) {
            _ = try stub.start()
        }
    }

    @Test("stop 被调用次数可追踪")
    func stopIsTracked() {
        let stub = StubTranscriber()
        stub.stop()
        stub.stop()
        #expect(stub.stopCount == 2)
    }

    @Test("真实实现遵循协议且可构造")
    func systemImplementationConforms() {
        let transcriber: SpeechTranscribing = SystemSpeechTranscriber()
        #expect(transcriber is SystemSpeechTranscriber)
    }
}

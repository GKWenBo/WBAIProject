import UIKit
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

    /// 为 true 时，`start()` 把 `events` 吐完后**不会自动 finish**，
    /// 要等测试显式调用 `finishStream()` / `finishStream(throwing:)` 流才会真正收尾。
    /// 用来复现 Task 19 Critical 1 描述的竞态：用户已经点了「完成/取消」，
    /// 但 `for try await` 循环那头的流还没走到终点。
    var manualFinish = false
    private var continuation: AsyncThrowingStream<SpeechEvent, Error>.Continuation?

    func requestAuthorization() async -> Bool { authorized }

    func start() throws -> AsyncThrowingStream<SpeechEvent, Error> {
        startCount += 1
        if let error { throw error }
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            if manualFinish {
                self.continuation = continuation
            } else {
                continuation.finish()
            }
        }
    }

    func stop() { stopCount += 1 }

    /// 手动触发流的自然收尾（模拟识别器自己给出终态、`for try await` 正常跑完）
    func finishStream() {
        continuation?.finish()
        continuation = nil
    }

    /// 手动触发流以错误收尾（模拟 `transcriber.stop()` 引发的收尾异常）
    func finishStream(throwing error: Error) {
        continuation?.finish(throwing: error)
        continuation = nil
    }
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

/// Task 19 状态机测试：覆盖 `ChatViewController.startVoiceInput` / `finishVoiceInput`
/// 这两个 Critical 之前完全没有单测盯着的状态机本身，而不是只测 `StubTranscriber` 自己的契约。
@Suite("语音输入状态机")
@MainActor
struct ChatViewControllerVoiceInputTests {

    private func make(transcriber: StubTranscriber) throws -> ChatViewController {
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek,
                                                             model: "deepseek-chat")
        let viewModel = ChatViewModel(conversationID: conversation.id,
                                      repository: repository,
                                      providerFactory: { MockProvider() },
                                      requestConfigProvider: { (model: "deepseek-chat", systemPrompt: nil) },
                                      throttle: ManualThrottle())
        let vc = ChatViewController(viewModel: viewModel,
                                    renderer: AttributedRenderer(),
                                    cache: AttributedCache(),
                                    pool: BlockViewPool(),
                                    transcriber: transcriber)
        _ = vc.view // 触发 viewDidLoad，接上 inputBar.onMicTap
        return vc
    }

    /// 纯靠 `Task.yield()` 让出主线程给 `startVoiceInput` 里那个 MainActor Task，
    /// 等到 `recordingOverlay` 出现——也就是等 `requestAuthorization()` 的 await 走完。
    /// 不用挂钟：跟仓库里 `GatedProvider` 用的是同一套「协作式让出」手法。
    private func waitUntilOverlayPresented(_ vc: ChatViewController,
                                           timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while vc.recordingOverlay == nil && Date() < deadline {
            await Task.yield()
        }
    }

    /// `RecordingOverlayView` 明确在「不要动」名单里，不能往里加测试专用的
    /// getter，所以从视图树里找那个唯一的 `UILabel`（`textLabel`）来读它当前
    /// 显示的文字——只是读，不改它的实现。用来确认「已经吐给 `setText` 的
    /// 内容」真的被消费端处理完了，而不是靠猜 yield 次数。
    private func currentOverlayText(_ vc: ChatViewController) -> String? {
        vc.recordingOverlay?.subviews.compactMap { $0 as? UILabel }.first?.text
    }

    private func waitUntilOverlayShows(_ text: String, in vc: ChatViewController,
                                       timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while currentOverlayText(vc) != text && Date() < deadline {
            await Task.yield()
        }
    }

    // MARK: - Critical 1：完成后只写一次

    @Test("点完成后流自然收尾，文字只写入一次")
    func confirmWritesTextExactlyOnce() async throws {
        let stub = StubTranscriber()
        stub.events = [.partial("你"), .final("你好")]
        stub.manualFinish = true
        let vc = try make(transcriber: stub)

        vc.inputBar.onMicTap?()
        await waitUntilOverlayPresented(vc)
        #expect(vc.recordingOverlay != nil)
        // 等最终结果真的被消费、写进浮层文字，再模拟用户点「完成」——
        // 此时流本身还没走到终点（manualFinish 卡着，for-await 还在等下一个事件）
        await waitUntilOverlayShows("你好", in: vc)

        vc.recordingOverlay?.onConfirm?()
        #expect(vc.inputBar.text == "你好")

        // 流才真正自然收尾——Critical 1 没修的话，这里会把「你好」再拼一次，
        // 变成「你好你好」
        stub.finishStream()
        await vc.speechTask?.value
        #expect(vc.inputBar.text == "你好")
    }

    // MARK: - Critical 1：取消后输入框保持为空（规格要求）

    @Test("点取消后流自然收尾，输入框保持为空")
    func cancelKeepsInputBarEmpty() async throws {
        let stub = StubTranscriber()
        stub.events = [.partial("你"), .final("你好")]
        stub.manualFinish = true
        let vc = try make(transcriber: stub)

        vc.inputBar.onMicTap?()
        await waitUntilOverlayPresented(vc)
        await waitUntilOverlayShows("你好", in: vc)

        vc.recordingOverlay?.onCancel?()
        #expect(vc.inputBar.text.isEmpty)

        // 流才真正自然收尾——如果自然收尾分支不做幂等判断，会无条件当成
        // 「确认」，把已经取消的这段文字写进输入框，直接违反规格
        stub.finishStream()
        await vc.speechTask?.value
        #expect(vc.inputBar.text.isEmpty)
    }

    // MARK: - 回归：全程没点按钮，识别器自己给终态时仍要正常写入一次

    @Test("全程未点按钮、流自然结束时仍写入一次")
    func naturalFinishWithoutAnyTapStillWritesOnce() async throws {
        let stub = StubTranscriber()
        stub.events = [.partial("你"), .final("你好")]
        // manualFinish 保持默认 false：start() 吐完事件直接 finish，
        // 模拟识别器自己给出终态、用户全程没碰「完成/取消」按钮
        let vc = try make(transcriber: stub)

        vc.inputBar.onMicTap?()
        await waitUntilOverlayPresented(vc)
        await vc.speechTask?.value

        #expect(vc.inputBar.text == "你好")
        #expect(vc.recordingOverlay == nil)
    }

    // MARK: - Critical 2：双击麦克风不能重入

    @Test("连续两次 startVoiceInput，transcriber.start() 只被调用一次")
    func doubleMicTapDoesNotReenter() async throws {
        let stub = StubTranscriber()
        stub.manualFinish = true // 卡住流，模拟"还在识别中"的窗口
        let vc = try make(transcriber: stub)

        vc.inputBar.onMicTap?()
        vc.inputBar.onMicTap?() // 紧跟着第二次点击，模拟双击
        await waitUntilOverlayPresented(vc)

        #expect(stub.startCount == 1)

        // 收尾，避免测试留下悬挂的 Task
        vc.recordingOverlay?.onCancel?()
        stub.finishStream()
        await vc.speechTask?.value
    }
}

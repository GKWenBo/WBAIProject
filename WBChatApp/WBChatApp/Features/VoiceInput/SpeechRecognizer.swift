//
//  SpeechRecognizer.swift
//  WBChatApp
//

import AVFoundation
import Observation
import Speech

/// 语音转文字：AVAudioEngine 采集 + SFSpeechRecognizer 实时中文识别，
/// 同时输出 RMS 音量电平序列驱动录音波形动画。
@Observable
final class SpeechRecognizer {

    /// 实时识别结果（partial results 持续更新）
    private(set) var transcript = ""
    private(set) var isRecording = false
    /// 最近的音量电平序列（0~1），供波形视图消费
    private(set) var levels: [Float] = Array(repeating: 0, count: SpeechRecognizer.levelCount)
    var errorMessage: String?

    static let levelCount = 28

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN")) ?? SFSpeechRecognizer()

    // MARK: - Control

    func start() async {
        guard !isRecording else { return }
        transcript = ""
        errorMessage = nil
        levels = Array(repeating: 0, count: Self.levelCount)

        guard await requestPermissions() else {
            errorMessage = "需要麦克风与语音识别权限，请在系统设置中开启"
            return
        }
        // 权限弹窗期间用户可能已松手
        guard recognitionTask == nil || !audioEngine.isRunning else { return }

        do {
            try startEngine()
            isRecording = true
        } catch {
            errorMessage = "录音启动失败：\(error.localizedDescription)"
            teardown()
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        // endAudio 后让识别任务自然结束，最终结果仍会通过回调更新 transcript
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        levels = Array(repeating: 0, count: Self.levelCount)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Private

    private func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private func startEngine() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor [weak self] in
                self?.transcript = text
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.level(from: buffer)
            Task { @MainActor [weak self] in
                self?.pushLevel(level)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func pushLevel(_ level: Float) {
        guard isRecording else { return }
        levels.removeFirst()
        levels.append(level)
    }

    private func teardown() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    /// 计算缓冲区 RMS 并按分贝归一化到 0~1
    private nonisolated static func level(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = channelData[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        let decibels = 20 * log10(max(rms, .leastNonzeroMagnitude))
        let minDecibels: Float = -50
        return max(0, min(1, (decibels - minDecibels) / -minDecibels))
    }
}

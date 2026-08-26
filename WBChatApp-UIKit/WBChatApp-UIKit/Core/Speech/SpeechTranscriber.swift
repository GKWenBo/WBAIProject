import Foundation
import Speech
import AVFoundation

enum SpeechEvent: Equatable {
    case partial(String)
    case final(String)
    /// 归一化到 0…1 的音量，用来驱动波形
    case level(Float)
}

enum SpeechError: Error, Equatable {
    case notAuthorized
    case recognizerUnavailable
    case audioEngineFailed
}

protocol SpeechTranscribing: AnyObject {
    func requestAuthorization() async -> Bool
    func start() throws -> AsyncThrowingStream<SpeechEvent, Error>
    func stop()
}

/// `SFSpeechRecognizer` + `AVAudioEngine` 实现。
///
/// 同一路 PCM 分两用：一路喂识别请求，一路算 RMS 驱动波形，
/// 避免开两个 tap 抢音频硬件。
final class SystemSpeechTranscriber: SpeechTranscribing {

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// 麦克风与语音识别是两套权限，缺一不可
    func requestAuthorization() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else { return false }

        // 注意：AVAudioApplication.requestRecordPermission 是 iOS 17+，
        // 本项目最低 iOS 16，必须走 AVAudioSession 上的这个方法
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() throws -> AsyncThrowingStream<SpeechEvent, Error> {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 端上识别不走网络、延迟更低；机型不支持时自动回落在线
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        return AsyncThrowingStream { continuation in
            task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    continuation.yield(result.isFinal ? .final(text) : .partial(text))
                    if result.isFinal { continuation.finish() }
                }
                if let error {
                    continuation.finish(throwing: error)
                }
            }

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
                continuation.yield(.level(Self.normalizedLevel(of: buffer)))
            }

            audioEngine.prepare()
            do {
                try audioEngine.start()
            } catch {
                continuation.finish(throwing: SpeechError.audioEngineFailed)
            }

            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// RMS 转成 0…1。取 -50dB 作为静音底，日常说话大约落在 0.3–0.9。
    private static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<count {
            sum += channel[index] * channel[index]
        }
        let rms = sqrt(sum / Float(count))
        let decibels = 20 * log10(max(rms, .leastNormalMagnitude))
        let floor: Float = -50
        return max(0, min(1, (decibels - floor) / -floor))
    }
}

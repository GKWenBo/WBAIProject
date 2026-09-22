import Foundation

protocol GenerationClock: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

struct SystemGenerationClock: GenerationClock {
    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

@MainActor
protocol BackgroundExecution: AnyObject {
    func begin(expiration: @escaping @MainActor () -> Void) -> Bool
    func end()
}

import Foundation
import Observation

@Observable
@MainActor
final class PlaybackMonitor {
    private(set) var isPlaying = false
    private(set) var isLooping = false
    private(set) var duration: TimeInterval = 0
    private(set) var currentTime: TimeInterval = 0

    private var startedAt: Date?
    private var timer: Timer?

    var progress: Double {
        guard duration > 0 else { return 0 }
        if isLooping {
            return (currentTime.truncatingRemainder(dividingBy: duration)) / duration
        }
        return min(1, currentTime / duration)
    }

    var currentTimeText: String { format(currentTimeDisplay) }
    var durationText: String { format(duration) }

    private var currentTimeDisplay: TimeInterval {
        guard duration > 0 else { return currentTime }
        if isLooping {
            return currentTime.truncatingRemainder(dividingBy: duration)
        }
        return min(currentTime, duration)
    }

    func start(duration: TimeInterval, looping: Bool) {
        stopMonitoring(reset: false)
        self.duration = max(0.01, duration)
        self.isLooping = looping
        self.isPlaying = true
        self.startedAt = Date()
        self.currentTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stopMonitoring(reset: Bool = true) {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        startedAt = nil
        if reset {
            currentTime = 0
        }
    }

    private func tick() {
        guard let startedAt else { return }
        currentTime = Date().timeIntervalSince(startedAt)
        if !isLooping, currentTime >= duration {
            currentTime = duration
            stopMonitoring(reset: false)
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let total = max(0, Int(t.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

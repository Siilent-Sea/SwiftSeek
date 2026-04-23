import Foundation
import Dispatch

/// Coalesces a stream of path events into debounced, de-duplicated batches.
///
/// Every `enqueue` call arms (or re-arms) a trailing timer. When the timer
/// fires, the currently-pending set of paths is drained and handed to
/// `onBatch` exactly once. Extra events arriving during handling are
/// collected into the next batch.
public final class EventQueue: @unchecked Sendable {
    public struct Options {
        public var debounce: TimeInterval
        public var label: String

        public init(debounce: TimeInterval = 0.2,
                    label: String = "swiftseek.eventqueue") {
            self.debounce = debounce
            self.label = label
        }
    }

    private let options: Options
    private let serial: DispatchQueue
    private let timerQueue: DispatchQueue
    private let onBatch: (Set<String>) -> Void

    private var pending: Set<String> = []
    private var timer: DispatchSourceTimer?
    private var stopped: Bool = false
    private var batchCount: Int = 0

    public init(options: Options = .init(),
                onBatch: @escaping (Set<String>) -> Void) {
        self.options = options
        self.serial = DispatchQueue(label: options.label, qos: .utility)
        self.timerQueue = DispatchQueue(label: options.label + ".timer", qos: .utility)
        self.onBatch = onBatch
    }

    deinit {
        timer?.cancel()
    }

    public func enqueue(_ path: String) {
        serial.async {
            guard !self.stopped else { return }
            self.pending.insert(path)
            self.armTimerLocked()
        }
    }

    public func enqueue(_ paths: [String]) {
        serial.async {
            guard !self.stopped else { return }
            for p in paths { self.pending.insert(p) }
            if !self.pending.isEmpty {
                self.armTimerLocked()
            }
        }
    }

    /// Drain any pending events immediately on the caller's behalf. Useful
    /// for deterministic shutdown and for tests that need to force-flush.
    public func flushNow() {
        serial.sync {
            self.timer?.cancel()
            self.timer = nil
            self.drainLocked()
        }
    }

    /// Stop accepting new events. Any pending batch is drained first.
    public func stop() {
        serial.sync {
            self.stopped = true
            self.timer?.cancel()
            self.timer = nil
            self.drainLocked()
        }
    }

    /// Total number of batches emitted so far. Intended for tests /
    /// observability — callers may inspect this to verify debounce merging.
    public var emittedBatches: Int {
        serial.sync { batchCount }
    }

    // MARK: - private (serial queue context)

    private func armTimerLocked() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: timerQueue)
        let deadline: DispatchTime = .now() + options.debounce
        t.schedule(deadline: deadline)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.serial.async { self.drainLocked() }
        }
        timer = t
        t.resume()
    }

    private func drainLocked() {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        batchCount += 1
        onBatch(batch)
    }
}

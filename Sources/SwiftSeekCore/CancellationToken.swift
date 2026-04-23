import Foundation

public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false

    public init(cancelled: Bool = false) {
        self._cancelled = cancelled
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }

    public func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
    }
}

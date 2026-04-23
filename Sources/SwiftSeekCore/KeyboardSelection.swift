import Foundation

/// Pure state machine for the search window's keyboard selection.
///
/// Lives in `SwiftSeekCore` (not the AppKit layer) so it is testable without
/// spinning up `NSApplication`. The window controller consults `currentIndex`
/// when drawing and calls `moveUp()` / `moveDown()` from arrow-key handlers;
/// `setResultCount(_:)` is called whenever the results array length changes
/// so the selection re-clamps instead of pointing past the end.
public struct KeyboardSelection: Equatable {
    public private(set) var resultCount: Int
    public private(set) var currentIndex: Int
    public var wrap: Bool

    public init(resultCount: Int = 0, wrap: Bool = true) {
        self.resultCount = max(0, resultCount)
        self.currentIndex = self.resultCount > 0 ? 0 : -1
        self.wrap = wrap
    }

    public var isEmpty: Bool { resultCount == 0 }

    public mutating func setResultCount(_ newCount: Int) {
        let clamped = max(0, newCount)
        resultCount = clamped
        if clamped == 0 {
            currentIndex = -1
            return
        }
        if currentIndex < 0 {
            currentIndex = 0
        } else if currentIndex >= clamped {
            currentIndex = clamped - 1
        }
    }

    public mutating func moveUp() {
        guard resultCount > 0 else { return }
        if currentIndex <= 0 {
            currentIndex = wrap ? resultCount - 1 : 0
        } else {
            currentIndex -= 1
        }
    }

    public mutating func moveDown() {
        guard resultCount > 0 else { return }
        if currentIndex >= resultCount - 1 {
            currentIndex = wrap ? 0 : resultCount - 1
        } else {
            currentIndex += 1
        }
    }

    public mutating func moveToFirst() {
        currentIndex = resultCount > 0 ? 0 : -1
    }

    public mutating func moveToLast() {
        currentIndex = resultCount > 0 ? resultCount - 1 : -1
    }

    public mutating func setIndex(_ i: Int) {
        guard resultCount > 0 else { currentIndex = -1; return }
        currentIndex = max(0, min(resultCount - 1, i))
    }
}

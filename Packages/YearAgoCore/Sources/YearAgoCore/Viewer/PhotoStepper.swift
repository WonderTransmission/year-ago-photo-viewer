/// Position within one year's photos. See proposal 4.3.
///
/// Positions `0..<count` are photos. Position `count` is the end card.
/// Stepping never leaves the year: it stops at the first photo and at the
/// end card.
public struct PhotoStepper: Equatable, Sendable {
    public private(set) var count: Int
    public private(set) var position: Int

    public init(count: Int) {
        self.count = max(count, 0)
        self.position = 0
    }

    /// Index of the photo on screen, or nil on the end card or when empty.
    public var currentIndex: Int? { position < count ? position : nil }

    /// True when the year has no photos.
    public var isEmpty: Bool { count == 0 }

    /// True when the end card is showing.
    public var isAtEnd: Bool { count > 0 && position == count }

    public var canGoBack: Bool { position > 0 }
    public var canGoForward: Bool { position < count }

    public mutating func next() {
        if canGoForward { position += 1 }
    }

    public mutating func previous() {
        if canGoBack { position -= 1 }
    }

    /// Moves to the end card. Does nothing when empty.
    public mutating func moveToEnd() {
        if count > 0 { position = count }
    }

    /// Jumps to a photo. Out-of-range indexes are ignored.
    public mutating func jump(to index: Int) {
        if (0..<count).contains(index) { position = index }
    }
}

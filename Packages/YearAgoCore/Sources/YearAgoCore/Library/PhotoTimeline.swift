/// All dated photos, sorted by date, with fast range lookups.
public struct PhotoTimeline: Sendable {
    /// Sorted by date, then by relative path.
    public let photos: [PhotoItem]

    public init(_ photos: [PhotoItem]) {
        self.photos = photos.sorted { lhs, rhs in
            lhs.date != rhs.date ? lhs.date < rhs.date : lhs.relativePath < rhs.relativePath
        }
    }

    /// Trusts that `photos` is already sorted by date, then relative path.
    public init(presorted photos: [PhotoItem]) {
        self.photos = photos
    }

    public static let empty = PhotoTimeline([])

    /// The date of the oldest photo, if any.
    public var oldest: LocalDateTime? { photos.first?.date }

    /// Photos whose date falls in `range`, in date order.
    public func photos(in range: ClosedRange<LocalDateTime>) -> [PhotoItem] {
        Array(photos[indices(in: range)])
    }

    /// How many photos fall in `range`, without copying them.
    public func count(in range: ClosedRange<LocalDateTime>) -> Int {
        indices(in: range).count
    }

    private func indices(in range: ClosedRange<LocalDateTime>) -> Range<Int> {
        let start = firstIndex { $0.date >= range.lowerBound }
        let end = firstIndex { $0.date > range.upperBound }
        return start..<max(start, end)
    }

    /// Binary search for the first index where `predicate` becomes true.
    /// `predicate` must be false then true across the sorted array.
    private func firstIndex(where predicate: (PhotoItem) -> Bool) -> Int {
        var low = 0
        var high = photos.count
        while low < high {
            let mid = (low + high) / 2
            if predicate(photos[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }
}

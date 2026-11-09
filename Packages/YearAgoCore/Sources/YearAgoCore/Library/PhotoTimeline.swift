/// All dated photos, sorted by date, with fast range lookups.
public struct PhotoTimeline: Sendable {
    /// Sorted by date, then by relative path.
    public let photos: [PhotoItem]

    public init(_ photos: [PhotoItem]) {
        self.photos = photos.sorted { lhs, rhs in
            lhs.date != rhs.date ? lhs.date < rhs.date : lhs.relativePath < rhs.relativePath
        }
    }

    public static let empty = PhotoTimeline([])

    /// The date of the oldest photo, if any.
    public var oldest: LocalDateTime? { photos.first?.date }

    /// Photos whose date falls in `range`, in date order.
    public func photos(in range: ClosedRange<LocalDateTime>) -> [PhotoItem] {
        let start = firstIndex { $0.date >= range.lowerBound }
        let end = firstIndex { $0.date > range.upperBound }
        return Array(photos[start..<end])
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

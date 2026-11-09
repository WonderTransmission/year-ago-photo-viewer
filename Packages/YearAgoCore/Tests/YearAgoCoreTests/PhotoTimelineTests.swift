import Foundation
import Testing
@testable import YearAgoCore

@Suite struct PhotoTimelineTests {
    private func item(_ path: String, _ date: LocalDateTime) -> PhotoItem {
        PhotoItem(url: URL(fileURLWithPath: "/photos/\(path)"), relativePath: path, kind: .image, date: date)
    }

    @Test func sortsByDateThenPath() {
        let timeline = PhotoTimeline([
            item("c.jpg", local(2025, 11, 3)),
            item("b.jpg", local(2025, 11, 1)),
            item("a.jpg", local(2025, 11, 3)),
        ])
        #expect(timeline.photos.map(\.relativePath) == ["b.jpg", "a.jpg", "c.jpg"])
        #expect(timeline.oldest == local(2025, 11, 1))
    }

    @Test func rangeIsInclusiveAtBothEnds() {
        let timeline = PhotoTimeline([
            item("before.jpg", local(2025, 10, 31, 23, 59, 59)),
            item("first.jpg", local(2025, 11, 1)),
            item("middle.jpg", local(2025, 11, 5, 12)),
            item("last.jpg", local(2025, 11, 8, 23, 59, 59)),
            item("after.jpg", local(2025, 11, 9)),
        ])
        let range = local(2025, 11, 1)...local(2025, 11, 8, 23, 59, 59)
        #expect(timeline.photos(in: range).map(\.relativePath) == ["first.jpg", "middle.jpg", "last.jpg"])
    }

    @Test func emptyCases() {
        let range = local(2025, 11, 1)...local(2025, 11, 8)
        #expect(PhotoTimeline.empty.photos(in: range).isEmpty)
        #expect(PhotoTimeline.empty.oldest == nil)
        let timeline = PhotoTimeline([item("x.jpg", local(2020, 1, 1))])
        #expect(timeline.photos(in: range).isEmpty)
    }
}

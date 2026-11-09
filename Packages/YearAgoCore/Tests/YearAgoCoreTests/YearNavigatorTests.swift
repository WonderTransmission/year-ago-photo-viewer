import Foundation
import Testing
@testable import YearAgoCore

@Suite struct YearNavigatorTests {
    // N:            1  2  3  4  5
    let counts =    [0, 4, 0, 0, 2]

    @Test func showingEmptyYearsOffersEveryYear() {
        let nav = YearNavigator(photoCounts: counts, showEmptyYears: true)
        #expect(nav.years == [1, 2, 3, 4, 5])
        #expect(nav.initialYear == 1)
        #expect(nav.next(after: 1) == 2)
        #expect(nav.next(after: 2) == 3)   // lands on empty years
        #expect(nav.next(after: 5) == nil)
        #expect(nav.previous(before: 1) == nil)
        #expect(nav.previous(before: 4) == 3)
    }

    @Test func hidingEmptyYearsSkipsThem() {
        let nav = YearNavigator(photoCounts: counts, showEmptyYears: false)
        #expect(nav.years == [2, 5])
        #expect(nav.initialYear == 2)      // N = 1 is empty: open at the nearest year with photos
        #expect(nav.next(after: 2) == 5)
        #expect(nav.previous(before: 5) == 2)
        #expect(nav.previous(before: 2) == nil)
    }

    @Test func nearestYear() {
        let nav = YearNavigator(photoCounts: counts, showEmptyYears: false)
        #expect(nav.nearest(to: 2) == 2)
        #expect(nav.nearest(to: 1) == 2)
        #expect(nav.nearest(to: 4) == 5)
        #expect(nav.nearest(to: 3) == 2)   // 2 is one away, 5 is two away
        #expect(nav.nearest(to: 9) == 5)
    }

    @Test func tieGoesToMoreRecentYear() {
        let nav = YearNavigator(photoCounts: [1, 0, 1], showEmptyYears: false)
        #expect(nav.nearest(to: 2) == 1)
    }

    @Test(arguments: [true, false])
    func noPhotosAtAllStillOffersOneYear(showEmpty: Bool) {
        let none = YearNavigator(photoCounts: [], showEmptyYears: showEmpty)
        #expect(none.years == [1])
        #expect(!none.hasAnyPhotos)
        #expect(none.next(after: 1) == nil)

        let allEmpty = YearNavigator(photoCounts: [0, 0, 0], showEmptyYears: showEmpty)
        #expect(allEmpty.years == (showEmpty ? [1, 2, 3] : [1]))
        #expect(!allEmpty.hasAnyPhotos)
    }

    @Test func countOutsideRangeIsZero() {
        let nav = YearNavigator(photoCounts: counts, showEmptyYears: true)
        #expect(nav.count(yearsAgo: 2) == 4)
        #expect(nav.count(yearsAgo: 0) == 0)
        #expect(nav.count(yearsAgo: 6) == 0)
    }

    @Test func buildCountsEachYearsWindow() {
        func item(_ date: LocalDateTime) -> PhotoItem {
            PhotoItem(url: URL(fileURLWithPath: "/p/\(date.seconds).jpg"),
                      relativePath: "\(date.seconds).jpg", kind: .image, date: date)
        }
        let timeline = PhotoTimeline([
            item(local(2025, 11, 3)),            // N = 1
            item(local(2025, 11, 8, 23)),        // N = 1
            item(local(2023, 11, 1)),            // N = 3, first day of the window
            item(local(2023, 10, 20)),           // N = 3 only with a 3-week window
            item(local(2021, 6, 1)),             // oldest: N = 5, outside every window
        ])
        let today = local(2026, 11, 8, 10)

        let oneWeek = YearNavigator.build(timeline: timeline, today: today, weeks: 1, showEmptyYears: true)
        #expect(oneWeek.photoCounts == [2, 0, 1, 0, 0])

        let threeWeeks = YearNavigator.build(timeline: timeline, today: today, weeks: 3, showEmptyYears: false)
        #expect(threeWeeks.photoCounts == [2, 0, 2, 0, 0])
        #expect(threeWeeks.years == [1, 3])
    }

    @Test func buildWithEmptyTimeline() {
        let nav = YearNavigator.build(timeline: .empty, today: local(2026, 11, 8), weeks: 1, showEmptyYears: true)
        #expect(nav.maxYearsAgo == 0)
        #expect(nav.years == [1])
    }
}

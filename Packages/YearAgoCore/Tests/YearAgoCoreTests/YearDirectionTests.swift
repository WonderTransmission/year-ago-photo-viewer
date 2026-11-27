import Foundation
import Testing
@testable import YearAgoCore

/// Oldest-first navigation plan, step 4.1.
@Suite struct YearDirectionTests {
    // N:              1  2  3  4  5  6
    private let counts = [0, 4, 0, 1, 2, 0]

    @Test func earlierAndLaterAreCalendarMoves() {
        let nav = YearNavigator(photoCounts: counts, showEmptyYears: false)
        #expect(nav.years == [2, 4, 5])
        #expect(nav.earlier(than: 2) == 4)   // 4 years ago is an earlier calendar year
        #expect(nav.later(than: 4) == 2)
        #expect(nav.earlier(than: 5) == nil)
        #expect(nav.later(than: 2) == nil)
    }

    @Test func forwardAndBackFollowTheDirection() {
        let nav = YearNavigator(photoCounts: counts, showEmptyYears: false)
        #expect(nav.forward(from: 4, direction: .newestFirst) == 5)
        #expect(nav.back(from: 4, direction: .newestFirst) == 2)
        #expect(nav.forward(from: 4, direction: .oldestFirst) == 2)
        #expect(nav.back(from: 4, direction: .oldestFirst) == 5)
        #expect(nav.forward(from: 2, direction: .oldestFirst) == nil)
        #expect(nav.back(from: 5, direction: .oldestFirst) == nil)
    }

    @Test func arrowMovesSkipEmptyYears() {
        let nav = YearNavigator(photoCounts: counts, showEmptyYears: true)
        // N = 3 is empty: forward and back jump over it.
        #expect(nav.forward(from: 2, direction: .newestFirst) == 3)
        #expect(nav.forwardWithPhotos(from: 2, direction: .newestFirst) == 4)
        #expect(nav.backWithPhotos(from: 4, direction: .newestFirst) == 2)
        #expect(nav.forwardWithPhotos(from: 4, direction: .oldestFirst) == 2)
        #expect(nav.backWithPhotos(from: 2, direction: .oldestFirst) == 4)
        #expect(nav.forwardWithPhotos(from: 5, direction: .newestFirst) == nil)  // 6 is empty
        #expect(nav.backWithPhotos(from: 5, direction: .oldestFirst) == nil)
    }

    @Test func endsSkipEmptyYearsEvenWhenShown() {
        let nav = YearNavigator(photoCounts: counts, showEmptyYears: true)
        #expect(nav.years == [1, 2, 3, 4, 5, 6])
        #expect(nav.yearsWithPhotos == [2, 4, 5])
        #expect(nav.newestWithPhotos == 2)
        #expect(nav.oldestWithPhotos == 5)
        #expect(nav.start(direction: .newestFirst) == 2)
        #expect(nav.end(direction: .newestFirst) == 5)
        #expect(nav.start(direction: .oldestFirst) == 5)
        #expect(nav.end(direction: .oldestFirst) == 2)
    }

    @Test func initialYearDependsOnDirection() {
        let shown = YearNavigator(photoCounts: counts, showEmptyYears: true)
        // Newest first is unchanged: with empty years shown, it opens at N = 1.
        #expect(shown.initialYear(direction: .newestFirst) == shown.initialYear)
        #expect(shown.initialYear(direction: .newestFirst) == 1)
        #expect(shown.initialYear(direction: .oldestFirst) == 5)

        let hidden = YearNavigator(photoCounts: counts, showEmptyYears: false)
        #expect(hidden.initialYear(direction: .newestFirst) == 2)
        #expect(hidden.initialYear(direction: .oldestFirst) == 5)
    }

    @Test func orderedFollowsTheDirection() {
        let nav = YearNavigator(photoCounts: counts, showEmptyYears: false)
        #expect(nav.ordered(direction: .newestFirst) == [2, 4, 5])
        #expect(nav.ordered(direction: .oldestFirst) == [5, 4, 2])
    }

    @Test func noPhotosAtAll() {
        let nav = YearNavigator(photoCounts: [0, 0, 0], showEmptyYears: false)
        #expect(nav.yearsWithPhotos.isEmpty)
        #expect(nav.oldestWithPhotos == nil)
        #expect(nav.start(direction: .oldestFirst) == nil)
        #expect(nav.initialYear(direction: .oldestFirst) == 1)
        #expect(nav.forward(from: 1, direction: .oldestFirst) == nil)
        #expect(nav.forward(from: 1, direction: .newestFirst) == nil)

        let empty = YearNavigator(photoCounts: [], showEmptyYears: true)
        #expect(empty.initialYear(direction: .oldestFirst) == 1)
        #expect(empty.ordered(direction: .oldestFirst) == [1])
    }
}

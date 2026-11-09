import Foundation
import Testing
@testable import YearAgoCore

@Suite struct OnThisDayTests {
    private func item(_ date: LocalDateTime) -> PhotoItem {
        PhotoItem(url: URL(fileURLWithPath: "/p/\(date.seconds).jpg"),
                  relativePath: "\(date.seconds).jpg", kind: .image, date: date)
    }

    private let today = local(2026, 11, 8, 12)
    private var timeline: PhotoTimeline {
        PhotoTimeline([
            item(local(2024, 11, 3)),                 // N = 2
            item(local(2022, 11, 5)), item(local(2022, 11, 6)),   // N = 4
            item(local(2020, 6, 1)),                  // oldest, N = 6, outside windows
        ])
    }

    @Test func withEmptyYearsShownStartsAtLastYear() {
        let navigator = YearNavigator.build(timeline: timeline, today: today, weeks: 1, showEmptyYears: true)
        let years = OnThisDay.years(count: 3, timeline: timeline, navigator: navigator, today: today, weeks: 1)
        #expect(years.map(\.yearsAgo) == [1, 2, 3])
        #expect(years.map(\.photos.count) == [0, 1, 0])
    }

    @Test func withEmptyYearsHiddenUsesTheNearestYearsWithPhotos() {
        let navigator = YearNavigator.build(timeline: timeline, today: today, weeks: 1, showEmptyYears: false)
        let years = OnThisDay.years(count: 3, timeline: timeline, navigator: navigator, today: today, weeks: 1)
        #expect(years.map(\.yearsAgo) == [2, 4])
        #expect(years.first?.photos.map(\.date) == [local(2024, 11, 3)])
    }

    @Test func noPhotosStillGivesOneYear() {
        let navigator = YearNavigator.build(timeline: .empty, today: today, weeks: 1, showEmptyYears: false)
        let years = OnThisDay.years(count: 3, timeline: .empty, navigator: navigator, today: today, weeks: 1)
        #expect(years.map(\.yearsAgo) == [1])
        #expect(years.first?.photos.isEmpty == true)
    }

    @Test func spreadPicksEvenlyAcrossTheWindow() {
        let photos = (1...10).map { item(local(2025, 11, 1, $0)) }
        let day = OnThisDay(window: DateWindow(yearsAgo: 1, weeks: 1, range: local(2025, 11, 1)...local(2025, 11, 8)),
                            photos: photos)
        #expect(day.spread(limit: 4).map { $0.date.components.hour } == [1, 4, 7, 10])
        #expect(day.spread(limit: 1).count == 1)
        #expect(day.spread(limit: 20).count == 10)
        #expect(day.spread(limit: 0).isEmpty)
    }
}

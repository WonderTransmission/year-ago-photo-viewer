import Foundation
import Testing
@testable import YearAgoCore

@Suite struct LocalDateTimeTests {
    @Test func epochIsZero() {
        #expect(local(1970, 1, 1).seconds == 0)
    }

    @Test func componentsRoundTrip() {
        let value = local(2024, 2, 29, 13, 50, 15)
        let c = value.components
        #expect([c.year, c.month, c.day, c.hour, c.minute, c.second] == [2024, 2, 29, 13, 50, 15])
        #expect(value.description == "2024-02-29 13:50:15")
    }

    @Test(arguments: [
        (2023, 2, 29, 0, 0, 0),   // not a leap year
        (2024, 2, 30, 0, 0, 0),
        (2024, 4, 31, 0, 0, 0),
        (2024, 13, 1, 0, 0, 0),
        (2024, 0, 1, 0, 0, 0),
        (2024, 1, 0, 0, 0, 0),
        (2024, 1, 1, 24, 0, 0),
        (2024, 1, 1, 0, 60, 0),
        (2024, 1, 1, 0, 0, 60),
        (0, 1, 1, 0, 0, 0),
    ])
    func rejectsImpossibleDates(y: Int, mo: Int, d: Int, h: Int, mi: Int, s: Int) {
        #expect(LocalDateTime(year: y, month: mo, day: d, hour: h, minute: mi, second: s) == nil)
    }

    @Test func acceptsLeapDay() {
        #expect(LocalDateTime(year: 2024, month: 2, day: 29) != nil)
        #expect(LocalDateTime(year: 2000, month: 2, day: 29) != nil)
        #expect(LocalDateTime(year: 1900, month: 2, day: 29) == nil)
    }

    @Test func convertsInstantUsingTimeZoneIncludingDST() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        // 2025-07-01 16:00:00 UTC is 12:00 EDT (UTC−4).
        let summer = Date(timeIntervalSince1970: TimeInterval(local(2025, 7, 1, 16).seconds))
        #expect(LocalDateTime(summer, in: newYork) == local(2025, 7, 1, 12))
        // 2025-01-15 17:00:00 UTC is 12:00 EST (UTC−5).
        let winter = Date(timeIntervalSince1970: TimeInterval(local(2025, 1, 15, 17).seconds))
        #expect(LocalDateTime(winter, in: newYork) == local(2025, 1, 15, 12))
    }

    @Test func startAndEndOfDay() {
        let value = local(2025, 11, 8, 14, 32, 5)
        #expect(value.startOfDay == local(2025, 11, 8))
        #expect(value.endOfDay == local(2025, 11, 8, 23, 59, 59))
    }

    @Test func yearArithmeticClampsLeapDay() {
        #expect(local(2024, 2, 29).adding(.year, -1) == local(2023, 2, 28))
        #expect(local(2024, 2, 29).adding(.year, -4) == local(2020, 2, 29))
    }
}

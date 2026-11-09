import Testing
@testable import YearAgoCore

@Suite struct WindowCalculatorTests {
    let calculator = WindowCalculator()

    @Test func proposalExample() {
        // Proposal 4.1: today 8 Nov 2026, N = 1, W = 1 → 1–8 Nov 2025.
        let window = calculator.window(today: local(2026, 11, 8, 15, 30), yearsAgo: 1, weeks: 1)
        #expect(window.range.lowerBound == local(2025, 11, 1))
        #expect(window.range.upperBound == local(2025, 11, 8, 23, 59, 59))
        #expect(window.yearsAgo == 1)
        #expect(window.weeks == 1)
    }

    @Test func timeOfDayDoesNotMatter() {
        let morning = calculator.window(today: local(2026, 11, 8, 0, 0, 1), yearsAgo: 2, weeks: 1)
        let night = calculator.window(today: local(2026, 11, 8, 23, 59, 59), yearsAgo: 2, weeks: 1)
        #expect(morning == night)
    }

    @Test(arguments: 1...6)
    func everyWindowLength(weeks: Int) {
        let window = calculator.window(today: local(2026, 11, 8), yearsAgo: 1, weeks: weeks)
        #expect(window.range.lowerBound == local(2025, 11, 8).adding(.day, -7 * weeks))
        #expect(window.range.upperBound == local(2025, 11, 8, 23, 59, 59))
    }

    @Test func weeksAreClamped() {
        let today = local(2026, 11, 8)
        #expect(calculator.window(today: today, yearsAgo: 1, weeks: 0).weeks == 1)
        #expect(calculator.window(today: today, yearsAgo: 1, weeks: 9).weeks == 6)
    }

    @Test func severalYearsBack() {
        let window = calculator.window(today: local(2026, 11, 8), yearsAgo: 3, weeks: 2)
        #expect(window.range.lowerBound == local(2023, 10, 25))
        #expect(window.range.upperBound == local(2023, 11, 8, 23, 59, 59))
    }

    @Test func crossesYearBoundary() {
        let window = calculator.window(today: local(2026, 1, 3), yearsAgo: 1, weeks: 1)
        #expect(window.range.lowerBound == local(2024, 12, 27))
        #expect(window.range.upperBound == local(2025, 1, 3, 23, 59, 59))
    }

    @Test func leapDayTodayMapsToFeb28() {
        let window = calculator.window(today: local(2028, 2, 29), yearsAgo: 1, weeks: 1)
        #expect(window.range.lowerBound == local(2027, 2, 21))
        #expect(window.range.upperBound == local(2027, 2, 28, 23, 59, 59))
    }

    @Test func leapDayTodayFourYearsBackKeepsFeb29() {
        let window = calculator.window(today: local(2028, 2, 29), yearsAgo: 4, weeks: 1)
        #expect(window.range.upperBound == local(2024, 2, 29, 23, 59, 59))
    }

    @Test func windowSpanningPastLeapDay() {
        // 1 Mar 2025 → anniversary 1 Mar 2024; a week earlier crosses 29 Feb.
        let window = calculator.window(today: local(2025, 3, 1), yearsAgo: 1, weeks: 1)
        #expect(window.range.lowerBound == local(2024, 2, 23))
    }

    @Test func maxYearsAgo() {
        let today = local(2026, 11, 8)
        // Oldest photo June 2019: anniversary 8 Nov 2019 is after it, 8 Nov 2018 is not.
        #expect(calculator.maxYearsAgo(oldest: local(2019, 6, 1), today: today) == 7)
        // Exactly on an anniversary day counts.
        #expect(calculator.maxYearsAgo(oldest: local(2023, 11, 8, 18), today: today) == 3)
        // Newer than last year's anniversary: no past years.
        #expect(calculator.maxYearsAgo(oldest: local(2026, 1, 1), today: today) == 0)
    }
}

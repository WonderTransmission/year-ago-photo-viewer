import Foundation
import Testing
import YearAgoSnapshot

@Suite struct WidgetSnapshotTests {
    private var sample: WidgetSnapshot {
        WidgetSnapshot(
            day: .init(year: 2026, month: 11, day: 8),
            hasSources: true,
            years: [
                .init(yearsAgo: 1, calendarYear: 2025, rangeText: "Nov 1 – 8, 2025", photoCount: 4, photos: [
                    .init(id: "1:a.jpg", imageFile: "aa.jpg", dateText: "Sat, Nov 1"),
                    .init(id: "1:b.jpg", imageFile: "bb.jpg", dateText: "Mon, Nov 3"),
                ]),
                .init(yearsAgo: 2, calendarYear: 2024, rangeText: "Nov 1 – 8, 2024", photoCount: 0, photos: []),
            ])
    }

    @Test func roundTripsThroughAFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try sample.write(to: folder)
        #expect(WidgetSnapshot.read(from: folder) == sample)
        #expect(sample.imageFiles == ["aa.jpg", "bb.jpg"])
    }

    @Test func missingOrCorruptFileReadsAsNil() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(WidgetSnapshot.read(from: folder) == nil)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.appendingPathComponent(WidgetSnapshot.fileName))
        #expect(WidgetSnapshot.read(from: folder) == nil)
    }

    @Test func currentOnlyOnItsOwnDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let sameDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 23)))
        let nextDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 0, minute: 1)))
        #expect(sample.isCurrent(on: sameDay, calendar: calendar))
        #expect(!sample.isCurrent(on: nextDay, calendar: calendar))
    }

    @Test func deepLinksRoundTrip() throws {
        let photo = WidgetDeepLink.url(photoID: "12:Trip 2024/IMG_1.jpg", yearsAgo: 2)
        #expect(photo.scheme == "yearago")
        let parsed = try #require(WidgetDeepLink.parse(photo))
        #expect(parsed.photoID == "12:Trip 2024/IMG_1.jpg")
        #expect(parsed.yearsAgo == 2)

        let year = try #require(WidgetDeepLink.parse(WidgetDeepLink.url(yearsAgo: 3)))
        #expect(year.photoID == nil)
        #expect(year.yearsAgo == 3)
    }

    @Test(arguments: ["https://example.com", "yearago://photo?years=1", "yearago://photo?id=x&years=0", "yearago://other?years=1"])
    func rejectsOtherURLs(text: String) throws {
        #expect(WidgetDeepLink.parse(try #require(URL(string: text))) == nil)
    }

    @Test func noAppGroupInTests() {
        // The test runner has no App Group entitlement.
        #expect(SharedContainer.widgetFolder == nil)
    }
}

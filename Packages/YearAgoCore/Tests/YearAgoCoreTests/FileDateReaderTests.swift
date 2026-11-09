import Foundation
import Testing
@testable import YearAgoCore

@Suite struct FileDateReaderTests {
    @Test func readsModifiedAndCreatedInGivenTimeZone() throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let url = dir.appendingPathComponent("photo.jpg")
        try Data([0xFF]).write(to: url)

        // Absolute instants, written as UTC wall-clock values.
        let created = Date(timeIntervalSince1970: TimeInterval(local(2020, 6, 1, 10).seconds))
        let modified = Date(timeIntervalSince1970: TimeInterval(local(2021, 1, 15, 22, 30).seconds))
        try FileManager.default.setAttributes(
            [.creationDate: created, .modificationDate: modified], ofItemAtPath: url.path)

        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))  // UTC+9, no DST
        let dates = FileDateReader.dates(at: url, timeZone: tokyo)
        #expect(dates.created == local(2020, 6, 1, 19))
        #expect(dates.modified == local(2021, 1, 16, 7, 30))
    }

    @Test func missingFileGivesNoDates() throws {
        let dir = try Fixtures.makeTemporaryDirectory()
        defer { Fixtures.cleanUp(dir) }
        let dates = FileDateReader.dates(at: dir.appendingPathComponent("missing.jpg"))
        #expect(dates == FileDates(modified: nil, created: nil))
    }
}

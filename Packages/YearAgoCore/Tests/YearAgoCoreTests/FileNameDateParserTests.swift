import Testing
@testable import YearAgoCore

@Suite struct FileNameDateParserTests {
    let parser = FileNameDateParser.standard()

    @Test(arguments: [
        // Proposal 4.5 examples.
        ("Screen Shot 2022-03-16 at 1.50.15 PM.png", local(2022, 3, 16, 13, 50, 15)),
        ("Screenshot 2022-03-16 at 13.50.15.png", local(2022, 3, 16, 13, 50, 15)),
        ("IMG_20220316_135015.jpg", local(2022, 3, 16, 13, 50, 15)),
        ("PXL_20220316_135015123.jpg", local(2022, 3, 16, 13, 50, 15)),
        ("2022-03-16 13.50.15.jpg", local(2022, 3, 16, 13, 50, 15)),
        ("20220316_135015.jpg", local(2022, 3, 16, 13, 50, 15)),
        // Variants.
        ("Screen Shot 2022-03-16 at 12.05.00 AM.png", local(2022, 3, 16, 0, 5, 0)),
        ("Screen Shot 2022-03-16 at 12.05.00 PM.png", local(2022, 3, 16, 12, 5, 0)),
        ("Screen Shot 2022-03-16 at 9.05.00 am.png", local(2022, 3, 16, 9, 5, 0)),
        ("Screenshot 2024-01-02 at 3.04.05\u{202F}PM.png", local(2024, 1, 2, 15, 4, 5)),
        ("Screenshot 2024-01-02 at 3.04.05 PM (2).png", local(2024, 1, 2, 15, 4, 5)),
        ("MVIMG_20220316_135015.jpg", local(2022, 3, 16, 13, 50, 15)),
        ("20240229_000000.heic", local(2024, 2, 29, 0, 0, 0)),
    ])
    func parsesKnownPatterns(fileName: String, expected: LocalDateTime) {
        #expect(parser.date(fromFileName: fileName) == expected)
    }

    @Test(arguments: [
        "IMG_1234.JPG",
        "DSC00042.ARW",
        "holiday.jpg",
        "",
        "IMG_20221316_135015.jpg",                  // month 13
        "20230229_120000.jpg",                      // 29 Feb in a non-leap year
        "2022-02-30 10.00.00.jpg",                  // 30 Feb
        "IMG_20220316_245015.jpg",                  // hour 24
        "Screen Shot 2022-03-16 at 13.50.15 PM.png", // 13 PM
        "Screen Shot 2022-03-16 at 0.50.15 AM.png",  // 0 AM
        "Copy of Screenshot 2022-03-16 at 13.50.15.png", // not at start
        "20220316_1350159.jpg",                     // extra digit
        "18991231_235959.jpg",                      // before 1900
    ])
    func rejectsNonDates(fileName: String) {
        #expect(parser.date(fromFileName: fileName) == nil)
    }

    @Test func customPatterns() throws {
        let parser = try FileNameDateParser(patterns: [
            .init(name: "test", source: #"^photo-(?<y>\d{4})(?<mo>\d{2})(?<d>\d{2})-(?<h>\d{2})(?<mi>\d{2})(?<s>\d{2})"#),
        ])
        #expect(parser.date(fromFileName: "photo-20200101-010203.jpg") == local(2020, 1, 1, 1, 2, 3))
        #expect(parser.date(fromFileName: "IMG_20220316_135015.jpg") == nil)
    }

    @Test func invalidPatternThrows() {
        #expect(throws: (any Error).self) {
            try FileNameDateParser(patterns: [.init(name: "bad", source: "(")])
        }
    }
}

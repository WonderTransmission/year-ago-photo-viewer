import Foundation

extension PhotoIndex {
    /// File names fetched per request to the library.
    static let fileNameBatchSize = 500
    /// Assets read from the library, and written to the index, per batch.
    static let libraryBatchSize = 500

    /// Adds the Photos library as a source. There is at most one; adding it
    /// again returns the existing source.
    public func addPhotosLibrarySource(name: String, dateSource: DateSourceKind) throws -> SourceRecord {
        if let existing = try sources().first(where: { $0.kind == .photos }) {
            return existing
        }
        try database.prepare("""
            INSERT INTO sources (kind, name, date_source, sort_order)
            VALUES ('photos', ?, ?, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM sources))
            """).run([.text(name), .text(dateSource.rawValue)])
        let id = database.lastInsertRowID
        guard let added = try sources().first(where: { $0.id == id }) else {
            throw DatabaseError(code: 0, message: "Source \(id) vanished after insert")
        }
        return added
    }

    /// Brings the index for the Photos library source up to date.
    ///
    /// New assets and assets whose modification date changed are stored;
    /// assets no longer in the library are deleted. `creationDate` fills
    /// both the Created and EXIF dates (Photos treats it as the capture
    /// date). File names are fetched only if the source uses File name dates.
    ///
    /// - Throws: `PhotoIndexError.rootUnavailable` if the library returns no
    ///   assets while the index has some (e.g. its drive is disconnected);
    ///   nothing is deleted.
    ///
    /// - Parameters:
    ///   - priorityWindows: on a first index, photos dated in these windows
    ///     (this week in past years) are read and shown before the rest.
    ///   - onPhotosAvailable: called when newly read photos are visible:
    ///     after the priority pass, then every `fillInInterval` seconds.
    public func syncLibrary(
        sourceID: Int64,
        library: any PhotoLibraryProviding,
        priorityWindows: [ClosedRange<LocalDateTime>] = [],
        onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in },
        onPhotosAvailable: @escaping @Sendable () -> Void = {}
    ) async throws -> SyncResult {
        guard !isSyncing else { throw PhotoIndexError.syncAlreadyRunning }
        isSyncing = true
        defer { isSyncing = false }

        let fetchesNames = try sources().first(where: { $0.id == sourceID })?.dateSource == .fileName
        let progress = ProgressReporter(plan: .library(fetchesNames: fetchesNames), onProgress: onProgress)

        // The first PhotoKit call waits for macOS to open the library.
        progress.report(.opening)

        // First index: show this week's photos from past years right away.
        var priorityRead = 0
        if !priorityWindows.isEmpty, try existingFiles(sourceID: sourceID).isEmpty {
            priorityRead = try await readPriorityWindows(priorityWindows, sourceID: sourceID, library: library)
            if priorityRead > 0 {
                try publishFillIn(sourceID: sourceID, pairs: false, onPhotosAvailable: onPhotosAvailable)
            }
        }

        let list = try await library.openImageAssets()
        try Task.checkCancellation()
        let total = list.count

        // Loaded after the priority pass, so its rows are skipped below.
        let existing = try existingFiles(sourceID: sourceID)
        // A library on a disconnected drive can look empty. Never treat that
        // as "every photo was deleted".
        if total == 0 && !existing.isEmpty {
            throw PhotoIndexError.rootUnavailable
        }

        // Read in batches; each is written before the next is read, so the
        // index fills in as it goes and a stop or quit loses nothing.
        progress.report(.reading, 0, of: total)
        var present = Set<String>()
        present.reserveCapacity(total)
        var changedCount = priorityRead
        var lastFillIn = Date()
        for start in stride(from: 0, to: total, by: Self.libraryBatchSize) {
            try Task.checkCancellation()
            let assets = try await list.assets(in: start..<min(start + Self.libraryBatchSize, total))
            var changed: [FileRecord] = []
            for asset in assets {
                present.insert(asset.localIdentifier)
                let modified = asset.modificationDate.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
                if let known = existing[asset.localIdentifier], known.mtime == modified {
                    continue
                }
                changed.append(record(for: asset))
            }
            try upsert(changed, sourceID: sourceID)
            changedCount += changed.count
            progress.report(.reading, start + assets.count, of: total)
            if Date().timeIntervalSince(lastFillIn) >= fillInInterval {
                try publishFillIn(sourceID: sourceID, pairs: false, onPhotosAvailable: onPhotosAvailable)
                lastFillIn = Date()
            }
        }
        let removed = existing.keys.filter { !present.contains($0) }
        try deleteFiles(sourceID: sourceID, locators: removed)

        if fetchesNames {
            try await fetchMissingFileNames(sourceID: sourceID, library: library, progress: progress)
        }
        progress.report(.organizing)
        try refreshDerived()
        progress.report(.organizing, 1, of: 1)
        return SyncResult(scanned: total, read: changedCount, removed: removed.count)
    }

    /// Reads and stores the library photos created in `windows`, widened by
    /// a day each side so time zones and DST can't cut photos off. Returns
    /// how many were stored.
    private func readPriorityWindows(_ windows: [ClosedRange<LocalDateTime>], sourceID: Int64,
                                     library: any PhotoLibraryProviding) async throws -> Int {
        let day: TimeInterval = 86_400
        let ranges = windows.map { window in
            window.lowerBound.date(in: timeZone).addingTimeInterval(-day)
                ... window.upperBound.date(in: timeZone).addingTimeInterval(day)
        }
        let list = try await library.openImageAssets(createdIn: ranges)
        let assets = try await list.assets(in: 0..<list.count)
        try upsert(assets.map(record(for:)), sourceID: sourceID)
        return assets.count
    }

    /// The index row for a library asset.
    private func record(for asset: LibraryAsset) -> FileRecord {
        let modified = asset.modificationDate.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
        let created = asset.creationDate.map { LocalDateTime($0, in: timeZone) }
        return FileRecord(
            locator: asset.localIdentifier, fileName: nil, byteSize: nil, fsMtime: modified,
            dateFileName: nil,
            dateModified: asset.modificationDate.map { LocalDateTime($0, in: timeZone) },
            dateCreated: created, dateExif: created,
            pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight, isRaw: false)
    }

    /// Fetches and stores original file names for library rows that lack
    /// one, and parses their file-name dates.
    private func fetchMissingFileNames(
        sourceID: Int64,
        library: any PhotoLibraryProviding,
        progress: ProgressReporter
    ) async throws {
        let query = try database.prepare("SELECT locator FROM photos WHERE source_id = ? AND file_name IS NULL")
        try query.bind([.int(sourceID)])
        var missing: [String] = []
        while try query.step() {
            missing.append(query.text(0))
        }
        guard !missing.isEmpty else { return }

        let parser = FileNameDateParser.standard()
        let update = try database.prepare(
            "UPDATE photos SET file_name = ?, date_file_name = ? WHERE source_id = ? AND locator = ?")
        progress.report(.naming, 0, of: missing.count)
        for start in stride(from: 0, to: missing.count, by: Self.fileNameBatchSize) {
            try Task.checkCancellation()
            let batch = Array(missing[start..<min(start + Self.fileNameBatchSize, missing.count)])
            let names = await library.originalFileNames(for: batch)
            try database.transaction {
                for (id, name) in names {
                    try update.run([.text(name), .date(parser.date(fromFileName: name)), .int(sourceID), .text(id)])
                }
            }
            progress.report(.naming, start + batch.count, of: missing.count)
        }
    }
}

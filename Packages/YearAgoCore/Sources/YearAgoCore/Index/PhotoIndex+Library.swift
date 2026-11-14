import Foundation

extension PhotoIndex {
    /// File names fetched per request to the library.
    static let fileNameBatchSize = 500

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
    public func syncLibrary(
        sourceID: Int64,
        library: any PhotoLibraryProviding,
        onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws -> SyncResult {
        guard !isSyncing else { throw PhotoIndexError.syncAlreadyRunning }
        isSyncing = true
        defer { isSyncing = false }

        // The first PhotoKit call waits for macOS to open the library.
        onProgress(ScanProgress(stage: .opening, completed: 0))
        let assets = try await library.imageAssets()
        try Task.checkCancellation()
        onProgress(ScanProgress(stage: .finding, completed: assets.count))

        let existing = try existingFiles(sourceID: sourceID)
        // A library on a disconnected drive can look empty. Never treat that
        // as "every photo was deleted".
        if assets.isEmpty && !existing.isEmpty {
            throw PhotoIndexError.rootUnavailable
        }
        var present = Set<String>()
        present.reserveCapacity(assets.count)
        var changed: [FileRecord] = []
        for asset in assets {
            present.insert(asset.localIdentifier)
            let modified = asset.modificationDate.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
            if let known = existing[asset.localIdentifier], known.mtime == modified {
                continue
            }
            let created = asset.creationDate.map { LocalDateTime($0, in: timeZone) }
            changed.append(FileRecord(
                locator: asset.localIdentifier, fileName: nil, byteSize: nil, fsMtime: modified,
                dateFileName: nil,
                dateModified: asset.modificationDate.map { LocalDateTime($0, in: timeZone) },
                dateCreated: created, dateExif: created,
                pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight, isRaw: false))
        }
        let removed = existing.keys.filter { !present.contains($0) }
        try deleteFiles(sourceID: sourceID, locators: removed)

        onProgress(ScanProgress(stage: .reading, completed: 0, total: changed.count))
        for start in stride(from: 0, to: changed.count, by: Self.batchSize) {
            let batch = Array(changed[start..<min(start + Self.batchSize, changed.count)])
            try upsert(batch, sourceID: sourceID)
            onProgress(ScanProgress(stage: .reading, completed: start + batch.count, total: changed.count))
        }

        if try sources().first(where: { $0.id == sourceID })?.dateSource == .fileName {
            try await fetchMissingFileNames(sourceID: sourceID, library: library, onProgress: onProgress)
        }
        try refreshDerived()
        return SyncResult(scanned: assets.count, read: changed.count, removed: removed.count)
    }

    /// Fetches and stores original file names for library rows that lack
    /// one, and parses their file-name dates.
    private func fetchMissingFileNames(
        sourceID: Int64,
        library: any PhotoLibraryProviding,
        onProgress: @escaping @Sendable (ScanProgress) -> Void
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
        onProgress(ScanProgress(stage: .reading, completed: 0, total: missing.count))
        for start in stride(from: 0, to: missing.count, by: Self.fileNameBatchSize) {
            try Task.checkCancellation()
            let batch = Array(missing[start..<min(start + Self.fileNameBatchSize, missing.count)])
            let names = await library.originalFileNames(for: batch)
            try database.transaction {
                for (id, name) in names {
                    try update.run([.text(name), .date(parser.date(fromFileName: name)), .int(sourceID), .text(id)])
                }
            }
            onProgress(ScanProgress(stage: .reading, completed: start + batch.count, total: missing.count))
        }
    }
}

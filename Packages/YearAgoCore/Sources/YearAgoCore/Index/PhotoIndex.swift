import Foundation

/// Progress of a folder sync, for the UI.
public struct ScanProgress: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        /// Walking the folder. `total` is nil.
        case finding
        /// Reading metadata from new and changed files.
        case reading
    }

    public var stage: Stage
    public var completed: Int
    public var total: Int?

    public init(stage: Stage, completed: Int, total: Int? = nil) {
        self.stage = stage
        self.completed = completed
        self.total = total
    }
}

/// What a sync did.
public struct SyncResult: Equatable, Sendable {
    /// Displayable files found in the folder.
    public var scanned: Int
    /// New or changed files whose metadata was read.
    public var read: Int
    /// Rows deleted because their file is gone.
    public var removed: Int
}

/// A folder source as stored in the index.
public struct FolderSourceRecord: Equatable, Sendable {
    public var id: Int64
    public var name: String
    public var rootPath: String
    public var dateSource: DateSourceKind
}

public enum PhotoIndexError: Error {
    case syncAlreadyRunning
}

/// The persistent photo index. See implementation plan sections 6 and 7 (M4).
///
/// Stores every date kind for every file, so changing a source's date
/// setting needs no rescan. Rescans re-read only files whose size or
/// modification time changed.
public actor PhotoIndex {
    /// Rows written per transaction.
    static let batchSize = 1_000
    /// Files per concurrent metadata-reading task.
    static let chunkSize = 128

    private let database: Database
    private let timeZone: TimeZone
    private var isSyncing = false

    /// Opens the index at `fileURL`, creating it and its folder if needed.
    /// Pass nil for a private in-memory index (tests).
    ///
    /// File dates are stored as wall-clock times in `timeZone`. If the
    /// index was built in a different time zone, every file is re-read on
    /// the next sync.
    public init(fileURL: URL?, timeZone: TimeZone = .current) throws {
        if let fileURL {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        }
        let database = try Database(path: fileURL?.path ?? ":memory:")
        try Schema.migrate(database)
        try Self.handleTimeZoneChange(database, timeZone: timeZone)
        self.database = database
        self.timeZone = timeZone
    }

    // MARK: - Sources

    /// Finds the folder source for `rootPath`, or creates it.
    public func folderSource(rootPath: String, name: String,
                             defaultDateSource: DateSourceKind) throws -> FolderSourceRecord {
        let find = try database.prepare(
            "SELECT id, name, date_source FROM sources WHERE kind = 'folder' AND root_path = ?")
        try find.bind([.text(rootPath)])
        if try find.step() {
            return FolderSourceRecord(id: find.int64(0), name: find.text(1), rootPath: rootPath,
                                      dateSource: DateSourceKind(rawValue: find.text(2)) ?? defaultDateSource)
        }
        try database.prepare("""
            INSERT INTO sources (kind, name, root_path, date_source, sort_order)
            VALUES ('folder', ?, ?, ?, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM sources))
            """).run([.text(name), .text(rootPath), .text(defaultDateSource.rawValue)])
        return FolderSourceRecord(id: database.lastInsertRowID, name: name, rootPath: rootPath,
                                  dateSource: defaultDateSource)
    }

    /// Deletes every source except `id`, with its photos. Used while the app
    /// supports a single folder (until M5).
    public func removeSources(except id: Int64) throws {
        try database.prepare("DELETE FROM sources WHERE id <> ?").run([.int(id)])
    }

    /// Changes which date a source uses. Takes effect without a rescan.
    public func setDateSource(_ dateSource: DateSourceKind, forSource id: Int64) throws {
        try database.prepare("UPDATE sources SET date_source = ? WHERE id = ?")
            .run([.text(dateSource.rawValue), .int(id)])
        try refreshDerived()
    }

    // MARK: - Sync

    /// Brings the index for one folder source up to date with the disk.
    ///
    /// New and changed files have their metadata read, concurrently and off
    /// the actor. Rows for files that no longer exist are deleted.
    /// - Throws: `PhotoIndexError.syncAlreadyRunning` if another sync is in
    ///   progress, or a database error.
    public func sync(
        sourceID: Int64,
        root: URL,
        onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws -> SyncResult {
        guard !isSyncing else { throw PhotoIndexError.syncAlreadyRunning }
        isSyncing = true
        defer { isSyncing = false }

        onProgress(ScanProgress(stage: .finding, completed: 0))
        let files = await Self.scanFolder(root, onProgress: onProgress)
        try Task.checkCancellation()

        let existing = try existingFiles(sourceID: sourceID)
        var present = Set<String>()
        present.reserveCapacity(files.count)
        var changed: [ScannedFile] = []
        for file in files {
            present.insert(file.relativePath)
            if let known = existing[file.relativePath],
               known.byteSize == file.byteSize, known.mtime == file.modifiedMilliseconds {
                continue
            }
            changed.append(file)
        }
        let removed = existing.keys.filter { !present.contains($0) }
        try deleteFiles(sourceID: sourceID, locators: removed)

        try await readAndStore(changed, sourceID: sourceID, onProgress: onProgress)
        try refreshDerived()
        return SyncResult(scanned: files.count, read: changed.count, removed: removed.count)
    }

    /// Walks the folder off the actor.
    @concurrent
    private static func scanFolder(_ root: URL,
                                   onProgress: @escaping @Sendable (ScanProgress) -> Void) async -> [ScannedFile] {
        FolderScanner.scan(root) { found in
            onProgress(ScanProgress(stage: .finding, completed: found))
        }
    }

    private func readAndStore(_ files: [ScannedFile], sourceID: Int64,
                              onProgress: @escaping @Sendable (ScanProgress) -> Void) async throws {
        let total = files.count
        onProgress(ScanProgress(stage: .reading, completed: 0, total: total))
        guard total > 0 else { return }

        let timeZone = timeZone
        let chunks = stride(from: 0, to: total, by: Self.chunkSize).map {
            Array(files[$0..<min($0 + Self.chunkSize, total)])
        }
        try await withThrowingTaskGroup(of: [FileRecord].self) { group in
            for chunk in chunks {
                group.addTask {
                    try Task.checkCancellation()
                    return FileRecord.read(chunk, timeZone: timeZone)
                }
            }
            var pending: [FileRecord] = []
            var completed = 0
            for try await records in group {
                pending.append(contentsOf: records)
                completed += records.count
                if pending.count >= Self.batchSize {
                    try upsert(pending, sourceID: sourceID)
                    pending.removeAll(keepingCapacity: true)
                }
                onProgress(ScanProgress(stage: .reading, completed: completed, total: total))
            }
            try upsert(pending, sourceID: sourceID)
        }
    }

    // MARK: - Queries

    /// Every visible photo, in date order. Photos from sources missing from
    /// `roots` are left out.
    /// - Parameter roots: each folder source's root URL, by source ID.
    public func loadTimeline(roots: [Int64: URL]) throws -> PhotoTimeline {
        let query = try database.prepare("""
            SELECT source_id, locator, effective_date, is_raw FROM photos
            WHERE is_visible = 1
            ORDER BY effective_date, locator
            """)
        try query.bind([])
        var items: [PhotoItem] = []
        while try query.step() {
            guard let root = roots[query.int64(0)] else { continue }
            let locator = query.text(1)
            items.append(PhotoItem(
                url: root.appending(path: locator, directoryHint: .notDirectory),
                relativePath: locator,
                kind: query.int64(3) != 0 ? .raw : .image,
                date: LocalDateTime(seconds: query.int64(2))))
        }
        return PhotoTimeline(presorted: items)
    }

    /// Number of indexed files for a source, dated or not.
    public func fileCount(sourceID: Int64) throws -> Int {
        let query = try database.prepare("SELECT COUNT(*) FROM photos WHERE source_id = ?")
        try query.bind([.int(sourceID)])
        _ = try query.step()
        return Int(query.int64(0))
    }

    // MARK: - Internals

    private func existingFiles(sourceID: Int64) throws -> [String: (byteSize: Int64, mtime: Int64?)] {
        let query = try database.prepare("SELECT locator, byte_size, fs_mtime FROM photos WHERE source_id = ?")
        try query.bind([.int(sourceID)])
        var result: [String: (Int64, Int64?)] = [:]
        while try query.step() {
            result[query.text(0)] = (query.int64(1), query.optionalInt64(2))
        }
        return result
    }

    private func deleteFiles(sourceID: Int64, locators: [String]) throws {
        guard !locators.isEmpty else { return }
        let delete = try database.prepare("DELETE FROM photos WHERE source_id = ? AND locator = ?")
        try database.transaction {
            for locator in locators {
                try delete.run([.int(sourceID), .text(locator)])
            }
        }
    }

    private func upsert(_ records: [FileRecord], sourceID: Int64) throws {
        guard !records.isEmpty else { return }
        let statement = try database.prepare("""
            INSERT INTO photos (source_id, locator, file_name, byte_size, fs_mtime,
                                date_file_name, date_modified, date_created, date_exif,
                                pixel_w, pixel_h, is_raw)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (source_id, locator) DO UPDATE SET
                file_name = excluded.file_name,
                byte_size = excluded.byte_size,
                fs_mtime = excluded.fs_mtime,
                date_file_name = excluded.date_file_name,
                date_modified = excluded.date_modified,
                date_created = excluded.date_created,
                date_exif = excluded.date_exif,
                pixel_w = excluded.pixel_w,
                pixel_h = excluded.pixel_h,
                is_raw = excluded.is_raw,
                content_hash = NULL
            """)
        try database.transaction {
            for record in records {
                try statement.run([
                    .int(sourceID), .text(record.locator), .text(record.fileName),
                    .int(record.byteSize), .optionalInt(record.fsMtime),
                    .date(record.dateFileName), .date(record.dateModified),
                    .date(record.dateCreated), .date(record.dateExif),
                    .optionalInt(record.pixelWidth), .optionalInt(record.pixelHeight),
                    .int(record.isRaw ? 1 : 0),
                ])
            }
        }
    }

    /// Recomputes `effective_date` and `is_visible` for every row.
    /// M5 and M6 extend this with pairing and duplicate rules.
    private func refreshDerived() throws {
        try database.transaction {
            try database.execute("""
                UPDATE photos SET effective_date = CASE
                    (SELECT date_source FROM sources WHERE sources.id = photos.source_id)
                    WHEN 'fileName' THEN date_file_name
                    WHEN 'modified' THEN date_modified
                    WHEN 'created'  THEN date_created
                    ELSE date_exif
                END;

                UPDATE photos SET is_visible = CASE
                    WHEN effective_date IS NOT NULL AND EXISTS (
                        SELECT 1 FROM sources s
                        WHERE s.id = photos.source_id AND s.is_enabled = 1 AND s.is_online = 1)
                    THEN 1 ELSE 0
                END;
                """)
        }
    }

    /// If the index was built in another time zone, clears every file's
    /// change marker so the next sync re-reads all file dates.
    private static func handleTimeZoneChange(_ database: Database, timeZone: TimeZone) throws {
        let query = try database.prepare("SELECT value FROM meta WHERE key = 'time_zone'")
        try query.bind([])
        let stored = try query.step() ? query.text(0) : nil
        guard stored != timeZone.identifier else { return }
        try database.transaction {
            if stored != nil {
                try database.execute("UPDATE photos SET fs_mtime = NULL")
            }
            try database.prepare("INSERT OR REPLACE INTO meta (key, value) VALUES ('time_zone', ?)")
                .run([.text(timeZone.identifier)])
        }
    }
}

/// One file's indexed metadata.
struct FileRecord: Sendable {
    var locator: String
    var fileName: String
    var byteSize: Int64
    var fsMtime: Int64?
    var dateFileName: LocalDateTime?
    var dateModified: LocalDateTime?
    var dateCreated: LocalDateTime?
    var dateExif: LocalDateTime?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var isRaw: Bool

    /// Reads all four dates and the pixel size for each file.
    static func read(_ files: [ScannedFile], timeZone: TimeZone) -> [FileRecord] {
        // One parser per call: FileNameDateParser is not Sendable.
        let parser = FileNameDateParser.standard()
        return files.map { file in
            let metadata = ImageMetadataReader.read(at: file.url)
            let fileName = file.url.lastPathComponent
            return FileRecord(
                locator: file.relativePath,
                fileName: fileName,
                byteSize: file.byteSize,
                fsMtime: file.modifiedMilliseconds,
                dateFileName: parser.date(fromFileName: fileName),
                dateModified: file.modified.map { LocalDateTime($0, in: timeZone) },
                dateCreated: file.created.map { LocalDateTime($0, in: timeZone) },
                dateExif: metadata.captureDate,
                pixelWidth: metadata.pixelWidth,
                pixelHeight: metadata.pixelHeight,
                isRaw: file.kind == .raw)
        }
    }
}

import Foundation

/// Progress of a folder sync, for the UI.
public struct ScanProgress: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        /// Walking the folder. `total` is nil.
        case finding
        /// Reading metadata from new and changed files.
        case reading
        /// Hashing same-size files to find duplicates.
        case hashing
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

public enum PhotoIndexError: Error {
    case syncAlreadyRunning
    /// The source's folder is missing, e.g. its drive is unplugged. Nothing
    /// was deleted.
    case rootUnavailable
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

    /// Internal so the source and derived-column extensions can use it.
    let database: Database
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

    // MARK: - Sync

    /// Brings the index for one folder source up to date with the disk.
    ///
    /// New and changed files have their metadata read, concurrently and off
    /// the actor. Rows for files that no longer exist are deleted.
    /// - Throws: `PhotoIndexError.syncAlreadyRunning` if another sync is in
    ///   progress, `PhotoIndexError.rootUnavailable` if `root` is not a
    ///   reachable folder (nothing is deleted), or a database error.
    public func sync(
        sourceID: Int64,
        root: URL,
        onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws -> SyncResult {
        guard !isSyncing else { throw PhotoIndexError.syncAlreadyRunning }
        // An unplugged drive looks like an empty folder. Never treat it as
        // "every file was deleted".
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw PhotoIndexError.rootUnavailable }
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
        if !changed.isEmpty || !removed.isEmpty {
            try updatePairs(sourceID: sourceID)
        }
        try refreshDerived()
        return SyncResult(scanned: files.count, read: changed.count, removed: removed.count)
    }

    /// Hashes files that might be duplicates, then regroups duplicates.
    ///
    /// Only files that share their byte size with another indexed file, and
    /// have no hash yet, are read. A changed file loses its hash on sync, so
    /// each file version is hashed once. Call after syncing sources.
    /// - Parameter roots: root URLs of the reachable folder sources.
    /// - Returns: how many files were hashed.
    @discardableResult
    public func findDuplicates(
        roots: [Int64: URL],
        onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws -> Int {
        guard !isSyncing else { throw PhotoIndexError.syncAlreadyRunning }
        isSyncing = true
        defer { isSyncing = false }

        let query = try database.prepare("""
            SELECT id, source_id, locator FROM photos
            WHERE content_hash IS NULL AND byte_size IN (
                SELECT byte_size FROM photos WHERE byte_size IS NOT NULL
                GROUP BY byte_size HAVING COUNT(*) > 1)
            """)
        try query.bind([])
        var candidates: [(id: Int64, url: URL)] = []
        while try query.step() {
            guard let root = roots[query.int64(1)] else { continue }
            candidates.append((query.int64(0), root.appending(path: query.text(2), directoryHint: .notDirectory)))
        }

        let total = candidates.count
        if total > 0 {
            onProgress(ScanProgress(stage: .hashing, completed: 0, total: total))
            let chunks = stride(from: 0, to: total, by: Self.chunkSize).map {
                Array(candidates[$0..<min($0 + Self.chunkSize, total)])
            }
            let setHash = try database.prepare("UPDATE photos SET content_hash = ? WHERE id = ?")
            try await withThrowingTaskGroup(of: [(Int64, Data?)].self) { group in
                for chunk in chunks {
                    group.addTask {
                        try Task.checkCancellation()
                        return chunk.map { ($0.id, ContentHasher.sha256(of: $0.url)) }
                    }
                }
                var completed = 0
                for try await hashes in group {
                    try database.transaction {
                        // Unreadable files keep a NULL hash and are retried next time.
                        for case let (id, hash?) in hashes {
                            try setHash.run([.blob(hash), .int(id)])
                        }
                    }
                    completed += hashes.count
                    onProgress(ScanProgress(stage: .hashing, completed: completed, total: total))
                }
            }
        }
        try refreshDerived()
        return total
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

    /// Every visible photo from every source, in date order. Photos from
    /// sources missing from `roots` are left out.
    /// - Parameter roots: each folder source's root URL, by source ID.
    public func loadTimeline(roots: [Int64: URL]) throws -> PhotoTimeline {
        let query = try database.prepare("""
            SELECT source_id, locator, effective_date, is_raw,
                   EXISTS (SELECT 1 FROM photos AS raw WHERE raw.pair_primary = photos.id)
            FROM photos
            WHERE is_visible = 1
            ORDER BY effective_date, locator
            """)
        try query.bind([])
        var items: [PhotoItem] = []
        while try query.step() {
            let sourceID = query.int64(0)
            guard let root = roots[sourceID] else { continue }
            let locator = query.text(1)
            items.append(PhotoItem(
                sourceID: sourceID,
                url: root.appending(path: locator, directoryHint: .notDirectory),
                relativePath: locator,
                kind: query.int64(3) != 0 ? .raw : .image,
                date: LocalDateTime(seconds: query.int64(2)),
                hasRawPartner: query.int64(4) != 0))
        }
        return PhotoTimeline(presorted: items)
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

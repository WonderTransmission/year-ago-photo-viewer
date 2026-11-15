import Foundation

/// A photo source as stored in the index.
public struct SourceRecord: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case folder
        /// The system Photos library, through PhotoKit.
        case photos
        /// A `.photoslibrary` package, read as files. See `PhotosLibraryPackage`.
        case libraryPackage

        /// True for sources read as files: folders and library packages.
        public var isFileBased: Bool { self != .photos }

        /// Date settings that make sense for this kind. Library packages
        /// store originals under UUID names, so the File name date is out.
        public var dateSources: [DateSourceKind] {
            self == .libraryPackage ? DateSourceKind.allCases.filter { $0 != .fileName } : DateSourceKind.allCases
        }

        /// `preferred`, or EXIF when this kind can't use it.
        public func dateSource(preferring preferred: DateSourceKind) -> DateSourceKind {
            dateSources.contains(preferred) ? preferred : .exif
        }
    }

    public var id: Int64
    public var kind: Kind
    public var name: String
    /// File-based sources only: the resolved root path (the package, for a
    /// library package).
    public var rootPath: String?
    /// File-based sources only: a security-scoped bookmark to the root.
    public var bookmark: Data?
    public var dateSource: DateSourceKind
    public var isEnabled: Bool
    /// False when the folder cannot be reached, e.g. its drive is unplugged.
    public var isOnline: Bool
    public var sortOrder: Int
    /// True when the user stopped indexing it; it isn't re-indexed until
    /// resumed.
    public var isStopped: Bool = false
    /// Items the source had at its last sync (library assets, or files
    /// found in the folder), if known.
    public var knownTotal: Int?
}

/// Per-source counts for the Sources panel.
public struct SourceStats: Equatable, Sendable {
    /// Indexed files, dated or not.
    public var files: Int
    /// Photos currently shown from this source.
    public var visible: Int

    public init(files: Int, visible: Int) {
        self.files = files
        self.visible = visible
    }
}

extension PhotoIndex {
    /// All sources, in the user's order.
    public func sources() throws -> [SourceRecord] {
        let query = try database.prepare("""
            SELECT id, kind, name, root_path, bookmark, date_source, is_enabled, is_online, sort_order,
                   is_stopped, known_total
            FROM sources ORDER BY sort_order, id
            """)
        try query.bind([])
        var result: [SourceRecord] = []
        while try query.step() {
            result.append(SourceRecord(
                id: query.int64(0),
                kind: SourceRecord.Kind(rawValue: query.text(1)) ?? .folder,
                name: query.text(2),
                rootPath: query.isNull(3) ? nil : query.text(3),
                bookmark: query.blob(4),
                dateSource: DateSourceKind(rawValue: query.text(5)) ?? .exif,
                isEnabled: query.int64(6) != 0,
                isOnline: query.int64(7) != 0,
                sortOrder: Int(query.int64(8)),
                isStopped: query.int64(9) != 0,
                knownTotal: query.optionalInt64(10).map(Int.init)))
        }
        return result
    }

    /// Adds a file-based source (a folder, or a library package) at the end
    /// of the list. If `rootPath` is already a source of that kind, returns
    /// it instead, updating its bookmark when given one. A date setting the
    /// kind can't use becomes EXIF.
    public func addFolderSource(rootPath: String, name: String, bookmark: Data?,
                                dateSource: DateSourceKind,
                                kind: SourceRecord.Kind = .folder) throws -> SourceRecord {
        precondition(kind.isFileBased, "The Photos library has its own add method")
        if let existing = try sources().first(where: { $0.kind == kind && $0.rootPath == rootPath }) {
            guard let bookmark else { return existing }
            try setBookmark(bookmark, forSource: existing.id)
            var updated = existing
            updated.bookmark = bookmark
            return updated
        }
        try database.prepare("""
            INSERT INTO sources (kind, name, root_path, bookmark, date_source, sort_order)
            VALUES (?, ?, ?, ?, ?, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM sources))
            """).run([.text(kind.rawValue), .text(name), .text(rootPath), bookmark.map(SQLValue.blob) ?? .null,
                      .text(kind.dateSource(preferring: dateSource).rawValue)])
        let id = database.lastInsertRowID
        guard let added = try sources().first(where: { $0.id == id }) else {
            throw DatabaseError(code: 0, message: "Source \(id) vanished after insert")
        }
        return added
    }

    /// Deletes a source and all its photos.
    public func removeSource(_ id: Int64) throws {
        try database.prepare("DELETE FROM sources WHERE id = ?").run([.int(id)])
        try refreshDerived()
    }

    public func renameSource(_ id: Int64, to name: String) throws {
        try database.prepare("UPDATE sources SET name = ? WHERE id = ?").run([.text(name), .int(id)])
    }

    public func setBookmark(_ bookmark: Data, forSource id: Int64) throws {
        try database.prepare("UPDATE sources SET bookmark = ? WHERE id = ?").run([.blob(bookmark), .int(id)])
    }

    /// Shows or hides a source's photos without deleting them.
    public func setEnabled(_ isEnabled: Bool, forSource id: Int64) throws {
        try database.prepare("UPDATE sources SET is_enabled = ? WHERE id = ?")
            .run([.int(isEnabled ? 1 : 0), .int(id)])
        try refreshDerived()
    }

    /// Marks a source reachable or not. Offline sources keep their rows but
    /// show no photos.
    public func setOnline(_ isOnline: Bool, forSource id: Int64) throws {
        try database.prepare("UPDATE sources SET is_online = ? WHERE id = ? AND is_online <> ?")
            .run([.int(isOnline ? 1 : 0), .int(id), .int(isOnline ? 1 : 0)])
        if database.changes > 0 {
            try refreshDerived()
        }
    }

    /// Marks a source stopped (not re-indexed until resumed) or resumed.
    public func setStopped(_ isStopped: Bool, forSource id: Int64) throws {
        try database.prepare("UPDATE sources SET is_stopped = ? WHERE id = ?")
            .run([.int(isStopped ? 1 : 0), .int(id)])
    }

    /// Records how many items a source had at its latest sync.
    func setKnownTotal(_ total: Int, forSource id: Int64) throws {
        try database.prepare("UPDATE sources SET known_total = ? WHERE id = ?").run([.int(Int64(total)), .int(id)])
    }

    /// Changes which date a source uses. Takes effect without a rescan.
    /// A date setting the source's kind can't use becomes EXIF.
    public func setDateSource(_ dateSource: DateSourceKind, forSource id: Int64) throws {
        let kind = try sources().first { $0.id == id }?.kind ?? .folder
        try database.prepare("UPDATE sources SET date_source = ? WHERE id = ?")
            .run([.text(kind.dateSource(preferring: dateSource).rawValue), .int(id)])
        try refreshDerived()
    }

    /// Gives every source the same date setting, where its kind can use it.
    /// Other sources keep theirs.
    public func setDateSourceForAll(_ dateSource: DateSourceKind) throws {
        let update = try database.prepare("UPDATE sources SET date_source = ? WHERE kind = ?")
        try database.transaction {
            for kind in SourceRecord.Kind.allCases where kind.dateSources.contains(dateSource) {
                try update.run([.text(dateSource.rawValue), .text(kind.rawValue)])
            }
        }
        try refreshDerived()
    }

    /// Stores a new order. `ids` lists source IDs first to last; sources
    /// not listed keep their relative order after them.
    public func reorderSources(_ ids: [Int64]) throws {
        let rest = try sources().map(\.id).filter { !ids.contains($0) }
        let update = try database.prepare("UPDATE sources SET sort_order = ? WHERE id = ?")
        try database.transaction {
            for (order, id) in (ids + rest).enumerated() {
                try update.run([.int(Int64(order + 1)), .int(id)])
            }
        }
    }

    /// File and visible-photo counts for every source.
    public func sourceStats() throws -> [Int64: SourceStats] {
        let query = try database.prepare("""
            SELECT s.id, COUNT(p.id), COALESCE(SUM(p.is_visible), 0)
            FROM sources s LEFT JOIN photos p ON p.source_id = s.id
            GROUP BY s.id
            """)
        try query.bind([])
        var result: [Int64: SourceStats] = [:]
        while try query.step() {
            result[query.int64(0)] = SourceStats(files: Int(query.int64(1)), visible: Int(query.int64(2)))
        }
        return result
    }

    /// Number of indexed files for a source, dated or not.
    public func fileCount(sourceID: Int64) throws -> Int {
        try sourceStats()[sourceID]?.files ?? 0
    }
}

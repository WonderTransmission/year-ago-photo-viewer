import Foundation

/// A photo source as stored in the index.
public struct SourceRecord: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case folder
        case photos
    }

    public var id: Int64
    public var kind: Kind
    public var name: String
    /// Folders only: the resolved root path.
    public var rootPath: String?
    /// Folders only: a security-scoped bookmark to the root.
    public var bookmark: Data?
    public var dateSource: DateSourceKind
    public var isEnabled: Bool
    /// False when the folder cannot be reached, e.g. its drive is unplugged.
    public var isOnline: Bool
    public var sortOrder: Int
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
            SELECT id, kind, name, root_path, bookmark, date_source, is_enabled, is_online, sort_order
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
                sortOrder: Int(query.int64(8))))
        }
        return result
    }

    /// Adds a folder source at the end of the list. If `rootPath` is already
    /// a source, returns it instead, updating its bookmark when given one.
    public func addFolderSource(rootPath: String, name: String, bookmark: Data?,
                                dateSource: DateSourceKind) throws -> SourceRecord {
        if let existing = try sources().first(where: { $0.kind == .folder && $0.rootPath == rootPath }) {
            guard let bookmark else { return existing }
            try setBookmark(bookmark, forSource: existing.id)
            var updated = existing
            updated.bookmark = bookmark
            return updated
        }
        try database.prepare("""
            INSERT INTO sources (kind, name, root_path, bookmark, date_source, sort_order)
            VALUES ('folder', ?, ?, ?, ?, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM sources))
            """).run([.text(name), .text(rootPath), bookmark.map(SQLValue.blob) ?? .null,
                      .text(dateSource.rawValue)])
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

    /// Changes which date a source uses. Takes effect without a rescan.
    public func setDateSource(_ dateSource: DateSourceKind, forSource id: Int64) throws {
        try database.prepare("UPDATE sources SET date_source = ? WHERE id = ?")
            .run([.text(dateSource.rawValue), .int(id)])
        try refreshDerived()
    }

    /// Gives every source the same date setting.
    public func setDateSourceForAll(_ dateSource: DateSourceKind) throws {
        try database.prepare("UPDATE sources SET date_source = ?").run([.text(dateSource.rawValue)])
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

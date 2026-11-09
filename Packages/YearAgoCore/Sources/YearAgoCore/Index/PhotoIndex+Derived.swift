import Foundation

extension PhotoIndex {
    /// Recomputes `dup_group`, `effective_date`, and `is_visible` for every
    /// row. See implementation plan section 6.1.
    ///
    /// M5 groups only the same file reached through nested folder sources.
    /// M6 adds RAW pairing and content duplicates.
    func refreshDerived() throws {
        let nested = try nestedSourcePairs()
        try database.transaction {
            // 1. Every row starts in its own duplicate group.
            try database.execute("UPDATE photos SET dup_group = id")

            // 2. A file inside a nested source is the same file as the outer
            //    source's row. Outer-most pairs first, so chains collapse.
            let link = try database.prepare("""
                UPDATE photos SET dup_group = COALESCE(
                    (SELECT outer_row.dup_group FROM photos AS outer_row
                     WHERE outer_row.source_id = ? AND outer_row.locator = ? || photos.locator),
                    dup_group)
                WHERE source_id = ?
                """)
            for pair in nested {
                try link.run([.int(pair.outer), .text(pair.prefix), .int(pair.inner)])
            }

            // 3. Each row's date comes from its own source's date setting.
            try database.execute("""
                UPDATE photos SET effective_date = CASE
                    (SELECT date_source FROM sources WHERE sources.id = photos.source_id)
                    WHEN 'fileName' THEN date_file_name
                    WHEN 'modified' THEN date_modified
                    WHEN 'created'  THEN date_created
                    ELSE date_exif
                END
                """)

            // 4. Visible: dated, from an enabled online source, and the
            //    earliest-dated copy in its group (ties: shortest path, then
            //    alphabetical). Only eligible rows compete, so a disabled
            //    source's copy never hides an enabled source's copy.
            try database.execute("""
                UPDATE photos SET is_visible = 0;

                WITH eligible AS (
                    SELECT p.id,
                           ROW_NUMBER() OVER (
                               PARTITION BY p.dup_group
                               ORDER BY p.effective_date,
                                        length(COALESCE(s.root_path, '') || '/' || p.locator),
                                        COALESCE(s.root_path, '') || '/' || p.locator
                           ) AS rank
                    FROM photos p JOIN sources s ON s.id = p.source_id
                    WHERE s.is_enabled = 1 AND s.is_online = 1
                      AND p.effective_date IS NOT NULL
                      AND p.pair_primary IS NULL
                )
                UPDATE photos SET is_visible = 1
                WHERE id IN (SELECT id FROM eligible WHERE rank = 1)
                """)
        }
    }

    /// Folder sources whose root sits inside another folder source's root.
    /// `prefix` is the inner root's path relative to the outer root, with a
    /// trailing "/". Sorted outer-most first.
    private func nestedSourcePairs() throws -> [(outer: Int64, inner: Int64, prefix: String)] {
        let folders = try sources().filter { $0.kind == .folder }.compactMap { source in
            source.rootPath.map { (id: source.id, root: $0.hasSuffix("/") ? $0 : $0 + "/") }
        }
        var pairs: [(outer: Int64, inner: Int64, prefix: String, outerLength: Int)] = []
        for outer in folders {
            for inner in folders where inner.id != outer.id && inner.root.hasPrefix(outer.root) {
                pairs.append((outer.id, inner.id, String(inner.root.dropFirst(outer.root.count)), outer.root.count))
            }
        }
        return pairs
            .sorted { $0.outerLength < $1.outerLength }
            .map { ($0.outer, $0.inner, $0.prefix) }
    }
}

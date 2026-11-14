import Foundation

extension PhotoIndex {
    /// Recomputes `dup_group`, `effective_date`, and `is_visible` for every
    /// row. See implementation plan section 6.1 and proposal 4.7–4.8.
    func refreshDerived() throws {
        let groups = try duplicateGroups()
        try database.transaction {
            // 1. Duplicate groups. Rows not linked to any other row are
            //    their own group.
            try database.execute("UPDATE photos SET dup_group = id")
            let setGroup = try database.prepare("UPDATE photos SET dup_group = ? WHERE id = ?")
            for (id, group) in groups where id != group {
                try setGroup.run([.int(group), .int(id)])
            }

            // 2. Each row's date comes from its own source's date setting.
            try database.execute("""
                UPDATE photos SET effective_date = CASE
                    (SELECT date_source FROM sources WHERE sources.id = photos.source_id)
                    WHEN 'fileName' THEN date_file_name
                    WHEN 'modified' THEN date_modified
                    WHEN 'created'  THEN date_created
                    ELSE date_exif
                END
                """)

            // 3. A JPEG/HEIC lacking the date reads it from its RAW partner,
            //    in the same date column (same shot, same date source).
            try database.execute("""
                UPDATE photos AS shown SET effective_date = (
                    SELECT CASE s.date_source
                        WHEN 'fileName' THEN raw.date_file_name
                        WHEN 'modified' THEN raw.date_modified
                        WHEN 'created'  THEN raw.date_created
                        ELSE raw.date_exif
                    END
                    FROM photos AS raw JOIN sources s ON s.id = raw.source_id
                    WHERE raw.pair_primary = shown.id
                    ORDER BY raw.id LIMIT 1)
                WHERE shown.effective_date IS NULL
                  AND EXISTS (SELECT 1 FROM photos AS raw WHERE raw.pair_primary = shown.id)
                """)

            // 4. Visible: dated, from an enabled online source, not a RAW
            //    hidden behind its partner, and the earliest-dated copy in
            //    its group (ties: shortest path, then alphabetical). Only
            //    eligible rows compete, so a disabled source's copy never
            //    hides an enabled source's copy, and an undated copy never wins.
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

    /// Links rows that are the same photo, and returns each linked row's
    /// group (its smallest ID). Three kinds of link:
    /// - identical content (same SHA-256)
    /// - the same file reached through nested folder sources
    /// - the same capture second and pixel size, between a Photos library
    ///   row and a folder row (exports of library photos). Two library rows
    ///   are never linked this way: burst shots share a second and a size.
    private func duplicateGroups() throws -> [Int64: Int64] {
        var unionFind = UnionFind()

        let sameContent = try database.prepare("""
            SELECT id, content_hash FROM photos
            WHERE content_hash IN (
                SELECT content_hash FROM photos WHERE content_hash IS NOT NULL
                GROUP BY content_hash HAVING COUNT(*) > 1)
            ORDER BY content_hash
            """)
        try sameContent.bind([])
        var first: (hash: Data, id: Int64)?
        while try sameContent.step() {
            let id = sameContent.int64(0)
            let hash = sameContent.blob(1) ?? Data()
            if let first, first.hash == hash {
                unionFind.union(first.id, id)
            } else {
                first = (hash, id)
            }
        }

        let sameFile = try database.prepare("""
            SELECT inner_row.id, outer_row.id
            FROM photos AS inner_row JOIN photos AS outer_row
              ON outer_row.source_id = ? AND outer_row.locator = ? || inner_row.locator
            WHERE inner_row.source_id = ?
            """)
        for pair in try nestedSourcePairs() {
            try sameFile.bind([.int(pair.outer), .text(pair.prefix), .int(pair.inner)])
            while try sameFile.step() {
                unionFind.union(sameFile.int64(0), sameFile.int64(1))
            }
        }

        let sameCapture = try database.prepare("""
            SELECT a.id, b.id
            FROM photos a
            JOIN sources sa ON sa.id = a.source_id AND sa.kind = 'photos'
            JOIN photos b ON b.date_exif = a.date_exif AND b.id <> a.id
             AND ((b.pixel_w = a.pixel_w AND b.pixel_h = a.pixel_h)
               OR (b.pixel_w = a.pixel_h AND b.pixel_h = a.pixel_w))
            JOIN sources sb ON sb.id = b.source_id AND sb.kind = 'folder'
            WHERE a.date_exif IS NOT NULL AND a.pixel_w IS NOT NULL
            """)
        try sameCapture.bind([])
        while try sameCapture.step() {
            unionFind.union(sameCapture.int64(0), sameCapture.int64(1))
        }

        return unionFind.groups()
    }

    /// Folder sources whose root sits inside another folder source's root.
    /// `prefix` is the inner root's path relative to the outer root, with a
    /// trailing "/".
    private func nestedSourcePairs() throws -> [(outer: Int64, inner: Int64, prefix: String)] {
        let folders = try sources().filter { $0.kind == .folder }.compactMap { source in
            source.rootPath.map { (id: source.id, root: $0.hasSuffix("/") ? $0 : $0 + "/") }
        }
        var pairs: [(outer: Int64, inner: Int64, prefix: String)] = []
        for outer in folders {
            for inner in folders where inner.id != outer.id && inner.root.hasPrefix(outer.root) {
                pairs.append((outer.id, inner.id, String(inner.root.dropFirst(outer.root.count))))
            }
        }
        return pairs
    }

    /// Recomputes RAW+JPEG pairs for one source. See `PairBuilder`.
    func updatePairs(sourceID: Int64) throws {
        let query = try database.prepare("SELECT id, locator, is_raw FROM photos WHERE source_id = ?")
        try query.bind([.int(sourceID)])
        var files: [PairBuilder.File] = []
        while try query.step() {
            files.append(PairBuilder.File(id: query.int64(0), locator: query.text(1), isRaw: query.int64(2) != 0))
        }
        let pairs = PairBuilder.pairs(in: files)
        try database.transaction {
            try database.prepare("UPDATE photos SET pair_primary = NULL WHERE source_id = ?").run([.int(sourceID)])
            let setPair = try database.prepare("UPDATE photos SET pair_primary = ? WHERE id = ?")
            for (raw, partner) in pairs {
                try setPair.run([.int(partner), .int(raw)])
            }
        }
    }
}

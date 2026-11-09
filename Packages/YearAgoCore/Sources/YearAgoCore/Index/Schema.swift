/// Database schema and migrations. See implementation plan section 6.
enum Schema {
    /// The newest schema version. Bump it and add a migration step to change
    /// the schema.
    static let currentVersion = 1

    /// Brings `database` up to `currentVersion`.
    static func migrate(_ database: Database) throws {
        let version = try database.userVersion
        guard version < currentVersion else { return }
        try database.transaction {
            if version < 1 {
                try database.execute(version1)
            }
            try database.setUserVersion(currentVersion)
        }
    }

    private static let version1 = """
        CREATE TABLE meta (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );

        CREATE TABLE sources (
          id          INTEGER PRIMARY KEY,
          kind        TEXT    NOT NULL,           -- 'photos' | 'folder'
          name        TEXT    NOT NULL,
          root_path   TEXT,                       -- folders: resolved path, to recognise the folder
          bookmark    BLOB,                       -- folders: security-scoped bookmark
          date_source TEXT    NOT NULL,           -- DateSourceKind raw value
          is_enabled  INTEGER NOT NULL DEFAULT 1,
          is_online   INTEGER NOT NULL DEFAULT 1,
          sort_order  INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE photos (
          id             INTEGER PRIMARY KEY,
          source_id      INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
          locator        TEXT    NOT NULL,        -- relative path, or Photos localIdentifier
          file_name      TEXT,
          byte_size      INTEGER,
          fs_mtime       INTEGER,                 -- modification time in ms, for change detection
          date_file_name INTEGER,                 -- LocalDateTime seconds, or NULL
          date_modified  INTEGER,
          date_created   INTEGER,
          date_exif      INTEGER,
          pixel_w        INTEGER,
          pixel_h        INTEGER,
          is_raw         INTEGER NOT NULL DEFAULT 0,
          content_hash   BLOB,
          pair_primary   INTEGER REFERENCES photos(id) ON DELETE SET NULL,
          dup_group      INTEGER,
          effective_date INTEGER,
          is_visible     INTEGER NOT NULL DEFAULT 0,
          UNIQUE (source_id, locator)
        );

        CREATE INDEX photos_visible_date ON photos(is_visible, effective_date);
        CREATE INDEX photos_size         ON photos(byte_size);
        CREATE INDEX photos_capture      ON photos(date_exif, pixel_w, pixel_h);
        """
}

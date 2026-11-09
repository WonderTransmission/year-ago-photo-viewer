# Implementation Plan: Year Ago Photo Viewer

Status: Draft 1
Companion to: [proposal.md](proposal.md) (Draft 6)

## 1. Overview

The build runs in 11 milestones, M0 to M10. Each one ends in a working,
tested state and fits in one pull request. Core logic comes first, in a Swift
package with no UI code. The app, menu bar item, and widget then sit on top
of it.

Toolchain: Xcode 27, Swift 6 language mode, macOS 26 deployment target.
Dependencies: Apple frameworks only.

## 2. Key technical choices

These refine the proposal where it left a choice open.

- **Database.** SQLite through the system `SQLite3` module, with a thin Swift
  wrapper. It handles 100,000+ rows well and supports window functions, which
  the duplicate rules need. SwiftData was the alternative. It makes bulk
  updates and custom SQL awkward.
- **One database.** A single file holds every source, keyed by `source_id`.
  Each source's rows still act as its own index. One file makes
  cross-source duplicate queries simple.
- **Photos is indexed too.** Proposal 6.4 skipped indexing Photos. Merging
  sources, counting years, and finding duplicates all need Photos rows next to
  folder rows. So the app indexes asset metadata, which PhotoKit returns
  quickly. File names are fetched lazily, only when a source uses the File
  name date.
- **Floating local time.** Every stored date is a wall-clock time with no
  time zone. It is stored as seconds since 1970-01-01 00:00:00, read as if in
  UTC. File and Photos timestamps are converted to the Mac's current time
  zone when indexed. EXIF and file-name dates are stored as written.
- **Project file.** A hand-made Xcode project using folder-synchronized
  groups. New source files then need no project file edits. No XcodeGen or
  other generator.
- **Tests.** Swift Testing (`import Testing`). "Today", the calendar, and the
  time zone are injected, so date tests never depend on the real clock.
- **Fixtures.** Tests generate their images at run time with ImageIO, in a
  temporary folder. The repo holds no image files.

## 3. Repository layout

```
.
├── LICENSE                         MIT, © WonderTransmission
├── README.md
├── .gitignore
├── Config/
│   ├── Base.xcconfig               shared build settings
│   ├── Local.xcconfig.template     placeholders; copied to Local.xcconfig
│   └── Local.xcconfig              ignored by git
├── YearAgoPhotoViewer.xcodeproj
├── App/                            app target
│   ├── YearAgoPhotoViewerApp.swift
│   ├── Model/                      observable view models
│   ├── Views/                      main window, Sources panel, settings
│   ├── MenuBar/                    MenuBarExtra content
│   ├── Platform/                   PhotoKit, bookmarks, FSEvents, thumbnails
│   ├── Resources/                  asset catalog
│   ├── Info.plist
│   └── App.entitlements
├── Widget/                         WidgetKit extension target
│   ├── YearAgoWidget.swift
│   ├── Info.plist
│   └── Widget.entitlements
├── Packages/
│   └── YearAgoCore/                Swift package, no UI, no PhotoKit
│       ├── Package.swift
│       ├── Sources/YearAgoCore/
│       └── Tests/YearAgoCoreTests/
└── docs/
```

`YearAgoCore` holds everything that can run in `swift test`. Code that needs
PhotoKit, the sandbox, or a running app lives in `App/Platform`, behind
protocols defined in the core package.

## 4. Configuration and signing

`Config/Local.xcconfig` holds every personal value. Git ignores it. The
template ships with placeholders:

```
// Copy to Local.xcconfig and fill in.
DEVELOPMENT_TEAM =
BUNDLE_ID_PREFIX = com.example
APP_GROUP_ID = group.com.example.yearago
```

`Base.xcconfig` includes it with `#include? "Local.xcconfig"`. Bundle IDs
derive from the prefix:

- App: `$(BUNDLE_ID_PREFIX).YearAgoPhotoViewer`
- Widget: `$(BUNDLE_ID_PREFIX).YearAgoPhotoViewer.Widget`

Entitlement files read `$(APP_GROUP_ID)`, so they hold no personal values.

**Signing note.** M0–M8 build fine with ad hoc signing and no team. The
widget (M10) needs an App Group, which needs a development team. A free
personal team works for local use. The README explains this.

### Entitlements

| Entitlement                                         | App | Widget |
|-----------------------------------------------------|-----|--------|
| `com.apple.security.app-sandbox`                    | ✓   | ✓      |
| `com.apple.security.files.user-selected.read-only`  | ✓   |        |
| `com.apple.security.files.bookmarks.app-scope`      | ✓   |        |
| `com.apple.security.personal-information.photos-library` | ✓ |     |
| `com.apple.security.application-groups`             | ✓   | ✓      |

There is no network entitlement. `Info.plist` sets
`NSPhotoLibraryUsageDescription`. It also registers a `yearago://` URL scheme,
which the widget uses to open a photo.

## 5. Core model (`YearAgoCore`)

### 5.1 Main types

```swift
/// Wall-clock time with no time zone. Seconds since 1970-01-01 00:00:00.
public struct LocalDateTime: Comparable, Hashable, Sendable {
    public var seconds: Int64
}

public enum DateSourceKind: String, CaseIterable, Sendable {
    case fileName, modified, created, exif
}

public enum SourceKind: Sendable {
    case photosLibrary
    case folder(bookmark: Data)
}

public struct PhotoSourceConfig: Identifiable, Sendable {
    public var id: Int64
    public var kind: SourceKind
    public var name: String
    public var dateSource: DateSourceKind
    public var isEnabled: Bool
}

public struct DateWindow: Sendable {
    public var yearsAgo: Int
    public var range: ClosedRange<LocalDateTime>
}

public struct ViewerSettings: Sendable {
    public var windowWeeks: Int          // 1...6
    public var showEmptyYears: Bool      // default true
    public var defaultDateSource: DateSourceKind
}
```

### 5.2 Modules inside the package

| Folder        | Contents                                                         |
|---------------|------------------------------------------------------------------|
| `Window/`     | `WindowCalculator`, `YearNavigator`                              |
| `Dates/`      | `FileNameDateParser`, `ExifDateReader`, `FileDateReader`         |
| `Scanning/`   | `FolderScanner`, file type rules, RAW and video lists            |
| `Grouping/`   | `PairBuilder` for RAW+JPEG                                       |
| `Dedup/`      | `ContentHasher`, `DuplicateGrouper` (union-find)                 |
| `Index/`      | `Database`, schema, migrations, `PhotoIndex` queries             |
| `Snapshot/`   | Widget manifest types, shared by app and widget                  |
| `Protocols/`  | `PhotoLibraryProviding`, `Clock`, and other seams for platform code |

The widget target links only `Snapshot/` types. A second, tiny library
product, `YearAgoSnapshot`, keeps the widget binary small.

## 6. Database schema

```sql
CREATE TABLE sources (
  id            INTEGER PRIMARY KEY,
  kind          TEXT    NOT NULL,          -- 'photos' | 'folder'
  name          TEXT    NOT NULL,
  bookmark      BLOB,                      -- folders only
  date_source   TEXT    NOT NULL,          -- DateSourceKind raw value
  is_enabled    INTEGER NOT NULL DEFAULT 1,
  is_online     INTEGER NOT NULL DEFAULT 1,
  sort_order    INTEGER NOT NULL
);

CREATE TABLE photos (
  id             INTEGER PRIMARY KEY,
  source_id      INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  locator        TEXT    NOT NULL,         -- relative path, or Photos localIdentifier
  file_name      TEXT,                     -- may be NULL until fetched (Photos)
  byte_size      INTEGER,
  fs_mtime       INTEGER,                  -- raw mtime, for change detection
  date_file_name INTEGER,                  -- LocalDateTime seconds, or NULL
  date_modified  INTEGER,
  date_created   INTEGER,
  date_exif      INTEGER,
  pixel_w        INTEGER,
  pixel_h        INTEGER,
  is_raw         INTEGER NOT NULL DEFAULT 0,
  content_hash   BLOB,                     -- only for same-size candidates
  pair_primary   INTEGER REFERENCES photos(id),  -- set on a RAW hidden behind its JPEG
  dup_group      INTEGER,                  -- union-find root id
  effective_date INTEGER,                  -- derived; see 6.1
  is_visible     INTEGER NOT NULL DEFAULT 0,
  UNIQUE (source_id, locator)
);

CREATE INDEX photos_visible_date ON photos(is_visible, effective_date);
CREATE INDEX photos_size         ON photos(byte_size);
CREATE INDEX photos_capture      ON photos(date_exif, pixel_w, pixel_h);
```

### 6.1 Derived columns

Two derived columns make every viewer query a simple range scan.
`refreshDerived()` recomputes them after any scan, source change, or date
setting change.

1. **`effective_date`.** Pick the date column named by the source's
   `date_source`. For a JPEG with a RAW partner, fall back to the RAW's date
   in the same column (proposal 4.7).
2. **`is_visible`.** True when all of these hold:
   - the source is enabled and online
   - the row is not a hidden RAW partner
   - `effective_date` is not NULL
   - the row wins its `dup_group`

The winner uses a window function:

```sql
ROW_NUMBER() OVER (
  PARTITION BY dup_group
  ORDER BY effective_date, length(locator), locator
) = 1
```

Only rows that pass the first three checks take part. A disabled source's
copies therefore never block a copy from an enabled source.

### 6.2 Viewer queries

- **Photos in a window.** `WHERE is_visible = 1 AND effective_date BETWEEN ?
  AND ? ORDER BY effective_date`.
- **Oldest photo.** `SELECT MIN(effective_date) WHERE is_visible = 1`.
- **Counts per year.** One indexed `COUNT(*)` per N. N rarely exceeds 30, so
  this is fast.

## 7. Milestones

Each milestone lists its tasks and a "done when" check.

### M0 — Repository bootstrap

- `git init`. Add `LICENSE` (MIT, © 2026 WonderTransmission), `.gitignore`,
  and a README stub.
- Add `Config/` files, with `Local.xcconfig` ignored.
- Create the Xcode project with the app target and folder-synchronized
  groups.
- Create the `YearAgoCore` package and link it to the app.
- Add a placeholder window that says "Hello".

**Done when:** `xcodebuild` builds the app, `swift test` runs in the package,
and `git status` shows no personal values.

### M1 — Window math and date extraction

- `WindowCalculator`: N, W, today, calendar → `DateWindow`. Feb 29 maps to
  Feb 28.
- `FileNameDateParser`: the six patterns in proposal 4.5. Reject impossible
  dates. Handle 12-hour times with AM/PM.
- `ExifDateReader`: read `DateTimeOriginal` with ImageIO. Fall back to
  `DateTimeDigitized`, then TIFF `DateTime`. All three are capture-time
  fields from the same EXIF source.
- `FileDateReader`: modified and created dates from `URLResourceValues`.
- Tests for each, using generated JPEGs with chosen EXIF values.

**Done when:** every case in proposal section 8 for window math, file names,
and EXIF passes.

### M2 — Folder scanning and a basic viewer

- `FolderScanner`: walk a folder with `FileManager.enumerator`. Skip hidden
  files and packages. Classify each file as image, RAW, video, or other.
  Ignore videos, `.xmp`, and `.aae`.
- In memory for now: scan one folder, take EXIF dates, filter to N = 1.
- Main window: current photo, photo arrows, caption, counter, end card.
- Folder picker using `NSOpenPanel`. Store a security-scoped bookmark.
- `ThumbnailLoader`: `CGImageSourceCreateThumbnailAtIndex`, cached in
  `NSCache`. Load full images off the main actor.

**Done when:** choosing a folder of test photos shows last year's week, and
arrow keys step through it.

### M3 — Navigation and settings

- `YearNavigator`: next and previous year, with and without empty years.
  Includes the "no year has photos" case.
- Header text: "2 years ago · 1–8 Nov 2024 · 12 of 37".
- Year controls, ⌘[ and ⌘], and the year picker.
- Window menu, 1–6 weeks.
- Empty panel. "Show years with no photos" in Settings and the View menu.
- Filmstrip.
- Persist settings in `UserDefaults`.

**Done when:** navigation tests pass and the UI matches proposal section 5.

### M4 — Persistent index

- `Database` wrapper: open, migrate, prepared statements, transactions.
- Schema from section 6. Store the database in Application Support.
- Index writer: batch inserts of 1,000 rows per transaction.
- Incremental rescan: compare `byte_size` and `fs_mtime`. Delete rows for
  missing files.
- `FSEventStream` watcher. Debounce events by 2 seconds, then rescan the
  affected folders.
- Progress reporting from the scanner to the UI.
- Replace the in-memory list from M2 with index queries.

**Done when:** a 100,000-file synthetic folder indexes once, then relaunches
without a rescan. A file added while running appears within a few seconds.

### M5 — Multiple sources

- `sources` table. Add, remove, rename, enable, disable, and reorder.
- Per-source date setting. The toolbar menu sets the default for new sources.
  It also offers "Apply to all sources".
- Sources panel, as in proposal 5.1.
- Offline detection: a bookmark that fails to resolve, or a missing volume.
  Mark the source offline and keep its rows.
- Nested folder sources: skip rows whose real path is already indexed by
  another source.
- `refreshDerived()` with the `effective_date` and `is_visible` rules. Duplicate
  groups are a stub for now: every row is its own group.

**Done when:** two folders with different date settings merge into one
timeline. Toggling a source updates the view at once.

### M6 — RAW pairs and duplicates

- `PairBuilder`: same folder, same base name ignoring case, one RAW plus one
  JPEG or HEIC. Set `pair_primary` on the RAW. Show a "RAW+JPEG" badge.
- Lone RAW files show normally. Check that ImageIO decodes CR2, CR3, NEF,
  ARW, RAF, ORF, and DNG on macOS 26.
- `ContentHasher`: SHA-256 with CryptoKit, streamed in 1 MB chunks. Hash only
  rows whose `byte_size` is shared, and only once per file version.
- `DuplicateGrouper`: union-find over two link types:
  - **Same hash.** Folder files with equal `content_hash`.
  - **Same capture.** Equal `date_exif` (or Photos `creationDate`) to the
    second, and equal pixel size. Needed for Photos-to-folder matches.
- Write `dup_group`, then call `refreshDerived()`.

**Done when:** the pairing and duplicate tests in proposal section 8 pass,
including earliest-date winners and tie-breaks.

### M7 — Photos library source

- `PhotoLibraryProviding` protocol in the core package. The PhotoKit version
  lives in `App/Platform`, so core tests use a fake.
- Request access when the user adds the Photos library. Handle denied and
  limited access with a clear message.
- Index image assets only (`mediaType == .image`). Store `localIdentifier`,
  `creationDate`, `modificationDate`, and pixel size. `creationDate` fills
  both `date_created` and `date_exif`, as in proposal 4.4.
- File name date: fetch `PHAssetResource.originalFilename` in the background,
  only when this source uses the File name date. Cache the result.
- Keep the index current with `PHPhotoLibraryChangeObserver`.
- Thumbnails and full images through `PHCachingImageManager`. Live Photos
  return their still key frame by default.

**Done when:** the manual checklist passes against a real library, including
a Live Photo and a RAW+JPEG asset.

### M8 — Polish and v1 release

- Keyboard shortcuts in the menus. VoiceOver labels on all controls.
- Empty, loading, error, and offline states.
- "Show in Finder" for folder photos. "Show in Photos" for library photos.
- README: features, build steps, `Local.xcconfig` setup, privacy notes, and
  screenshots made from generated sample photos.
- Privacy check: search the repo for home paths, user names, and team IDs.

**Done when:** a fresh clone builds by following the README alone. Tag
`v1.0`.

### M9 — Menu bar item

- `MenuBarExtra` with `.window` style. Show one photo from the current
  window at N = 1, or the nearest year with photos when empty years are
  hidden.
- Shuffle, the summary line, and "Open in Viewer".
- A Settings toggle to hide the item.

**Done when:** the popover matches proposal 5.2 and follows every setting.

### M10 — Widget

- Add the widget extension target and the App Group.
- `WidgetSnapshotter` in the app. It writes thumbnails (max 600 px JPEG) and
  `manifest.json` to the App Group container. It runs at launch, after
  midnight, and on settings or index changes. Then it calls
  `WidgetCenter.shared.reloadAllTimelines()`.
- Widget timeline: one entry now, and one after the next midnight.
- Small, medium, and large layouts, including empty tiles.
- Taps open `yearago://photo/<id>`. The app jumps to that photo.
- A stale snapshot shows its date.

**Done when:** all three sizes render from a snapshot, and tapping opens the
right photo.

## 8. Testing strategy

- **Unit tests.** Everything in `YearAgoCore`, run with `swift test`.
- **Database tests.** Each test uses a fresh in-memory SQLite database.
- **Fixture builder.** A test helper writes JPEG, HEIC, and PNG files with
  chosen EXIF dates, sizes, and file times. RAW pairing tests use empty files
  with RAW extensions, since pairing reads names only.
- **Scale test.** An opt-in test builds 100,000 tiny files and times a full
  index and a no-change rescan. It is skipped by default.
- **Manual checklist.** `docs/manual-test-checklist.md`, added in M7, covers
  PhotoKit, permissions, offline drives, the menu bar item, and the widget.

## 9. Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Time zone mismatch between EXIF and Photos `creationDate` | Some Photos-to-folder duplicates are missed | Accept for v1. A later version could allow a ±1 hour match with equal pixel size. |
| Mac time zone changes after indexing | File-time dates shift by the offset | Store the zone used. Re-derive file-time dates if it changes. |
| Fetching Photos file names is slow | First use of the File name date takes minutes on large libraries | Fetch in the background with progress. Cache the result. |
| Widget needs a development team | Ad hoc builds cannot show the widget | Document a free personal team in the README. The rest of the app works without one. |
| ImageIO cannot decode a RAW format | That RAW file shows a placeholder | Show the file name and a "can't preview" tile. Pairs still show the JPEG. |
| Hashing a large folder is slow | First index takes longer | Hash only same-size files. Run at low priority. Show progress. |

## 10. Definition of done for v1

- Proposal sections 4 and 5 work as written, except the menu bar item and
  widget.
- All unit tests pass. The manual checklist passes.
- The repo has no personal data. A fresh clone builds from the README.
- M9 and M10 follow as v1.1 and v1.2.

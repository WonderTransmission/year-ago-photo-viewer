# Plan: Other Photos Libraries as Sources

Status: done and released in 1.4 (steps 4.1, 4.2, 4.4, 4.5). Option 3.1 is
built. Option 3.3 (step 4.3) is deferred (section 5.2).
Trigger: users keep more than one `.photoslibrary`, for example an archive
library on an external drive. Only the system library can be a source today.

## 1. Goal

The user can add any `.photoslibrary` package as a source, in addition to
the system Photos library.

- **Any library.** It works whether or not the library is the system
  library. It works whether or not Photos has the library open.
- **Read-only.** The app never writes into the package. This rule follows the
  "no editing" non-goal in `proposal.md`.
- **Same experience.** Progress, stop and resume, and incremental updates
  work as they do for folders.
- **Sandboxed.** The app stays sandboxed, with a user-selected read-only
  bookmark.

## 2. What happens today

- **PhotoKit only.** `PhotoKitLibrary` uses `PHPhotoLibrary.shared()`. On
  macOS that is always the system library. No public API opens another one.
- **Packages skipped.** `FolderScanner` passes `.skipsPackageDescendants`. A
  folder source that contains a `.photoslibrary` ignores it, and a test
  checks this (`FolderScannerTests`).
- **Open panel.** `NSOpenPanel` shows a `.photoslibrary` as a single file.
  The folder picker can't select it.
- **Documented gap.** `proposal.md` §3 lists "Other Photos libraries" as a
  non-goal, because PhotoKit only reads the system library.

## 3. Options considered

### 3.1 Scan the package's `originals/` folder

Treat `<library>/originals/` as a folder tree and scan it with
`FolderScanner`. Libraries from before macOS 10.15 use `Masters/` instead.

- **Effort.** Smallest. Scanning, bookmarks, watching, and dedup all exist.
- **Dates.** EXIF and file dates work. Date fixes made in Photos are lost.
- **File names.** Originals are stored under UUID names. The File name date
  source is useless here.
- **Wrong content.** Recently Deleted and Hidden photos are included. Edits
  are not; the app shows originals.
- **Gaps.** Libraries set to "Optimize Mac Storage" lack many originals.

### 3.2 Read `database/Photos.sqlite`

Read the library's own database, as the open-source `osxphotos` tool does.
Implement it as a second `PhotoLibraryProviding`, keyed by `ZASSET.ZUUID`.

- **Fit.** Clean. The core protocol already abstracts the library. Date
  ranges, the index, and incremental changes work unchanged.
- **Accuracy.** Best. It gives adjusted dates and original file names. It can
  filter trashed and hidden assets and find edited renders.
- **Fragility.** The schema is private and changes with most macOS releases.
  It needs per-version handling.
- **Locking.** Photos keeps the database in WAL mode. Open it with
  `mode=ro`, which reads the WAL and writes nothing (spike step 3). Never
  use `immutable=1`: it ignores the WAL, and can miss every asset.
- **Changes.** There are no change notifications. The app must watch
  `database/` and resync.

### 3.3 Hybrid (deferred)

Use 3.1 as the base. When the database schema is recognised, layer its
metadata on top. When parsing fails, fall back to plain scanning.

This has the safest failure mode of the database options. A macOS update
can only lose the extra metadata, never the source. The spike found it adds
little for now, so it is deferred (section 5.2).

### 3.4 Ruled out

- **Switching the system library.** It needs a Photos relaunch with ⌥ held.
  It is hostile and changes the user's setup.
- **AppleScript or `MLMediaLibrary`.** Both only see the library Photos has
  open.
- **Bundling `osxphotos`.** It is Python, an external dependency. It doesn't
  fit the build-from-source model.

## 4. Work plan

### 4.1 Spike: access and layout (done; results in 6.2)

Answer the unknowns before writing product code. Use a throwaway branch.

1. **Open panel.** Let `NSOpenPanel` select a `.photoslibrary`. Try
   `allowedContentTypes` with `com.apple.photos.library`. Fall back to
   `canChooseFiles` with a package filter.
2. **TCC.** Read `originals/` from a sandboxed debug build. Test three
   libraries:
   - the system library;
   - a second library in `~/Pictures`;
   - a library on an external drive.

   Note which ones trigger the Photos privacy prompt, and which are refused.
3. **Database.** Open `Photos.sqlite` read-only with `immutable=1`. Test
   it with Photos closed, and again with that library open in Photos.
4. **Layout.** Record which folders hold originals for libraries from
   different macOS versions. Check `originals/`, `Masters/`, and any
   Shared Library `scopes/` folders.
5. **Identity.** Check that an original's file name, minus its extension,
   is the asset UUID. Check that `PHAsset.fetchAssets(withLocalIdentifiers:)`
   finds `<UUID>/L0/001` when the package is the system library, and finds
   nothing when it isn't. This is the detection in 4.2 step 7.
6. **Renders.** Edit a photo, then revert it. Record what appears and
   disappears in `resources/renders/` each time. This answers the stale
   render question in section 6.
7. **Database cost.** Count the schema versions found in steps 3 and 4.
   Note how much the dates, flags, and names differ from file-only data.
   This is the input to the 3.3 decision.

Record the results in section 6. Use counts and paths relative to the
package only, so they contain no personal data.

### 4.2 Library package source, files only (done)

Ship option 3.1 as a new source kind.

Built as planned, with these differences:

- **No migration.** `sources.kind` is free text, so the new kind needed no
  schema change. An older app version would read the package as a plain
  folder.
- **Warning only with both sources.** The system library check runs only
  when the Photos Library source exists. Without it, adding the system
  library as a file is a fine way to use it, with no Photos permission.
- **Duplicates hidden.** If both sources exist, matching photos show once.
  The capture-time match now links Photos Library rows to any file-based
  row, not only folders. A later change also links them by asset ID: an
  original named `<UUID>.<ext>` matches the asset `<UUID>/L0/001`. This
  catches photos with no EXIF date, which the capture-time match misses.
- **Watching.** The watcher covers only the originals folders. Photos writes
  to the rest of the package (its database, thumbnails) constantly.
- **Debug.** `-DebugFolderPath` adds a `.photoslibrary` path as a library
  source.

1. **Core: source kind.** Add `SourceRecord.Kind.libraryPackage`. It stores
   the package path and a bookmark, like a folder. Add a schema migration.
2. **Core: scan roots.** Add a helper that lists the originals folders
   inside a package: `originals/`, `Masters/`, and
   `scopes/collectionshare/originals/`, where they exist. See section 6.3
   about that last folder.
   Never scan the package root; it also holds thumbnails and other derived
   copies (spike: 13,023 images found there, versus 64 originals).
3. **Core: date sources.** Hide the File name date for this kind. The
   default becomes EXIF.
4. **App: adding.** Add an "Add Photos Library File…" button to
   `SourcesView`. It opens the panel from 4.1 and calls a new
   `addLibraryPackages(_:)` on `ViewerModel`. It shares bookmark code with
   `addFolders(_:)`.
5. **App: syncing.** Sync and watch the originals folder the same way as a
   folder source. `FolderAccess` keeps the bookmark on the package itself.
6. **App: labels.** Show the package name without `.photoslibrary`. Use the
   Photos icon in the Sources list.
7. **App: system library warning.** When a package is added, sample a few
   original file names. Look them up in PhotoKit as `<UUID>/L0/001`. If
   they are found, the package is the system library. Warn the user, and
   let them add it anyway. Skip the check when Photos access isn't granted;
   the app never asks for access just to run it.
8. **Tests.** Build a fake package in a temporary directory, with both
   layouts. Use generated images only, never real photos. Cover scanning,
   the missing-originals case, and the migration.

### 4.3 Database metadata overlay (deferred)

Add option 3.2 on top of 4.2. Build this only if section 5.2's conditions
are met later.

1. **Core: reader.** Add a `PhotosDatabaseReader` in the core package. It
   maps the file path of each original to its metadata:
   - creation date (adjusted by the user);
   - original file name;
   - trashed and hidden flags.
2. **Core: schema guard.** Check the tables and columns before reading. On
   any mismatch, return nothing and log the schema version.
3. **Core: use it.** During sync, skip trashed and hidden files. Use the
   database date as the Created date. Enable the File name date when names
   are available.
4. **App: changes.** Also watch `database/`. Resync the source when it
   changes, with the existing debounce.
5. **Tests.** Use a small made-up `Photos.sqlite` fixture with only the
   tables the reader uses. Cover every schema version from 4.1.

### 4.5 Show edited photos (done)

Choice 2 from section 6.1: show Photos' edited copy, found by file name.

1. **Core: lookup.** `PhotosLibraryPackage.editedRender(forOriginal:in:)`
   maps `…/originals/<X>/<UUID>.<ext>` to `…/resources/renders/<X>/`. It
   returns the image there named `<UUID>_1_201_a.*`, or else any image
   named `<UUID>_*`. `Masters/` libraries get none.
2. **Core: timeline.** Library-file photos carry their package
   (`PhotoItem.libraryPackage`). `PhotoItem.displayURL()` returns the
   render if there is one, else the original.
3. **App: loading.** `ImageRepository` loads `displayURL()`. So the viewer,
   filmstrip, menu bar, and widget all show the edit.
4. **Unchanged.** Dates, duplicates, and the index still use the original.
   The lookup runs when a photo is loaded, so new edits and reverts need no
   re-index.
5. **Tests.** The lookup in both originals folders, the preferred name,
   reverts, and `Masters/`.

Known limit: a photo edited again keeps its render's file name. The app may
show the older edit until the image leaves its cache, or until relaunch.

### 4.4 Docs (done)

- **Proposal.** Remove "Other Photos libraries" from the non-goals. Describe
  the new source kind.
- **README.** Explain the two ways to add a library. Note what the
  file-only mode misses.
- **Checklist.** Add manual steps to `manual-test-checklist.md`, using the
  libraries from 4.1.

## 5. Decisions

### 5.1 Made

- **Option 3.1.** Build the file-only source (4.2) whatever the spike
  finds.
- **Never write.** The app opens the package read-only. It never creates
  files in it, including SQLite `-shm` or `-wal` files.
- **Made-up test data.** Test packages, images, and databases are
  generated. No real photos or real library databases go in the repo.
- **Warn on the system library.** If a package is detectably the system
  library, warn when it is added (4.2 step 7).
- **New kind, not a folder.** A separate kind lets the app pick the scan
  root and hide the File name date. A plain folder source can't.
- **Defer 3.3.** On the large on-disk library, files alone found 98.6% of
  images. Nothing was trashed or hidden. Edits can be found by file name
  (6.1). So the database reader isn't worth its fragility yet.

### 5.2 When to revisit 3.3

Build 4.3 later only if both of these hold:

- **It's needed.** File-only mode misses enough to matter. For example,
  many photos have adjusted dates, or Recently Deleted and Hidden photos
  show up.
- **It's contained.** The spike finds few schema versions. The reader stays
  in one core file with its own tests, and nothing else depends on it.

If 3.3 is built, it must fail soft. An unknown schema loses metadata, not
photos.

## 6. Open questions

- **Shared photos.** See 6.3.
- **Edits.** See 6.1.

### 6.1 Edits

Photos never changes an original. Crops, rotations, filters, and exposure
fixes are saved as instructions. Photos also writes a full-size rendered
copy to `resources/renders/`. The render's file name starts with the asset
UUID, for example `<UUID>_1_201_a.jpeg`.

The two source kinds would show different things:

- **System library.** PhotoKit returns the edited version
  (`options.version = .current` in `PhotoKitLibrary.swift`). Users see their
  crops and fixes.
- **Package source (3.1).** It scans `originals/` only. Users see the
  uncropped, unfixed photo. A photo straightened or rotated in Photos shows
  the old way.

Choices:

1. **Originals only.** Simplest. It differs from the system library source.
   Explain the difference in the README.
2. **Prefer the render, matched by file name.** Index the original, but
   display the render when one exists for the same UUID. This works without
   the database. Risk: a render may stay behind after the user reverts an
   edit. The app would then show an edit that no longer exists. 4.1 step 6
   checks this.
3. **Prefer the render, confirmed by the database.** Same as 2, but only
   when the database says the asset has edits. This is correct, but needs
   3.3.

Dates come from the original in all three, so the day a photo appears on
doesn't change. Only the picture shown does.

Decision: choice 2, built in step 4.5.

Spike result: renders exist while photos are edited (517 render images for
521 edited assets), and none remained after a revert (6.2, step 6). So
choice 2 is safe, and works without 3.3.

### 6.2 Spike results (2026-11-14)

Two Macs. The probe was a sandboxed, ad-hoc signed debug build. It logged
counts only. Libraries tested:

- **System.** The system library, about 10,000 assets. Optimize Mac Storage
  is on, so few originals are on disk.
- **TEST.** A new library in `~/Pictures`, with 4 photos. One was edited,
  then reverted.
- **Legacy.** An old, empty library with a `Masters/` folder only (shell
  check only).
- **External.** A 29 GB library on a USB hard-drive enclosure, about 11,000
  assets, all stored locally. It is the system library on its Mac.

| Step | Result |
|---|---|
| 1. Open panel | Works. `allowedContentTypes = [UTType("com.apple.photos.library")]` selects the package. A read-only security-scoped bookmark is created. |
| 2. TCC | No prompt, and no Photos permission needed, for either library in `~/Pictures`. This includes the system library. The user-selected bookmark is enough. External: all originals were read before any Photos prompt; no removable-volume prompt. |
| 3. Database | `mode=ro` reads both libraries in the sandbox, including WAL data. `immutable=1` found 0 of 4 assets in TEST, whose data was all in the WAL. In External, both modes agreed (WAL already checkpointed). Nothing was written to `database/` in any run. |
| 4. Layout | Own photos: `originals/<hex>/<UUID>.<ext>`. `scopes/collectionshare/originals/<hex>/`, probably shared content (6.3). Shared albums: `scopes/cloudsharing/data/<id>/`. Live Photo videos: `<UUID>_3.mov`, already ignored. The legacy library uses `Masters/`. |
| 5. Identity | Every original's file name is its asset UUID (10,347 of 10,347 in System). PhotoKit found 5 of 5 System samples as `<UUID>/L0/001`, 5 of 5 External samples (correct: it is that Mac's system library), and 0 of 4 TEST samples. The check needs Photos permission. |
| 6. Renders | After a revert, `resources/renders/` was empty. The database still had an adjustment timestamp and a leftover `ZUNMANAGEDADJUSTMENT` row. External: 521 assets edited, 517 render images. |
| 7. Database cost | Drift already shows: `ZHASADJUSTMENTS`, used by older tools, is gone; `ZADJUSTMENTSSTATE` replaces it. External: the database lists 10,904 images; `originals/` holds 10,747 (98.6%). No trashed or hidden photos. Adjusted dates were not measured. |
| Scan time | External: `originals/` took 52 s on the USB hard drive. The package root held 34,420 images, mostly derivatives. |

Consequences for the plan:

- **Optimised libraries.** On an iCloud library with Optimize Mac Storage,
  3.1 finds only the originals on disk. Here that was 64 files, while the
  database lists about 720 images outside shared albums. (PhotoKit counts
  only 13 of those as the user's own; see 6.3.) The Sources panel says
  so in its tooltip. 3.3 could count the missing ones from the database.
- **3.3 deferred.** See 5.1. Revisit if photos show on the wrong day
  because their dates were fixed in Photos.
- **Warning matters.** The motivating external library is a system library.
  Adding it as a package would duplicate the PhotoKit source, so 4.2 step 7
  is needed.

### 6.3 Shared photos (future)

The spike labelled `scopes/collectionshare/originals/` as the iCloud Shared
Library. Testing on the system library (2026-11-14) cast doubt on that:

- **Not in PhotoKit.** Its 51 originals aren't in PhotoKit's user library.
  PhotoKit returned only the 13 photos in `originals/`.
- **Different type.** Photos' database gives them saved-asset type 16. The
  photos in `originals/` have type 3.

So they're probably shared content from other people, like shared albums.
The Photos Library source skips shared albums (9,215 images on that Mac).

Decision for now: keep scanning the folder. A library file may therefore
show more photos than the Photos Library source does.

Future: showing shared photos (shared albums, and this folder) may become a
feature, possibly optional, for both source kinds. Shared-album files live
in `scopes/cloudsharing/data/`, at reduced size.

The probe code is not kept in the repo. It was a throwaway DEBUG build that
logged counts under subsystem `YearAgoPhotoViewer`, category `probe`.

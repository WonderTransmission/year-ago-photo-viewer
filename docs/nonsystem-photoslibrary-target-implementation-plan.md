# Plan: Other Photos Libraries as Sources

Status: proposed; step 4.1 (spike) to do. Option 3.1 is chosen. Whether to
add 3.3 is decided after the spike (section 5).
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
- **Locking.** Photos keeps the database in WAL mode. A read-only bookmark
  can't create the `-shm` file. The app must open with `immutable=1` or read
  a temporary copy. Both can return slightly stale data.
- **Changes.** There are no change notifications. The app must watch
  `database/` and resync.

### 3.3 Hybrid (undecided)

Use 3.1 as the base. When the database schema is recognised, layer its
metadata on top. When parsing fails, fall back to plain scanning.

This has the safest failure mode of the database options. A macOS update
can only lose the extra metadata, never the source. Section 5 lists what
decides whether it is worth building.

### 3.4 Ruled out

- **Switching the system library.** It needs a Photos relaunch with ⌥ held.
  It is hostile and changes the user's setup.
- **AppleScript or `MLMediaLibrary`.** Both only see the library Photos has
  open.
- **Bundling `osxphotos`.** It is Python, an external dependency. It doesn't
  fit the build-from-source model.

## 4. Work plan

### 4.1 Spike: access and layout (to do)

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

### 4.2 Library package source, files only (to do)

Ship option 3.1 as a new source kind.

1. **Core: source kind.** Add `SourceRecord.Kind.libraryPackage`. It stores
   the package path and a bookmark, like a folder. Add a schema migration.
2. **Core: scan root.** Add a helper that finds the originals folder inside
   a package (`originals/`, else `Masters/`). Return nil when neither exists.
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

### 4.3 Database metadata overlay (only if chosen)

Add option 3.2 on top of 4.2. Build this only if section 5 decides for it.

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

### 4.4 Docs (to do)

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

### 5.2 To make after the spike: add 3.3?

Build 4.3 only if both of these hold:

- **It's needed.** File-only mode misses enough to matter. For example,
  many photos have adjusted dates, or Recently Deleted and Hidden photos
  show up.
- **It's contained.** The spike finds few schema versions. The reader stays
  in one core file with its own tests, and nothing else depends on it.

If 3.3 is built, it must fail soft. An unknown schema loses metadata, not
photos.

## 6. Open questions

- **TCC.** Does macOS ask for Photos access for any `.photoslibrary`, or
  only for the system library? (4.1 step 2)
- **Shared Library.** Do iCloud Shared Library assets live outside
  `originals/`? (4.1 step 4)
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

Suggestion: start with 1. Move to 2 if the spike shows renders are removed
on revert. Otherwise use 3, if 3.3 is built.

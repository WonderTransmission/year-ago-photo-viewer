# Proposal: Year Ago Photo Viewer

Status: Draft 6 — ready for review
License: MIT, © WonderTransmission
Target platform: macOS 26 (Tahoe), Apple silicon

## 1. Summary

Year Ago Photo Viewer is a small native macOS app. It shows the photos you took
around this time in past years. Open it, and you step through last year's
photos from the past week. Press "Next year", and you step through the same
week two years ago, then three.

The app reads photos from one or more sources at once:

- **Photos library.** The Mac's system Photos library, via Apple's PhotoKit.
- **Folders.** Any number of folders of image files, including nested
  subfolders.

Photos from all enabled sources merge into one timeline.

You choose where each photo's date comes from:

- **File name.** A date embedded in the name, such as
  `Screen Shot 2022-03-16 at 1.50.15 PM.png`.
- **Modified date.** The file's last-modified timestamp.
- **Created date.** The file's creation timestamp.
- **EXIF date.** The capture date stored inside the image.

The project is a personal app. Its source code will be public on GitHub. The
repo will contain no personal data.

## 2. Goals

- Show photos from a date window N years ago, with one click to change N.
- Let the user add, remove, enable, and disable photo sources at any time.
- Let the user change the date source at any time, per photo source.
- Let the user widen the window from 1 to 6 weeks.
- Always show which year is on screen.
- Show each photo once: hide duplicates, and pair RAW files with their JPEGs.
- Offer a quick "on this day" glance from the menu bar and a widget.
- Stay fast with libraries of 100,000+ photos.
- Keep all data on the Mac. No network access. No telemetry.

## 3. Non-goals (v1)

- **Editing.** The app never modifies, moves, or deletes photos.
- **Sharing.** No export, share sheet, or upload.
- **Video.** The app ignores videos. Live Photos show their still key frame.
- **Date fallbacks.** A photo without the chosen date is ignored.
- **Other Photos libraries.** PhotoKit only reads the system library.
- **iOS or iPadOS.** macOS only.
- **App Store release.** Users build from source.

## 4. Core concepts

### 4.1 The viewing window

The window is a date range in a past year. Today is the anchor. The user sets
the window length, W, from 1 to 6 weeks. The default is 1 week.

For "N years ago", the window is:

```
start = (today − N years) − W weeks
end   = (today − N years), inclusive of that whole day
```

Example: today is 8 Nov 2026, N = 1, W = 1 week. The window is
1 Nov 2025 through 8 Nov 2025.

Date math uses the user's calendar and time zone. 29 Feb maps to 28 Feb in
non-leap years. Foundation's `Calendar` handles this.

### 4.2 Years available

N ranges from 1 to the age of the oldest photo across all enabled sources. The
app computes this after it scans the sources. It also counts the photos in each year's
window.

### 4.2.1 Empty years

Some years have no photos in the window. A setting controls what happens:

- **Setting.** A checkbox: "Show years with no photos". It is on by default.
- **On.** Every year from 1 to N appears. An empty year shows an empty panel
  with the usual header, such as "6 years ago · 1–8 Nov 2020 · No photos".
  "Next year" moves to it like any other year.
- **Off.** Empty years are skipped. "Previous year" and "Next year" jump to
  the nearest year with photos. The year picker hides empty years.

The checkbox lives in Settings and in the View menu. Changing it applies at
once.

If the setting is off and N = 1 is empty, the app opens at the nearest
year with photos. If no year has photos, the app shows the empty panel anyway.

### 4.3 Navigation

Navigation has two levels: photos within a year, and years.

**Within a year.** The app opens at N = 1 on the first photo in the window.
The user steps through the photos in date order:

- **Keys.** Left and right arrow keys.
- **Buttons.** "Previous photo" and "Next photo" on screen.
- **Position.** A counter shows progress, such as "12 of 37".

Stepping never crosses into another year. After the last photo, the app shows
an end card. The card offers a "Next year" button.

**Between years.** Only an explicit action changes the year:

- **Buttons.** "Previous year" and "Next year" in the toolbar.
- **Keys.** ⌘[ and ⌘].
- **Picker.** A menu that lists the years. Empty years appear with
  "(no photos)" or are hidden, per section 4.2.1.

Changing the year opens that year's window at its first photo. An empty year
opens the empty panel.

The header always shows the year both ways, for example:
**"2 years ago · 1–8 Nov 2024 · 12 of 37"**.

### 4.4 Date sources

Each photo gets one date from its photo source's chosen date source. Times are
local wall-clock time. EXIF dates and file names usually lack a time zone, so
this is the safest reading.

**Per-source setting.** Each photo source has its own date source. A
screenshots folder can use File name while a camera folder uses EXIF. The
toolbar's Date menu sets a default. New sources start with that default. The
Sources panel (section 5) overrides it per source.

| Date source  | Folder source                          | Photos library source                       |
|--------------|----------------------------------------|---------------------------------------------|
| File name    | Parse the file name                    | Parse the original file name of the asset   |
| Modified     | File modification date                 | `PHAsset.modificationDate` (see note)       |
| Created      | File creation (birth) date             | `PHAsset.creationDate`                      |
| EXIF         | `DateTimeOriginal`, via ImageIO        | Same as Created (Photos uses capture date)  |

Notes:

- **Photos modified date.** Offered, though of limited use. Photos bumps this
  on any edit or sync. A tooltip says so.
- **File created date.** Copying files often resets it. The app will say so in
  a tooltip.
- **Missing dates.** Some photos lack the chosen date, such as a PNG with no
  EXIF. The app ignores them. There is no fallback to another date source.

### 4.5 File name patterns

The file name parser will ship with a list of common patterns:

| Example                                     | Origin                       |
|---------------------------------------------|------------------------------|
| `Screen Shot 2022-03-16 at 1.50.15 PM.png`  | macOS screenshots (≤ 12)     |
| `Screenshot 2022-03-16 at 13.50.15.png`     | macOS screenshots (13+)      |
| `IMG_20220316_135015.jpg`                   | Android cameras              |
| `PXL_20220316_135015123.jpg`                | Google Pixel                 |
| `2022-03-16 13.50.15.jpg`                   | Dropbox camera uploads       |
| `20220316_135015.jpg`                       | Samsung and others           |

The parser rejects impossible dates, such as month 13. A pattern list in code
makes new formats easy to add.

### 4.6 Media types

The app shows still images only.

- **Photos.** JPEG, HEIC, PNG, TIFF, and other formats ImageIO can read.
- **RAW.** Shown. ImageIO reads common RAW formats, such as CR2, CR3, NEF,
  ARW, RAF, ORF, and DNG.
- **Videos.** Ignored in both sources.
- **Live Photos in Photos.** The app shows the asset's still key frame.
  PhotoKit returns this by default when asked for an image.
- **Live Photos in a folder.** A Live Photo exported to disk is a `.HEIC`
  plus a `.MOV` with the same name. The app shows the `.HEIC` and ignores
  the `.MOV`, as it does every video.

### 4.7 RAW + JPEG pairs

Many cameras save each shot twice, such as `IMG_1234.CR2` and `IMG_1234.JPG`.
The app shows each pair as one photo.

- **Matching rule.** Same folder, same base name, ignoring case. One file is
  RAW. The other is JPEG or HEIC.
- **Displayed file.** The JPEG or HEIC. It is the camera's own rendering, and
  it loads much faster.
- **Date.** Read from the displayed file. If it lacks the chosen date, read
  the RAW. Both files record the same shot, so this is not a fallback to a
  different date source.
- **RAW only.** A RAW file with no partner is shown on its own.
- **Caption.** Paired photos show a small "RAW+JPEG" badge.
- **Sidecars.** `.XMP` and `.AAE` files are ignored.

In the Photos library, Photos already stores a RAW+JPEG pair as one asset.
The app needs no extra pairing there.

### 4.8 Duplicates

The app hides duplicate photos. Each photo appears once in the timeline.

**Folders.** Two files are duplicates when their contents match exactly. This
applies within one folder and across all folder sources.

1. Group files by size. Files with a unique size cannot be duplicates.
2. Hash only the files that share a size, using SHA-256.
3. Files with the same hash are duplicates.
4. The app shows one copy, the "winner". See the winner rule below.

The index stores each hash, so this runs once per file.

**Why the winner matters.** Copies share content but not file metadata. A
backup copy often has a newer created or modified date, or a different name.
So the winner decides:

- **Date.** With File name, Modified, or Created dates, copies can differ. The
  photo appears once, at the winner's date. With EXIF, all copies agree.
- **Location.** Which path the caption and "Show in Finder" use.

**Winner rule: earliest date wins.**

1. Date each copy using its own source's date setting.
2. Drop copies that lack that date. If none remain, the photo is ignored.
3. The copy with the earliest date wins. Backups usually carry newer dates, so
   this tends to pick the original.
4. Ties go to the shortest path, then alphabetical order.

The rule applies to every kind of duplicate: within a folder, across folders,
and between Photos and folders. The photo appears only at the winner's date.
The losing copies stay hidden, even if their own dates fall in the window.

**Photos library.** PhotoKit does not expose Photos' own duplicate detection.
The app treats two assets as duplicates when both match:

- **Capture time.** Same `creationDate`, to the second.
- **Size.** Same pixel width and height.

**Across Photos and folders.** A folder often holds exports of photos that
are also in Photos. Hashing Photos originals is too slow, so the app uses the
same heuristic. A folder file matches a Photos asset when its EXIF date equals
the asset's `creationDate`, to the second, and its pixel size matches. Files
without EXIF dates are never matched this way.

**Limits.** v1 finds exact copies only. A resized or re-encoded copy is not
caught. Perceptual matching could come later.

## 5. User interface

One main window, built in SwiftUI. The current photo fills most of it.

```
┌───────────────────────────────────────────────────────────────────┐
│ [Sources: 3 ▾] [Default date: EXIF ▾] [Window: 1 week ▾]          │
│                                                                   │
│ ◀◀ Prev year   2 years ago · 1–8 Nov 2024   [Year ▾] Next year ▶▶ │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│                                                                   │
│     ◀                    current photo                      ▶     │
│                                                                   │
│                                                                   │
├───────────────────────────────────────────────────────────────────┤
│  Wed 6 Nov 2024, 14:32                                  12 of 37  │
│  ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ■ ▢ ▢ ▢ ▢ ▢ ▢ ▢   ← filmstrip              │
└───────────────────────────────────────────────────────────────────┘
```

- **Photo.** The current photo, scaled to fit.
- **Photo arrows.** Step to the previous or next photo in this year.
- **Caption.** The photo's date, and the name of its photo source.
- **Counter.** Position within this year's window.
- **Filmstrip.** Thumbnails of this year's photos. Click one to jump to it.
- **Year controls.** Previous year, next year, and a year picker.
- **End card.** After the last photo: "That's all for 2024" and a
  "Next year" button.
- **Sources button.** Shows how many sources are enabled. Opens the Sources
  panel.
- **Default date menu.** The four date sources. Sets the default for new
  sources, and can apply it to all sources at once.
- **Window menu.** 1 to 6 weeks.
- **Empty panel.** Shown for a year with no photos, when empty years are
  shown. It reads "No photos from 1–8 Nov 2019". It keeps the year controls
  and offers a "Next year" button. The filmstrip is hidden.
- **Empty years setting.** "Show years with no photos" checkbox. See 4.2.1.
- **Progress.** A progress bar during the first scan of a large folder.

All settings persist between launches.

### 5.1 Sources panel

A sheet that lists every photo source:

```
┌──────────────────────────────────────────────────────────────┐
│ Sources                                                      │
├──────────────────────────────────────────────────────────────┤
│ ☑  Photos Library            Date: [Created ▾]    1,204 ✓    │
│ ☑  Camera Archive            Date: [EXIF ▾]      48,311 ✓    │
│ ☑  Screenshots               Date: [File name ▾]  2,950 ⟳    │
│ ☐  Old Backup Drive          Date: [Modified ▾]  offline     │
├──────────────────────────────────────────────────────────────┤
│ [+ Add Folder…]  [+ Add Photos Library]  [− Remove]          │
└──────────────────────────────────────────────────────────────┘
```

- **Checkbox.** Enables or disables a source without removing it.
- **Name.** The folder name by default. The user can rename it.
- **Date menu.** The date source for this source. Options that do not apply
  are dimmed.
- **Status.** Photo count, scanning progress, or "offline".
- **Offline.** A folder on an unplugged drive is skipped until it returns.
  Its index is kept.
- **Nested folders.** Adding a folder inside an existing source is allowed.
  Its files are counted once.
- **Photos Library.** It can be added at most once.

### 5.2 Menu bar item

A small "On this day" item lives in the menu bar. Users can turn it off in
Settings.

- **Icon.** A small calendar or photo glyph.
- **Popover.** Shows one photo from 1 year ago, in the current window.
- **Shuffle.** A button picks another photo from the same window.
- **Summary.** A line such as "37 photos from 1–8 Nov 2025".
- **Open.** A button opens the main window at that photo.

It uses the same sources, date sources, window length, and empty-years setting
as the main window.

### 5.3 Widget

A desktop and Notification Center widget, built with WidgetKit.

- **Small.** One photo from 1 year ago, with its date.
- **Medium.** One photo each from 1, 2, and 3 years ago.
- **Large.** A 2×3 grid from the current window, 1 year ago.
- **Tap.** Opens the main window at that photo.
- **Empty years.** Follows the same setting. When on, an empty year shows an
  empty tile. When off, the widget uses the next years with photos.
- **Refresh.** Once a day, after midnight, and when settings change.

A widget runs in its own sandboxed process. It cannot open the user's folder
bookmark or query PhotoKit quickly. So the main app does the work:

1. Each day, the app picks the widget's photos.
2. It writes small JPEG thumbnails and a JSON manifest to a shared App Group
   container.
3. It asks WidgetKit to reload.
4. The widget reads only that container.

If the app has not run today, the widget shows the last snapshot. It labels
the snapshot with its date.

## 6. Architecture

### 6.1 Technology

- **Language.** Swift 6 with strict concurrency.
- **UI.** SwiftUI, with AppKit only where SwiftUI falls short.
- **Menu bar.** SwiftUI `MenuBarExtra`.
- **Widget.** WidgetKit extension, sharing data through an App Group.
- **Hashing.** CryptoKit SHA-256 for duplicate detection.
- **Images.** ImageIO for EXIF and thumbnails. PhotoKit for the Photos library.
- **Persistence.** SwiftData or SQLite for the photo index.
- **Build.** Xcode project with a separate Swift package for core logic.
- **Dependencies.** None beyond Apple frameworks.

### 6.2 Components

```
App (SwiftUI)
 ├── ViewerModel        current N, W, merged photo list
 ├── SourceRegistry     list of sources, enabled flags, per-source date source
 ├── PhotoSource        protocol
 │    ├── FolderSource       walks folders, reads file and EXIF dates
 │    └── PhotosLibrarySource PhotoKit queries
 ├── DateExtractor      file name, modified, created, EXIF
 ├── PhotoGrouper       RAW+JPEG and HEIC+MOV pairing
 ├── Deduplicator       size grouping, SHA-256, cross-source heuristic
 ├── PhotoIndex         cached dates, hashes, and groups per source
 ├── WindowCalculator   N, W, today → date range
 ├── ThumbnailLoader    async, cached thumbnails
 └── WidgetSnapshotter  writes daily thumbnails to the App Group

MenuBarExtra (SwiftUI)  reads ViewerModel
Widget extension        reads the App Group snapshot only
```

Core logic lives in a Swift package, `YearAgoCore`. It has no UI code. Unit
tests run against it without launching the app.

### 6.3 Indexing a folder

Reading EXIF from 100,000 files takes time. So the app builds an index once and
reuses it:

1. Walk the folder and list image files.
2. For each file, record path, size, modified date, created date, file name
   date, and EXIF date. Read all four at once, so switching the date source
   needs no rescan.
3. Pair RAW files with their JPEG or HEIC partners.
4. Hash files that share a size, and mark duplicates.
5. Store the index in Application Support, keyed by folder.
6. On later launches, re-read only files whose size or modified date changed.
7. Watch the folder with FSEvents to pick up changes while the app runs.

Queries then run against the index, not the disk.

Each folder source has its own index. Duplicate detection runs across all
indexes. Disabling a source keeps its index, so re-enabling it is instant.
Removing a source deletes its index.

### 6.4 Photos library

PhotoKit can filter by `creationDate` directly. The app needs no index for the
Created and EXIF date sources. The File name source needs each asset's
original file name. Fetching that is slow, so the app caches it like a folder
index.

### 6.5 Permissions and sandbox

- **Sandbox.** The app runs in the App Sandbox.
- **Folders.** The user picks folders with an open panel. The app stores a
  security-scoped bookmark so access survives relaunch.
- **Folders.** Each folder source has its own bookmark.
- **Photos.** The app asks for Photos access when the user adds that source.
- **App Group.** Shared by the app and the widget, for snapshots only.
- **Network.** No network entitlement.

## 7. Privacy and the public repo

The code will be public. These rules keep personal data out:

- **No real photos.** Tests use small images generated by a script, with
  synthetic EXIF.
- **No personal paths.** No user names or home paths in code, docs, or
  screenshots.
- **No stored data in the repo.** The index lives in Application Support.
- **Clean screenshots.** README images use sample photos only.
- **Ignore files.** `.gitignore` covers `xcuserdata`, `DerivedData`, and
  build output.
- **Signing.** Sign locally, ad hoc or with a personal team. No team ID is
  committed. The App Group ID and bundle IDs come from a local, ignored
  `.xcconfig` file. The repo ships a template with placeholder values.
- **License.** MIT, copyright WonderTransmission. A `LICENSE` file goes in
  the repo root.

## 8. Testing

- **Window math.** Year boundaries, leap days, DST shifts, 1–6 week windows.
- **File name parser.** Every pattern in 4.5, plus near-misses that must fail.
- **EXIF reading.** Generated fixtures with and without `DateTimeOriginal`.
- **File filtering.** Videos are ignored. A `.HEIC` + `.MOV` pair yields one
  photo.
- **Pairing.** `IMG_1234.CR2` + `IMG_1234.jpg` yields one photo showing the
  JPEG. A lone RAW is shown. Same names in different folders do not pair.
- **Duplicates.** Identical files show once, within and across folders.
  Same-size, different files both show. The earliest-dated copy wins. A copy
  without a date never wins. Equal dates fall back to shortest path.
- **Multiple sources.** Photos from all enabled sources merge in date order.
  Each source uses its own date source. Disabled and offline sources are
  skipped.
- **Navigation.** Stepping stops at the end card and never changes the year.
- **Empty years.** With the setting on, "Next year" lands on empty years.
  With it off, it skips them. The all-empty case still shows a panel.
- **Widget snapshot.** The manifest and thumbnails match the chosen window.
- **Indexer.** Incremental rescans after add, change, and delete.
- **Manual.** A checklist for the Photos library, since tests cannot use a
  real one.

## 9. Milestones

1. **Core logic.** `YearAgoCore` package: window math, date extractors, tests.
2. **Folder viewer.** Pick a folder, scan it, step through photos for N = 1.
3. **Navigation.** Year controls, end card, filmstrip, and the menus.
4. **Index.** Persistent index, incremental rescan, progress UI.
5. **Multiple sources.** Sources panel, per-source date source, merging.
6. **Pairs and duplicates.** RAW+JPEG pairing and duplicate hiding.
7. **Photos library.** PhotoKit source, Live Photo key frames, permissions.
8. **Polish.** Empty states, keyboard shortcuts, README, LICENSE.
9. **Menu bar item.** "On this day" popover.
10. **Widget.** App Group snapshot and WidgetKit extension.

## 10. Decisions

| # | Topic             | Decision                                                  |
|---|-------------------|-----------------------------------------------------------|
| 1 | Window direction  | The W weeks before the date N years ago, inclusive.       |
| 2 | Navigation        | Step through one year's photos. Change year only on an explicit action. |
| 3 | Missing dates     | Ignore photos that lack the chosen date. No fallback.     |
| 4 | Video             | Ignore videos.                                            |
| 5 | Live Photos       | Show the still key frame.                                 |
| 6 | Duplicates        | Hide them. Exact matches only in v1.                      |
| 7 | RAW               | Show RAW files. Pair `IMG_1234.CR2` with `IMG_1234.JPG`.  |
| 8 | On this day       | Add a menu bar item and a widget.                         |
| 9 | License           | MIT.                                                      |
| 10 | App name         | Year Ago Photo Viewer.                                    |
| 11 | Empty years      | Show with an empty panel. A checkbox can hide them. On by default. |
| 12 | Photos modified date | Offered, though of limited use.                       |
| 13 | Sources          | Multiple sources at once: Photos plus any number of folders. |
| 14 | Copyright holder | WonderTransmission.                                       |
| 15 | Duplicate winner | Earliest date wins. Ties go to shortest path, then alphabetical. |
| 16 | Date setting     | Per source. The toolbar sets the default for new sources. |

## 11. Open questions

None at present.

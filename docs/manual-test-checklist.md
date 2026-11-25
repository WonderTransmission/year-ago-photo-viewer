# Manual Test Checklist

Unit tests cover the core logic. These checks cover what tests can't reach:
the real Photos library, permissions, drives, the menu bar item, and the
widget. Run them before a release.

Tip: copy the boxes into a release issue and tick them there.

## Setup

- [ ] Build and run the **YearAgoPhotoViewer** scheme from Xcode.
- [ ] For a clean start, quit the app and delete
  `~/Library/Containers/<bundle id>/Data/Library/Application Support/YearAgoPhotoViewer`.

## Folders (M2–M6)

- [ ] **Add folder.** Welcome screen → Add Folder… → choose a folder of photos.
  The first index shows a progress bar, then the viewer.
- [ ] **Step.** ← and → step through the year's photos. The last step shows the
  end card. ⌘] and ⌘[ change the year.
- [ ] **Zoom.** Pinch to zoom; double-click toggles fit and 250%; ⌘= / ⌘- /
  ⌘0 zoom in, out, and to fit. A "250% Fit" badge shows while zoomed. Drag
  pans, stopping at the photo's edges. → or ← returns to fit.
- [ ] **Buttons on bright photos.** On a white or very bright photo that
  reaches the window's edges, both arrow buttons stay clearly visible.
- [ ] **Relaunch.** Quit and relaunch. Photos appear at once, with no
  full-window progress.
- [ ] **Live change.** Copy a photo dated last year into the folder. It appears
  within a few seconds.
- [ ] **Second folder.** Sources… → Add Folder… Give it a different date
  setting. Its photos merge into the timeline.
- [ ] **Disable.** Untick a source. Its photos disappear at once. Tick it again.
- [ ] **Drive.** Add a folder on an external drive, then eject the drive.
  The source shows "Offline" and its photos disappear. Plug it back in:
  the source comes back online.
- [ ] **RAW pair.** A folder with `IMG_1.CR2` and `IMG_1.JPG` shows one photo
  with a "RAW+JPEG" badge.
- [ ] **Duplicate.** Copy a photo into a second source folder. It shows once.

## Photos library (M7)

- [ ] **Permission prompt.** Sources… → Add Photos Library. macOS asks for
  Photos access. Allow it. The library indexes with progress.
- [ ] **Photos appear.** Photos from this week last year appear, merged with
  folder photos, sorted by date.
- [ ] **Live Photo.** A Live Photo shows its still key frame (no motion, no
  playback controls).
- [ ] **RAW+JPEG asset.** An asset imported as RAW+JPEG shows once.
- [ ] **Videos.** Videos from this week do not appear.
- [ ] **iCloud.** A photo whose original is only in iCloud still loads,
  perhaps after a short delay.
- [ ] **Edit in Photos.** Change a photo's date in Photos (Image › Adjust Date
  and Time). Within about a second it moves to its new date in the viewer,
  without the toolbar showing a full re-index.
- [ ] **Delete and import in Photos.** Delete a photo from this week last
  year, then import a new one dated then. Both changes show within a second.
- [ ] **File name dates.** Set the Photos Library source to "File name".
  Screenshots in the library appear by their file-name date. The first
  switch fetches file names with progress; later switches are instant.
- [ ] **Exported copy.** Export a library photo (unmodified original) to a
  source folder. It shows once, not twice.
- [ ] **Access denied.** In System Settings › Privacy & Security › Photos,
  turn access off and relaunch. The source shows "No Access…", which opens
  System Settings. No library photos appear; folder photos still do.
- [ ] **Add twice.** Add Photos Library is disabled once the library is a source.
- [ ] **Slow first open.** After a macOS upgrade (or with a library on an
  external hard drive), add the library. The window keeps responding. A
  banner shows "Opening your Photos library…" with the time so far; after
  30 s it explains why and offers **Show Progress in Photos**. Folder photos
  stay usable meanwhile.
- [ ] **Library drive disconnected.** With the library on an external drive,
  eject the drive and relaunch. The source shows "Unavailable", not
  "No Access…", and its index is kept. Reconnect: it comes back.
- [ ] **Bursts.** Burst photos in the library all appear, not just one.
- [ ] **Stop and Resume.** While a source indexes, click the toolbar progress
  and **Stop**. Indexing ends within a second or two; photos indexed so far
  stay. The Sources panel shows "Stopped — N of M" with **Resume**. Quit and
  relaunch: the source stays stopped. Click Resume: it continues, reading only
  what's left.
- [ ] **Stop while opening.** While "Opening your Photos library…" shows,
  stop the library from the Sources panel. The app stops waiting at once;
  other sources keep indexing.
- [ ] **This week first.** Remove the Photos Library source and add it again.
  Within seconds of the library opening, this week's photos from past years
  appear, while the toolbar still shows indexing progress.
- [ ] **Fill-in.** During a long first index of a large folder, photos appear
  and the year list grows every few seconds; the current photo stays put.

## Photos library files

Use a second library (hold ⌥ while opening Photos to create one) and, if
possible, one on an external drive.

- [ ] **Picker.** Sources… → Add Photos Library File… Only `.photoslibrary`
  files can be chosen. No Photos prompt appears.
- [ ] **Photos appear.** The library indexes with progress. Its photos from
  this week last year appear, merged with other sources.
- [ ] **No extras.** The photo count roughly matches the library's own count
  in Photos (fewer with Optimize Mac Storage). No thumbnails or duplicate
  edited copies appear.
- [ ] **Date menu.** The source's Date menu has no File name option.
- [ ] **Edits.** Crop a photo from this week last year in Photos. The viewer
  shows the crop. Revert to Original in Photos: the uncropped photo shows
  (relaunch if it doesn't update at once).
- [ ] **Live change.** Import a photo dated last year into that library in
  Photos. It appears within a few seconds.
- [ ] **Read-only.** After indexing, Photos still opens the library with no
  repair prompt.
- [ ] **Drive.** With the library on an external drive, eject the drive.
  The source shows "Offline". Plug it back in: it comes back.
- [ ] **System library warning.** With the Photos Library source added and
  allowed, add the system library's file. The app says it's the same
  library. The new row is named "… (File)". Each photo shows once.

## Photo info

- [ ] **Open and close.** ⓘ in the caption, or ⌘I, opens Photo Info. ⌘I
  again closes it.
- [ ] **Folder photo with GPS.** Camera, Exposure, Lens, Image, Dates, and
  Location sections show. "Date used" names the source's date setting.
  **Open in Maps** opens Maps at the right place.
- [ ] **No GPS.** A photo without a location has no Location section and no
  Maps button.
- [ ] **Photos library item.** Only Image, Dates, and Location (if any)
  show, with the note about camera details.
- [ ] **Edited library-file photo.** The original's metadata shows.
- [ ] **Closes on navigation.** ← or → while it's open changes the photo
  and closes it. So do a filmstrip click and a year change.
- [ ] **Copy All.** Pasting gives every section as text.

## Menu bar item (M9)

- [ ] **Shown by default.** A clock-arrow icon appears in the menu bar.
  Clicking it shows "On This Day" with one photo from the viewer's first year.
- [ ] **Shuffle.** Shuffle shows a different photo from the same week. It is
  disabled when the week has fewer than two photos.
- [ ] **Open in Viewer.** Opens the main window at that photo and closes the
  popover.
- [ ] **Empty week.** With "Show years with no photos" on and no photos last
  year, the popover says "No photos from …". With it off, it shows the
  nearest year with photos.
- [ ] **Close the window.** Close the main window. The app keeps running and
  the menu bar item still works. Open in Viewer brings the window back.
- [ ] **Hide.** Settings › untick "Show “On This Day” in the menu bar". The
  icon disappears. Closing the window now quits the app.

## Widget (M10)

The widget needs a development team (see the README). Set `DEVELOPMENT_TEAM`
and `CODE_SIGN_IDENTITY = Apple Development` in `Config/Local.xcconfig`.

- [ ] **Ad hoc build.** Without a team the app still builds and runs. The
  widget, if added, says "Open Year Ago Photo Viewer to add photos."
- [ ] **Gallery.** With a team, run the app once, then right-click the
  desktop › Edit Widgets. "On This Day" appears in small, medium, and large.
- [ ] **Small.** One photo from the viewer's first year, with its date.
- [ ] **Medium.** One photo each from the first three years offered. With
  "Show years with no photos" on, an empty year shows "No photos".
- [ ] **Large.** Up to six photos from the first year in a 2 × 3 grid, with
  the date range and photo count.
- [ ] **Tap.** Clicking a photo opens the app at that photo.
- [ ] **Updates.** Add a photo from last year to a source. Within a few
  seconds of the app indexing it, the widget updates.
- [ ] **Stale.** Quit the app before midnight. After midnight the widget
  shows "As of <date>" until the app runs again.

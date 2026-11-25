# Plan: Photo Info Popover

Status: steps 4.1 and 4.2 done; 4.3 to do.
Trigger: users want to see a photo's EXIF data, and where it was taken.

## 1. Goal

An ⓘ button shows everything known about the current photo in a popover.

- **All metadata.** Every EXIF, TIFF, GPS, and IPTC value the file holds,
  grouped and readable.
- **Location.** When the photo has a location, show its coordinates and an
  **Open in Maps** button.
- **Closes on navigation.** Moving to another photo closes the popover.
- **Still offline.** The app keeps "no network access" true. It never shows
  a map itself; the Maps app does that.

## 2. Decisions

- **No in-app map (option B).** An inline MapKit map would need the network
  entitlement. It would also send the photo's location to Apple for map
  tiles. **Open in Maps** hands the coordinates to the Maps app instead. An
  opt-in inline map may come later.
- **Photos Library source: basic info only.** PhotoKit gives the date, pixel
  size, location, and kind without reading the file. Full EXIF would need
  the original, maybe downloaded from iCloud. Not now.
- **Popover.** It's attached to an ⓘ button in the caption bar. A sheet
  would block the arrow keys, so the user could never navigate away.
- **Original's metadata.** A library-file photo shows its edited copy
  (`displayURL()`), but the popover reads the original (`url`). Edited
  copies may have lost metadata.

## 3. What happens today

- **Reading.** `ImageMetadataReader` already opens each file with ImageIO.
  It keeps only the capture date and pixel size.
- **Caption bar.** `ViewerView.caption` shows the date, source, RAW badge,
  and file name. The ⓘ button fits at its trailing end.
- **Shortcuts.** ⌘I is unused. macOS uses it for "Get Info".

## 4. Work plan

### 4.1 Core: metadata model and formatting (done)

Built as `PhotoInfo` and `PhotoInfoReader` (in `Imaging/`), with these
details:

- **More sections.** Leftover values go into one section per dictionary,
  titled "More: EXIF", "More: TIFF", "More: Apple maker notes", and so on.
  Nested dictionaries are flattened as "Parent › Key".
- **Unknown keys.** They get readable labels from their ImageIO names:
  "ISOSpeedRatings" becomes "ISO Speed Ratings".
- **Long arrays.** Arrays of more than 32 values count as binary.
- **Maps URL.** `Coordinate.mapsURL(label:)` builds the `maps://` link, so
  it's tested in the core.
- **Spelling.** Labels use US spelling ("Color profile"), like macOS.

1. **Reading.** Add `PhotoInfoReader.read(at:) -> PhotoInfo` in the core
   package. It calls `CGImageSourceCopyPropertiesAtIndex` once and keeps
   every dictionary.
2. **Sections.** Group values into sections, in this order:
   - Camera (make, model, software)
   - Exposure (shutter, aperture, ISO, exposure bias, flash, metering)
   - Lens (model, focal length, 35 mm equivalent)
   - Image (pixel size, orientation, color profile, file type and size)
   - Dates (original, digitized, modified, with time zone offsets)
   - Location (latitude, longitude, altitude, direction)
   - Other (every remaining key, by dictionary)
3. **Labels and values.** Known keys get readable labels and formats:
   `1/250 s`, `f/2.8`, `35 mm`, `ISO 400`, signed decimal degrees.
   Unknown keys show their ImageIO name and a plain value.
4. **Skipped values.** Leave out binary data such as maker-note blobs and
   thumbnails. Count them instead ("3 binary values not shown").
5. **Location.** `PhotoInfo.coordinate` comes from the GPS dictionary, with
   the N/S and E/W references applied. Missing or zero-zero coordinates give
   nil.
6. **Tests.** Generated images with made-up EXIF, TIFF, and GPS values, as
   the fixtures already write. Cover:
   - grouping and labels;
   - formatting of fractions, apertures, and focal lengths;
   - southern and western coordinates;
   - an image with no metadata;
   - skipped binary values.

### 4.2 App: Photos Library items (done)

Built as `LibraryAssetDetails` and `PhotoInfo.libraryItem` in the core, so
the formatting is unit-tested. The app's `details(forAssetID:)` fills the
details from the `PHAsset`. It never asks for access. Kinds shown: Live
Photo, Panorama, HDR, Screenshot, Portrait, and Burst; Favorite shows when
set. The original file name shows when the index has it. The debug fake
library returns made-up details.

1. **Basic info.** Build a `PhotoInfo` from the `PHAsset`: creation and
   modification dates, pixel size, media subtypes (Live Photo, screenshot,
   HDR, panorama), and `location`. The location includes altitude and course
   when present.
2. **Location source.** Use `PHAsset.location`: it reflects location fixes
   made in Photos.
3. **Note.** End with one line: "Full camera details aren't available for
   Photos library items."
4. **Off the main thread.** Fetch the asset with `@concurrent`, like the
   other PhotoKit calls.

### 4.3 App: the popover (to do)

1. **Button.** Add an ⓘ button at the end of the caption bar. Add
   **View › Photo Info** with ⌘I. Both are disabled when no photo shows.
2. **Popover.** Use `.popover`, anchored to the button. Its content is a
   scrolling list of sections with label/value rows. It's about 360 points
   wide, with a maximum height.
3. **Loading.** Read off the main thread. Show a small spinner if reading
   takes over 0.2 s, as on a slow drive.
4. **Location row.** It shows the coordinates and an **Open in Maps**
   button. The button opens `maps://?ll=<lat>,<lon>&q=<date>` with
   `NSWorkspace`. Show nothing map-related when there's no location.
5. **Copy.** Rows can be selected. ⌘C copies "Label: Value". A **Copy All**
   button copies every row as text.
6. **Close on navigation.** Keep `isShowingInfo` in `ViewerModel`. Clear it
   in an `onChange` of the current photo's ID. That covers arrow keys, the
   filmstrip, year and window changes, and the photo leaving the timeline.
7. **Arrow keys.** ← and → must still change photos while the popover is
   open, and so close it. The popover must not keep keyboard focus. Test
   this first; if the list captures arrows, give the popover no focusable
   list.
8. **Accessibility.** The button's label is "Photo Info". VoiceOver reads
   each row as "Label, Value".

### 4.4 Docs (to do)

- **README.** Add a feature line and a "Using it" step. Keep the privacy
  line as is: still no network access.
- **Proposal.** Describe the popover in the viewer section.
- **Checklist.** Add manual checks:
  - a folder photo with GPS, and Open in Maps;
  - a photo without GPS;
  - a Photos Library item (basic info only);
  - a library-file photo that's edited (the original's metadata shows);
  - closing on ←, →, the filmstrip, and a year change.
- **Screenshot.** If one is added, use a generated image with made-up
  camera and GPS values.

## 5. Open questions

- **Time zone.** EXIF offset fields (`OffsetTimeOriginal`) exist only in
  newer files. Show them when present; otherwise show the time as stored.
- **RAW pairs.** The popover reads the file shown, usually the JPEG. Should
  it also list the RAW partner's name? Suggest yes, as one row under Image.
- **Later.** An opt-in inline map (needs the network entitlement), and full
  EXIF for Photos Library items.

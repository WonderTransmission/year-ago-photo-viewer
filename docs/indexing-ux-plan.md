# Plan: Responsive Indexing with Progress

Status: Draft 2 — cause confirmed, decisions recorded
Trigger: adding a 29 GB Photos library on an external drive made the app
unresponsive for 20+ minutes, with no sign of progress.

## 1. Goal

Indexing may take as long as it needs. While it runs:

- **Responsive.** The app never beach-balls. Every window, menu, and button
  keeps working.
- **Visible.** The user always sees that work is happening, what stage it is
  in, and a percentage.
- **Useful early.** Photos for this week appear as soon as they are indexed,
  not only at the end.
- **Safe to interrupt.** Quitting mid-index loses nothing. The next launch
  resumes where it stopped.

## 2. What happens today

### 2.0 Diagnosis (confirmed from logs)

Logs from the affected Mac (9,755 photos; library on a USB 4-bay hard-drive
enclosure; no iCloud) show:

| Time | Thread | Event |
|---|---|---|
| 21:51:16 | background | Photos access requested |
| 21:51:19.43 | background | Access granted |
| 21:51:19.44 | **main** | Connects to the Photos service and starts opening the library store |
| — | **main** | *Nothing for 19 min 41 s* |
| 22:11:00.38 | **main** | `openPhotoLibraryDatabase succeeded` |
| 22:11–22:12 | background | The app's own indexing of 10,747 items |

The Force Quit window was opened three times during the wait (21:52,
22:01, 22:06), so the UI was frozen.

**Cause:** right after access is granted, `addPhotosLibrary()` creates the
library change observer on the main thread. Its
`PHPhotoLibrary.shared().register(_:)` is the first PhotoKit call, so the
main thread waits while macOS opens the library. On this drive, macOS took
almost 20 minutes. Once open, the app indexed everything in about a minute.
Relaunching was quick because the library was already open.

**Why the open was slow:** the Mac had just been upgraded from macOS 15, and
the library had not been opened since. After a major upgrade, macOS upgrades
a Photos library the first time any app opens it. The Photos app shows
progress for this; other apps just wait. On spinning disks, that one-time
upgrade plausibly took the 20 minutes. Users who add the library soon after a
macOS upgrade will hit the same wait, so the app must handle it gracefully.

So cause 1 below is confirmed. Causes 2–4 are still real problems, but they
did not cause this hang.

### 2.1 Suspected causes, from reading the code

These were the likely causes before the logs arrived, most likely first.

### 2.1 Probable causes of the hang

1. **PhotoKit on the main thread.** The library change observer calls
   `PHPhotoLibrary.shared().register(_:)` on the main thread, right after
   access is granted. The first PhotoKit call opens the library. For a large
   library on an external drive, that can take minutes, and the main thread
   waits. The two `PHCachingImageManager` instances are also created on the
   main thread, at launch.
2. **One long silent step.** `imageAssets()` reads every asset before it
   reports anything. The UI shows "Finding photos… 0 found" until it ends. On
   a slow drive that step is most of the work.
3. **Endless resyncs.** Photos sends many change notifications while it
   settles a newly opened library (analysis, iCloud). Each one triggers a full
   resync 5 seconds later, which re-reads every asset. This can repeat for as
   long as Photos keeps working.
4. **Feedback hides when folders exist.** If any folder is already indexed,
   the full-window progress never shows. The only sign of work is a small
   toolbar spinner, with details only on hover.

Cause 1 is confirmed (section 2.0).

### 2.2 Other problems found during the review

- **Burst shots hidden.** Duplicate matching links library photos with the
  same capture second and pixel size. That was meant to catch exports in
  folders. It also merges burst shots inside the library, so all but one
  burst frame disappear.
- **Drive unplugged mid-sync.** If the library's drive goes away, PhotoKit
  may return zero assets. The sync would then delete every library row. This
  is the same bug fixed for folders in M5.
- **Logs vanish.** The app logs at "info" level, which macOS doesn't keep on
  disk. After a hang there is nothing to read.
- **Source IDs are reused.** Removing the newest source and adding another
  gives the new one the same ID, because SQLite reuses the highest row ID.
  Anything cached by source ID (photo IDs, widget thumbnails) could briefly
  show stale data. Fix: never reuse IDs (keep a counter in `meta`).
- **Absurd years.** A photo dated year 1 or 1904 (common in scans) stretches
  the year list to hundreds of empty years.

## 3. Design

### 3.1 Keep the main thread free

- **Rule.** No PhotoKit, file system, or database call runs on the main
  thread. The main thread only updates the UI.
- **PhotoKit.** Create the change observer and the image managers off the
  main thread, after access is granted.
- **Watchdog (debug builds).** A timer logs a warning, with a stack, when the
  main thread is blocked for more than 250 ms. This catches regressions early.

### 3.1a Explain a slow library open

macOS can take many minutes to open a large library for the first time,
especially on an external hard drive. The app can't speed that up, but it
can explain it. While the first PhotoKit call is waiting, show:

- **"Opening your Photos library…"** with an indeterminate bar and elapsed
  time ("4 min so far").
- **After 30 seconds:** "macOS is preparing your Photos library. After a
  macOS update, or on an external drive, this can take a while the first
  time. You can keep using the app."
- **"Show Progress in Photos" button.** Opens the Photos app, which shows
  Apple's own progress for a library upgrade. Indexing continues on its own
  once the library is ready.
- Folder sources stay usable throughout.

### 3.2 Index in measurable steps

Each sync reports one of these stages, with counts.

| Stage | What happens | Progress shown |
|---|---|---|
| Opening | Connecting to the Photos library, or walking a folder | Count of photos found so far |
| Reading | Reading dates and sizes, written to the index in batches | N of M, with % |
| Organizing | Pairing, duplicate groups, visibility | Short; indeterminate |
| Checking duplicates | Hashing same-size files | N of M, with % |

**The Photos library gives a total up front.** `PHAsset.fetchAssets` returns
its count at once and loads assets lazily. The new reader walks the result in
chunks of 500. Each chunk is written to the index and reported, so the
percentage is real from the first second.

**Folders give a total after the walk.** The walk counts files as it goes.
On a rescan, the previous file count is the estimate until the walk ends.

**Overall %** weights the stages by expected cost: opening 10%, reading 80%,
organizing 5%, duplicates 5%. Each source gets its own percentage. With
several sources queued, the toolbar shows the overall one.

**Time left** appears after 10% is done and at least 20 seconds have passed,
based on the recent rate. It's rounded, as in "about 12 minutes left".

### 3.3 Show progress everywhere it matters

- **Toolbar.** A progress ring with the percentage, such as "Indexing 42%".
  Clicking it opens a popover with:
  - the source name and stage ("Reading photo details")
  - "12,345 of 29,410 photos"
  - time left
  - a **Stop** button (3.5)
- **First index.** The full-window screen gains a progress bar with %, the
  stage, counts, time left, and the line "Photos appear as they're indexed."
  It shows whenever no photos are visible yet, even if folders exist.
- **Sources panel.** Each row being indexed shows a progress bar and %.
  Queued rows say "Waiting".
- **Dock icon.** A progress bar on the Dock icon while indexing, with the
  percentage. It's visible when the window is hidden or behind others, which
  is where the user was looking during the hang (decision 5.4). It is drawn
  by the app's main thread like everything else, so it relies on 3.1 keeping
  that thread free.
- **Menu bar popover.** "Indexing 42%" under the photo.
- **Update rate.** The UI refreshes at most 4 times a second, so progress
  never costs much.

### 3.4 Show this week's photos first

For the Photos library, the reader first fetches assets dated inside the
current year windows (for example, 1–8 Nov in each past year). PhotoKit can
filter by date, so this takes seconds. The viewer then shows this week's
photos while the rest of the library indexes behind them.

During a long index, the viewer also reloads every 10 seconds, keeping the
current photo, so new photos fill in.

Folders have no dates until each file is read, so they fill in as they go.

### 3.5 Stop and resume

One control covers both cancelling and pausing (decision 5.3). Indexing
already commits each batch as it goes, so stopping loses nothing and a later
resume skips what's done. That makes "pause" nearly free: it's just Stop
followed by Resume.

- **Stop** ends the current indexing run after the batch in flight, within a
  second or two. It's in the toolbar popover and on the source's row in the
  Sources panel.
- **Stopped state.** The source shows "Stopped — 4,210 of 9,755 indexed" with
  a **Resume** button. Photos indexed so far stay visible.
- **Stays stopped.** A stopped source isn't re-indexed automatically, not by
  folder or library changes, and not at the next launch, until the user
  presses Resume. That suits the backup case: stop, let the backup finish,
  resume later. The stopped flag is saved per source.
- **Resume** continues from where it stopped.
- **During a slow library open (3.1a)**, Stop stops the app waiting. macOS
  may carry on preparing the library on its own; the app can't cancel that.
- **Quit** mid-index is safe for the same reason. A source that wasn't
  stopped resumes at the next launch and shows "Resuming… 4,210 of 9,755".
- **Remove source** during indexing stops it and deletes its index.

A separate Pause that holds a run in place isn't planned: Stop and Resume
give the same result without extra states to manage.

### 3.6 Handle library changes incrementally

- **Change details, not full resyncs.** Keep the `PHFetchResult` from the last
  sync. On a change notification, use `PHChange.changeDetails(for:)` to get
  only inserted, removed, and changed assets, and apply just those.
- **Batch notifications.** Wait for 30 seconds of quiet. Ignore notifications
  while an index is running; re-check once it ends.
- **Full resync** only at launch, and when change details aren't available.

### 3.7 Correctness fixes

- **Bursts.** Capture-time duplicate links only connect a library photo to a
  folder photo, never two library photos.
- **Missing library.** If PhotoKit returns no assets but the index has rows,
  treat the library as unavailable. Mark it offline and delete nothing.
- **Dates.** Ignore dates before 1900 or after tomorrow when working out the
  year range. Those photos stay indexed but don't stretch the year list.
- **Logs.** Log stage timings at "notice" level, which macOS keeps. Still log
  counts only, never paths or names.

## 4. Work plan

Each step is one commit to `main`, tested before the next.

### 4.1 Confirm the cause (done)

Confirmed from the logs; see section 2.0. Kept for future reports:

- **Sample the hang.** If the app is still stuck on your Mac, capture what it
  is doing: Activity Monitor › select **Year Ago Photo Viewer** › ••• menu ›
  **Sample Process**. Or in Terminal:

  ```sh
  sample "Year Ago Photo Viewer" 10 -file ~/Desktop/yapv-sample.txt
  ```

  The section that starts with `Thread_… DispatchQueue_1: com.apple.main-thread`
  shows what blocks the UI. The file includes your user name in paths, so
  send that section only, or redact it.
- **Hang reports.** macOS may also have written one to
  `~/Library/Logs/DiagnosticReports/` (a `.hang` or `.spin` file).
- **Persistent logs.** Switch stage logging to "notice" so the next run leaves
  a trace.

### 4.2 Responsiveness (done)

Result: with `-DebugFakeLibrary 60` (a fake library whose every call blocks
its thread for 60 s, like the real library after the macOS upgrade), the
watchdog logged no main-thread stalls while the window was used during the
wait. The watchdog itself was checked with `-DebugBlockMainThread 2`, which
it reported as a 2.00 s stall. Folder sources now sync before the Photos
library, so their photos appear while it opens.

- Move all PhotoKit calls off the main thread (3.1).
- Add the debug main-thread watchdog.
- Fix the missing-library and burst bugs (3.7).
- Show the "Opening your Photos library…" state (3.1a).
- **Done when:** the main thread is never blocked for more than 250 ms, both
  with a fake library that takes a minute to open (tests) and with the real
  library (manual).

### 4.3 Measurable progress in the core

- Stage-based `ScanProgress` with totals, overall %, and time left; tested.
- Chunked library reader with an up-front count; the
  `PhotoLibraryProviding` protocol gains a count and a chunked fetch.
- Throttled progress events (at most 4 a second).
- **Done when:** tests with a 200,000-asset fake library show progress rising
  steadily to 100%, with rows written before the end.

### 4.4 Progress UI

- Toolbar ring and popover, first-index screen, Sources panel bars, Dock
  progress, menu bar line (3.3).
- **Done when:** screenshots show each, mid-index, with a slowed fake library
  in a debug build.

### 4.5 This week first, and live fill-in

- Priority fetch of the current windows for the Photos library (3.4).
- Periodic reload during long indexes.
- **Done when:** with a large library, this week's photos show within
  seconds of adding it.

### 4.6 Stop, resume, incremental changes

- Stop and Resume, the saved stopped flag, and resume after quit (3.5).
- Incremental library changes via change details (3.6).
- **Done when:** editing one photo's date in Photos updates the index in
  under a second, without a full resync.

### 4.7 Verify on the real library

- Run the manual checklist on the 29 GB external-drive library.
- Record time to first photos, total index time, and memory use.

## 5. Decisions

| # | Question | Answer |
|---|---|---|
| 5.1 | What did "unresponsive" look like? | The main window stopped redrawing. After it went behind another window, switching back left it blank. Force Quit listed the app as not responding. This matches the blocked main thread in 2.0. |
| 5.2 | Library size and storage | 9,755 photos and 362 videos. "Optimize Mac Storage" off (no iCloud). APFS volume on a USB 4-bay enclosure. The Mac had just been upgraded from macOS 15 and the library not opened since. |
| 5.3 | Pause and Cancel | Both useful: stopping during a backup reduces disk contention. Pause is an edge case, so only if simple. Resolved as one Stop/Resume control (3.5), which covers both at little cost. |
| 5.4 | Dock progress | Wanted, especially when the window is slow to redraw. Included (3.3). |

## 6. Open questions

1. **Count mismatch.** The index held 10,747 library items, but Photos shows
   9,755 photos. The 992 extra may be items Photos counts differently
   (for example, hidden or shared-library items). Check what the asset fetch
   includes during step 4.3, and match Photos' count if it's a fetch-option
   difference.

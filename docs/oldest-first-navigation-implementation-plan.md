# Plan: Oldest-First Navigation

Status: steps 4.1–4.4 done (manual checks pending); 4.5 to do.
Trigger: it's easy to step back from last year, one year at a time, but
hard to start at the oldest photos and move forward in time.

## 1. Goal

The user can start at their oldest photos and travel forward, year by year,
as easily as they travel back today.

- **Jump to either end.** One click or shortcut reaches the oldest or the
  most recent year.
- **Choose a direction.** An "Oldest years first" setting starts at the
  oldest year and points every control forward in time.
- **Keep going.** → at the end of a year continues into the next year in
  the chosen direction.
- **Clear words.** Year buttons say **Earlier Year** and **Later Year**, in
  both directions.

## 2. Decisions

- **Scope.** Jumps (4.2), the direction setting (4.3), and continuing with
  the arrow keys (4.4) ship together. A years overview strip is left for
  later (section 6).
- **Labels in both modes.** "Next Year" meaning *older* confused people.
  The buttons become **Earlier Year** and **Later Year** whatever the
  direction.
- **The right-hand button goes forward.** It always moves in the direction
  of travel, and ⌘] always presses it. So the keys feel the same in both
  modes. Only the labels and arrows on each side swap.
- **Where the toggle lives.** View menu, Settings, and a small button in
  the year bar.
- **Menu bar item and widget unchanged.** They show "a year ago" by design.

## 3. What happens today

- **Years.** `YearNavigator` (core) offers years as "years ago" N = 1, 2,
  3… `initialYear` is the first one. `next(after:)` goes one year further
  back; `previous(before:)` one year more recent.
- **Year bar.** `ViewerView.YearBar`: **◀◀ Previous Year** (more recent,
  ⌘[) on the left, then the title, the year menu, and **Next Year ▶▶**
  (older, ⌘]) on the right.
- **Year menu.** `YearPicker` lists every offered year, newest first, with
  photo counts.
- **Within a year.** `PhotoStepper` (core) steps through the year's photos,
  oldest first. Position `count` is the end card; stepping never leaves the
  year. The end card offers **Next Year: 2023** (older).
- **Opening a year.** `ViewerModel.goToYear(_:)` opens it at its first
  photo.
- **Settings.** `SettingsStore` holds window weeks, empty years, default
  date, and the menu bar item.

## 4. Work plan

### 4.1 Core: direction-aware navigation (done)

Built in `Window/YearDirection.swift` as an extension on `YearNavigator`,
with `YearDirection` and the moves listed below. `next(after:)` and
`previous(before:)` stay unchanged; `earlier(than:)` and `later(than:)`
wrap them. `start(direction:)` and `end(direction:)` name the two ends in
travel order, for the jump shortcuts.

1. **Direction.** Add `YearDirection` with two cases: `.newestFirst`
   (today) and `.oldestFirst`.
2. **Navigator.** Give `YearNavigator` calendar-based moves, so callers
   don't have to think in "years ago":
   - `earlier(than:)` and `later(than:)`: the neighbouring offered years.
   - `forward(from:direction:)` and `back(from:direction:)`: earlier or
     later, depending on the direction.
   - `oldestWithPhotos` and `newestWithPhotos`: the ends. They skip years
     with no photos in the window, even when empty years are shown, so a
     jump never lands on an empty panel.
   - `initialYear(direction:)`: the newest year as today, or the oldest
     year with photos.
   - `ordered(direction:)`: the offered years in travel order, for the year
     menu.
3. **Keep old names working.** `next(after:)` and `previous(before:)`
   become thin wrappers, or are replaced at their few call sites.
4. **Tests.** Cover both directions, with and without empty years, at both
   ends, and with no photos at all.

### 4.2 Jump to either end (done)

1. **Year menu.** At the top: **Oldest Year (2009)** and **Most Recent Year
   (2025)**, then a divider, then the years. The years are listed in travel
   order.
2. **Go menu.** The same two items. Their shortcuts follow the buttons:
   ⇧⌘] jumps to the far end in the direction of travel, and ⇧⌘[ to the
   start. With newest first, ⇧⌘] is Oldest Year; with oldest first, ⇧⌘]
   is Most Recent Year.
3. **Disabled when already there.**

### 4.3 The "Oldest years first" setting (done)

Built as planned, with one change: the year bar button uses the
`arrow.left.arrow.right` icon, as a toggle that's highlighted while oldest
first is on. Travel through years is left to right, so a horizontal icon
fits better than `arrow.up.arrow.down`.

1. **Stored setting.** `SettingsStore.yearDirection`, default
   `.newestFirst`, so nothing changes for current users.
2. **Toggles.**
   - **View menu:** **Oldest Years First**, a checkmark toggle.
   - **Settings:** "Start with the oldest year", in the section with
     window length and empty years.
   - **Year bar:** a small icon button (`arrow.up.arrow.down`) next to the
     year menu. Its help text names the current direction and what a click
     does.
3. **Start year.** On launch, and when the timeline first loads, open at
   `initialYear(direction:)`. Changing the setting doesn't move the user;
   it only re-points the controls.
4. **Year bar.**
   - Newest first: **◀◀ Later Year** on the left, **Earlier Year ▶▶** on
     the right.
   - Oldest first: **◀◀ Earlier Year** on the left, **Later Year ▶▶** on
     the right.
   - ⌘[ and ⌘] press the left and right buttons. Help text gives the
     target year, e.g. "Later year: 2012 (⌘])".
5. **Go menu.** **Earlier Year** and **Later Year**, with ⌘[ or ⌘] on
   whichever is left or right.
6. **End card.** "That's all for 2011", with **Earlier Year: 2010** or
   **Later Year: 2012**, in the direction of travel.
7. **Empty panel.** Its button follows the direction too.

### 4.4 Keep going with the arrow keys (done)

Built with two changes from the steps below:

- **Empty years skipped.** → and ← cross to the next year *with photos*
  (`forwardWithPhotos`, `backWithPhotos` in the core). Landing on an empty
  panel would hide the arrows and stop the walk.
- **No `moveToStart()`.** `goToYear(_:atEnd:)` opens a year at its first
  photo or its end card, which covers both cases.

`-DebugNextPhotoCount <n>` repeats `-DebugNextPhotoAfter`, to check
crossing years without a keyboard.

Seen working on made-up photos (2012–2025): oldest first opens at 2012
with Earlier Year disabled; three → presses go photo, end card, then 2015;
newest first opens at 2025 with Later Year disabled and Earlier Year on
the right.

1. **→ on the end card.** Opens the next year in the direction of travel,
   at its first photo. At the last year, nothing happens.
2. **← on a year's first photo.** Opens the previous year in the direction
   of travel, at its end card. So ← and → retrace each other exactly.
3. **Arrow buttons.** The on-screen arrows follow the keys. They're enabled
   when a move into another year is possible.
4. **Core.** Add `PhotoStepper.moveToStart()`, plus a model method that
   opens a year at its end. `goToYear(_:)` keeps opening at the first
   photo.
5. **Photo Info.** Changing year this way closes Photo Info, as any photo
   change does.

### 4.5 Docs (to do)

- **README.** "Using it": the new labels, jumps, the setting, and arrows
  that carry on into the next year.
- **Proposal.** Update sections 4.3 (navigation) and 5 (the year bar
  sketch and the end card).
- **Checklist.** Manual checks for both directions:
  - launch position;
  - button labels, sides, and ⌘[ / ⌘];
  - jumps by menu and shortcut;
  - the end card;
  - → and ← across years;
  - the setting from all three places.
- **Screenshots.** Retake `viewer.png` with the new labels, from made-up
  sample images.

## 5. Risks

- **Muscle memory.** Users used to **Next Year** on the right going older
  keep that: with newest first, the right-hand button still goes older. Only
  the label changes.
- **Arrow keys leaving the year.** Today → stops at the end card. Carrying
  on could surprise someone who expects it to stop. The end card still
  shows first, so it's a pause, not a jump.

## 6. Later

- **Years overview.** A strip with one tick per year, sized by photo count.
  Click to jump.
- **Remember the last year viewed.** Reopen where the user left off.

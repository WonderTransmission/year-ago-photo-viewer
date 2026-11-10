# Installing Year Ago Photo Viewer

You can install a ready-made copy without Xcode. The download is not
notarized by Apple, so macOS asks you to approve it once. This page explains
how.

## Requirements

- macOS 26 or later
- Apple silicon or Intel Mac

## 1. Download

1. Open the [latest release](https://github.com/WonderTransmission/year-ago-photo-viewer/releases/latest).
2. Under **Assets**, download `YearAgoPhotoViewer-<version>.dmg`.

**Optional: check the download.** The release notes list the file's SHA-256.
In Terminal, compare it with:

```sh
shasum -a 256 ~/Downloads/YearAgoPhotoViewer-*.dmg
```

## 2. Install

1. Double-click the `.dmg` to open it.
2. Drag **Year Ago Photo Viewer** onto the **Applications** folder.
3. Eject the disk image.

## 3. Open it the first time

macOS blocks apps from the internet that Apple hasn't notarized. Approve it
once, using either method below. Later launches open normally.

### Option A: System Settings

1. Open **Year Ago Photo Viewer** from Applications. macOS says it can't be
   opened. Click **Done**.
2. Open **System Settings › Privacy & Security**.
3. Scroll down to **Security**. Next to the message about Year Ago Photo
   Viewer, click **Open Anyway**.
4. Confirm with your password or Touch ID, then click **Open Anyway** again.

### Option B: Terminal

Run this once, then open the app normally:

```sh
xattr -dr com.apple.quarantine "/Applications/Year Ago Photo Viewer.app"
```

This removes the "downloaded from the internet" mark that triggers the check.

## Why isn't it notarized?

Notarizing requires a paid Apple Developer account in the publisher's name.
This project keeps the download unsigned instead. The app is still sandboxed:
it can read only the folders you choose and, if you allow it, your Photos
library. It has no network access.

If you'd rather not run a downloaded app, [build it from source](README.md#building).
It takes a few minutes with Xcode.

## Permissions

- **Folders.** The app reads only folders you pick with **Add Folder…**.
- **Photos.** When you add the Photos library, macOS asks for access. You can
  change this later in **System Settings › Privacy & Security › Photos**.

## What's different in the download

- **No widget.** The widget needs an App Group, which needs a signed build. In
  the download, the widget shows a setup message. The menu bar item works.
- **Updates ask again.** Each new version is a new unsigned build. macOS may
  ask you to approve it again (step 3) and to allow Photos access again.

## Updating

Download the new `.dmg` and drag the app into Applications again, replacing
the old one. Your sources and settings are kept.

## Uninstalling

1. Quit the app, including its menu bar item.
2. Drag **Year Ago Photo Viewer** from Applications to the Trash.
3. Optional: delete its data folder, which holds the photo index and
   settings. In Finder, choose **Go › Go to Folder…** and enter:

   ```
   ~/Library/Containers/com.wondertransmission.YearAgoPhotoViewer
   ```

   Your photos are never stored there and are not affected.

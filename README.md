# Year Ago Photo Viewer

A small macOS app that shows the photos you took around this time in past
years. Step through last year's photos from the past week. Then step back a
year, and another.

**Status:** early development. See [docs/proposal.md](docs/proposal.md) for
the design and [docs/implementation-plan.md](docs/implementation-plan.md) for
the build plan.

## Requirements

- macOS 26 or later
- Xcode 27 or later

## Building

1. Copy the signing template:

   ```sh
   cp Config/Local.xcconfig.template Config/Local.xcconfig
   ```

2. Optional: edit `Config/Local.xcconfig` to set your bundle ID prefix and
   development team. Without a team, the app is signed ad hoc, which is fine
   for local use. Git ignores this file.

3. Open `YearAgoPhotoViewer.xcodeproj` and run the **YearAgoPhotoViewer**
   scheme. Or build from the command line:

   ```sh
   xcodebuild -project YearAgoPhotoViewer.xcodeproj \
     -scheme YearAgoPhotoViewer -configuration Debug build
   ```

## Testing

Core logic lives in a Swift package with its own tests:

```sh
swift test --package-path Packages/YearAgoCore
```

## Privacy

The app reads photos only. It never modifies them. It has no network access
and sends no telemetry.

## License

MIT. See [LICENSE](LICENSE).

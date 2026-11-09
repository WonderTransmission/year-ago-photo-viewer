import CoreServices
import Foundation

/// Calls a handler when anything changes under a folder, using FSEvents.
///
/// FSEvents coalesces changes over `latency` seconds, which debounces bursts
/// such as a large copy. The handler runs on a private queue.
final class FolderWatcher {
    private let handler: @Sendable () -> Void
    private let queue = DispatchQueue(label: "YearAgoPhotoViewer.FolderWatcher")
    private var stream: FSEventStreamRef?

    init(url: URL, latency: TimeInterval = 2, handler: @escaping @Sendable () -> Void) {
        self.handler = handler

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().handler()
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot))
        else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    deinit {
        stop()
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

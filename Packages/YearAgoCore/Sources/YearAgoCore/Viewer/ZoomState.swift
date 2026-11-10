import CoreGraphics

/// Magnification and pan for the photo on screen.
///
/// `scale` 1 means "fit": the whole photo is visible. `offset` moves the
/// magnified photo, and is clamped so its edges never pull inside the
/// viewport. The viewer resets this whenever it moves to another photo.
public struct ZoomState: Equatable, Sendable {
    public static let minScale: Double = 1
    public static let maxScale: Double = 8
    /// Zoom In multiplies by this; Zoom Out divides.
    public static let step: Double = 1.5
    /// Double-click zooms to this from fit.
    public static let doubleClickScale: Double = 2.5

    public private(set) var scale: Double = 1
    public private(set) var offset: CGSize = .zero

    public init() {}

    /// True when magnified beyond fit.
    public var isZoomed: Bool { scale > Self.minScale + 0.001 }

    /// The scale as a whole percentage, e.g. 250.
    public var percent: Int { Int((scale * 100).rounded()) }

    /// Back to fit.
    public mutating func reset() {
        self = ZoomState()
    }

    public mutating func zoomIn(layout: Layout) {
        setScale(scale * Self.step, layout: layout)
    }

    public mutating func zoomOut(layout: Layout) {
        setScale(scale / Self.step, layout: layout)
    }

    /// Fit ↔ `doubleClickScale`.
    public mutating func toggle(layout: Layout) {
        if isZoomed {
            reset()
        } else {
            setScale(Self.doubleClickScale, layout: layout)
        }
    }

    /// Sets the scale, clamped to `minScale...maxScale`. The offset scales
    /// with it, so the same spot stays near the centre, then is clamped.
    public mutating func setScale(_ newScale: Double, layout: Layout) {
        let clamped = min(max(newScale, Self.minScale), Self.maxScale)
        let ratio = clamped / scale
        scale = clamped
        offset = layout.clamp(CGSize(width: offset.width * ratio, height: offset.height * ratio), scale: scale)
    }

    /// Sets the pan offset, clamped to the photo's edges.
    public mutating func setOffset(_ newOffset: CGSize, layout: Layout) {
        offset = layout.clamp(newOffset, scale: scale)
    }

    /// The photo's size when fitted in the viewport, and the viewport size.
    public struct Layout: Equatable, Sendable {
        public var fitted: CGSize
        public var viewport: CGSize

        public init(fitted: CGSize, viewport: CGSize) {
            self.fitted = fitted
            self.viewport = viewport
        }

        /// Fits `imageSize` inside `viewport`, keeping its aspect ratio.
        public init(imageSize: CGSize, viewport: CGSize) {
            guard imageSize.width > 0, imageSize.height > 0 else {
                self.init(fitted: .zero, viewport: viewport)
                return
            }
            let ratio = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
            self.init(fitted: CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio),
                      viewport: viewport)
        }

        /// Limits an offset so the scaled photo still covers the viewport
        /// wherever it is larger than the viewport, and stays centred
        /// wherever it is smaller.
        public func clamp(_ offset: CGSize, scale: Double) -> CGSize {
            let maxX = max(0, (fitted.width * scale - viewport.width) / 2)
            let maxY = max(0, (fitted.height * scale - viewport.height) / 2)
            return CGSize(width: min(max(offset.width, -maxX), maxX),
                          height: min(max(offset.height, -maxY), maxY))
        }
    }
}

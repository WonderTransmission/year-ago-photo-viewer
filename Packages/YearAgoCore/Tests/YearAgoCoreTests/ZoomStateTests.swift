import CoreGraphics
import Testing
@testable import YearAgoCore

@Suite struct ZoomStateTests {
    /// A 4:3 photo in an 800 × 400 viewport fits at 533 × 400.
    let layout = ZoomState.Layout(imageSize: CGSize(width: 4000, height: 3000),
                                  viewport: CGSize(width: 800, height: 400))

    @Test func fitsKeepingAspectRatio() {
        #expect(abs(layout.fitted.width - 533.33) < 0.01)
        #expect(layout.fitted.height == 400)
    }

    @Test func startsAtFit() {
        let zoom = ZoomState()
        #expect(zoom.scale == 1)
        #expect(zoom.offset == .zero)
        #expect(!zoom.isZoomed)
        #expect(zoom.percent == 100)
    }

    @Test func zoomInAndOutStayWithinLimits() {
        var zoom = ZoomState()
        zoom.zoomIn(layout: layout)
        #expect(zoom.scale == 1.5)
        #expect(zoom.isZoomed)
        for _ in 0..<20 { zoom.zoomIn(layout: layout) }
        #expect(zoom.scale == ZoomState.maxScale)
        for _ in 0..<20 { zoom.zoomOut(layout: layout) }
        #expect(zoom.scale == ZoomState.minScale)
        #expect(!zoom.isZoomed)
    }

    @Test func doubleClickTogglesAndResetsPan() {
        var zoom = ZoomState()
        zoom.toggle(layout: layout)
        #expect(zoom.scale == ZoomState.doubleClickScale)
        zoom.setOffset(CGSize(width: 100, height: 50), layout: layout)
        zoom.toggle(layout: layout)
        #expect(zoom == ZoomState())
    }

    @Test func panIsClampedToThePhotosEdges() {
        var zoom = ZoomState()
        zoom.setScale(2, layout: layout)
        // Scaled photo: 1066.7 × 800 in an 800 × 400 viewport.
        zoom.setOffset(CGSize(width: 10_000, height: -10_000), layout: layout)
        #expect(abs(zoom.offset.width - 133.33) < 0.01)
        #expect(zoom.offset.height == -200)
    }

    @Test func noPanAtFit() {
        var zoom = ZoomState()
        zoom.setOffset(CGSize(width: 50, height: 50), layout: layout)
        #expect(zoom.offset == .zero)
    }

    @Test func zoomingOutPullsThePanBackIn() {
        var zoom = ZoomState()
        zoom.setScale(4, layout: layout)
        zoom.setOffset(CGSize(width: 10_000, height: 10_000), layout: layout)
        zoom.setScale(1, layout: layout)
        #expect(zoom.offset == .zero)
    }

    @Test func emptyImageGivesNoPan() {
        let empty = ZoomState.Layout(imageSize: .zero, viewport: CGSize(width: 800, height: 400))
        #expect(empty.fitted == .zero)
        var zoom = ZoomState()
        zoom.setScale(3, layout: empty)
        zoom.setOffset(CGSize(width: 99, height: 99), layout: empty)
        #expect(zoom.offset == .zero)
    }
}

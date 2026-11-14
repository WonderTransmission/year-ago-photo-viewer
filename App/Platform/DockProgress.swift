import AppKit

/// Shows indexing progress on the Dock icon: the app icon with a progress
/// bar and percentage along the bottom. Visible even when the window is
/// hidden or behind others (plan section 3.3).
@MainActor
final class DockProgress {
    private var shownPercent: Int?
    private var shownIndeterminate = false

    /// Updates the Dock icon. Pass nil to restore the plain icon. Redraws
    /// only when the whole percentage changes.
    func update(fraction: Double?, indeterminate: Bool) {
        guard let fraction else {
            guard shownPercent != nil else { return }
            shownPercent = nil
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.display()
            return
        }
        let percent = Int((min(max(fraction, 0), 1) * 100).rounded(.down))
        guard percent != shownPercent || indeterminate != shownIndeterminate else { return }
        shownPercent = percent
        shownIndeterminate = indeterminate

        let image = Self.render(percent: percent, indeterminate: indeterminate,
                                size: NSApp.dockTile.size)
        let view = NSImageView(image: image)
        view.frame = NSRect(origin: .zero, size: NSApp.dockTile.size)
        NSApp.dockTile.contentView = view
        NSApp.dockTile.display()
        #if DEBUG
        Self.debugSave(image)
        #endif
    }

    /// The app icon with a bar and percentage label near the bottom.
    static func render(percent: Int, indeterminate: Bool, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSApp.applicationIconImage.draw(in: rect)

            let barHeight = rect.height * 0.12
            let inset = rect.width * 0.12
            let bar = NSRect(x: inset, y: rect.height * 0.10,
                             width: rect.width - inset * 2, height: barHeight)
            let radius = barHeight / 2

            // Track: a dark outline and light fill, readable on any icon.
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: bar.insetBy(dx: -2, dy: -2), xRadius: radius + 2, yRadius: radius + 2).fill()
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()

            if !indeterminate {
                let filled = NSRect(x: bar.minX, y: bar.minY,
                                    width: max(barHeight, bar.width * CGFloat(percent) / 100), height: bar.height)
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
            }

            // Percentage label above the bar.
            let text = indeterminate ? "…" : "\(percent)%"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: rect.height * 0.16, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let label = NSAttributedString(string: text, attributes: attributes)
            let labelSize = label.size()
            let pill = NSRect(x: rect.midX - labelSize.width / 2 - 8, y: bar.maxY + rect.height * 0.04,
                              width: labelSize.width + 16, height: labelSize.height + 2)
            NSColor.black.withAlphaComponent(0.65).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            label.draw(at: NSPoint(x: pill.minX + 8, y: pill.minY + 1))
            return true
        }
    }

    #if DEBUG
    /// -DebugDockSnapshot <path>: saves each rendered tile as PNG, so the
    /// tile can be checked without capturing the screen.
    private static func debugSave(_ image: NSImage) {
        guard let path = UserDefaults.standard.string(forKey: "DebugDockSnapshot"),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
    #endif
}

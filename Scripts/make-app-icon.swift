// Draws the app icon and writes every macOS size into the asset catalog.
//
// Usage (from the repo root):
//   swift Scripts/make-app-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
//
// The artwork is plain Core Graphics, so the icon is reproducible and free
// of third-party or SF Symbols artwork.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputFolder = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "App/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

let canvas: CGFloat = 1024
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}

/// A photo print: white border, a small landscape inside.
func drawPrint(_ ctx: CGContext, center: CGPoint, size: CGSize, angle: CGFloat,
               sky: [CGColor], hill: CGColor, sun: CGColor?) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let card = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)

    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0, 0, 0, 0.35))
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.setFillColor(color(0.98, 0.97, 0.95))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    let inset: CGFloat = 26
    let picture = card.insetBy(dx: inset, dy: inset).offsetBy(dx: 0, dy: inset * 0.6)
    let pictureRect = CGRect(x: picture.minX, y: picture.minY + inset * 0.6,
                             width: picture.width, height: picture.height - inset * 1.2)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: pictureRect, cornerWidth: 8, cornerHeight: 8, transform: nil))
    ctx.clip()
    let gradient = CGGradient(colorsSpace: sRGB, colors: sky as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: pictureRect.maxY),
                           end: CGPoint(x: 0, y: pictureRect.minY), options: [])
    if let sun {
        ctx.setFillColor(sun)
        ctx.fillEllipse(in: CGRect(x: pictureRect.minX + pictureRect.width * 0.62,
                                   y: pictureRect.minY + pictureRect.height * 0.52,
                                   width: pictureRect.width * 0.2, height: pictureRect.width * 0.2))
    }
    ctx.setFillColor(hill)
    ctx.move(to: CGPoint(x: pictureRect.minX, y: pictureRect.minY))
    ctx.addLine(to: CGPoint(x: pictureRect.minX, y: pictureRect.minY + pictureRect.height * 0.35))
    ctx.addQuadCurve(to: CGPoint(x: pictureRect.maxX, y: pictureRect.minY + pictureRect.height * 0.22),
                     control: CGPoint(x: pictureRect.midX, y: pictureRect.minY + pictureRect.height * 0.62))
    ctx.addLine(to: CGPoint(x: pictureRect.maxX, y: pictureRect.minY))
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()
    ctx.restoreGState()
}

/// A round "back in time" badge: a counter-clockwise arrow around a dot.
func drawBadge(_ ctx: CGContext, center: CGPoint, radius: CGFloat) {
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(0, 0, 0, 0.3))
    ctx.setFillColor(color(0.13, 0.36, 0.78))
    ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    let arcRadius = radius * 0.56
    ctx.setStrokeColor(color(1, 1, 1))
    ctx.setLineWidth(radius * 0.16)
    ctx.setLineCap(.round)
    let start: CGFloat = .pi * 0.15, end: CGFloat = .pi * 1.75
    ctx.addArc(center: center, radius: arcRadius, startAngle: start, endAngle: end, clockwise: false)
    ctx.strokePath()

    // Arrowhead at the arc's start, pointing backwards (clockwise).
    let tip = CGPoint(x: center.x + arcRadius * cos(start), y: center.y + arcRadius * sin(start))
    let head = radius * 0.3
    ctx.setFillColor(color(1, 1, 1))
    ctx.move(to: CGPoint(x: tip.x + head * 0.55, y: tip.y + head * 0.5))
    ctx.addLine(to: CGPoint(x: tip.x - head * 0.55, y: tip.y + head * 0.5))
    ctx.addLine(to: CGPoint(x: tip.x, y: tip.y - head * 0.55))
    ctx.closePath()
    ctx.fillPath()

    // Clock hands.
    ctx.setLineWidth(radius * 0.12)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + arcRadius * 0.6))
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + arcRadius * 0.45, y: center.y - arcRadius * 0.15))
    ctx.strokePath()
}

func drawIcon() -> CGImage {
    let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8,
                        bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // macOS icon grid: an 824 pt body centred on the 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.3))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0.95, 0.55, 0.3))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let background = CGGradient(colorsSpace: sRGB,
                                colors: [color(1.0, 0.78, 0.42), color(0.93, 0.42, 0.33), color(0.55, 0.24, 0.45)] as CFArray,
                                locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])

    drawPrint(ctx, center: CGPoint(x: 470, y: 540), size: CGSize(width: 470, height: 400), angle: 9,
              sky: [color(0.55, 0.72, 0.86), color(0.82, 0.88, 0.92)], hill: color(0.42, 0.55, 0.42), sun: nil)
    drawPrint(ctx, center: CGPoint(x: 500, y: 490), size: CGSize(width: 500, height: 420), angle: -6,
              sky: [color(0.99, 0.66, 0.38), color(0.99, 0.86, 0.6)], hill: color(0.33, 0.27, 0.42),
              sun: color(1, 0.97, 0.85))
    drawBadge(ctx, center: CGPoint(x: 735, y: 285), radius: 118)
    ctx.restoreGState()
    return ctx.makeImage()!
}

func scaled(_ image: CGImage, to pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Could not write \(url.path)")
}

try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
let master = drawIcon()
// (points, scale) pairs required for a macOS app icon.
let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in slots {
    let pixels = points * scale
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    writePNG(scaled(master, to: pixels), to: outputFolder.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputFolder.appendingPathComponent("Contents.json"))
print("Wrote \(slots.count) icon sizes to \(outputFolder.path)")

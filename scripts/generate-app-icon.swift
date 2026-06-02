#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("KnowledgedMac/Assets.xcassets/AppIcon.appiconset")

struct Slot {
    let size: Int
    let scale: Int

    var pixels: Int { size * scale }
    var filename: String { "AppIcon-\(pixels).png" }
}

let slots = [
    Slot(size: 16, scale: 1),
    Slot(size: 16, scale: 2),
    Slot(size: 32, scale: 1),
    Slot(size: 32, scale: 2),
    Slot(size: 128, scale: 1),
    Slot(size: 128, scale: 2),
    Slot(size: 256, scale: 1),
    Slot(size: 256, scale: 2),
    Slot(size: 512, scale: 1),
    Slot(size: 512, scale: 2),
]

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size: Int) -> CGImage {
    let width = size
    let height = size
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create CGContext")
    }

    let s = CGFloat(size)
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    ctx.clear(canvas)

    ctx.saveGState()
    ctx.addPath(roundedRect(CGRect(x: 56, y: 56, width: 912, height: 912), radius: 205))
    ctx.clip()

    let backgroundGradient = CGGradient(
        colorsSpace: cs,
        colors: [
            color(0x122238).cgColor,
            color(0x1e5463).cgColor,
            color(0xf2b84b).cgColor,
        ] as CFArray,
        locations: [0, 0.66, 1]
    )!
    ctx.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: 150, y: 930),
        end: CGPoint(x: 890, y: 80),
        options: []
    )

    let glowGradient = CGGradient(
        colorsSpace: cs,
        colors: [
            color(0xffd86a, alpha: 0.56).cgColor,
            color(0xffd86a, alpha: 0).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        glowGradient,
        startCenter: CGPoint(x: 682, y: 676),
        startRadius: 24,
        endCenter: CGPoint(x: 682, y: 676),
        endRadius: 440,
        options: []
    )

    ctx.restoreGState()

    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 34, color: color(0x07111c, alpha: 0.36).cgColor)

    let bookLeft = NSBezierPath()
    bookLeft.move(to: CGPoint(x: 222, y: 276))
    bookLeft.curve(to: CGPoint(x: 500, y: 212), controlPoint1: CGPoint(x: 308, y: 226), controlPoint2: CGPoint(x: 410, y: 204))
    bookLeft.line(to: CGPoint(x: 500, y: 714))
    bookLeft.curve(to: CGPoint(x: 238, y: 738), controlPoint1: CGPoint(x: 414, y: 760), controlPoint2: CGPoint(x: 306, y: 774))
    bookLeft.curve(to: CGPoint(x: 222, y: 276), controlPoint1: CGPoint(x: 216, y: 644), controlPoint2: CGPoint(x: 214, y: 414))
    bookLeft.close()

    let bookRight = NSBezierPath()
    bookRight.move(to: CGPoint(x: 524, y: 212))
    bookRight.curve(to: CGPoint(x: 802, y: 276), controlPoint1: CGPoint(x: 614, y: 204), controlPoint2: CGPoint(x: 716, y: 226))
    bookRight.curve(to: CGPoint(x: 786, y: 738), controlPoint1: CGPoint(x: 810, y: 414), controlPoint2: CGPoint(x: 808, y: 644))
    bookRight.curve(to: CGPoint(x: 524, y: 714), controlPoint1: CGPoint(x: 718, y: 774), controlPoint2: CGPoint(x: 610, y: 760))
    bookRight.close()

    ctx.addPath(bookLeft.cgPath)
    ctx.setFillColor(color(0xf7faf7).cgColor)
    ctx.fillPath()

    ctx.addPath(bookRight.cgPath)
    ctx.setFillColor(color(0xffcf64).cgColor)
    ctx.fillPath()

    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(color(0x102034).cgColor)
    ctx.setLineWidth(34)
    ctx.addPath(bookLeft.cgPath)
    ctx.strokePath()
    ctx.addPath(bookRight.cgPath)
    ctx.strokePath()

    ctx.setStrokeColor(color(0x102034, alpha: 0.28).cgColor)
    ctx.setLineWidth(12)
    for y in [344, 430, 516, 602] as [CGFloat] {
        ctx.move(to: CGPoint(x: 292, y: y))
        ctx.addCurve(to: CGPoint(x: 452, y: y + 20), control1: CGPoint(x: 342, y: y + 24), control2: CGPoint(x: 404, y: y + 28))
        ctx.strokePath()
    }

    ctx.setStrokeColor(color(0x102034).cgColor)
    ctx.setLineWidth(24)
    ctx.move(to: CGPoint(x: 512, y: 218))
    ctx.addLine(to: CGPoint(x: 512, y: 740))
    ctx.strokePath()

    ctx.setStrokeColor(color(0xfff0a3).cgColor)
    ctx.setLineWidth(28)
    for segment in [
        (CGPoint(x: 512, y: 812), CGPoint(x: 512, y: 870)),
        (CGPoint(x: 380, y: 774), CGPoint(x: 338, y: 816)),
        (CGPoint(x: 644, y: 774), CGPoint(x: 686, y: 816)),
        (CGPoint(x: 320, y: 658), CGPoint(x: 260, y: 658)),
        (CGPoint(x: 724, y: 658), CGPoint(x: 784, y: 658)),
    ] {
        ctx.move(to: segment.0)
        ctx.addLine(to: segment.1)
        ctx.strokePath()
    }

    ctx.setFillColor(color(0xffffff, alpha: 0.92).cgColor)
    for point in [
        CGPoint(x: 326, y: 646),
        CGPoint(x: 386, y: 570),
        CGPoint(x: 438, y: 646),
        CGPoint(x: 360, y: 482),
        CGPoint(x: 444, y: 420),
    ] {
        ctx.fillEllipse(in: CGRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34))
    }

    ctx.setStrokeColor(color(0xffffff, alpha: 0.74).cgColor)
    ctx.setLineWidth(12)
    for segment in [
        (CGPoint(x: 326, y: 646), CGPoint(x: 386, y: 570)),
        (CGPoint(x: 386, y: 570), CGPoint(x: 438, y: 646)),
        (CGPoint(x: 386, y: 570), CGPoint(x: 360, y: 482)),
        (CGPoint(x: 360, y: 482), CGPoint(x: 444, y: 420)),
    ] {
        ctx.move(to: segment.0)
        ctx.addLine(to: segment.1)
        ctx.strokePath()
    }

    ctx.setStrokeColor(color(0x102034).cgColor)
    ctx.setLineWidth(26)
    ctx.move(to: CGPoint(x: 404, y: 184))
    ctx.addLine(to: CGPoint(x: 620, y: 184))
    ctx.strokePath()
    ctx.setLineWidth(22)
    ctx.move(to: CGPoint(x: 438, y: 136))
    ctx.addLine(to: CGPoint(x: 586, y: 136))
    ctx.strokePath()

    guard let image = ctx.makeImage() else {
        fatalError("Could not render icon")
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fatalError("Could not create PNG destination for \(url.path)")
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not write \(url.path)")
    }
}

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for slot in slots {
    writePNG(drawIcon(size: slot.pixels), to: iconset.appendingPathComponent(slot.filename))
}

let images = slots.map { slot -> [String: String] in
    [
        "filename": slot.filename,
        "idiom": "mac",
        "scale": "\(slot.scale)x",
        "size": "\(slot.size)x\(slot.size)",
    ]
}
let contents: [String: Any] = [
    "images": images,
    "info": [
        "author": "xcode",
        "version": 1,
    ],
]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: iconset.appendingPathComponent("Contents.json"), options: .atomic)

print("Generated \(slots.count) macOS app icon renditions in \(iconset.path)")

#!/usr/bin/env swift
import AppKit
import Foundation

// Renders the Turing Enigma app icon and packages it as a real .icns file.
// Usage: swift Scripts/generate-icon.swift [output.icns] [preview-1024.png]

let arguments = CommandLine.arguments
let outputURL = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "Sources/App/Resources/AppIcon.icns")
let previewURL = arguments.count > 2 ? URL(fileURLWithPath: arguments[2]) : nil
let canvasSize: CGFloat = 1024

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let ink = rgb(16, 18, 20)
let brass = rgb(198, 157, 83)
let brassLight = rgb(236, 207, 144)
let brassDark = rgb(91, 66, 30)
let ivory = rgb(242, 234, 211)

let masterRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize),
    pixelsHigh: Int(canvasSize),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: masterRep)
NSGraphicsContext.current?.imageInterpolation = .high
NSGraphicsContext.current?.shouldAntialias = true

let center = NSPoint(x: 512, y: 512)

// MARK: - Tile

let tileRect = NSRect(x: 84, y: 84, width: 856, height: 856)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 192, yRadius: 192)

// Soft cast shadow on the transparent canvas.
NSGraphicsContext.saveGraphicsState()
let tileShadow = NSShadow()
tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
tileShadow.shadowBlurRadius = 46
tileShadow.shadowOffset = NSSize(width: 0, height: -18)
tileShadow.set()
ink.setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
tile.addClip()

// Graphite body.
let body = NSGradient(colorsAndLocations:
    (rgb(55, 61, 65), 0.0),
    (rgb(31, 35, 38), 0.46),
    (rgb(12, 14, 16), 1.0)
)!
body.draw(in: tileRect, angle: -90)

// Warm workshop glow from the upper left.
let glow = NSGradient(colorsAndLocations:
    (rgb(236, 176, 79, 0.23), 0.0),
    (rgb(236, 176, 79, 0.06), 0.55),
    (rgb(236, 176, 79, 0.0), 1.0)
)!
glow.draw(
    fromCenter: NSPoint(x: 300, y: 790),
    radius: 8,
    toCenter: NSPoint(x: 300, y: 790),
    radius: 760,
    options: []
)

// Fine diagonal brushing.
NSGraphicsContext.saveGraphicsState()
tile.addClip()
for index in 0..<120 {
    let offset = CGFloat(index) * 11 - 220
    let line = NSBezierPath()
    line.move(to: NSPoint(x: offset, y: 20))
    line.line(to: NSPoint(x: offset + 420, y: 1040))
    line.lineWidth = 1
    rgb(255, 255, 255, 0.012).setStroke()
    line.stroke()
}
NSGraphicsContext.restoreGraphicsState()

// Inset rim.
NSGraphicsContext.saveGraphicsState()
tile.addClip()
let rim = NSBezierPath(roundedRect: tileRect.insetBy(dx: 3, dy: 3), xRadius: 189, yRadius: 189)
rim.lineWidth = 3
brass.withAlphaComponent(0.75).setStroke()
rim.stroke()
let innerRim = NSBezierPath(roundedRect: tileRect.insetBy(dx: 14, dy: 14), xRadius: 178, yRadius: 178)
innerRim.lineWidth = 1.5
rgb(255, 255, 255, 0.07).setStroke()
innerRim.stroke()
NSGraphicsContext.restoreGraphicsState()

// MARK: - Rotor

let discRadius: CGFloat = 342
let faceRadius: CGFloat = 300
let medallionRadius: CGFloat = 208

// Shadow beneath the rotor.
NSGraphicsContext.saveGraphicsState()
let rotorShadow = NSShadow()
rotorShadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
rotorShadow.shadowBlurRadius = 32
rotorShadow.shadowOffset = NSSize(width: 0, height: -12)
rotorShadow.set()
NSColor.black.setFill()
NSBezierPath(ovalIn: NSRect(
    x: center.x - discRadius,
    y: center.y - discRadius,
    width: discRadius * 2,
    height: discRadius * 2
)).fill()
NSGraphicsContext.restoreGraphicsState()

// 26 brass teeth, one for each Enigma letter.
for index in 0..<26 {
    NSGraphicsContext.saveGraphicsState()
    let angle = CGFloat(index) / 26 * 2 * .pi
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byRadians: angle)
    transform.concat()

    let tooth = NSBezierPath(
        roundedRect: NSRect(x: -23, y: 336, width: 46, height: 74),
        xRadius: 9,
        yRadius: 9
    )
    let metal = NSGradient(colorsAndLocations:
        (rgb(247, 222, 163), 0.0),
        (rgb(190, 147, 72), 0.45),
        (rgb(112, 81, 34), 1.0)
    )!
    metal.draw(in: tooth, angle: 90)
    tooth.lineWidth = 2
    rgb(52, 37, 16, 0.9).setStroke()
    tooth.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

// Rotor body.
let bodyDisc = NSBezierPath(ovalIn: NSRect(
    x: center.x - discRadius,
    y: center.y - discRadius,
    width: discRadius * 2,
    height: discRadius * 2
))
NSGradient(colorsAndLocations:
    (rgb(217, 180, 112), 0.0),
    (rgb(160, 121, 57), 0.5),
    (rgb(75, 54, 23), 1.0)
)!.draw(in: bodyDisc, angle: -90)
bodyDisc.lineWidth = 4
rgb(43, 31, 13).setStroke()
bodyDisc.stroke()

// Recessed ring.
let recess = NSBezierPath(ovalIn: NSRect(
    x: center.x - 318,
    y: center.y - 318,
    width: 636,
    height: 636
))
NSGradient(colorsAndLocations:
    (rgb(20, 22, 24), 0.0),
    (rgb(50, 45, 37), 0.62),
    (rgb(25, 27, 29), 1.0)
)!.draw(in: recess, angle: 90)
recess.lineWidth = 2
brassLight.withAlphaComponent(0.65).setStroke()
recess.stroke()

// Face of the rotor.
let face = NSBezierPath(ovalIn: NSRect(
    x: center.x - faceRadius,
    y: center.y - faceRadius,
    width: faceRadius * 2,
    height: faceRadius * 2
))
NSGradient(colorsAndLocations:
    (rgb(59, 61, 60), 0.0),
    (rgb(25, 27, 28), 0.55),
    (rgb(10, 11, 12), 1.0)
)!.draw(in: face, angle: -90)
face.lineWidth = 3
rgb(8, 9, 10).setStroke()
face.stroke()

// Letter tick marks.
for index in 0..<26 {
    let angle = CGFloat(index) / 26 * 2 * .pi - .pi / 2
    let outer: CGFloat = index % 2 == 0 ? 286 : 278
    let tick = NSBezierPath()
    tick.move(to: NSPoint(
        x: center.x + cos(angle) * 248,
        y: center.y + sin(angle) * 248
    ))
    tick.line(to: NSPoint(
        x: center.x + cos(angle) * outer,
        y: center.y + sin(angle) * outer
    ))
    tick.lineWidth = index % 2 == 0 ? 4 : 2.5
    brassLight.withAlphaComponent(index % 2 == 0 ? 0.9 : 0.48).setStroke()
    tick.stroke()
}

// Inner brass collar.
let collar = NSBezierPath(ovalIn: NSRect(
    x: center.x - 232,
    y: center.y - 232,
    width: 464,
    height: 464
))
collar.lineWidth = 9
NSGradient(colorsAndLocations:
    (brassLight, 0.0),
    (brass, 0.45),
    (brassDark, 1.0)
)!.draw(in: collar, angle: -90)

// Ivory medallion.
let medallion = NSBezierPath(ovalIn: NSRect(
    x: center.x - medallionRadius,
    y: center.y - medallionRadius,
    width: medallionRadius * 2,
    height: medallionRadius * 2
))
NSGraphicsContext.saveGraphicsState()
let medallionShadow = NSShadow()
medallionShadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
medallionShadow.shadowBlurRadius = 18
medallionShadow.shadowOffset = NSSize(width: 0, height: -6)
medallionShadow.set()
ivory.setFill()
medallion.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colorsAndLocations:
    (rgb(252, 247, 231), 0.0),
    (rgb(238, 229, 207), 0.55),
    (rgb(208, 197, 169), 1.0)
)!.draw(in: medallion, angle: -90)
medallion.lineWidth = 11
brassDark.setStroke()
medallion.stroke()
let medallionBevel = NSBezierPath(ovalIn: NSRect(
    x: center.x - medallionRadius + 7,
    y: center.y - medallionRadius + 7,
    width: (medallionRadius - 7) * 2,
    height: (medallionRadius - 7) * 2
))
medallionBevel.lineWidth = 2.5
brassLight.setStroke()
medallionBevel.stroke()

// Hairline inlay inside the medallion.
let inlay = NSBezierPath(ovalIn: NSRect(
    x: center.x - 188,
    y: center.y - 188,
    width: 376,
    height: 376
))
inlay.lineWidth = 2
brassDark.withAlphaComponent(0.45).setStroke()
inlay.stroke()

// Index notch: a ruby dot at 12 o'clock.
let ruby = NSBezierPath(ovalIn: NSRect(
    x: center.x - 9,
    y: center.y + discRadius - 8,
    width: 18,
    height: 18
))
NSGraphicsContext.saveGraphicsState()
let rubyGlow = NSShadow()
rubyGlow.shadowColor = rgb(205, 68, 46, 0.85)
rubyGlow.shadowBlurRadius = 12
rubyGlow.set()
rgb(176, 55, 38).setFill()
ruby.fill()
NSGraphicsContext.restoreGraphicsState()
ruby.lineWidth = 2
rgb(79, 22, 16).setStroke()
ruby.stroke()

// Cast-iron screws in the tile corners.
for point in [NSPoint(x: 166, y: 858), NSPoint(x: 858, y: 858),
              NSPoint(x: 166, y: 166), NSPoint(x: 858, y: 166)] {
    let screw = NSBezierPath(ovalIn: NSRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20))
    NSGradient(colorsAndLocations:
        (rgb(206, 176, 115), 0.0),
        (rgb(105, 81, 43), 1.0)
    )!.draw(in: screw, angle: -90)
    screw.lineWidth = 2
    rgb(43, 31, 13, 0.8).setStroke()
    screw.stroke()
    let slot = NSBezierPath()
    slot.move(to: NSPoint(x: point.x - 5, y: point.y - 5))
    slot.line(to: NSPoint(x: point.x + 5, y: point.y + 5))
    slot.lineWidth = 2
    rgb(38, 28, 13, 0.8).setStroke()
    slot.stroke()
}

// The letter E — enamel inlaid into the ivory medallion.
let letter = "E" as NSString
let font = NSFont(name: "NewYork-Bold", size: 300)
    ?? NSFont(name: "Georgia-Bold", size: 300)
    ?? NSFont.systemFont(ofSize: 300, weight: .bold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: rgb(30, 28, 24)
]
let letterSize = letter.size(withAttributes: attributes)
let letterOrigin = NSPoint(
    x: center.x - letterSize.width / 2,
    y: center.y - letterSize.height / 2 + 8
)
NSGraphicsContext.saveGraphicsState()
let letterShadow = NSShadow()
letterShadow.shadowColor = NSColor.white.withAlphaComponent(0.6)
letterShadow.shadowBlurRadius = 2
letterShadow.shadowOffset = NSSize(width: 0, height: -2)
letterShadow.set()
letter.draw(at: letterOrigin, withAttributes: attributes)
NSGraphicsContext.restoreGraphicsState()

// Vignette and top sheen.
let vignette = NSGradient(colorsAndLocations:
    (NSColor.black.withAlphaComponent(0.0), 0.0),
    (NSColor.black.withAlphaComponent(0.34), 1.0)
)!
vignette.draw(
    fromCenter: center,
    radius: 320,
    toCenter: center,
    radius: 660,
    options: [.drawsAfterEndingLocation]
)
let sheen = NSGradient(colorsAndLocations:
    (NSColor.white.withAlphaComponent(0.07), 0.0),
    (NSColor.white.withAlphaComponent(0.0), 1.0)
)!
sheen.draw(
    fromCenter: NSPoint(x: 360, y: 860),
    radius: 20,
    toCenter: NSPoint(x: 360, y: 860),
    radius: 620,
    options: []
)

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

let masterImage = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
masterImage.addRepresentation(masterRep)

// MARK: - Export

func pngData(_ representation: NSBitmapImageRep) throws -> Data {
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "TuringEnigmaIcon", code: 1)
    }
    return data
}

func scaled(_ image: NSImage, pixels: Int) throws -> NSBitmapImageRep {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
        throw NSError(domain: "TuringEnigmaIcon", code: 2)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    return representation
}

let fileManager = FileManager.default
let iconsetURL = fileManager.temporaryDirectory
    .appendingPathComponent("TuringEnigma-\(UUID().uuidString).iconset", isDirectory: true)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconsetURL) }

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in variants {
    let representation = try scaled(masterImage, pixels: pixels)
    try pngData(representation).write(to: iconsetURL.appendingPathComponent(name))
}

try fileManager.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
let errorPipe = Pipe()
iconutil.standardError = errorPipe
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    FileHandle.standardError.write(Data("iconutil failed: \(message)\n".utf8))
    exit(3)
}

if let previewURL {
    try fileManager.createDirectory(
        at: previewURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData(try scaled(masterImage, pixels: 1024)).write(to: previewURL)
    print(previewURL.path)
}
print(outputURL.path)

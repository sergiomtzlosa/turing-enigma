import AppKit
import SceneKit
import CoreGraphics
import TuringEnigmaCore

/// Deterministic procedural texture generation. Every surface in the app is
/// produced here; there are no bundled photographic assets.
enum TextureFactory {
    struct RNG {
        private var state: UInt64
        init(seed: UInt64) { state = seed | 1 }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
        mutating func unit() -> Double {
            Double(next() >> 11) / Double(UInt64(1) << 53)
        }
        mutating func range(_ lower: Double, _ upper: Double) -> Double {
            lower + (upper - lower) * unit()
        }
    }

    static func image(size: CGSize, draw: (CGContext, CGSize) -> Void) -> NSImage {
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: size)
        }
        rep.size = size
        guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(size: size)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let ctx = graphics.cgContext
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        draw(ctx, size)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    static func wood(seed: UInt64, light: NSColor, dark: NSColor, size: CGSize = CGSize(width: 1024, height: 512)) -> NSImage {
        image(size: size) { ctx, size in
            var rng = RNG(seed: seed)
            let colors = [dark.cgColor, light.cgColor, dark.blended(withFraction: 0.28, of: .black)?.cgColor ?? dark.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.48, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
            }

            // Long, wandering grain.
            for _ in 0..<240 {
                let y = rng.range(0, Double(size.height))
                let amp = rng.range(2, 17)
                let wavelength = rng.range(120, 620)
                let phase = rng.range(0, .pi * 2)
                let alpha = rng.range(0.025, 0.13)
                ctx.setStrokeColor((rng.unit() > 0.42 ? NSColor.black : NSColor.white).withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(rng.range(0.5, 2.3))
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: y))
                var x: Double = 0
                while x <= Double(size.width) {
                    let yy = y + sin(x / wavelength * .pi * 2 + phase) * amp + sin(x / (wavelength * 0.23) + phase) * amp * 0.18
                    path.addLine(to: CGPoint(x: x, y: yy))
                    x += 6
                }
                ctx.addPath(path)
                ctx.strokePath()
            }

            // Pores and flecks.
            for _ in 0..<4200 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                let length = rng.range(0.6, 5.5)
                let alpha = rng.range(0.03, 0.16)
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(rng.range(0.35, 1.1))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + length, y: y + rng.range(-0.7, 0.7)))
                ctx.strokePath()
            }

            // A few knots.
            for _ in 0..<4 {
                let cx = rng.range(80, Double(size.width) - 80)
                let cy = rng.range(60, Double(size.height) - 60)
                let rx = rng.range(10, 34)
                let ry = rng.range(5, 18)
                for ring in 0..<10 {
                    let expand = 1.0 + Double(ring) * 0.30
                    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.07 + Double(ring) * 0.008).cgColor)
                    ctx.setLineWidth(1.1)
                    ctx.strokeEllipse(in: CGRect(
                        x: cx - rx * expand,
                        y: cy - ry * expand,
                        width: rx * 2 * expand,
                        height: ry * 2 * expand
                    ))
                }
            }

            // Soft highlight along the top.
            if let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                NSColor.white.withAlphaComponent(0.07).cgColor,
                NSColor.white.withAlphaComponent(0).cgColor
            ] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: size.height * 0.55), options: [])
            }
        }
    }

    static func crinkle(seed: UInt64, base: NSColor, size: CGSize = CGSize(width: 512, height: 512)) -> NSImage {
        image(size: size) { ctx, size in
            var rng = RNG(seed: seed)
            ctx.setFillColor(base.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))

            for _ in 0..<24000 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                let r = rng.range(0.35, 1.8)
                let light = rng.unit() > 0.48
                ctx.setFillColor((light ? NSColor.white : NSColor.black).withAlphaComponent(rng.range(0.018, 0.075)).cgColor)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }

            // Wrinkled paint ridges.
            for _ in 0..<700 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                let length = rng.range(2, 18)
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(rng.range(0.04, 0.14)).cgColor)
                ctx.setLineWidth(rng.range(0.5, 1.7))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addCurve(
                    to: CGPoint(x: x + length, y: y + rng.range(-3, 3)),
                    control1: CGPoint(x: x + length * 0.3, y: y + rng.range(-5, 5)),
                    control2: CGPoint(x: x + length * 0.7, y: y + rng.range(-5, 5))
                )
                ctx.strokePath()
            }

            // Subtle patina blooms.
            for _ in 0..<16 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                let radius = rng.range(20, 95)
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                    NSColor(calibratedRed: 0.58, green: 0.65, blue: 0.52, alpha: 0.08).cgColor,
                    NSColor(calibratedRed: 0.58, green: 0.65, blue: 0.52, alpha: 0).cgColor
                ] as CFArray, locations: [0, 1]) {
                    ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: radius, options: [])
                }
            }
        }
    }

    static func brushedMetal(seed: UInt64, base: NSColor, size: CGSize = CGSize(width: 512, height: 512)) -> NSImage {
        image(size: size) { ctx, size in
            var rng = RNG(seed: seed)
            ctx.setFillColor(base.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<6500 {
                let y = rng.range(0, Double(size.height))
                let alpha = rng.range(0.015, 0.095)
                ctx.setStrokeColor((rng.unit() > 0.5 ? NSColor.white : NSColor.black).withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(rng.range(0.25, 1.2))
                let x = rng.range(0, Double(size.width))
                let length = rng.range(18, 230)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: min(Double(size.width), x + length), y: y + rng.range(-0.4, 0.4)))
                ctx.strokePath()
            }
            for _ in 0..<25 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.05).cgColor)
                ctx.setLineWidth(1)
                ctx.strokeEllipse(in: CGRect(x: x, y: y, width: rng.range(2, 20), height: rng.range(1, 8)))
            }
        }
    }

    static func bakelite(seed: UInt64, size: CGSize = CGSize(width: 512, height: 512)) -> NSImage {
        image(size: size) { ctx, size in
            var rng = RNG(seed: seed)
            ctx.setFillColor(NSColor(calibratedRed: 0.075, green: 0.058, blue: 0.045, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<160 {
                let y = rng.range(0, Double(size.height))
                let amplitude = rng.range(2, 18)
                ctx.setStrokeColor(NSColor(calibratedRed: 0.22, green: 0.14, blue: 0.085, alpha: rng.range(0.025, 0.09)).cgColor)
                ctx.setLineWidth(rng.range(0.5, 2.4))
                ctx.move(to: CGPoint(x: 0, y: y))
                for x in stride(from: 0.0, through: Double(size.width), by: 8) {
                    ctx.addLine(to: CGPoint(x: x, y: y + sin(x / 90 + y) * amplitude))
                }
                ctx.strokePath()
            }
            for _ in 0..<9000 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                ctx.setFillColor((rng.unit() > 0.5 ? NSColor.white : NSColor.black).withAlphaComponent(rng.range(0.015, 0.05)).cgColor)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: rng.range(0.4, 1.7), height: rng.range(0.4, 1.7)))
            }
        }
    }

    static func ivory(seed: UInt64, size: CGSize = CGSize(width: 512, height: 512)) -> NSImage {
        image(size: size) { ctx, size in
            var rng = RNG(seed: seed)
            ctx.setFillColor(NSColor(calibratedRed: 0.80, green: 0.76, blue: 0.65, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<120 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                let length = rng.range(30, 220)
                ctx.setStrokeColor(NSColor(calibratedRed: 0.60, green: 0.53, blue: 0.38, alpha: rng.range(0.02, 0.08)).cgColor)
                ctx.setLineWidth(rng.range(0.5, 2.0))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addCurve(
                    to: CGPoint(x: x + length, y: y + rng.range(-18, 18)),
                    control1: CGPoint(x: x + length * 0.3, y: y + rng.range(-20, 20)),
                    control2: CGPoint(x: x + length * 0.7, y: y + rng.range(-20, 20))
                )
                ctx.strokePath()
            }
            for _ in 0..<14 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                let radius = rng.range(8, 42)
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                    NSColor(calibratedRed: 0.60, green: 0.48, blue: 0.27, alpha: 0.08).cgColor,
                    NSColor(calibratedRed: 0.60, green: 0.48, blue: 0.27, alpha: 0).cgColor
                ] as CFArray, locations: [0, 1]) {
                    ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: radius, options: [])
                }
            }
        }
    }

    static func paper(seed: UInt64, size: CGSize = CGSize(width: 512, height: 512)) -> NSImage {
        image(size: size) { ctx, size in
            var rng = RNG(seed: seed)
            ctx.setFillColor(NSColor(calibratedRed: 0.78, green: 0.72, blue: 0.58, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<9000 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                ctx.setStrokeColor((rng.unit() > 0.5 ? NSColor.white : NSColor.black).withAlphaComponent(rng.range(0.012, 0.045)).cgColor)
                ctx.setLineWidth(0.5)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + rng.range(-5, 5), y: y + rng.range(-1, 1)))
                ctx.strokePath()
            }
            // Faint ruled handwriting guidelines.
            for row in 0..<8 {
                let y = Double(size.height) * 0.12 + Double(row) * 36
                ctx.setStrokeColor(NSColor(calibratedRed: 0.35, green: 0.31, blue: 0.22, alpha: 0.09).cgColor)
                ctx.setLineWidth(0.6)
                ctx.move(to: CGPoint(x: 24, y: y))
                ctx.addLine(to: CGPoint(x: Double(size.width) - 24, y: y))
                ctx.strokePath()
            }
            for _ in 0..<3 {
                let x = rng.range(40, Double(size.width) - 40)
                let y = rng.range(40, Double(size.height) - 40)
                let radius = rng.range(18, 65)
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                    NSColor(calibratedRed: 0.42, green: 0.26, blue: 0.12, alpha: 0.12).cgColor,
                    NSColor(calibratedRed: 0.42, green: 0.26, blue: 0.12, alpha: 0).cgColor
                ] as CFArray, locations: [0, 1]) {
                    ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: radius, options: [])
                }
            }
        }
    }

    static func brick(seed: UInt64, size: CGSize = CGSize(width: 1024, height: 512)) -> NSImage {
        image(size: size) { ctx, size in
            var rng = RNG(seed: seed)
            ctx.setFillColor(NSColor(calibratedRed: 0.17, green: 0.14, blue: 0.12, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            let rowHeight: CGFloat = 62
            let brickWidth: CGFloat = 124
            var row = 0
            var y: CGFloat = -10
            while y < size.height {
                let offset: CGFloat = row % 2 == 0 ? 0 : brickWidth / 2
                var x = -offset
                while x < size.width {
                    let inset: CGFloat = 3
                    let rect = CGRect(x: x + inset, y: y + inset, width: brickWidth - inset * 2, height: rowHeight - inset * 2)
                    let warm = rng.range(0.28, 0.48)
                    let color = NSColor(
                        calibratedRed: warm,
                        green: warm * rng.range(0.55, 0.72),
                        blue: warm * rng.range(0.42, 0.57),
                        alpha: 1
                    )
                    ctx.setFillColor(color.cgColor)
                    ctx.fill(rect)
                    // Brick face variation.
                    for _ in 0..<90 {
                        let px = rng.range(Double(rect.minX), Double(rect.maxX))
                        let py = rng.range(Double(rect.minY), Double(rect.maxY))
                        ctx.setFillColor((rng.unit() > 0.45 ? NSColor.black : NSColor.white).withAlphaComponent(rng.range(0.02, 0.08)).cgColor)
                        ctx.fillEllipse(in: CGRect(x: px, y: py, width: rng.range(0.5, 3), height: rng.range(0.5, 2)))
                    }
                    // Chipped edges.
                    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.20).cgColor)
                    ctx.setLineWidth(1)
                    ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
                    x += brickWidth
                }
                row += 1
                y += rowHeight
            }
            // Mortar grime and damp patches.
            for _ in 0..<12 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                let radius = rng.range(60, 220)
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                    NSColor(calibratedWhite: 0.06, alpha: 0.16).cgColor,
                    NSColor(calibratedWhite: 0.06, alpha: 0).cgColor
                ] as CFArray, locations: [0, 1]) {
                    ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: radius, options: [])
                }
            }
        }
    }

    static func concrete(seed: UInt64, size: CGSize = CGSize(width: 1024, height: 1024)) -> NSImage {
        image(size: size) { ctx, size in
            var rng = RNG(seed: seed)
            ctx.setFillColor(NSColor(calibratedRed: 0.30, green: 0.31, blue: 0.30, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<26000 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                let light = rng.unit() > 0.5
                ctx.setFillColor((light ? NSColor.white : NSColor.black).withAlphaComponent(rng.range(0.01, 0.055)).cgColor)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: rng.range(0.4, 3), height: rng.range(0.4, 3)))
            }
            for _ in 0..<8 {
                var x = rng.range(40, Double(size.width) - 40)
                var y = rng.range(40, Double(size.height) - 40)
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(rng.range(0.10, 0.24)).cgColor)
                ctx.setLineWidth(rng.range(0.6, 1.8))
                ctx.move(to: CGPoint(x: x, y: y))
                for _ in 0..<14 {
                    x += rng.range(-24, 28)
                    y += rng.range(-9, 9)
                    ctx.addLine(to: CGPoint(x: x, y: y))
                }
                ctx.strokePath()
            }
            for _ in 0..<8 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                    NSColor(calibratedWhite: 0.06, alpha: 0.10).cgColor,
                    NSColor(calibratedWhite: 0.06, alpha: 0).cgColor
                ] as CFArray, locations: [0, 1]) {
                    ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: x, y: y), startRadius: 10, endCenter: CGPoint(x: x, y: y), endRadius: rng.range(120, 340), options: [])
                }
            }
        }
    }

    static func letterBand(seed: UInt64, dark: Bool, size: CGSize = CGSize(width: 2048, height: 256)) -> NSImage {
        image(size: size) { ctx, size in
            var rng = RNG(seed: seed)
            let background = dark ? NSColor(calibratedWhite: 0.075, alpha: 1) : NSColor(calibratedRed: 0.78, green: 0.73, blue: 0.61, alpha: 1)
            let foreground = dark ? NSColor(calibratedRed: 0.92, green: 0.88, blue: 0.78, alpha: 1) : NSColor(calibratedWhite: 0.10, alpha: 1)
            ctx.setFillColor(background.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            let cell = size.width / 26
            for index in 0..<26 {
                let x = CGFloat(index) * cell
                ctx.setStrokeColor((dark ? NSColor.white : NSColor.black).withAlphaComponent(0.12).cgColor)
                ctx.setLineWidth(1.5)
                ctx.move(to: CGPoint(x: x, y: 8))
                ctx.addLine(to: CGPoint(x: x, y: size.height - 8))
                ctx.strokePath()
                let letter = String(Alphabet.letter(at: index)) as NSString
                let font = NSFont(name: "AvenirNextCondensed-DemiBold", size: 118) ?? NSFont.systemFont(ofSize: 118, weight: .semibold)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
                let letterSize = letter.size(withAttributes: attributes)
                letter.draw(at: CGPoint(x: x + (cell - letterSize.width) / 2, y: 52), withAttributes: attributes)
                let number = String(format: "%02d", index + 1) as NSString
                let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 21, weight: .medium)
                number.draw(at: CGPoint(x: x + cell / 2 - 8, y: 18), withAttributes: [.font: numberFont, .foregroundColor: foreground.withAlphaComponent(0.62)])
                // Small index mark at the top edge.
                ctx.setFillColor(NSColor(calibratedRed: 0.76, green: 0.22, blue: 0.14, alpha: 0.9).cgColor)
                ctx.fill(CGRect(x: x + cell / 2 - 2, y: size.height - 11, width: 4, height: 8))
            }
            // Slight wear.
            for _ in 0..<900 {
                let x = rng.range(0, Double(size.width))
                let y = rng.range(0, Double(size.height))
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(rng.range(0.01, 0.04)).cgColor)
                ctx.setLineWidth(0.5)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + rng.range(1, 8), y: y))
                ctx.strokePath()
            }
        }
    }

    static func letterDecal(_ letter: Character, color: NSColor, size: CGSize = CGSize(width: 128, height: 128)) -> NSImage {
        image(size: size) { ctx, size in
            ctx.clear(CGRect(origin: .zero, size: size))
            let text = String(letter) as NSString
            let font = NSFont(name: "AvenirNextCondensed-Bold", size: 92) ?? NSFont.systemFont(ofSize: 92, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .kern: 0.5
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attributes)
        }
    }

    static func outlinedLetterDecal(_ letter: Character, fill: NSColor, outline: NSColor, size: CGSize = CGSize(width: 128, height: 128)) -> NSImage {
        image(size: size) { ctx, size in
            ctx.clear(CGRect(origin: .zero, size: size))
            let text = String(letter) as NSString
            let font = NSFont(name: "AvenirNextCondensed-Bold", size: 88) ?? NSFont.systemFont(ofSize: 88, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: fill,
                .strokeColor: outline,
                .strokeWidth: -7.0,
                .kern: 0.5
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attributes)
        }
    }

    static func textDecal(
        _ text: String,
        size: CGSize,
        font: NSFont,
        color: NSColor,
        background: NSColor? = nil,
        alignment: NSTextAlignment = .center,
        padding: CGFloat = 12
    ) -> NSImage {
        image(size: size) { ctx, size in
            ctx.clear(CGRect(origin: .zero, size: size))
            if let background {
                let path = CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2), cornerWidth: 10, cornerHeight: 10, transform: nil)
                ctx.addPath(path)
                ctx.setFillColor(background.cgColor)
                ctx.fillPath()
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
            let rect = CGRect(x: padding, y: padding, width: size.width - padding * 2, height: size.height - padding * 2)
            (text as NSString).draw(in: rect, withAttributes: attributes)
        }
    }

    static func nameplate(title: String, subtitle: String, size: CGSize = CGSize(width: 1024, height: 256)) -> NSImage {
        image(size: size) { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let gradientColors = [
                NSColor(calibratedRed: 0.52, green: 0.41, blue: 0.22, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.80, green: 0.67, blue: 0.39, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.46, green: 0.35, blue: 0.18, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors, locations: [0, 0.46, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
            }
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(8)
            ctx.stroke(rect.insetBy(dx: 9, dy: 9))
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(rect.insetBy(dx: 16, dy: 16))
            let titleFont = NSFont(name: "AvenirNextCondensed-DemiBold", size: 86) ?? NSFont.systemFont(ofSize: 86, weight: .semibold)
            let subtitleFont = NSFont(name: "AvenirNextCondensed-Medium", size: 30) ?? NSFont.systemFont(ofSize: 30, weight: .medium)
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: NSColor(calibratedWhite: 0.09, alpha: 0.88),
                .kern: 3
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 0.74),
                .kern: 5
            ]
            let titleSize = (title as NSString).size(withAttributes: titleAttributes)
            (title as NSString).draw(at: CGPoint(x: (size.width - titleSize.width) / 2, y: size.height * 0.45), withAttributes: titleAttributes)
            let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttributes)
            (subtitle as NSString).draw(at: CGPoint(x: (size.width - subtitleSize.width) / 2, y: size.height * 0.25), withAttributes: subtitleAttributes)
            // Engraved shadow.
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: 40, y: 30))
            ctx.addLine(to: CGPoint(x: size.width - 40, y: 30))
            ctx.strokePath()
        }
    }

    static func instructionPlate(size: CGSize = CGSize(width: 900, height: 600)) -> NSImage {
        image(size: size) { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.setFillColor(NSColor(calibratedRed: 0.76, green: 0.70, blue: 0.57, alpha: 1).cgColor)
            ctx.fill(rect)
            for _ in 0..<5000 {
                let x = CGFloat.random(in: 0..<size.width)
                let y = CGFloat.random(in: 0..<size.height)
                ctx.setFillColor(NSColor.black.withAlphaComponent(CGFloat.random(in: 0.01...0.04)).cgColor)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
            }
            let headingFont = NSFont(name: "AvenirNextCondensed-DemiBold", size: 44) ?? NSFont.systemFont(ofSize: 44, weight: .semibold)
            let bodyFont = NSFont(name: "AvenirNextCondensed-Regular", size: 21) ?? NSFont.systemFont(ofSize: 21)
            let ink = NSColor(calibratedWhite: 0.12, alpha: 0.88)
            ("GEBRAUCHSANWEISUNG" as NSString).draw(at: CGPoint(x: 44, y: size.height - 76), withAttributes: [.font: headingFont, .foregroundColor: ink, .kern: 2])
            let lines = [
                "1.  Deckel öffnen. Walzen nach Tagesbefehl einlegen.",
                "2.  Ringstellung an den Walzen einstellen.",
                "3.  Fensterstellung ablesen und notieren.",
                "4.  Stecker nach Schlüsseltafel verbinden.",
                "5.  Taste drücken; Lampe zeigt den Geheimtext.",
                "",
                "Vor dem Funken: Schlüssel prüfen. Nach dem Funken:",
                "Walzenstellung notieren und Gerät zurücksetzen.",
                "",
                "TURING ENIGMA · SIMULATION"
            ]
            var y = size.height - 140
            for line in lines {
                (line as NSString).draw(at: CGPoint(x: 44, y: y), withAttributes: [.font: bodyFont, .foregroundColor: ink])
                y -= 31
            }
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(rect.insetBy(dx: 18, dy: 18))
            // Brass corner pins.
            for point in [CGPoint(x: 34, y: 34), CGPoint(x: size.width - 34, y: 34), CGPoint(x: 34, y: size.height - 34), CGPoint(x: size.width - 34, y: size.height - 34)] {
                ctx.setFillColor(NSColor(calibratedRed: 0.60, green: 0.47, blue: 0.24, alpha: 1).cgColor)
                ctx.fillEllipse(in: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
            }
        }
    }

    static func drumFace(seed: UInt64, color: NSColor, label: String, size: CGSize = CGSize(width: 512, height: 512)) -> NSImage {
        image(size: size) { ctx, size in
            var rng = RNG(seed: seed)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2
            let edge = color.blended(withFraction: 0.42, of: .black) ?? color
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color.cgColor, edge.cgColor, edge.cgColor] as CFArray, locations: [0, 0.65, 1]) {
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            }
            // Concentric machined rings.
            for ring in 1...9 {
                let r = radius * CGFloat(ring) / 10
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(ring % 3 == 0 ? 0.38 : 0.18).cgColor)
                ctx.setLineWidth(ring % 3 == 0 ? 3 : 1.2)
                ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
            // Ticks and rotor index numbers.
            for index in 0..<36 {
                let angle = CGFloat(index) / 36 * .pi * 2
                let inner = radius * (index % 3 == 0 ? 0.72 : 0.80)
                let outer = radius * 0.90
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(index % 3 == 0 ? 0.8 : 0.34).cgColor)
                ctx.setLineWidth(index % 3 == 0 ? 3 : 1)
                ctx.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                ctx.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                ctx.strokePath()
            }
            for index in 0..<12 {
                let angle = CGFloat(index) / 12 * .pi * 2
                let r = radius * 0.67
                let number = String(format: "%02d", index + 1) as NSString
                let font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
                number.draw(
                    at: CGPoint(x: center.x + cos(angle) * r - 8, y: center.y + sin(angle) * r - 10),
                    withAttributes: [.font: font, .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 0.72)]
                )
            }
            // Central hub and locking arrow.
            ctx.setFillColor(NSColor(calibratedRed: 0.30, green: 0.27, blue: 0.22, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - radius * 0.22, y: center.y - radius * 0.22, width: radius * 0.44, height: radius * 0.44))
            ctx.setFillColor(NSColor(calibratedWhite: 0.07, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - radius * 0.15, y: center.y - radius * 0.15, width: radius * 0.30, height: radius * 0.30))
            ctx.setFillColor(NSColor(calibratedWhite: 0.82, alpha: 0.86).cgColor)
            ctx.fill(CGRect(x: center.x - 3, y: center.y + radius * 0.14, width: 6, height: radius * 0.18))
            ctx.setFillColor(NSColor(calibratedRed: 0.88, green: 0.34, blue: 0.18, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - 8, y: center.y + radius * 0.31, width: 16, height: 16))
            // Label near the lower edge.
            let labelFont = NSFont(name: "AvenirNextCondensed-DemiBold", size: 30) ?? NSFont.systemFont(ofSize: 30, weight: .semibold)
            let labelSize = (label as NSString).size(withAttributes: [.font: labelFont])
            (label as NSString).draw(
                at: CGPoint(x: center.x - labelSize.width / 2, y: center.y - radius * 0.53),
                withAttributes: [.font: labelFont, .foregroundColor: NSColor(calibratedWhite: 0.95, alpha: 0.75), .kern: 2]
            )
            // Wear and grime.
            for _ in 0..<280 {
                let angle = rng.range(0, .pi * 2)
                let distance = rng.range(0.20, 0.96) * Double(radius)
                let x = center.x + CGFloat(cos(angle) * distance)
                let y = center.y + CGFloat(sin(angle) * distance)
                ctx.setStrokeColor((rng.unit() > 0.5 ? NSColor.white : NSColor.black).withAlphaComponent(rng.range(0.03, 0.12)).cgColor)
                ctx.setLineWidth(rng.range(0.5, 2.0))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + rng.range(-7, 7), y: y + rng.range(-2, 2)))
                ctx.strokePath()
            }
            // Dark edge vignette.
            if let vignette = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0.55).cgColor] as CFArray, locations: [0.72, 1]) {
                ctx.drawRadialGradient(vignette, startCenter: center, startRadius: radius * 0.70, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
            }
        }
    }

    static func meterFace(size: CGSize = CGSize(width: 512, height: 512)) -> NSImage {        image(size: size) { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.35)
            ctx.setFillColor(NSColor(calibratedRed: 0.80, green: 0.75, blue: 0.63, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.82).cgColor)
            ctx.setLineWidth(3)
            let radius = size.width * 0.38
            let start = Double.pi * 0.82
            let end = Double.pi * 0.18
            ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
            ctx.strokePath()
            for index in 0...10 {
                let t = Double(index) / 10
                let angle = start + (end - start) * t
                let inner = radius - (index % 5 == 0 ? 26 : 14)
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.75).cgColor)
                ctx.setLineWidth(index % 5 == 0 ? 3 : 1.5)
                ctx.move(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                ctx.addLine(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                ctx.strokePath()
                if index % 5 == 0 {
                    let label = "\(index * 10)" as NSString
                    let font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium)
                    label.draw(at: CGPoint(x: center.x + cos(angle) * (radius + 18) - 12, y: center.y + sin(angle) * (radius + 18) - 10), withAttributes: [.font: font, .foregroundColor: NSColor.black.withAlphaComponent(0.8)])
                }
            }
            ctx.setStrokeColor(NSColor(calibratedRed: 0.55, green: 0.12, blue: 0.09, alpha: 0.85).cgColor)
            ctx.setLineWidth(5)
            ctx.addArc(center: center, radius: radius - 10, startAngle: Double.pi * 0.35, endAngle: Double.pi * 0.18, clockwise: true)
            ctx.strokePath()
            ctx.setStrokeColor(NSColor(calibratedWhite: 0.12, alpha: 0.9).cgColor)
            ctx.setLineWidth(4)
            ctx.move(to: center)
            ctx.addLine(to: CGPoint(x: center.x + cos(Double.pi * 0.62) * radius * 0.80, y: center.y + sin(Double.pi * 0.62) * radius * 0.80))
            ctx.strokePath()
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.8).cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24))
            let label = "VOLTS" as NSString
            label.draw(at: CGPoint(x: center.x - 30, y: 28), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.black.withAlphaComponent(0.7)])
        }
    }

    static func glow(size: CGSize = CGSize(width: 256, height: 256), color: NSColor) -> NSImage {
        image(size: size) { ctx, size in
            ctx.clear(CGRect(origin: .zero, size: size))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                color.withAlphaComponent(0.95).cgColor,
                color.withAlphaComponent(0.28).cgColor,
                color.withAlphaComponent(0).cgColor
            ] as CFArray, locations: [0, 0.25, 1]) {
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width / 2, options: [])
            }
        }
    }

    static func selectionRing(size: CGSize = CGSize(width: 512, height: 512)) -> NSImage {
        image(size: size) { ctx, size in
            ctx.clear(CGRect(origin: .zero, size: size))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for (radius, alpha, width) in [(size.width * 0.42, 0.9, 8.0), (size.width * 0.35, 0.35, 3.0)] {
                ctx.setStrokeColor(NSColor(calibratedRed: 0.95, green: 0.80, blue: 0.42, alpha: alpha).cgColor)
                ctx.setLineWidth(width)
                ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                NSColor(calibratedRed: 0.95, green: 0.80, blue: 0.42, alpha: 0.16).cgColor,
                NSColor(calibratedRed: 0.95, green: 0.80, blue: 0.42, alpha: 0).cgColor
            ] as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: size.width * 0.30, endCenter: center, endRadius: size.width * 0.48, options: [])
            }
        }
    }

    static func background(size: CGSize = CGSize(width: 1600, height: 1000)) -> NSImage {
        image(size: size) { ctx, size in
            let colors = [
                NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.075, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.018, green: 0.022, blue: 0.026, alpha: 1).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
            }
            if let vignette = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                NSColor.black.withAlphaComponent(0).cgColor,
                NSColor.black.withAlphaComponent(0.42).cgColor
            ] as CFArray, locations: [0.4, 1]) {
                ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 120, endCenter: CGPoint(x: size.width / 2, y: size.height / 2), endRadius: size.width * 0.72, options: [.drawsAfterEndLocation])
            }
        }
    }

    static func cubeFaces() -> [NSImage] {
        (0..<6).map { face -> NSImage in
            image(size: CGSize(width: 256, height: 256)) { ctx, size in
                let top = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.15, alpha: 1)
                let bottom = NSColor(calibratedRed: 0.025, green: 0.032, blue: 0.04, alpha: 1)
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]) {
                    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])
                }
                // Broad softbox panels.
                let boxes: [(CGFloat, CGFloat, CGFloat, CGFloat, NSColor)] = [
                    (size.width * 0.10, size.height * 0.62, size.width * 0.38, size.height * 0.16, NSColor(calibratedRed: 0.95, green: 0.84, blue: 0.64, alpha: 0.42)),
                    (size.width * 0.60, size.height * 0.70, size.width * 0.25, size.height * 0.10, NSColor(calibratedRed: 0.70, green: 0.82, blue: 1.0, alpha: 0.28)),
                    (size.width * 0.18, size.height * 0.18, size.width * 0.30, size.height * 0.12, NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.30, alpha: 0.18))
                ]
                for (x, y, w, h, color) in boxes {
                    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
                        ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: x + w / 2, y: y + h / 2), startRadius: 4, endCenter: CGPoint(x: x + w / 2, y: y + h / 2), endRadius: max(w, h), options: [])
                    }
                }
                // A faint floor bounce for faces below.
                if face == 3 {
                    ctx.setFillColor(NSColor(calibratedRed: 0.16, green: 0.14, blue: 0.11, alpha: 0.35).cgColor)
                    ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.35))
                }
            }
        }
    }

    static func normalMap(from image: NSImage, strength: CGFloat = 1.6) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = min(1024, cgImage.width)
        let height = min(1024, cgImage.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func luminance(_ x: Int, _ y: Int) -> CGFloat {
            let xx = ((x % width) + width) % width
            let yy = ((y % height) + height) % height
            let index = (yy * width + xx) * 4
            let r = CGFloat(pixels[index]) / 255
            let g = CGFloat(pixels[index + 1]) / 255
            let b = CGFloat(pixels[index + 2]) / 255
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }

        var normals = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let left = luminance(x - 1, y)
                let right = luminance(x + 1, y)
                let up = luminance(x, y + 1)
                let down = luminance(x, y - 1)
                let dx = (left - right) * strength
                let dy = (up - down) * strength
                let length = max(0.0001, sqrt(dx * dx + dy * dy + 1))
                let nx = dx / length
                let ny = dy / length
                let nz = 1 / length
                let index = (y * width + x) * 4
                normals[index] = UInt8(clamping: Int((nx * 0.5 + 0.5) * 255))
                normals[index + 1] = UInt8(clamping: Int((ny * 0.5 + 0.5) * 255))
                normals[index + 2] = UInt8(clamping: Int((nz * 0.5 + 0.5) * 255))
                normals[index + 3] = 255
            }
        }
        let data = Data(normals)
        guard let provider = CGDataProvider(data: data as CFData),
              let normalCG = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else { return nil }
        let result = NSImage(size: NSSize(width: width, height: height))
        result.addRepresentation(NSBitmapImageRep(cgImage: normalCG))
        return result
    }
}

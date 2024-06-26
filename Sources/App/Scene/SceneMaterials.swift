import AppKit
import SceneKit
import TuringEnigmaCore

final class MaterialLibrary {
    static let shared = MaterialLibrary()

    lazy var walnutTexture = TextureFactory.wood(
        seed: 0xA11CE,
        light: NSColor(calibratedRed: 0.34, green: 0.20, blue: 0.105, alpha: 1),
        dark: NSColor(calibratedRed: 0.12, green: 0.065, blue: 0.032, alpha: 1)
    )
    lazy var walnutDarkTexture = TextureFactory.wood(
        seed: 0xBEEF,
        light: NSColor(calibratedRed: 0.25, green: 0.14, blue: 0.075, alpha: 1),
        dark: NSColor(calibratedRed: 0.07, green: 0.035, blue: 0.018, alpha: 1)
    )
    lazy var crinkleTexture = TextureFactory.crinkle(
        seed: 0xC0FFEE,
        base: NSColor(calibratedRed: 0.22, green: 0.27, blue: 0.215, alpha: 1)
    )
    lazy var brassTexture = TextureFactory.brushedMetal(
        seed: 0xB4A55,
        base: NSColor(calibratedRed: 0.59, green: 0.46, blue: 0.22, alpha: 1)
    )
    lazy var steelTexture = TextureFactory.brushedMetal(
        seed: 0x5EED,
        base: NSColor(calibratedRed: 0.34, green: 0.35, blue: 0.36, alpha: 1)
    )
    lazy var bakeliteTexture = TextureFactory.bakelite(seed: 0xBA7E)
    lazy var ivoryTexture = TextureFactory.ivory(seed: 0x1A0B)
    lazy var paperTexture = TextureFactory.paper(seed: 0xFAFA)
    lazy var brickTexture = TextureFactory.brick(seed: 0xB21C)
    lazy var concreteTexture = TextureFactory.concrete(seed: 0xC0AC)
    lazy var letterBandDarkTexture = TextureFactory.letterBand(seed: 0x1E77, dark: true)
    lazy var letterBandCreamTexture = TextureFactory.letterBand(seed: 0xC4EA, dark: false)

    lazy var woodNormal = TextureFactory.normalMap(from: walnutTexture, strength: 1.0)
    lazy var crinkleNormal = TextureFactory.normalMap(from: crinkleTexture, strength: 2.0)
    lazy var brickNormal = TextureFactory.normalMap(from: brickTexture, strength: 1.8)
    lazy var concreteNormal = TextureFactory.normalMap(from: concreteTexture, strength: 1.2)
    lazy var brassNormal = TextureFactory.normalMap(from: brassTexture, strength: 0.35)

    lazy var walnut = makePBR(diffuse: walnutTexture, roughness: 0.44, metalness: 0.0, normal: woodNormal, clearCoat: 0.18)
    lazy var deskWood = makePBR(diffuse: walnutTexture, roughness: 0.64, metalness: 0.0, normal: woodNormal, clearCoat: 0.03)
    lazy var walnutDark = makePBR(diffuse: walnutDarkTexture, roughness: 0.48, metalness: 0.0, normal: woodNormal)
    lazy var brass = makePBR(diffuse: brassTexture, roughness: 0.24, metalness: 0.92, normal: brassNormal, clearCoat: 0.08)
    lazy var agedBrass = makePBR(diffuse: brassTexture, roughness: 0.42, metalness: 0.84, normal: brassNormal)
    lazy var steel = makePBR(diffuse: steelTexture, roughness: 0.32, metalness: 0.90, normal: brassNormal)
    lazy var darkSteel = makePBR(diffuse: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.115, alpha: 1), roughness: 0.38, metalness: 0.78)
    lazy var bluedSteel = makePBR(diffuse: NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.20, alpha: 1), roughness: 0.27, metalness: 0.85, clearCoat: 0.2)
    lazy var bakelite = makePBR(diffuse: bakeliteTexture, roughness: 0.48, metalness: 0.0, clearCoat: 0.28)
    lazy var matteBlack = makePBR(diffuse: bakeliteTexture, roughness: 0.74, metalness: 0.0, clearCoat: 0.02)
    lazy var ivory = makePBR(diffuse: ivoryTexture, roughness: 0.46, metalness: 0.0, clearCoat: 0.18)
    lazy var paper = makePBR(diffuse: paperTexture, roughness: 0.78, metalness: 0.0)
    lazy var crinkle = makePBR(diffuse: crinkleTexture, roughness: 0.69, metalness: 0.16, normal: crinkleNormal)
    lazy var brick = makePBR(diffuse: brickTexture, roughness: 0.91, metalness: 0.0, normal: brickNormal)
    lazy var concrete = makePBR(diffuse: concreteTexture, roughness: 0.86, metalness: 0.0, normal: concreteNormal)
    lazy var rubberBlack = makePBR(diffuse: NSColor(calibratedWhite: 0.045, alpha: 1), roughness: 0.80, metalness: 0.0)
    lazy var rubberRed = makePBR(diffuse: NSColor(calibratedRed: 0.27, green: 0.045, blue: 0.035, alpha: 1), roughness: 0.78, metalness: 0.0)
    lazy var rubberCream = makePBR(diffuse: NSColor(calibratedRed: 0.62, green: 0.55, blue: 0.42, alpha: 1), roughness: 0.80, metalness: 0.0)
    lazy var felt = makePBR(diffuse: NSColor(calibratedRed: 0.035, green: 0.10, blue: 0.075, alpha: 1), roughness: 1.0, metalness: 0.0)

    lazy var glass: SCNMaterial = {
        let material = SCNMaterial()
        material.name = "glass"
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(calibratedWhite: 0.76, alpha: 0.16)
        material.roughness.contents = NSNumber(value: 0.045)
        material.metalness.contents = NSNumber(value: 0.0)
        material.transparency = 0.34
        material.blendMode = .alpha
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.clearCoat.contents = NSNumber(value: 1.0)
        material.clearCoatRoughness.contents = NSNumber(value: 0.03)
        return material
    }()

    lazy var bandDark: SCNMaterial = makePBR(
        diffuse: letterBandDarkTexture,
        roughness: 0.35,
        metalness: 0.0,
        clearCoat: 0.5
    )

    lazy var bandCream: SCNMaterial = makePBR(
        diffuse: letterBandCreamTexture,
        roughness: 0.48,
        metalness: 0.0,
        clearCoat: 0.12
    )

    lazy var background: NSImage = TextureFactory.background()
    lazy var cubeEnvironment: [NSImage] = TextureFactory.cubeFaces()
    lazy var selectionImage: NSImage = TextureFactory.selectionRing()
    lazy var keyDecalMaterial: SCNMaterial = makeDecal(TextureFactory.letterDecal(" ", color: .black))

    var coloredMaterials: [String: SCNMaterial] = [:]
    private var decalMaterials: [String: SCNMaterial] = [:]
    private var glowMaterials: [String: SCNMaterial] = [:]
    private var letterMaterials: [String: SCNMaterial] = [:]
    private var outlinedLetterMaterials: [String: SCNMaterial] = [:]
    private var nameplateMaterials: [String: SCNMaterial] = [:]

    private init() {}

    func makePBR(
        diffuse: Any,
        roughness: CGFloat,
        metalness: CGFloat,
        normal: Any? = nil,
        clearCoat: CGFloat = 0,
        emission: Any? = nil
    ) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = diffuse
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.roughness.contents = NSNumber(value: roughness)
        material.metalness.contents = NSNumber(value: metalness)
        if let normal {
            material.normal.contents = normal
            material.normal.wrapS = .repeat
            material.normal.wrapT = .repeat
        }
        if clearCoat > 0 {
            material.clearCoat.contents = NSNumber(value: clearCoat)
            material.clearCoatRoughness.contents = NSNumber(value: 0.18)
        }
        if let emission {
            material.emission.contents = emission
        }
        material.diffuse.minificationFilter = .linear
        material.diffuse.magnificationFilter = .linear
        material.diffuse.mipFilter = .linear
        return material
    }

    func coloredMetal(_ color: NSColor, roughness: CGFloat = 0.36, metalness: CGFloat = 0.72) -> SCNMaterial {
        let key = "\(color.description)-\(roughness)-\(metalness)"
        if let cached = coloredMaterials[key] { return cached }
        let material = makePBR(diffuse: color, roughness: roughness, metalness: metalness, normal: brassNormal)
        coloredMaterials[key] = material
        return material
    }

    func paintedMetal(_ color: NSColor, roughness: CGFloat = 0.58) -> SCNMaterial {
        let key = "paint-\(color.description)-\(roughness)"
        if let cached = coloredMaterials[key] { return cached }
        let material = makePBR(diffuse: color, roughness: roughness, metalness: 0.22, normal: crinkleNormal)
        coloredMaterials[key] = material
        return material
    }

    func makeDecal(_ image: NSImage) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.transparencyMode = .aOne
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        return material
    }

    func decal(_ image: NSImage, key: String) -> SCNMaterial {
        if let cached = decalMaterials[key] { return cached }
        let material = makeDecal(image)
        decalMaterials[key] = material
        return material
    }

    func letter(_ character: Character, color: NSColor = NSColor(calibratedWhite: 0.06, alpha: 1)) -> SCNMaterial {
        let key = "\(character)-\(color.description)"
        if let cached = letterMaterials[key] { return cached }
        let material = makeDecal(TextureFactory.letterDecal(character, color: color))
        letterMaterials[key] = material
        return material
    }

    func outlinedLetter(_ character: Character, fill: NSColor, outline: NSColor) -> SCNMaterial {
        let key = "\(character)-\(fill.description)-\(outline.description)"
        if let cached = outlinedLetterMaterials[key] { return cached }
        let material = makeDecal(TextureFactory.outlinedLetterDecal(character, fill: fill, outline: outline))
        outlinedLetterMaterials[key] = material
        return material
    }

    func nameplate(_ title: String, subtitle: String) -> SCNMaterial {
        let key = "\(title)-\(subtitle)"
        if let cached = nameplateMaterials[key] { return cached }
        let image = TextureFactory.nameplate(title: title, subtitle: subtitle)
        let material = makePBR(diffuse: image, roughness: 0.32, metalness: 0.62, normal: brassNormal, clearCoat: 0.12)
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        nameplateMaterials[key] = material
        return material
    }

    func glow(color: NSColor, key: String) -> SCNMaterial {
        if let cached = glowMaterials[key] { return cached }
        let image = TextureFactory.glow(color: color)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.transparencyMode = .aOne
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.isDoubleSided = true
        glowMaterials[key] = material
        return material
    }

    func selectionMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = selectionImage
        material.transparencyMode = .aOne
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.isDoubleSided = true
        return material
    }

    func meterMaterial() -> SCNMaterial {
        let image = TextureFactory.meterFace()
        let material = makePBR(diffuse: image, roughness: 0.35, metalness: 0.0, clearCoat: 0.8)
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        return material
    }

    func instructionMaterial() -> SCNMaterial {
        let image = TextureFactory.instructionPlate()
        let material = makePBR(diffuse: image, roughness: 0.65, metalness: 0.0)
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        return material
    }
}

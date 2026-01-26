import AppKit
import SceneKit
import simd
import TuringEnigmaCore

struct SceneCameraConfiguration {
    var target: SCNVector3
    var distance: CGFloat
    var yaw: CGFloat
    var pitch: CGFloat

    /// A true isometric bearing: 45° around the vertical axis and
    /// `atan(1 / sqrt(2))` above the horizon, so all three world axes
    /// foreshorten equally.
    static let isometricYaw = CGFloat.pi / 4
    static let isometricPitch = CGFloat(atan(1.0 / sqrt(2.0)))
}

final class EnigmaSceneRenderer {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let machineRoot = SCNNode()
    let library = MaterialLibrary.shared

    private var keyNodes: [Character: SCNNode] = [:]
    private var keyBaseY: [Character: CGFloat] = [:]
    private var lampLenses: [Character: SCNNode] = [:]
    private var lampGlows: [Character: SCNNode] = [:]
    private var rotorPivots: [SCNNode] = []
    private var rotorWindowLetterNodes: [SCNNode] = []
    private var rotorWindowContainers: [SCNNode] = []
    private var rotorIndexLabels: [SCNNode] = []
    private var rotorNodes: [SCNNode] = []
    private var reflectorLabelNode: SCNNode?
    private var plugboardCableGroup = SCNNode()
    private var plugboardSocketPositions: [Character: SCNVector3] = [:]
    private var backWallGroup = SCNNode()
    private var frontWallGroup = SCNNode()
    private var backFillNode = SCNNode()
    private var backFillNode2 = SCNNode()
    private var backAmbientNode = SCNNode()
    private var highlightNode = SCNNode()
    private var lampOnMaterial: SCNMaterial!
    private var lampOffMaterial: SCNMaterial!
    private var lastPlugSignature = ""
    private var lastReflectorID = ""
    private var lastMachineType: EnigmaMachineType?
    private var lastHighlight: ComponentSelection?

    init() {
        buildRoom()
        buildMachine()
        buildLighting()
        configureCamera()
        scene.background.contents = library.background
        scene.lightingEnvironment.contents = library.cubeEnvironment
        scene.lightingEnvironment.intensity = 0.36
        scene.fogColor = NSColor(calibratedWhite: 0.02, alpha: 1)
        scene.fogStartDistance = 3.0
        scene.fogEndDistance = 9.0
        scene.rootNode.addChildNode(machineRoot)
    }

    // MARK: - Public updates

    func apply(settings: EnigmaSettings, presentation: EnigmaPresentation, selection: ComponentSelection?, animated: Bool = true) {
        if lastMachineType != settings.machineType {
            lastMachineType = settings.machineType
            applyRotorLayout(for: settings)
        }

        if lastReflectorID != settings.reflectorID {
            lastReflectorID = settings.reflectorID
            updateReflectorLabel(settings.reflectorID)
        }

        let positions = presentation.rotorPositions
        for (index, pivot) in rotorPivots.enumerated() where index < positions.count {
            let angle = -CGFloat(positions[index]) / 26.0 * .pi * 2
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.09 : 0
            pivot.eulerAngles.x = angle
            SCNTransaction.commit()
            if index < rotorWindowLetterNodes.count {
                let letter = Alphabet.letter(at: positions[index])
                rotorWindowLetterNodes[index].geometry?.materials = [library.letter(letter, color: NSColor(calibratedRed: 0.94, green: 0.88, blue: 0.74, alpha: 1))]
            }
        }

        for (letter, node) in keyNodes {
            let isPressed = presentation.pressedKey == letter
            let targetY = (keyBaseY[letter] ?? node.position.y) - (isPressed ? 0.0042 : 0)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.055 : 0
            node.position.y = targetY
            SCNTransaction.commit()
        }

        for (letter, lens) in lampLenses {
            let lit = presentation.litLamp == letter
            lens.geometry?.materials = [lit ? lampOnMaterial : lampOffMaterial]
            lampGlows[letter]?.opacity = lit ? 1 : 0
        }

        let signature = settings.normalizedPlugboard.map(\.id).joined(separator: ",")
        if signature != lastPlugSignature {
            lastPlugSignature = signature
            rebuildPlugboardCables(settings.normalizedPlugboard)
        }

        if selection != lastHighlight {
            lastHighlight = selection
            updateHighlight(selection)
        }
    }

    func cameraConfiguration(for preset: CameraPreset) -> SceneCameraConfiguration {
        switch preset {
        case .overview:
            // The default view is a true isometric framing centered on the
            // machine, so Center has a single, predictable state to restore.
            return SceneCameraConfiguration(
                target: SCNVector3(0, 0.96, 0.01),
                distance: 1.55,
                yaw: SceneCameraConfiguration.isometricYaw,
                pitch: SceneCameraConfiguration.isometricPitch
            )
        case .keyboard:
            return SceneCameraConfiguration(target: SCNVector3(0, 0.87, 0.075), distance: 0.61, yaw: 0.26, pitch: 0.48)
        case .rotors:
            return SceneCameraConfiguration(target: SCNVector3(0, 0.91, -0.105), distance: 0.56, yaw: 0.24, pitch: 0.52)
        case .plugboard:
            return SceneCameraConfiguration(target: SCNVector3(0, 0.80, 0.13), distance: 0.55, yaw: 0.10, pitch: 0.16)
        default:
            return cameraConfiguration(for: .overview)
        }
    }

    var defaultCameraConfiguration: SceneCameraConfiguration { cameraConfiguration(for: .overview) }

    /// A free orbit is allowed, so hide the near back wall once the camera has
    /// crossed behind it. Otherwise the wall's dark rear face would fill the
    /// viewport and look like a rendering failure.
    func updateBackWallVisibility(forCameraPosition position: SCNVector3) {
        let isBehind = position.z < -0.70
        backWallGroup.isHidden = isBehind
        backWallGroup.opacity = isBehind ? 0 : 1
        frontWallGroup.isHidden = position.z > 1.30
        // Rear fills, used only from behind, keep the far side of the room and
        // the back of the machine readable instead of nearly black.
        backFillNode.isHidden = !isBehind
        backFillNode2.isHidden = !isBehind
        backAmbientNode.isHidden = !isBehind
    }

    // MARK: - Room and furniture

    private func buildRoom() {
        let floor = Geo.plane(width: 6.0, height: 6.0, material: library.walnutDark, name: "room.floor")
        floor.eulerAngles.x = -.pi / 2
        floor.position = SCNVector3(0, 0, 0)
        floor.castsShadow = false
        scene.rootNode.addChildNode(floor)

        // A complete room shell surrounds the desk. The camera stays inside the
        // side, front, and ceiling planes; only the back wall is close enough to
        // be crossed during a free orbit and is hidden by the camera coordinator.
        let roomPaint = library.makePBR(
            diffuse: NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.20, alpha: 1),
            roughness: 0.92,
            metalness: 0.0,
            emission: NSColor(calibratedRed: 0.035, green: 0.042, blue: 0.036, alpha: 1)
        )
        let shellPaint = SCNMaterial()
        shellPaint.lightingModel = .constant
        shellPaint.diffuse.contents = NSColor(calibratedRed: 0.15, green: 0.18, blue: 0.16, alpha: 1)
        shellPaint.isDoubleSided = true
        let backdropGeometry = SCNSphere(radius: 8.0)
        backdropGeometry.segmentCount = 64
        let backdropMaterial = SCNMaterial()
        backdropMaterial.lightingModel = .constant
        backdropMaterial.diffuse.contents = NSColor(calibratedRed: 0.095, green: 0.115, blue: 0.09, alpha: 1)
        backdropMaterial.isDoubleSided = true
        backdropGeometry.materials = [backdropMaterial]
        let backdrop = SCNNode(geometry: backdropGeometry)
        backdrop.name = "room.backdrop"
        backdrop.castsShadow = false
        scene.rootNode.addChildNode(backdrop)
        frontWallGroup.name = "room.frontWallGroup"
        scene.rootNode.addChildNode(frontWallGroup)
        let frontWall = Geo.box(6.0, 3.2, 0.05, material: roomPaint, name: "room.frontWall")
        frontWall.position = SCNVector3(0, 1.6, 1.35)
        frontWall.castsShadow = false
        frontWallGroup.addChildNode(frontWall)
        for x in [-3.0, 3.0] {
            let sideWall = Geo.box(0.05, 3.2, 6.0, material: shellPaint, name: "room.sideWall")
            sideWall.position = SCNVector3(CGFloat(x), 1.6, 0)
            sideWall.castsShadow = false
            scene.rootNode.addChildNode(sideWall)
        }
        let ceiling = Geo.box(6.0, 0.05, 6.0, material: shellPaint, name: "room.ceiling")
        ceiling.position = SCNVector3(0, 3.2, 0)
        ceiling.castsShadow = false
        scene.rootNode.addChildNode(ceiling)

        // Skirting and a panelled door on the front wall give the rear view the
        // same authored context as the front of the room.
        let frontSkirting = Geo.box(6.0, 0.16, 0.06, material: library.walnutDark)
        frontSkirting.position = SCNVector3(0, 0.08, 1.31)
        frontWallGroup.addChildNode(frontSkirting)
        for x in [-2.96, 2.96] {
            let sideSkirting = Geo.box(0.06, 0.16, 6.0, material: library.walnutDark)
            sideSkirting.position = SCNVector3(CGFloat(x), 0.08, 0)
            scene.rootNode.addChildNode(sideSkirting)
        }
        let doorFrame = Geo.box(0.92, 2.12, 0.08, chamfer: 0.006, material: library.walnutDark)
        doorFrame.position = SCNVector3(-0.95, 1.06, 1.30)
        frontWallGroup.addChildNode(doorFrame)
        let door = Geo.box(0.80, 2.00, 0.04, chamfer: 0.005, material: library.walnut)
        door.position = SCNVector3(-0.95, 1.00, 1.26)
        frontWallGroup.addChildNode(door)
        for y in [0.58, 1.53] {
            let inset = Geo.box(0.56, 0.66, 0.012, chamfer: 0.003, material: library.walnutDark)
            inset.position = SCNVector3(-0.95, CGFloat(y), 1.235)
            frontWallGroup.addChildNode(inset)
        }
        let handle = Geo.sphere(radius: 0.028, material: library.agedBrass)
        handle.position = SCNVector3(-0.60, 1.00, 1.21)
        frontWallGroup.addChildNode(handle)

        // A simple wall clock above the door side of the room.
        let clockRim = Geo.cylinder(radius: 0.20, height: 0.022, material: library.agedBrass, axis: .z, radialSegments: 32)
        clockRim.position = SCNVector3(0.92, 2.18, 1.31)
        frontWallGroup.addChildNode(clockRim)
        let clockFace = Geo.cylinder(radius: 0.17, height: 0.024, material: library.paper, axis: .z, radialSegments: 32)
        clockFace.position = SCNVector3(0.92, 2.18, 1.295)
        frontWallGroup.addChildNode(clockFace)
        for (angle, length) in [(CGFloat.pi / 2, CGFloat(0.12)), (CGFloat(-.pi * 0.35), CGFloat(0.09))] {
            let hand = Geo.box(0.008, length, 0.008, material: library.darkSteel)
            hand.position = SCNVector3(0.92, 2.18, 1.275)
            hand.pivot = SCNMatrix4MakeTranslation(0, -length / 2, 0)
            hand.eulerAngles.z = angle
            frontWallGroup.addChildNode(hand)
        }

        // Wall sconce. Its bulb is the visible source for the rear fill that the
        // renderer enables when the camera orbits behind the desk.
        let sconcePlate = Geo.cylinder(radius: 0.085, height: 0.025, material: library.agedBrass, axis: .z, radialSegments: 28)
        sconcePlate.position = SCNVector3(1.95, 2.20, 1.315)
        frontWallGroup.addChildNode(sconcePlate)
        let sconceArm = Geo.cylinder(radius: 0.012, height: 0.14, material: library.agedBrass, axis: .z, radialSegments: 12)
        sconceArm.position = SCNVector3(1.95, 2.20, 1.25)
        frontWallGroup.addChildNode(sconceArm)
        let sconceShade = SCNCone(topRadius: 0.025, bottomRadius: 0.075, height: 0.07)
        sconceShade.materials = [library.agedBrass]
        let sconceShadeNode = SCNNode(geometry: sconceShade)
        sconceShadeNode.position = SCNVector3(1.95, 2.24, 1.17)
        sconceShadeNode.castsShadow = false
        frontWallGroup.addChildNode(sconceShadeNode)
        let sconceBulb = Geo.sphere(radius: 0.045, material: library.makePBR(
            diffuse: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.44, alpha: 1),
            roughness: 0.15,
            metalness: 0,
            emission: NSColor(calibratedRed: 1.0, green: 0.56, blue: 0.20, alpha: 1)
        ))
        sconceBulb.position = SCNVector3(1.95, 2.19, 1.17)
        sconceBulb.castsShadow = false
        frontWallGroup.addChildNode(sconceBulb)

        // Desk top.
        let deskTop = Geo.box(1.55, 0.055, 0.82, chamfer: 0.008, material: library.deskWood, name: "room.deskTop")
        deskTop.position = SCNVector3(0, 0.725, 0)
        scene.rootNode.addChildNode(deskTop)
        let deskEdge = Geo.box(1.57, 0.018, 0.84, chamfer: 0.006, material: library.walnutDark)
        deskEdge.position = SCNVector3(0, 0.694, 0)
        scene.rootNode.addChildNode(deskEdge)
        for x in [-0.68, 0.68] {
            for z in [-0.31, 0.31] {
                let leg = Geo.box(0.055, 0.69, 0.055, chamfer: 0.006, material: library.walnutDark)
                leg.position = SCNVector3(x, 0.35, z)
                scene.rootNode.addChildNode(leg)
            }
        }

        // Rug under the desk.
        let rug = Geo.plane(width: 2.4, height: 1.5, material: library.felt)
        rug.eulerAngles.x = -.pi / 2
        rug.position = SCNVector3(0, 0.005, 0.35)
        rug.castsShadow = false
        scene.rootNode.addChildNode(rug)

        // Back wall with panelled lower section. The whole assembly is grouped so
        // a free 360° orbit can hide it when the camera moves behind it, rather
        // than filling the viewport with the unlit rear face.
        backWallGroup.name = "room.backWall"
        scene.rootNode.addChildNode(backWallGroup)

        let wall = Geo.box(4.4, 3.2, 0.04, material: library.paintedMetal(NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.145, alpha: 1), roughness: 0.85))
        wall.position = SCNVector3(0, 1.6, -0.78)
        backWallGroup.addChildNode(wall)
        let wainscot = Geo.box(4.4, 0.72, 0.055, material: library.walnutDark)
        wainscot.position = SCNVector3(0, 0.34, -0.755)
        backWallGroup.addChildNode(wainscot)
        let rail = Geo.box(4.4, 0.025, 0.075, chamfer: 0.004, material: library.walnut)
        rail.position = SCNVector3(0, 0.705, -0.745)
        backWallGroup.addChildNode(rail)
        for x in stride(from: -2.0, through: 2.0, by: 0.5) {
            let stile = Geo.box(0.014, 0.66, 0.008, material: library.walnutDark)
            stile.position = SCNVector3(CGFloat(x), 0.34, -0.723)
            backWallGroup.addChildNode(stile)
        }

        // Framed operations map.
        let frame = Geo.box(0.52, 0.38, 0.025, chamfer: 0.006, material: library.walnutDark)
        frame.position = SCNVector3(0.52, 1.25, -0.742)
        backWallGroup.addChildNode(frame)
        let map = Geo.plane(width: 0.46, height: 0.32, material: library.paper)
        map.position = SCNVector3(0.52, 1.25, -0.727)
        backWallGroup.addChildNode(map)
        let mapInk = Geo.textNode(
            text: "NORTH ATLANTIC\nCONVOY ROUTES\n\n  ◇  ◇  ◇\n  1940",
            width: 0.38,
            height: 0.23,
            font: NSFont(name: "AvenirNextCondensed-Medium", size: 20) ?? NSFont.systemFont(ofSize: 20),
            color: NSColor(calibratedRed: 0.22, green: 0.17, blue: 0.10, alpha: 0.8)
        )
        mapInk.position = SCNVector3(0.52, 1.25, -0.724)
        backWallGroup.addChildNode(mapInk)

        // Desk lamp.
        let lampBase = Geo.cylinder(radius: 0.075, height: 0.018, material: library.agedBrass)
        lampBase.position = SCNVector3(-0.58, 0.758, -0.17)
        scene.rootNode.addChildNode(lampBase)
        let stem = Geo.cylinder(radius: 0.008, height: 0.35, material: library.agedBrass)
        stem.position = SCNVector3(-0.58, 0.94, -0.17)
        scene.rootNode.addChildNode(stem)
        let shade = SCNCone(topRadius: 0.042, bottomRadius: 0.115, height: 0.105)
        shade.materials = [library.agedBrass]
        let shadeNode = SCNNode(geometry: shade)
        shadeNode.position = SCNVector3(-0.58, 1.14, -0.17)
        shadeNode.castsShadow = false
        scene.rootNode.addChildNode(shadeNode)
        let bulb = Geo.sphere(radius: 0.026, material: library.makePBR(
            diffuse: NSColor(calibratedRed: 1.0, green: 0.75, blue: 0.38, alpha: 1),
            roughness: 0.15,
            metalness: 0,
            emission: NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.20, alpha: 1)
        ))
        bulb.position = SCNVector3(-0.58, 1.095, -0.17)
        scene.rootNode.addChildNode(bulb)

        // Paper and pencil props.
        let sheet = Geo.plane(width: 0.27, height: 0.19, material: library.paper)
        sheet.eulerAngles.x = -.pi / 2
        sheet.eulerAngles.z = -0.16
        sheet.position = SCNVector3(0.45, 0.755, 0.115)
        scene.rootNode.addChildNode(sheet)
        let ink = Geo.textNode(
            text: "BLETCHLEY PARK\nHUT 6 — 1940\n\nThe weather report\nis the way in.",
            width: 0.22,
            height: 0.145,
            font: NSFont(name: "AvenirNextCondensed-Regular", size: 18) ?? NSFont.systemFont(ofSize: 18),
            color: NSColor(calibratedRed: 0.20, green: 0.15, blue: 0.09, alpha: 0.72),
            alignment: .left
        )
        ink.eulerAngles.x = -.pi / 2
        ink.eulerAngles.z = -0.16
        ink.position = SCNVector3(0.45, 0.756, 0.115)
        scene.rootNode.addChildNode(ink)

        let pencil = Geo.cylinder(radius: 0.004, height: 0.16, material: library.paintedMetal(NSColor(calibratedRed: 0.58, green: 0.34, blue: 0.08, alpha: 1), roughness: 0.7), axis: .z)
        pencil.position = SCNVector3(0.22, 0.765, 0.19)
        pencil.eulerAngles.y = 0.22
        scene.rootNode.addChildNode(pencil)
        let pencilTip = Geo.cylinder(radius: 0.0038, height: 0.018, material: library.darkSteel, axis: .z)
        pencilTip.position = SCNVector3(0.22, 0.765, 0.278)
        pencilTip.eulerAngles.y = 0.22
        scene.rootNode.addChildNode(pencilTip)
    }

    // MARK: - Enigma machine

    private func buildMachine() {
        machineRoot.position = SCNVector3(0, 0.755, 0)
        machineRoot.name = "enigma.root"

        // Walnut case shell.
        let bottom = Geo.box(0.38, 0.018, 0.32, chamfer: 0.006, material: library.walnutDark, name: "enigma.case")
        bottom.position = SCNVector3(0, 0.009, 0)
        machineRoot.addChildNode(bottom)
        for x in [-0.185, 0.185] {
            let side = Geo.box(0.015, 0.105, 0.32, chamfer: 0.005, material: library.walnut, name: "enigma.case")
            side.position = SCNVector3(CGFloat(x), 0.063, 0)
            machineRoot.addChildNode(side)
        }
        let frontWall = Geo.box(0.355, 0.095, 0.014, chamfer: 0.004, material: library.walnut, name: "enigma.case")
        frontWall.position = SCNVector3(0, 0.061, 0.153)
        machineRoot.addChildNode(frontWall)
        let backWall = Geo.box(0.355, 0.105, 0.014, chamfer: 0.004, material: library.walnut, name: "enigma.case")
        backWall.position = SCNVector3(0, 0.063, -0.153)
        machineRoot.addChildNode(backWall)

        let deck = Geo.box(0.36, 0.006, 0.30, chamfer: 0.003, material: library.matteBlack, name: "enigma.case")
        deck.position = SCNVector3(0, 0.105, 0)
        machineRoot.addChildNode(deck)

        // Brass corner protectors and screws.
        for x in [-0.177, 0.177] {
            for z in [-0.145, 0.145] {
                let corner = Geo.box(0.022, 0.02, 0.022, chamfer: 0.003, material: library.agedBrass)
                corner.position = SCNVector3(CGFloat(x), 0.112, CGFloat(z))
                machineRoot.addChildNode(corner)
            }
        }
        for x in [-0.16, 0.16] {
            let screw = Geo.screw(radius: 0.0045, length: 0.0035)
            screw.position = SCNVector3(CGFloat(x), 0.116, 0.15)
            machineRoot.addChildNode(screw)
        }

        buildLid()
        buildKeyboard()
        buildLampboard()
        buildRotorBay()
        buildPlugboard()
        buildCaseFittings()

        highlightNode.name = "selection.highlight"
        highlightNode.geometry = SCNPlane(width: 0.055, height: 0.055)
        highlightNode.geometry?.materials = [library.selectionMaterial()]
        highlightNode.constraints = [SCNBillboardConstraint()]
        highlightNode.opacity = 0
        highlightNode.renderingOrder = 30
        machineRoot.addChildNode(highlightNode)
    }

    private func buildLid() {
        let hinge = SCNNode()
        hinge.name = "enigma.lid"
        hinge.position = SCNVector3(0, 0.115, -0.158)
        machineRoot.addChildNode(hinge)

        let lid = Geo.box(0.38, 0.022, 0.32, chamfer: 0.006, material: library.walnut, name: "enigma.lid")
        lid.position = SCNVector3(0, 0.011, 0.16)
        hinge.addChildNode(lid)

        let inner = Geo.box(0.35, 0.004, 0.29, chamfer: 0.003, material: library.felt)
        inner.position = SCNVector3(0, -0.001, 0.16)
        hinge.addChildNode(inner)

        let plate = Geo.plane(width: 0.28, height: 0.20, material: library.instructionMaterial())
        plate.eulerAngles.x = .pi / 2
        plate.position = SCNVector3(0, -0.0035, 0.15)
        hinge.addChildNode(plate)

        for x in [-0.155, 0.155] {
            let hingeBlock = Geo.box(0.036, 0.012, 0.028, chamfer: 0.003, material: library.agedBrass)
            hingeBlock.position = SCNVector3(CGFloat(x), 0.005, -0.005)
            hinge.addChildNode(hingeBlock)
            let pin = Geo.cylinder(radius: 0.004, height: 0.045, material: library.steel, axis: .x)
            pin.position = SCNVector3(CGFloat(x), 0.005, -0.005)
            hinge.addChildNode(pin)
        }

        hinge.eulerAngles.x = -1.78
    }

    private func buildKeyboard() {
        let panel = Geo.box(0.35, 0.004, 0.125, chamfer: 0.003, material: library.matteBlack, name: "enigma.keyboard")
        panel.position = SCNVector3(0, 0.109, 0.102)
        machineRoot.addChildNode(panel)

        let rows: [[Character]] = [
            Array("QWERTZUIOP"),
            Array("ASDFGHJKL"),
            Array("YXCVBNM")
        ]
        let zRows: [CGFloat] = [0.132, 0.099, 0.066]
        let pitches: [CGFloat] = [0.031, 0.031, 0.031]
        for (rowIndex, row) in rows.enumerated() {
            let pitch = pitches[rowIndex]
            let startX = -CGFloat(row.count - 1) * pitch / 2
            for (columnIndex, letter) in row.enumerated() {
                let x = startX + CGFloat(columnIndex) * pitch
                let z = zRows[rowIndex]
                let base = Geo.cylinder(radius: 0.0145, height: 0.005, material: library.darkSteel, name: "enigma.key.\(letter)")
                base.position = SCNVector3(x, 0.112, z)
                machineRoot.addChildNode(base)
                let rim = Geo.torus(ringRadius: 0.0132, pipeRadius: 0.0012, material: library.agedBrass, radialSegments: 28, pipeSegments: 8, name: "enigma.key.\(letter)")
                rim.eulerAngles.x = .pi / 2
                rim.position = SCNVector3(x, 0.115, z)
                machineRoot.addChildNode(rim)

                let key = Geo.cylinder(radius: 0.0115, height: 0.015, material: library.ivory, name: "enigma.key.\(letter)")
                key.position = SCNVector3(x, 0.117, z)
                let decal = Geo.letterNode(letter, size: 0.0148)
                decal.eulerAngles.x = -.pi / 2
                decal.position = SCNVector3(0, 0.0081, -0.0015)
                decal.renderingOrder = 12
                key.addChildNode(decal)
                machineRoot.addChildNode(key)
                keyNodes[letter] = key
                keyBaseY[letter] = key.position.y
            }
        }

        let label = Geo.textNode(
            text: "T A S T E N",
            width: 0.11,
            height: 0.016,
            font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            color: NSColor(calibratedRed: 0.72, green: 0.63, blue: 0.45, alpha: 0.65)
        )
        label.eulerAngles.x = -.pi / 2
        label.position = SCNVector3(0, 0.114, 0.045)
        machineRoot.addChildNode(label)
    }

    private func buildLampboard() {
        let panel = Geo.box(0.34, 0.006, 0.075, chamfer: 0.003, material: library.matteBlack, name: "enigma.lampboard")
        panel.position = SCNVector3(0, 0.112, -0.032)
        machineRoot.addChildNode(panel)

        lampOnMaterial = library.makePBR(
            diffuse: NSColor(calibratedRed: 0.92, green: 0.58, blue: 0.25, alpha: 0.92),
            roughness: 0.12,
            metalness: 0,
            emission: NSColor(calibratedRed: 1.0, green: 0.52, blue: 0.18, alpha: 1)
        )
        lampOffMaterial = library.makePBR(
            diffuse: NSColor(calibratedRed: 0.36, green: 0.25, blue: 0.14, alpha: 0.95),
            roughness: 0.10,
            metalness: 0.05,
            emission: NSColor(calibratedWhite: 0.025, alpha: 1)
        )
        lampOffMaterial.transparency = 0.94
        lampOnMaterial.transparency = 1

        let rows: [[Character]] = [
            Array("QWERTZUIOP"),
            Array("ASDFGHJKL"),
            Array("YXCVBNM")
        ]
        let zRows: [CGFloat] = [-0.008, -0.034, -0.060]
        let pitch: CGFloat = 0.029
        for (rowIndex, row) in rows.enumerated() {
            let startX = -CGFloat(row.count - 1) * pitch / 2
            for (columnIndex, letter) in row.enumerated() {
                let x = startX + CGFloat(columnIndex) * pitch
                let z = zRows[rowIndex]
                let bezel = Geo.torus(ringRadius: 0.0062, pipeRadius: 0.0012, material: library.agedBrass, radialSegments: 24, pipeSegments: 8, name: "enigma.lamp.\(letter)")
                bezel.eulerAngles.x = .pi / 2
                bezel.position = SCNVector3(x, 0.117, z)
                machineRoot.addChildNode(bezel)
                let lens = Geo.cylinder(radius: 0.0052, height: 0.0015, material: lampOffMaterial, radialSegments: 24, name: "enigma.lamp.\(letter)")
                lens.position = SCNVector3(x, 0.117, z)
                machineRoot.addChildNode(lens)
                let glow = Geo.plane(width: 0.044, height: 0.044, material: library.glow(color: NSColor(calibratedRed: 1.0, green: 0.50, blue: 0.16, alpha: 1), key: "lamp-glow"))
                glow.eulerAngles.x = -.pi / 2
                glow.position = SCNVector3(x, 0.1185, z)
                glow.opacity = 0
                glow.renderingOrder = 20
                machineRoot.addChildNode(glow)
                lampLenses[letter] = lens
                lampGlows[letter] = glow

                let decalMaterial = library.outlinedLetter(letter, fill: NSColor(calibratedWhite: 0.94, alpha: 1), outline: NSColor(calibratedWhite: 0.02, alpha: 0.9))
                let decal = Geo.plane(width: 0.0105, height: 0.0105, material: decalMaterial, name: "enigma.lamp.\(letter)")
                decal.eulerAngles.x = -.pi / 2
                decal.position = SCNVector3(x, 0.1168, z + 0.0100)
                decal.renderingOrder = 12
                machineRoot.addChildNode(decal)
            }
        }

        let label = Geo.textNode(
            text: "L A M P E N F E L D",
            width: 0.16,
            height: 0.014,
            font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            color: NSColor(calibratedRed: 0.70, green: 0.62, blue: 0.46, alpha: 0.6)
        )
        label.eulerAngles.x = -.pi / 2
        label.position = SCNVector3(0, 0.116, -0.073)
        machineRoot.addChildNode(label)
    }

    private func buildRotorBay() {
        // The drums sit proud of the bay in the same way as the real machine:
        // an open-topped well with a low front lip, side rails and a rear bulkhead.
        let bayBase = Geo.box(0.31, 0.034, 0.105, chamfer: 0.006, material: library.darkSteel)
        bayBase.position = SCNVector3(0, 0.120, -0.118)
        machineRoot.addChildNode(bayBase)
        let bayBack = Geo.box(0.31, 0.085, 0.012, chamfer: 0.003, material: library.bakelite)
        bayBack.position = SCNVector3(0, 0.166, -0.169)
        machineRoot.addChildNode(bayBack)
        let bayLip = Geo.box(0.31, 0.019, 0.012, chamfer: 0.003, material: library.darkSteel)
        bayLip.position = SCNVector3(0, 0.143, -0.067)
        machineRoot.addChildNode(bayLip)
        for x in [-0.158, 0.158] {
            let rail = Geo.box(0.012, 0.082, 0.112, chamfer: 0.003, material: library.bakelite)
            rail.position = SCNVector3(CGFloat(x), 0.166, -0.118)
            machineRoot.addChildNode(rail)
            let brassRail = Geo.box(0.007, 0.005, 0.112, chamfer: 0.001, material: library.agedBrass)
            brassRail.position = SCNVector3(CGFloat(x), 0.207, -0.118)
            machineRoot.addChildNode(brassRail)
        }

        // The four rotor pivots. Three are used by Enigma I/M3, four by M4.
        for index in 0..<4 {
            let pivot = SCNNode()
            pivot.name = "enigma.rotor.\(index)"
            pivot.position = SCNVector3(0, 0.166, -0.118)
            machineRoot.addChildNode(pivot)

            let band = SCNCylinder(radius: 0.034, height: 0.030)
            band.radialSegmentCount = 72
            band.materials = [library.bandDark, library.brass, library.brass]
            let drum = SCNNode(geometry: band)
            drum.eulerAngles.z = .pi / 2
            drum.castsShadow = true
            drum.name = "enigma.rotor.\(index)"
            pivot.addChildNode(drum)

            for side in [-0.017, 0.017] {
                let cheek = Geo.cylinder(radius: 0.036, height: 0.0035, material: index % 2 == 0 ? library.agedBrass : library.darkSteel, axis: .x, radialSegments: 48)
                cheek.position.x = CGFloat(side)
                pivot.addChildNode(cheek)
            }
            let axle = Geo.cylinder(radius: 0.004, height: 0.05, material: library.steel, axis: .x, radialSegments: 20)
            pivot.addChildNode(axle)
            rotorPivots.append(pivot)
            rotorNodes.append(pivot)

            let windowContainer = SCNNode()
            windowContainer.position = SCNVector3(0, 0.204, -0.118)
            windowContainer.name = "enigma.rotor.\(index)"
            machineRoot.addChildNode(windowContainer)
            rotorWindowContainers.append(windowContainer)

            let width: CGFloat = 0.047
            let depth: CGFloat = 0.040
            let bar: CGFloat = 0.004
            for (dx, dz, w, d) in [
                (0.0, depth / 2, width, bar),
                (0.0, -depth / 2, width, bar),
                (-width / 2, 0.0, bar, depth),
                (width / 2, 0.0, bar, depth)
            ] {
                let frame = Geo.box(w, 0.004, d, chamfer: 0.001, material: library.darkSteel)
                frame.position = SCNVector3(CGFloat(dx), 0, CGFloat(dz))
                windowContainer.addChildNode(frame)
            }
            let glass = Geo.plane(width: width - 0.008, height: depth - 0.008, material: library.glass)
            glass.eulerAngles.x = .pi / 2
            glass.position.y = 0.005
            windowContainer.addChildNode(glass)

            let letter = Geo.letterNode("A", size: 0.021, color: NSColor(calibratedRed: 0.94, green: 0.88, blue: 0.74, alpha: 1))
            letter.eulerAngles.x = -.pi / 2
            letter.position.y = 0.004
            windowContainer.addChildNode(letter)
            rotorWindowLetterNodes.append(letter)

            let label = Geo.textNode(
                text: "\(index + 1)",
                width: 0.014,
                height: 0.012,
                font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                color: NSColor(calibratedRed: 0.74, green: 0.65, blue: 0.48, alpha: 0.8)
            )
            label.eulerAngles.x = -.pi / 2
            label.position = SCNVector3(0, 0.003, 0.034)
            label.opacity = 0
            windowContainer.addChildNode(label)
            rotorIndexLabels.append(label)
        }

        let bayLabel = Geo.textNode(
            text: "W A L Z E N",
            width: 0.075,
            height: 0.011,
            font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            color: NSColor(calibratedRed: 0.76, green: 0.68, blue: 0.50, alpha: 0.7)
        )
        bayLabel.position = SCNVector3(0, 0.152, -0.061)
        machineRoot.addChildNode(bayLabel)

    }

    private func applyRotorLayout(for settings: EnigmaSettings) {
        let count = settings.rotorIDs.count
        let positions: [CGFloat] = count == 4
            ? [-0.093, -0.031, 0.031, 0.093]
            : [-0.061, 0, 0.061]
        let scale: CGFloat = count == 4 ? 0.80 : 1.0
        for index in 0..<4 {
            let visible = index < count
            rotorPivots[index].isHidden = !visible
            rotorWindowContainers[index].isHidden = !visible
            rotorIndexLabels[index].opacity = visible ? 1 : 0
            if visible {
                rotorPivots[index].position.x = positions[index]
                rotorPivots[index].scale = SCNVector3(scale, scale, scale)
                rotorWindowContainers[index].position.x = positions[index]
                rotorWindowContainers[index].scale = SCNVector3(scale, scale, scale)
            }
        }
    }

    private func updateReflectorLabel(_ id: String) {
        reflectorLabelNode?.removeFromParentNode()
        let plate = Geo.nameplateNode(title: "UKW", subtitle: id.uppercased(), width: 0.075)
        plate.name = "enigma.reflector"
        plate.position = SCNVector3(0, 0.155, -0.184)
        machineRoot.addChildNode(plate)
        reflectorLabelNode = plate
    }

    private func buildPlugboard() {
        let panel = Geo.box(0.355, 0.082, 0.008, chamfer: 0.004, material: library.matteBlack, name: "enigma.plugboard")
        panel.position = SCNVector3(0, 0.055, 0.160)
        machineRoot.addChildNode(panel)

        let heading = Geo.textNode(
            text: "S T E C K E R F E L D",
            width: 0.17,
            height: 0.010,
            font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            color: NSColor(calibratedRed: 0.74, green: 0.65, blue: 0.46, alpha: 0.72)
        )
        heading.position = SCNVector3(0, 0.091, 0.166)
        machineRoot.addChildNode(heading)

        for index in 0..<26 {
            let letter = Alphabet.letter(at: index)
            let row = index / 13
            let column = index % 13
            let x = -0.138 + CGFloat(column) * 0.023
            let y = row == 0 ? 0.037 : 0.070
            let socket = SCNNode()
            socket.name = "enigma.plug.\(letter)"
            socket.position = SCNVector3(x, CGFloat(y), 0.165)
            let bezel = Geo.torus(ringRadius: 0.0047, pipeRadius: 0.0012, material: library.agedBrass, radialSegments: 22, pipeSegments: 8)
            bezel.eulerAngles.x = .pi / 2
            socket.addChildNode(bezel)
            let hole = Geo.cylinder(radius: 0.0035, height: 0.004, material: library.darkSteel, axis: .z, radialSegments: 18)
            hole.position.z = 0.001
            socket.addChildNode(hole)
            machineRoot.addChildNode(socket)
            plugboardSocketPositions[letter] = SCNVector3(x, CGFloat(y), 0.170)

            let label = Geo.letterNode(letter, size: 0.008, color: NSColor(calibratedRed: 0.80, green: 0.72, blue: 0.54, alpha: 0.82))
            label.name = "enigma.plug.\(letter)"
            label.position = SCNVector3(x, CGFloat(row == 0 ? y + 0.010 : y - 0.010), 0.166)
            machineRoot.addChildNode(label)
        }

        plugboardCableGroup.name = "enigma.cables"
        machineRoot.addChildNode(plugboardCableGroup)
    }

    private func rebuildPlugboardCables(_ pairs: [PlugboardPair]) {
        plugboardCableGroup.childNodes.forEach { $0.removeFromParentNode() }
        let materials = [library.rubberBlack, library.rubberRed, library.rubberCream]
        for (index, pair) in pairs.enumerated() {
            guard let start = plugboardSocketPositions[pair.first],
                  let end = plugboardSocketPositions[pair.second] else { continue }
            let startWorld = machineRoot.convertPosition(start, to: nil)
            let endWorld = machineRoot.convertPosition(end, to: nil)
            let s = machineRoot.convertPosition(startWorld, from: nil)
            let e = machineRoot.convertPosition(endWorld, from: nil)
            let lift = CGFloat(0.020 + Double(index % 3) * 0.006)
            let controls = [
                SCNVector3(s.x, s.y, s.z),
                SCNVector3(s.x + 0.004, s.y - 0.010, s.z + lift),
                SCNVector3((s.x + e.x) / 2, min(s.y, e.y) - 0.018 - CGFloat(index % 2) * 0.006, max(s.z, e.z) + lift + 0.012),
                SCNVector3(e.x - 0.004, e.y - 0.010, e.z + lift),
                SCNVector3(e.x, e.y, e.z)
            ]
            let cable = Geo.cable(points: controls, radius: 0.0028, material: materials[index % materials.count], radialSegments: 8, samplesPerSegment: 12)
            cable.name = "enigma.cable.\(pair.id)"
            plugboardCableGroup.addChildNode(cable)
            for (letter, point) in [(pair.first, s), (pair.second, e)] {
                let plug = Geo.cylinder(radius: 0.0038, height: 0.017, material: library.agedBrass, axis: .z, radialSegments: 18)
                plug.name = "enigma.plug.\(letter)"
                plug.position = SCNVector3(point.x, point.y, point.z + 0.007)
                plugboardCableGroup.addChildNode(plug)
                let collar = Geo.torus(ringRadius: 0.0048, pipeRadius: 0.0011, material: library.darkSteel, radialSegments: 18, pipeSegments: 6)
                collar.name = "enigma.plug.\(letter)"
                collar.eulerAngles.x = .pi / 2
                collar.position = SCNVector3(point.x, point.y, point.z + 0.014)
                plugboardCableGroup.addChildNode(collar)
            }
        }
    }

    private func buildCaseFittings() {
        // Hinges on the rear lid edge.
        for x in [-0.155, 0.155] {
            let hinge = Geo.box(0.038, 0.008, 0.020, chamfer: 0.002, material: library.agedBrass)
            hinge.position = SCNVector3(CGFloat(x), 0.111, -0.158)
            machineRoot.addChildNode(hinge)
        }
        // Latches on the front.
        for x in [-0.15, 0.15] {
            let latch = Geo.box(0.022, 0.012, 0.014, chamfer: 0.002, material: library.agedBrass)
            latch.position = SCNVector3(CGFloat(x), 0.101, 0.158)
            machineRoot.addChildNode(latch)
        }
        let serial = Geo.textNode(
            text: "M3 · 1944 · 2317",
            width: 0.11,
            height: 0.012,
            font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            color: NSColor(calibratedRed: 0.72, green: 0.65, blue: 0.50, alpha: 0.55)
        )
        serial.position = SCNVector3(0, 0.015, 0.161)
        machineRoot.addChildNode(serial)
    }

    // MARK: - Lights and camera

    private func buildLighting() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 28
        ambient.color = NSColor(calibratedRed: 0.52, green: 0.58, blue: 0.68, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // A wide, soft-edged spot stands in for a studio softbox. SCNRenderer
        // renders a dark shape over the scene when an area light is in use, so
        // keep the key light as a spot and soften it with the shadow radius.
        let key = SCNLight()
        key.type = .spot
        key.spotInnerAngle = 58
        key.spotOuterAngle = 105
        key.intensity = 16
        key.temperature = 5_200
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowSampleCount = 16
        key.shadowRadius = 12
        key.shadowColor = NSColor.black.withAlphaComponent(0.64)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(0.35, 1.66, 0.70)
        keyNode.look(at: SCNVector3(0, 0.86, 0))
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 18
        fill.temperature = 6_500
        fill.castsShadow = false
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(-0.85, 1.45, 1.10)
        fillNode.look(at: SCNVector3(0, 0.92, 0))
        scene.rootNode.addChildNode(fillNode)

        let rim = SCNLight()
        rim.type = .spot
        rim.intensity = 16
        rim.temperature = 5_200
        rim.spotInnerAngle = 24
        rim.spotOuterAngle = 58
        rim.castsShadow = false
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(-0.25, 1.35, -0.65)
        rimNode.look(at: SCNVector3(0, 0.95, 0))
        scene.rootNode.addChildNode(rimNode)

        let practical = SCNLight()
        practical.type = .omni
        practical.intensity = 1.4
        practical.temperature = 2_700
        practical.castsShadow = false
        practical.attenuationStartDistance = 0.15
        practical.attenuationEndDistance = 1.6
        let practicalNode = SCNNode()
        practicalNode.light = practical
        practicalNode.position = SCNVector3(-0.58, 1.06, -0.17)
        scene.rootNode.addChildNode(practicalNode)

        // Filled in only when the camera orbits behind the desk, so the far wall
        // and the reverse of the machine are readable without flattening the
        // carefully lit front view.
        let rearFill = SCNLight()
        rearFill.type = .omni
        rearFill.intensity = 60
        rearFill.temperature = 3_000
        rearFill.castsShadow = false
        rearFill.attenuationStartDistance = 0.2
        rearFill.attenuationEndDistance = 6.0
        backFillNode.light = rearFill
        backFillNode.position = SCNVector3(1.60, 2.50, 0.95)
        backFillNode.isHidden = true
        scene.rootNode.addChildNode(backFillNode)

        let rearFill2 = SCNLight()
        rearFill2.type = .omni
        rearFill2.intensity = 60
        rearFill2.temperature = 3_000
        rearFill2.castsShadow = false
        rearFill2.attenuationStartDistance = 0.2
        rearFill2.attenuationEndDistance = 6.0
        backFillNode2.light = rearFill2
        backFillNode2.position = SCNVector3(-1.60, 2.50, 0.95)
        backFillNode2.isHidden = true
        scene.rootNode.addChildNode(backFillNode2)

        let rearAmbient = SCNLight()
        rearAmbient.type = .ambient
        rearAmbient.intensity = 28
        rearAmbient.color = NSColor(calibratedRed: 0.62, green: 0.58, blue: 0.48, alpha: 1)
        backAmbientNode.light = rearAmbient
        backAmbientNode.isHidden = true
        scene.rootNode.addChildNode(backAmbientNode)
    }

    private func configureCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.01
        camera.zFar = 20
        camera.wantsHDR = true
        camera.bloomIntensity = 0.10
        camera.bloomThreshold = 1.05
        camera.bloomBlurRadius = 6
        camera.screenSpaceAmbientOcclusionIntensity = 0.52
        camera.screenSpaceAmbientOcclusionRadius = 0.07
        camera.screenSpaceAmbientOcclusionBias = 0.012
        camera.motionBlurIntensity = 0.12
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -1.15
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        let config = defaultCameraConfiguration
        cameraNode.position = position(for: config)
        cameraNode.lookAtSceneTarget(config.target)
    }

    func position(for configuration: SceneCameraConfiguration) -> SCNVector3 {
        let yaw = configuration.yaw
        let pitch = configuration.pitch
        let horizontal = configuration.distance * cos(pitch)
        return SCNVector3(
            configuration.target.x + horizontal * sin(yaw),
            configuration.target.y + configuration.distance * sin(pitch),
            configuration.target.z + horizontal * cos(yaw)
        )
    }

    private func updateHighlight(_ selection: ComponentSelection?) {
        highlightNode.removeAllActions()
        guard let selection else {
            highlightNode.opacity = 0
            return
        }
        let position: SCNVector3
        let size: CGFloat
        switch selection {
        case .enigmaCase:
            position = SCNVector3(0, 0.13, 0.02); size = 0.26
        case .enigmaLid:
            position = SCNVector3(0, 0.38, -0.27); size = 0.20
        case .enigmaKeyboard:
            position = SCNVector3(0, 0.145, 0.105); size = 0.11
        case .enigmaLampboard:
            position = SCNVector3(0, 0.135, -0.035); size = 0.09
        case .enigmaPlugboard:
            position = SCNVector3(0, 0.105, 0.19); size = 0.10
        case .enigmaRotor(let index):
            position = SCNVector3(rotorWindowContainers[safe: index]?.position.x ?? 0, 0.222, -0.118); size = 0.055
        case .enigmaReflector:
            position = SCNVector3(0, 0.19, -0.185); size = 0.065
        default:
            highlightNode.opacity = 0
            return
        }
        highlightNode.position = position
        highlightNode.scale = SCNVector3(size / 0.055, size / 0.055, size / 0.055)
        highlightNode.opacity = 1
        let pulse = SCNAction.sequence([
            SCNAction.scale(to: size / 0.055 * 1.06, duration: 0.65),
            SCNAction.scale(to: size / 0.055, duration: 0.65)
        ])
        highlightNode.runAction(.repeatForever(pulse))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

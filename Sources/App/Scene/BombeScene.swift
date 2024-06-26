import AppKit
import SceneKit
import simd
import TuringEnigmaCore

final class BombeSceneRenderer {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let machineRoot = SCNNode()
    let library = MaterialLibrary.shared

    private var drumPivots: [SCNNode] = []
    private var indicatorPivots: [SCNNode] = []
    private var indicatorLetters: [SCNNode] = []
    private var progressLamps: [SCNNode] = []
    private var progressGlows: [SCNNode] = []
    private var needlePivot = SCNNode()
    private var startButton: SCNNode?
    private var stopButton: SCNNode?
    private var highlightNode = SCNNode()
    private var jackPositions: [SCNVector3] = []
    private var cableGroup = SCNNode()
    private var backWallGroup = SCNNode()
    private var backFillNode = SCNNode()

    private var lampOnMaterial: SCNMaterial!
    private var lampOffMaterial: SCNMaterial!
    private var buttonGreenOn: SCNMaterial!
    private var buttonGreenOff: SCNMaterial!
    private var buttonRedOn: SCNMaterial!
    private var buttonRedOff: SCNMaterial!
    private var lastState: BombeRunState = .idle
    private var lastSelection: ComponentSelection?
    private var lastStopID: UUID?

    init() {
        buildRoom()
        buildCabinet()
        buildLighting()
        configureCamera()
        scene.background.contents = library.background
        scene.lightingEnvironment.contents = library.cubeEnvironment
        scene.lightingEnvironment.intensity = 0.30
        scene.fogColor = NSColor(calibratedRed: 0.045, green: 0.045, blue: 0.038, alpha: 1)
        scene.fogStartDistance = 3.6
        scene.fogEndDistance = 13
        scene.rootNode.addChildNode(machineRoot)
    }

    // MARK: - Public interface

    func apply(state: BombeRunState, progress: Double, selectedStop: BombeStop?, selection: ComponentSelection?) {
        let clamped = max(0, min(1, progress))
        updateIndicators(for: selectedStop, progress: clamped, running: state == .running)
        updateMeter(progress: state == .stopped ? 1 : clamped)
        updateProgressLamps(clamped, state: state)
        updateButtons(state: state)

        if state != lastState {
            lastState = state
            switch state {
            case .running:
                startDrumAnimation()
            case .stopped:
                settleDrums(to: selectedStop)
            case .idle:
                settleDrums(to: nil)
            }
        } else if state == .stopped, selectedStop?.id != lastStopID {
            settleDrums(to: selectedStop)
        }

        lastStopID = selectedStop?.id
        if selection != lastSelection {
            lastSelection = selection
            updateHighlight(selection)
        }
    }

    func cameraConfiguration(for preset: CameraPreset) -> SceneCameraConfiguration {
        switch preset {
        case .overview:
            // Match the Enigma's default: a true isometric, machine-centered
            // framing that Center can restore exactly.
            return SceneCameraConfiguration(
                target: SCNVector3(0, 1.05, 0.02),
                distance: 4.40,
                yaw: SceneCameraConfiguration.isometricYaw,
                pitch: SceneCameraConfiguration.isometricPitch
            )
        case .drums:
            return SceneCameraConfiguration(target: SCNVector3(0, 1.49, 0.20), distance: 1.65, yaw: 0.16, pitch: 0.10)
        case .controls:
            return SceneCameraConfiguration(target: SCNVector3(0, 1.03, 0.22), distance: 1.28, yaw: 0.10, pitch: 0.14)
        case .keyboard, .plugboard, .rotors:
            return SceneCameraConfiguration(target: SCNVector3(0, 1.83, 0.20), distance: 1.10, yaw: 0.15, pitch: 0.18)
        }
    }

    var defaultCameraConfiguration: SceneCameraConfiguration { cameraConfiguration(for: .overview) }

    /// Hide the back wall and its wall-mounted pipes once the camera is behind
    /// them, so a full 360° orbit never looks into the unlit rear of the room.
    func updateBackWallVisibility(forCameraPosition position: SCNVector3) {
        let isBehind = position.z < -2.38
        backWallGroup.isHidden = isBehind
        // Illuminate the far wall and the reverse of the cabinet only while the
        // camera is behind the machine.
        backFillNode.isHidden = !isBehind
    }

    func position(for configuration: SceneCameraConfiguration) -> SCNVector3 {
        let horizontal = configuration.distance * cos(configuration.pitch)
        return SCNVector3(
            configuration.target.x + horizontal * sin(configuration.yaw),
            configuration.target.y + configuration.distance * sin(configuration.pitch),
            configuration.target.z + horizontal * cos(configuration.yaw)
        )
    }

    // MARK: - Room

    private func buildRoom() {
        let floor = Geo.plane(width: 12, height: 12, material: library.concrete, name: "bombe.room.floor")
        floor.eulerAngles.x = -.pi / 2
        floor.position = SCNVector3(0, 0, -1.0)
        floor.castsShadow = false
        scene.rootNode.addChildNode(floor)

        // The back wall assembly is grouped for full-orbit camera handling. When
        // the camera is behind it, the group is hidden so its unlit rear face
        // cannot fill the viewport.
        backWallGroup.name = "bombe.room.backWall"
        scene.rootNode.addChildNode(backWallGroup)

        let backWall = Geo.box(12, 4.6, 0.12, material: library.brick, name: "bombe.room.wall")
        backWall.position = SCNVector3(0, 2.3, -2.7)
        backWallGroup.addChildNode(backWall)

        // The rest of the room shell keeps the rear view authored instead of
        // opening onto empty black space. The camera's limits keep it inside
        // these planes.
        let leftWall = Geo.box(0.10, 4.6, 12, material: library.brick, name: "bombe.room.sideWall")
        leftWall.position = SCNVector3(-5.4, 2.3, -1.0)
        leftWall.castsShadow = false
        scene.rootNode.addChildNode(leftWall)
        let rightWall = Geo.box(0.10, 4.6, 12, material: library.brick, name: "bombe.room.sideWall")
        rightWall.position = SCNVector3(5.4, 2.3, -1.0)
        rightWall.castsShadow = false
        scene.rootNode.addChildNode(rightWall)
        let frontWall = Geo.box(12, 4.6, 0.12, material: library.brick, name: "bombe.room.frontWall")
        frontWall.position = SCNVector3(0, 2.3, 4.8)
        frontWall.castsShadow = false
        scene.rootNode.addChildNode(frontWall)

        // Concrete skirting and a steel cable tray.
        let skirting = Geo.box(12, 0.24, 0.08, material: library.concrete)
        skirting.position = SCNVector3(0, 0.12, -2.63)
        backWallGroup.addChildNode(skirting)
        let tray = Geo.box(9, 0.06, 0.28, chamfer: 0.01, material: library.agedBrass)
        tray.position = SCNVector3(0, 3.55, -2.5)
        backWallGroup.addChildNode(tray)
        for x in stride(from: -3.5, through: 3.5, by: 0.7) {
            let bracket = Geo.box(0.035, 0.25, 0.035, material: library.darkSteel)
            bracket.position = SCNVector3(CGFloat(x), 3.42, -2.54)
            backWallGroup.addChildNode(bracket)
        }

        // Heavy wall pipes.
        for (y, radius) in [(3.05, 0.055), (3.25, 0.038), (2.85, 0.030)] {
            let pipe = Geo.cylinder(radius: CGFloat(radius), height: 8.5, material: library.steel, axis: .x, radialSegments: 20)
            pipe.position = SCNVector3(0, CGFloat(y), -2.48)
            backWallGroup.addChildNode(pipe)
        }
        for x in [-3.1, 2.9] {
            let vertical = Geo.cylinder(radius: 0.045, height: 1.8, material: library.steel, radialSegments: 18)
            vertical.position = SCNVector3(CGFloat(x), 2.2, -2.48)
            backWallGroup.addChildNode(vertical)
            let valve = Geo.torus(ringRadius: 0.13, pipeRadius: 0.018, material: library.agedBrass, radialSegments: 28, pipeSegments: 8)
            valve.position = SCNVector3(CGFloat(x), 2.55, -2.45)
            backWallGroup.addChildNode(valve)
            let wheel = Geo.cylinder(radius: 0.10, height: 0.012, material: library.darkSteel, axis: .z, radialSegments: 28)
            wheel.position = SCNVector3(CGFloat(x), 2.55, -2.42)
            backWallGroup.addChildNode(wheel)
        }

        // Heavy double doors and a hut sign on the front wall. These are only
        // seen once the camera orbits behind the Bombe, but they make that side
        // of the room feel intentional rather than empty.
        let doorPaint = library.paintedMetal(
            NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.155, alpha: 1),
            roughness: 0.62
        )
        for x in [-0.82, 0.82] {
            let leaf = Geo.box(1.52, 3.0, 0.09, chamfer: 0.01, material: doorPaint, name: "bombe.room.door")
            leaf.position = SCNVector3(CGFloat(x), 1.52, 4.72)
            leaf.castsShadow = false
            scene.rootNode.addChildNode(leaf)
            for y in stride(from: 0.45, through: 2.65, by: 0.44) {
                let rib = Geo.box(1.38, 0.035, 0.025, chamfer: 0.004, material: library.darkSteel)
                rib.position = SCNVector3(CGFloat(x), CGFloat(y), 4.66)
                scene.rootNode.addChildNode(rib)
            }
        }
        for x in [-1.62, 1.62] {
            let jamb = Geo.box(0.12, 3.2, 0.16, chamfer: 0.008, material: library.agedBrass)
            jamb.position = SCNVector3(CGFloat(x), 1.60, 4.67)
            scene.rootNode.addChildNode(jamb)
        }
        let lintel = Geo.box(3.36, 0.14, 0.16, chamfer: 0.008, material: library.agedBrass)
        lintel.position = SCNVector3(0, 3.13, 4.67)
        scene.rootNode.addChildNode(lintel)
        for x in [-0.28, 0.28] {
            let handle = Geo.cylinder(radius: 0.022, height: 0.24, material: library.agedBrass, radialSegments: 14)
            handle.position = SCNVector3(CGFloat(x), 1.30, 4.62)
            scene.rootNode.addChildNode(handle)
        }
        let sign = Geo.textNode(
            text: "HUT 11  ·  BOMBE BAY",
            width: 2.9,
            height: 0.46,
            font: NSFont(name: "AvenirNextCondensed-DemiBold", size: 42) ?? NSFont.boldSystemFont(ofSize: 42),
            color: NSColor(calibratedRed: 0.86, green: 0.72, blue: 0.42, alpha: 1)
        )
        sign.position = SCNVector3(0, 3.70, 4.72)
        sign.eulerAngles.y = .pi
        sign.castsShadow = false
        scene.rootNode.addChildNode(sign)

        let frontSkirting = Geo.box(12, 0.22, 0.08, material: library.concrete)
        frontSkirting.position = SCNVector3(0, 0.11, 4.72)
        scene.rootNode.addChildNode(frontSkirting)
        for x in [-5.34, 5.34] {
            let sideSkirting = Geo.box(0.08, 0.22, 12, material: library.concrete)
            sideSkirting.position = SCNVector3(CGFloat(x), 0.11, -1.0)
            scene.rootNode.addChildNode(sideSkirting)
        }

        // Hanging practical lamp.
        let ceiling = Geo.plane(width: 12, height: 12, material: library.concrete)
        ceiling.eulerAngles.x = .pi / 2
        ceiling.position = SCNVector3(0, 4.55, -1.0)
        scene.rootNode.addChildNode(ceiling)
        let lampCable = Geo.cylinder(radius: 0.012, height: 1.1, material: library.rubberBlack)
        lampCable.position = SCNVector3(0.25, 3.95, 0.40)
        scene.rootNode.addChildNode(lampCable)
        let shade = SCNCone(topRadius: 0.08, bottomRadius: 0.38, height: 0.30)
        shade.materials = [library.agedBrass]
        let shadeNode = SCNNode(geometry: shade)
        shadeNode.position = SCNVector3(0.25, 3.32, 0.40)
        shadeNode.castsShadow = false
        scene.rootNode.addChildNode(shadeNode)
        let bulb = Geo.sphere(radius: 0.075, material: library.makePBR(
            diffuse: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.42, alpha: 1),
            roughness: 0.18,
            metalness: 0,
            emission: NSColor(calibratedRed: 1.0, green: 0.52, blue: 0.16, alpha: 1)
        ))
        bulb.position = SCNVector3(0.25, 3.20, 0.40)
        scene.rootNode.addChildNode(bulb)

        // A small side bench with a tool box and papers.
        let benchTop = Geo.box(1.55, 0.06, 0.62, chamfer: 0.012, material: library.walnutDark)
        benchTop.position = SCNVector3(-2.25, 0.76, -0.35)
        benchTop.eulerAngles.y = 0.12
        scene.rootNode.addChildNode(benchTop)
        for x in [-2.95, -1.55] {
            for z in [-0.61, -0.09] {
                let leg = Geo.box(0.055, 0.73, 0.055, material: library.darkSteel)
                leg.position = SCNVector3(CGFloat(x), 0.36, CGFloat(z))
                scene.rootNode.addChildNode(leg)
            }
        }
        let toolbox = Geo.box(0.42, 0.18, 0.24, chamfer: 0.008, material: library.paintedMetal(NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.17, alpha: 1), roughness: 0.5))
        toolbox.position = SCNVector3(-2.45, 0.88, -0.34)
        toolbox.eulerAngles.y = 0.12
        scene.rootNode.addChildNode(toolbox)
        let paper = Geo.plane(width: 0.34, height: 0.24, material: library.paper)
        paper.eulerAngles.x = -.pi / 2
        paper.eulerAngles.z = 0.20
        paper.position = SCNVector3(-1.95, 0.795, -0.33)
        scene.rootNode.addChildNode(paper)
    }

    // MARK: - Cabinet

    private func buildCabinet() {
        machineRoot.name = "bombe.root"

        let plinth = Geo.box(2.18, 0.10, 0.68, chamfer: 0.015, material: library.darkSteel, name: "bombe.cabinet")
        plinth.position = SCNVector3(0, 0.10, 0)
        machineRoot.addChildNode(plinth)

        // Lower body, side skins, back and top.
        let lowerBody = Geo.box(2.08, 0.62, 0.58, chamfer: 0.012, material: library.crinkle, name: "bombe.cabinet")
        lowerBody.position = SCNVector3(0, 0.46, 0)
        machineRoot.addChildNode(lowerBody)
        for x in [-1.035, 1.035] {
            let side = Geo.box(0.035, 1.72, 0.62, chamfer: 0.008, material: library.crinkle, name: "bombe.cabinet")
            side.position = SCNVector3(CGFloat(x), 1.01, 0)
            machineRoot.addChildNode(side)
            // Side louvres.
            for index in 0..<6 {
                let louvre = Geo.box(0.012, 0.018, 0.34, chamfer: 0.003, material: library.darkSteel)
                louvre.position = SCNVector3(CGFloat(x) > 0 ? CGFloat(x) + 0.025 : CGFloat(x) - 0.025, 0.63 + CGFloat(index) * 0.045, -0.03)
                machineRoot.addChildNode(louvre)
            }
        }
        let back = Geo.box(2.04, 1.70, 0.035, chamfer: 0.008, material: library.crinkle, name: "bombe.cabinet")
        back.position = SCNVector3(0, 1.01, -0.30)
        machineRoot.addChildNode(back)
        let top = Geo.box(2.16, 0.08, 0.66, chamfer: 0.015, material: library.crinkle, name: "bombe.cabinet")
        top.position = SCNVector3(0, 1.90, 0)
        machineRoot.addChildNode(top)

        // Front frame.
        for x in [-1.035, 1.035] {
            let post = Geo.box(0.06, 1.72, 0.06, chamfer: 0.008, material: library.agedBrass, name: "bombe.cabinet")
            post.position = SCNVector3(CGFloat(x), 1.01, 0.285)
            machineRoot.addChildNode(post)
        }
        for y in [0.78, 1.29, 1.72] {
            let rail = Geo.box(2.07, 0.045, 0.055, chamfer: 0.006, material: library.agedBrass, name: "bombe.cabinet")
            rail.position = SCNVector3(0, CGFloat(y), 0.285)
            machineRoot.addChildNode(rail)
        }

        // Rivets along the front frame.
        for x in stride(from: -1.02, through: 1.02, by: 0.085) {
            for y in [1.735, 1.305, 0.765] {
                let rivet = Geo.rivet(radius: 0.006)
                rivet.position = SCNVector3(CGFloat(x), CGFloat(y), 0.318)
                machineRoot.addChildNode(rivet)
            }
        }

        buildDrumBanks()
        buildIndicators()
        buildLowerDoors()
        buildControls()
        buildSideHardware()
        buildCables()
        buildHighlight()
    }

    private func buildHighlight() {
        highlightNode.name = "selection.highlight"
        highlightNode.geometry = SCNPlane(width: 0.06, height: 0.06)
        highlightNode.geometry?.materials = [library.selectionMaterial()]
        highlightNode.constraints = [SCNBillboardConstraint()]
        highlightNode.opacity = 0
        highlightNode.renderingOrder = 30
        machineRoot.addChildNode(highlightNode)
    }

    private func buildDrumBanks() {
        let bankCenters: [CGFloat] = [-0.70, 0, 0.70]
        let bankColors: [NSColor] = [
            NSColor(calibratedRed: 0.46, green: 0.11, blue: 0.08, alpha: 1),
            NSColor(calibratedRed: 0.12, green: 0.31, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.09, green: 0.20, blue: 0.35, alpha: 1)
        ]
        let rowYs: [CGFloat] = [1.390, 1.495, 1.600]
        let columnPitch: CGFloat = 0.050
        let drumRadius: CGFloat = 0.023
        let drumLength: CGFloat = 0.055

        let bodyMaterial = library.coloredMetal(NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.16, alpha: 1), roughness: 0.44, metalness: 0.72)
        let bodyGeometry = SCNCylinder(radius: drumRadius, height: drumLength)
        bodyGeometry.radialSegmentCount = 32
        bodyGeometry.materials = [bodyMaterial]

        let bezelGeometry = SCNTorus(ringRadius: drumRadius + 0.0035, pipeRadius: 0.0028)
        bezelGeometry.ringSegmentCount = 32
        bezelGeometry.pipeSegmentCount = 8
        bezelGeometry.materials = [library.agedBrass]

        var faceGeometries: [SCNGeometry] = []
        for (index, color) in bankColors.enumerated() {
            let image = TextureFactory.drumFace(seed: UInt64(0xD00D + index * 37), color: color, label: "BANK \(index + 1)")
            let faceMaterial = library.makePBR(diffuse: image, roughness: 0.34, metalness: 0.20, clearCoat: 0.36)
            faceMaterial.diffuse.wrapS = .clamp
            faceMaterial.diffuse.wrapT = .clamp
            let geometry = SCNCylinder(radius: drumRadius - 0.0018, height: 0.0025)
            geometry.radialSegmentCount = 32
            geometry.materials = [bodyMaterial, faceMaterial, bodyMaterial]
            faceGeometries.append(geometry)
        }

        let hubGeometry = SCNSphere(radius: 0.0065)
        hubGeometry.segmentCount = 16
        hubGeometry.materials = [library.darkSteel]

        for (bankIndex, centerX) in bankCenters.enumerated() {
            let bankPanel = Geo.box(0.655, 0.38, 0.045, chamfer: 0.006, material: library.paintedMetal(NSColor(calibratedRed: 0.08, green: 0.105, blue: 0.09, alpha: 1), roughness: 0.62), name: "bombe.drums")
            bankPanel.position = SCNVector3(centerX, 1.495, 0.285)
            machineRoot.addChildNode(bankPanel)
            let border = Geo.box(0.68, 0.405, 0.016, chamfer: 0.005, material: library.agedBrass)
            border.position = SCNVector3(centerX, 1.495, 0.268)
            machineRoot.addChildNode(border)

            let label = Geo.textNode(
                text: "BANK \(bankIndex + 1)",
                width: 0.17,
                height: 0.022,
                font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                color: NSColor(calibratedRed: 0.82, green: 0.72, blue: 0.53, alpha: 0.86)
            )
            label.position = SCNVector3(centerX, 1.695, 0.312)
            machineRoot.addChildNode(label)

            for row in 0..<3 {
                for column in 0..<12 {
                    let x = centerX - 0.275 + CGFloat(column) * columnPitch
                    let y = rowYs[row]
                    let pivot = SCNNode()
                    pivot.name = "bombe.drum.\(bankIndex).\(row).\(column)"
                    pivot.position = SCNVector3(x, y, 0.315)
                    machineRoot.addChildNode(pivot)

                    let body = SCNNode(geometry: bodyGeometry)
                    body.eulerAngles.x = .pi / 2
                    body.name = "bombe.drum.\(bankIndex).\(row).\(column)"
                    pivot.addChildNode(body)

                    let face = SCNNode(geometry: faceGeometries[bankIndex])
                    face.eulerAngles.x = .pi / 2
                    face.position.z = drumLength / 2 - 0.0008
                    pivot.addChildNode(face)

                    let bezel = SCNNode(geometry: bezelGeometry)
                    bezel.eulerAngles.x = .pi / 2
                    bezel.position.z = drumLength / 2 + 0.002
                    pivot.addChildNode(bezel)

                    let hub = SCNNode(geometry: hubGeometry)
                    hub.position.z = drumLength / 2 + 0.004
                    pivot.addChildNode(hub)

                    let notch = Geo.box(0.003, 0.014, 0.003, material: library.rubberCream)
                    notch.position = SCNVector3(0, 0.0165, drumLength / 2 + 0.003)
                    pivot.addChildNode(notch)

                    drumPivots.append(pivot)
                }
            }

            // Row labels and index numbers along the bank.
            for row in 0..<3 {
                let rowLabel = Geo.textNode(
                    text: String(format: "%02d", row + 1),
                    width: 0.018,
                    height: 0.016,
                    font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                    color: NSColor(calibratedRed: 0.70, green: 0.62, blue: 0.45, alpha: 0.65)
                )
                rowLabel.position = SCNVector3(centerX - 0.305, rowYs[row], 0.311)
                machineRoot.addChildNode(rowLabel)
            }
            for column in [0, 5, 11] {
                let columnLabel = Geo.textNode(
                    text: String(format: "%02d", column + 1),
                    width: 0.018,
                    height: 0.012,
                    font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                    color: NSColor(calibratedRed: 0.70, green: 0.62, blue: 0.45, alpha: 0.60)
                )
                columnLabel.position = SCNVector3(centerX - 0.275 + CGFloat(column) * columnPitch, 1.345, 0.311)
                machineRoot.addChildNode(columnLabel)
            }
        }
    }

    private func buildIndicators() {
        let centers: [CGFloat] = [-0.18, 0, 0.18]
        let bodyMaterial = library.coloredMetal(NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.095, alpha: 1), roughness: 0.36, metalness: 0.7)
        for (index, centerX) in centers.enumerated() {
            let panel = Geo.box(0.56, 0.18, 0.035, chamfer: 0.006, material: library.paintedMetal(NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.08, alpha: 1), roughness: 0.6), name: "bombe.indicators")
            panel.position = SCNVector3(0, 1.815, 0.29)
            machineRoot.addChildNode(panel)

            let pivot = SCNNode()
            pivot.position = SCNVector3(centerX, 1.815, 0.325)
            pivot.name = "bombe.indicator.\(index)"
            machineRoot.addChildNode(pivot)

            let body = Geo.cylinder(radius: 0.047, height: 0.08, material: bodyMaterial, axis: .z, radialSegments: 40)
            pivot.addChildNode(body)

            let face = Geo.cylinder(radius: 0.041, height: 0.002, material: library.matteBlack, axis: .z, radialSegments: 40)
            face.position.z = 0.041
            pivot.addChildNode(face)

            let bezel = Geo.torus(ringRadius: 0.045, pipeRadius: 0.003, material: library.agedBrass, radialSegments: 40, pipeSegments: 8)
            bezel.eulerAngles.x = .pi / 2
            bezel.position.z = 0.043
            pivot.addChildNode(bezel)

            let letter = Geo.letterNode("A", size: 0.046, color: NSColor(calibratedRed: 0.94, green: 0.87, blue: 0.71, alpha: 1))
            letter.position.z = 0.045
            pivot.addChildNode(letter)
            indicatorLetters.append(letter)

            let glass = Geo.plane(width: 0.075, height: 0.075, material: library.glass)
            glass.position.z = 0.052
            pivot.addChildNode(glass)

            let label = Geo.textNode(
                text: "INDICATOR \(index + 1)",
                width: 0.15,
                height: 0.018,
                font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                color: NSColor(calibratedRed: 0.75, green: 0.66, blue: 0.50, alpha: 0.68)
            )
            label.position = SCNVector3(centerX, 1.715, 0.311)
            machineRoot.addChildNode(label)

            indicatorPivots.append(pivot)
        }

        let heading = Geo.textNode(
            text: "INDICATORS",
            width: 0.20,
            height: 0.018,
            font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
            color: NSColor(calibratedRed: 0.78, green: 0.69, blue: 0.53, alpha: 0.7)
        )
        heading.position = SCNVector3(0, 1.735, 0.311)
        machineRoot.addChildNode(heading)
    }

    private func buildLowerDoors() {
        let panelMaterial = library.paintedMetal(NSColor(calibratedRed: 0.10, green: 0.135, blue: 0.11, alpha: 1), roughness: 0.65)
        for x in [-0.51, 0.51] {
            let door = Geo.box(0.985, 0.58, 0.035, chamfer: 0.008, material: panelMaterial, name: "bombe.cabinet")
            door.position = SCNVector3(CGFloat(x), 0.45, 0.30)
            machineRoot.addChildNode(door)
            for index in 0..<5 {
                let louvre = Geo.box(0.52, 0.014, 0.012, chamfer: 0.002, material: library.darkSteel)
                louvre.position = SCNVector3(CGFloat(x), 0.30 + CGFloat(index) * 0.045, 0.321)
                machineRoot.addChildNode(louvre)
            }
            let handle = Geo.box(0.14, 0.018, 0.025, chamfer: 0.006, material: library.agedBrass)
            handle.position = SCNVector3(CGFloat(x), 0.65, 0.326)
            machineRoot.addChildNode(handle)
            let hinge = Geo.cylinder(radius: 0.008, height: 0.08, material: library.agedBrass)
            hinge.position = SCNVector3(CGFloat(x) + (x < 0 ? -0.45 : 0.45), 0.45, 0.322)
            machineRoot.addChildNode(hinge)
        }
        let label = Geo.textNode(
            text: "AUTOMATIC HIGH-SPEED ANALYSER",
            width: 0.48,
            height: 0.020,
            font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            color: NSColor(calibratedRed: 0.72, green: 0.65, blue: 0.50, alpha: 0.6)
        )
        label.position = SCNVector3(0, 0.735, 0.326)
        machineRoot.addChildNode(label)
    }

    private func buildControls() {
        let panel = Geo.box(2.0, 0.44, 0.035, chamfer: 0.008, material: library.matteBlack, name: "bombe.controls")
        panel.position = SCNVector3(0, 1.03, 0.30)
        machineRoot.addChildNode(panel)
        let topTrim = Geo.box(2.02, 0.018, 0.055, chamfer: 0.003, material: library.agedBrass)
        topTrim.position = SCNVector3(0, 1.242, 0.312)
        machineRoot.addChildNode(topTrim)

        // Name plate.
        let plate = Geo.nameplateNode(title: "BOMBE", subtitle: "BRITISH TABULATING MACHINE", width: 0.54)
        plate.position = SCNVector3(0, 1.205, 0.322)
        machineRoot.addChildNode(plate)

        // Galvanometer.
        let meterBase = Geo.cylinder(radius: 0.115, height: 0.025, material: library.agedBrass, axis: .z, radialSegments: 48)
        meterBase.position = SCNVector3(-0.77, 1.035, 0.322)
        machineRoot.addChildNode(meterBase)
        let meterFace = Geo.cylinder(radius: 0.102, height: 0.004, material: library.meterMaterial(), axis: .z, radialSegments: 48)
        meterFace.position = SCNVector3(-0.77, 1.035, 0.337)
        machineRoot.addChildNode(meterFace)
        let meterGlass = Geo.plane(width: 0.18, height: 0.18, material: library.glass)
        meterGlass.position = SCNVector3(-0.77, 1.035, 0.342)
        machineRoot.addChildNode(meterGlass)
        needlePivot.position = SCNVector3(-0.77, 1.035, 0.344)
        let needle = Geo.box(0.005, 0.085, 0.002, material: library.paintedMetal(NSColor(calibratedRed: 0.52, green: 0.07, blue: 0.045, alpha: 1), roughness: 0.4))
        needle.position.y = 0.042
        needlePivot.addChildNode(needle)
        machineRoot.addChildNode(needlePivot)
        let meterLabel = Geo.textNode(
            text: "GALVANOMETER",
            width: 0.16,
            height: 0.014,
            font: NSFont.monospacedSystemFont(ofSize: 8, weight: .medium),
            color: NSColor(calibratedRed: 0.72, green: 0.64, blue: 0.49, alpha: 0.65)
        )
        meterLabel.position = SCNVector3(-0.77, 0.905, 0.323)
        machineRoot.addChildNode(meterLabel)

        buildButton(name: "bombe.start", title: "START", color: NSColor(calibratedRed: 0.15, green: 0.34, blue: 0.18, alpha: 1), x: -0.38, y: 1.035, isStart: true)
        buildButton(name: "bombe.stop", title: "STOP", color: NSColor(calibratedRed: 0.42, green: 0.09, blue: 0.06, alpha: 1), x: -0.14, y: 1.035, isStart: false)

        // Toggle switches.
        for index in 0..<6 {
            let x = -0.60 + CGFloat(index) * 0.038
            let base = Geo.box(0.018, 0.034, 0.014, chamfer: 0.002, material: library.agedBrass)
            base.position = SCNVector3(x, 1.075, 0.327)
            machineRoot.addChildNode(base)
            let lever = Geo.cylinder(radius: 0.004, height: 0.035, material: library.darkSteel)
            lever.position = SCNVector3(x, 1.095, 0.330)
            lever.eulerAngles.x = index % 2 == 0 ? 0.45 : -0.45
            machineRoot.addChildNode(lever)
        }

        // Progress lamps.
        lampOnMaterial = library.makePBR(
            diffuse: NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.10, alpha: 1),
            roughness: 0.08,
            metalness: 0,
            emission: NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.06, alpha: 1)
        )
        lampOffMaterial = library.makePBR(
            diffuse: NSColor(calibratedRed: 0.12, green: 0.075, blue: 0.04, alpha: 1),
            roughness: 0.15,
            metalness: 0.1,
            emission: NSColor(calibratedWhite: 0.01, alpha: 1)
        )
        for index in 0..<8 {
            let x = 0.10 + CGFloat(index) * 0.040
            let bezel = Geo.torus(ringRadius: 0.009, pipeRadius: 0.0015, material: library.agedBrass, radialSegments: 22, pipeSegments: 8)
            bezel.position = SCNVector3(x, 1.145, 0.330)
            machineRoot.addChildNode(bezel)
            let lamp = Geo.cylinder(radius: 0.0065, height: 0.006, material: lampOffMaterial, axis: .z, radialSegments: 20, name: "bombe.controls")
            lamp.position = SCNVector3(x, 1.145, 0.330)
            machineRoot.addChildNode(lamp)
            let glow = Geo.plane(width: 0.045, height: 0.045, material: library.glow(color: NSColor(calibratedRed: 1.0, green: 0.40, blue: 0.08, alpha: 1), key: "bombe-lamp-glow"))
            glow.position = SCNVector3(x, 1.145, 0.340)
            glow.opacity = 0
            glow.renderingOrder = 20
            machineRoot.addChildNode(glow)
            progressLamps.append(lamp)
            progressGlows.append(glow)
        }
        let progressLabel = Geo.textNode(
            text: "RUN",
            width: 0.07,
            height: 0.014,
            font: NSFont.monospacedSystemFont(ofSize: 8, weight: .medium),
            color: NSColor(calibratedRed: 0.72, green: 0.64, blue: 0.49, alpha: 0.65)
        )
        progressLabel.position = SCNVector3(0.02, 1.145, 0.331)
        machineRoot.addChildNode(progressLabel)

        // Jack field.
        let jackPanel = Geo.box(0.58, 0.30, 0.025, chamfer: 0.006, material: library.darkSteel)
        jackPanel.position = SCNVector3(0.68, 1.02, 0.327)
        machineRoot.addChildNode(jackPanel)
        for row in 0..<2 {
            for column in 0..<8 {
                let x = 0.44 + CGFloat(column) * 0.065
                let y = 1.10 - CGFloat(row) * 0.090
                let bezel = Geo.torus(ringRadius: 0.010, pipeRadius: 0.002, material: library.agedBrass, radialSegments: 20, pipeSegments: 8)
                bezel.position = SCNVector3(x, y, 0.342)
                machineRoot.addChildNode(bezel)
                let hole = Geo.cylinder(radius: 0.0065, height: 0.010, material: library.rubberBlack, axis: .z, radialSegments: 16)
                hole.position = SCNVector3(x, y, 0.343)
                machineRoot.addChildNode(hole)
                jackPositions.append(SCNVector3(x, y, 0.352))
            }
        }
        let jackLabel = Geo.textNode(
            text: "PATCH",
            width: 0.07,
            height: 0.014,
            font: NSFont.monospacedSystemFont(ofSize: 8, weight: .medium),
            color: NSColor(calibratedRed: 0.72, green: 0.64, blue: 0.49, alpha: 0.65)
        )
        jackLabel.position = SCNVector3(0.48, 0.86, 0.331)
        machineRoot.addChildNode(jackLabel)

        // Fuse panel.
        for index in 0..<4 {
            let x = 0.66 + CGFloat(index) * 0.07
            let fuse = Geo.cylinder(radius: 0.008, height: 0.050, material: library.makePBR(diffuse: NSColor(calibratedRed: 0.55, green: 0.48, blue: 0.32, alpha: 0.72), roughness: 0.2, metalness: 0), axis: .z, radialSegments: 16)
            fuse.position = SCNVector3(x, 0.86, 0.335)
            fuse.eulerAngles.z = .pi / 2
            machineRoot.addChildNode(fuse)
        }

        let stopLabel = Geo.textNode(
            text: "STOPS",
            width: 0.07,
            height: 0.014,
            font: NSFont.monospacedSystemFont(ofSize: 8, weight: .medium),
            color: NSColor(calibratedRed: 0.72, green: 0.64, blue: 0.49, alpha: 0.65)
        )
        stopLabel.position = SCNVector3(0.28, 1.18, 0.331)
        machineRoot.addChildNode(stopLabel)
    }

    private func buildButton(name: String, title: String, color: NSColor, x: CGFloat, y: CGFloat, isStart: Bool) {
        let group = SCNNode()
        group.name = name
        group.position = SCNVector3(x, y, 0.335)
        machineRoot.addChildNode(group)
        let ring = Geo.cylinder(radius: 0.047, height: 0.020, material: library.agedBrass, axis: .z, radialSegments: 32)
        group.addChildNode(ring)
        let buttonMaterial = library.paintedMetal(color, roughness: 0.24)
        let cap = Geo.cylinder(radius: 0.033, height: 0.018, material: buttonMaterial, axis: .z, radialSegments: 32, name: name)
        cap.position.z = 0.012
        group.addChildNode(cap)
        let label = Geo.textNode(
            text: title,
            width: 0.058,
            height: 0.014,
            font: NSFont.monospacedSystemFont(ofSize: 8, weight: .bold),
            color: NSColor(calibratedWhite: 0.92, alpha: 0.9)
        )
        label.position = SCNVector3(0, 0, 0.028)
        group.addChildNode(label)
        if isStart {
            startButton = cap
            buttonGreenOn = library.makePBR(diffuse: NSColor(calibratedRed: 0.18, green: 0.56, blue: 0.25, alpha: 1), roughness: 0.12, metalness: 0, emission: NSColor(calibratedRed: 0.05, green: 0.25, blue: 0.08, alpha: 1))
            buttonGreenOff = buttonMaterial
        } else {
            stopButton = cap
            buttonRedOn = library.makePBR(diffuse: NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.08, alpha: 1), roughness: 0.12, metalness: 0, emission: NSColor(calibratedRed: 0.5, green: 0.03, blue: 0.01, alpha: 1))
            buttonRedOff = buttonMaterial
        }
    }

    private func buildSideHardware() {
        // Handles and vents.
        for side in [-1, 1] {
            let handle = Geo.torus(ringRadius: 0.10, pipeRadius: 0.012, material: library.agedBrass, radialSegments: 32, pipeSegments: 10)
            handle.eulerAngles.z = .pi / 2
            handle.position = SCNVector3(CGFloat(side) * 1.075, 1.58, 0.02)
            machineRoot.addChildNode(handle)
            let plate = Geo.box(0.06, 0.24, 0.16, chamfer: 0.01, material: library.darkSteel)
            plate.position = SCNVector3(CGFloat(side) * 1.06, 1.58, 0.02)
            machineRoot.addChildNode(plate)
        }
        // Top vent grille.
        for row in 0..<4 {
            for column in 0..<12 {
                let slot = Geo.box(0.010, 0.006, 0.25, material: library.darkSteel)
                slot.position = SCNVector3(-0.33 + CGFloat(column) * 0.06, 1.942, -0.10 + CGFloat(row) * 0.045)
                machineRoot.addChildNode(slot)
            }
        }
        // Casters.
        let wheelGeometry = SCNCylinder(radius: 0.055, height: 0.035)
        wheelGeometry.radialSegmentCount = 28
        wheelGeometry.materials = [library.rubberBlack]
        let hubGeometry = SCNCylinder(radius: 0.020, height: 0.040)
        hubGeometry.radialSegmentCount = 20
        hubGeometry.materials = [library.agedBrass]
        for x in [-0.88, 0.88] {
            for z in [-0.22, 0.22] {
                let caster = SCNNode()
                caster.position = SCNVector3(CGFloat(x), 0.055, CGFloat(z))
                let fork = Geo.box(0.055, 0.10, 0.04, chamfer: 0.006, material: library.darkSteel)
                fork.position.y = 0.055
                caster.addChildNode(fork)
                let wheel = SCNNode(geometry: wheelGeometry)
                wheel.eulerAngles.z = .pi / 2
                caster.addChildNode(wheel)
                let hub = SCNNode(geometry: hubGeometry)
                hub.eulerAngles.z = .pi / 2
                caster.addChildNode(hub)
                machineRoot.addChildNode(caster)
            }
        }
        // Serial plate.
        let serial = Geo.textNode(
            text: "BOMBE MK II  ·  SERIAL 108  ·  B.T.M.",
            width: 0.44,
            height: 0.018,
            font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            color: NSColor(calibratedRed: 0.74, green: 0.66, blue: 0.50, alpha: 0.60)
        )
        serial.position = SCNVector3(0, 0.125, 0.306)
        machineRoot.addChildNode(serial)
    }

    private func buildCables() {
        cableGroup.name = "bombe.cables"
        machineRoot.addChildNode(cableGroup)

        // Patch leads between the jack field sockets.
        guard jackPositions.count >= 16 else { return }
        let pairs = [(0, 9), (3, 14), (5, 11), (7, 12)]
        let materials = [library.rubberRed, library.rubberBlack, library.rubberCream, library.rubberRed]
        for (index, pair) in pairs.enumerated() {
            let a = jackPositions[pair.0]
            let b = jackPositions[pair.1]
            let sag = CGFloat(0.10 + Double(index % 3) * 0.02)
            let points = [
                SCNVector3(a.x, a.y, a.z),
                SCNVector3(a.x + 0.01, a.y - 0.035, a.z + 0.035),
                SCNVector3((a.x + b.x) / 2, min(a.y, b.y) - sag, 0.405),
                SCNVector3(b.x - 0.01, b.y - 0.035, b.z + 0.035),
                SCNVector3(b.x, b.y, b.z)
            ]
            let cable = Geo.cable(points: points, radius: 0.0042, material: materials[index], radialSegments: 8, samplesPerSegment: 12)
            cableGroup.addChildNode(cable)
            for point in [a, b] {
                let plug = Geo.cylinder(radius: 0.0052, height: 0.020, material: library.agedBrass, axis: .z, radialSegments: 16)
                plug.position = SCNVector3(point.x, point.y, point.z + 0.008)
                cableGroup.addChildNode(plug)
            }
        }

        // A thick power cable running to the wall tray.
        let points = [
            SCNVector3(0.92, 1.88, -0.25),
            SCNVector3(1.10, 2.15, -0.55),
            SCNVector3(1.15, 3.10, -1.20),
            SCNVector3(0.85, 3.52, -2.40),
            SCNVector3(0.35, 3.55, -2.50)
        ]
        let power = Geo.cable(points: points, radius: 0.018, material: library.rubberBlack, radialSegments: 10, samplesPerSegment: 14)
        scene.rootNode.addChildNode(power)
    }

    // MARK: - Light and camera

    private func buildLighting() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 28
        ambient.color = NSColor(calibratedRed: 0.48, green: 0.55, blue: 0.62, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .spot
        key.intensity = 1_350
        key.temperature = 3_100
        key.spotInnerAngle = 24
        key.spotOuterAngle = 58
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowSampleCount = 16
        key.shadowRadius = 7
        key.shadowColor = NSColor.black.withAlphaComponent(0.72)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(0.25, 3.18, 0.40)
        keyNode.look(at: SCNVector3(0, 1.1, 0.1))
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 120
        fill.temperature = 6_400
        fill.castsShadow = false
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(-1.5, 2.3, 2.7)
        fillNode.look(at: SCNVector3(0, 1.2, 0))
        scene.rootNode.addChildNode(fillNode)

        let rim = SCNLight()
        rim.type = .spot
        rim.intensity = 600
        rim.temperature = 4_400
        rim.spotInnerAngle = 28
        rim.spotOuterAngle = 65
        rim.castsShadow = false
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(-1.7, 2.8, -1.3)
        rimNode.look(at: SCNVector3(0, 1.4, 0.2))
        scene.rootNode.addChildNode(rimNode)

        let practical = SCNLight()
        practical.type = .omni
        practical.intensity = 80
        practical.temperature = 2_900
        practical.castsShadow = false
        practical.attenuationStartDistance = 0.5
        practical.attenuationEndDistance = 5.0
        let practicalNode = SCNNode()
        practicalNode.light = practical
        practicalNode.position = SCNVector3(0.25, 3.16, 0.40)
        scene.rootNode.addChildNode(practicalNode)

        let rearFill = SCNLight()
        rearFill.type = .omni
        rearFill.intensity = 750
        rearFill.temperature = 3_100
        rearFill.castsShadow = false
        rearFill.attenuationStartDistance = 0.6
        rearFill.attenuationEndDistance = 8.0
        backFillNode.light = rearFill
        backFillNode.position = SCNVector3(0, 3.55, 3.90)
        backFillNode.isHidden = true
        scene.rootNode.addChildNode(backFillNode)
    }

    private func configureCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 40
        camera.zNear = 0.03
        camera.zFar = 30
        camera.wantsHDR = true
        camera.bloomIntensity = 0.15
        camera.bloomThreshold = 1.10
        camera.bloomBlurRadius = 8
        camera.screenSpaceAmbientOcclusionIntensity = 0.58
        camera.screenSpaceAmbientOcclusionRadius = 0.12
        camera.screenSpaceAmbientOcclusionBias = 0.02
        camera.motionBlurIntensity = 0.12
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -1.05
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        let config = defaultCameraConfiguration
        cameraNode.position = position(for: config)
        cameraNode.lookAtSceneTarget(config.target)
    }

    // MARK: - State and animation

    private func startDrumAnimation() {
        for (index, pivot) in drumPivots.enumerated() {
            pivot.removeAllActions()
            let duration = 0.55 + Double(index % 11) * 0.055
            let direction: CGFloat = index % 2 == 0 ? -1 : 1
            let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 0, z: direction * .pi * 2, duration: duration))
            pivot.runAction(spin, forKey: "spin")
        }
        for (index, pivot) in indicatorPivots.enumerated() {
            pivot.removeAllActions()
            let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 0, z: (index % 2 == 0 ? -1 : 1) * .pi * 2, duration: 1.1 + Double(index) * 0.2))
            pivot.runAction(spin, forKey: "spin")
        }
    }

    private func settleDrums(to stop: BombeStop?) {
        for (index, pivot) in drumPivots.enumerated() {
            pivot.removeAction(forKey: "spin")
            let target: CGFloat
            if let stop {
                let seed = stop.initialPositions.reduce(0, +) + stop.ringSettings.reduce(0, +)
                target = CGFloat((index * 31 + seed * 7) % 26) / 26 * .pi * 2
            } else {
                target = 0
            }
            let settle = SCNAction.rotateTo(x: 0, y: 0, z: target, duration: 0.8 + Double(index % 5) * 0.06, usesShortestUnitArc: true)
            settle.timingMode = .easeOut
            pivot.runAction(settle, forKey: "settle")
        }
        for pivot in indicatorPivots {
            pivot.removeAction(forKey: "spin")
            let settle = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.5, usesShortestUnitArc: true)
            pivot.runAction(settle, forKey: "settle")
        }
    }

    private func updateIndicators(for stop: BombeStop?, progress: Double, running: Bool) {
        let positions: [Int]
        if let stop, !running {
            positions = stop.initialPositions
        } else if running {
            let base = Int(progress * 26)
            positions = [base, (base + 7) % 26, (base + 15) % 26]
        } else {
            positions = [0, 0, 0]
        }
        for (index, node) in indicatorLetters.enumerated() where index < positions.count {
            let letter = Alphabet.letter(at: positions[index])
            node.geometry?.materials = [library.letter(letter, color: NSColor(calibratedRed: 0.94, green: 0.87, blue: 0.71, alpha: 1))]
        }
    }

    private func updateMeter(progress: Double) {
        let angle = -1.05 + 2.10 * progress
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.12
        needlePivot.eulerAngles.z = CGFloat(angle)
        SCNTransaction.commit()
    }

    private func updateProgressLamps(_ progress: Double, state: BombeRunState) {
        for (index, lamp) in progressLamps.enumerated() {
            let threshold = Double(index + 1) / Double(progressLamps.count)
            let lit = state == .stopped ? true : (state == .running && progress >= threshold)
            lamp.geometry?.materials = [lit ? lampOnMaterial : lampOffMaterial]
            progressGlows[index].opacity = lit ? 1 : 0
        }
    }

    private func updateButtons(state: BombeRunState) {
        startButton?.geometry?.materials = [state == .running ? buttonGreenOn : buttonGreenOff]
        stopButton?.geometry?.materials = [state == .running ? buttonRedOff : buttonRedOn]
        if state == .idle {
            stopButton?.geometry?.materials = [buttonRedOff]
        }
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
        case .bombeCabinet:
            position = SCNVector3(0, 1.05, 0.40); size = 1.45
        case .bombeDrums:
            position = SCNVector3(0, 1.50, 0.40); size = 1.0
        case .bombeIndicators:
            position = SCNVector3(0, 1.82, 0.40); size = 0.32
        case .bombeControls:
            position = SCNVector3(0, 1.02, 0.40); size = 0.55
        case .bombeMenu:
            position = SCNVector3(0.0, 1.25, 0.40); size = 0.35
        default:
            highlightNode.opacity = 0
            return
        }
        highlightNode.position = position
        highlightNode.scale = SCNVector3(size / 0.06, size / 0.06, size / 0.06)
        highlightNode.opacity = 0.78
        let pulse = SCNAction.sequence([
            SCNAction.scale(to: size / 0.06 * 1.04, duration: 0.7),
            SCNAction.scale(to: size / 0.06, duration: 0.7)
        ])
        highlightNode.runAction(.repeatForever(pulse))
    }
}

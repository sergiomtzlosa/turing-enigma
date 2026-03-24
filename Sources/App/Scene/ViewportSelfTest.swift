import AppKit
import Foundation
import SceneKit
import TuringEnigmaCore

/// Headless checks for the 3D interaction surface. They are deliberately kept
/// outside the XCTest target so they can run without Developer Mode and without
/// an attached display.
enum ViewportSelfTest {
    static func runIfRequested() -> Int32? {
        guard CommandLine.arguments.contains("--viewport-check") else { return nil }
        let failures = check()
        if failures.isEmpty {
            print("viewport check passed: scene nodes, intent mapping, camera presets, and click routing")
            return 0
        }
        for failure in failures {
            fputs("viewport check: \(failure)\n", stderr)
        }
        return 1
    }

    private static func check() -> [String] {
        var failures: [String] = []
        let enigma = EnigmaSceneRenderer()
        let bombe = BombeSceneRenderer()
        let scenario = DemoScenario.weather
        var presentation = EnigmaPresentation(settings: scenario.settings)
        presentation.pressedKey = "W"
        presentation.litLamp = "G"
        enigma.apply(settings: scenario.settings, presentation: presentation, selection: .enigmaRotor(1), animated: false)
        bombe.apply(state: .stopped, progress: 1, selectedStop: nil, selection: .bombeControls)

        let enigmaNames = Set(allNodes(in: enigma.scene.rootNode).compactMap(\.name))
        let bombeNames = Set(allNodes(in: bombe.scene.rootNode).compactMap(\.name))

        let requiredEnigmaNames = [
            "enigma.case", "enigma.lid", "enigma.keyboard", "enigma.lampboard",
            "enigma.plugboard", "enigma.reflector", "enigma.rotor.0",
            "enigma.rotor.1", "enigma.rotor.2", "enigma.rotor.3",
            "enigma.key.A", "enigma.key.Z", "enigma.lamp.A", "enigma.lamp.Z",
            "enigma.plug.A", "enigma.plug.Z", "selection.highlight"
        ]
        for name in requiredEnigmaNames where !enigmaNames.contains(name) {
            failures.append("Enigma node missing: \(name)")
        }

        let keyNames = enigmaNames.filter { $0.hasPrefix("enigma.key.") }
        if keyNames.count != 26 {
            failures.append("Enigma keys: expected 26, found \(keyNames.count)")
        }
        let lampNames = enigmaNames.filter { $0.hasPrefix("enigma.lamp.") }
        if lampNames.count != 26 {
            failures.append("Enigma lamps: expected 26, found \(lampNames.count)")
        }
        let plugNames = enigmaNames.filter { $0.hasPrefix("enigma.plug.") }
        if plugNames.count != 26 {
            failures.append("Enigma plug sockets: expected 26, found \(plugNames.count)")
        }

        let requiredBombeNames = [
            "bombe.start", "bombe.stop", "bombe.drums", "bombe.indicators",
            "bombe.controls", "bombe.cabinet", "bombe.drum.0.0.0",
            "bombe.drum.2.2.11", "bombe.indicator.0", "bombe.indicator.2",
            "selection.highlight"
        ]
        for name in requiredBombeNames where !bombeNames.contains(name) {
            failures.append("Bombe node missing: \(name)")
        }
        let drumNames = bombeNames.filter { $0.hasPrefix("bombe.drum.") }
        if drumNames.count != 108 {
            failures.append("Bombe drums: expected 108, found \(drumNames.count)")
        }
        let indicatorNames = bombeNames.filter { $0.hasPrefix("bombe.indicator.") }
        if indicatorNames.count != 3 {
            failures.append("Bombe indicators: expected 3, found \(indicatorNames.count)")
        }

        checkRotorVisibility(enigma, failures: &failures)
        checkIntents(failures: &failures)
        checkCameras(enigma, bombe, failures: &failures)
        checkInteractions(enigma, bombe, failures: &failures)
        return failures
    }

    private static func checkRotorVisibility(_ renderer: EnigmaSceneRenderer, failures: inout [String]) {
        let m3Visible = visibleRotorNames(in: renderer)
        if m3Visible != Set(0..<3) {
            failures.append("M3 rotor visibility: expected 0...2, found \(m3Visible.sorted())")
        }

        var m4 = EnigmaSettings.standard
        m4.changeMachineType(to: .m4)
        var presentation = EnigmaPresentation(settings: m4)
        presentation.rotorPositions = m4.initialPositions
        renderer.apply(settings: m4, presentation: presentation, selection: nil, animated: false)
        let m4Visible = visibleRotorNames(in: renderer)
        if m4Visible != Set(0..<4) {
            failures.append("M4 rotor visibility: expected 0...3, found \(m4Visible.sorted())")
        }
    }

    private static func visibleRotorNames(in renderer: EnigmaSceneRenderer) -> Set<Int> {
        Set(allNodes(in: renderer.machineRoot).compactMap { node -> Int? in
            guard !isEffectivelyHidden(node), let name = node.name, name.hasPrefix("enigma.rotor.") else {
                return nil
            }
            return Int(name.dropFirst("enigma.rotor.".count))
        })
    }

    private static func isEffectivelyHidden(_ node: SCNNode) -> Bool {
        var current: SCNNode? = node
        while let candidate = current {
            if candidate.isHidden { return true }
            current = candidate.parent
        }
        return false
    }

    private static func checkIntents(failures: inout [String]) {
        let expectations: [(AppMode, String, SceneIntent)] = [
            (.enigma, "enigma.key.Q", .pressKey("Q")),
            (.enigma, "enigma.plug.W", .plug("W")),
            (.enigma, "enigma.lamp.E", .select(.enigmaLampboard)),
            (.enigma, "enigma.rotor.2", .select(.enigmaRotor(2))),
            (.enigma, "enigma.keyboard", .select(.enigmaKeyboard)),
            (.enigma, "enigma.lampboard", .select(.enigmaLampboard)),
            (.enigma, "enigma.plugboard", .select(.enigmaPlugboard)),
            (.enigma, "enigma.cables", .select(.enigmaPlugboard)),
            (.enigma, "enigma.cable.WE", .select(.enigmaPlugboard)),
            (.enigma, "enigma.lid", .select(.enigmaLid)),
            (.enigma, "enigma.reflector", .select(.enigmaReflector)),
            (.enigma, "enigma.case", .select(.enigmaCase)),
            (.bombe, "bombe.start", .startBombe),
            (.bombe, "bombe.stop", .stopBombe),
            (.bombe, "bombe.drum.1.2.7", .select(.bombeDrums)),
            (.bombe, "bombe.drums", .select(.bombeDrums)),
            (.bombe, "bombe.indicator.2", .select(.bombeIndicators)),
            (.bombe, "bombe.indicators", .select(.bombeIndicators)),
            (.bombe, "bombe.controls", .select(.bombeControls)),
            (.bombe, "bombe.cabinet", .select(.bombeCabinet)),
            (.bombe, "bombe.menu", .select(.bombeMenu))
        ]

        for (mode, name, expected) in expectations {
            let actual = SceneIntentMapper.intent(for: name, mode: mode)
            if actual != expected {
                failures.append("Intent \(mode.rawValue)/\(name): expected \(expected), got \(String(describing: actual))")
            }
        }

        for (mode, name) in [(AppMode.enigma, "room.deskTop"), (.enigma, "enigma.unknown"), (.bombe, "bombe.room.floor")] {
            if SceneIntentMapper.intent(for: name, mode: mode) != nil {
                failures.append("Intent \(mode.rawValue)/\(name) should be unmapped")
            }
        }
    }

    private static func checkCameras(
        _ enigma: EnigmaSceneRenderer,
        _ bombe: BombeSceneRenderer,
        failures: inout [String]
    ) {
        for preset in CameraPreset.allCases {
            checkCamera(
                mode: .enigma,
                preset: preset,
                configuration: enigma.cameraConfiguration(for: preset),
                position: enigma.position(for: enigma.cameraConfiguration(for: preset)),
                failures: &failures
            )
            checkCamera(
                mode: .bombe,
                preset: preset,
                configuration: bombe.cameraConfiguration(for: preset),
                position: bombe.position(for: bombe.cameraConfiguration(for: preset)),
                failures: &failures
            )
        }
    }

    private static func checkCamera(
        mode: AppMode,
        preset: CameraPreset,
        configuration: SceneCameraConfiguration,
        position: SCNVector3,
        failures: inout [String]
    ) {
        let values = [
            configuration.target.x, configuration.target.y, configuration.target.z,
            configuration.distance, configuration.yaw, configuration.pitch,
            position.x, position.y, position.z
        ]
        guard values.allSatisfy(\.isFinite), configuration.distance > 0 else {
            failures.append("Camera \(mode.rawValue)/\(preset.rawValue) is not finite")
            return
        }
        let dx = position.x - configuration.target.x
        let dy = position.y - configuration.target.y
        let dz = position.z - configuration.target.z
        let distance = sqrt(dx * dx + dy * dy + dz * dz)
        if abs(distance - configuration.distance) > 0.002 {
            failures.append("Camera \(mode.rawValue)/\(preset.rawValue) distance mismatch")
        }
    }

    private static func checkIsometricCenter(
        _ configuration: SceneCameraConfiguration,
        expectedTarget: SCNVector3,
        label: String,
        failures: inout [String]
    ) {
        let epsilon: CGFloat = 0.0001
        if abs(configuration.target.x - expectedTarget.x) > epsilon
            || abs(configuration.target.y - expectedTarget.y) > epsilon
            || abs(configuration.target.z - expectedTarget.z) > epsilon {
            failures.append("\(label) target is not the machine center")
        }
        if abs(configuration.yaw - SceneCameraConfiguration.isometricYaw) > epsilon {
            failures.append("\(label) is not at the 45° isometric yaw")
        }
        if abs(configuration.pitch - SceneCameraConfiguration.isometricPitch) > epsilon {
            failures.append("\(label) is not at the 35.26° isometric pitch")
        }
    }

    private static func checkInteractions(
        _ enigma: EnigmaSceneRenderer,
        _ bombe: BombeSceneRenderer,
        failures: inout [String]
    ) {
        let view = InteractiveSceneView(
            frame: NSRect(x: 0, y: 0, width: 1280, height: 840),
            options: nil
        )
        let coordinator = SceneViewportCoordinator()
        let recorder = IntentRecorder()
        coordinator.attach(to: view)
        view.layoutSubtreeIfNeeded()

        let scenario = DemoScenario.weather
        let presentation = EnigmaPresentation(settings: scenario.settings)
        let cameraRequestID = UUID()
        var centerRequestID = UUID()
        let emptyBombe = BombeConfig()

        coordinator.update(
            view: view,
            mode: .enigma,
            enigma: scenario.settings,
            presentation: presentation,
            selection: nil,
            bombe: emptyBombe,
            bombeState: .idle,
            bombeProgress: 0,
            selectedStop: nil,
            cameraRequest: .overview,
            cameraRequestID: cameraRequestID,
            centerRequestID: centerRequestID,
            onIntent: { recorder.intents.append($0) }
        )
        view.layoutSubtreeIfNeeded()

        if click(nodeName: "enigma.key.Q", in: view, coordinator: coordinator, recorder: recorder) != .pressKey("Q") {
            failures.append("Clicking the 3D Q key did not press Q")
        }
        if click(nodeName: "enigma.plug.W", in: view, coordinator: coordinator, recorder: recorder) != .plug("W") {
            failures.append("Clicking the 3D W socket did not select its plug")
        }
        if click(nodeName: "enigma.rotor.1", in: view, coordinator: coordinator, recorder: recorder) != .select(.enigmaRotor(1)) {
            failures.append("Clicking rotor 2 did not select it")
        }
        if click(at: CGPoint(x: 30, y: 30), in: view, coordinator: coordinator, recorder: recorder) != .select(nil) {
            failures.append("Clicking the room did not clear the selection")
        }

        recorder.intents.removeAll()
        if coordinator.viewport(view, handleKeyDown: keyEvent("a", keyCode: 0)) != true
            || recorder.intents.last != .pressKey("A") {
            failures.append("Hardware-keyboard A did not press the A key")
        }
        recorder.intents.removeAll()
        if coordinator.viewport(view, handleKeyDown: keyEvent("a", keyCode: 0, modifiers: .command)) != false {
            failures.append("Command-A should not be swallowed by the viewport")
        }
        recorder.intents.removeAll()
        if coordinator.viewport(view, handleKeyDown: keyEvent("\u{1b}", keyCode: 53)) != true
            || recorder.intents.last != .select(nil) {
            failures.append("Escape did not clear the Enigma selection")
        }

        if let camera = view.pointOfView {
            let overview = enigma.defaultCameraConfiguration
            let target = overview.target
            let defaultPosition = enigma.position(for: overview)
            if !samePosition(camera.position, defaultPosition) {
                failures.append("Enigma viewport did not start at the overview camera")
            }
            checkIsometricCenter(
                overview,
                expectedTarget: SCNVector3(0, 0.96, 0.01),
                label: "Enigma overview",
                failures: &failures
            )

            if namedNode("room.backWall", in: view)?.isHidden != false {
                failures.append("Enigma back wall should start visible")
            }

            coordinator.viewport(view, didOrbitBy: CGSize(width: 80, height: 25))
            if samePosition(camera.position, defaultPosition) {
                failures.append("Orbiting did not move the Enigma camera")
            }

            // Orbit all the way behind the desk. The model must remain the
            // subject of the view by hiding the near wall, not by refusing to
            // rotate past the front arc.
            let yawAfterNudge = overview.yaw - 80 * 0.0045
            let dragToBack = (yawAfterNudge - .pi) / 0.0045
            coordinator.viewport(view, didOrbitBy: CGSize(width: dragToBack, height: 0))
            if camera.position.z > target.z - 0.5 {
                failures.append("Enigma orbit did not reach the back of the machine")
            }
            if namedNode("room.backWall", in: view)?.isHidden != true {
                failures.append("Enigma back wall should hide when the camera orbits behind it")
            }

            coordinator.viewport(view, didZoomBy: -1_000, precise: true)
            if abs(distance(from: camera.position, to: target) - 2.80) > 0.01 {
                failures.append("Enigma zoom-out did not clamp at 2.80 m")
            }
            coordinator.viewport(view, didZoomBy: 1_000, precise: true)
            if abs(distance(from: camera.position, to: target) - 0.55) > 0.01 {
                failures.append("Enigma zoom-in did not clamp at 0.55 m")
            }
            let zoomedDistance = distance(from: camera.position, to: target)
            let beforePan = camera.position
            coordinator.viewport(view, didPanBy: CGSize(width: 900, height: 500))
            if samePosition(camera.position, beforePan) {
                failures.append("Panning did not move the Enigma camera")
            }
            if abs(distance(from: camera.position, to: target) - zoomedDistance) < 0.01 {
                failures.append("Panning did not move the Enigma camera target")
            }
            coordinator.viewport(view, didPanBy: CGSize(width: -10_000, height: -10_000))
            if !camera.position.x.isFinite || !camera.position.y.isFinite || !camera.position.z.isFinite {
                failures.append("Enigma pan produced a non-finite camera position")
            }

            centerRequestID = UUID()
            coordinator.update(
                view: view,
                mode: .enigma,
                enigma: scenario.settings,
                presentation: presentation,
                selection: nil,
                bombe: emptyBombe,
                bombeState: .idle,
                bombeProgress: 0,
                selectedStop: nil,
                cameraRequest: .overview,
                cameraRequestID: cameraRequestID,
                centerRequestID: centerRequestID,
                onIntent: { recorder.intents.append($0) }
            )
            let centered = enigma.defaultCameraConfiguration
            let centeredPosition = enigma.position(for: centered)
            if !samePosition(camera.position, centeredPosition) {
                failures.append("Center did not restore the Enigma default isometric camera")
            }
            if abs(distance(from: camera.position, to: centered.target) - centered.distance) > 0.01 {
                failures.append("Center did not restore the Enigma default isometric distance")
            }
            if namedNode("room.backWall", in: view)?.isHidden != false {
                failures.append("Center did not restore the Enigma back wall")
            }
            checkIsometricCenter(
                centered,
                expectedTarget: SCNVector3(0, 0.96, 0.01),
                label: "Enigma Center",
                failures: &failures
            )
        } else {
            failures.append("The Enigma viewport has no camera")
        }

        coordinator.update(
            view: view,
            mode: .bombe,
            enigma: scenario.settings,
            presentation: presentation,
            selection: nil,
            bombe: emptyBombe,
            bombeState: .idle,
            bombeProgress: 0,
            selectedStop: nil,
            cameraRequest: .overview,
            cameraRequestID: cameraRequestID,
            centerRequestID: centerRequestID,
            onIntent: { recorder.intents.append($0) }
        )
        view.layoutSubtreeIfNeeded()
        if view.scene?.rootNode.childNode(withName: "bombe.root", recursively: true) == nil {
            failures.append("Switching modes did not install the Bombe scene")
        }
        if click(nodeName: "bombe.drum.1.1.5", in: view, coordinator: coordinator, recorder: recorder) != .select(.bombeDrums) {
            failures.append("Clicking a Bombe drum did not select the drum bank")
        }
        if click(nodeName: "bombe.start", in: view, coordinator: coordinator, recorder: recorder) != .startBombe {
            failures.append("Clicking the Bombe START button did not start the run")
        }
        if click(nodeName: "bombe.stop", in: view, coordinator: coordinator, recorder: recorder) != .stopBombe {
            failures.append("Clicking the Bombe STOP button did not stop the run")
        }

        recorder.intents.removeAll()
        if coordinator.viewport(view, handleKeyDown: keyEvent("\u{1b}", keyCode: 53)) != true
            || recorder.intents.last != .select(nil) {
            failures.append("Escape did not clear the Bombe selection")
        }
        recorder.intents.removeAll()
        if coordinator.viewport(view, handleKeyDown: keyEvent("a", keyCode: 0)) != false || !recorder.intents.isEmpty {
            failures.append("Letter keys should not press Enigma keys in Bombe mode")
        }

        if let camera = view.pointOfView {
            let overview = bombe.defaultCameraConfiguration
            let target = overview.target
            let defaultPosition = bombe.position(for: overview)
            if !samePosition(camera.position, defaultPosition) {
                failures.append("Bombe viewport did not start at the overview camera")
            }
            checkIsometricCenter(
                overview,
                expectedTarget: SCNVector3(0, 1.05, 0.02),
                label: "Bombe overview",
                failures: &failures
            )

            if namedNode("bombe.room.backWall", in: view)?.isHidden != false {
                failures.append("Bombe back wall should start visible")
            }

            coordinator.viewport(view, didOrbitBy: CGSize(width: 80, height: 25))
            if samePosition(camera.position, defaultPosition) {
                failures.append("Orbiting did not move the Bombe camera")
            }

            let yawAfterNudge = overview.yaw - 80 * 0.0045
            let dragToBack = (yawAfterNudge - .pi) / 0.0045
            coordinator.viewport(view, didOrbitBy: CGSize(width: dragToBack, height: 0))
            if camera.position.z > target.z - 1.0 {
                failures.append("Bombe orbit did not reach the back of the cabinet")
            }
            if namedNode("bombe.room.backWall", in: view)?.isHidden != true {
                failures.append("Bombe back wall should hide when the camera orbits behind it")
            }

            coordinator.viewport(view, didZoomBy: -1_000, precise: true)
            if abs(distance(from: camera.position, to: target) - 5.80) > 0.01 {
                failures.append("Bombe zoom-out did not clamp at 5.80 m")
            }
            coordinator.viewport(view, didZoomBy: 1_000, precise: true)
            if abs(distance(from: camera.position, to: target) - 1.05) > 0.01 {
                failures.append("Bombe zoom-in did not clamp at 1.05 m")
            }

            let beforePan = camera.position
            coordinator.viewport(view, didPanBy: CGSize(width: 900, height: 500))
            if samePosition(camera.position, beforePan) {
                failures.append("Panning did not move the Bombe camera")
            }
            coordinator.viewport(view, didPanBy: CGSize(width: -10_000, height: -10_000))
            if !camera.position.x.isFinite || !camera.position.y.isFinite || !camera.position.z.isFinite {
                failures.append("Bombe pan produced a non-finite camera position")
            }

            centerRequestID = UUID()
            coordinator.update(
                view: view,
                mode: .bombe,
                enigma: scenario.settings,
                presentation: presentation,
                selection: nil,
                bombe: emptyBombe,
                bombeState: .idle,
                bombeProgress: 0,
                selectedStop: nil,
                cameraRequest: .overview,
                cameraRequestID: cameraRequestID,
                centerRequestID: centerRequestID,
                onIntent: { recorder.intents.append($0) }
            )
            let centered = bombe.defaultCameraConfiguration
            let centeredPosition = bombe.position(for: centered)
            if !samePosition(camera.position, centeredPosition) {
                failures.append("Center did not restore the Bombe default isometric camera")
            }
            if abs(distance(from: camera.position, to: centered.target) - centered.distance) > 0.01 {
                failures.append("Center did not restore the Bombe default isometric distance")
            }
            if namedNode("bombe.room.backWall", in: view)?.isHidden != false {
                failures.append("Center did not restore the Bombe back wall")
            }
            checkIsometricCenter(
                centered,
                expectedTarget: SCNVector3(0, 1.05, 0.02),
                label: "Bombe Center",
                failures: &failures
            )
        } else {
            failures.append("The Bombe viewport has no camera")
        }
    }

    private static func namedNode(_ name: String, in view: InteractiveSceneView) -> SCNNode? {
        guard let scene = view.scene else { return nil }
        return allNodes(in: scene.rootNode).first { $0.name == name }
    }

    private static func click(
        nodeName: String,
        in view: InteractiveSceneView,
        coordinator: SceneViewportCoordinator,
        recorder: IntentRecorder
    ) -> SceneIntent? {
        guard let scene = view.scene,
              let node = allNodes(in: scene.rootNode).first(where: { $0.name == nodeName }) else {
            return nil
        }
        let projected = view.projectPoint(node.convertPosition(SCNVector3Zero, to: nil))
        guard projected.x.isFinite, projected.y.isFinite else { return nil }
        return click(
            at: CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y)),
            in: view,
            coordinator: coordinator,
            recorder: recorder
        )
    }

    private static func click(
        at point: CGPoint,
        in view: InteractiveSceneView,
        coordinator: SceneViewportCoordinator,
        recorder: IntentRecorder
    ) -> SceneIntent? {
        recorder.intents.removeAll()
        coordinator.viewport(view, didClickAt: point)
        return recorder.intents.last
    }

    private final class IntentRecorder {
        var intents: [SceneIntent] = []
    }

    private static func keyEvent(
        _ characters: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private static func samePosition(_ lhs: SCNVector3, _ rhs: SCNVector3) -> Bool {
        distance(from: lhs, to: rhs) < 0.000_001
    }

    private static func distance(from position: SCNVector3, to target: SCNVector3) -> CGFloat {
        let dx = position.x - target.x
        let dy = position.y - target.y
        let dz = position.z - target.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private static func allNodes(in root: SCNNode) -> [SCNNode] {
        var result = [root]
        for child in root.childNodes {
            result.append(contentsOf: allNodes(in: child))
        }
        return result
    }
}

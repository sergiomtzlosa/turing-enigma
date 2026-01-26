import AppKit
import SceneKit
import Metal
import Foundation
import TuringEnigmaCore

enum SceneSnapshot {
    @discardableResult
    static func runIfRequested() -> Bool {
        guard let index = CommandLine.arguments.firstIndex(of: "--snapshot") else { return false }
        let directory = index + 1 < CommandLine.arguments.count
            ? CommandLine.arguments[index + 1]
            : ".build/snapshots"
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            fputs("Could not create snapshot directory: \(error)\n", stderr)
            return true
        }
        renderEnigma(to: directory)
        renderBombe(to: directory)
        return true
    }

    static func renderEnigma(to directory: String) {
        let renderer = EnigmaSceneRenderer()
        let scenario = DemoScenario.weather
        var presentation = EnigmaPresentation(settings: scenario.settings)
        presentation.rotorPositions = scenario.settings.initialPositions
        presentation.pressedKey = "W"
        presentation.litLamp = "G"
        renderer.apply(settings: scenario.settings, presentation: presentation, selection: .enigmaRotor(1), animated: false)

        let views: [(String, CameraPreset)] = [
            ("enigma-overview", .overview),
            ("enigma-keyboard", .keyboard),
            ("enigma-rotors", .rotors),
            ("enigma-plugboard", .plugboard)
        ]
        for (name, preset) in views {
            let config = renderer.cameraConfiguration(for: preset)
            renderer.cameraNode.position = renderer.position(for: config)
            renderer.cameraNode.lookAtSceneTarget(config.target)
            renderer.updateBackWallVisibility(forCameraPosition: renderer.cameraNode.position)
            render(scene: renderer.scene, camera: renderer.cameraNode, name: name, directory: directory)
        }

        // Orbited all the way behind the desk. The near wall hides, leaving the
        // machine readable instead of showing an unlit wall face.
        let backConfig = SceneCameraConfiguration(
            target: SCNVector3(0, 0.88, 0.01),
            distance: 1.15,
            yaw: .pi,
            pitch: 0.50
        )
        renderer.cameraNode.position = renderer.position(for: backConfig)
        renderer.cameraNode.lookAtSceneTarget(backConfig.target)
        renderer.updateBackWallVisibility(forCameraPosition: renderer.cameraNode.position)
        render(scene: renderer.scene, camera: renderer.cameraNode, name: "enigma-back", directory: directory)

        let backWideConfig = SceneCameraConfiguration(
            target: SCNVector3(0, 0.88, 0.01),
            distance: 2.40,
            yaw: .pi,
            pitch: 0.50
        )
        renderer.cameraNode.position = renderer.position(for: backWideConfig)
        renderer.cameraNode.lookAtSceneTarget(backWideConfig.target)
        renderer.updateBackWallVisibility(forCameraPosition: renderer.cameraNode.position)
        render(scene: renderer.scene, camera: renderer.cameraNode, name: "enigma-back-wide", directory: directory)

        renderer.cameraNode.position = SCNVector3(0, 1.20, 0.10)
        renderer.cameraNode.lookAtSceneTarget(SCNVector3(0, 0.87, -0.005))
        renderer.updateBackWallVisibility(forCameraPosition: renderer.cameraNode.position)
        render(scene: renderer.scene, camera: renderer.cameraNode, name: "enigma-top", directory: directory)
    }

    static func renderBombe(to directory: String) {
        let renderer = BombeSceneRenderer()
        let scenario = DemoScenario.weather
        let stop = BombeStop(
            rotorOrder: scenario.settings.rotorIDs,
            ringSettings: scenario.settings.ringSettings,
            initialPositions: scenario.settings.initialPositions,
            cribPositions: [],
            plugboard: [],
            plugboardMap: Array(0..<26),
            hypothesis: "E",
            decryptedText: scenario.plaintext,
            languageScore: 1.8,
            confidence: 0.96,
            loopCount: 7
        )
        renderer.apply(state: .running, progress: 0.56, selectedStop: nil, selection: .bombeDrums)
        let runningViews: [(String, CameraPreset)] = [
            ("bombe-overview", .overview),
            ("bombe-drums", .drums)
        ]
        for (name, preset) in runningViews {
            let config = renderer.cameraConfiguration(for: preset)
            renderer.cameraNode.position = renderer.position(for: config)
            renderer.cameraNode.lookAtSceneTarget(config.target)
            renderer.updateBackWallVisibility(forCameraPosition: renderer.cameraNode.position)
            render(scene: renderer.scene, camera: renderer.cameraNode, name: name, directory: directory)
        }

        renderer.apply(state: .stopped, progress: 1.0, selectedStop: stop, selection: .bombeControls)
        let stoppedViews: [(String, CameraPreset)] = [
            ("bombe-controls", .controls),
            ("bombe-indicators", .keyboard)
        ]
        for (name, preset) in stoppedViews {
            let config = renderer.cameraConfiguration(for: preset)
            renderer.cameraNode.position = renderer.position(for: config)
            renderer.cameraNode.lookAtSceneTarget(config.target)
            renderer.updateBackWallVisibility(forCameraPosition: renderer.cameraNode.position)
            render(scene: renderer.scene, camera: renderer.cameraNode, name: name, directory: directory)
        }

        let backConfig = SceneCameraConfiguration(
            target: SCNVector3(0, 1.02, 0.02),
            distance: 3.80,
            yaw: .pi,
            pitch: 0.34
        )
        renderer.cameraNode.position = renderer.position(for: backConfig)
        renderer.cameraNode.lookAtSceneTarget(backConfig.target)
        renderer.updateBackWallVisibility(forCameraPosition: renderer.cameraNode.position)
        render(scene: renderer.scene, camera: renderer.cameraNode, name: "bombe-back", directory: directory)
    }

    static func render(scene: SCNScene, camera: SCNNode, name: String, directory: String) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fputs("Metal device unavailable\n", stderr)
            return
        }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let size = CGSize(width: 1600, height: 1100)
        let image = renderer.snapshot(atTime: 1.0, with: size, antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fputs("Could not encode \(name)\n", stderr)
            return
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        do {
            try png.write(to: url)
            print("snapshot:", url.path)
        } catch {
            fputs("Could not save \(name): \(error)\n", stderr)
        }
    }
}

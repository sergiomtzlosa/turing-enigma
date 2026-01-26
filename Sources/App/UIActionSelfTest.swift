import AppKit
import SceneKit
import SwiftUI
import TuringEnigmaCore

/// Records SwiftUI control frames while a headless UI action check is running.
/// Frames are expressed in the `ui-probe` coordinate space (top-left origin).
enum UIActionProbe {
    static var frames: [String: CGRect] = [:]
    static var isEnabled: Bool { CommandLine.arguments.contains("--ui-action-check") }

    static func record(_ name: String, _ frame: CGRect) {
        guard isEnabled else { return }
        frames[name] = frame
    }
}

extension View {
    func uiProbeFrame(_ name: String) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("ui-probe"))
        } action: { frame in
            UIActionProbe.record(name, frame)
        }
    }
}

/// Drives the real SwiftUI controls through an offscreen `NSHostingView`.
/// This catches the class of bug where a button is visible but obscured or the
/// model action is not wired, without needing Developer Mode or UI automation.
enum UIActionSelfTest {
    static func runIfRequested() -> Int32? {
        guard CommandLine.arguments.contains("--ui-action-check") else { return nil }
        let failures = MainActor.assumeIsolated { check() }
        if failures.isEmpty {
            print("ui action check passed: demo, center, encipher, and send buttons route to the model")
            return 0
        }
        for failure in failures {
            fputs("ui action check: \(failure)\n", stderr)
        }
        return 1
    }

    @MainActor
    private static func check() -> [String] {
        var failures: [String] = []
        let model = AppModel(loadPersisted: false)
        model.isSoundEnabled = false
        model.sound.isEnabled = false
        model.animatePlayback = false

        let size = NSSize(width: 1180, height: 792)
        let host = NSHostingView(
            rootView: ContentView()
                .environment(model)
                .frame(width: size.width, height: size.height)
        )
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        host.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let viewport = findViewport(in: host) else {
            failures.append("The hosted ContentView did not contain the 3D viewport")
            return failures
        }
        guard let camera = viewport.pointOfView else {
            failures.append("The 3D viewport has no camera")
            return failures
        }

        func frame(_ name: String) -> CGRect? {
            UIActionProbe.frames[name]
        }

        func point(_ name: String) -> NSPoint? {
            guard let frame = frame(name) else { return nil }
            // `ui-probe` uses SwiftUI's top-left origin; AppKit views use
            // bottom-left. The probe coordinate space fills the hosting view.
            return NSPoint(x: frame.midX, y: size.height - frame.midY)
        }

        for name in ["demo", "center", "encipher", "bombe.send"] where frame(name) == nil {
            failures.append("Missing control frame: \(name)")
        }
        guard failures.isEmpty else { return failures }

        for name in ["demo", "center", "encipher", "bombe.send"] {
            guard let p = point(name) else { continue }
            if host.hitTest(p) is InteractiveSceneView {
                failures.append("The 3D viewport intercepts the \(name) control")
            }
        }

        guard let demoPoint = point("demo") else { return failures }
        click(demoPoint, in: window)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        if model.message != DemoScenario.weather.plaintext {
            failures.append("Demo button did not load the weather message")
        }
        if model.enigma.windowLetters != "EHL" {
            failures.append("Demo button did not load the EHL window setting")
        }

        // Exercise the real SwiftUI Center path after moving the camera. This
        // checks the visible presentation state, not only the model request.
        let defaultCameraPosition = camera.position
        let defaultCameraOrientation = camera.worldOrientation
        let defaultPresentationPosition = camera.presentation.position
        let defaultPresentationOrientation = camera.presentation.worldOrientation

        viewport.interactionDelegate?.viewport(viewport, didOrbitBy: CGSize(width: 180, height: 45))
        viewport.interactionDelegate?.viewport(viewport, didPanBy: CGSize(width: 320, height: 180))
        viewport.interactionDelegate?.viewport(viewport, didZoomBy: -240, precise: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        if samePosition(camera.position, defaultCameraPosition) {
            failures.append("The test gesture did not move the 3D camera")
        }

        let centerBefore = model.centerRequestID
        if let centerPoint = point("center") {
            click(centerPoint, in: window)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            if model.centerRequestID == centerBefore {
                failures.append("Center button did not request a camera recenter")
            }
            if !samePosition(camera.position, defaultCameraPosition) {
                failures.append("Center did not restore the default 3D camera position")
            }
            if !sameOrientation(camera.worldOrientation, defaultCameraOrientation) {
                failures.append("Center did not restore the default 3D camera orientation")
            }
            if !samePosition(camera.presentation.position, defaultPresentationPosition) {
                failures.append("Center did not restore the visible camera position")
            }
            if !sameOrientation(camera.presentation.worldOrientation, defaultPresentationOrientation) {
                failures.append("Center did not restore the visible camera orientation")
            }
        }

        if let encipherPoint = point("encipher") {
            click(encipherPoint, in: window)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if model.output != DemoScenario.weather.ciphertext {
                failures.append("Encipher button did not produce the demo ciphertext")
            }
        }

        // Enciphering adds the live transcript row, which moves the console
        // buttons. Re-read the frame so the synthetic click lands on the button.
        if let sendPoint = point("bombe.send") {
            click(sendPoint, in: window)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if model.mode != .bombe {
                failures.append("Send to Bombe button did not switch modes")
            }
            if model.bombe.ciphertext != DemoScenario.weather.ciphertext {
                failures.append("Send to Bombe button did not transfer the ciphertext")
            }
        }

        // The Bombe Center button lives in the same overlay and must be hittable.
        if let centerPoint = point("center") {
            if host.hitTest(centerPoint) is InteractiveSceneView {
                failures.append("The 3D viewport intercepts the Bombe Center control")
            }
            let bombeCenterBefore = model.centerRequestID
            click(centerPoint, in: window)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if model.centerRequestID == bombeCenterBefore {
                failures.append("Center button did not work in Bombe mode")
            }
        }

        return failures
    }

    @MainActor
    private static func click(_ point: NSPoint, in window: NSWindow) {
        let now = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: now,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ), let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: point,
            modifierFlags: [],
            timestamp: now + 0.05,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0
        ) else {
            return
        }
        window.sendEvent(down)
        window.sendEvent(up)
    }

    private static func findViewport(in view: NSView) -> InteractiveSceneView? {
        if let viewport = view as? InteractiveSceneView {
            return viewport
        }
        for child in view.subviews {
            if let viewport = findViewport(in: child) {
                return viewport
            }
        }
        return nil
    }

    private static func samePosition(_ lhs: SCNVector3, _ rhs: SCNVector3) -> Bool {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        let dz = lhs.z - rhs.z
        return sqrt(dx * dx + dy * dy + dz * dz) < 0.001
    }

    private static func sameOrientation(_ lhs: SCNQuaternion, _ rhs: SCNQuaternion) -> Bool {
        let dot = lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z + lhs.w * rhs.w
        return abs(abs(dot) - 1) < 0.0001
    }
}

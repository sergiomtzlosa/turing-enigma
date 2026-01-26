import AppKit
import SceneKit
import SwiftUI
import simd
import TuringEnigmaCore

extension SCNNode {
    /// Uses a fixed world up and the camera's local forward axis. SceneKit's
    /// simpler `look(at:)` can preserve roll from the node's previous
    /// orientation, which made Center restore the same position but a visibly
    /// different camera roll after an orbit.
    func lookAtSceneTarget(_ target: SCNVector3) {
        look(
            at: target,
            up: SCNVector3(0, 1, 0),
            localFront: SCNVector3(0, 0, -1)
        )
    }
}

/// The SwiftUI surface for the SceneKit world. It hosts a single `SCNView`
/// and swaps scenes when the app changes between the Enigma and the Bombe.
struct MachineViewport: View {
    let mode: AppMode
    let enigma: EnigmaSettings
    let presentation: EnigmaPresentation
    let selection: ComponentSelection?
    let bombe: BombeConfig
    let bombeState: BombeRunState
    let bombeProgress: Double
    let selectedStop: BombeStop?
    let cameraRequest: CameraPreset
    let cameraRequestID: UUID
    let centerRequestID: UUID
    let onIntent: (SceneIntent) -> Void

    var body: some View {
        SceneViewportRepresentable(
            mode: mode,
            enigma: enigma,
            presentation: presentation,
            selection: selection,
            bombe: bombe,
            bombeState: bombeState,
            bombeProgress: bombeProgress,
            selectedStop: selectedStop,
            cameraRequest: cameraRequest,
            cameraRequestID: cameraRequestID,
            centerRequestID: centerRequestID,
            onIntent: onIntent
        )
    }
}

// MARK: - SwiftUI bridge

private struct SceneViewportRepresentable: NSViewRepresentable {
    let mode: AppMode
    let enigma: EnigmaSettings
    let presentation: EnigmaPresentation
    let selection: ComponentSelection?
    let bombe: BombeConfig
    let bombeState: BombeRunState
    let bombeProgress: Double
    let selectedStop: BombeStop?
    let cameraRequest: CameraPreset
    let cameraRequestID: UUID
    let centerRequestID: UUID
    let onIntent: (SceneIntent) -> Void

    func makeCoordinator() -> SceneViewportCoordinator {
        SceneViewportCoordinator()
    }

    func makeNSView(context: Context) -> InteractiveSceneView {
        let view = InteractiveSceneView(frame: .zero, options: nil)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: InteractiveSceneView, context: Context) {
        context.coordinator.update(
            view: nsView,
            mode: mode,
            enigma: enigma,
            presentation: presentation,
            selection: selection,
            bombe: bombe,
            bombeState: bombeState,
            bombeProgress: bombeProgress,
            selectedStop: selectedStop,
            cameraRequest: cameraRequest,
            cameraRequestID: cameraRequestID,
            centerRequestID: centerRequestID,
            onIntent: onIntent
        )
    }
}

// MARK: - Interaction

protocol SceneViewportInteractionDelegate: AnyObject {
    func viewport(_ view: InteractiveSceneView, didClickAt point: CGPoint)
    func viewport(_ view: InteractiveSceneView, didOrbitBy delta: CGSize)
    func viewport(_ view: InteractiveSceneView, didPanBy delta: CGSize)
    func viewport(_ view: InteractiveSceneView, didZoomBy delta: CGFloat, precise: Bool)
    func viewport(_ view: InteractiveSceneView, didMagnifyBy delta: CGFloat)
    func viewport(_ view: InteractiveSceneView, handleKeyDown event: NSEvent) -> Bool
}

/// An `SCNView` that forwards camera gestures and keyboard events to the
/// coordinator while keeping SceneKit's own camera controls disabled.
final class InteractiveSceneView: SCNView {
    weak var interactionDelegate: SceneViewportInteractionDelegate?

    private var dragOrigin: CGPoint = .zero
    private var lastDragPoint: CGPoint = .zero
    private var isDragging = false
    private var rightDragging = false
    private var didAutoFocus = false

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !didAutoFocus else { return }
        didAutoFocus = true
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            if window.firstResponder is NSText || window.firstResponder is NSTextView { return }
            window.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragOrigin = convert(event.locationInWindow, from: nil)
        lastDragPoint = dragOrigin
        isDragging = false
        rightDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - dragOrigin.x, point.y - dragOrigin.y)
        if !isDragging, distance >= 3 {
            isDragging = true
        }
        guard isDragging else { return }

        let delta = CGSize(width: point.x - lastDragPoint.x, height: point.y - lastDragPoint.y)
        lastDragPoint = point
        let wantsPan = rightDragging
            || event.modifierFlags.contains(.option)
            || event.modifierFlags.contains(.shift)
        if wantsPan {
            interactionDelegate?.viewport(self, didPanBy: delta)
        } else {
            interactionDelegate?.viewport(self, didOrbitBy: delta)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            isDragging = false
            rightDragging = false
        }
        guard !isDragging else { return }
        interactionDelegate?.viewport(self, didClickAt: dragOrigin)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastDragPoint = convert(event.locationInWindow, from: nil)
        rightDragging = true
        isDragging = false
    }

    override func rightMouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let delta = CGSize(width: point.x - lastDragPoint.x, height: point.y - lastDragPoint.y)
        lastDragPoint = point
        interactionDelegate?.viewport(self, didPanBy: delta)
    }

    override func rightMouseUp(with event: NSEvent) {
        rightDragging = false
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else {
            super.scrollWheel(with: event)
            return
        }
        interactionDelegate?.viewport(self, didZoomBy: delta, precise: event.hasPreciseScrollingDeltas)
    }

    override func magnify(with event: NSEvent) {
        interactionDelegate?.viewport(self, didMagnifyBy: event.magnification)
    }

    override func keyDown(with event: NSEvent) {
        if interactionDelegate?.viewport(self, handleKeyDown: event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Coordinator

private struct CameraRig {
    var target: SCNVector3
    var distance: CGFloat
    var yaw: CGFloat
    var pitch: CGFloat

    init(_ configuration: SceneCameraConfiguration) {
        target = configuration.target
        distance = configuration.distance
        yaw = configuration.yaw
        pitch = configuration.pitch
    }

    var configuration: SceneCameraConfiguration {
        SceneCameraConfiguration(target: target, distance: distance, yaw: yaw, pitch: pitch)
    }
}

final class SceneViewportCoordinator: SceneViewportInteractionDelegate {
    private weak var view: InteractiveSceneView?
    private var onIntent: ((SceneIntent) -> Void)?

    private let enigmaRenderer = EnigmaSceneRenderer()
    private lazy var bombeRenderer = BombeSceneRenderer()

    private var mode: AppMode = .enigma
    private var enigmaRig: CameraRig?
    private var bombeRig: CameraRig?
    private var lastCameraRequestID: UUID?
    private var lastCenterRequestID: UUID?

    // MARK: Lifecycle

    func attach(to view: InteractiveSceneView) {
        self.view = view
        view.interactionDelegate = self
        view.scene = enigmaRenderer.scene
        view.pointOfView = enigmaRenderer.cameraNode
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.showsStatistics = false
        view.setAccessibilityLabel("Interactive 3D machine viewport")

        mode = .enigma
        enigmaRig = CameraRig(enigmaRenderer.defaultCameraConfiguration)
        applyCamera(animated: false)
    }

    func update(
        view: InteractiveSceneView,
        mode: AppMode,
        enigma: EnigmaSettings,
        presentation: EnigmaPresentation,
        selection: ComponentSelection?,
        bombe: BombeConfig,
        bombeState: BombeRunState,
        bombeProgress: Double,
        selectedStop: BombeStop?,
        cameraRequest: CameraPreset,
        cameraRequestID: UUID,
        centerRequestID: UUID,
        onIntent: @escaping (SceneIntent) -> Void
    ) {
        self.onIntent = onIntent

        if self.mode != mode {
            activate(mode, in: view)
        }

        switch mode {
        case .enigma:
            enigmaRenderer.apply(
                settings: enigma,
                presentation: presentation,
                selection: selection
            )
        case .bombe:
            bombeRenderer.apply(
                state: bombeState,
                progress: bombeProgress,
                selectedStop: selectedStop,
                selection: selection
            )
        }

        if lastCameraRequestID != cameraRequestID {
            lastCameraRequestID = cameraRequestID
            apply(preset: cameraRequest, animated: true)
            view.window?.makeFirstResponder(view)
        }
        // The initial request ID is a baseline, not a Center action. Otherwise
        // the first SwiftUI update would replace the default overview with the
        // Center framing before the user pressed anything.
        if lastCenterRequestID == nil {
            lastCenterRequestID = centerRequestID
        } else if lastCenterRequestID != centerRequestID {
            lastCenterRequestID = centerRequestID
            center(animated: true)
            view.window?.makeFirstResponder(view)
        }
    }

    private func activate(_ newMode: AppMode, in view: InteractiveSceneView) {
        mode = newMode
        switch newMode {
        case .enigma:
            view.scene = enigmaRenderer.scene
            view.pointOfView = enigmaRenderer.cameraNode
            if enigmaRig == nil {
                enigmaRig = CameraRig(enigmaRenderer.defaultCameraConfiguration)
            }
        case .bombe:
            view.scene = bombeRenderer.scene
            view.pointOfView = bombeRenderer.cameraNode
            if bombeRig == nil {
                bombeRig = CameraRig(bombeRenderer.defaultCameraConfiguration)
            }
        }
        view.window?.makeFirstResponder(view)
        applyCamera(animated: true)
    }

    // MARK: Camera

    private var activeRig: CameraRig? {
        get { mode == .enigma ? enigmaRig : bombeRig }
        set {
            if mode == .enigma {
                enigmaRig = newValue
            } else {
                bombeRig = newValue
            }
        }
    }

    private var activeCameraNode: SCNNode {
        mode == .enigma ? enigmaRenderer.cameraNode : bombeRenderer.cameraNode
    }

    /// Horizontal orbit is unrestricted. The renderer hides the near back wall
    /// when the camera crosses behind it, so the model can be inspected from all
    /// sides without the room turning into a black screen. Pitch, distance and
    /// pan still stay inside sensible physical limits.
    private var pitchRange: ClosedRange<CGFloat> {
        mode == .enigma ? 0.12...0.95 : 0.06...0.68
    }

    private var distanceRange: ClosedRange<CGFloat> {
        mode == .enigma ? 0.55...4.80 : 1.05...7.80
    }

    private var targetBounds: (
        x: ClosedRange<CGFloat>,
        y: ClosedRange<CGFloat>,
        z: ClosedRange<CGFloat>
    ) {
        switch mode {
        case .enigma:
            return (-0.40...0.40, 0.72...1.10, -0.15...0.30)
        case .bombe:
            return (-0.90...0.90, 0.80...1.85, -0.15...0.45)
        }
    }

    private func clamped(_ rig: CameraRig) -> CameraRig {
        var result = rig
        result.yaw = normalizedAngle(result.yaw)
        result.pitch = min(max(result.pitch, pitchRange.lowerBound), pitchRange.upperBound)
        result.distance = min(max(result.distance, distanceRange.lowerBound), distanceRange.upperBound)

        let bounds = targetBounds
        result.target.x = min(max(result.target.x, bounds.x.lowerBound), bounds.x.upperBound)
        result.target.y = min(max(result.target.y, bounds.y.lowerBound), bounds.y.upperBound)
        result.target.z = min(max(result.target.z, bounds.z.lowerBound), bounds.z.upperBound)
        return result
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var result = angle.truncatingRemainder(dividingBy: .pi * 2)
        if result > .pi { result -= .pi * 2 }
        if result < -.pi { result += .pi * 2 }
        return result
    }

    private func cameraPosition(for configuration: SceneCameraConfiguration) -> SCNVector3 {
        switch mode {
        case .enigma:
            return enigmaRenderer.position(for: configuration)
        case .bombe:
            return bombeRenderer.position(for: configuration)
        }
    }

    private func applyCamera(animated: Bool) {
        guard var rig = activeRig else { return }
        rig = clamped(rig)
        activeRig = rig
        let configuration = rig.configuration
        let node = activeCameraNode

        node.removeAllAnimations()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.42 : 0
        node.position = cameraPosition(for: configuration)
        node.lookAtSceneTarget(rig.target)
        SCNTransaction.commit()

        switch mode {
        case .enigma:
            enigmaRenderer.updateBackWallVisibility(forCameraPosition: node.position)
        case .bombe:
            bombeRenderer.updateBackWallVisibility(forCameraPosition: node.position)
        }
    }

    private func apply(preset: CameraPreset, animated: Bool) {
        let configuration: SceneCameraConfiguration
        switch mode {
        case .enigma:
            configuration = enigmaRenderer.cameraConfiguration(for: preset)
        case .bombe:
            configuration = bombeRenderer.cameraConfiguration(for: preset)
        }
        activeRig = CameraRig(configuration)
        applyCamera(animated: animated)
    }

    /// Restores the default isometric view so a panned, orbited, or zoomed
    /// viewport returns to exactly the framing the user started with.
    private func center(animated: Bool) {
        apply(preset: .overview, animated: animated)
    }

    private func clampedDistance(_ value: CGFloat) -> CGFloat {
        let range = distanceRange
        return min(max(value, range.lowerBound), range.upperBound)
    }

    func viewport(_ view: InteractiveSceneView, didOrbitBy delta: CGSize) {
        guard var rig = activeRig else { return }
        rig.yaw = normalizedAngle(rig.yaw - delta.width * 0.0045)
        rig.pitch += delta.height * 0.0045
        activeRig = rig
        applyCamera(animated: false)
    }

    func viewport(_ view: InteractiveSceneView, didPanBy delta: CGSize) {
        guard var rig = activeRig else { return }
        let configuration = rig.configuration
        let position = cameraPosition(for: configuration)
        let forward = SIMD3<Float>(
            Float(rig.target.x - position.x),
            Float(rig.target.y - position.y),
            Float(rig.target.z - position.z)
        )
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_normalize(simd_cross(right, forward))
        let scale = Float(rig.distance * 0.0007)
        let translation = right * Float(delta.width) * scale + up * Float(delta.height) * scale

        rig.target.x -= CGFloat(translation.x)
        rig.target.y -= CGFloat(translation.y)
        rig.target.z -= CGFloat(translation.z)
        activeRig = rig
        applyCamera(animated: false)
    }

    func viewport(_ view: InteractiveSceneView, didZoomBy delta: CGFloat, precise: Bool) {
        guard var rig = activeRig else { return }
        let sensitivity: CGFloat = precise ? 0.006 : 0.10
        rig.distance = clampedDistance(rig.distance * CGFloat(exp(Double(-delta * sensitivity))))
        activeRig = rig
        applyCamera(animated: false)
    }

    func viewport(_ view: InteractiveSceneView, didMagnifyBy delta: CGFloat) {
        guard var rig = activeRig else { return }
        rig.distance = clampedDistance(rig.distance * CGFloat(exp(Double(-delta * 1.7))))
        activeRig = rig
        applyCamera(animated: false)
    }

    // MARK: Hit testing

    func viewport(_ view: InteractiveSceneView, didClickAt point: CGPoint) {
        let options: [SCNHitTestOption: Any] = [
            .searchMode: SCNHitTestSearchMode.all.rawValue,
            .ignoreHiddenNodes: true,
            .backFaceCulling: false
        ]
        let hits = view.hitTest(point, options: options)
        let root = mode == .enigma ? enigmaRenderer.machineRoot : bombeRenderer.machineRoot
        var fallback: ComponentSelection?

        for hit in hits {
            var node: SCNNode? = hit.node
            while let candidate = node {
                if let name = candidate.name {
                    if name == "selection.highlight" { break }
                    if let intent = SceneIntentMapper.intent(for: name, mode: mode) {
                        onIntent?(intent)
                        return
                    }
                }
                if candidate === root {
                    if fallback == nil {
                        fallback = mode == .enigma ? .enigmaCase : .bombeCabinet
                    }
                    break
                }
                node = candidate.parent
            }
        }

        if let fallback {
            onIntent?(.select(fallback))
        } else {
            onIntent?(.select(nil))
        }
    }

    // MARK: Keyboard

    func viewport(_ view: InteractiveSceneView, handleKeyDown event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
        }
        if event.keyCode == 53 {
            onIntent?(.select(nil))
            return true
        }
        guard mode == .enigma else { return false }
        guard let characters = event.charactersIgnoringModifiers?.uppercased(),
              let first = characters.first,
              Alphabet.index(of: first) != nil else {
            return false
        }
        if !event.isARepeat {
            onIntent?(.pressKey(first))
        }
        return true
    }
}

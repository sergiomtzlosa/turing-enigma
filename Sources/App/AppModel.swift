import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers
import TuringEnigmaCore

enum AppMode: String, CaseIterable, Identifiable {
    case enigma = "Enigma"
    case bombe = "Bombe"

    var id: String { rawValue }
}

enum CameraPreset: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case keyboard = "Keyboard"
    case rotors = "Rotors"
    case plugboard = "Plugboard"
    case drums = "Drum bank"
    case controls = "Controls"

    var id: String { rawValue }
}

enum ComponentSelection: Hashable {
    case enigmaCase
    case enigmaLid
    case enigmaKeyboard
    case enigmaLampboard
    case enigmaPlugboard
    case enigmaRotor(Int)
    case enigmaReflector
    case bombeCabinet
    case bombeDrums
    case bombeIndicators
    case bombeControls
    case bombeMenu
}

enum BombeRunState: Equatable {
    case idle
    case running
    case stopped
}

enum SceneIntent: Equatable {
    case pressKey(Character)
    case plug(Character)
    case select(ComponentSelection?)
    case startBombe
    case stopBombe
    case camera(CameraPreset)
}

struct EnigmaPresentation: Equatable {
    var rotorPositions: [Int]
    var litLamp: Character?
    var pressedKey: Character?

    init(settings: EnigmaSettings) {
        rotorPositions = settings.initialPositions
        litLamp = nil
        pressedKey = nil
    }
}

struct BombeConfig: Equatable {
    var ciphertext: String = ""
    var crib: String = ""
    var cribOffset: Int = 0
    var rotorCandidates: [String] = ["I", "II", "III"]
    var ringSettings: [Int] = [0, 0, 0]
    var reflectorID: String = "B"
    var language: BombeLanguage = .german
    var knownPlugboard: [PlugboardPair] = []

    var query: BombeQuery {
        BombeQuery(
            ciphertext: ciphertext,
            crib: crib,
            cribOffset: cribOffset,
            rotorCandidates: rotorCandidates,
            ringSettings: ringSettings,
            reflectorID: reflectorID,
            knownPlugboard: knownPlugboard,
            language: language,
            maxResults: 24
        )
    }

    var ringLetters: String {
        String(ringSettings.map { Alphabet.letter(at: $0) })
    }

    /// A short, user-facing description of anything that prevents the current
    /// crib from being used. Validation happens before the solver starts so a
    /// bad crib cannot leave the app in a running state or raise a modal alert.
    var validationIssue: String? {
        let normalisedCipher = Alphabet.normalize(ciphertext)
        let normalisedCrib = Alphabet.normalize(crib)
        guard !normalisedCipher.isEmpty else {
            return "Paste a ciphertext before running the Bombe."
        }
        guard !normalisedCrib.isEmpty else {
            return "Enter a crib — a guessed plaintext fragment."
        }
        guard cribOffset >= 0, cribOffset + normalisedCrib.count <= normalisedCipher.count else {
            return "The crib does not fit this ciphertext. Shorten it or move the offset."
        }
        return nil
    }
}

@MainActor
@Observable
final class AppModel {
    var mode: AppMode = .enigma
    var enigma: EnigmaSettings = .standard
    var presentation: EnigmaPresentation
    var message: String = ""
    var output: String = ""
    var liveInput: String = ""
    var liveOutput: String = ""
    var animatePlayback: Bool = true
    var isAnimating: Bool = false

    var pendingPlug: Character?
    var selectedComponent: ComponentSelection?

    var bombe: BombeConfig = BombeConfig()
    var bombeState: BombeRunState = .idle
    var bombeProgress: Double = 0
    var bombeResults: [BombeStop] = []
    var bombeSummary: BombeResult?
    var selectedStopID: UUID?

    var isInspectorVisible: Bool = true
    var isSoundEnabled: Bool = true
    var showHelp: Bool = false
    var toast: String?

    var cameraRequest: CameraPreset = .overview
    var cameraRequestID: UUID = UUID()
    var centerRequestID: UUID = UUID()

    let sound = SoundEngine()
    private var bombeTask: Task<Void, Never>?
    private var bombeSolverTask: Task<Result<BombeResult, Error>, Never>?
    private var bombeRunToken: UUID?
    private var playbackToken: UUID?
    private var flashToken: UUID = UUID()
    private var toastTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var hasLoaded = false

    init(loadPersisted: Bool = true) {
        let initial = EnigmaSettings.standard
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        self.enigma = initial
        self.presentation = EnigmaPresentation(settings: initial)
        sound.isEnabled = isSoundEnabled
        if loadPersisted, !isUITesting, let preset = PresetStore.loadLast() {
            enigma = preset.enigma
            presentation = EnigmaPresentation(settings: preset.enigma)
            message = preset.message
            output = preset.output
            bombe.ciphertext = preset.bombeCiphertext
            // Older builds could persist the demo crib beside a shorter custom
            // ciphertext. Never reopen the app with a crib that cannot fit.
            let savedCipher = Alphabet.normalize(preset.bombeCiphertext)
            let savedCrib = Alphabet.normalize(preset.bombeCrib)
            let savedOffset = max(0, preset.bombeOffset)
            if !savedCrib.isEmpty, savedOffset + savedCrib.count <= savedCipher.count {
                bombe.crib = savedCrib
                bombe.cribOffset = savedOffset
            } else {
                bombe.crib = ""
                bombe.cribOffset = 0
            }
        }
        // UI tests must never read or write the user's saved session.
        hasLoaded = !isUITesting
    }

    var statusText: String {
        switch mode {
        case .enigma:
            if isAnimating { return "ENCODING" }
            if presentation.litLamp != nil { return "LAMP \(presentation.litLamp!)" }
            return "STANDBY"
        case .bombe:
            switch bombeState {
            case .idle: return "STANDBY"
            case .running: return "SEARCHING · \(Int(bombeProgress * 100))%"
            case .stopped: return bombeResults.isEmpty ? "NO STOPS" : "STOP FOUND"
            }
        }
    }

    var selectedStop: BombeStop? {
        guard let selectedStopID else { return bombeResults.first }
        return bombeResults.first(where: { $0.id == selectedStopID }) ?? bombeResults.first
    }

    // MARK: - Enigma configuration

    func changeMachine(to type: EnigmaMachineType) {
        enigma.changeMachineType(to: type)
        resetRunState()
        scheduleSave()
    }

    func setReflector(_ id: String) {
        enigma.reflectorID = id
        resetRunState()
        scheduleSave()
    }

    func setRotor(at index: Int, to id: String) {
        guard enigma.rotorIDs.indices.contains(index) else { return }
        var ids = enigma.rotorIDs
        if let existing = ids.firstIndex(of: id), existing != index {
            ids.swapAt(index, existing)
        } else {
            ids[index] = id
        }
        enigma.rotorIDs = ids
        resetRunState()
        scheduleSave()
    }

    func availableRotors(for index: Int) -> [String] {
        if enigma.machineType == .m4 && index == 0 {
            return ["Beta", "Gamma"]
        }
        if enigma.machineType == .m4 {
            return ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
        }
        return enigma.machineType.availableRotorIDs
    }

    func setRing(at index: Int, to value: Int) {
        guard enigma.ringSettings.indices.contains(index) else { return }
        enigma.ringSettings[index] = ((value % 26) + 26) % 26
        resetRunState()
        scheduleSave()
    }

    func setWindow(at index: Int, to value: Int) {
        guard enigma.initialPositions.indices.contains(index) else { return }
        enigma.initialPositions[index] = ((value % 26) + 26) % 26
        resetRunState()
        scheduleSave()
    }

    func stepRing(at index: Int, by delta: Int) {
        guard enigma.ringSettings.indices.contains(index) else { return }
        setRing(at: index, to: enigma.ringSettings[index] + delta)
    }

    func stepWindow(at index: Int, by delta: Int) {
        guard enigma.initialPositions.indices.contains(index) else { return }
        setWindow(at: index, to: enigma.initialPositions[index] + delta)
    }

    func resetRunState() {
        guard hasLoaded else { return }
        cancelPlayback()
        presentation = EnigmaPresentation(settings: enigma)
        liveInput = ""
        liveOutput = ""
        pendingPlug = nil
    }

    private func cancelPlayback() {
        playbackToken = nil
        isAnimating = false
        presentation.pressedKey = nil
        presentation.litLamp = nil
    }

    func resetMachine() {
        resetRunState()
        output = ""
        toastMessage("Machine reset")
    }

    // MARK: - Plugboard

    func togglePlug(_ letter: Character) {
        let upper = Character(String(letter).uppercased())
        guard Alphabet.index(of: upper) != nil else { return }
        if let existing = enigma.plugboard.firstIndex(where: { $0.first == upper || $0.second == upper }) {
            enigma.plugboard.remove(at: existing)
            pendingPlug = nil
            scheduleSave()
            return
        }
        if let pending = pendingPlug {
            if pending == upper {
                pendingPlug = nil
                return
            }
            guard enigma.plugboard.count < 13 else {
                pendingPlug = nil
                toastMessage("The plugboard already has 13 pairs")
                return
            }
            enigma.plugboard.append(PlugboardPair(pending, upper))
            pendingPlug = nil
            scheduleSave()
        } else {
            pendingPlug = upper
        }
    }

    func removePlug(_ pair: PlugboardPair) {
        enigma.plugboard.removeAll { $0 == pair }
        pendingPlug = nil
        scheduleSave()
    }

    func clearPlugboard() {
        enigma.plugboard.removeAll()
        pendingPlug = nil
        scheduleSave()
    }

    func isPlugged(_ letter: Character) -> PlugboardPair? {
        enigma.plugboard.first(where: { $0.first == letter || $0.second == letter })
    }

    // MARK: - Enigma operation

    func pressKey(_ letter: Character) {
        guard !isAnimating else { return }
        guard let machine = try? EnigmaMachine(settings: enigma, positions: presentation.rotorPositions) else {
            toastMessage("The Enigma configuration is invalid.")
            return
        }
        var mutable = machine
        guard let event = try? mutable.process(letter: letter) else {
            toastMessage("The Enigma could not process that key.")
            return
        }
        liveInput.append(event.input)
        liveOutput.append(event.output)
        presentation.rotorPositions = mutable.positions
        presentation.pressedKey = event.input
        presentation.litLamp = event.output
        sound.keyClick()
        let token = UUID()
        flashToken = token
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)
            guard self.flashToken == token else { return }
            self.presentation.pressedKey = nil
            self.presentation.litLamp = nil
        }
    }

    func encodeMessage() {
        guard !isAnimating else { return }
        let normalised = Alphabet.normalize(message)
        guard !normalised.isEmpty else {
            toastMessage("Enter a message containing letters A–Z.")
            return
        }
        guard let machine = try? EnigmaMachine(settings: enigma) else {
            toastMessage("The Enigma configuration is invalid.")
            return
        }
        var mutable = machine
        guard let transcript = try? mutable.process(normalised) else {
            toastMessage("The Enigma could not process this message.")
            return
        }
        output = transcript.output
        liveInput = transcript.normalisedInput
        liveOutput = transcript.output

        guard animatePlayback, transcript.events.count <= 60 else {
            presentation.rotorPositions = transcript.finalPositions
            presentation.pressedKey = nil
            presentation.litLamp = nil
            scheduleSave()
            return
        }

        cancelPlayback()
        let token = UUID()
        playbackToken = token
        isAnimating = true
        presentation.rotorPositions = enigma.initialPositions
        presentation.pressedKey = nil
        presentation.litLamp = nil
        Task { @MainActor in
            for event in transcript.events {
                guard self.playbackToken == token, !Task.isCancelled else { return }
                self.presentation.rotorPositions = event.positionsAfter
                self.presentation.pressedKey = event.input
                self.presentation.litLamp = event.output
                self.sound.keyClick()
                try? await Task.sleep(nanoseconds: 85_000_000)
            }
            guard self.playbackToken == token, !Task.isCancelled else { return }
            self.presentation.pressedKey = nil
            self.presentation.litLamp = nil
            self.presentation.rotorPositions = transcript.finalPositions
            self.playbackToken = nil
            self.isAnimating = false
            self.scheduleSave()
        }
    }

    func copyOutput() {
        let text = output.isEmpty ? liveOutput : output
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        toastMessage("Cipher text copied")
    }

    func copyPlaintext() {
        let text = output.isEmpty ? liveOutput : output
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        toastMessage("Text copied")
    }

    // MARK: - Demo / Bombe

    func loadDemo() {
        let scenario = DemoScenario.weather
        cancelPlayback()
        cancelBombeRun()
        enigma = scenario.settings
        presentation = EnigmaPresentation(settings: scenario.settings)
        message = scenario.plaintext
        output = ""
        liveInput = ""
        liveOutput = ""
        bombe.ciphertext = scenario.ciphertext
        bombe.crib = scenario.crib
        bombe.cribOffset = scenario.cribOffset
        bombe.rotorCandidates = scenario.rotorCandidates
        bombe.ringSettings = scenario.settings.ringSettings
        bombe.reflectorID = scenario.settings.reflectorID
        bombe.language = scenario.language
        bombeResults = []
        bombeSummary = nil
        bombeProgress = 0
        bombeState = .idle
        selectedStopID = nil
        selectedComponent = nil
        mode = .enigma
        requestCamera(.overview)
        toastMessage("Demo loaded — encipher, then send to the Bombe")
        scheduleSave()
    }

    func sendToBombe() {
        cancelPlayback()
        cancelBombeRun()
        let cipher = Alphabet.normalize(output.isEmpty ? message : output)
        guard !cipher.isEmpty else {
            toastMessage("Encipher a message first, then send the ciphertext to the Bombe.")
            return
        }
        bombe.ciphertext = cipher

        let demo = DemoScenario.weather
        let currentCrib = Alphabet.normalize(bombe.crib)
        let currentOffset = max(0, bombe.cribOffset)
        let cribFits = !currentCrib.isEmpty && currentOffset + currentCrib.count <= cipher.count
        var transferNote = "Ciphertext transferred to the Bombe"

        if !cribFits {
            if cipher == demo.ciphertext {
                // The built-in weather ciphertext has a known crib, so the demo
                // can be sent across in one action even if the crib was cleared.
                bombe.crib = demo.crib
                bombe.cribOffset = demo.cribOffset
                bombe.rotorCandidates = demo.rotorCandidates
            } else {
                // Never attach the demo crib to an arbitrary message: it usually
                // does not fit and would make the Bombe fail before it starts.
                bombe.crib = ""
                bombe.cribOffset = 0
                transferNote = "Ciphertext transferred — enter a crib that fits this message"
            }
        }

        bombe.ringSettings = enigma.ringSettings
        bombe.reflectorID = enigma.reflectorID
        bombeResults = []
        bombeSummary = nil
        bombeProgress = 0
        bombeState = .idle
        selectedStopID = nil
        mode = .bombe
        requestCamera(.overview)
        toastMessage(transferNote)
        scheduleSave()
    }

    func runBombe() {
        guard bombeState != .running else { return }
        if let issue = bombe.validationIssue {
            toastMessage(issue, duration: 4.0)
            return
        }
        let query = bombe.query
        let token = UUID()
        bombeRunToken = token
        bombeState = .running
        bombeProgress = 0
        bombeResults = []
        bombeSummary = nil
        selectedStopID = nil
        sound.startMotor()
        let started = Date()
        bombeTask?.cancel()
        bombeSolverTask?.cancel()

        let reportProgress: @Sendable (Double) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard let self,
                      self.bombeRunToken == token,
                      self.bombeState == .running else { return }
                self.bombeProgress = progress
            }
        }
        let solverTask = Task.detached(priority: .userInitiated) { () -> Result<BombeResult, Error> in
            do {
                let result = try BombeSolver.solve(query, progress: reportProgress)
                return .success(result)
            } catch {
                return .failure(error)
            }
        }
        bombeSolverTask = solverTask

        bombeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await solverTask.value

            guard !Task.isCancelled, self.bombeRunToken == token else {
                if self.bombeRunToken == token {
                    self.sound.stopMotor()
                }
                return
            }

            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 2.8 {
                try? await Task.sleep(nanoseconds: UInt64((2.8 - elapsed) * 1_000_000_000))
            }
            guard !Task.isCancelled, self.bombeRunToken == token else {
                if self.bombeRunToken == token {
                    self.sound.stopMotor()
                }
                return
            }
            self.sound.stopMotor()
            switch outcome {
            case .failure(let error):
                self.bombeState = .idle
                // Solver errors are actionable hints, not modal failures. A modal
                // alert would block the header, Demo, and camera controls until
                // the user dismissed it.
                self.toastMessage(error.localizedDescription, duration: 4.0)
                self.sound.stopBell()
            case .success(let result):
                self.bombeSummary = result
                self.bombeResults = result.stops
                self.selectedStopID = result.stops.first?.id
                self.bombeState = .stopped
                self.bombeProgress = 1
                if let topStop = result.stops.first {
                    self.sound.stopBell()
                    let prefix = result.stops.count == 1 ? "Deciphered" : "Top stop deciphered"
                    self.toastMessage(
                        "\(prefix): \(Alphabet.grouped(topStop.decryptedText))",
                        duration: 6.0
                    )
                } else {
                    self.toastMessage("No stops found — check the crib or ring settings")
                }
                self.scheduleSave()
            }
        }
    }

    func stopBombe() {
        cancelBombeRun()
        bombeState = .idle
        bombeProgress = 0
        toastMessage("Bombe stopped")
    }

    private func cancelBombeRun() {
        bombeRunToken = nil
        bombeTask?.cancel()
        bombeSolverTask?.cancel()
        bombeTask = nil
        bombeSolverTask = nil
        sound.stopMotor()
    }

    func apply(stop: BombeStop) {
        cancelPlayback()
        var settings = EnigmaSettings(
            machineType: .m3,
            reflectorID: bombe.reflectorID,
            rotorIDs: stop.rotorOrder,
            ringSettings: stop.ringSettings,
            initialPositions: stop.initialPositions,
            plugboard: stop.plugboard
        )
        settings.plugboard = stop.plugboard
        enigma = settings
        presentation = EnigmaPresentation(settings: settings)
        message = bombe.ciphertext
        output = stop.decryptedText
        liveInput = bombe.ciphertext
        liveOutput = stop.decryptedText
        selectedComponent = nil
        mode = .enigma
        requestCamera(.overview)
        toastMessage("Bombe key applied — plaintext recovered")
        scheduleSave()
    }

    func toggleRotorCandidate(_ id: String) {
        if let index = bombe.rotorCandidates.firstIndex(of: id) {
            guard bombe.rotorCandidates.count > 3 else {
                toastMessage("The Bombe needs at least three rotors")
                return
            }
            bombe.rotorCandidates.remove(at: index)
        } else {
            bombe.rotorCandidates.append(id)
            bombe.rotorCandidates.sort { lhs, rhs in
                let order = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
                return (order.firstIndex(of: lhs) ?? 99) < (order.firstIndex(of: rhs) ?? 99)
            }
        }
        scheduleSave()
    }

    func setBombeRing(at index: Int, to value: Int) {
        guard bombe.ringSettings.indices.contains(index) else { return }
        bombe.ringSettings[index] = ((value % 26) + 26) % 26
        scheduleSave()
    }

    func setBombeReflector(_ id: String) {
        bombe.reflectorID = id
        scheduleSave()
    }

    func setBombeLanguage(_ language: BombeLanguage) {
        bombe.language = language
        scheduleSave()
    }

    func setCribOffset(_ value: Int) {
        let cipherCount = Alphabet.normalize(bombe.ciphertext).count
        let cribCount = Alphabet.normalize(bombe.crib).count
        let maximum = max(0, cipherCount - cribCount)
        bombe.cribOffset = min(max(0, value), maximum)
        scheduleSave()
    }

    // MARK: - UI

    func select(_ component: ComponentSelection?) {
        selectedComponent = component
    }

    func handle(_ intent: SceneIntent) {
        switch intent {
        case .pressKey(let letter):
            pressKey(letter)
        case .plug(let letter):
            togglePlug(letter)
        case .select(let component):
            selectedComponent = component
        case .startBombe:
            runBombe()
        case .stopBombe:
            stopBombe()
        case .camera(let preset):
            requestCamera(preset)
        }
    }

    func requestCamera(_ preset: CameraPreset) {
        cameraRequest = preset
        cameraRequestID = UUID()
    }

    func centerCamera() {
        centerRequestID = UUID()
        toastMessage("View reset to the default isometric view")
    }

    func toastMessage(_ message: String, duration: TimeInterval = 2.4) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled { self.toast = nil }
        }
    }

    func toggleSound() {
        isSoundEnabled.toggle()
        sound.isEnabled = isSoundEnabled
    }

    func scheduleSave() {
        guard hasLoaded else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        let preset = AppPreset(
            name: "Last session",
            enigma: enigma,
            message: message,
            output: output,
            bombeCiphertext: bombe.ciphertext,
            bombeCrib: bombe.crib,
            bombeOffset: bombe.cribOffset
        )
        PresetStore.saveLast(preset)
    }

    func exportTranscript() {
        let panel = NSSavePanel()
        panel.title = "Export transcript"
        panel.nameFieldStringValue = "turing-enigma-transcript.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = """
        TURING ENIGMA
        Machine: \(enigma.machineType.rawValue)
        Rotors: \(enigma.rotorIDs.joined(separator: " "))
        Reflector: \(enigma.reflectorID)
        Rings: \(enigma.ringLetters)
        Windows: \(enigma.windowLetters)
        Plugboard: \(enigma.plugboard.map { "\($0.first)\($0.second)" }.joined(separator: " "))

        Input:
        \(message)

        Output:
        \(output)
        """
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

import Foundation
import TuringEnigmaCore

/// Headless end-to-end check of the demo workflow. It drives the same
/// `AppModel` used by the UI, so the encipher → Bombe → recover loop can be
/// verified without Developer Mode or an attached display.
enum AppFlowSelfTest {
    static func runIfRequested() -> Int32? {
        guard CommandLine.arguments.contains("--flow-check") else { return nil }
        let failures = MainActor.assumeIsolated { check() }
        if failures.isEmpty {
            print("flow check passed: demo enciphered, Bombe solved, key applied")
            return 0
        }
        for failure in failures {
            fputs("flow check: \(failure)\n", stderr)
        }
        return 1
    }

    @MainActor
    private static func check() -> [String] {
        var failures: [String] = []
        let scenario = DemoScenario.weather
        let model = AppModel(loadPersisted: false)
        model.isSoundEnabled = false
        model.sound.isEnabled = false
        model.animatePlayback = false

        // 1. Load the authoritative demo.
        model.loadDemo()
        expect(model.mode == .enigma, "Demo should start in Enigma mode", &failures)
        expect(model.enigma.windowLetters == "EHL", "Demo windows should be EHL, got \(model.enigma.windowLetters)", &failures)
        expect(model.bombe.ciphertext == scenario.ciphertext, "Demo ciphertext missing", &failures)
        expect(model.bombe.crib == scenario.crib, "Demo crib missing", &failures)
        expect(model.bombe.cribOffset == scenario.cribOffset, "Demo crib offset missing", &failures)
        expect(Set(model.bombe.rotorCandidates) == Set(scenario.rotorCandidates), "Demo rotor candidates missing", &failures)

        // The viewport's Center button uses the same re-target request.
        let previousCenterRequest = model.centerRequestID
        model.centerCamera()
        expect(model.centerRequestID != previousCenterRequest, "Center should restart the camera animation", &failures)

        // 2. Encipher without playback so the check stays deterministic.
        model.encodeMessage()
        expect(model.output == scenario.ciphertext, "Enciphered output \(model.output) != \(scenario.ciphertext)", &failures)
        expect(model.liveInput == scenario.plaintext, "Live input was not the demo plaintext", &failures)
        expect(!model.isAnimating, "Playback should be disabled for the flow check", &failures)

        // 3. Hand the ciphertext to the Bombe.
        model.sendToBombe()
        expect(model.mode == .bombe, "Send to Bombe should switch modes", &failures)
        expect(model.bombe.ciphertext == scenario.ciphertext, "Bombe ciphertext was not transferred", &failures)
        expect(model.bombeState == .idle, "Bombe should be idle before the run", &failures)

        // 4. Run the real background solver through the app model.
        model.runBombe()
        guard waitForBombe(model, timeout: 90) else {
            failures.append("Bombe did not stop within 90 seconds")
            return failures
        }
        expect(model.bombeState == .stopped, "Bombe state is \(model.bombeState), expected stopped", &failures)
        expect(!model.bombeResults.isEmpty, "Bombe returned no stops", &failures)
        guard let stop = model.selectedStop else {
            failures.append("Bombe did not select a stop")
            return failures
        }
        expect(stop.rotorOrder == ["III", "II", "I"], "Top stop rotors \(stop.orderLabel) != III · II · I", &failures)
        expect(stop.windowLabel == "EHL", "Top stop windows \(stop.windowLabel) != EHL", &failures)
        let expectedPlugs = Set(["BI", "CH", "EW", "RT"])
        let recoveredPlugs = Set(stop.plugboard.map(\.id))
        expect(expectedPlugs.isSubset(of: recoveredPlugs), "Recovered plugs \(recoveredPlugs) missing demo pairs", &failures)
        expect(stop.decryptedText == scenario.plaintext, "Bombe plaintext \(stop.decryptedText) != \(scenario.plaintext)", &failures)
        let deciphered = Alphabet.grouped(scenario.plaintext)
        expect(
            model.toast?.contains(deciphered) == true,
            "Completion toast should show the deciphered text \(deciphered), got \(model.toast ?? "nil")",
            &failures
        )

        // 5. Apply the recovered key back to the Enigma.
        model.apply(stop: stop)
        expect(model.mode == .enigma, "Apply should return to Enigma mode", &failures)
        expect(model.enigma.rotorIDs == stop.rotorOrder, "Applied rotor order does not match the stop", &failures)
        expect(model.enigma.windowLetters == stop.windowLabel, "Applied windows do not match the stop", &failures)
        expect(model.output == scenario.plaintext, "Recovered plaintext \(model.output) != \(scenario.plaintext)", &failures)
        expect(model.message == scenario.ciphertext, "Recovered message should show the ciphertext", &failures)

        // 6. A custom short message must never inherit the 13-letter demo crib.
        // This was the cause of "The crib extends beyond the ciphertext" after
        // enciphering a short message and sending it to the Bombe.
        let custom = AppModel(loadPersisted: false)
        custom.isSoundEnabled = false
        custom.sound.isEnabled = false
        custom.animatePlayback = false
        custom.message = "HELLOWORLD"
        custom.encodeMessage()
        expect(custom.output.count == 10, "Custom test message should encipher to 10 letters", &failures)
        custom.sendToBombe()
        expect(custom.bombe.ciphertext == custom.output, "Custom ciphertext was not transferred", &failures)
        expect(custom.bombe.crib.isEmpty, "Custom ciphertext should not inherit the demo crib, got \(custom.bombe.crib)", &failures)
        expect(custom.bombe.validationIssue != nil, "Short custom ciphertext should require a crib", &failures)
        custom.runBombe()
        expect(custom.bombeState == .idle, "Invalid Bombe input should not start a run", &failures)
        expect(custom.toast != nil, "Invalid Bombe input should show a non-blocking hint", &failures)

        // A fitting custom crib is preserved and its offset is clamped.
        custom.bombe.crib = "HELLO"
        custom.setCribOffset(99)
        expect(custom.bombe.cribOffset == 5, "Crib offset should clamp to the end of the ciphertext, got \(custom.bombe.cribOffset)", &failures)
        expect(custom.bombe.validationIssue == nil, "A fitting custom crib should validate", &failures)

        return failures
    }

    @MainActor
    private static func waitForBombe(_ model: AppModel, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while model.bombeState == .running, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        // Let any final state/progress updates drain before the caller asserts.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        return model.bombeState != .running
    }

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String, _ failures: inout [String]) {
        if !condition {
            failures.append(message())
        }
    }
}

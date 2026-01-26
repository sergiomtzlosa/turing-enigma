import XCTest
@testable import TuringEnigmaCore

final class EnigmaMachineTests: XCTestCase {
    func testClassicAAAAAVector() throws {
        let settings = EnigmaSettings(
            machineType: .m3,
            reflectorID: "B",
            rotorIDs: ["I", "II", "III"],
            ringSettings: [0, 0, 0],
            initialPositions: [0, 0, 0],
            plugboard: []
        )
        let output = try EnigmaMachine.encrypt("AAAAA", settings: settings)
        XCTAssertEqual(output, "BDZGO")
    }

    func testReciprocalDecryption() throws {
        let settings = EnigmaSettings(
            machineType: .m3,
            reflectorID: "B",
            rotorIDs: ["IV", "II", "V"],
            ringSettings: [3, 7, 11],
            initialPositions: [12, 4, 20],
            plugboard: [PlugboardPair("A", "M"), PlugboardPair("F", "I"), PlugboardPair("N", "V")]
        )
        let ciphertext = try EnigmaMachine.encrypt("HELLO WORLD", settings: settings)
        let plaintext = try EnigmaMachine.decrypt(ciphertext, settings: settings)
        XCTAssertEqual(plaintext, "HELLOWORLD")
    }

    func testDoubleStepSequence() throws {
        let settings = EnigmaSettings(
            machineType: .m3,
            reflectorID: "B",
            rotorIDs: ["I", "II", "III"],
            ringSettings: [0, 0, 0],
            initialPositions: [0, 3, 20],
            plugboard: []
        )
        var machine = try EnigmaMachine(settings: settings)
        _ = try machine.process(letter: "A")
        XCTAssertEqual(machine.positions, [0, 3, 21])
        _ = try machine.process(letter: "A")
        XCTAssertEqual(machine.positions, [0, 4, 22])
        _ = try machine.process(letter: "A")
        XCTAssertEqual(machine.positions, [1, 5, 23])
    }

    func testDemoCiphertextAndDecryption() throws {
        let scenario = DemoScenario.weather
        let encrypted = try EnigmaMachine.encrypt(scenario.plaintext, settings: scenario.settings)
        XCTAssertEqual(encrypted, scenario.ciphertext)
        let decrypted = try EnigmaMachine.decrypt(scenario.ciphertext, settings: scenario.settings)
        XCTAssertEqual(decrypted, scenario.plaintext)
    }

    func testM4Configuration() throws {
        let settings = EnigmaSettings(
            machineType: .m4,
            reflectorID: "Thin B",
            rotorIDs: ["Beta", "I", "II", "III"],
            ringSettings: [0, 0, 0, 0],
            initialPositions: [0, 0, 0, 0],
            plugboard: []
        )
        let ciphertext = try EnigmaMachine.encrypt("AAAAA", settings: settings)
        XCTAssertEqual(ciphertext.count, 5)
        let plaintext = try EnigmaMachine.decrypt(ciphertext, settings: settings)
        XCTAssertEqual(plaintext, "AAAAA")
    }

    func testValidationRejectsDuplicateRotor() {
        var settings = EnigmaSettings.standard
        settings.rotorIDs = ["I", "I", "III"]
        XCTAssertFalse(settings.validationIssues().isEmpty)
    }

    func testPlugboardNormalisation() throws {
        let settings = EnigmaSettings(
            machineType: .m3,
            reflectorID: "B",
            rotorIDs: ["I", "II", "III"],
            ringSettings: [0, 0, 0],
            initialPositions: [0, 0, 0],
            plugboard: [PlugboardPair("Z", "A"), PlugboardPair("M", "B")]
        )
        let map = settings.plugboardMap
        XCTAssertEqual(map[Alphabet.index(of: "A")!], Alphabet.index(of: "Z")!)
        XCTAssertEqual(map[Alphabet.index(of: "Z")!], Alphabet.index(of: "A")!)
    }
}

final class BombeSolverTests: XCTestCase {
    func testMenuLoopCount() throws {
        let menu = try Menu(
            crib: "WETTERBERICHT",
            ciphertext: "GQGYWTWGVYZBD",
            offset: 0
        )
        XCTAssertGreaterThan(menu.loopCount, 0)
        XCTAssertEqual(menu.edges.count, 13)
    }

    func testSelfEncryptionIsRejected() {
        XCTAssertThrowsError(try Menu(crib: "ABC", ciphertext: "AXC", offset: 0)) { error in
            guard case BombeError.selfEncryption = error else {
                return XCTFail("Expected selfEncryption, got \(error)")
            }
        }
    }

    func testBombeFindsDemoStop() throws {
        let scenario = DemoScenario.weather
        let result = try BombeSolver.solve(scenario.bombeQuery)
        XCTAssertFalse(result.stops.isEmpty, "Bombe returned no stops")
        guard let trueStop = result.stops.first(where: {
            $0.rotorOrder == ["III", "II", "I"] &&
            $0.initialPositions == [4, 7, 11]
        }) else {
            return XCTFail("Expected demo stop III II I / EHL. Stops: \(result.stops.map { "\($0.orderLabel) \($0.windowLabel)" })")
        }
        let expectedPairs = Set(["BI", "CH", "EW", "RT"])
        let actualPairs = Set(trueStop.plugboard.map { $0.id })
        XCTAssertTrue(expectedPairs.isSubset(of: actualPairs), "Recovered \(actualPairs)")
        XCTAssertEqual(trueStop.decryptedText, scenario.plaintext)
        XCTAssertEqual(result.stops.first?.id, trueStop.id, "The true stop should rank first")
    }

    func testBombeCanBeRestrictedToKnownOrder() throws {
        let scenario = DemoScenario.weather
        var query = scenario.bombeQuery
        query.allowedRotorOrders = [["III", "II", "I"]]
        let result = try BombeSolver.solve(query)
        XCTAssertEqual(result.candidatesSearched, 17_576)
        XCTAssertEqual(result.stops.first?.rotorOrder, ["III", "II", "I"])
    }

    func testLanguageScorerPrefersPlaintext() {
        let plain = "WETTERBERICHTFUERDIENACHT"
        let random = "QXJZKVBPWMFHYTRLNSDAGCIEUO"
        let plainScore = LanguageScorer.score(plain, language: .german)
        let randomScore = LanguageScorer.score(random, language: .german)
        XCTAssertGreaterThan(plainScore, randomScore)
    }

    func testInvalidReflectorRejected() {
        let query = BombeQuery(
            ciphertext: "ABCDEF",
            crib: "ABC",
            reflectorID: "Thin B"
        )
        XCTAssertThrowsError(try BombeSolver.solve(query))
    }

    func testBombeCancellationStopsTheSearch() async throws {
        let query = DemoScenario.weather.bombeQuery
        let task = Task.detached(priority: .userInitiated) {
            try BombeSolver.solve(query)
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled Bombe search should not return a result")
        } catch let error as BombeError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("Expected BombeError.cancelled, got \(error)")
        }
    }
}

final class PersistenceTests: XCTestCase {
    func testPresetRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preset = AppPreset(
            name: "Test",
            enigma: .demoSecret(),
            message: "HELLO",
            output: "WORLD",
            bombeCiphertext: "ABC",
            bombeCrib: "A",
            bombeOffset: 0
        )
        PresetStore.saveLast(preset, to: directory)
        let loaded = PresetStore.loadLast(from: directory)
        XCTAssertEqual(loaded?.name, "Test")
        XCTAssertEqual(loaded?.enigma, preset.enigma)
        XCTAssertEqual(loaded?.updatedAt.timeIntervalSince1970 ?? 0, preset.updatedAt.timeIntervalSince1970, accuracy: 1)
        try? FileManager.default.removeItem(at: directory)
    }
}

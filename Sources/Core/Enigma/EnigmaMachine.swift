import Foundation

public struct EnigmaKeyEvent: Sendable, Identifiable {
    public let id: UUID
    public let input: Character
    public let output: Character
    public let positionsBefore: [Int]
    public let positionsAfter: [Int]
    public let rotorOrder: [String]
    public let ringSettings: [Int]

    public init(
        id: UUID = UUID(),
        input: Character,
        output: Character,
        positionsBefore: [Int],
        positionsAfter: [Int],
        rotorOrder: [String],
        ringSettings: [Int]
    ) {
        self.id = id
        self.input = input
        self.output = output
        self.positionsBefore = positionsBefore
        self.positionsAfter = positionsAfter
        self.rotorOrder = rotorOrder
        self.ringSettings = ringSettings
    }
}

public struct EnigmaTranscript: Sendable {
    public let originalText: String
    public let normalisedInput: String
    public let output: String
    public let events: [EnigmaKeyEvent]
    public let finalPositions: [Int]
    public let settings: EnigmaSettings

    public init(
        originalText: String,
        normalisedInput: String,
        output: String,
        events: [EnigmaKeyEvent],
        finalPositions: [Int],
        settings: EnigmaSettings
    ) {
        self.originalText = originalText
        self.normalisedInput = normalisedInput
        self.output = output
        self.events = events
        self.finalPositions = finalPositions
        self.settings = settings
    }
}

/// Pure rotor/reflector stepping and transformation logic shared by the
/// Enigma simulator and the Bombe search. No plugboard is applied here.
struct RotorBank {
    let rotors: [RotorSpec]
    let reflector: ReflectorSpec
    let rings: [Int]
    var positions: [Int]

    init(rotors: [RotorSpec], reflector: ReflectorSpec, rings: [Int], positions: [Int]) {
        self.rotors = rotors
        self.reflector = reflector
        self.rings = rings
        self.positions = positions
    }

    mutating func step() {
        guard rotors.count >= 3 else { return }
        let right = rotors.count - 1
        let middle = rotors.count - 2
        let left = rotors.count - 3

        let middleAtNotch = rotors[middle].notches.contains(modulo(positions[middle] - rings[middle], 26))
        let rightAtNotch = rotors[right].notches.contains(modulo(positions[right] - rings[right], 26))

        if middleAtNotch {
            positions[middle] = modulo(positions[middle] + 1, 26)
            positions[left] = modulo(positions[left] + 1, 26)
        } else if rightAtNotch {
            positions[middle] = modulo(positions[middle] + 1, 26)
        }
        positions[right] = modulo(positions[right] + 1, 26)
    }

    func transform(_ letter: Int) -> Int {
        var value = letter
        for index in stride(from: rotors.count - 1, through: 0, by: -1) {
            value = forward(value, rotor: rotors[index], position: positions[index], ring: rings[index])
        }
        value = reflector.wiring[value]
        for index in 0..<rotors.count {
            value = backward(value, rotor: rotors[index], position: positions[index], ring: rings[index])
        }
        return value
    }

    private func forward(_ letter: Int, rotor: RotorSpec, position: Int, ring: Int) -> Int {
        let offset = modulo(position - ring, 26)
        return modulo(rotor.wiring[modulo(letter + offset, 26)] - offset, 26)
    }

    private func backward(_ letter: Int, rotor: RotorSpec, position: Int, ring: Int) -> Int {
        let offset = modulo(position - ring, 26)
        return modulo(rotor.inverseWiring[modulo(letter + offset, 26)] - offset, 26)
    }
}

public struct EnigmaMachine {
    public let settings: EnigmaSettings
    public private(set) var positions: [Int]
    private var bank: RotorBank
    private let plugboard: [Int]

    public init(settings: EnigmaSettings, positions overridePositions: [Int]? = nil) throws {
        let validated = try settings.validated()
        let rotors = try validated.rotorIDs.map { id -> RotorSpec in
            guard let rotor = RotorSpec.named(id) else {
                throw EnigmaError.invalidConfiguration("Unknown rotor \(id).")
            }
            return rotor
        }
        guard let reflector = ReflectorSpec.named(validated.reflectorID) else {
            throw EnigmaError.invalidConfiguration("Unknown reflector \(validated.reflectorID).")
        }
        let start = overridePositions ?? validated.initialPositions
        guard start.count == rotors.count else {
            throw EnigmaError.invalidConfiguration("Window settings do not match the rotor count.")
        }
        self.settings = validated
        self.positions = start
        self.bank = RotorBank(rotors: rotors, reflector: reflector, rings: validated.ringSettings, positions: start)
        self.plugboard = validated.plugboardMap
    }

    public mutating func step() {
        bank.step()
        positions = bank.positions
    }

    /// Advances the rotors without sending a signal. Useful for reaching a
    /// crib offset when solving.
    public mutating func advanceRotors(_ count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count { step() }
    }

    /// The rotor/reflector permutation without the plugboard, for the current state.
    public func rotorTransform(_ letter: Int) -> Int {
        bank.transform(modulo(letter, 26))
    }

    public mutating func process(letter: Character) throws -> EnigmaKeyEvent {
        guard let inputIndex = Alphabet.index(of: letter) else {
            throw EnigmaError.invalidLetter(letter)
        }
        let before = positions
        step()
        var value = plugboard[inputIndex]
        value = bank.transform(value)
        value = plugboard[value]
        let output = Alphabet.letter(at: value)
        return EnigmaKeyEvent(
            input: Alphabet.letter(at: inputIndex),
            output: output,
            positionsBefore: before,
            positionsAfter: positions,
            rotorOrder: settings.rotorIDs,
            ringSettings: settings.ringSettings
        )
    }

    public mutating func process(_ text: String) throws -> EnigmaTranscript {
        let normalised = Alphabet.normalize(text)
        var output = ""
        var events: [EnigmaKeyEvent] = []
        output.reserveCapacity(normalised.count)
        events.reserveCapacity(normalised.count)
        for character in normalised {
            let event = try process(letter: character)
            output.append(event.output)
            events.append(event)
        }
        return EnigmaTranscript(
            originalText: text,
            normalisedInput: normalised,
            output: output,
            events: events,
            finalPositions: positions,
            settings: settings
        )
    }

    public static func encrypt(_ text: String, settings: EnigmaSettings) throws -> String {
        var machine = try EnigmaMachine(settings: settings)
        return try machine.process(text).output
    }

    public static func decrypt(_ text: String, settings: EnigmaSettings) throws -> String {
        try encrypt(text, settings: settings)
    }
}

@inline(__always)
func modulo(_ value: Int, _ modulus: Int) -> Int {
    let remainder = value % modulus
    return remainder >= 0 ? remainder : remainder + modulus
}

import Foundation

public enum EnigmaMachineType: String, Codable, CaseIterable, Identifiable, Sendable {
    case enigmaI = "Enigma I"
    case m3 = "M3"
    case m4 = "M4"

    public var id: String { rawValue }

    public var rotorCount: Int { self == .m4 ? 4 : 3 }

    public var availableRotorIDs: [String] {
        switch self {
        case .enigmaI: return ["I", "II", "III", "IV", "V"]
        case .m3: return ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
        case .m4: return ["Beta", "Gamma", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
        }
    }

    public var availableReflectorIDs: [String] {
        self == .m4 ? ["Thin B", "Thin C"] : ["B", "C"]
    }

    public var defaultRotorIDs: [String] {
        self == .m4 ? ["Beta", "I", "II", "III"] : ["I", "II", "III"]
    }

    public var defaultReflectorID: String {
        self == .m4 ? "Thin B" : "B"
    }

    public var shortName: String {
        switch self {
        case .enigmaI: return "ENIGMA I"
        case .m3: return "ENIGMA M3"
        case .m4: return "ENIGMA M4"
        }
    }

    public var usesGreekRotor: Bool { self == .m4 }
}

public struct RotorSpec: Identifiable, Hashable, Sendable {
    public let id: String
    public let wiring: [Int]
    public let inverseWiring: [Int]
    public let notches: Set<Int>

    public init(id: String, wiring: String, notchLetters: String) {
        self.id = id
        let characters = Array(wiring)
        precondition(characters.count == 26, "Rotor wiring must contain 26 letters")
        let map = characters.compactMap { Alphabet.index(of: $0) }
        self.wiring = map
        var inverse = Array(repeating: 0, count: 26)
        for (index, value) in map.enumerated() { inverse[value] = index }
        self.inverseWiring = inverse
        self.notches = Set(notchLetters.compactMap { Alphabet.index(of: $0) })
    }

    public var notchLetters: String {
        notches.sorted().map { String(Alphabet.letter(at: $0)) }.joined()
    }

    public static let all: [RotorSpec] = [
        RotorSpec(id: "I", wiring: "EKMFLGDQVZNTOWYHXUSPAIBRCJ", notchLetters: "Q"),
        RotorSpec(id: "II", wiring: "AJDKSIRUXBLHWTMCQGZNPYFVOE", notchLetters: "E"),
        RotorSpec(id: "III", wiring: "BDFHJLCPRTXVZNYEIWGAKMUSQO", notchLetters: "V"),
        RotorSpec(id: "IV", wiring: "ESOVPZJAYQUIRHXLNFTGKDCMWB", notchLetters: "J"),
        RotorSpec(id: "V", wiring: "VZBRGITYUPSDNHLXAWMJQOFECK", notchLetters: "Z"),
        RotorSpec(id: "VI", wiring: "JPGVOUMFYQBENHZRDKASXLICTW", notchLetters: "ZM"),
        RotorSpec(id: "VII", wiring: "NZJHGRCXMYSWBOUFAIVLPEKQDT", notchLetters: "ZM"),
        RotorSpec(id: "VIII", wiring: "FKQHTLXOCBJSPDZRAMEWNIUYGV", notchLetters: "ZM"),
        RotorSpec(id: "Beta", wiring: "LEYJVCNIXWPBQMDRTAKZGFUHOS", notchLetters: ""),
        RotorSpec(id: "Gamma", wiring: "FSOKANUERHMBTIYCWLQPZXVGJD", notchLetters: "")
    ]

    public static let byID: [String: RotorSpec] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func named(_ id: String) -> RotorSpec? { byID[id] }
}

public struct ReflectorSpec: Identifiable, Hashable, Sendable {
    public let id: String
    public let wiring: [Int]

    public init(id: String, wiring: String) {
        self.id = id
        let characters = Array(wiring)
        precondition(characters.count == 26, "Reflector wiring must contain 26 letters")
        self.wiring = characters.compactMap { Alphabet.index(of: $0) }
    }

    public static let all: [ReflectorSpec] = [
        ReflectorSpec(id: "B", wiring: "YRUHQSLDPXNGOKMIEBFZCWVJAT"),
        ReflectorSpec(id: "C", wiring: "FVPJIAOYEDRZXWGCTKUQSBNMHL"),
        ReflectorSpec(id: "Thin B", wiring: "ENKQAUYWJICOPBLMDXZVFTHRGS"),
        ReflectorSpec(id: "Thin C", wiring: "RDOBJNTKVEHMLFCWZAXGYIPSUQ")
    ]

    public static let byID: [String: ReflectorSpec] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func named(_ id: String) -> ReflectorSpec? { byID[id] }
}

public struct PlugboardPair: Codable, Hashable, Sendable, Identifiable {
    public var first: Character
    public var second: Character

    public init(_ first: Character, _ second: Character) {
        self.first = first
        self.second = second
    }

    private enum CodingKeys: String, CodingKey {
        case first
        case second
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let a = try container.decode(String.self, forKey: .first)
        let b = try container.decode(String.self, forKey: .second)
        guard let first = a.first, let second = b.first else {
            throw DecodingError.dataCorruptedError(forKey: .first, in: container, debugDescription: "Plugboard letters must be single characters.")
        }
        self.first = first
        self.second = second
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(first), forKey: .first)
        try container.encode(String(second), forKey: .second)
    }

    public var id: String {
        let a = String(first), b = String(second)
        return a < b ? a + b : b + a
    }

    public var letters: (Character, Character) { (first, second) }
}

public struct EnigmaSettings: Codable, Equatable, Sendable {
    public var machineType: EnigmaMachineType
    public var reflectorID: String
    public var rotorIDs: [String]
    public var ringSettings: [Int]
    public var initialPositions: [Int]
    public var plugboard: [PlugboardPair]

    public init(
        machineType: EnigmaMachineType = .m3,
        reflectorID: String = "B",
        rotorIDs: [String] = ["I", "II", "III"],
        ringSettings: [Int] = [0, 0, 0],
        initialPositions: [Int] = [0, 0, 0],
        plugboard: [PlugboardPair] = []
    ) {
        self.machineType = machineType
        self.reflectorID = reflectorID
        self.rotorIDs = rotorIDs
        self.ringSettings = ringSettings
        self.initialPositions = initialPositions
        self.plugboard = plugboard
    }

    public static var standard: EnigmaSettings { EnigmaSettings() }

    public static func demoSecret() -> EnigmaSettings {
        EnigmaSettings(
            machineType: .m3,
            reflectorID: "B",
            rotorIDs: ["III", "II", "I"],
            ringSettings: [0, 0, 0],
            initialPositions: [4, 7, 11],
            plugboard: [
                PlugboardPair("W", "E"),
                PlugboardPair("T", "R"),
                PlugboardPair("B", "I"),
                PlugboardPair("C", "H")
            ]
        )
    }

    public var normalizedPlugboard: [PlugboardPair] {
        plugboard.map { pair in
            let a = Character(String(pair.first).uppercased())
            let b = Character(String(pair.second).uppercased())
            return a < b ? PlugboardPair(a, b) : PlugboardPair(b, a)
        }.sorted { $0.id < $1.id }
    }

    public var plugboardMap: [Int] {
        var map = Array(0..<26)
        for pair in normalizedPlugboard {
            guard let a = Alphabet.index(of: pair.first),
                  let b = Alphabet.index(of: pair.second),
                  a != b else { continue }
            map[a] = b
            map[b] = a
        }
        return map
    }

    public var windowLetters: String {
        String(initialPositions.map { Alphabet.letter(at: $0) })
    }

    public var ringLetters: String {
        String(ringSettings.map { Alphabet.letter(at: $0) })
    }

    public mutating func changeMachineType(to type: EnigmaMachineType, preservingPlugboard: Bool = true) {
        let oldPlugs = preservingPlugboard ? plugboard : []
        machineType = type
        rotorIDs = type.defaultRotorIDs
        reflectorID = type.defaultReflectorID
        ringSettings = Array(repeating: 0, count: type.rotorCount)
        initialPositions = Array(repeating: 0, count: type.rotorCount)
        plugboard = oldPlugs
    }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        let expected = machineType.rotorCount
        if rotorIDs.count != expected {
            issues.append("Expected \(expected) rotors, found \(rotorIDs.count).")
        }
        if ringSettings.count != expected || initialPositions.count != expected {
            issues.append("Rotor settings do not match the machine's rotor count.")
        }
        for id in rotorIDs {
            guard let rotor = RotorSpec.named(id) else {
                issues.append("Unknown rotor \(id).")
                continue
            }
            if !machineType.availableRotorIDs.contains(id) {
                issues.append("Rotor \(rotor.id) is not available for \(machineType.rawValue).")
            }
        }
        if machineType == .m4 {
            if !["Beta", "Gamma"].contains(rotorIDs.first ?? "") {
                issues.append("M4 requires Beta or Gamma as the leftmost rotor.")
            }
        }
        if !machineType.availableReflectorIDs.contains(reflectorID) {
            issues.append("Reflector \(reflectorID) is not available for \(machineType.rawValue).")
        }
        if Set(rotorIDs).count != rotorIDs.count {
            issues.append("Rotor order contains duplicates.")
        }
        if ringSettings.contains(where: { !(0..<26).contains($0) }) ||
            initialPositions.contains(where: { !(0..<26).contains($0) }) {
            issues.append("Ring and window settings must be A–Z.")
        }
        var used: Set<Character> = []
        for pair in plugboard {
            let a = Character(String(pair.first).uppercased())
            let b = Character(String(pair.second).uppercased())
            if Alphabet.index(of: a) == nil || Alphabet.index(of: b) == nil {
                issues.append("Plugboard contains a non-letter.")
            }
            if a == b {
                issues.append("A letter cannot be plugged to itself.")
            }
            if used.contains(a) || used.contains(b) {
                issues.append("A plugboard letter is used more than once.")
            }
            used.insert(a)
            used.insert(b)
        }
        if plugboard.count > 13 {
            issues.append("The plugboard supports at most 13 pairs.")
        }
        return issues
    }

    public func validated() throws -> EnigmaSettings {
        let issues = validationIssues()
        guard issues.isEmpty else {
            throw EnigmaError.invalidConfiguration(issues.joined(separator: " "))
        }
        return self
    }
}

public enum EnigmaError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case invalidLetter(Character)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): return message
        case .invalidLetter(let character): return "Invalid Enigma letter: \(character)"
        }
    }
}

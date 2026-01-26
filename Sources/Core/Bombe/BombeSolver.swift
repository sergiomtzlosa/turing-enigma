import Foundation

public struct BombeQuery: Sendable {
    public var ciphertext: String
    public var crib: String
    public var cribOffset: Int
    public var rotorCandidates: [String]
    public var ringSettings: [Int]
    public var reflectorID: String
    public var knownPlugboard: [PlugboardPair]
    public var language: BombeLanguage
    public var maxResults: Int
    /// Optional test/debug hook. When present, only these rotor orders are searched.
    public var allowedRotorOrders: [[String]]?

    public init(
        ciphertext: String,
        crib: String,
        cribOffset: Int = 0,
        rotorCandidates: [String] = ["I", "II", "III"],
        ringSettings: [Int] = [0, 0, 0],
        reflectorID: String = "B",
        knownPlugboard: [PlugboardPair] = [],
        language: BombeLanguage = .german,
        maxResults: Int = 24,
        allowedRotorOrders: [[String]]? = nil
    ) {
        self.ciphertext = ciphertext
        self.crib = crib
        self.cribOffset = cribOffset
        self.rotorCandidates = rotorCandidates
        self.ringSettings = ringSettings
        self.reflectorID = reflectorID
        self.knownPlugboard = knownPlugboard
        self.language = language
        self.maxResults = maxResults
        self.allowedRotorOrders = allowedRotorOrders
    }
}

public struct BombeStop: Identifiable, Sendable {
    public let id: UUID
    public let rotorOrder: [String]
    public let ringSettings: [Int]
    public let initialPositions: [Int]
    public let cribPositions: [Int]
    public let plugboard: [PlugboardPair]
    public let plugboardMap: [Int]
    public let hypothesis: Character
    public let decryptedText: String
    public let languageScore: Double
    public let confidence: Double
    public let loopCount: Int

    public init(
        id: UUID = UUID(),
        rotorOrder: [String],
        ringSettings: [Int],
        initialPositions: [Int],
        cribPositions: [Int],
        plugboard: [PlugboardPair],
        plugboardMap: [Int],
        hypothesis: Character,
        decryptedText: String,
        languageScore: Double,
        confidence: Double,
        loopCount: Int
    ) {
        self.id = id
        self.rotorOrder = rotorOrder
        self.ringSettings = ringSettings
        self.initialPositions = initialPositions
        self.cribPositions = cribPositions
        self.plugboard = plugboard
        self.plugboardMap = plugboardMap
        self.hypothesis = hypothesis
        self.decryptedText = decryptedText
        self.languageScore = languageScore
        self.confidence = confidence
        self.loopCount = loopCount
    }

    public var orderLabel: String { rotorOrder.joined(separator: " · ") }
    public var windowLabel: String { String(initialPositions.map { Alphabet.letter(at: $0) }) }
    public var plugboardLabel: String {
        plugboard.isEmpty ? "No plugs recovered" : plugboard.map { "\($0.first)\($0.second)" }.joined(separator: "  ")
    }
}

public struct BombeResult: Sendable {
    public let stops: [BombeStop]
    public let menu: Menu
    public let candidatesSearched: Int
    public let totalCandidates: Int
    public let elapsed: TimeInterval
    public let normalisedCiphertext: String
    public let normalisedCrib: String
    public let query: BombeQuery

    public var best: BombeStop? { stops.first }
}

public enum BombeSolver {
    public static func solve(
        _ query: BombeQuery,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> BombeResult {
        let started = Date()
        let cipher = Alphabet.normalize(query.ciphertext)
        let crib = Alphabet.normalize(query.crib)
        guard !cipher.isEmpty else { throw BombeError.emptyCiphertext }
        guard !crib.isEmpty else { throw BombeError.emptyCrib }
        guard query.ringSettings.count == 3,
              query.ringSettings.allSatisfy({ (0..<26).contains($0) }) else {
            throw BombeError.invalidRingSettings
        }
        guard ["B", "C"].contains(query.reflectorID) else {
            throw BombeError.unsupportedReflector(query.reflectorID)
        }
        guard let reflector = ReflectorSpec.named(query.reflectorID) else {
            throw BombeError.unsupportedReflector(query.reflectorID)
        }

        let menu = try Menu(crib: crib, ciphertext: cipher, offset: query.cribOffset)
        let candidates = Array(Set(query.rotorCandidates)).sorted()
        guard candidates.count >= 3 else {
            throw BombeError.invalidRotors("Select at least three rotors for the Bombe.")
        }
        if candidates.contains(where: { ["Beta", "Gamma"].contains($0) }) {
            throw BombeError.invalidRotors("The 3-rotor Bombe cannot use the M4 Greek rotors.")
        }
        let specs = try candidates.map { id -> RotorSpec in
            guard let spec = RotorSpec.named(id), !["Beta", "Gamma"].contains(id) else {
                throw BombeError.invalidRotors("Unknown rotor \(id).")
            }
            return spec
        }
        let specByID = Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0) })

        let knownMap = try makeKnownMap(query.knownPlugboard)

        let orders: [[String]]
        if let allowed = query.allowedRotorOrders, !allowed.isEmpty {
            orders = allowed
        } else {
            orders = permutations(of: candidates, choose: 3)
        }
        guard !orders.isEmpty else {
            throw BombeError.invalidRotors("No rotor orders to search.")
        }

        let totalCandidates = orders.count * 17_576
        var searched = 0
        var rawStops: [BombeStop] = []
        var seenStops: Set<String> = []
        let menuComponents = menu.componentLetters

        progress?(0)

        for order in orders {
            guard order.count == 3 else {
                throw BombeError.invalidRotors("Each rotor order must contain exactly three rotors.")
            }
            guard Set(order).isSubset(of: Set(candidates)) else {
                throw BombeError.invalidRotors("A rotor order contains a rotor that is not in the selected set.")
            }
            let rotors = try order.map { id -> RotorSpec in
                guard let spec = specByID[id] else {
                    throw BombeError.invalidRotors("Unknown rotor \(id) in order.")
                }
                return spec
            }

            for first in 0..<26 {
                for second in 0..<26 {
                    for third in 0..<26 {
                        if searched % 128 == 0 {
                            if Task.isCancelled { throw BombeError.cancelled }
                            progress?(Double(searched) / Double(totalCandidates))
                        }
                        searched += 1

                        let start = [first, second, third]
                        var bank = RotorBank(rotors: rotors, reflector: reflector, rings: query.ringSettings, positions: start)
                        for _ in 0..<query.cribOffset { bank.step() }
                        let cribStart = bank.positions

                        var edgeData: [(plain: Int, cipher: Int, r: [Int], rinv: [Int])] = []
                        edgeData.reserveCapacity(menu.edges.count)
                        for edge in menu.edges {
                            bank.step()
                            var r = [Int](repeating: 0, count: 26)
                            for letter in 0..<26 { r[letter] = bank.transform(letter) }
                            var rinv = [Int](repeating: 0, count: 26)
                            for letter in 0..<26 { rinv[r[letter]] = letter }
                            edgeData.append((edge.plain, edge.cipher, r, rinv))
                        }

                        let solutions = plugboardSolutions(
                            edges: edgeData,
                            components: menuComponents,
                            known: knownMap,
                            limit: 32
                        )
                        if solutions.isEmpty { continue }

                        for solution in solutions {
                            let key = stopKey(order: order, positions: start, state: solution)
                            if seenStops.contains(key) { continue }

                            var pairs: [PlugboardPair] = []
                            for letter in 0..<26 {
                                let partner = solution[letter]
                                if partner > letter {
                                    pairs.append(PlugboardPair(
                                        Alphabet.letter(at: letter),
                                        Alphabet.letter(at: partner)
                                    ))
                                }
                            }
                            pairs.sort { $0.id < $1.id }

                            let settings = EnigmaSettings(
                                machineType: .m3,
                                reflectorID: query.reflectorID,
                                rotorIDs: order,
                                ringSettings: query.ringSettings,
                                initialPositions: start,
                                plugboard: pairs
                            )
                            guard let machine = try? EnigmaMachine(settings: settings) else { continue }
                            var machineCopy = machine
                            guard let transcript = try? machineCopy.process(cipher) else { continue }
                            let offset = query.cribOffset
                            guard transcript.output.count >= offset + crib.count else { continue }
                            let startIndex = transcript.output.index(transcript.output.startIndex, offsetBy: offset)
                            let endIndex = transcript.output.index(startIndex, offsetBy: crib.count)
                            let cribResult = String(transcript.output[startIndex..<endIndex])
                            guard cribResult == crib else { continue }

                            let score = LanguageScorer.score(transcript.output, language: query.language)
                            let hypothesisLetter: Character = {
                                guard let firstEdge = menu.edges.first else { return "A" }
                                return Alphabet.letter(at: solution[firstEdge.plain])
                            }()
                            let stop = BombeStop(
                                rotorOrder: order,
                                ringSettings: query.ringSettings,
                                initialPositions: start,
                                cribPositions: cribStart,
                                plugboard: pairs,
                                plugboardMap: solution,
                                hypothesis: hypothesisLetter,
                                decryptedText: transcript.output,
                                languageScore: score,
                                confidence: LanguageScorer.confidence(for: score),
                                loopCount: menu.loopCount
                            )
                            rawStops.append(stop)
                            seenStops.insert(key)
                            if rawStops.count >= 500 { break }
                        }
                        if rawStops.count >= 500 { break }
                    }
                    if rawStops.count >= 500 { break }
                }
                if rawStops.count >= 500 { break }
            }
            if rawStops.count >= 500 { break }
        }

        let ranked = rawStops.sorted {
            if abs($0.languageScore - $1.languageScore) > 0.0001 {
                return $0.languageScore > $1.languageScore
            }
            if $0.rotorOrder != $1.rotorOrder { return $0.rotorOrder.joined() < $1.rotorOrder.joined() }
            return $0.initialPositions.lexicographicallyPrecedes($1.initialPositions)
        }
        progress?(1)
        return BombeResult(
            stops: Array(ranked.prefix(max(1, query.maxResults))),
            menu: menu,
            candidatesSearched: searched,
            totalCandidates: totalCandidates,
            elapsed: Date().timeIntervalSince(started),
            normalisedCiphertext: cipher,
            normalisedCrib: crib,
            query: query
        )
    }

    private static func makeKnownMap(_ pairs: [PlugboardPair]) throws -> [Int] {
        var map = Array(repeating: -1, count: 26)
        var used: Set<Int> = []
        for pair in pairs {
            guard let a = Alphabet.index(of: pair.first), let b = Alphabet.index(of: pair.second) else {
                throw BombeError.invalidKnownPlugboard("Known plugboard contains a non-letter.")
            }
            guard a != b else {
                throw BombeError.invalidKnownPlugboard("A letter cannot be plugged to itself.")
            }
            guard !used.contains(a), !used.contains(b) else {
                throw BombeError.invalidKnownPlugboard("A known plugboard letter is used more than once.")
            }
            used.insert(a); used.insert(b)
            map[a] = b; map[b] = a
        }
        return map
    }

    private static func stopKey(order: [String], positions: [Int], state: [Int]) -> String {
        order.joined(separator: ",") + "|" +
        positions.map(String.init).joined(separator: ",") + "|" +
        state.map(String.init).joined(separator: ",")
    }

    private static func plugboardSolutions(
        edges: [(plain: Int, cipher: Int, r: [Int], rinv: [Int])],
        components: [[Int]],
        known: [Int],
        limit: Int
    ) -> [[Int]] {
        var results: [[Int]] = []
        var seen: Set<String> = []

        /// Returns 1 when the assignment changed state, 0 when it was already
        /// satisfied, and -1 when it contradicts existing assignments.
        func assign(_ state: inout [Int], _ a: Int, _ b: Int) -> Int {
            if a == b {
                if state[a] == a { return 0 }
                if state[a] == -1 { state[a] = a; return 1 }
                return -1
            }
            if state[a] == b && state[b] == a { return 0 }
            if state[a] != -1 && state[a] != b { return -1 }
            if state[b] != -1 && state[b] != a { return -1 }
            state[a] = b
            state[b] = a
            return 1
        }

        func propagate(_ state: inout [Int]) -> Bool {
            var changed = true
            while changed {
                changed = false
                for edge in edges {
                    if state[edge.plain] >= 0 {
                        let wanted = edge.r[state[edge.plain]]
                        let result = assign(&state, edge.cipher, wanted)
                        if result < 0 { return false }
                        if result > 0 { changed = true }
                    }
                    if state[edge.cipher] >= 0 {
                        let wanted = edge.rinv[state[edge.cipher]]
                        let result = assign(&state, edge.plain, wanted)
                        if result < 0 { return false }
                        if result > 0 { changed = true }
                    }
                }
                for letter in 0..<26 {
                    let partner = state[letter]
                    if partner >= 0 {
                        let result = assign(&state, partner, letter)
                        if result < 0 { return false }
                        if result > 0 { changed = true }
                    }
                }
            }
            return true
        }

        func recurse(_ state: [Int], _ componentIndex: Int) {
            if results.count >= limit { return }
            if componentIndex == components.count {
                var completed = state
                for letter in 0..<26 where completed[letter] == -1 {
                    completed[letter] = letter
                }
                guard completed.allSatisfy({ completed[completed[$0]] == $0 }) else { return }
                let key = completed.map(String.init).joined(separator: ",")
                if !seen.contains(key) {
                    seen.insert(key)
                    results.append(completed)
                }
                return
            }
            let component = components[componentIndex]
            guard let firstUnassigned = component.first(where: { state[$0] == -1 }) else {
                recurse(state, componentIndex + 1)
                return
            }
            for partner in 0..<26 {
                if partner != firstUnassigned && state[partner] != -1 { continue }
                var candidate = state
                let result = assign(&candidate, firstUnassigned, partner)
                if result >= 0, propagate(&candidate) {
                    recurse(candidate, componentIndex + 1)
                }
                if results.count >= limit { return }
            }
        }

        var initial = known
        if !propagate(&initial) { return [] }
        recurse(initial, 0)
        return results
    }

    private static func permutations(of values: [String], choose count: Int) -> [[String]] {
        guard count > 0, values.count >= count else { return [] }
        var result: [[String]] = []
        var used = Array(repeating: false, count: values.count)
        var current: [String] = []
        func recurse() {
            if current.count == count {
                result.append(current)
                return
            }
            for index in values.indices where !used[index] {
                used[index] = true
                current.append(values[index])
                recurse()
                current.removeLast()
                used[index] = false
            }
        }
        recurse()
        return result
    }
}

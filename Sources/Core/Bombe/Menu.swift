import Foundation

public struct MenuEdge: Hashable, Sendable {
    public let offset: Int
    public let plain: Int
    public let cipher: Int

    public init(offset: Int, plain: Int, cipher: Int) {
        self.offset = offset
        self.plain = plain
        self.cipher = cipher
    }
}

public struct Menu: Sendable {
    public let edges: [MenuEdge]
    public let cribOffset: Int
    public let letters: [Int]
    public let adjacency: [Int: Set<Int>]
    public let loopCount: Int

    public init(crib: String, ciphertext: String, offset: Int) throws {
        let normalisedCrib = Alphabet.normalize(crib)
        let normalisedCipher = Alphabet.normalize(ciphertext)
        guard !normalisedCrib.isEmpty else { throw BombeError.emptyCrib }
        guard offset >= 0 else { throw BombeError.invalidOffset }
        guard offset + normalisedCrib.count <= normalisedCipher.count else {
            throw BombeError.cribOutsideCiphertext
        }

        var edges: [MenuEdge] = []
        var adjacency: [Int: Set<Int>] = [:]
        var vertices: Set<Int> = []
        var uniquePairs: Set<String> = []

        let cribCharacters = Array(normalisedCrib)
        let cipherCharacters = Array(normalisedCipher)
        for (index, plainCharacter) in cribCharacters.enumerated() {
            guard let plain = Alphabet.index(of: plainCharacter),
                  let cipher = Alphabet.index(of: cipherCharacters[offset + index]) else {
                throw BombeError.invalidCharacters
            }
            if plain == cipher {
                throw BombeError.selfEncryption(letter: plainCharacter, position: index)
            }
            edges.append(MenuEdge(offset: index, plain: plain, cipher: cipher))
            adjacency[plain, default: []].insert(cipher)
            adjacency[cipher, default: []].insert(plain)
            vertices.insert(plain)
            vertices.insert(cipher)
            let key = plain < cipher ? "\(plain)-\(cipher)" : "\(cipher)-\(plain)"
            uniquePairs.insert(key)
        }

        self.edges = edges
        self.cribOffset = offset
        self.letters = vertices.sorted()
        self.adjacency = adjacency

        // Number of independent cycles in the undirected menu graph.
        var parent = Array(0..<26)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
        }
        for edge in edges { union(edge.plain, edge.cipher) }
        var componentCount = 0
        var roots: Set<Int> = []
        for letter in vertices {
            let root = find(letter)
            if !roots.contains(root) { roots.insert(root); componentCount += 1 }
        }
        self.loopCount = max(0, uniquePairs.count - vertices.count + componentCount)
    }

    public var componentLetters: [[Int]] {
        var visited: Set<Int> = []
        var components: [[Int]] = []
        for letter in letters where !visited.contains(letter) {
            var queue = [letter]
            visited.insert(letter)
            var component: [Int] = []
            while let current = queue.popLast() {
                component.append(current)
                for neighbour in adjacency[current, default: []] where !visited.contains(neighbour) {
                    visited.insert(neighbour)
                    queue.append(neighbour)
                }
            }
            components.append(component.sorted())
        }
        return components
    }

    public var loopDescription: String {
        loopCount == 1 ? "1 loop" : "\(loopCount) loops"
    }
}

public enum BombeError: LocalizedError, Equatable {
    case emptyCiphertext
    case emptyCrib
    case invalidOffset
    case cribOutsideCiphertext
    case invalidCharacters
    case selfEncryption(letter: Character, position: Int)
    case unsupportedReflector(String)
    case invalidRotors(String)
    case invalidRingSettings
    case invalidKnownPlugboard(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .emptyCiphertext: return "Paste a ciphertext before running the Bombe."
        case .emptyCrib: return "The Bombe needs a crib — a guessed plaintext fragment."
        case .invalidOffset: return "The crib offset cannot be negative."
        case .cribOutsideCiphertext: return "The crib extends beyond the ciphertext."
        case .invalidCharacters: return "Ciphertext and crib must contain letters A–Z."
        case .selfEncryption(let letter, let position):
            return "The crib is impossible: \(letter) encrypts to itself at position \(position + 1)."
        case .unsupportedReflector(let id):
            return "The Bombe supports reflectors B and C; \(id) is not valid for this search."
        case .invalidRotors(let message): return message
        case .invalidRingSettings: return "Ring settings must contain three letters A–Z."
        case .invalidKnownPlugboard(let message): return message
        case .cancelled: return "Bombe run cancelled."
        }
    }
}

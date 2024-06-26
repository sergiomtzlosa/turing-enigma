import Foundation

public enum BombeLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case german = "German"
    case english = "English"

    public var id: String { rawValue }
}

public enum LanguageScorer {
    private static let germanFrequencies: [Character: Double] = [
        "A": 6.51, "B": 1.89, "C": 3.06, "D": 5.08, "E": 17.40, "F": 1.66,
        "G": 3.01, "H": 4.76, "I": 7.55, "J": 0.27, "K": 1.21, "L": 3.44,
        "M": 2.53, "N": 9.78, "O": 2.51, "P": 0.79, "Q": 0.02, "R": 7.00,
        "S": 7.27, "T": 6.15, "U": 4.35, "V": 0.67, "W": 1.89, "X": 0.03,
        "Y": 0.04, "Z": 1.13
    ]

    private static let englishFrequencies: [Character: Double] = [
        "A": 8.17, "B": 1.49, "C": 2.78, "D": 4.25, "E": 12.70, "F": 2.23,
        "G": 2.02, "H": 6.09, "I": 6.97, "J": 0.15, "K": 0.77, "L": 4.03,
        "M": 2.41, "N": 6.75, "O": 7.51, "P": 1.93, "Q": 0.10, "R": 5.99,
        "S": 6.33, "T": 9.06, "U": 2.76, "V": 0.98, "W": 2.36, "X": 0.15,
        "Y": 1.97, "Z": 0.07
    ]

    private static let germanBigrams = [
        "EN", "ER", "CH", "DE", "EI", "ND", "TE", "ST", "IE", "IN",
        "GE", "UN", "RE", "HE", "BE", "AN", "AU", "ES", "SC", "SI"
    ]
    private static let englishBigrams = [
        "TH", "HE", "IN", "ER", "AN", "RE", "ON", "AT", "EN", "ND",
        "TI", "ES", "OR", "TE", "OF", "ED", "IS", "IT", "AL", "AR"
    ]
    private static let germanTrigrams = [
        "EIN", "ICH", "NDE", "UNG", "DER", "DIE", "UND", "SCH", "CHE",
        "GEN", "INE", "ERS", "STE", "VER", "EIT"
    ]
    private static let englishTrigrams = [
        "THE", "AND", "ING", "ENT", "ION", "HER", "FOR", "THA", "NTH",
        "INT", "ERE", "TIO", "TER", "EST", "ERS"
    ]
    private static let germanWords = [
        "DER", "DIE", "DAS", "UND", "NICHT", "WETTER", "BERICHT", "NACHT",
        "FUER", "MIT", "IST", "DEN", "EIN", "EINE", "AUF"
    ]
    private static let englishWords = [
        "THE", "AND", "THAT", "WITH", "NIGHT", "WEATHER", "REPORT", "THIS",
        "FROM", "HAVE", "FOR", "NOT", "ARE", "WAS", "OUR"
    ]

    public static func score(_ text: String, language: BombeLanguage) -> Double {
        let normalised = Alphabet.normalize(text)
        guard !normalised.isEmpty else { return -20 }
        let frequencies = language == .german ? germanFrequencies : englishFrequencies
        let bigrams = language == .german ? germanBigrams : englishBigrams
        let trigrams = language == .german ? germanTrigrams : englishTrigrams
        let words = language == .german ? germanWords : englishWords
        let characters = Array(normalised)
        let total = Double(frequencies.values.reduce(0, +))

        var score = 0.0
        for character in characters {
            let percentage = frequencies[character] ?? 0.03
            score += log(max(percentage / total, 0.000001))
        }
        score /= Double(characters.count)

        var bigramHits = 0
        var trigramHits = 0
        if characters.count >= 2 {
            for index in 0..<(characters.count - 1) {
                let pair = String(characters[index...index + 1])
                if bigrams.contains(pair) { bigramHits += 1 }
            }
        }
        if characters.count >= 3 {
            for index in 0..<(characters.count - 2) {
                let triple = String(characters[index...index + 2])
                if trigrams.contains(triple) { trigramHits += 1 }
            }
        }
        let bigramRate = Double(bigramHits) / Double(max(1, characters.count - 1))
        let trigramRate = Double(trigramHits) / Double(max(1, characters.count - 2))
        score += bigramRate * 0.55 + trigramRate * 0.85

        var wordHits = 0
        for word in words where normalised.contains(word) {
            wordHits += 1
        }
        score += Double(wordHits) * 0.12

        return score
    }

    /// Maps a raw score into a friendly 0…1 plausibility value.
    public static func confidence(for score: Double) -> Double {
        let scaled = (score + 4.45) / 1.85
        return min(1, max(0, scaled))
    }
}

import Foundation

public enum Alphabet {
    public static let letters: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    public static let string = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    public static func index(of character: Character) -> Int? {
        guard let scalar = character.uppercased().unicodeScalars.first,
              scalar.value >= 65, scalar.value <= 90 else { return nil }
        return Int(scalar.value - 65)
    }

    public static func letter(at index: Int) -> Character {
        letters[((index % 26) + 26) % 26]
    }

    public static func normalize(_ text: String, transliterate: Bool = true) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text.uppercased() {
            switch character {
            case "Ä" where transliterate: result += "AE"
            case "Ö" where transliterate: result += "OE"
            case "Ü" where transliterate: result += "UE"
            case "ß" where transliterate: result += "SS"
            default:
                if let index = index(of: character) {
                    result.append(letter(at: index))
                }
            }
        }
        return result
    }

    public static func grouped(_ text: String, size: Int = 5) -> String {
        guard size > 0 else { return text }
        var groups: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if current.count == size {
                groups.append(current)
                current = ""
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups.joined(separator: " ")
    }

    public static func lettersOnly(_ text: String) -> [Character] {
        Array(normalize(text))
    }
}

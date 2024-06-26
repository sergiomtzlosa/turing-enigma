import Foundation

public struct AppPreset: Codable, Sendable {
    public var name: String
    public var enigma: EnigmaSettings
    public var message: String
    public var output: String
    public var bombeCiphertext: String
    public var bombeCrib: String
    public var bombeOffset: Int
    public var updatedAt: Date

    public init(
        name: String,
        enigma: EnigmaSettings,
        message: String,
        output: String,
        bombeCiphertext: String,
        bombeCrib: String,
        bombeOffset: Int,
        updatedAt: Date = Date()
    ) {
        self.name = name
        self.enigma = enigma
        self.message = message
        self.output = output
        self.bombeCiphertext = bombeCiphertext
        self.bombeCrib = bombeCrib
        self.bombeOffset = bombeOffset
        self.updatedAt = updatedAt
    }
}

public enum PresetStore {
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TuringEnigma", isDirectory: true)
    }

    public static func loadLast(from directory: URL = defaultDirectory) -> AppPreset? {
        let url = directory.appendingPathComponent("last-session.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppPreset.self, from: data)
    }

    public static func saveLast(_ preset: AppPreset, to directory: URL = defaultDirectory) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(preset)
            try data.write(to: directory.appendingPathComponent("last-session.json"), options: .atomic)
        } catch {
            // Persistence is a convenience; a failed write must never block the app.
        }
    }
}

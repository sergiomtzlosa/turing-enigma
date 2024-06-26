import Foundation

public struct DemoScenario: Sendable {
    public let title: String
    public let subtitle: String
    public let plaintext: String
    public let crib: String
    public let cribOffset: Int
    public let settings: EnigmaSettings
    public let ciphertext: String
    public let language: BombeLanguage
    public let rotorCandidates: [String]

    public var bombeQuery: BombeQuery {
        BombeQuery(
            ciphertext: ciphertext,
            crib: crib,
            cribOffset: cribOffset,
            rotorCandidates: rotorCandidates,
            ringSettings: settings.ringSettings,
            reflectorID: settings.reflectorID,
            language: language,
            maxResults: 24
        )
    }

    public static let weather = DemoScenario(
        title: "Weather for the night",
        subtitle: "A three-rotor Enigma message with a fully recoverable plugboard.",
        plaintext: "WETTERBERICHTFUERDIENACHT",
        crib: "WETTERBERICHT",
        cribOffset: 0,
        settings: EnigmaSettings.demoSecret(),
        ciphertext: "GQGYWTWGVYZBDEVSLIRPMWMBB",
        language: .german,
        rotorCandidates: ["I", "II", "III"]
    )
}

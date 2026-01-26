import Foundation
import TuringEnigmaCore

/// Maps SceneKit node names onto app intents. Keeping this separate from the
/// renderer makes the 3D interaction surface easy to inspect and test.
enum SceneIntentMapper {
    static func intent(for nodeName: String, mode: AppMode) -> SceneIntent? {
        switch mode {
        case .enigma:
            if let letter = letter(in: nodeName, prefix: "enigma.key.") {
                return .pressKey(letter)
            }
            if let letter = letter(in: nodeName, prefix: "enigma.plug.") {
                return .plug(letter)
            }
            if nodeName.hasPrefix("enigma.lamp.") {
                return .select(.enigmaLampboard)
            }
            if nodeName.hasPrefix("enigma.rotor."),
               let index = Int(nodeName.dropFirst("enigma.rotor.".count)),
               (0..<4).contains(index) {
                return .select(.enigmaRotor(index))
            }
            switch nodeName {
            case "enigma.keyboard": return .select(.enigmaKeyboard)
            case "enigma.lampboard": return .select(.enigmaLampboard)
            case "enigma.plugboard", "enigma.cables": return .select(.enigmaPlugboard)
            case "enigma.case": return .select(.enigmaCase)
            case "enigma.lid": return .select(.enigmaLid)
            case "enigma.reflector": return .select(.enigmaReflector)
            default:
                if nodeName.hasPrefix("enigma.cable.") {
                    return .select(.enigmaPlugboard)
                }
            }
        case .bombe:
            switch nodeName {
            case "bombe.start": return .startBombe
            case "bombe.stop": return .stopBombe
            case "bombe.drums": return .select(.bombeDrums)
            case "bombe.indicators": return .select(.bombeIndicators)
            case "bombe.controls": return .select(.bombeControls)
            case "bombe.cabinet": return .select(.bombeCabinet)
            case "bombe.menu": return .select(.bombeMenu)
            default:
                if nodeName.hasPrefix("bombe.drum.") { return .select(.bombeDrums) }
                if nodeName.hasPrefix("bombe.indicator.") { return .select(.bombeIndicators) }
            }
        }
        return nil
    }

    private static func letter(in name: String, prefix: String) -> Character? {
        guard name.hasPrefix(prefix) else { return nil }
        let suffix = name.dropFirst(prefix.count)
        guard suffix.count == 1, let character = suffix.first else { return nil }
        let upper = String(character).uppercased()
        guard upper.count == 1, let letter = upper.first, Alphabet.index(of: letter) != nil else {
            return nil
        }
        return letter
    }
}

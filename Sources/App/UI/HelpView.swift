import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OPERATOR'S GUIDE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(2.4)
                        .foregroundStyle(Theme.brass)
                    Text("Turing Enigma")
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ivory)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle())
            }
            .padding(24)

            Divider().overlay(Theme.stroke)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 11) {
                        SectionLabel(text: "Using the application")
                        Text("Two linked machines share one 3D viewport. Use the Enigma to encipher a message, then send the ciphertext to the Bombe to recover the daily key.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.ivory.opacity(0.88))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        usageStep(
                            "1",
                            "Choose a mode",
                            "Use the ENIGMA / BOMBE switch in the header. The inspector on the right changes with the mode; hide it with the sidebar button when you want more room for the machine."
                        )
                        usageStep(
                            "2",
                            "Set up the Enigma",
                            "Choose the model, reflector, rotor order, ring settings, window letters, and plugboard in the inspector. You can also click 3D keys and plugboard sockets, or type A–Z while the viewport has focus."
                        )
                        usageStep(
                            "3",
                            "Encipher a message",
                            "Type or paste text into the message console and press Encipher. The ciphertext appears in Output. Press Send to Bombe to carry it across, or load the built-in weather demo from the header."
                        )
                        usageStep(
                            "4",
                            "Run the Bombe",
                            "Check the crib, offset, rotor candidates, ring settings, and reflector, then press Run Bombe. When the drums settle, the deciphered text of the top stop appears in a message and in the Bombe console. Review the ranked stops, select one, and press Apply to Enigma to restore the plaintext."
                        )
                        usageStep(
                            "5",
                            "Navigate the 3D view",
                            "Drag to orbit all the way around the machine, Shift- or Option-drag (or right-drag) to pan, and scroll or pinch to zoom. When you orbit behind a room, its near back wall hides so the machine stays visible. Pitch, zoom, and pan remain limited to sensible physical bounds. Press Center to restore the default isometric view, use the camera presets for close-ups, and press Escape to clear a selection."
                        )
                    }
                    .panel()

                    section(
                        title: "The Enigma signal path",
                        text: "Each key press first advances the rotors, then sends current through the plugboard, the three (or four) rotors, the reflector, and back. The reflector makes encipherment reciprocal: the same settings decrypt the ciphertext. The middle rotor can double-step when the right-hand notch aligns, which is modelled exactly."
                    )

                    section(
                        title: "Setting the machine",
                        text: "Choose Enigma I, M3, or M4. Set the reflector, rotor order, ring settings, window letters, and plugboard. The 3D keyboard, rotor windows, lampboard, and plugboard sockets are live: click a key, a socket, or a rotor to interact. Click a plugged socket again to remove its cable. Type on the hardware keyboard while the viewport has focus. Drag to orbit, Shift/Option- or right-drag to pan, scroll or pinch to zoom, and press Escape to clear the selection."
                    )

                    section(
                        title: "The Bombe",
                        text: "The Bombe tests rotor orders and all 26³ starting windows. A crib — a guessed plaintext fragment — defines a menu of letter relationships. The crib must fit inside the ciphertext at the chosen offset; custom messages need their own crib. For each candidate, the simulator propagates the implied plugboard constraints and counts contradictions, like the diagonal board. Surviving candidates are stops. Full decodes are ranked with German or English letter, bigram, trigram, and word frequencies. When the run finishes, the top stop's deciphered text is shown as a message and remains visible in the Bombe console and stop cards."
                    )

                    section(
                        title: "What the Bombe can recover",
                        text: "Only plugboard pairs whose letters appear in the menu are constrained by the crib. Pairs outside the menu are information-theoretically unknowable from that crib alone. The demo is constructed so that every plug in the key appears in the menu; applying its stop therefore recovers the complete plaintext. Ring settings are supplied as daily-key intelligence in this simulation; automatic ring search is future work."
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Quick demo")
                        step("1", "Press Demo in the header to load the weather message and secret key.")
                        step("2", "Press Encipher. The rotors step, lamps glow, and the ciphertext appears.")
                        step("3", "Press Send to Bombe, then Run Bombe. The drums spin while the search runs.")
                        step("4", "Select the top stop and press Apply to Enigma. The recovered key is applied and the plaintext is revealed.")
                    }
                    .panel()

                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Theme.lamp)
                        Text("This is a behavioural simulation of the Bombe's logic, not an electrical relay model. It is intended for learning and exploration.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .panel()

                    HStack {
                        Spacer()
                        Button("Close") { dismiss() }
                            .buttonStyle(BrassButtonStyle(prominent: true))
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 720, height: 700)
        .background(Theme.background)
    }

    private func section(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: title)
            Text(text)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.ivory.opacity(0.88))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panel()
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.black)
                .frame(width: 19, height: 19)
                .background(Circle().fill(Theme.brass))
            Text(text)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.ivory.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func usageStep(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.brass))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ivory)
                Text(detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

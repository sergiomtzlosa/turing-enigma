import SwiftUI
import TuringEnigmaCore

struct EnigmaInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            machineCard
            rotorCard
            plugboardCard
            stateCard
        }
    }

    private var machineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Machine")
                Spacer()
                Text(model.enigma.machineType.shortName)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.brass)
            }

            Picker("Model", selection: Binding(
                get: { model.enigma.machineType },
                set: { model.changeMachine(to: $0) }
            )) {
                ForEach(EnigmaMachineType.allCases) { type in
                    Text(type == .enigmaI ? "ENIGMA I" : type.rawValue.uppercased()).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Text("Reflector")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Picker("Reflector", selection: Binding(
                    get: { model.enigma.reflectorID },
                    set: { model.setReflector($0) }
                )) {
                    ForEach(model.enigma.machineType.availableReflectorIDs, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 120)
            }

            if !model.enigma.validationIssues().isEmpty {
                Text(model.enigma.validationIssues().joined(separator: " "))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.danger)
            }
        }
        .panel()
    }

    private var rotorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Rotor order & rings")
                Spacer()
                Text("left → right")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }

            ForEach(Array(model.enigma.rotorIDs.indices), id: \.self) { index in
                HStack(spacing: 8) {
                    Text(index == 0 ? "L" : (index == model.enigma.rotorIDs.count - 1 ? "R" : "M"))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.brass)
                        .frame(width: 14)

                    Picker("Rotor", selection: Binding(
                        get: { model.enigma.rotorIDs[index] },
                        set: { model.setRotor(at: index, to: $0) }
                    )) {
                        ForEach(model.availableRotors(for: index), id: \.self) { id in
                            Text(id).tag(id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 82)

                    LetterSettingMenu(
                        label: "Ring",
                        value: model.enigma.ringSettings[index],
                        onSelect: { model.setRing(at: index, to: $0) }
                    )

                    LetterSettingMenu(
                        label: "Window",
                        value: model.enigma.initialPositions[index],
                        onSelect: { model.setWindow(at: index, to: $0) }
                    )
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                Text("WINDOWS")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(model.enigma.windowLetters)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(Theme.brassBright)
                    .accessibilityIdentifier("windows.text")
                Spacer()
                Text("RINGS")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(model.enigma.ringLetters)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(Theme.ivory)
            }
            .padding(.top, 2)
        }
        .panel()
    }

    private var plugboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Plugboard")
                Spacer()
                Text("\(model.enigma.plugboard.count)/13")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Alphabet.letters, id: \.self) { letter in
                    Button {
                        model.togglePlug(letter)
                    } label: {
                        LetterCube(letter: letter, state: plugState(letter))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let pending = model.pendingPlug {
                Text("Choose a partner for \(String(pending)) — or click \(String(pending)) again to cancel.")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(Theme.lamp)
            } else if model.enigma.plugboard.isEmpty {
                Text("Click two letters to make a cable. Click a connected letter to remove its pair.")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(Theme.muted)
            } else {
                FlowLayout(spacing: 5) {
                    ForEach(model.enigma.plugboard, id: \.id) { pair in
                        HStack(spacing: 4) {
                            Text("\(String(pair.first))—\(String(pair.second))")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.ivory)
                            Button {
                                model.removePlug(pair)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(Theme.muted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                    }
                }
            }

            HStack {
                Button("Clear plugboard") { model.clearPlugboard() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("One letter cannot be used twice")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(Theme.muted.opacity(0.7))
            }
        }
        .panel()
    }

    private var stateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Machine state")
                Spacer()
                Button("Reset") { model.resetMachine() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.brass)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT WINDOWS")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                    Text(String(model.presentation.rotorPositions.map { Alphabet.letter(at: $0) }))
                        .font(.system(size: 21, weight: .semibold, design: .monospaced))
                        .tracking(5)
                        .foregroundStyle(Theme.ivory)
                }
                Spacer()
                if let lamp = model.presentation.litLamp {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("LAMP")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                        Text(String(lamp))
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .foregroundStyle(Theme.lamp)
                            .shadow(color: Theme.lamp.opacity(0.8), radius: 10)
                    }
                } else {
                    Text(model.isAnimating ? "RUNNING" : "READY")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(model.isAnimating ? Theme.lamp : Theme.muted)
                }
            }

            Divider().overlay(Theme.stroke)

            HStack {
                Text("Click the 3D keyboard or type while the viewport is focused.")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
        }
        .panel()
    }

    private func plugState(_ letter: Character) -> LetterCube.State {
        if model.pendingPlug == letter { return .pending }
        if model.isPlugged(letter) != nil { return .paired }
        return .idle
    }
}

struct LetterSettingMenu: View {
    let label: String
    let value: Int
    let onSelect: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(0..<26, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Text(verbatim: "\(Alphabet.letter(at: index))  ·  \(String(format: "%02d", index + 1))")
                }
            }
        } label: {
            VStack(spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(String(Alphabet.letter(at: value)))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ivory)
                    .frame(minWidth: 26)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
        }
        .menuStyle(.borderlessButton)
        .fixMenuLabel()
    }
}

private extension View {
    func fixMenuLabel() -> some View {
        self.menuIndicator(.hidden)
    }
}

struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 6, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

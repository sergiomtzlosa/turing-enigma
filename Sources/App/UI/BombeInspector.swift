import SwiftUI
import TuringEnigmaCore

struct BombeInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            interceptCard
            setupCard
            menuCard
            runCard
            if !model.bombeResults.isEmpty {
                resultsCard
            }
        }
    }

    private var interceptCard: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Intercept")
                Spacer()
                Button("Load demo") {
                    model.loadDemo()
                    model.mode = .bombe
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.brass)
            }

            TextEditor(text: $model.bombe.ciphertext)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ivory)
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(height: 74)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black.opacity(0.34))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if model.bombe.ciphertext.isEmpty {
                        Text("Ciphertext")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Theme.muted.opacity(0.6))
                            .padding(.leading, 12)
                            .padding(.top, 9)
                            .allowsHitTesting(false)
                    }
                }

            TextField("Crib — guessed plaintext", text: $model.bombe.crib)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ivory)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )

            Text("The Bombe is a known-plaintext attack. A crib is a plaintext fragment you believe the message contains; it creates the letter menu needed to reject wrong keys and recover the plugboard.")
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            let maxOffset = max(0, Alphabet.normalize(model.bombe.ciphertext).count - Alphabet.normalize(model.bombe.crib).count)
            HStack {
                Text("Offset")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Stepper(
                    value: Binding(
                        get: { min(max(0, model.bombe.cribOffset), maxOffset) },
                        set: { model.setCribOffset($0) }
                    ),
                    in: 0...max(0, maxOffset)
                ) {
                    Text("\(model.bombe.cribOffset)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.ivory)
                }
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                Text("\(Alphabet.normalize(model.bombe.ciphertext).count) cipher letters")
                Text("·")
                Text("\(Alphabet.normalize(model.bombe.crib).count) crib letters")
                Spacer()
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(Theme.muted)

            if !Alphabet.normalize(model.bombe.ciphertext).isEmpty,
               let issue = model.bombe.validationIssue {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text(issue)
                        .font(.system(size: 9, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.lamp)
            }
        }
        .panel()
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                SectionLabel(text: "Bombe setup")
                Spacer()
                Text("\(model.bombe.rotorCandidates.count) rotors")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }

            Text("Rotor candidates")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                ForEach(["I", "II", "III", "IV", "V", "VI", "VII", "VIII"], id: \.self) { id in
                    Button {
                        model.toggleRotorCandidate(id)
                    } label: {
                        Text(id)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(model.bombe.rotorCandidates.contains(id) ? Color.black : Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(model.bombe.rotorCandidates.contains(id) ? Theme.brass : Color.white.opacity(0.055))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("Ring settings")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("windows searched: 26³")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Theme.muted.opacity(0.75))
            }

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    LetterSettingMenu(
                        label: index == 0 ? "Left ring" : (index == 1 ? "Middle ring" : "Right ring"),
                        value: model.bombe.ringSettings[index],
                        onSelect: { model.setBombeRing(at: index, to: $0) }
                    )
                }
                Spacer()
            }

            HStack {
                Text("Reflector")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                Picker("Reflector", selection: Binding(
                    get: { model.bombe.reflectorID },
                    set: { model.setBombeReflector($0) }
                )) {
                    Text("B").tag("B")
                    Text("C").tag("C")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 90)

                Spacer()

                Text("Language")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                Picker("Language", selection: Binding(
                    get: { model.bombe.language },
                    set: { model.setBombeLanguage($0) }
                )) {
                    ForEach(BombeLanguage.allCases) { language in
                        Text(language.rawValue).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 96)
            }
        }
        .panel()
    }

    private var menuCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionLabel(text: "Menu")
                Spacer()
                if let menu = try? TuringEnigmaCore.Menu(
                    crib: model.bombe.crib,
                    ciphertext: model.bombe.ciphertext,
                    offset: model.bombe.cribOffset
                ) {
                    Text("\(menu.edges.count) edges · \(menu.loopDescription)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.brass)
                }
            }

            if let menu = try? TuringEnigmaCore.Menu(
                crib: model.bombe.crib,
                ciphertext: model.bombe.ciphertext,
                offset: model.bombe.cribOffset
            ) {
                MenuGraphView(menu: menu)
                    .frame(height: 150)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 20, weight: .thin))
                        .foregroundStyle(Theme.muted.opacity(0.6))
                    Text("A valid crib and ciphertext will draw the menu graph.")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                )
            }

            if let menu = try? TuringEnigmaCore.Menu(
                crib: model.bombe.crib,
                ciphertext: model.bombe.ciphertext,
                offset: model.bombe.cribOffset
            ) {
                Text("A loop gives the Bombe its contradiction test. More loops mean fewer false stops.")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if menu.loopCount == 0 {
                    Text("This menu has no loops — the search may return many false stops.")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(Theme.lamp)
                }
            }
        }
        .panel()
    }

    private var runCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Search")
                Spacer()
                if let summary = model.bombeSummary {
                    Text("\(summary.candidatesSearched.formatted()) candidates · \(String(format: "%.2fs", summary.elapsed))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
            }

            if model.bombeState == .running {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: model.bombeProgress)
                        .progressViewStyle(.linear)
                        .tint(Theme.brass)
                    HStack {
                        Text("Drums running")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.lamp)
                        Spacer()
                        Text("\(Int(model.bombeProgress * 100))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.ivory)
                    }
                }
                Button {
                    model.stopBombe()
                } label: {
                    Label("Stop Bombe", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BrassButtonStyle())
            } else {
                Button {
                    model.runBombe()
                } label: {
                    Label("Run Bombe", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BrassButtonStyle(prominent: true))
            }

            if model.bombeResults.isEmpty && model.bombeState == .stopped {
                Text("No stops. Try moving the crib offset, changing the rotor candidates, or checking the ring settings.")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(Theme.lamp)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panel()
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Stops")
                Spacer()
                Text("\(model.bombeResults.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.brass)
            }

            ForEach(Array(model.bombeResults.enumerated()), id: \.element.id) { index, stop in
                stopCard(stop, rank: index + 1)
            }
        }
        .panel()
    }

    private func stopCard(_ stop: BombeStop, rank: Int) -> some View {
        let selected = model.selectedStopID == stop.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                model.selectedStopID = stop.id
            } label: {
                HStack(alignment: .top) {
                    Text(String(format: "%02d", rank))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(selected ? Color.black : Theme.brass)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(selected ? Theme.brass : Theme.brass.opacity(0.12))
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(stop.orderLabel)  ·  window \(stop.windowLabel)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.ivory)
                        Text("Rings \(String(stop.ringSettings.map { Alphabet.letter(at: $0) }))  ·  hypothesis \(String(stop.hypothesis))")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text("\(Int(stop.confidence * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(stop.confidence > 0.7 ? Theme.ok : Theme.muted)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                ForEach(stop.plugboard) { pair in
                    Text("\(String(pair.first))\(String(pair.second))")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.ivory)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.065)))
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Deciphered text")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.brass)
                Text(Alphabet.grouped(stop.decryptedText))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ivory)
                    .lineLimit(4)
                    .help(stop.decryptedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("\(stop.plugboard.count) plugs recovered")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button {
                    model.apply(stop: stop)
                } label: {
                    Text("Apply to Enigma")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                }
                .buttonStyle(BrassButtonStyle(prominent: true))
                .controlSize(.small)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Theme.brass.opacity(0.10) : Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(selected ? Theme.brass.opacity(0.45) : Theme.stroke, lineWidth: 1)
        )
    }
}

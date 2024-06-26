import SwiftUI
import TuringEnigmaCore

struct MessageConsole: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Message")
                Spacer()
                Toggle(isOn: $model.animatePlayback) {
                    Text("Animate")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Text("\(Alphabet.normalize(model.message).count) letters")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }

            HStack(alignment: .top, spacing: 12) {
                TextEditor(text: $model.message)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ivory)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 66)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.34))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if model.message.isEmpty {
                            Text("Type a message — punctuation and spaces are removed.")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(Theme.muted.opacity(0.65))
                                .padding(.leading, 13)
                                .padding(.top, 10)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityIdentifier("message.editor")

                VStack(spacing: 7) {
                    Button {
                        model.encodeMessage()
                    } label: {
                        Label("Encipher", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("encipher.button")
                    .buttonStyle(BrassButtonStyle(prominent: true))
                    .disabled(model.isAnimating)
                    .uiProbeFrame("encipher")

                    Button {
                        model.sendToBombe()
                    } label: {
                        Label("Send to Bombe", systemImage: "waveform.path.ecg")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("bombe.send")
                    .buttonStyle(BrassButtonStyle())
                    .disabled(model.isAnimating || (model.output.isEmpty && model.message.isEmpty))
                    .uiProbeFrame("bombe.send")
                }
                .frame(width: 150)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionLabel(text: "Output")
                Text(model.output.isEmpty ? "—" : Alphabet.grouped(model.output))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(model.output.isEmpty ? Theme.muted : Theme.brassBright)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("output.text")
                Spacer()
                if !model.output.isEmpty {
                    Button {
                        model.copyOutput()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Copy output")
                }
            }

            if !model.liveInput.isEmpty {
                HStack(spacing: 10) {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.lamp)
                    Text(Alphabet.grouped(model.liveInput))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    Text("→")
                        .foregroundStyle(Theme.brass)
                    Text(Alphabet.grouped(model.liveOutput))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.ivory)
                        .lineLimit(1)
                    Spacer()
                    Button("Clear") {
                        model.liveInput = ""
                        model.liveOutput = ""
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.muted)
                }
                .padding(.top, 1)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.panel.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.brass.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 28, y: 12)
    }
}

struct BombeConsole: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "Bombe run")
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.bombeState == .running ? Theme.lamp : (model.bombeResults.isEmpty ? Theme.muted : Theme.ok))
                        .frame(width: 7, height: 7)
                    Text(statusLine)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.ivory)
                        .lineLimit(1)
                }
            }

            if model.bombeState == .running {
                ProgressView(value: model.bombeProgress)
                    .progressViewStyle(.linear)
                    .tint(Theme.brass)
                    .frame(maxWidth: 220)
            } else if let stop = model.selectedStop {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("\(stop.orderLabel)  ·  \(stop.windowLabel)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.brassBright)
                        Text(stop.plugboardLabel)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("DECIPHERED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.brass)
                        Text(Alphabet.grouped(stop.decryptedText))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.ivory)
                            .lineLimit(2)
                            .help(stop.decryptedText)
                    }
                }
            } else {
                Text("Enter a crib, then start the drums.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            if model.bombeState == .running {
                Button {
                    model.stopBombe()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(BrassButtonStyle())
            } else {
                Button {
                    model.runBombe()
                } label: {
                    Label("Run Bombe", systemImage: "play.fill")
                }
                .accessibilityIdentifier("bombe.run")
                .buttonStyle(BrassButtonStyle(prominent: true))
            }

            if let stop = model.selectedStop, model.bombeState == .stopped {
                Button {
                    model.apply(stop: stop)
                } label: {
                    Label("Apply", systemImage: "checkmark.circle")
                }
                .accessibilityIdentifier("bombe.apply")
                .buttonStyle(BrassButtonStyle())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.panel.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.brass.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 28, y: 12)
    }

    private var statusLine: String {
        switch model.bombeState {
        case .idle:
            return model.bombe.ciphertext.isEmpty ? "Awaiting intercept" : "Ready · \(Alphabet.normalize(model.bombe.ciphertext).count) letters"
        case .running:
            return "Drums running · \(Int(model.bombeProgress * 100))%"
        case .stopped:
            if let summary = model.bombeSummary {
                return "\(model.bombeResults.count) stop\(model.bombeResults.count == 1 ? "" : "s") · \(String(format: "%.2fs", summary.elapsed))"
            }
            return "Stopped"
        }
    }
}

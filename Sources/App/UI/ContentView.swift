import SwiftUI
import TuringEnigmaCore

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            HStack(spacing: 0) {
                viewportPane
                if model.isInspectorVisible {
                    Divider().overlay(Theme.stroke)
                    inspectorPane
                        .frame(width: 396)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .coordinateSpace(name: "ui-probe")
        .background(Theme.background)
        .animation(.easeInOut(duration: 0.22), value: model.isInspectorVisible)
        .sheet(isPresented: $model.showHelp) {
            HelpView()
                .environment(model)
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(text: toast)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: 18) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Theme.brassBright, Theme.brass, Color(hex: 0x5D4823)],
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: 24
                            )
                        )
                        .frame(width: 34, height: 34)
                    Circle()
                        .stroke(Color.black.opacity(0.4), lineWidth: 1)
                        .frame(width: 34, height: 34)
                    Text("E")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(Color(hex: 0x17120A))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("TURING ENIGMA")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .tracking(2.2)
                        .foregroundStyle(Theme.ivory)
                        .accessibilityIdentifier("app.title")
                    Text("BLETCHLEY SIMULATION LAB")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(Theme.muted)
                }
            }

            ModeSwitch(selection: $model.mode)
                .frame(width: 220)

            Spacer(minLength: 12)

            statusPill

            HStack(spacing: 8) {
                Button {
                    model.loadDemo()
                } label: {
                    Label("Demo", systemImage: "sparkles")
                }
                .accessibilityIdentifier("demo.button")
                .buttonStyle(BrassButtonStyle())
                .uiProbeFrame("demo")

                Button {
                    model.toggleSound()
                } label: {
                    Image(systemName: model.isSoundEnabled ? "speaker.wave.2" : "speaker.slash")
                }
                .buttonStyle(IconButtonStyle())
                .help("Toggle sound")

                Button {
                    model.showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(IconButtonStyle())
                .help("How to use Turing Enigma")

                Button {
                    model.isInspectorVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(IconButtonStyle())
                .help("Toggle inspector")
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x16191D), Color(hex: 0x0E1013)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .shadow(color: statusColor.opacity(0.8), radius: 5)
            Text(model.statusText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
        )
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }

    private var statusColor: Color {
        if model.isAnimating || model.bombeState == .running { return Theme.lamp }
        if model.mode == .bombe && model.bombeState == .stopped {
            return model.bombeResults.isEmpty ? Theme.danger : Theme.ok
        }
        return Theme.muted
    }

    private var viewportPane: some View {
        ZStack {
            MachineViewport(
                mode: model.mode,
                enigma: model.enigma,
                presentation: model.presentation,
                selection: model.selectedComponent,
                bombe: model.bombe,
                bombeState: model.bombeState,
                bombeProgress: model.bombeProgress,
                selectedStop: model.selectedStop,
                cameraRequest: model.cameraRequest,
                cameraRequestID: model.cameraRequestID,
                centerRequestID: model.centerRequestID,
                onIntent: { intent in
                    model.handle(intent)
                }
            )
            .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    machineLabel
                    Spacer()
                    cameraButtons
                }
                Spacer()
            }
            .padding(20)

            VStack {
                Spacer()
                if model.mode == .enigma {
                    MessageConsole()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                } else {
                    BombeConsole()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                }
            }
        }
        .background(Color.black)
        .clipped()
    }

    private var machineLabel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.mode == .enigma ? "ENIGMA I / M3 / M4" : "TURING–WELCHMAN BOMBE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Theme.brass)
            Text(model.mode == .enigma ? "Rotors, plugboard and lampboard" : "108 drums · 36 Enigma equivalents")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.black.opacity(0.42)))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }

    private var cameraButtons: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button {
                model.centerCamera()
            } label: {
                Label("Center", systemImage: "scope")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ivory)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.brass.opacity(0.20)))
                    .overlay(Capsule().stroke(Theme.brass.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Restore the default isometric view")
            .accessibilityIdentifier("camera.center")
            .accessibilityLabel("Restore default isometric view")
            .uiProbeFrame("center")

            ForEach(CameraPreset.allCases) { preset in
                if (model.mode == .enigma && [.keyboard, .rotors, .plugboard].contains(preset)) ||
                    (model.mode == .bombe && [.drums, .controls].contains(preset)) {
                    Button {
                        model.requestCamera(preset)
                    } label: {
                        Text(preset.rawValue)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.4)))
                            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var inspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.mode == .enigma {
                    EnigmaInspector()
                } else {
                    BombeInspector()
                }
            }
            .padding(16)
        }
        .background(
            LinearGradient(
                colors: [Color(hex: 0x121519), Color(hex: 0x0D0F12)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct ModeSwitch: View {
    @Binding var selection: AppMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = mode }
                } label: {
                    Text(mode.rawValue.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(selection == mode ? Theme.ivory : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == mode ? Color.white.opacity(0.10) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(selection == mode ? Theme.brass.opacity(0.45) : Color.clear, lineWidth: 1)
                        )
                }
                .accessibilityIdentifier("mode.\(mode.rawValue.lowercased())")
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }
}

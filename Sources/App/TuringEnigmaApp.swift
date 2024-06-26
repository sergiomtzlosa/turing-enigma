import SwiftUI
import TuringEnigmaCore

@main
struct TuringEnigmaApp: App {
    @State private var model = AppModel()

    init() {
        if SceneSnapshot.runIfRequested() {
            exit(0)
        }
        if let code = ViewportSelfTest.runIfRequested() {
            exit(code)
        }
        if let code = AppFlowSelfTest.runIfRequested() {
            exit(code)
        }
        if let code = UIActionSelfTest.runIfRequested() {
            exit(code)
        }
    }

    var body: some Scene {
        WindowGroup("Turing Enigma") {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    model.loadDemo()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("Machine") {
                Button("Encipher Message") { model.encodeMessage() }
                    .keyboardShortcut("e", modifiers: [.command])
                    .disabled(model.isAnimating)
                Button("Send Cipher to Bombe") { model.sendToBombe() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Divider()
                Button("Run Bombe") { model.runBombe() }
                    .keyboardShortcut("b", modifiers: [.command])
                    .disabled(model.bombeState == .running)
                Button("Stop Bombe") { model.stopBombe() }
                    .disabled(model.bombeState != .running)
                Divider()
                Button("Reset Machine") { model.resetMachine() }
                Button("Reset Camera") { model.centerCamera() }
                Divider()
                Button("Load Weather Demo") { model.loadDemo() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Toggle Sound") { model.toggleSound() }
                Button("Operator's Guide") { model.showHelp = true }
            }
        }
    }
}

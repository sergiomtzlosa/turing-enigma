import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0B0D0F)
    static let panel = Color(hex: 0x15181C)
    static let panelRaised = Color(hex: 0x1B1F24)
    static let stroke = Color.white.opacity(0.09)
    static let brass = Color(hex: 0xC8A45C)
    static let brassBright = Color(hex: 0xE4C77D)
    static let ivory = Color(hex: 0xE9E1CF)
    static let muted = Color(hex: 0x8D9198)
    static let lamp = Color(hex: 0xFFB347)
    static let danger = Color(hex: 0xC05A4A)
    static let ok = Color(hex: 0x7FB68A)

    static let titleFont = Font.system(size: 22, weight: .semibold, design: .serif)
    static let captionFont = Font.system(size: 10, weight: .semibold, design: .monospaced)
    static let monoFont = Font.system(size: 12, weight: .medium, design: .monospaced)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct PanelStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.panel.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func panel(padding: CGFloat = 16) -> some View {
        modifier(PanelStyle(padding: padding))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.captionFont)
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
    }
}

struct BrassButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(prominent ? Color(hex: 0x16120A) : Theme.ivory)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        prominent
                            ? LinearGradient(colors: [Theme.brassBright, Theme.brass], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(prominent ? Theme.brassBright.opacity(0.8) : Theme.stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.ivory)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.15 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

struct LetterCube: View {
    let letter: Character
    var state: State = .idle

    enum State {
        case idle
        case pending
        case paired
        case pressed
    }

    var body: some View {
        Text(String(letter))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(state == .pressed ? Color.black : Theme.ivory)
            .frame(width: 27, height: 27)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(state == .idle ? Theme.stroke : Theme.brass.opacity(0.45), lineWidth: 1)
            )
    }

    private var fill: Color {
        switch state {
        case .idle: return Color.white.opacity(0.055)
        case .pending: return Theme.brass.opacity(0.38)
        case .paired: return Color(hex: 0x3A3427)
        case .pressed: return Theme.lamp
        }
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.ivory)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.panelRaised.opacity(0.96)))
            .overlay(Capsule().stroke(Theme.brass.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }
}

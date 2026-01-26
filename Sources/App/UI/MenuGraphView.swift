import SwiftUI
import TuringEnigmaCore

struct MenuGraphView: View {
    let menu: TuringEnigmaCore.Menu

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let positions = nodePositions(in: size)

            ZStack {
                Canvas { context, _ in
                    for (index, edge) in menu.edges.enumerated() {
                        guard let a = positions[edge.plain], let b = positions[edge.cipher] else { continue }
                        var path = Path()
                        path.move(to: a)
                        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                        let dx = b.x - a.x
                        let dy = b.y - a.y
                        let length = max(0.001, sqrt(dx * dx + dy * dy))
                        let bend = CGFloat(index % 2 == 0 ? 4 : -4)
                        let control = CGPoint(
                            x: mid.x - dy / length * bend,
                            y: mid.y + dx / length * bend
                        )
                        path.addQuadCurve(to: b, control: control)
                        context.stroke(
                            path,
                            with: .color(Theme.brass.opacity(menu.loopCount > 0 ? 0.55 : 0.30)),
                            lineWidth: menu.loopCount > 0 ? 1.1 : 0.8
                        )
                    }
                }

                ForEach(menu.letters, id: \.self) { letter in
                    if let point = positions[letter] {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Theme.brassBright.opacity(0.95), Theme.brass.opacity(0.7)],
                                        center: .topLeading,
                                        startRadius: 0,
                                        endRadius: 18
                                    )
                                )
                                .frame(width: 23, height: 23)
                            Circle()
                                .stroke(Color.black.opacity(0.35), lineWidth: 1)
                                .frame(width: 23, height: 23)
                            Text(String(Alphabet.letter(at: letter)))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(hex: 0x17120A))
                        }
                        .position(point)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.20))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
        }
    }

    private func nodePositions(in size: CGSize) -> [Int: CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(18, min(size.width, size.height) / 2 - 18)
        let count = max(1, menu.letters.count)
        var result: [Int: CGPoint] = [:]
        for (index, letter) in menu.letters.enumerated() {
            let angle = -Double.pi / 2 + (Double(index) / Double(count)) * 2 * Double.pi
            result[letter] = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
        }
        return result
    }
}

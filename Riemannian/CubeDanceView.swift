import SwiftUI

struct CubeDanceView: View {
    @ObservedObject var audio: AudioEngine
    @Binding var selectedChord: Chord?

    private let cubeDance = CubeDance.shared
    private let totalNodes = 28

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) * 0.43

            ZStack {
                ForEach(cubeDance.edges) { edge in
                    if let fromPos = position(id: edge.fromId, center: center, radius: radius),
                       let toPos = position(id: edge.toId, center: center, radius: radius) {
                        EdgeShape(from: fromPos, to: toPos, dashed: !edge.solid)
                    }
                }

                ForEach(cubeDance.nodes) { node in
                    if let pos = position(id: node.id, center: center, radius: radius) {
                        NodeView(
                            node: node,
                            isSelected: node.chord != nil && node.chord == selectedChord,
                            isActive: isActive(node)
                        )
                        .position(pos)
                        .onTapGesture { handleTap(node) }
                    }
                }
            }
        }
    }

    private func angle(for ringPosition: Int) -> Double {
        Double(ringPosition) / Double(totalNodes) * 2 * .pi - .pi / 2
    }

    private func position(id: String, center: CGPoint, radius: CGFloat) -> CGPoint? {
        guard let node = cubeDance.nodes.first(where: { $0.id == id }) else { return nil }
        let r = node.isAugmented ? radius * 1.1 : radius
        let a = angle(for: node.ringPosition)
        return CGPoint(x: center.x + r * CGFloat(cos(a)),
                       y: center.y + r * CGFloat(sin(a)))
    }

    private func isActive(_ node: CubeDanceNode) -> Bool {
        guard let chord = node.chord else { return false }
        // Active if any of the chord's pitch classes are sounding
        return chord.midiNotes.contains { audio.activePitchClasses.contains(Int($0) % 12) }
    }

    private func handleTap(_ node: CubeDanceNode) {
        guard let chord = node.chord else { return }
        if selectedChord == chord {
            selectedChord = nil
            audio.stopAll()
        } else {
            selectedChord = chord
            audio.transitionToChord(chord)
        }
    }
}

// MARK: - Edge

struct EdgeShape: View {
    let from: CGPoint
    let to: CGPoint
    let dashed: Bool

    var body: some View {
        Path { p in
            p.move(to: from)
            p.addLine(to: to)
        }
        .stroke(
            dashed ? Color.cyan.opacity(0.28) : Color.white.opacity(0.42),
            style: StrokeStyle(lineWidth: dashed ? 1 : 1.5, dash: dashed ? [5, 4] : [])
        )
    }
}

// MARK: - Node

struct NodeView: View {
    let node: CubeDanceNode
    let isSelected: Bool
    let isActive: Bool

    private var isMajor: Bool { node.chord?.mode == .major }
    private var nodeSize: CGFloat { node.isAugmented ? 28 : 38 }

    private var fillColor: Color {
        if isSelected { return .yellow }
        if isActive { return isMajor ? Color.blue.opacity(0.95) : Color.teal.opacity(0.95) }
        if node.isAugmented { return Color.purple.opacity(0.55) }
        return isMajor ? Color.blue.opacity(0.65) : Color.teal.opacity(0.65)
    }

    private var strokeColor: Color {
        if isSelected { return .yellow }
        if isActive { return .white }
        return .white.opacity(0.4)
    }

    var body: some View {
        ZStack {
            filledNode
                .frame(width: nodeSize, height: nodeSize)

            Text(node.displayName)
                .font(.system(size: node.isAugmented ? 7 : 10, weight: .semibold))
                .foregroundColor(isSelected ? .black : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: nodeSize - 4)
        }
        .scaleEffect(isSelected || isActive ? 1.2 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.65), value: isSelected)
        .animation(.spring(response: 0.15, dampingFraction: 0.7), value: isActive)
    }

    @ViewBuilder
    private var filledNode: some View {
        let sw: CGFloat = isSelected ? 2.5 : (isActive ? 2 : 1)
        if node.isAugmented {
            Diamond()
                .fill(fillColor)
                .overlay(Diamond().stroke(strokeColor, lineWidth: sw))
        } else if isMajor {
            RoundedRectangle(cornerRadius: 6)
                .fill(fillColor)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(strokeColor, lineWidth: sw))
        } else {
            Circle()
                .fill(fillColor)
                .overlay(Circle().stroke(strokeColor, lineWidth: sw))
        }
    }
}

// MARK: - Diamond shape

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

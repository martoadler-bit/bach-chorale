import SwiftUI

struct TheoryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                introSection
                operationsSection
                cyclesSection
                weitzmannSection
            }
            .padding()
        }
        .background(Color.black)
    }

    // MARK: - Intro

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey("theory.intro.title"))
                .font(.title2.bold())
                .foregroundColor(.white)
            Text(LocalizedStringKey("theory.intro.body"))
                .font(.callout)
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Operations

    private var operationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(titleKey: "theory.ops.title", subtitleKey: "theory.ops.subtitle")
            ForEach(NRTOperation.allCases, id: \.self) { op in
                OperationCard(op: op)
            }
        }
    }

    // MARK: - Hexatonic Cycles

    private var cyclesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(titleKey: "theory.hex.title", subtitleKey: "theory.hex.subtitle")
            Text(LocalizedStringKey("theory.hex.body"))
                .font(.callout)
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(HexatonicCycle.all) { cycle in
                CycleRow(label: cycle.name, chords: cycle.chords, color: .yellow)
            }
        }
    }

    // MARK: - Weitzmann Regions

    private var weitzmannSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(titleKey: "theory.weitz.title", subtitleKey: "theory.weitz.subtitle")
            Text(LocalizedStringKey("theory.weitz.body"))
                .font(.callout)
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(WeitzmannRegion.all) { region in
                let label = "\(Chord.noteNames[region.augRoot])+ — \(region.name)"
                CycleRow(label: label, chords: region.chords, color: .cyan)
            }
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let titleKey: String
    let subtitleKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(titleKey))
                .font(.title3.bold())
                .foregroundColor(.white)
            Text(LocalizedStringKey(subtitleKey))
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.top, 4)
    }
}

// MARK: - Operation Card

struct OperationCard: View {
    let op: NRTOperation

    @State private var expanded = false

    private var opColor: Color {
        switch op {
        case .L: return .orange
        case .P: return .green
        case .R: return .blue
        case .N: return .purple
        case .H: return .red
        case .S: return .cyan
        }
    }

    // Demo: show C major transforming through each op
    private let demoChord = Chord(root: 0, mode: .major)
    private var target: Chord { op.apply(to: demoChord) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible
            Button { withAnimation(.spring(response: 0.3)) { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    Text(op.rawValue)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(opColor)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(op.fullName)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text(NSLocalizedString("op.\(op.rawValue.lowercased()).short", comment: ""))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    // Static demo arrow
                    HStack(spacing: 4) {
                        ChordPill(chord: demoChord, color: opColor, dim: true)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(opColor.opacity(0.7))
                        ChordPill(chord: target, color: opColor, dim: false)
                    }

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding()
            }
            .buttonStyle(.plain)

            // Expanded detail
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().background(opColor.opacity(0.3))

                    Text(NSLocalizedString("op.\(op.rawValue.lowercased()).long", comment: ""))
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)

                    // Voice movement diagram
                    VoiceMovementView(op: op, from: demoChord, to: target, color: opColor)

                    // Properties row
                    HStack(spacing: 8) {
                        PropertyTag(label: "±\(op.semitonesDisplaced) st", color: opColor)
                        if op == .H || op == .S {
                            PropertyTag(label: LocalizedStringKey("op.compound"), color: .white.opacity(0.4))
                        }
                        PropertyTag(label: LocalizedStringKey("op.involution"), color: .white.opacity(0.4))
                    }
                }
                .padding([.horizontal, .bottom])
            }
        }
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(opColor.opacity(expanded ? 0.5 : 0.2), lineWidth: 1))
        .cornerRadius(12)
    }
}

// MARK: - Chord Pill

struct ChordPill: View {
    let chord: Chord
    let color: Color
    let dim: Bool

    var body: some View {
        Text(chord.displayName)
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(dim ? 0.15 : 0.35))
            .cornerRadius(6)
    }
}

// MARK: - Property Tag

struct PropertyTag: View {
    let label: LocalizedStringKey
    let color: Color

    init(label: LocalizedStringKey, color: Color) {
        self.label = label
        self.color = color
    }

    init(label: String, color: Color) {
        self.label = LocalizedStringKey(label)
        self.color = color
    }

    var body: some View {
        Text(label)
            .font(.caption2)
            .foregroundColor(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(color, lineWidth: 1))
            .cornerRadius(5)
    }
}

// MARK: - Voice Movement Diagram

struct VoiceMovementView: View {
    let op: NRTOperation
    let from: Chord
    let to: Chord
    let color: Color

    private var fromNotes: [Int] { from.midiNotes.map { Int($0) % 12 } }
    private var toNotes: [Int] { to.midiNotes.map { Int($0) % 12 } }

    private func noteName(_ pc: Int) -> String { Chord.noteNames[pc] }

    var body: some View {
        HStack(spacing: 0) {
            // From column
            VStack(spacing: 6) {
                ForEach(fromNotes.reversed(), id: \.self) { pc in
                    Text(noteName(pc))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(movedNote(pc) ? color : .white.opacity(0.5))
                        .frame(width: 32, height: 24, alignment: .trailing)
                }
            }

            // Arrow column
            VStack(spacing: 6) {
                ForEach(fromNotes.reversed(), id: \.self) { pc in
                    if movedNote(pc) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(color)
                            .frame(width: 28, height: 24)
                    } else {
                        Image(systemName: "minus")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.2))
                            .frame(width: 28, height: 24)
                    }
                }
            }

            // To column
            VStack(spacing: 6) {
                ForEach(toNotes.reversed(), id: \.self) { pc in
                    Text(noteName(pc))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(movedNote(pc) ? color : .white.opacity(0.5))
                        .frame(width: 32, height: 24, alignment: .leading)
                }
            }

            Spacer()

            // Semitone cost
            VStack(alignment: .trailing, spacing: 2) {
                Text(LocalizedStringKey("op.total_movement"))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                Text("\(op.semitonesDisplaced) st")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
    }

    private func movedNote(_ pc: Int) -> Bool {
        !toNotes.contains(pc)
    }
}

// MARK: - Cycle / Region Row (static, no audio)

struct CycleRow: View {
    let label: String
    let chords: [Chord]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(color)

            HStack(spacing: 6) {
                ForEach(chords) { chord in
                    Text(chord.displayName)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(chord.mode == .major ? color.opacity(0.22) : color.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.35), lineWidth: 1))
                        .cornerRadius(7)
                }
            }
            .padding(.horizontal, 1)
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }
}

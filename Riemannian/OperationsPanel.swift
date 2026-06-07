import SwiftUI

struct OperationsPanel: View {
    let selectedChord: Chord?
    @ObservedObject var audio: AudioEngine
    @Binding var navigateTo: Chord?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let chord = selectedChord {
                HStack {
                    Text(chord.displayName)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    Spacer()
                    MembershipBadges(chord: chord)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(NRTOperation.allCases, id: \.self) { op in
                        let target = op.apply(to: chord)
                        OperationButton(operation: op, target: target) {
                            navigateTo = target
                            audio.transitionToChord(target)
                        }
                    }
                }
            } else {
                Text(LocalizedStringKey("panel.hint"))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
    }
}

// MARK: - Operation Button

struct OperationButton: View {
    let operation: NRTOperation
    let target: Chord
    let onTap: () -> Void

    private var opColor: Color {
        switch operation {
        case .L: return .orange
        case .P: return .green
        case .R: return .blue
        case .N: return .purple
        case .H: return .red
        case .S: return .cyan
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text(operation.rawValue)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(opColor)
                Text(target.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                Text("±\(operation.semitonesDisplaced)st")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(opColor.opacity(0.13))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(opColor.opacity(0.45), lineWidth: 1))
            .cornerRadius(10)
        }
    }
}

// MARK: - Membership Badges

struct MembershipBadges: View {
    let chord: Chord

    var body: some View {
        HStack(spacing: 6) {
            let cycles = HexatonicCycle.all.filter { $0.contains(chord) }
            let regions = WeitzmannRegion.all.filter { $0.contains(chord) }

            ForEach(cycles) { cycle in
                Text(cycle.name)
                    .font(.caption2)
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(6)
            }
            ForEach(regions) { region in
                Text(region.name)
                    .font(.caption2)
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.1))
                    .cornerRadius(6)
            }
        }
    }
}

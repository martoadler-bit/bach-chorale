import SwiftUI

// MARK: - Theory View

struct TheoryView: View {
    @State private var selectedSection: TheorySection = .voiceLeading

    var body: some View {
        NavigationView {
            List {
                ForEach(TheorySection.allCases) { section in
                    NavigationLink(destination: TheorySectionView(section: section)) {
                        HStack(spacing: 12) {
                            Image(systemName: section.icon)
                                .foregroundColor(section.color)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                    .font(.headline)
                                Text(section.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Chorale Theory")
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Sections

enum TheorySection: String, CaseIterable, Identifiable {
    case voiceLeading = "voice_leading"
    case ranges       = "ranges"
    case parallels    = "parallels"
    case cadences     = "cadences"
    case figuredBass  = "figured_bass"
    case harmony      = "harmony"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voiceLeading: return String(localized: "theory.section.voiceLeading.title")
        case .ranges:       return String(localized: "theory.section.ranges.title")
        case .parallels:    return String(localized: "theory.section.parallels.title")
        case .cadences:     return String(localized: "theory.section.cadences.title")
        case .figuredBass:  return String(localized: "theory.section.figuredBass.title")
        case .harmony:      return String(localized: "theory.section.harmony.title")
        }
    }

    var subtitle: String {
        switch self {
        case .voiceLeading: return String(localized: "theory.section.voiceLeading.subtitle")
        case .ranges:       return String(localized: "theory.section.ranges.subtitle")
        case .parallels:    return String(localized: "theory.section.parallels.subtitle")
        case .cadences:     return String(localized: "theory.section.cadences.subtitle")
        case .figuredBass:  return String(localized: "theory.section.figuredBass.subtitle")
        case .harmony:      return String(localized: "theory.section.harmony.subtitle")
        }
    }

    var icon: String {
        switch self {
        case .voiceLeading: return "arrow.up.and.down"
        case .ranges:       return "waveform"
        case .parallels:    return "exclamationmark.triangle"
        case .cadences:     return "flag.checkered"
        case .figuredBass:  return "textformat.123"
        case .harmony:      return "circle.grid.3x3"
        }
    }

    var color: Color {
        switch self {
        case .voiceLeading: return .blue
        case .ranges:       return .green
        case .parallels:    return .red
        case .cadences:     return .orange
        case .figuredBass:  return .purple
        case .harmony:      return .teal
        }
    }
}

// MARK: - Section content

struct TheorySectionView: View {
    let section: TheorySection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(sectionCards(section), id: \.title) { card in
                    TheoryCard(card: card)
                }
            }
            .padding()
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    func sectionCards(_ s: TheorySection) -> [TheoryCard.Model] {
        switch s {
        case .voiceLeading:
            return [
                .init(title: "Contrary motion",
                      body: "When the bass ascends, the upper voices should tend to descend, and vice versa. This creates independence between the parts and avoids parallel sounds.",
                      example: "If the bass moves from G to C (↑5th), the soprano should descend."),
                .init(title: "Stepwise motion",
                      body: "Bach prefers each voice to move as little as possible: a semitone or a whole tone. Large leaps are possible but must resolve in the opposite direction.",
                      example: "A 6th leap in the alto should be followed by descending motion."),
                .init(title: "Leading tone",
                      body: "The leading tone (7th degree) must always resolve to the tonic. Never double the leading tone between two voices.",
                      example: "In C major, B must ascend to C."),
                .init(title: "Voice crossing",
                      body: "Voices must never cross: soprano > alto > tenor > bass at all times. If a crossing occurs, the result sounds confused and unnatural.",
                      example: "The alto must NOT rise above the soprano."),
            ]

        case .ranges:
            return [
                .init(title: "Soprano",
                      body: "C4 to G5. Highest voice, carries the main melody.",
                      example: "MIDI 60–79"),
                .init(title: "Alto",
                      body: "F3 to C5. Harmonizes below the soprano.",
                      example: "MIDI 53–72"),
                .init(title: "Tenor",
                      body: "C3 to G4. High male voice, written in treble clef transposed down an octave.",
                      example: "MIDI 48–67"),
                .init(title: "Bass",
                      body: "E2 to C4. Determines the harmony and harmonic movement.",
                      example: "MIDI 40–60"),
            ]

        case .parallels:
            return [
                .init(title: "Parallel fifths",
                      body: "Two voices moving in parallel with a perfect fifth interval produce an empty, organum-like sound. Bach almost always avoids them.",
                      example: "G–D → A–E (both voices rising a 2nd) = parallel fifths"),
                .init(title: "Parallel octaves",
                      body: "Two voices doubling at the octave in parallel motion reduce the texture to 3 independent voices. Always avoid.",
                      example: "C–G → D–A (soprano and bass in parallel) = parallel octaves"),
                .init(title: "Horn fifths",
                      body: "Occur when two voices reach a fifth by direct motion (both moving in the same direction). Allowed in the inner voices; dangerous in soprano–bass.",
                      example: "Upper voice leaps to a fifth while the bass moves in parallel."),
            ]

        case .cadences:
            return [
                .init(title: "Perfect authentic cadence",
                      body: "V → I with the tonic in the soprano. The most conclusive cadence type. Bach uses it at the end of every chorale.",
                      example: "G7 → C, soprano ends on C"),
                .init(title: "Imperfect authentic cadence",
                      body: "V → I but without the tonic in the soprano, or with inverted chords. Less conclusive, used at internal cadences.",
                      example: "G → C with E in the soprano"),
                .init(title: "Plagal cadence",
                      body: "IV → I ('Amen'). Used as confirmation at the end of an already-concluded section.",
                      example: "F → C in C major"),
                .init(title: "Deceptive cadence",
                      body: "V → VI instead of V → I. The ear expects the tonic but receives VI, creating surprise and continuation.",
                      example: "G7 → Am in C major"),
                .init(title: "Half cadence",
                      body: "Ends on the V chord. Creates tension requiring continuation.",
                      example: "I → V at the end of a half-phrase"),
            ]

        case .figuredBass:
            return [
                .init(title: "Roman numerals",
                      body: "I II III IV V VI VII represent the scale degrees. Uppercase = major chord, lowercase = minor. ° = diminished.",
                      example: "C major: I=C, ii=Dm, iii=Em, IV=F, V=G, vi=Am, vii°=B dim"),
                .init(title: "Inversions",
                      body: "⁶ = first inversion (third in the bass). ⁶₄ = second inversion (fifth in the bass).",
                      example: "I⁶ = C chord with E in the bass"),
                .init(title: "V7 and dominant",
                      body: "The V7 adds the seventh to the dominant chord, creating greater tension toward the tonic.",
                      example: "G7 in C major: G–B–D–F → resolves to C–E–G"),
                .init(title: "Secondary dominant",
                      body: "V/V = dominant of the dominant. Creates a passing modulation to degree V before resolving.",
                      example: "In C major: D7 (V/V) → G (V) → C (I)"),
            ]

        case .harmony:
            return [
                .init(title: "Tonic function",
                      body: "The I chord (and also III and VI) represents stability and rest. Phrases begin and end here.",
                      example: "I, iii, vi"),
                .init(title: "Dominant function",
                      body: "V and VII create tension that 'wants' to resolve to the tonic. They are the chords of greatest tension.",
                      example: "V, V7, vii°"),
                .init(title: "Subdominant function",
                      body: "IV and II prepare the dominant. They create harmonic motion toward the tension.",
                      example: "IV, ii, ii7"),
                .init(title: "Typical Bach progressions",
                      body: "Bach frequently uses: I–IV–V–I (basic), I–vi–IV–V–I (extended), ii–V7–I (cadential), I–V–vi–IV (descending).",
                      example: "The ii–V7–I cadence is the most characteristic of the chorales."),
            ]
        }
    }
}

// MARK: - Card

struct TheoryCard: View {
    struct Model {
        let title: String
        let body: String
        let example: String
    }

    let card: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.headline)
            Text(card.body)
                .font(.body)
                .foregroundColor(.primary)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "music.quarternote.3")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .padding(.top, 1)
                Text(card.example)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.06))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

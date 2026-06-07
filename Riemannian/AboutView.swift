import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    appSection
                    referencesSection
                    creditsSection
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle(Text(LocalizedStringKey("about.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("settings.done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - App

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image("AppIcon-1024")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .cornerRadius(14)

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey("app.title"))
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text(LocalizedStringKey("about.version"))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.45))
                }
            }

            Text(LocalizedStringKey("about.description"))
                .font(.callout)
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Academic References

    private var referencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("about.refs.title"))
                .font(.title3.bold())
                .foregroundColor(.white)

            ForEach(references, id: \.author) { ref in
                ReferenceCard(ref: ref)
            }
        }
    }

    // MARK: - Credits

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey("about.credits.title"))
                .font(.title3.bold())
                .foregroundColor(.white)

            CreditRow(
                name: "GeneralUser GS",
                detail: LocalizedStringKey("about.credits.sf2"),
                url: "https://schristiancollins.com/generaluser.php"
            )
        }
    }
}

// MARK: - Reference data

struct Reference {
    let author: String
    let year: String
    let title: String
    let source: String
}

private let references: [Reference] = [
    Reference(
        author: "Hugo Riemann",
        year: "1893",
        title: "Vereinfachte Harmonielehre",
        source: "Original formulation of harmonic functions and transformational ideas."
    ),
    Reference(
        author: "David Lewin",
        year: "1987",
        title: "Generalized Musical Intervals and Transformations",
        source: "Yale University Press. Foundation of transformational theory and the GIS framework."
    ),
    Reference(
        author: "Richard Cohn",
        year: "1996",
        title: "Maximally Smooth Cycles, Hexatonic Systems, and the Analysis of Late-Romantic Triadic Progressions",
        source: "Music Analysis, 15(1), 9–40."
    ),
    Reference(
        author: "Richard Cohn",
        year: "1997",
        title: "Neo-Riemannian Operations, Parsimonious Trichords, and Their Tonnetz Representations",
        source: "Journal of Music Theory, 41(1), 1–66."
    ),
    Reference(
        author: "Jack Douthett & Peter Steinbach",
        year: "1998",
        title: "Parsimonious Graphs: A Study in Parsimony, Contextual Transformations, and Modes of Limited Transposition",
        source: "Journal of Music Theory, 42(2), 241–263. Introduces the Cube Dance."
    ),
    Reference(
        author: "Carl Friedrich Weitzmann",
        year: "1853",
        title: "Der übermässige Dreiklang",
        source: "Berlin. First systematic analysis of the augmented triad and its voice-leading neighbors."
    ),
]

// MARK: - Reference Card

struct ReferenceCard: View {
    let ref: Reference

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ref.year)
                    .font(.caption.bold())
                    .foregroundColor(.yellow)
                    .frame(width: 36, alignment: .leading)
                Text(ref.author)
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
            Text(ref.title)
                .font(.caption)
                .italic()
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 42)
            Text(ref.source)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 42)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

// MARK: - Credit Row

struct CreditRow: View {
    let name: String
    let detail: LocalizedStringKey
    let url: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "music.note.list")
                .foregroundColor(.yellow)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Link(url, destination: URL(string: url)!)
                    .font(.caption2)
                    .foregroundColor(.cyan)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

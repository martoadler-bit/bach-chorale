import SwiftUI
import Foundation

// MARK: - Library Entry

struct LibraryChoraleEntry: Identifiable {
    let id = UUID()
    let title: String
    let keyRoot: Int
    let isMinor: Bool
    let tempo: Int
    let pickupBeats: Double
    let soprano: [(Double, UInt8, Double)]
    let alto:    [(Double, UInt8, Double)]
    let tenor:   [(Double, UInt8, Double)]
    let bass:    [(Double, UInt8, Double)]
    // Pre-computed chord labels from music21 (nil → computed on the fly)
    let precomputedLabels: [ChordLabel]?

    func toChoraleData() -> ChoraleData {
        func toChoralNotes(_ raw: [(Double, UInt8, Double)]) -> [ChoralNote] {
            raw.map { ChoralNote(midiNote: $0.1, beatPosition: $0.0, duration: $0.2) }
        }
        let sopNotes   = toChoralNotes(soprano)
        let bassNotes  = toChoralNotes(bass)
        let altoNotes  = toChoralNotes(alto)
        let tenorNotes = toChoralNotes(tenor)

        // Correct relative-minor misdetection: final bass note is almost always the tonic.
        let finalBassPC = bassNotes.last.map { Int($0.midiNote) % 12 } ?? keyRoot
        var resolvedRoot  = keyRoot
        var resolvedMinor = isMinor
        if isMinor && finalBassPC != keyRoot {
            let relativeMajor = (keyRoot + 3) % 12
            if finalBassPC == relativeMajor {
                resolvedRoot  = relativeMajor
                resolvedMinor = false
            }
        }

        let totalBeats   = sopNotes.last.map { $0.beatPosition + $0.duration } ?? 0
        let fullMeasures = Int(ceil((totalBeats - pickupBeats) / 4.0))
        let measures     = max(1, fullMeasures) + (pickupBeats > 0 ? 1 : 0)

        let labels: [ChordLabel]
        if let pre = precomputedLabels, !pre.isEmpty {
            labels = pre
        } else {
            labels = BachHarmonizer.chordLabels(
                bass: bassNotes, soprano: sopNotes,
                alto: altoNotes, tenor: tenorNotes,
                keyRoot: resolvedRoot, isMinor: resolvedMinor
            )
        }

        return ChoraleData(
            soprano: sopNotes, alto: altoNotes,
            tenor: tenorNotes, bass: bassNotes,
            tempo: tempo, keyRoot: resolvedRoot, isMinor: resolvedMinor,
            measuresCount: measures, chordLabels: labels,
            fermataBeats: [], pickupBeats: pickupBeats
        )
    }
}

// MARK: - Library Data

// 4 voces reales de J.S. Bach (†1750) — dominio público.
// Extraídas con music21 del corpus musicológico de Bach.
struct BachChoraleLibrary {
    static let chorales: [LibraryChoraleEntry] = loadFromBundle()

    private static let titles: [String: String] = [
        "BWV 1.6": "Wie schön leuchtet der Morgenstern",
        "BWV 10.7": "Meine Seel erhebt den Herren",
        "BWV 101.7": "Nimm von uns, Herr",
        "BWV 102.7": "Wo soll ich fliehen hin",
        "BWV 103.6": "Ich bin ja, Herr, in deiner Macht",
        "BWV 108.6": "Herr Jesu Christ, du höchstes Gut",
        "BWV 109.7": "Ich glaub, lieber Herr",
        "BWV 111.6": "Was mein Gott will, das gscheh allzeit",
        "BWV 112.5": "Der Herr ist mein getreuer Hirt",
        "BWV 114.7": "Wo Gott der Herr nicht bei uns hält",
        "BWV 116.6": "Du Friedefürst, Herr Jesu Christ",
        "BWV 117.9": "Sei Lob und Ehr dem höchsten Gut",
        "BWV 119.9": "Nun lob, mein Seel, den Herren",
        "BWV 120.6": "Nun danket alle Gott",
        "BWV 121.6": "Christum wir sollen loben schon",
        "BWV 122.6": "Das neugeborne Kindelein",
        "BWV 123.6": "Liebster Immanuel",
        "BWV 124.6": "Meinen Jesum lass ich nicht",
        "BWV 125.6": "Mit Fried und Freud ich fahr dahin",
        "BWV 126.6": "Erhalt uns, Herr, bei deinem Wort",
        "BWV 127.5": "Herr Jesu Christ, wahr Mensch und Gott",
        "BWV 128.5": "Auf Christi Himmelfahrt allein",
        "BWV 129.5": "Gelobet sei der Herr, mein Gott",
        "BWV 13.6": "Meine Seufzer, meine Tränen",
        "BWV 130.6": "Herr Gott, dich loben alle wir",
        "BWV 133.6": "Ich freue mich in dir",
        "BWV 135.6": "Ach Herr, mich armen Sünder",
        "BWV 136.6": "Wo soll ich fliehen hin (var.)",
        "BWV 137.5": "Lobe den Herren, den mächtigen König",
        "BWV 139.6": "Wohl dem, der sich auf seinen Gott",
        "BWV 14.5": "Wär Gott nicht mit uns diese Zeit",
        "BWV 144.3": "Nimm, was dein ist, und gehe hin",
        "BWV 144.6": "Was Gott tut, das ist wohlgetan",
        "BWV 148.6": "Ach, lieben Christen, seid getrost",
        "BWV 151.5": "Lobt Gott, ihr Christen allzugleich",
        "BWV 153.1": "Schau, lieber Gott, wie meine Feind",
        "BWV 153.5": "Herzlich tut mich verlangen",
        "BWV 155.5": "Wo Gott der Herr nicht bei uns hält (var.)",
        "BWV 156.6": "Herr, wie du willst, so schicks mit mir",
        "BWV 157.5": "Herzlich lieb hab ich dich, o Herr",
        "BWV 159.5": "Jesu, deine Passion",
        "BWV 16.6": "Uns ist ein Kind geboren",
        "BWV 161.6": "Herzlich tut mich verlangen (var.)",
        "BWV 162.6": "Jesu, meine Freude",
        "BWV 164.6": "Ihr Gestirn, ihr hohlen Lüfte",
        "BWV 165.6": "Jesu, der du meine Seele",
        "BWV 168.6": "Lobt Gott, ihr Christen (var.)",
        "BWV 172.6": "Wie schön leuchtet (var.)",
        "BWV 174.5": "Herzlich lieb hab ich dich (var.)",
        "BWV 175.7": "Komm, Heiliger Geist, Herre Gott",
        "BWV 177.5": "Ich ruf zu dir, Herr Jesu Christ",
        "BWV 178.7": "Wo Gott der Herr nicht bei uns (var.)",
        "BWV 179.6": "Ich armer Mensch, ich armer Sünder",
        "BWV 18.5": "Durch Adams Fall ist ganz verderbt",
        "BWV 180.7": "Schmücke dich, o liebe Seele",
        "BWV 183.5": "Du Lebensfürst, Herr Jesu Christ",
        "BWV 185.6": "O Gott, du frommer Gott",
        "BWV 187.7": "Singen wir aus Herzens Grund",
        "BWV 19.7": "Fürchtet euch nicht",
        "BWV 190.7": "Jesu, nun sei gepreiset",
        "BWV 192.3": "Nun danket alle Gott (var.)",
        "BWV 2.6": "Ach Gott, vom Himmel sieh darein",
        "BWV 20.11": "O Ewigkeit, du Donnerwort",
        "BWV 20.7": "O Ewigkeit, du Donnerwort (var.)",
        "BWV 226.2": "Komm, Jesu, komm",
        "BWV 227.1": "Jesu, meine Freude (I)",
        "BWV 227.11": "Jesu, meine Freude (XI)",
        "BWV 227.3": "Jesu, meine Freude (III)",
        "BWV 227.5": "Jesu, meine Freude (V)",
        "BWV 227.7": "Jesu, meine Freude (VII)",
        "BWV 228": "Fürchte dich nicht",
        "BWV 244.10": "Herzliebster Jesu — Pasión S. Mateo",
        "BWV 244.15": "O Welt, sieh hier dein Leben",
        "BWV 244.17": "Herzlich tut mich verlangen — S. Mateo",
        "BWV 244.25": "O Haupt voll Blut und Wunden",
        "BWV 244.32": "Befiehl du deine Wege",
        "BWV 244.37": "O Haupt voll Blut (var.)",
        "BWV 244.40": "Wenn ich einmal soll scheiden",
        "BWV 244.44": "Bin ich gleich von dir gewichen",
        "BWV 244.54": "O Haupt voll Blut (cadencia final)",
        "BWV 244.62": "O Haupt voll Blut (cierre)",
        "BWV 245.11": "Herzliebster Jesu — Pasión S. Juan",
        "BWV 245.14": "O große Lieb, o Lieb ohn alle Maße",
        "BWV 245.26": "Jesu Kreuz, Leiden und Pein",
        "BWV 245.28": "In meines Herzens Grunde",
        "BWV 245.37": "Dein Will gescheh, Herr Gott",
        "BWV 245.40": "Ach Herr, lass dein lieb Engelein",
        "BWV 248.12": "Vom Himmel hoch da komm ich her",
        "BWV 248.17": "Schaut hin, dort liegt im finstern Stall",
        "BWV 248.23": "Wir Christenleut habn jetzund Freud",
        "BWV 248.28": "Dies ist der Tag, den Gott gemacht",
        "BWV 248.33": "Hilf, Herr Jesu, lass gelingen",
        "BWV 248.35": "Ich steh an deiner Krippen hier",
        "BWV 248.42": "Jesu, du mein liebstes Leben",
        "BWV 248.46": "In dulci jubilo",
        "BWV 248.53": "Nun seid ihr wohl gerochen",
        "BWV 248.59": "Ich freue mich in dir (var.)",
        "BWV 248.64": "Jesus richte mein Beginnen",
        "BWV 253": "Ach Gott, vom Himmel sieh darein",
        "BWV 255": "Ach lieben Christen, seid getrost",
        "BWV 260": "Allein Gott in der Höh sei Ehr",
        "BWV 277": "Christus, der ist mein Leben",
        "BWV 292": "Ein feste Burg ist unser Gott",
        "BWV 299": "Es wird schier der letzte Tag herkommen",
        "BWV 302": "Geist und Seele wird verwirret",
        "BWV 368": "Nun ruhen alle Wälder",
        "BWV 369": "O Gott, du frommer Gott",
        "BWV 370": "O Haupt voll Blut und Wunden (var.)",
        "BWV 386": "Nun danket alle Gott (completo)",
        "BWV 394": "Was Gott tut, das ist wohlgetan (var.)",
        "BWV 416": "Werde munter, mein Gemüte",
        "BWV 434": "Wer nur den lieben Gott lässt walten",
        "BWV 436": "Wie schön leuchtet der Morgenstern (var.)",
    ]

    private static func loadFromBundle() -> [LibraryChoraleEntry] {
        guard let url = Bundle.main.url(forResource: "bach_chorales", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        let noteNames = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]

        func bwvSortKey(_ title: String) -> Double {
            // Extract numeric part from "BWV 244.10 …" → 244.10
            let s = title.components(separatedBy: " ").first(where: { Double($0) != nil }) ?? "0"
            return Double(s) ?? 0
        }

        return raw.compactMap { entry in
            guard let bwv = entry["b"] as? String,
                  let k   = entry["k"] as? Int,
                  let m   = entry["m"] as? Bool,
                  let t   = entry["t"] as? Int,
                  let sRaw = entry["s"] as? [[Double]],
                  let aRaw = entry["a"] as? [[Double]],
                  let nRaw = entry["n"] as? [[Double]],
                  let lRaw = entry["l"] as? [[Double]]
            else { return nil }
            let pickup = entry["p"] as? Double ?? 0.0

            func parse(_ arr: [[Double]]) -> [(Double, UInt8, Double)] {
                arr.compactMap { r in
                    guard r.count == 3 else { return nil }
                    return (r[0], UInt8(clamping: Int(r[1])), r[2])
                }
            }

            let known = titles[bwv] ?? ""
            let keyStr = noteNames[k] + (m ? "m" : "")
            let title = known.isEmpty ? "Coral \(bwv) — \(keyStr)" : "\(known) (\(bwv))"

            // Parse pre-computed chord labels from music21 (field "cl"), if present
            var preLabels: [ChordLabel]? = nil
            if let clRaw = entry["cl"] as? [[String: Any]] {
                let parsed = clRaw.compactMap { d -> ChordLabel? in
                    guard let beat = d["b"] as? Double,
                          let label = d["l"] as? String,
                          let rn    = d["rn"] as? String
                    else { return nil }
                    return ChordLabel(beatPosition: beat, label: label, romanNumeral: rn)
                }
                if !parsed.isEmpty { preLabels = parsed }
            }

            return LibraryChoraleEntry(
                title: title, keyRoot: k, isMinor: m, tempo: t, pickupBeats: pickup,
                soprano: parse(sRaw), alto: parse(aRaw),
                tenor: parse(nRaw), bass: parse(lRaw),
                precomputedLabels: preLabels
            )
        }
        .sorted { bwvSortKey($0.title) < bwvSortKey($1.title) }
    }
}

// MARK: - LibraryView

struct LibraryView: View {
    @ObservedObject var vm: ChoraleViewModel
    @Binding var selectedTab: Int
    @ObservedObject private var userStore = UserChoraleStore.shared
    @State private var selectedEntry: LibraryChoraleEntry? = nil
    @State private var choraleData: ChoraleData? = nil
    @State private var isLoading = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationView {
            List {
                if !userStore.entries.isEmpty {
                    Section("My Chorales") {
                        ForEach(userStore.entries.sorted { $0.date > $1.date }) { entry in
                            Button {
                                vm.chorale = entry.chorale
                                vm.sopranоNotes = entry.sopranoNotes
                                vm.keyRoot = entry.chorale.keyRoot
                                vm.isMinor = entry.chorale.isMinor
                                vm.tempo = entry.chorale.tempo
                                vm.choraleOrigin = entry.sopranoNotes.isEmpty ? .generated : .fromSoprano
                                selectedTab = 2
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(dateFormatter.string(from: entry.date))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { offsets in
                            let sorted = userStore.entries.sorted { $0.date > $1.date }
                            for i in offsets {
                                userStore.delete(sorted[i])
                            }
                        }
                    }
                }

                Section("Bach Library") {
                    ForEach(BachChoraleLibrary.chorales) { entry in
                        Button {
                            loadChorale(entry)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    let noteNames = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
                                    Text("\(noteNames[entry.keyRoot])\(entry.isMinor ? "m" : "") · \(entry.tempo) bpm")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedEntry?.id == entry.id && isLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "music.note")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .sheet(item: $choraleData) { data in
                LibraryChoraleDetailView(chorale: data)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func loadChorale(_ entry: LibraryChoraleEntry) {
        selectedEntry = entry
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let data = entry.toChoraleData()
            DispatchQueue.main.async {
                isLoading = false
                choraleData = data
            }
        }
    }
}

// MARK: - Make ChoraleData Identifiable for sheet presentation

extension ChoraleData: Identifiable {
    public var id: Int { soprano.count ^ alto.count ^ tenor.count ^ bass.count ^ tempo ^ keyRoot }
}

// MARK: - Detail view (score + piano roll + playback)

struct LibraryChoraleDetailView: View {
    let chorale: ChoraleData
    @StateObject private var player = ChoralePlayer()
    @State private var displayMode: ScoreDisplayMode = .score
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $displayMode) {
                    ForEach(ScoreDisplayMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)

                Group {
                    if displayMode == .score {
                        ChoraleScoreRepresentable(chorale: chorale, currentBeat: player.currentBeat, mutedVoices: player.mutedVoices)
                    } else {
                        ChoraleRollView(chorale: chorale, currentBeat: player.currentBeat, mutedVoices: player.mutedVoices)
                    }
                }

                MixerView(player: player)

                HStack(spacing: 16) {
                    Button {
                        if player.isPlaying { player.stop() }
                        else {
                            player.play(chorale: chorale,
                                        onBeat: { b in player.currentBeat = b },
                                        onFinish: { })
                        }
                    } label: {
                        Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)

                    Picker("", selection: $player.sound) {
                        ForEach(ChoraleSound.allCases) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 130)

                    Spacer()
                    Text("\(chorale.tempo) bpm")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .navigationTitle(keyLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { player.stop(); dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var keyLabel: String {
        let noteNames = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
        return "\(noteNames[chorale.keyRoot])\(chorale.isMinor ? "m" : "")"
    }
}

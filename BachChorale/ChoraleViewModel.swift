import SwiftUI
import Combine

enum ChoraleOrigin { case none, fromSoprano, generated }

class ChoraleViewModel: ObservableObject {
    @Published var sopranоNotes: [MelodyNote] = []
    @Published var chorale: ChoraleData = ChoraleData()
    @Published var keyRoot: Int = 0
    @Published var isMinor: Bool = false
    @Published var tempo: Int = 72
    @Published var measuresCount: Int = 4
    @Published var isHarmonizing: Bool = false
    @Published var choraleOrigin: ChoraleOrigin = .none

    func harmonizeSoprano(completion: (() -> Void)? = nil) {
        guard !sopranоNotes.isEmpty else { return }
        isHarmonizing = true
        let notes = sopranоNotes
        let kr = keyRoot; let min = isMinor; let t = tempo
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var result = BachHarmonizer.harmonize(soprano: notes, keyRoot: kr, isMinor: min, tempo: t)
            // Propagate explicit ties from the user's score into the chorale soprano
            result.soprano = result.soprano.enumerated().map { i, cn in
                let mn = notes.first { abs($0.beatPosition - cn.beatPosition) < 0.01 && $0.midiNote == cn.midiNote }
                var out = cn; out.tiedToNext = mn?.tiedToNext ?? false; return out
            }
            DispatchQueue.main.async {
                self?.chorale = result
                self?.choraleOrigin = .fromSoprano
                self?.isHarmonizing = false
                completion?()
            }
        }
    }

    func detectKey() {
        let (root, minor) = BachHarmonizer.detectKey(melody: sopranоNotes)
        keyRoot = root
        isMinor = minor
    }

    func generateFromScratch(completion: (() -> Void)? = nil) {
        isHarmonizing = true
        let kr = keyRoot; let min = isMinor; let t = tempo; let m = measuresCount
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = BachHarmonizer.generate(measuresCount: m, keyRoot: kr, isMinor: min, tempo: t)
            DispatchQueue.main.async {
                self?.chorale = result
                self?.sopranоNotes = result.soprano.map {
                    MelodyNote(midiNote: $0.midiNote, beatPosition: $0.beatPosition, duration: $0.duration)
                }
                self?.choraleOrigin = .generated
                self?.isHarmonizing = false
                completion?()
            }
        }
    }

    func reHarmonize(completion: (() -> Void)? = nil) {
        switch choraleOrigin {
        case .fromSoprano: harmonizeSoprano(completion: completion)
        case .generated:   generateFromScratch(completion: completion)
        case .none: break
        }
    }

    func exportMIDI() -> Data {
        ChoraleMIDIExporter.export(chorale: chorale)
    }
}

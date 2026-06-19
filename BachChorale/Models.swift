import Foundation

// MARK: - MelodyNote (for piano roll soprano input)

struct MelodyNote: Identifiable, Equatable, Codable {
    let id: UUID
    var midiNote: UInt8
    var beatPosition: Double
    var duration: Double
    var tiedToNext: Bool        // user-set tie to the immediately following note
    var isStructural: Bool
    var velocity: UInt8

    init(midiNote: UInt8, beatPosition: Double, duration: Double,
         tiedToNext: Bool = false, isStructural: Bool = false, velocity: UInt8 = 90) {
        self.id = UUID()
        self.midiNote = midiNote
        self.beatPosition = beatPosition
        self.duration = duration
        self.tiedToNext = tiedToNext
        self.isStructural = isStructural
        self.velocity = velocity
    }

    var noteName: String {
        let names = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
        let pc = Int(midiNote) % 12
        let oct = Int(midiNote) / 12 - 1
        return "\(names[pc])\(oct)"
    }
}

// MARK: - Voice

enum Voice: Int, CaseIterable, Identifiable {
    case soprano = 0, alto = 1, tenor = 2, bass = 3

    var id: Int { rawValue }

    var label: String {
        switch self { case .soprano: "S"; case .alto: "A"; case .tenor: "T"; case .bass: "B" }
    }

    var fullName: String {
        switch self { case .soprano: "Soprano"; case .alto: "Alto"; case .tenor: "Tenor"; case .bass: "Bass" }
    }

    // SATB ranges in MIDI
    var midiRange: ClosedRange<UInt8> {
        switch self {
        case .soprano: return 60...79   // C4–G5
        case .alto:    return 53...72   // F3–C5
        case .tenor:   return 48...67   // C3–G4
        case .bass:    return 40...60   // E2–C4
        }
    }

    var color: (r: Double, g: Double, b: Double) {
        switch self {
        case .soprano: return (0.30, 0.70, 1.00)
        case .alto:    return (0.35, 0.80, 0.45)
        case .tenor:   return (0.91, 0.66, 0.29)
        case .bass:    return (0.90, 0.35, 0.35)
        }
    }
}

// MARK: - ChoralNote

struct ChoralNote: Identifiable, Equatable, Codable {
    let id: UUID
    var midiNote: UInt8
    var beatPosition: Double
    var duration: Double
    var tiedToNext: Bool        // propagated from MelodyNote when harmonizing user soprano

    init(midiNote: UInt8, beatPosition: Double, duration: Double, tiedToNext: Bool = false) {
        self.id = UUID()
        self.midiNote = midiNote
        self.beatPosition = beatPosition
        self.duration = duration
        self.tiedToNext = tiedToNext
    }

    var noteName: String {
        let names = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
        let pc = Int(midiNote) % 12
        let oct = Int(midiNote) / 12 - 1
        return "\(names[pc])\(oct)"
    }
}

// MARK: - ChoraleData

struct ChordLabel: Equatable, Codable {
    var beatPosition: Double
    var label: String
    var romanNumeral: String = ""

    /// Roman numeral without inversion or seventh suffixes (e.g. "V65" → "V", "bVII6" → "bVII")
    var degree: String {
        var s = romanNumeral
        // Strip secondary dominant slash target (e.g. "V/V" → "V")
        if let slash = s.firstIndex(of: "/") { s = String(s[s.startIndex..<slash]) }
        // Remove trailing digits and inversion figures
        while let last = s.last, last.isNumber { s.removeLast() }
        // Remove common suffixes: o (dim), ø (half-dim), + (aug) only when followed by digits (already removed)
        return s.isEmpty ? romanNumeral : s
    }
}

struct ChoraleData: Equatable, Codable {
    var soprano: [ChoralNote] = []
    var alto: [ChoralNote] = []
    var tenor: [ChoralNote] = []
    var bass: [ChoralNote] = []
    var tempo: Int = 72
    var keyRoot: Int = 0     // 0=C, 1=C#, ..., 11=B
    var isMinor: Bool = false
    var measuresCount: Int = 4
    var chordLabels: [ChordLabel] = []
    var fermataBeats: [Double] = []   // beat positions where fermatas occur (phrase endings)
    var pickupBeats: Double = 0.0    // anacrusis duration (0 = starts on downbeat)

    func notes(for voice: Voice) -> [ChoralNote] {
        switch voice {
        case .soprano: return soprano
        case .alto:    return alto
        case .tenor:   return tenor
        case .bass:    return bass
        }
    }

    var isEmpty: Bool { soprano.isEmpty && alto.isEmpty }
}

// MARK: - Measure / ChordSlot (for piano roll chord row display)

struct ChordSlot: Identifiable, Equatable {
    let id = UUID()
    var chord: String = ""
    var beats: Int = 0
}

struct Measure: Identifiable {
    let id = UUID()
    var slots: [ChordSlot] = []
    var displayIndex: Int = -1
}

// MARK: - MelodySoundType (for piano roll playback)

enum MelodySoundType: String, CaseIterable, Equatable {
    case uprightPiano = "Upright Piano"
    case grandPiano   = "Grand Piano"
    case organ        = "Organ"

    var midiProgram: UInt8 {
        switch self {
        case .uprightPiano: return 0
        case .grandPiano:   return 0
        case .organ:        return 19
        }
    }

    var sf2Name: String? {
        switch self {
        case .uprightPiano: return "UprightPianoKW-20220221"
        case .grandPiano:   return "GeneralUser-GS"
        case .organ:        return "GeneralUser-GS"
        }
    }
}

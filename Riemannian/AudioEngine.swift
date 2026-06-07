import AVFoundation
import Foundation

// MARK: - Sound Preset

enum SoundPreset: String, CaseIterable, Identifiable {
    case rhodes    = "Rhodes"
    case strings   = "Strings"
    case choir     = "Choir"
    case organ     = "Organ"
    case synthPad  = "Synth Pad"

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .rhodes:   return "sound.rhodes"
        case .strings:  return "sound.strings"
        case .choir:    return "sound.choir"
        case .organ:    return "sound.organ"
        case .synthPad: return "sound.synthpad"
        }
    }

    var midiProgram: UInt8 {
        switch self {
        case .rhodes:   return 4
        case .strings:  return 49   // String Ensemble 2 (48 has bad sample data in GeneralUser-GS)
        case .choir:    return 52
        case .organ:    return 19
        case .synthPad: return 88
        }
    }

    var sfName: String { "GeneralUser-GS" }
}

// MARK: - AudioEngine

class AudioEngine: ObservableObject {
    private var engine = AVAudioEngine()
    private var sampler = AVAudioUnitSampler()

    @Published var currentPreset: SoundPreset = .strings {
        didSet { reloadSoundfont() }
    }

    @Published var activePitchClasses: Set<Int> = []

    private var currentNotes: [UInt8] = []

    init() {
        setupEngine()
    }

    // MARK: - Setup

    private func setupEngine() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)

        // Load soundfont BEFORE starting the engine — this is what prevents the render-thread crash.
        // loadSoundBankInstrument is not thread-safe with an active render callback.
        loadSoundfontIntoSampler(preset: currentPreset)

        try? engine.start()
    }

    // Called only when the preset changes — stops engine, swaps instrument, restarts.
    private func reloadSoundfont() {
        let preset = currentPreset
        stopAllNotes()
        engine.stop()
        loadSoundfontIntoSampler(preset: preset)
        try? engine.start()
    }

    private func loadSoundfontIntoSampler(preset: SoundPreset) {
        guard let url = Bundle.main.url(forResource: preset.sfName, withExtension: "sf2") else {
            print("⚠️ SF2 not found in bundle: \(preset.sfName).sf2")
            return
        }
        let mel = UInt8(kAUSampler_DefaultMelodicBankMSB)
        let lsb = UInt8(kAUSampler_DefaultBankLSB)
        try? sampler.loadSoundBankInstrument(at: url, program: preset.midiProgram,
                                              bankMSB: mel, bankLSB: lsb)
    }

    // MARK: - Pad playback with voice leading

    func transitionToChord(_ chord: Chord, velocity: UInt8 = 72) {
        guard engine.isRunning else { return }

        let newNotes = voiceLead(from: currentNotes, to: chord)
        let oldSet = Set(currentNotes)
        let newSet = Set(newNotes)

        // Start incoming voices first
        for note in newSet.subtracting(oldSet).sorted() {
            sampler.startNote(note, withVelocity: velocity, onChannel: 0)
        }

        // Stop outgoing voices after a brief overlap so there's no gap
        let notesToStop = Array(oldSet.subtracting(newSet))
        let delay: Double = currentPreset == .organ ? 0.01 : 0.07
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            for note in notesToStop { self?.sampler.stopNote(note, onChannel: 0) }
        }

        currentNotes = newNotes
        activePitchClasses = Set(newNotes.map { Int($0) % 12 })
    }

    func stopAll() {
        stopAllNotes()
        activePitchClasses = []
    }

    private func stopAllNotes() {
        for note in currentNotes { sampler.stopNote(note, onChannel: 0) }
        currentNotes = []
    }

    func reactivate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        if !engine.isRunning { try? engine.start() }
    }

    // MARK: - Voice leading

    private func voiceLead(from old: [UInt8], to chord: Chord) -> [UInt8] {
        let intervals: [Int] = chord.mode == .major ? [0, 4, 7] : [0, 3, 7]
        let newPCs = intervals.map { (chord.root + $0) % 12 }

        guard !old.isEmpty else {
            // Initial placement in octave 4 (C4=60), comfortable range for all programs
            return newPCs.map { pc -> UInt8 in
                let n = 60 + pc
                return UInt8(n > 72 ? n - 12 : n)
            }.sorted()
        }

        let centroid = old.map(Int.init).reduce(0, +) / old.count

        return newPCs.map { pc -> UInt8 in
            // Keep common tones at same MIDI note
            if let existing = old.first(where: { Int($0) % 12 == pc }) {
                return existing
            }
            // Find nearest octave to centroid
            var candidates: [Int] = []
            var n = pc
            while n < 36 { n += 12 }
            while n <= 84 { candidates.append(n); n += 12 }
            let best = candidates.min(by: { abs($0 - centroid) < abs($1 - centroid) }) ?? 60
            return UInt8(clamping: best)
        }.sorted()
    }
}

import AVFoundation
import Foundation

// MARK: - Sound preset

enum ChoraleSound: String, CaseIterable, Identifiable {
    case voices  = "voices"
    case organ   = "organ"
    case piano   = "piano"
    case strings = "strings"
    case rhodes  = "rhodes"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .voices:  return String(localized: "sound.voices")
        case .organ:   return String(localized: "sound.organ")
        case .piano:   return String(localized: "sound.piano")
        case .strings: return String(localized: "sound.strings")
        case .rhodes:  return String(localized: "sound.rhodes")
        }
    }

    var midiPrograms: [UInt8] {
        switch self {
        case .voices:  return [52, 52, 52, 52]
        case .organ:   return [19, 19, 19, 19]
        case .piano:   return [0,  0,  0,  0]
        case .strings: return [48, 48, 48, 48]
        case .rhodes:  return [4,  4,  4,  4]
        }
    }

    // How much reverb wetness (0–1) suits this sound
    // How many seconds before the beat to trigger a note-on so slow-attack
    // samples (choir) reach full volume by the time the beat actually lands.
    var attackPreroll: Double {
        switch self {
        case .voices:  return 0.030
        case .organ:   return 0.020
        case .strings: return 0.025
        case .piano:   return 0.000
        case .rhodes:  return 0.000
        }
    }

    var legatoOverlap: Double {
        switch self {
        case .voices:  return 0.040
        case .organ:   return 0.030
        case .strings: return 0.035
        case .piano:   return 0.010
        case .rhodes:  return 0.010
        }
    }

    var reverbMix: Float {
        switch self {
        case .voices:  return 0.18
        case .organ:   return 0.15
        case .strings: return 0.14
        case .piano:   return 0.08
        case .rhodes:  return 0.06
        }
    }
}

// MARK: - ChoralePlayer

class ChoralePlayer: ObservableObject {
    @Published var isPlaying  = false
    @Published var currentBeat: Double = -1.0
    @Published var mutedVoices: Set<Voice> = []
    @Published var sound: ChoraleSound = .voices { didSet { reloadSound() } }

    private let engine    = AVAudioEngine()
    private var samplers: [AVAudioUnitSampler] = []
    private let reverb    = AVAudioUnitReverb()
    private let preMixer  = AVAudioMixerNode()   // combines all 4 samplers before reverb
    private var timerSrc: DispatchSourceTimer?
    private let audioQ = DispatchQueue(label: "com.dlrk.bachchorale.audio", qos: .userInteractive)
    private(set) var engineStarted = false

    init() { configureSession(); setupEngine() }

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setupEngine() {
        // Reverb unit — Cathedral preset works well for choral music
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 18
        engine.attach(reverb)
        engine.attach(preMixer)

        for _ in 0..<4 {
            let s = AVAudioUnitSampler()
            engine.attach(s)
            // All 4 samplers → preMixer (supports multiple inputs)
            engine.connect(s, to: preMixer, format: nil)
            samplers.append(s)
        }
        // preMixer → reverb → mainMixer
        engine.connect(preMixer, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)

        do { try engine.start(); engineStarted = true; reloadSound() }
        catch { print("ChoralePlayer engine: \(error)") }
    }

    private func reloadSound() {
        guard engineStarted else { return }
        let generalURL   = Bundle.main.url(forResource: "GeneralUser-GS",           withExtension: "sf2")
        let florestanURL = Bundle.main.url(forResource: "052_Florestan_Ahh_Choir",  withExtension: "sf2")
        let uprightURL   = Bundle.main.url(forResource: "UprightPianoKW-20220221",  withExtension: "sf2")
        let mel = UInt8(kAUSampler_DefaultMelodicBankMSB)
        let lsb = UInt8(kAUSampler_DefaultBankLSB)
        for (i, s) in samplers.enumerated() {
            let url: URL
            let prog: UInt8
            switch sound {
            case .voices:
                url  = florestanURL ?? generalURL!
                prog = 52
            case .organ:
                url  = generalURL!
                prog = 19
            case .piano:
                url  = uprightURL ?? generalURL!
                prog = 0
            default:
                url  = generalURL!
                prog = sound.midiPrograms[i]
            }
            try? s.loadSoundBankInstrument(at: url, program: prog, bankMSB: mel, bankLSB: lsb)
        }
        reverb.wetDryMix = sound.reverbMix * 100
    }

    func toggleMute(_ voice: Voice) {
        if mutedVoices.contains(voice) { mutedVoices.remove(voice) }
        else {
            mutedVoices.insert(voice)
            let s = samplers[voice.rawValue]; let ch = UInt8(voice.rawValue)
            for n in 0...127 { s.stopNote(UInt8(n), onChannel: ch) }
        }
    }

    // MARK: - Playback

    func play(chorale: ChoraleData,
              onBeat: @escaping (Double) -> Void,
              onFinish: @escaping () -> Void) {
        guard engineStarted else { onFinish(); return }
        stop()
        isPlaying = true

        let beatDur = 60.0 / Double(chorale.tempo)
        typealias Ev = (time: Double, fn: () -> Void)
        var events: [Ev] = []

        // DEBUG: log note layout for all voices
        for (v, vNotes) in [("S", chorale.soprano), ("A", chorale.alto),
                             ("T", chorale.tenor),   ("B", chorale.bass)] {
            let desc = vNotes.map { "\($0.midiNote)@\($0.beatPosition)d\($0.duration)" }.joined(separator: " ")

        }

        let pairs: [(Voice, [ChoralNote])] = [
            (.soprano, chorale.soprano), (.alto, chorale.alto),
            (.tenor,   chorale.tenor),   (.bass, chorale.bass)
        ]


        let fermatas = Set(chorale.fermataBeats)
        // Fermata notes are held 2× their written duration, then a brief pause follows.
        let fermataMult = 2.0
        let fermataGap  = 0.3 * beatDur   // silence between phrase and next

        // Build a time-shift table: events after a fermata slide forward in time.
        // We compute cumulative offset as we walk through the soprano timeline.
        // Map beat position → cumulative offset at that point
        var offsetAtBeat: [(beat: Double, offset: Double)] = [(0, 0)]
        for note in chorale.soprano.sorted(by: { $0.beatPosition < $1.beatPosition }) {
            let beat = note.beatPosition
            let currentOffset = offsetAtBeat.last!.offset
            if fermatas.contains(beat) {
                let extraTime = note.duration * beatDur * (fermataMult - 1.0) + fermataGap
                offsetAtBeat.append((beat + note.duration, currentOffset + extraTime))
            }
        }

        func shiftedTime(_ nominalBeatSeconds: Double) -> Double {
            // Find the largest offset entry whose beat is <= this time
            var off = 0.0
            for entry in offsetAtBeat {
                if entry.beat * beatDur <= nominalBeatSeconds + 0.001 { off = entry.offset }
                else { break }
            }
            return nominalBeatSeconds + off
        }

        // Beat indicator: fire onBeat at every unique beat position across all voices.
        // This ensures glows update even when one voice has a note shorter than another.
        let allBeatPositions = Set(pairs.flatMap { $0.1.map { $0.beatPosition } })
        for beat in allBeatPositions.sorted() {
            let t = shiftedTime(beat * beatDur)
            events.append((max(0, t), { DispatchQueue.main.async { onBeat(beat) } }))
        }

        for (voice, notes) in pairs {
            let smp = samplers[voice.rawValue]
            let ch  = UInt8(voice.rawValue)
            for (i, note) in notes.enumerated() {
                let beatT      = note.beatPosition * beatDur
                // Fermata duration extension only applies to the soprano; inner voices
                // sustain through the fermata gap via the shiftedTime extension below.
                let isFermata  = (voice == .soprano) && fermatas.contains(note.beatPosition)
                let writtenDur = note.duration * beatDur
                // Soprano fermata notes: double the written duration.
                // All other notes: use the real-time span so they sustain through any
                // fermata gap that falls within or after this note.
                let noteEndTime = (note.beatPosition + note.duration) * beatDur
                let soundDur: Double = isFermata
                    ? writtenDur * fermataMult
                    : max(writtenDur, shiftedTime(noteEndTime) - shiftedTime(beatT))

                let onT  = shiftedTime(beatT)
                let beat = note.beatPosition

                let prevNote  = i > 0 ? notes[i - 1] : nil
                let nextNote  = i + 1 < notes.count ? notes[i + 1] : nil
                let nextBeatT = nextNote.map { shiftedTime($0.beatPosition * beatDur) }

                // All voices use the explicit tiedToNext flag — no pitch-matching.
                // For soprano: also break ties at fermata notes (fermata needs a fresh attack).
                let prevIsFermata = (voice == .soprano) && fermatas.contains(prevNote?.beatPosition ?? -99)
                let isTiedFrom = (prevNote?.tiedToNext == true)
                              && (prevNote?.midiNote == note.midiNote)
                              && !prevIsFermata
                let isTieTo    = note.tiedToNext && !isFermata

                if !isTiedFrom {
                    let onTClamped = max(0, onT)
                    events.append((onTClamped, { [weak self] in
                        guard let self else { return }
                        if !self.mutedVoices.contains(voice) {
                            smp.startNote(note.midiNote, withVelocity: 72, onChannel: ch)
                        }
                    }))
                }

                let stopT: Double?
                if isTieTo {
                    stopT = nil
                } else if let nt = nextBeatT {
                    let sameAsNext = nextNote?.midiNote == note.midiNote
                    let isAdjacent = (nt - (shiftedTime(beatT) + soundDur)) < 0.05
                    if !sameAsNext && isAdjacent {
                        // Consecutive different pitch: send NoteOff just after the next NoteOn
                        // so the sampler processes the new attack before releasing the old note.
                        // The old note's release tail blends with the new note's attack.
                        stopT = nt + 0.008
                    } else {
                        // Gap, rest, or repeated pitch: stop at natural note end.
                        stopT = shiftedTime(beatT) + soundDur
                    }
                } else {
                    stopT = shiftedTime(beatT) + soundDur
                }

                if let st = stopT {
                    events.append((st, { smp.stopNote(note.midiNote, onChannel: ch) }))
                }
            }
        }

        // Use the latest actual stop time from all scheduled events to avoid finishing too early
        // (fermatas extend real time beyond nominal beat duration).
        let nominalEnd = (chorale.bass.map { $0.beatPosition + $0.duration }.max() ?? 4) * beatDur
        let total = max(nominalEnd, shiftedTime(nominalEnd))
        events.append((total + 0.5, { [weak self] in
            DispatchQueue.main.async {
                self?.isPlaying   = false
                self?.currentBeat = -1.0
                onFinish()
            }
        }))

        events.sort { $0.time < $1.time }

        var idx = 0
        let t0  = CACurrentMediaTime()

        let src = DispatchSource.makeTimerSource(flags: [], queue: audioQ)
        src.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        src.setEventHandler { [weak self] in
            guard let self, self.isPlaying else { return }
            let now = CACurrentMediaTime() - t0
            while idx < events.count && events[idx].time <= now + 0.006 {
                events[idx].fn()
                idx += 1
            }
        }
        src.resume()
        timerSrc = src
    }

    func stop() {
        timerSrc?.cancel(); timerSrc = nil
        for (i, s) in samplers.enumerated() {
            for n in 0...127 { s.stopNote(UInt8(n), onChannel: UInt8(i)) }
        }
        isPlaying   = false
        currentBeat = -1.0
    }
}

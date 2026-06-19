import AVFoundation
import Foundation

// MARK: - MelodyPlayer
// Reproductor simple de melodía usando AVAudioUnitSampler.
// Compartido entre MelodyReviewView y MelodyBuildView.

class MelodyPlayer: ObservableObject {
    @Published var isPlaying = false
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var workItems: [DispatchWorkItem] = []
    private var isRunning = false
    private let audioQueue = DispatchQueue(label: "com.reharmonizador.melodyplayer", qos: .userInteractive)

    init(sound: MelodySoundType = .uprightPiano) {
        engine.attach(sampler)
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(sampler, to: engine.mainMixerNode, format: format)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
        isRunning = true
        loadSound(sound)
    }

    func loadSound(_ sound: MelodySoundType) {
        let mel = UInt8(kAUSampler_DefaultMelodicBankMSB)
        let lsb = UInt8(kAUSampler_DefaultBankLSB)
        let sf2Name = sound.sf2Name ?? "GeneralUser-GS"
        guard let url = Bundle.main.url(forResource: sf2Name, withExtension: "sf2") else { return }
        try? sampler.loadSoundBankInstrument(at: url, program: sound.midiProgram, bankMSB: mel, bankLSB: lsb)
    }

    func playSingleNote(midiNote: UInt8) {
        guard isRunning else { return }
        sampler.startNote(midiNote, withVelocity: 60, onChannel: 0)
        let item = DispatchWorkItem { [weak self] in self?.sampler.stopNote(midiNote, onChannel: 0) }
        workItems.append(item)
        audioQueue.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    func playMelody(notes: [MelodyNote], bpm: Int,
                    onNoteStart: @escaping (Int) -> Void,
                    onFinish: @escaping () -> Void) {
        guard isRunning, !notes.isEmpty else { onFinish(); return }
        stop()
        DispatchQueue.main.async { self.isPlaying = true }
        let beatDuration = 60.0 / Double(bpm)
        for (i, note) in notes.enumerated() {
            let startTime = note.beatPosition * beatDuration
            let prevNote = i > 0 ? notes[i - 1] : nil
            // Use explicit tiedToNext flag — pitch matching caused unintended sustained notes
            let isTiedFrom = prevNote?.tiedToNext == true && prevNote?.midiNote == note.midiNote
            let isTieTo    = note.tiedToNext
            let noteDuration = note.duration * beatDuration + (isTieTo ? 0.01 : 0.0)

            if !isTiedFrom {
                let startItem = DispatchWorkItem { [weak self] in
                    guard let self = self, self.isRunning else { return }
                    self.sampler.startNote(note.midiNote, withVelocity: 68, onChannel: 0)
                    DispatchQueue.main.async { onNoteStart(i) }
                }
                workItems.append(startItem)
                audioQueue.asyncAfter(deadline: .now() + startTime, execute: startItem)
            } else {
                // Still update highlighted note index for display
                let item = DispatchWorkItem { DispatchQueue.main.async { onNoteStart(i) } }
                workItems.append(item)
                audioQueue.asyncAfter(deadline: .now() + startTime, execute: item)
            }

            if !isTieTo {
                let stopItem = DispatchWorkItem { [weak self] in
                    self?.sampler.stopNote(note.midiNote, onChannel: 0)
                }
                workItems.append(stopItem)
                audioQueue.asyncAfter(deadline: .now() + startTime + noteDuration, execute: stopItem)
            }
        }
        let last = notes.last!
        let total = (last.beatPosition + last.duration) * beatDuration
        let fin = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async { self?.isPlaying = false; onFinish() }
        }
        workItems.append(fin)
        audioQueue.asyncAfter(deadline: .now() + total + 0.15, execute: fin)
    }

    func stop() {
        workItems.forEach { $0.cancel() }
        workItems = []
        for n in 0...127 { sampler.stopNote(UInt8(n), onChannel: 0) }
        DispatchQueue.main.async { self.isPlaying = false }
    }
}

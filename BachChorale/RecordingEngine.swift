import Foundation
import AVFoundation

// MARK: - RecordingEngine

class RecordingEngine: ObservableObject {

    enum RecordingState { case idle, countIn, recording, stopped }

    @Published var state: RecordingState = .idle
    @Published var currentBeat: Double = 0
    @Published var recordedNotes: [MelodyNote] = []

    var bpm: Int = 80
    var totalMeasures: Int = 4
    var onBeat: ((Int) -> Void)?

    // AVAudio for metronome
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var clickBuffer: AVAudioPCMBuffer?
    private let sampleRate: Double = 44100

    // Timing
    private var startTime: CFAbsoluteTime = 0
    private var countInBeats: Int = 4
    private var beatDuration: Double = 0
    private var totalBeats: Int = 0
    private var nextBeatIndex: Int = 0
    private var schedulerTimer: Timer?
    private var beatTimer: Timer?

    // Active notes being held
    private var activeNoteStarts: [UInt8: CFAbsoluteTime] = [:]

    init() {
        setupAudio()
    }

    private func setupAudio() {
        engine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        clickBuffer = makeClickBuffer(format: format)
        try? engine.start()
    }

    private func makeClickBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * 0.015) // 15ms
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buf.frameLength = frameCount
        let ch = buf.floatChannelData![0]
        let freq: Double = 1000
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let envelope = exp(-t / 0.005)
            ch[i] = Float(sin(2 * .pi * freq * t) * envelope * 0.8)
        }
        return buf
    }

    // MARK: - Public API

    func startFreeRecord(bpm: Int, totalMeasures: Int) {
        guard state == .idle || state == .stopped else { return }
        self.bpm = bpm
        self.totalMeasures = totalMeasures
        self.beatDuration = 60.0 / Double(bpm)
        self.totalBeats = totalMeasures * 4
        self.activeNoteStarts = [:]
        self.recordedNotes = []

        state = .countIn
        nextBeatIndex = 0

        if !engine.isRunning { try? engine.start() }
        playerNode.play()

        scheduleBeats()
    }

    func stopRecording() {
        schedulerTimer?.invalidate(); schedulerTimer = nil
        beatTimer?.invalidate(); beatTimer = nil
        playerNode.stop()
        // Release any still-held notes
        let now = CFAbsoluteTimeGetCurrent()
        for (midi, startT) in activeNoteStarts {
            finalizeNote(midi: midi, startT: startT, endT: now)
        }
        activeNoteStarts = [:]
        finalize()
        state = .stopped
    }

    func reset() {
        stopRecording()
        recordedNotes = []
        currentBeat = 0
        state = .idle
    }

    func noteOn(midi: UInt8) {
        guard state == .recording else { return }
        activeNoteStarts[midi] = CFAbsoluteTimeGetCurrent()
    }

    func noteOff(midi: UInt8) {
        guard state == .recording else { return }
        guard let startT = activeNoteStarts[midi] else { return }
        activeNoteStarts.removeValue(forKey: midi)
        finalizeNote(midi: midi, startT: startT, endT: CFAbsoluteTimeGetCurrent())
    }

    // MARK: - Beat scheduling

    private func scheduleBeats() {
        // Schedule clicks using a timer that fires each beat
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: beatDuration, repeats: true) { [weak self] _ in
            self?.fireBeat()
        }
        schedulerTimer?.fire() // immediate first beat
    }

    private func fireBeat() {
        let beatIdx = nextBeatIndex
        nextBeatIndex += 1

        // Play click
        if let buf = clickBuffer {
            playerNode.scheduleBuffer(buf, completionHandler: nil)
        }

        // Notify UI on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onBeat?(beatIdx)
        }

        if state == .countIn {
            let countInTotal = countInBeats
            if beatIdx == countInTotal - 1 {
                // Last count-in beat — start recording after this beat
                let delay = beatDuration
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.beginRecording()
                }
            }
        } else if state == .recording {
            let recordBeat = beatIdx - countInBeats
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.currentBeat = Double(recordBeat)
            }
            // Stop after totalBeats
            if recordBeat >= totalBeats {
                schedulerTimer?.invalidate()
                schedulerTimer = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.stopRecording()
                }
            }
        }
    }

    private func beginRecording() {
        startTime = CFAbsoluteTimeGetCurrent()
        state = .recording
    }

    // MARK: - Note finalization

    private func finalizeNote(midi: UInt8, startT: CFAbsoluteTime, endT: CFAbsoluteTime) {
        let startSec = startT - startTime
        let durSec   = endT - startT
        guard startSec >= 0, durSec > 0.05 else { return }

        var beatPos = startSec / beatDuration
        var dur     = durSec  / beatDuration

        // Quantize to nearest eighth note (0.5 beats)
        beatPos = (beatPos / 0.5).rounded() * 0.5
        dur     = max(0.5, (dur / 0.5).rounded() * 0.5)

        // Clamp to recording window
        let maxBeat = Double(totalBeats)
        guard beatPos < maxBeat else { return }
        dur = min(dur, maxBeat - beatPos)

        let note = MelodyNote(midiNote: midi, beatPosition: beatPos, duration: dur, velocity: 90)
        recordedNotes.append(note)
    }

    private func finalize() {
        recordedNotes.sort { $0.beatPosition < $1.beatPosition }
    }
}

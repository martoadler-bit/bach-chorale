import SwiftUI
import UIKit

// MARK: - Note duration model (up to eighth note)

struct NoteValue: Identifiable, Equatable {
    let id = UUID()
    let smufl: String
    let beats: Double
    let name: String
}

private let noteValues: [NoteValue] = [
    NoteValue(smufl: "\u{E1D2}", beats: 4,   name: "Whole"),
    NoteValue(smufl: "\u{E1D3}", beats: 2,   name: "Half"),
    NoteValue(smufl: "\u{E1D5}", beats: 1,   name: "Quarter"),
    NoteValue(smufl: "\u{E1D7}", beats: 0.5, name: "Eighth"),
]

// MARK: - SopranoInputView

struct SopranoInputView: View {
    @ObservedObject var vm: ChoraleViewModel
    @Binding var selectedTab: Int
    @StateObject private var melodyPlayer = MelodyPlayer()
    @StateObject private var recordingEngine = RecordingEngine()
    @State private var selectedNoteIndex: Int? = nil
    @State private var playingNoteIndex: Int? = nil
    @State private var showKeyPicker = false
    @State private var currentDuration: Double = 1.0
    @State private var constructionMode: ConstructionMode = .stepRecord
    @State private var insertBeat: Double = 0
    @State private var countInDisplay: String = ""

    enum ConstructionMode { case freeRecord, stepRecord }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // ── key row ────────────────────────────────────────────
                HStack(spacing: 12) {
                    Spacer()
                    Button { showKeyPicker = true } label: {
                        HStack(spacing: 4) {
                            Text(keyLabel)
                                .font(.caption.bold())
                                .foregroundColor(.yellow)
                            if vm.keyIsAutoDetected {
                                Text("auto")
                                    .font(.caption2)
                                    .foregroundColor(.yellow.opacity(0.6))
                            }
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.yellow.opacity(0.6))
                        }
                    }
                    Picker("", selection: Binding(
                        get: { vm.isMinor },
                        set: { vm.userSetKey(root: vm.keyRoot, minor: $0) }
                    )) {
                        Text("Major").tag(false); Text("Minor").tag(true)
                    }.pickerStyle(.segmented).frame(width: 120)
                }
                .padding(.horizontal).padding(.vertical, 6)

                // ── mode picker ────────────────────────────────────────
                Picker("", selection: $constructionMode) {
                    Text("Free").tag(ConstructionMode.freeRecord)
                    Text("Step by step").tag(ConstructionMode.stepRecord)
                }.pickerStyle(.segmented)
                .padding(.horizontal, 8).padding(.bottom, 4)
                .onChange(of: constructionMode) { _ in
                    if recordingEngine.state == .recording || recordingEngine.state == .countIn {
                        recordingEngine.stopRecording()
                    }
                }

                // ── rhythm bar for step mode ───────────────────────────
                if constructionMode == .stepRecord {
                    HStack(spacing: 4) {
                        RhythmBar(currentDuration: $currentDuration, useFractionLabels: true, showTieButton: false)
                        Button {
                            if !vm.sopranоNotes.isEmpty {
                                vm.sopranоNotes.removeLast()
                                insertBeat = max(0, insertBeat - currentDuration)
                            }
                        } label: {
                            Text("⌫")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 40, height: 38)
                                .background(Color.white.opacity(0.12))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }.disabled(vm.sopranоNotes.isEmpty)
                    }
                    .padding(.horizontal, 8).padding(.bottom, 4)
                }

                // ── piano roll ─────────────────────────────────────────
                PianoRollRepresentable(
                    notes: $vm.sopranоNotes,
                    totalMeasures: vm.measuresCount,
                    beatsPerMeasure: 4,
                    gridSize: currentDuration,
                    selectedNoteIndex: $selectedNoteIndex,
                    playingNoteIndex: $playingNoteIndex,
                    currentBeat: -1.0,
                    isPlayingMelody: melodyPlayer.isPlaying,
                    measures: [],
                    melodySound: .uprightPiano,
                    midiMin: 57,
                    midiMax: 86,
                    onNotesChanged: { vm.sopranоNotes = $0 },
                    onNoteSelected: { selectedNoteIndex = $0 },
                    cursorBeat: constructionMode == .stepRecord ? insertBeat : -1
                )

                // ── free record controls ───────────────────────────────
                if constructionMode == .freeRecord {
                    freeRecordControls
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }

                // ── piano keyboard ─────────────────────────────────────
                PianoKeyboardRepresentable(
                    onNoteOn:  { midi in handleNoteOn(midi: midi) },
                    onNoteOff: { midi in handleNoteOff(midi: midi) }
                )
                .frame(height: 120)
                .padding(.horizontal, 4)

                // ── bottom bar ─────────────────────────────────────────
                HStack(spacing: 12) {
                    Label("\(vm.measuresCount)", systemImage: "square.grid.3x3")
                        .font(.caption).foregroundColor(.secondary)
                    Stepper("", value: $vm.measuresCount, in: 1...16)
                        .labelsHidden().frame(width: 86)
                    Button {
                        if melodyPlayer.isPlaying {
                            melodyPlayer.stop()
                            playingNoteIndex = nil
                        } else {
                            melodyPlayer.playMelody(
                                notes: vm.sopranоNotes, bpm: max(60, vm.tempo),
                                onNoteStart: { i in playingNoteIndex = i },
                                onFinish: { playingNoteIndex = nil }
                            )
                        }
                    } label: {
                        Image(systemName: melodyPlayer.isPlaying ? "stop.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 34, height: 34)
                            .background(melodyPlayer.isPlaying ? Color.orange : Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .disabled(vm.sopranоNotes.isEmpty)
                    Spacer()
                    Button {
                        melodyPlayer.stop(); playingNoteIndex = nil
                        vm.harmonizeSoprano { selectedTab = 3 }
                    } label: {
                        if vm.isHarmonizing {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Label("Harmonize", systemImage: "waveform.badge.magnifyingglass")
                                .font(.subheadline.bold())
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.sopranоNotes.isEmpty || vm.isHarmonizing)
                }
                .padding(.horizontal).padding(.vertical, 10)
            }
            .navigationTitle("Soprano").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        vm.sopranоNotes = []
                        selectedNoteIndex = nil
                        insertBeat = 0
                        recordingEngine.reset()
                    }
                    .disabled(vm.sopranоNotes.isEmpty)
                }
            }
            .sheet(isPresented: $showKeyPicker) {
                KeyPickerSheet(keyRoot: vm.keyRoot, isMinor: vm.isMinor) { root, minor in
                    vm.userSetKey(root: root, minor: minor)
                }
            }
            .onReceive(recordingEngine.$state) { newState in
                if newState == .stopped {
                    vm.sopranоNotes = recordingEngine.recordedNotes
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Free record controls view

    @ViewBuilder
    private var freeRecordControls: some View {
        HStack(spacing: 12) {
            switch recordingEngine.state {
            case .idle, .stopped:
                Button {
                    recordingEngine.reset()
                    vm.sopranоNotes = []
                    recordingEngine.onBeat = { beatIdx in
                        let countInBeats = 4
                        if beatIdx < countInBeats {
                            countInDisplay = "\(countInBeats - beatIdx)"
                        } else {
                            countInDisplay = ""
                        }
                    }
                    recordingEngine.startFreeRecord(bpm: max(40, vm.tempo), totalMeasures: vm.measuresCount)
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 12, height: 12)
                        Text("Record")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(Color.red.opacity(0.2))
                    .foregroundColor(.red)
                    .cornerRadius(8)
                }

            case .countIn:
                HStack(spacing: 8) {
                    Text("Count: \(countInDisplay)")
                        .font(.title2.bold())
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                    Button {
                        recordingEngine.stopRecording()
                        countInDisplay = ""
                    } label: {
                        Text("Cancel").font(.caption).foregroundColor(.secondary)
                    }
                }

            case .recording:
                Button {
                    recordingEngine.stopRecording()
                    countInDisplay = ""
                } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 12, height: 12)
                        Text("Stop")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(Color.red.opacity(0.3))
                    .foregroundColor(.red)
                    .cornerRadius(8)
                }
                .overlay(alignment: .trailing) {
                    RecordingPulse()
                        .padding(.trailing, 10)
                }
            }
        }
    }

    // MARK: - Note handling

    private func handleNoteOn(midi: UInt8) {
        melodyPlayer.playSingleNote(midiNote: midi)
        switch constructionMode {
        case .freeRecord:
            recordingEngine.noteOn(midi: midi)
        case .stepRecord:
            let maxBeat = Double(vm.measuresCount * 4)
            guard insertBeat < maxBeat else { return }
            let dur = min(currentDuration, maxBeat - insertBeat)
            let note = MelodyNote(midiNote: midi, beatPosition: insertBeat, duration: dur)
            var notes = vm.sopranоNotes
            notes.removeAll { $0.beatPosition >= insertBeat && $0.beatPosition < insertBeat + dur }
            notes.append(note)
            notes.sort { $0.beatPosition < $1.beatPosition }
            vm.sopranоNotes = notes
            insertBeat = min(insertBeat + currentDuration, maxBeat)
        }
    }

    private func handleNoteOff(midi: UInt8) {
        if constructionMode == .freeRecord {
            recordingEngine.noteOff(midi: midi)
        }
    }

    private var keyLabel: String {
        let n = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
        return "\(n[vm.keyRoot]) \(vm.isMinor ? "m" : "")"
    }
}

// MARK: - Recording pulse indicator

private struct RecordingPulse: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .opacity(pulsing ? 0.2 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Rhythm bar

private let fractionLabels = ["1", "1/2", "1/4", "1/8"]

struct RhythmBar: View {
    @Binding var currentDuration: Double
    var useFractionLabels: Bool = false
    var showTieButton: Bool = true
    var onTiePressed: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(noteValues.enumerated()), id: \.element.id) { i, nv in
                Button { currentDuration = nv.beats } label: {
                    Group {
                        if useFractionLabels {
                            Text(fractionLabels[i])
                                .font(.system(size: 14, weight: .semibold))
                        } else {
                            Text(nv.smufl)
                                .font(.custom("Bravura", size: 16))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
                    .background(currentDuration == nv.beats
                                ? Color.yellow : Color.white.opacity(0.12))
                    .foregroundColor(currentDuration == nv.beats ? .black : .white)
                    .cornerRadius(6)
                }
            }
            if showTieButton {
                Button { onTiePressed?() } label: {
                    Text("⌒")
                        .font(.system(size: 18, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
            }
        }
    }
}

// MARK: - Key picker sheet

struct KeyPickerSheet: View {
    let initialKeyRoot: Int
    let initialIsMinor: Bool
    let onSelect: (Int, Bool) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var keyRoot: Int
    @State private var isMinor: Bool

    init(keyRoot: Int, isMinor: Bool, onSelect: @escaping (Int, Bool) -> Void) {
        self.initialKeyRoot = keyRoot
        self.initialIsMinor = isMinor
        self.onSelect = onSelect
        _keyRoot = State(initialValue: keyRoot)
        _isMinor = State(initialValue: isMinor)
    }

    private let noteNames = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Root note")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 4), spacing: 12) {
                    ForEach(0..<12, id: \.self) { i in
                        Button {
                            keyRoot = i
                        } label: {
                            Text(noteNames[i])
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(keyRoot == i ? Color.yellow : Color.gray.opacity(0.3))
                                .cornerRadius(8)
                                .foregroundColor(keyRoot == i ? .black : .white)
                                .font(.body.bold())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Text("Mode")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                Picker("", selection: $isMinor) {
                    Text("Major").tag(false)
                    Text("Minor").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Key").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        onSelect(keyRoot, isMinor)
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

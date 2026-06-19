import SwiftUI
import UIKit

enum ScoreDisplayMode: String, CaseIterable {
    case score    = "Score"
    case pianoRoll = "Piano Roll"
}

struct ChoraleResultView: View {
    @ObservedObject var vm: ChoraleViewModel
    @StateObject private var player = ChoralePlayer()
    @State private var displayMode: ScoreDisplayMode = .score
    @State private var showSaveSheet = false
    @State private var saveName = ""


    var body: some View {
        NavigationView {
            if vm.chorale.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // Score / Piano Roll toggle
                    Picker("", selection: $displayMode) {
                        ForEach(ScoreDisplayMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 6)

                    // Main display
                    Group {
                        if displayMode == .score {
                            ChoraleScoreRepresentable(
                                chorale: vm.chorale,
                                currentBeat: player.currentBeat,
                                mutedVoices: player.mutedVoices
                            )
                        } else {
                            ChoraleRollView(
                                chorale: vm.chorale,
                                currentBeat: player.currentBeat,
                                mutedVoices: player.mutedVoices
                            )
                        }
                    }

                    // Mixer
                    MixerView(player: player)

                    // Bottom controls
                    bottomControls
                }
                .navigationTitle(keyLabel)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
                .sheet(isPresented: $showSaveSheet) {
                    SaveChoraleSheet(defaultName: defaultSaveName) { name in
                        let entry = UserChoraleEntry(
                            id: UUID(), name: name, date: Date(),
                            chorale: vm.chorale,
                            sopranoNotes: vm.sopranоNotes
                        )
                        UserChoraleStore.shared.save(entry)
                    }
                }
            }
        }
    }

    private var defaultSaveName: String {
        let noteNames = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
        let key = "\(noteNames[vm.chorale.keyRoot])\(vm.chorale.isMinor ? "m" : "")"
        switch vm.choraleOrigin {
        case .fromSoprano: return "Chorale in \(key)"
        case .generated:   return "Generated in \(key)"
        case .none:        return "Chorale"
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.quarternote.3")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No chorale yet")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Use the Soprano tab to harmonize a melody,\nor Generate to create one from scratch.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .navigationTitle("Chorale")
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        HStack(spacing: 12) {
            // Play / Stop
            Button {
                if player.isPlaying {
                    player.stop()
                } else {
                    player.play(
                        chorale: vm.chorale,
                        onBeat: { beat in player.currentBeat = beat },
                        onFinish: { }
                    )
                }
            } label: {
                Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderedProminent)

            // Nueva versión
            if vm.choraleOrigin != .none {
                Button {
                    vm.reHarmonize()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(vm.isHarmonizing)
            }

            // Sound picker
            Picker("", selection: $player.sound) {
                ForEach(ChoraleSound.allCases) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 120)

            Spacer()

            // Tempo
            Text("\(vm.chorale.tempo) bpm")
                .font(.caption)
                .foregroundColor(.secondary)

            // Guardar
            Button {
                showSaveSheet = true
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)

            // MIDI export
            Button {
                let data = vm.exportMIDI()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("coral_bach.mid")
                try? data.write(to: url)
                let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = scene.windows.first?.rootViewController {
                    var top = root
                    while let presented = top.presentedViewController { top = presented }
                    top.present(ac, animated: true)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Text(keyLabel)
                .font(.caption.bold())
                .foregroundColor(.yellow)
        }
    }

    private var keyLabel: String {
        let noteNames = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
        return "\(noteNames[vm.chorale.keyRoot])\(vm.chorale.isMinor ? "m" : "") — Chorale"
    }
}

// MARK: - MixerView

struct MixerView: View {
    @ObservedObject var player: ChoralePlayer

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Voice.allCases) { voice in
                voiceButton(voice)
            }
        }
        .frame(height: 44)
        .background(Color(white: 0.12))
    }

    private func voiceButton(_ voice: Voice) -> some View {
        let muted = player.mutedVoices.contains(voice)
        let c = voice.color
        let color = Color(red: c.r, green: c.g, blue: c.b)

        return Button {
            player.toggleMute(voice)
        } label: {
            VStack(spacing: 2) {
                Circle()
                    .fill(muted ? Color.gray.opacity(0.4) : color)
                    .frame(width: 12, height: 12)
                Text(voice.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(muted ? .gray : color)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(muted ? Color.clear : color.opacity(0.08))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ChoraleRollView (4-voice piano roll)

struct ChoraleRollView: UIViewRepresentable {
    let chorale: ChoraleData
    let currentBeat: Double
    let mutedVoices: Set<Voice>

    func makeUIView(context: Context) -> ChoraleRollUIView {
        let v = ChoraleRollUIView()
        v.update(chorale: chorale, currentBeat: currentBeat, mutedVoices: mutedVoices)
        return v
    }

    func updateUIView(_ v: ChoraleRollUIView, context: Context) {
        v.update(chorale: chorale, currentBeat: currentBeat, mutedVoices: mutedVoices)
    }
}

class ChoraleRollUIView: UIView {
    private let scrollView = UIScrollView()
    private let canvas     = UIView()
    private var chorale    = ChoraleData()
    private var mutedVoices: Set<Voice> = []
    // Per-voice note layers for mute dimming
    private var voiceContainers = [Voice: CALayer]()
    private let playheadLayer = CALayer()

    // Smooth scroll via CADisplayLink
    private var displayLink:    CADisplayLink?
    private var anchorBeat:     Double = 0
    private var anchorTime:     CFTimeInterval = 0
    private var beatsPerSecond: Double = 2.0
    private var lastBeat:       Double = -1.0

    let keyboardW: CGFloat = 44
    let beatW:     CGFloat = 52
    let minRowH:   CGFloat = 8
    let maxRowH:   CGFloat = 24

    private var midiMin = 38
    private var midiMax = 82

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.07, alpha: 1)
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        scrollView.addSubview(canvas)
        playheadLayer.backgroundColor = UIColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.85).cgColor
        playheadLayer.isHidden = true
        canvas.layer.addSublayer(playheadLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        redrawAll()
    }

    func update(chorale: ChoraleData, currentBeat: Double, mutedVoices: Set<Voice>) {
        let choraleChanged = self.chorale != chorale
        self.chorale = chorale

        // Smooth scroll anchor: when beat advances, record position and time
        if currentBeat >= 0 && currentBeat != lastBeat {
            if lastBeat >= 0 && currentBeat > lastBeat {
                let elapsed = CACurrentMediaTime() - anchorTime
                if elapsed > 0 { beatsPerSecond = (currentBeat - anchorBeat) / elapsed }
            }
            anchorBeat = currentBeat
            anchorTime = CACurrentMediaTime()
            lastBeat   = currentBeat
        }

        if choraleChanged { redrawAll() }

        if currentBeat >= 0 {
            if displayLink == nil { startDisplayLink() }
            playheadLayer.isHidden = false
        } else {
            stopDisplayLink()
            playheadLayer.isHidden = true
            lastBeat = -1
        }

        if self.mutedVoices != mutedVoices {
            self.mutedVoices = mutedVoices
            updateMuteOpacity()
        }
    }

    // MARK: - Display link

    private func startDisplayLink() {
        let dl = CADisplayLink(target: self, selector: #selector(tick))
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard lastBeat >= 0 else { stopDisplayLink(); return }
        let elapsed = CACurrentMediaTime() - anchorTime
        let beat    = anchorBeat + elapsed * beatsPerSecond

        let x  = keyboardW + CGFloat(beat) * beatW
        let vw = scrollView.bounds.width
        let tx = max(0, x - vw * 0.3)
        let mx = max(0, scrollView.contentSize.width - vw)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playheadLayer.frame.origin.x = x
        scrollView.contentOffset = CGPoint(x: min(tx, mx), y: scrollView.contentOffset.y)
        CATransaction.commit()
    }

    // MARK: - Mute

    private func updateMuteOpacity() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (voice, container) in voiceContainers {
            container.opacity = mutedVoices.contains(voice) ? 0.18 : 1.0
        }
        CATransaction.commit()
    }

    // MARK: - Build

    private func computeMidiRange() {
        let allNotes = [chorale.soprano, chorale.alto, chorale.tenor, chorale.bass].flatMap { $0 }
        guard !allNotes.isEmpty else { midiMin = 38; midiMax = 82; return }
        midiMin = max(24, allNotes.map { Int($0.midiNote) }.min()! - 3)
        midiMax = min(96, allNotes.map { Int($0.midiNote) }.max()! + 4)
    }

    private func rowHeight() -> CGFloat {
        let h = max(1, bounds.height) / CGFloat(midiMax - midiMin)
        return min(maxRowH, max(minRowH, h))
    }

    private func redrawAll() {
        guard bounds.height > 0 else { return }
        canvas.subviews.forEach { $0.removeFromSuperview() }
        canvas.layer.sublayers?.filter { $0 !== playheadLayer }.forEach { $0.removeFromSuperlayer() }
        voiceContainers = [Voice: CALayer]()

        computeMidiRange()
        let rowH       = rowHeight()
        let totalBeats = chorale.soprano.map { $0.beatPosition + $0.duration }.max() ?? 16.0
        let midiRange  = midiMax - midiMin
        let w = keyboardW + CGFloat(totalBeats) * beatW
        let h = CGFloat(midiRange) * rowH

        canvas.frame = CGRect(x: 0, y: 0, width: w, height: h)
        scrollView.contentSize = CGSize(width: w, height: h)

        drawBackground(totalBeats: totalBeats, midiRange: midiRange, rowH: rowH)
        drawNotes(rowH: rowH, midiRange: midiRange, h: h)
        playheadLayer.frame = CGRect(x: keyboardW, y: 0, width: 2.5, height: h)
        canvas.layer.addSublayer(playheadLayer)   // keep playhead on top
    }

    private func drawBackground(totalBeats: Double, midiRange: Int, rowH: CGFloat) {
        let imgSize = CGSize(width: keyboardW + CGFloat(totalBeats)*beatW,
                             height: CGFloat(midiRange)*rowH)
        UIGraphicsBeginImageContextWithOptions(imgSize, false, UIScreen.main.scale)
        guard let ctx = UIGraphicsGetCurrentContext() else { UIGraphicsEndImageContext(); return }
        UIGraphicsPushContext(ctx)

        for i in 0..<midiRange {
            let midi    = midiMax - 1 - i
            let isBlack = [1,3,6,8,10].contains(midi % 12)
            let isC     = midi % 12 == 0
            ctx.setFillColor((isBlack ? UIColor(white:0.085,alpha:1) : UIColor(white:0.115,alpha:1)).cgColor)
            ctx.fill(CGRect(x: keyboardW, y: CGFloat(i)*rowH, width: CGFloat(totalBeats)*beatW, height: rowH))
            if isC {
                ctx.setFillColor(UIColor.white.withAlphaComponent(0.04).cgColor)
                ctx.fill(CGRect(x: keyboardW, y: CGFloat(i)*rowH, width: CGFloat(totalBeats)*beatW, height: 1))
            }
            let kw = keyboardW
            ctx.setFillColor((isBlack ? UIColor(white:0.12,alpha:1) : UIColor(white:0.28,alpha:1)).cgColor)
            ctx.fill(CGRect(x: 0, y: CGFloat(i)*rowH, width: kw, height: rowH - 0.5))
            if isBlack {
                ctx.setFillColor(UIColor(white:0.22,alpha:1).cgColor)
                ctx.fill(CGRect(x: 0, y: CGFloat(i)*rowH, width: kw*0.62, height: rowH - 0.5))
            }
            if isC && rowH >= 10 {
                let label = "C\(midi/12 - 1)" as NSString
                label.draw(at: CGPoint(x: kw*0.68, y: CGFloat(i)*rowH + 1), withAttributes: [
                    .font: UIFont.systemFont(ofSize: min(rowH-2, 9), weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.55)
                ])
            }
        }
        var beat = 0.0
        while beat <= totalBeats {
            let x  = keyboardW + CGFloat(beat) * beatW
            let isMeasure = beat.truncatingRemainder(dividingBy: 4) < 0.001
            ctx.setFillColor(UIColor.white.withAlphaComponent(isMeasure ? 0.22 : 0.07).cgColor)
            ctx.fill(CGRect(x: x - (isMeasure ? 0.75 : 0.25), y: 0,
                            width: isMeasure ? 1.5 : 0.5, height: CGFloat(midiRange)*rowH))
            beat += 1.0
        }
        UIGraphicsPopContext()
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        let bg = CALayer(); bg.frame = canvas.bounds; bg.contents = img?.cgImage
        canvas.layer.insertSublayer(bg, at: 0)
    }

    private func drawNotes(rowH: CGFloat, midiRange: Int, h: CGFloat) {
        let voiceOrder: [Voice] = [.bass, .tenor, .alto, .soprano]
        let notesList: [(Voice, [ChoralNote])] = [
            (.soprano, chorale.soprano), (.alto, chorale.alto),
            (.tenor,   chorale.tenor),   (.bass, chorale.bass)
        ]
        for (voice, notes) in notesList {
            let container = CALayer()
            container.frame = CGRect(x: 0, y: 0, width: canvas.bounds.width, height: h)
            container.opacity = mutedVoices.contains(voice) ? 0.18 : 1.0
            canvas.layer.addSublayer(container)
            voiceContainers[voice] = container

            let c         = voice.color
            let color     = UIColor(red: c.r, green: c.g, blue: c.b, alpha: 0.9).cgColor
            let glowColor = UIColor(red: c.r, green: c.g, blue: c.b, alpha: 0.25).cgColor

            for note in notes {
                let midi = Int(note.midiNote)
                guard midi >= midiMin && midi < midiMax else { continue }
                let row = midiMax - 1 - midi
                let x = keyboardW + CGFloat(note.beatPosition) * beatW + 1
                let y = CGFloat(row) * rowH + 1
                let w = max(6, CGFloat(note.duration) * beatW - 2)
                let nh = max(4, rowH - 2)

                let glow = CALayer()
                glow.frame = CGRect(x: x-2, y: y-1, width: w+4, height: nh+2)
                glow.backgroundColor = glowColor
                glow.cornerRadius = 4
                container.addSublayer(glow)

                let layer = CALayer()
                layer.frame = CGRect(x: x, y: y, width: w, height: nh)
                layer.backgroundColor = color
                layer.cornerRadius = 3
                container.addSublayer(layer)
            }
        }
        _ = voiceOrder  // ordering handled by addSublayer sequence above
    }
}

// MARK: - Save Chorale Sheet

struct SaveChoraleSheet: View {
    let defaultName: String
    let onSave: (String) -> Void

    @State private var name: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Chorale name") {
                    TextField("Name", text: $name)
                }
            }
            .navigationTitle("Save chorale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(name.isEmpty ? defaultName : name)
                        dismiss()
                    }
                }
            }
            .onAppear { name = defaultName }
        }
    }
}

// MARK: - MIDI Share Sheet


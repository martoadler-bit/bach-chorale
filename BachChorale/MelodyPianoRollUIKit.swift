import UIKit
import SwiftUI
import AVFoundation

// MARK: - PianoRollUIView

class PianoRollUIView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    // MARK: - Public API
    var notes: [MelodyNote] = [] { didSet { redrawNotes() } }
    var totalMeasures: Int = 8 { didSet { updateLayout() } }
    var beatsPerMeasure: Int = 4 { didSet { updateLayout() } }
    var gridSize: Double = 0.5 { didSet { gridLayer.setNeedsDisplay() } }
    var selectedNoteIndex: Int? { didSet { redrawNotes() } }
    var playingNoteIndex: Int? {
        didSet {
            redrawNotes()
            scrollToPlayingNote()
        }
    }
    var measures: [Measure] = [] { didSet { chordLayer.setNeedsDisplay() } }
    let chordRowHeight: CGFloat = 24
    private let chordLayer = ChordRowLayer()

    // Playback
    var currentBeat: Double = -1.0 { didSet { updatePlayhead() } }
    var isPlayingMelody: Bool = false { didSet { updatePlayhead() } }
    private var displayLink: CADisplayLink?
    private var targetScrollX: CGFloat = 0
    private var playheadLayer = CALayer()
    private var didScrollToNotes = false

    var onNoteSelected: ((Int?) -> Void)?
    var onNotesChanged: (([MelodyNote]) -> Void)?

    var cursorBeat: Double = -1 { didSet { updateCursorLayer() } }
    private var cursorLayer = CALayer()

    // MARK: - Layout constants
    private var _beatWidth: CGFloat = 44
    private var _rowHeight: CGFloat = 12
    var beatWidth: CGFloat {
        get { _beatWidth }
        set { if _beatWidth != newValue { _beatWidth = newValue; updateLayout() } }
    }
    var rowHeight: CGFloat {
        get { _rowHeight }
        set { if _rowHeight != newValue { _rowHeight = newValue; updateLayout() } }
    }
    let keyboardWidth: CGFloat = 44
    var midiMin: Int = 24 { didSet { if midiMin != oldValue { updateLayout() } } }
    var midiMax: Int = 108 { didSet { if midiMax != oldValue { updateLayout() } } }
    var midiRange: Int { midiMax - midiMin }
    var totalBeats: Double { Double(totalMeasures * beatsPerMeasure) }
    var rollWidth: CGFloat { CGFloat(totalBeats) * beatWidth }
    var rollHeight: CGFloat { CGFloat(midiRange) * rowHeight }
    var totalWidth: CGFloat { keyboardWidth + rollWidth }

    // MARK: - Subviews / layers
    private let scrollView = SmartScrollView()
    let contentView = UIView()          // inside scrollView
    private let keyboardLayer = KeyboardCALayer()  // draws piano keys
    private let gridLayer = GridCALayer()       // draws rows + grid lines
    private let notesLayer = CALayer()          // parent of note layers

    // MARK: - Note interaction
    private var noteLayers: [NoteCALayer] = []
    var melodySound: MelodySoundType = .uprightPiano
    private var notePlayer: MelodyPlayer? = nil
    private var keyboardPlayer: MelodyPlayer? = nil
    private var lastKeyboardMidi: Int = -1

    // Drag state
    private var activeDragNoteIdx: Int? = nil
    var isDraggingNote: Bool = false
    private var activeDragType: DragType = .move
    private var dragStartBeat: Double = 0
    private var dragStartMidi: Int = 0
    private var dragStartDuration: Double = 0
    private var dragStartPos: CGPoint = .zero
    private var lastDragMidi: Int = -1

    // Zoom state — acumular durante el gesto, aplicar al terminar
    private var zoomStartBeatWidth: CGFloat = 44
    private var zoomStartRowHeight: CGFloat = 12
    private var zoomPinchPoint: CGPoint = .zero

    enum DragType { case move, resizeLeft, resizeRight }
    private weak var noteDragGesture: UIPanGestureRecognizer?

    // MARK: - Init
    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup
    private func setup() {
        backgroundColor = UIColor(white: 0.08, alpha: 1)

        // ScrollView
        scrollView.delegate = self
        (scrollView as? SmartScrollView)?.pianoRoll = self
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.backgroundColor = .clear
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        // Zoom nativo desactivado — usamos pinch gestures custom
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 1.0
        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Content view
        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)

        // Layers — order matters (bottom to top)
        keyboardLayer.contentsScale = UIScreen.main.scale
        keyboardLayer.pianoRoll = self
        gridLayer.contentsScale = UIScreen.main.scale
        gridLayer.pianoRoll = self
        contentView.layer.addSublayer(keyboardLayer)
        contentView.layer.addSublayer(gridLayer)
        contentView.layer.addSublayer(notesLayer)

        // Gestures
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        contentView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(onSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        contentView.addGestureRecognizer(singleTap)

        // Keyboard drag (tocar teclas)
        let keyDrag = UIPanGestureRecognizer(target: self, action: #selector(onKeyboardDrag(_:)))
        keyDrag.delegate = self
        contentView.addGestureRecognizer(keyDrag)

        // Note drag (mover/resize notas) — separado del scroll
        // Pinch custom para zoom horizontal y vertical separados
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let noteDrag = UIPanGestureRecognizer(target: self, action: #selector(onNoteDrag(_:)))
        noteDrag.delegate = self
        noteDrag.maximumNumberOfTouches = 1
        contentView.addGestureRecognizer(noteDrag)
        noteDragGesture = noteDrag

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        contentView.addGestureRecognizer(longPress)

        // ChordLayer lives in contentView (same scroll) but stays fixed vertically
        chordLayer.contentsScale = UIScreen.main.scale
        chordLayer.pianoRoll = self
        contentView.layer.addSublayer(chordLayer)

        // Playhead
        playheadLayer.backgroundColor = UIColor(red: 0.91, green: 0.66, blue: 0.29, alpha: 0.75).cgColor
        playheadLayer.isHidden = true
        contentView.layer.addSublayer(playheadLayer)

        // Cursor (step-record insert position)
        cursorLayer.backgroundColor = UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 0.7).cgColor
        cursorLayer.isHidden = true
        contentView.layer.addSublayer(cursorLayer)

        updateLayout()
    }

    // MARK: - Layout
    func updateLayout() {
        let w = totalWidth
        let h = rollHeight
        let ch = chordRowHeight

        contentView.frame = CGRect(x: 0, y: 0, width: w, height: h + ch)
        scrollView.contentSize = CGSize(width: w, height: h + ch)

        // ChordLayer at top — will be kept visible via scrollViewDidScroll
        chordLayer.frame = CGRect(x: keyboardWidth, y: 0, width: rollWidth, height: ch)
        chordLayer.setNeedsDisplay()

        keyboardLayer.frame = CGRect(x: 0, y: ch, width: keyboardWidth, height: h)
        keyboardLayer.setNeedsDisplay()

        gridLayer.frame = CGRect(x: keyboardWidth, y: ch, width: rollWidth, height: h)
        gridLayer.setNeedsDisplay()

        notesLayer.frame = CGRect(x: keyboardWidth, y: ch, width: rollWidth, height: h)
        playheadLayer.frame = CGRect(x: playheadLayer.frame.minX, y: ch, width: 1.5, height: h)
        cursorLayer.frame = CGRect(x: cursorLayer.frame.minX, y: ch, width: 2, height: h)

        redrawNotes()
        updatePlayhead()

        // Scroll to note range vertically
        if !didScrollToNotes && !notes.isEmpty {
            didScrollToNotes = true
            let midiValues = notes.map { Int($0.midiNote) }
            let midMidi = ((midiValues.min() ?? 60) + (midiValues.max() ?? 72)) / 2
            let midRow = (midiMax - midiMin) - (midMidi - midiMin)
            let targetY = max(0, ch + CGFloat(midRow) * rowHeight - scrollView.bounds.height / 2)
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: min(targetY, maxY)), animated: false)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout()
    }

    // MARK: - Draw keyboard
    // Called by keyboardLayer's delegate (set below via KeyboardCALayer)
    func drawKeyboard(in ctx: CGContext) {
        for i in 0..<midiRange {
            let midi = midiMax - 1 - i
            let y = CGFloat(i) * rowHeight
            let isBlack = [1,3,6,8,10].contains(midi % 12)
            let bg: UIColor = isBlack
                ? UIColor(white: 0.15, alpha: 1)
                : UIColor(white: 0.22, alpha: 1)
            ctx.setFillColor(bg.cgColor)
            ctx.fill(CGRect(x: 0, y: y, width: keyboardWidth, height: rowHeight))
            // Right border
            ctx.setFillColor(UIColor.white.withAlphaComponent(0.08).cgColor)
            ctx.fill(CGRect(x: keyboardWidth - 0.5, y: y, width: 0.5, height: rowHeight))
            // C label
            if midi % 12 == 0 {
                let label = "C\(midi/12 - 1)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 7, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.4)
                ]
                let sz = label.size(withAttributes: attrs)
                label.draw(at: CGPoint(x: keyboardWidth - sz.width - 3,
                                        y: y + (rowHeight - sz.height) / 2),
                           withAttributes: attrs)
            }
        }
    }


    // MARK: - Monophonic enforcement
    // La melodía es monofónica: no puede haber dos notas superpuestas en el timeline.
    // Al agregar o mover una nota, recortamos o eliminamos las que se superponen.
    private func enforceMonophonic(_ notes: [MelodyNote], changed changedIdx: Int) -> [MelodyNote] {
        var result = notes
        let changed = result[changedIdx]
        let changedEnd = changed.beatPosition + changed.duration

        var toRemove: [Int] = []
        for (i, note) in result.enumerated() {
            guard i != changedIdx else { continue }
            let noteEnd = note.beatPosition + note.duration
            // Overlap: note starts before changed ends AND note ends after changed starts
            let overlaps = note.beatPosition < changedEnd && noteEnd > changed.beatPosition
            if overlaps { toRemove.append(i) }
        }
        // Remove overlapping notes (highest index first to preserve indices)
        for i in toRemove.sorted().reversed() { result.remove(at: i) }
        return result
    }
    // MARK: - Note layers
    func redrawNotes() {
        noteLayers.forEach { $0.removeFromSuperlayer() }
        noteLayers = []

        for (i, note) in notes.enumerated() {
            let layer = NoteCALayer()
            layer.note = note
            layer.isNoteSelected = selectedNoteIndex == i
            layer.isNotePlaying = playingNoteIndex == i
            layer.contentsScale = UIScreen.main.scale

            let midiC = max(midiMin, min(midiMax - 1, Int(note.midiNote)))
            let x = CGFloat(note.beatPosition) * beatWidth
            let y = CGFloat(midiMax - 1 - midiC) * rowHeight
            let w = max(beatWidth * 0.3, CGFloat(note.duration) * beatWidth - 2)
            let h = rowHeight - 1
            layer.frame = CGRect(x: x, y: y, width: w, height: h)
            layer.setNeedsDisplay()

            notesLayer.addSublayer(layer)
            noteLayers.append(layer)
        }
    }

    // MARK: - Playhead
    func updatePlayhead() {
        let quarter = currentBeat / 2.0
        let x = keyboardWidth + CGFloat(quarter) * beatWidth
        playheadLayer.isHidden = true
        playheadLayer.frame = CGRect(x: x, y: chordRowHeight, width: 1.5, height: rollHeight)

        if isPlayingMelody && currentBeat >= 0 {
            for (i, layer) in noteLayers.enumerated() {
                guard i < notes.count else { continue }
                let n = notes[i]
                let isActive = quarter >= n.beatPosition && quarter < n.beatPosition + n.duration
                let gold = UIColor(red: 0.91, green: 0.66, blue: 0.29, alpha: 1)
                let blue = UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1)
                layer.backgroundColor = isActive ? gold.cgColor :
                    (n.isStructural ? blue.cgColor : blue.withAlphaComponent(0.55).cgColor)
            }
            let viewW = scrollView.bounds.width
            let targetX = max(0, min(x - viewW * 0.3, scrollView.contentSize.width - viewW))
            if abs(targetX - scrollView.contentOffset.x) > 0.5 {
                scrollView.contentOffset.x = targetX
            }
        } else {
            didScrollToNotes = false
            for (i, layer) in noteLayers.enumerated() {
                guard i < notes.count else { continue }
                let blue = UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1)
                layer.backgroundColor = notes[i].isStructural ? blue.cgColor : blue.withAlphaComponent(0.55).cgColor
            }
        }
    }

    // MARK: - Cursor layer
    func updateCursorLayer() {
        let ch = chordRowHeight
        let h  = rollHeight
        if cursorBeat < 0 {
            cursorLayer.isHidden = true
        } else {
            let x = keyboardWidth + CGFloat(cursorBeat) * beatWidth
            cursorLayer.isHidden = false
            cursorLayer.frame = CGRect(x: x, y: ch, width: 2, height: h)
        }
    }

    // MARK: - Hit testing helpers
    func noteIndex(at point: CGPoint) -> Int? {
        let notePoint = CGPoint(x: point.x - keyboardWidth, y: point.y)
        // Exact hit first
        for (i, layer) in noteLayers.enumerated().reversed() {
            if layer.frame.contains(notePoint) { return i }
        }
        // Expanded hit area (±10px) for thin notes
        for (i, layer) in noteLayers.enumerated().reversed() {
            if layer.frame.insetBy(dx: -10, dy: -10).contains(notePoint) { return i }
        }
        return nil
    }

    private func dragType(at point: CGPoint, noteIdx: Int) -> DragType {
        let notePoint = CGPoint(x: point.x - keyboardWidth, y: point.y)
        let frame = noteLayers[noteIdx].frame
        let handleW: CGFloat = max(22, min(frame.width * 0.3, 36))
        if notePoint.x - frame.minX < handleW { return .resizeLeft }
        if frame.maxX - notePoint.x < handleW { return .resizeRight }
        return .move
    }

    // MARK: - Gestures

    // UIScrollView native zoom delegates
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Keep chordLayer pinned to top of visible area
        let offsetY = scrollView.contentOffset.y
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chordLayer.frame = CGRect(
            x: keyboardWidth,
            y: offsetY,
            width: rollWidth,
            height: chordRowHeight
        )
        CATransaction.commit()
        chordLayer.setNeedsDisplay()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return nil  // zoom nativo desactivado
    }

    // MARK: - Pinch zoom custom (H e V separados, centro correcto)
    private var pinchStartBeatWidth: CGFloat = 0
    private var pinchStartRowHeight: CGFloat = 0
    private var pinchStartMidBeat: Double = 0
    private var pinchStartMidRow: CGFloat = 0
    private var pinchStartDist: CGPoint = .zero
    private var pinchFrameCount: Int = 0

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            guard g.numberOfTouches == 2 else { return }
            pinchStartBeatWidth = _beatWidth
            pinchStartRowHeight = _rowHeight
            let t1 = g.location(ofTouch: 0, in: contentView)
            let t2 = g.location(ofTouch: 1, in: contentView)
            pinchStartDist = CGPoint(x: abs(t1.x - t2.x), y: abs(t1.y - t2.y))
            pinchFrameCount = 0
            let mid = CGPoint(x: (t1.x + t2.x) / 2, y: (t1.y + t2.y) / 2)
            pinchStartMidBeat = Double(max(0, mid.x - keyboardWidth) / _beatWidth)
            pinchStartMidRow = mid.y / _rowHeight

        case .changed:
            guard g.numberOfTouches == 2 else { return }
            let t1 = g.location(ofTouch: 0, in: contentView)
            let t2 = g.location(ofTouch: 1, in: contentView)
            let curr = CGPoint(x: abs(t1.x - t2.x), y: abs(t1.y - t2.y))

            // Scale relativo al inicio — correcto para centro fijo
            let sx = pinchStartDist.x > 20 ? (curr.x / pinchStartDist.x) : 1.0
            let sy = pinchStartDist.y > 20 ? (curr.y / pinchStartDist.y) : 1.0

            let newBW = (pinchStartBeatWidth * sx).clamped(12...200)
            let newRH = (pinchStartRowHeight * sy).clamped(4...40)

            _beatWidth = newBW
            _rowHeight = newRH

            // Throttle: redibujar solo cada 2 frames para reducir temblor
            pinchFrameCount += 1
            if pinchFrameCount % 2 == 0 {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                updateLayout()
                CATransaction.commit()
            }

            // Mantener el punto medio del pinch fijo
            let newOffX = keyboardWidth + CGFloat(pinchStartMidBeat) * _beatWidth - scrollView.bounds.width / 2
            let newOffY = pinchStartMidRow * _rowHeight - scrollView.bounds.height / 2
            let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            scrollView.setContentOffset(CGPoint(
                x: max(0, min(newOffX, maxX)),
                y: max(0, min(newOffY, maxY))
            ), animated: false)

        case .ended, .cancelled:
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updateLayout()
            CATransaction.commit()
        default: break
        }
    }

        @objc private func onDoubleTap(_ g: UITapGestureRecognizer) {
        let pt = g.location(in: contentView)
        guard pt.x > keyboardWidth else { return }
        let savedOffset = scrollView.contentOffset
        (scrollView as? SmartScrollView)?.lockCurrentOffset()
        // Doble tap en nota = borrar
        if let idx = noteIndex(at: pt) {
            var newNotes = notes
            newNotes.remove(at: idx)
            notes = newNotes
            selectedNoteIndex = nil
            onNoteSelected?(nil)
            onNotesChanged?(notes)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let off = savedOffset
            DispatchQueue.main.async { [weak self] in
                self?.scrollView.contentOffset = off
                DispatchQueue.main.async { self?.scrollView.contentOffset = off }
            }
            return
        }
        let off2 = savedOffset
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.scrollView.contentOffset = off2
                DispatchQueue.main.async { self?.scrollView.contentOffset = off2 }
            }
        }
        let beatPos = Double((pt.x - keyboardWidth) / beatWidth)
        let midiRow = Int(pt.y / rowHeight)
        let midiVal = midiMax - 1 - midiRow
        guard midiVal >= midiMin && midiVal < midiMax else { return }
        let midi = UInt8(clamping: midiVal)
        let snapped = (beatPos / gridSize).rounded(.down) * gridSize
        guard snapped < totalBeats else { return }
        guard !notes.contains(where: {
            $0.midiNote == midi && snapped >= $0.beatPosition && snapped < $0.beatPosition + $0.duration
        }) else { return }
        var newNotes = notes
        let newNote = MelodyNote(midiNote: midi, beatPosition: snapped, duration: gridSize, isStructural: false)
        newNotes.append(newNote)
        let insertedIdx = newNotes.count - 1
        newNotes = enforceMonophonic(newNotes, changed: insertedIdx)
        notes = newNotes
        let newIdx = notes.count - 1
        selectedNoteIndex = newIdx
        onNoteSelected?(newIdx)
        onNotesChanged?(notes)
        // Sonar la nota al crearla
        playNote(midi: midi)
    }

    @objc private func onSingleTap(_ g: UITapGestureRecognizer) {
        let pt = g.location(in: contentView)
        let savedOffset = scrollView.contentOffset
        (scrollView as? SmartScrollView)?.lockCurrentOffset()
        if let idx = noteIndex(at: pt) {
            if selectedNoteIndex == idx {
                selectedNoteIndex = nil
                onNoteSelected?(nil)
            } else {
                selectedNoteIndex = idx
                onNoteSelected?(idx)
                playNote(midi: notes[idx].midiNote)
            }
            let off = savedOffset
            DispatchQueue.main.async { [weak self] in
                self?.scrollView.contentOffset = off
                DispatchQueue.main.async { self?.scrollView.contentOffset = off }
            }
        } else {
            selectedNoteIndex = nil
            onNoteSelected?(nil)
        }
    }

    @objc private func onLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let pt = g.location(in: contentView)
        guard let idx = noteIndex(at: pt) else { return }
        var newNotes = notes
        newNotes.remove(at: idx)
        notes = newNotes
        selectedNoteIndex = nil
        onNoteSelected?(nil)
        onNotesChanged?(notes)
    }

    @objc private func onNoteDrag(_ g: UIPanGestureRecognizer) {
        let pt = g.location(in: contentView)

        switch g.state {
        case .began:
            guard pt.x > keyboardWidth, let idx = noteIndex(at: pt) else {
                activeDragNoteIdx = nil
                return  // no note — scroll handles it (simultaneous)
            }
            isDraggingNote = true
            // Frenar inercia del scroll solo si estaba en movimiento
            if scrollView.isDecelerating {
                scrollView.setContentOffset(scrollView.contentOffset, animated: false)
            }
            activeDragNoteIdx = idx
            activeDragType = dragType(at: pt, noteIdx: idx)
            dragStartBeat = notes[idx].beatPosition
            dragStartMidi = Int(notes[idx].midiNote)
            dragStartDuration = notes[idx].duration
            dragStartPos = pt
            selectedNoteIndex = idx
            onNoteSelected?(idx)

        case .changed:
            guard let idx = activeDragNoteIdx else { return }
            let translation = CGPoint(x: pt.x - dragStartPos.x, y: pt.y - dragStartPos.y)
            let gs = gridSize
            var newNotes = notes

            switch activeDragType {
            case .move:
                let dBeat = Double(translation.x / beatWidth)
                let dMidi = -Int((translation.y / rowHeight).rounded())
                let newBeat = max(0, min(totalBeats - notes[idx].duration, dragStartBeat + dBeat))
                let newMidi = max(midiMin, min(midiMax - 1, dragStartMidi + dMidi))
                newNotes[idx].beatPosition = (newBeat / gs).rounded() * gs
                newNotes[idx].midiNote = UInt8(newMidi)
                // Tocar nota al cambiar de pitch durante el drag
                if newMidi != lastDragMidi {
                    lastDragMidi = newMidi
                    playNote(midi: UInt8(newMidi))
                }
            case .resizeRight:
                let dBeat = Double(translation.x / beatWidth)
                let newDur = max(gs, dragStartDuration + dBeat)
                let snapped = (newDur / gs).rounded() * gs
                newNotes[idx].duration = min(snapped, totalBeats - notes[idx].beatPosition)
            case .resizeLeft:
                let dBeat = Double(translation.x / beatWidth)
                let newStart = max(0, dragStartBeat + dBeat)
                let snapped = (newStart / gs).rounded() * gs
                let newDur = dragStartDuration - (snapped - dragStartBeat)
                guard newDur >= gs else { return }
                newNotes[idx].beatPosition = snapped
                newNotes[idx].duration = newDur
            }
            notes = newNotes

        case .ended, .cancelled:
            isDraggingNote = false
            lastDragMidi = -1
            if let idx = activeDragNoteIdx, idx < notes.count {
                var enforced = notes
                enforced = enforceMonophonic(enforced, changed: idx)
                notes = enforced
                onNotesChanged?(notes)
            }
            activeDragNoteIdx = nil

        default: break
        }
    }

    @objc private func onKeyboardDrag(_ g: UIPanGestureRecognizer) {
        let pt = g.location(in: contentView)
        guard pt.x < keyboardWidth else { return }
        if g.state == .ended || g.state == .cancelled { lastKeyboardMidi = -1; return }
        let midiRow = Int(pt.y / rowHeight)
        let midi = midiMax - 1 - midiRow
        guard midi >= midiMin && midi < midiMax && midi != lastKeyboardMidi else { return }
        lastKeyboardMidi = midi
        playNote(midi: UInt8(midi))
    }

    // MARK: - AutoScroll
    private func scrollToPlayingNote() {
        guard let idx = playingNoteIndex, idx < notes.count else { return }
        let note = notes[idx]
        let noteX = CGFloat(note.beatPosition) * beatWidth + keyboardWidth
        let noteWidth = CGFloat(note.duration) * beatWidth
        let visibleMinX = scrollView.contentOffset.x
        let visibleMaxX = visibleMinX + scrollView.bounds.width

        // Solo scrollear hacia adelante si la nota está por salir de la vista
        if noteX + noteWidth > visibleMaxX {
            let targetX = noteX - 40  // 40px de margen izquierdo
            let maxOffset = scrollView.contentSize.width - scrollView.bounds.width
            let clampedX = max(0, min(targetX, maxOffset))
            // Solo si avanzamos (nunca scroll hacia atrás durante reproducción)
            if clampedX > visibleMinX {
                scrollView.setContentOffset(CGPoint(x: clampedX, y: scrollView.contentOffset.y), animated: true)
            }
        }
    }

    // MARK: - Sound
    private func playNote(midi: UInt8) {
        notePlayer?.stop()
        notePlayer = MelodyPlayer(sound: melodySound)
        notePlayer?.playSingleNote(midiNote: midi)
    }

    // MARK: - UIGestureRecognizerDelegate
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // pinch custom en self, no necesita simultáneo con scroll
        if g === noteDragGesture && other === scrollView.panGestureRecognizer { return true }
        if other === noteDragGesture && g === scrollView.panGestureRecognizer { return true }
        return false
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        return false
    }

func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return true
    }
}

// MARK: - SmartScrollView
class SmartScrollView: UIScrollView {
    weak var pianoRoll: PianoRollUIView?
    var lockOffset: Bool = false
    private var lockedOffset: CGPoint = .zero

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g === panGestureRecognizer, let pr = pianoRoll {
            // Si hay drag activo, el scroll no empieza nunca
            guard !pr.isDraggingNote else { return false }
            // Si el dedo empieza sobre una nota, el scroll no empieza
            let pt = g.location(in: pr.contentView)
            if pt.x > pr.keyboardWidth && pr.noteIndex(at: pt) != nil { return false }
        }
        return super.gestureRecognizerShouldBegin(g)
    }

    func lockCurrentOffset() {
        lockedOffset = contentOffset
        lockOffset = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.lockOffset = false
        }
    }

    override var contentOffset: CGPoint {
        get { return super.contentOffset }
        set {
            if lockOffset && abs(newValue.x) < 1 && abs(newValue.y) < 1 {
                // Ignorar reset al origen
                super.contentOffset = lockedOffset
            } else {
                super.contentOffset = newValue
            }
        }
    }
}

// MARK: - GridCALayer
class GridCALayer: CALayer {
    weak var pianoRoll: PianoRollUIView?

    override func draw(in ctx: CGContext) {
        guard let pr = pianoRoll else { return }

        // Row backgrounds
        for i in 0..<pr.midiRange {
            let midi = pr.midiMax - 1 - i
            let y = CGFloat(i) * pr.rowHeight
            let isBlack = [1,3,6,8,10].contains(midi % 12)
            let isC = midi % 12 == 0
            let color: UIColor = isC ? UIColor(white: 0.14, alpha: 1)
                : isBlack ? UIColor(white: 0.10, alpha: 1)
                           : UIColor(white: 0.12, alpha: 1)
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: 0, y: y, width: pr.rollWidth, height: pr.rowHeight))
            // Row border
            ctx.setFillColor(UIColor.white.withAlphaComponent(isC ? 0.06 : 0.02).cgColor)
            ctx.fill(CGRect(x: 0, y: y + pr.rowHeight - 0.5, width: pr.rollWidth, height: 0.5))
        }

        // Grid lines
        let gs = pr.gridSize
        var beat = 0.0
        while beat <= pr.totalBeats {
            let x = CGFloat(beat) * pr.beatWidth
            let isMeasure = beat.truncatingRemainder(dividingBy: Double(pr.beatsPerMeasure)) < 0.001
            let isBeat = beat.truncatingRemainder(dividingBy: 1.0) < 0.001
            let alpha: CGFloat = isMeasure ? 0.20 : isBeat ? 0.08 : 0.03
            let lw: CGFloat = isMeasure ? 1.0 : 0.5
            ctx.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
            ctx.fill(CGRect(x: x, y: 0, width: lw, height: pr.rollHeight))
            beat += gs
        }

        // Measure numbers
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.3)
        ]
        UIGraphicsPushContext(ctx)
        for m in 0..<pr.totalMeasures {
            let x = CGFloat(m * pr.beatsPerMeasure) * pr.beatWidth + 3
            "\(m + 1)".draw(at: CGPoint(x: x, y: 2), withAttributes: attrs)
        }
        UIGraphicsPopContext()
    }
}

// MARK: - KeyboardCALayer
class KeyboardCALayer: CALayer {
    weak var pianoRoll: PianoRollUIView?
    override func draw(in ctx: CGContext) {
        guard let pr = pianoRoll else { return }
        pr.drawKeyboard(in: ctx)
    }
}

// MARK: - NoteCALayer
class NoteCALayer: CALayer {
    var note: MelodyNote = MelodyNote(midiNote: 60, beatPosition: 0, duration: 0.5, isStructural: false)
    var isNoteSelected: Bool = false
    var isNotePlaying: Bool = false

    private let handleWidth: CGFloat = 10

    override func draw(in ctx: CGContext) {
        let gold = UIColor(red: 0.91, green: 0.66, blue: 0.29, alpha: 1)
        let blue = UIColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1)
        let base: UIColor = isNotePlaying ? gold : isNoteSelected ? .white
            : note.isStructural ? blue : blue.withAlphaComponent(0.55)
        let fill = base.withAlphaComponent(isNoteSelected ? 1.0 : 0.85)

        let rect = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 3)

        UIGraphicsPushContext(ctx)
        fill.setFill(); path.fill()
        if isNoteSelected { UIColor.white.withAlphaComponent(0.6).setStroke(); path.lineWidth = 1.5; path.stroke() }

        // Handles
        UIColor.white.withAlphaComponent(isNoteSelected ? 0.4 : 0.15).setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: handleWidth, height: bounds.height)).fill()
        UIBezierPath(rect: CGRect(x: bounds.width - handleWidth, y: 0, width: handleWidth, height: bounds.height)).fill()

        // Note name
        if bounds.width > 28 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8, weight: .semibold),
                .foregroundColor: UIColor.black.withAlphaComponent(0.75)
            ]
            let name = note.noteName as NSString
            let sz = name.size(withAttributes: attrs)
            name.draw(at: CGPoint(x: handleWidth + 2, y: (bounds.height - sz.height) / 2), withAttributes: attrs)
        }
        UIGraphicsPopContext()
    }
}

// MARK: - Clamped extension
extension Comparable {
    func clamped(_ range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - SwiftUI Wrapper
// MARK: - ChordRowLayer
class ChordRowLayer: CALayer {
    weak var pianoRoll: PianoRollUIView?
    override func draw(in ctx: CGContext) {
        guard let pr = pianoRoll, !pr.measures.isEmpty else { return }
        UIGraphicsPushContext(ctx)
        let gold = UIColor(red: 0.91, green: 0.66, blue: 0.29, alpha: 1)
        let h = pr.chordRowHeight
        let bw = pr.beatWidth

        UIColor(white: 0.09, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: bounds.width, height: h)).fill()

        var prevChord: String? = nil
        for (mi, measure) in pr.measures.enumerated() {
            let measureW = CGFloat(pr.beatsPerMeasure) * bw
            let measureX = CGFloat(mi * pr.beatsPerMeasure) * bw
            UIColor.white.withAlphaComponent(0.12).setFill()
            UIBezierPath(rect: CGRect(x: measureX, y: 0, width: 0.5, height: h)).fill()
            let nonEmpty = measure.slots.filter { !$0.chord.isEmpty }
            guard !nonEmpty.isEmpty else { prevChord = nil; continue }
            let slotW = measureW / CGFloat(nonEmpty.count)
            for (si, slot) in nonEmpty.enumerated() {
                if si == 0 && slot.chord == prevChord { prevChord = slot.chord; continue }
                if si > 0 && slot.chord == nonEmpty[si-1].chord { continue }
                let slotX = measureX + CGFloat(si) * slotW
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: gold
                ]
                ctx.saveGState()
                ctx.clip(to: CGRect(x: slotX + 2, y: 0, width: slotW - 4, height: h))
                slot.chord.draw(at: CGPoint(x: slotX + 4, y: (h - 13) / 2), withAttributes: attrs)
                ctx.restoreGState()
                prevChord = slot.chord
            }
        }
        UIGraphicsPopContext()
    }
}

struct PianoRollRepresentable: UIViewRepresentable {
    @Binding var notes: [MelodyNote]
    let totalMeasures: Int
    let beatsPerMeasure: Int
    let gridSize: Double
    @Binding var selectedNoteIndex: Int?
    @Binding var playingNoteIndex: Int?
    var currentBeat: Double = -1.0
    var isPlayingMelody: Bool = false
    var measures: [Measure] = []
    var melodySound: MelodySoundType = .uprightPiano
    var midiMin: Int = 24
    var midiMax: Int = 108
    var onNotesChanged: ([MelodyNote]) -> Void
    var onNoteSelected: (Int?) -> Void
    var onViewCreated: ((PianoRollUIView) -> Void)? = nil
    var cursorBeat: Double = -1

    func makeUIView(context: Context) -> PianoRollUIView {
        let v = PianoRollUIView()
        v.melodySound = melodySound
        v.totalMeasures = totalMeasures
        v.beatsPerMeasure = beatsPerMeasure
        v.gridSize = gridSize
        v.midiMin = midiMin
        v.midiMax = midiMax
        v.notes = notes
        v.onNoteSelected = { idx in DispatchQueue.main.async { onNoteSelected(idx) } }
        v.onNotesChanged = { n in DispatchQueue.main.async { onNotesChanged(n) } }
        DispatchQueue.main.async { onViewCreated?(v) }
        return v
    }

    func updateUIView(_ v: PianoRollUIView, context: Context) {
        var changed = false
        if v.totalMeasures != totalMeasures { v.totalMeasures = totalMeasures; changed = true }
        if v.beatsPerMeasure != beatsPerMeasure { v.beatsPerMeasure = beatsPerMeasure; changed = true }
        if v.gridSize != gridSize { v.gridSize = gridSize }
        if v.notes != notes { v.notes = notes }
        if v.selectedNoteIndex != selectedNoteIndex { v.selectedNoteIndex = selectedNoteIndex }
        if v.playingNoteIndex != playingNoteIndex { v.playingNoteIndex = playingNoteIndex }
        if abs(v.currentBeat - currentBeat) > 0.001 { v.currentBeat = currentBeat }
        if v.melodySound != melodySound { v.melodySound = melodySound }
        if v.isPlayingMelody != isPlayingMelody { v.isPlayingMelody = isPlayingMelody }
        if v.measures.count != measures.count { v.measures = measures }
        if v.midiMin != midiMin { v.midiMin = midiMin; changed = true }
        if v.midiMax != midiMax { v.midiMax = midiMax; changed = true }
        if changed { v.updateLayout() }
        if abs(v.cursorBeat - cursorBeat) > 0.001 { v.cursorBeat = cursorBeat }
    }
}

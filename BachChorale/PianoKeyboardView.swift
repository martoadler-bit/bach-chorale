import UIKit
import SwiftUI

// MARK: - PianoKeyboardUIView

class PianoKeyboardUIView: UIView {

    var onNoteOn:  ((UInt8) -> Void)?
    var onNoteOff: ((UInt8) -> Void)?

    // MIDI 60 (C4) to MIDI 84 (C6) — soprano range
    private let midiMin: UInt8 = 60
    private let midiMax: UInt8 = 84

    // White key MIDI notes in order
    private let whiteKeys: [UInt8] = {
        var keys: [UInt8] = []
        for midi in 60...84 {
            if !isBlack(UInt8(midi)) { keys.append(UInt8(midi)) }
        }
        return keys
    }()

    // Black key MIDI notes
    private let blackKeys: [UInt8] = {
        var keys: [UInt8] = []
        for midi in 60...84 {
            if isBlack(UInt8(midi)) { keys.append(UInt8(midi)) }
        }
        return keys
    }()

    private static func isBlack(_ midi: UInt8) -> Bool {
        let pc = midi % 12
        return [1, 3, 6, 8, 10].contains(pc)
    }

    private var pressedNotes: Set<UInt8> = []
    // Map touch -> current midi note
    private var touchNoteMap: [UITouch: UInt8] = [:]

    private var whiteKeyWidth: CGFloat { bounds.width / CGFloat(whiteKeys.count) }
    private var blackKeyWidth: CGFloat { whiteKeyWidth * 0.6 }
    private var blackKeyHeight: CGFloat { bounds.height * 0.62 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = UIColor(white: 0.3, alpha: 1)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let ww = whiteKeyWidth
        let h  = bounds.height

        // White keys
        for (i, midi) in whiteKeys.enumerated() {
            let x = CGFloat(i) * ww
            let pressed = pressedNotes.contains(midi)
            let fillColor: UIColor = pressed
                ? UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.7)
                : .white
            fillColor.setFill()
            UIColor(white: 0.4, alpha: 1).setStroke()
            let r = CGRect(x: x + 0.5, y: 0.5, width: ww - 1, height: h - 1)
            ctx.fill(r)
            ctx.stroke(r)
        }

        // Black keys (drawn on top)
        let bw = blackKeyWidth
        let bh = blackKeyHeight
        for midi in blackKeys {
            guard let pos = blackKeyXCenter(midi: midi) else { continue }
            let pressed = pressedNotes.contains(midi)
            let fillColor: UIColor = pressed
                ? UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.7)
                : UIColor(white: 0.15, alpha: 1)
            fillColor.setFill()
            let r = CGRect(x: pos - bw/2, y: 0, width: bw, height: bh)
            ctx.fill(r)
        }
    }

    // Returns x-center of black key given its midi note
    private func blackKeyXCenter(midi: UInt8) -> CGFloat? {
        let pc = midi % 12
        // For each black key pitch class, find the white key to its left
        let leftWhitePC: UInt8
        switch pc {
        case 1:  leftWhitePC = 0   // C# left of C
        case 3:  leftWhitePC = 2   // D# left of D
        case 6:  leftWhitePC = 5   // F# left of F
        case 8:  leftWhitePC = 7   // G# left of G
        case 10: leftWhitePC = 9   // A# left of A
        default: return nil
        }
        let octave = Int(midi / 12)
        let leftMidi = UInt8(octave * 12 + Int(leftWhitePC))
        guard leftMidi >= midiMin, leftMidi <= midiMax else { return nil }
        guard let leftIdx = whiteKeys.firstIndex(of: leftMidi) else { return nil }
        let leftX = CGFloat(leftIdx) * whiteKeyWidth
        return leftX + whiteKeyWidth
    }

    // MARK: - Hit testing

    private func midiNote(at point: CGPoint) -> UInt8? {
        let bw = blackKeyWidth
        let bh = blackKeyHeight

        // Check black keys first (they are on top)
        for midi in blackKeys {
            guard let cx = blackKeyXCenter(midi: midi) else { continue }
            let r = CGRect(x: cx - bw/2, y: 0, width: bw, height: bh)
            if r.contains(point) { return midi }
        }

        // Check white keys
        let ww = whiteKeyWidth
        for (i, midi) in whiteKeys.enumerated() {
            let r = CGRect(x: CGFloat(i) * ww, y: 0, width: ww, height: bounds.height)
            if r.contains(point) { return midi }
        }
        return nil
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: self)
            if let midi = midiNote(at: pt) {
                touchNoteMap[touch] = midi
                pressedNotes.insert(midi)
                onNoteOn?(midi)
            }
        }
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: self)
            let newMidi = midiNote(at: pt)
            let oldMidi = touchNoteMap[touch]
            if newMidi != oldMidi {
                if let old = oldMidi {
                    pressedNotes.remove(old)
                    onNoteOff?(old)
                }
                if let new = newMidi {
                    touchNoteMap[touch] = new
                    pressedNotes.insert(new)
                    onNoteOn?(new)
                } else {
                    touchNoteMap.removeValue(forKey: touch)
                }
            }
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let midi = touchNoteMap[touch] {
                pressedNotes.remove(midi)
                onNoteOff?(midi)
                touchNoteMap.removeValue(forKey: touch)
            }
        }
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}

// MARK: - PianoKeyboardRepresentable

struct PianoKeyboardRepresentable: UIViewRepresentable {
    var onNoteOn:  (UInt8) -> Void
    var onNoteOff: (UInt8) -> Void

    func makeUIView(context: Context) -> PianoKeyboardUIView {
        let v = PianoKeyboardUIView()
        v.onNoteOn  = onNoteOn
        v.onNoteOff = onNoteOff
        return v
    }

    func updateUIView(_ v: PianoKeyboardUIView, context: Context) {
        v.onNoteOn  = onNoteOn
        v.onNoteOff = onNoteOff
    }
}

import UIKit
import SwiftUI

// MARK: - Dynamic layout

private struct ScoreLayout {
    let lineSpacing: CGFloat
    let beatWidth: CGFloat
    let labelWidth: CGFloat     // width reserved for voice name on the left
    let headerWidth: CGFloat    // clef + key sig + time sig
    let staffGap: CGFloat       // space between adjacent staves
    let topPad: CGFloat
    let bottomPad: CGFloat
    let noteRadius: CGFloat
    let stemLen: CGFloat
    let clefFontSize: CGFloat
    let accFontSize: CGFloat
    let labelFontSize: CGFloat

    var staffHeight: CGFloat { lineSpacing * 4 }
    var leftMargin: CGFloat  { labelWidth + headerWidth }

    func staffTop(_ i: Int) -> CGFloat {
        topPad + CGFloat(i) * (staffHeight + staffGap)
    }

    var totalHeight: CGFloat {
        staffTop(3) + staffHeight + bottomPad
    }

    init(viewHeight: CGFloat, numAccidentals: Int = 0) {
        // Fit 4 staves + 3 gaps + top/bottom padding into view height
        // totalHeight ≈ ls * 37.5 (derived below)
        let ls = max(8, min(16, viewHeight / 37.5))
        lineSpacing     = ls
        beatWidth       = ls * 2.8
        clefFontSize    = ls * 4.0
        accFontSize     = ls * 1.35
        labelFontSize   = ls * 1.0
        let clefW       = ls * 3.2
        let keySigW     = CGFloat(numAccidentals) * ls * 0.82
        labelWidth      = ls * 5.5
        headerWidth     = clefW + keySigW + ls * 1.2
        topPad          = ls * 2.5
        staffGap        = ls * 4.0
        bottomPad       = ls * 7.0
        noteRadius      = ls * 0.50
        stemLen         = ls * 2.8
    }
}

// MARK: - Staff descriptors for 4 voices

private struct StaffDesc {
    let voice: Voice
    let notes: [ChoralNote]
    let treble: Bool      // true = treble clef, false = bass clef
    let tenorOctave: Bool // true = use 8vb treble clef (tenor); notes displayed +12 for staffPos
    let name: String
}

// MARK: - Staff position helper

/// Returns Y offset from the TOP of a 5-line staff for the given MIDI note.
/// refDia: treble = 34 (B4, middle line), bass = 22 (D3, middle line).
private func staffPos(midi: Int, treble: Bool, ls: CGFloat) -> CGFloat {
    // Maps PC to diatonic step: black keys go to the letter of their conventional spelling.
    // Eb(3)→E(2), F#(6)→F(3), Ab(8)→A(5), Bb(10)→B(6), C#/Db(1)→C(0) or D(1).
    // For display purposes we use the "upper" letter for flat-spelled notes (Eb→E, Bb→B, Ab→A)
    // and the "lower" letter for sharp-spelled notes (F#→F, C#→C, G#→G, D#→D).
    let diaPC: [Int] = [0,0,1,2,2,3,3,4,5,5,6,6]
    let octave = midi / 12 - 1
    let dia    = octave * 7 + diaPC[midi % 12]
    let refDia = treble ? 34 : 22
    return 2 * ls - CGFloat(dia - refDia) * (ls / 2)
}

private func ledgerLines(midi: Int, treble: Bool, ls: CGFloat) -> [CGFloat] {
    let sp   = staffPos(midi: midi, treble: treble, ls: ls)
    let half = ls / 2
    var out: [CGFloat] = []
    if sp < -half / 2 {
        var y = -ls; while y >= sp - half/2 { out.append(y); y -= ls }
    }
    if sp > ls * 4 + half / 2 {
        var y = ls * 5; while y <= sp + half/2 { out.append(y); y += ls }
    }
    return out
}

// MARK: - Key signature helpers

private func keySigInfo(keyRoot: Int, isMinor: Bool) -> (count: Int, isSharps: Bool) {
    // Separate maps so enharmonic spelling matches the displayed note name:
    // note names: C C# D Eb E F F# G Ab A Bb B
    let majorMap: [Int: Int] = [
        0: 0,   // C
        1: 7,   // C#: 7#
        2: 2,   // D:  2#
        3: -3,  // Eb: 3b
        4: 4,   // E:  4#
        5: -1,  // F:  1b
        6: 6,   // F#: 6#
        7: 1,   // G:  1#
        8: -4,  // Ab: 4b
        9: 3,   // A:  3#
        10: -2, // Bb: 2b
        11: 5   // B:  5#
    ]
    let minorMap: [Int: Int] = [
        0: -3,  // Cm  → Eb: 3b
        1: 4,   // C#m → E:  4#
        2: -1,  // Dm  → F:  1b
        3: -6,  // Ebm → Gb: 6b
        4: 1,   // Em  → G:  1#
        5: -4,  // Fm  → Ab: 4b
        6: 3,   // F#m → A:  3#
        7: -2,  // Gm  → Bb: 2b
        8: -7,  // Abm → Cb: 7b
        9: 0,   // Am  → C:  0
        10: -5, // Bbm → Db: 5b
        11: 2   // Bm  → D:  2#
    ]
    let n = isMinor ? (minorMap[keyRoot] ?? 0) : (majorMap[keyRoot] ?? 0)
    return n >= 0 ? (n, true) : (-n, false)
}

// The 7 pitch classes of a key's scale.
// Also returns whether the key prefers sharps for spelling chromatic notes.
private func scaleInfo(keyRoot: Int, isMinor: Bool) -> (scalePCs: [Int], preferSharps: Bool) {
    let majorSteps = [0,2,4,5,7,9,11]
    let minorSteps = [0,2,3,5,7,8,10]
    let pcs = (isMinor ? minorSteps : majorSteps).map { (keyRoot + $0) % 12 }
    let (_, isSharps) = keySigInfo(keyRoot: keyRoot, isMinor: isMinor)
    return (pcs, isSharps)
}

// Given a pitch class, returns the "letter" index (0=C 1=D 2=E 3=F 4=G 5=A 6=B)
// and the "natural PC" for that letter.
// Black keys use conventional tonal spelling:
//   C#/Db → C# in sharp keys, Db in flat keys
//   D#/Eb → always Eb
//   F#/Gb → always F#
//   G#/Ab → always Ab
//   A#/Bb → always Bb
private func letterInfo(pc: Int, preferSharps: Bool) -> (letter: Int, naturalPC: Int) {
    switch pc {
    case 0:  return (0, 0)   // C
    case 1:  return (0, 0)   // C# (staffPos puts PC 1 at C's line/space)
    case 2:  return (1, 2)   // D
    case 3:  return (2, 4)   // Eb (almost never D# in tonal music)
    case 4:  return (2, 4)   // E
    case 5:  return (3, 5)   // F
    case 6:  return (3, 5)   // F# (almost never Gb in tonal music)
    case 7:  return (4, 7)   // G
    case 8:  return (5, 9)   // Ab (almost never G# in tonal music)
    case 9:  return (5, 9)   // A
    case 10: return (6, 11)  // Bb (almost never A# in tonal music)
    case 11: return (6, 11)  // B
    default: return (0, 0)
    }
}

// Returns the accidental symbol to show before a note, or nil if none needed.
// measureState: [letter 0-6 → currently active PC for that letter]
//   Defaults to what the scale says; reset at each barline.
private func accidentalSymbol(midi: Int, scalePCs: [Int], preferSharps: Bool,
                               measureState: inout [Int: Int]) -> String? {
    let pc = midi % 12
    let (letter, naturalPC) = letterInfo(pc: pc, preferSharps: preferSharps)

    // What does the scale prescribe for this letter?
    // Look up which scale PC shares this letter.
    let nat = [0,2,4,5,7,9,11]
    let scalePC: Int = scalePCs.first(where: { letterInfo(pc: $0, preferSharps: preferSharps).letter == letter }) ?? naturalPC

    // What's currently active in this measure for this letter?
    let activePC = measureState[letter] ?? scalePC

    if pc == activePC { return nil }  // already correct — no symbol needed

    // Need an accidental
    let sym: String
    if pc == naturalPC {
        sym = "♮"
    } else if pc == (naturalPC + 1) % 12 {
        sym = "♯"
    } else if pc == (naturalPC + 11) % 12 {
        sym = "♭"
    } else {
        sym = preferSharps ? "♯" : "♭"
    }

    measureState[letter] = pc
    return sym
}

private func unicodeForAccidental(_ sym: String) -> UInt32 {
    switch sym {
    case "♯": return 0xE262  // Bravura: sharp
    case "♭": return 0xE260  // Bravura: flat
    case "♮": return 0xE261  // Bravura: natural
    default:  return 0xE261
    }
}

private let sharpMidiTreble: [Int] = [77, 72, 79, 74, 69, 76, 71]
private let flatMidiTreble:  [Int] = [71, 76, 69, 74, 67, 72, 65]
private let sharpMidiBass:   [Int] = [53, 48, 55, 50, 45, 52, 47]
private let flatMidiBass:    [Int] = [47, 52, 45, 50, 43, 48, 41]

// MARK: - ChoraleScoreUIView

private struct NoteGlow {
    let glowLayer: CALayer
    let voice: Voice
    let beatPosition: Double
    let duration: Double
}

private struct ChordGlow {
    let layer: CALayer
    let beatPosition: Double
    let duration: Double
}

private struct TieDot {
    let layer: CALayer
    let voice: Voice
    let startBeat: Double
    let duration: Double
    let p0: CGPoint
    let p1: CGPoint
    let p2: CGPoint
}

private func quadBezier(t: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint) -> CGPoint {
    let mt = 1 - t
    return CGPoint(x: mt*mt*p0.x + 2*mt*t*p1.x + t*t*p2.x,
                   y: mt*mt*p0.y + 2*mt*t*p1.y + t*t*p2.y)
}

class ChoraleScoreUIView: UIView {
    var chorale:     ChoraleData = ChoraleData() { didSet { rebuildLayout(); redraw() } }
    var currentBeat: Double = -1.0               { didSet { updateHighlights() } }

    var mutedVoices: Set<Voice> = [] { didSet { redrawImage() } }

    private let scrollView = UIScrollView()
    private let canvas     = UIView()
    private var layout     = ScoreLayout(viewHeight: 300)
    // beat position → absolute x in canvas (accounts for accidental extra space)
    private var beatXMap: [Double: CGFloat] = [:]
    private var noteGlows:  [NoteGlow]  = []
    private var chordGlows: [ChordGlow] = []
    private var tieDots:    [TieDot]    = []
    private var imgLayer   = CALayer()

    // Smooth scrolling: CADisplayLink interpolates scroll between beat updates
    private var displayLink: CADisplayLink?
    private var anchorBeat: Double = 0
    private var anchorTime: CFTimeInterval = 0
    private var beatsPerSecond: Double = 2.0

    private let bgColor      = UIColor.black
    private let staffColor   = UIColor(white: 1, alpha: 0.45)
    private let barColor     = UIColor(white: 1, alpha: 0.35)
    private let clefColor    = UIColor(white: 1, alpha: 0.55)
    private let rnColor      = UIColor(red: 0.95, green: 0.76, blue: 0.25, alpha: 1)
    private let fermataColor = UIColor(white: 1, alpha: 0.88)
    private let labelColor   = UIColor(white: 0.65, alpha: 1)

    private var totalBeats: Double {
        chorale.soprano.map { $0.beatPosition + $0.duration }.max() ?? 16.0
    }
    private var contentWidth: CGFloat {
        let lastX = beatXMap.values.max() ?? (layout.leftMargin + CGFloat(totalBeats) * layout.beatWidth)
        return lastX + layout.beatWidth + layout.lineSpacing * 3
    }

    // Fixed chord display — shows current chord in one place, doesn't scroll
    private let chordPill = UIView()
    private let chordDegreeLabel = UILabel()
    private let chordNameLabel   = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = bgColor
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = true
        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Chord pill — fixed bottom-left, above scroll indicator
        chordPill.backgroundColor = UIColor(red: 0.14, green: 0.10, blue: 0.22, alpha: 0.92)
        chordPill.layer.cornerRadius = 10
        chordPill.layer.borderColor  = rnColor.withAlphaComponent(0.5).cgColor
        chordPill.layer.borderWidth  = 1.2
        chordPill.isHidden = true
        addSubview(chordPill)
        chordPill.translatesAutoresizingMaskIntoConstraints = false

        chordDegreeLabel.font      = UIFont.boldSystemFont(ofSize: 18)
        chordDegreeLabel.textColor = rnColor
        chordDegreeLabel.textAlignment = .center
        chordNameLabel.font        = UIFont.systemFont(ofSize: 12, weight: .medium)
        chordNameLabel.textColor   = UIColor(white: 0.80, alpha: 1)
        chordNameLabel.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [chordDegreeLabel, chordNameLabel])
        stack.axis = .vertical; stack.spacing = 1
        chordPill.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            chordPill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            chordPill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            chordPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),

            stack.topAnchor.constraint(equalTo: chordPill.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: chordPill.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: chordPill.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: chordPill.trailingAnchor, constant: -10),
        ])
        scrollView.addSubview(canvas)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rebuildLayout() {
        let (count, _) = keySigInfo(keyRoot: chorale.keyRoot, isMinor: chorale.isMinor)
        layout = ScoreLayout(viewHeight: bounds.height > 0 ? bounds.height : 300,
                             numAccidentals: count)
        beatXMap = buildBeatXMap()
    }

    /// Returns absolute canvas x for a given beat position.
    private func xFor(beat: Double) -> CGFloat {
        // Exact hit
        if let x = beatXMap[beat] { return x }
        // Interpolate between surrounding known beats (for tie arcs etc.)
        let sorted = beatXMap.keys.sorted()
        guard !sorted.isEmpty else {
            return layout.leftMargin + CGFloat(beat) * layout.beatWidth
        }
        if beat <= sorted.first! { return beatXMap[sorted.first!]! }
        if beat >= sorted.last!  { return beatXMap[sorted.last!]! }
        let lo = sorted.last  { $0 < beat }!
        let hi = sorted.first { $0 > beat }!
        let t  = CGFloat((beat - lo) / (hi - lo))
        return beatXMap[lo]! + t * (beatXMap[hi]! - beatXMap[lo]!)
    }

    /// Pre-compute x position for every beat across all voices.
    /// Beats that have an accidental in any voice get extra horizontal padding.
    private func buildBeatXMap() -> [Double: CGFloat] {
        let ls = layout.lineSpacing
        guard !chorale.isEmpty else { return [:] }

        // Collect all unique beat positions across all voices, plus barline beats
        // so that notes starting at measure boundaries (from splitAtBarLines) are
        // placed correctly and never land visually on the barline.
        let pickup   = chorale.pickupBeats
        let allNotes = chorale.soprano + chorale.alto + chorale.tenor + chorale.bass
        var rawBeats = Set(allNotes.map { $0.beatPosition })
        let maxBeat  = (rawBeats.max() ?? 0) + 4.0
        var barBeat  = pickup > 0 ? pickup : 4.0
        while barBeat <= maxBeat { rawBeats.insert(barBeat); barBeat += 4.0 }
        let beatSet  = rawBeats.sorted()
        guard !beatSet.isEmpty else { return [:] }

        // Determine which beats need accidental space (any voice has an accidental there)
        let (scalePCs, preferSharps) = scaleInfo(keyRoot: chorale.keyRoot, isMinor: chorale.isMinor)
        var measureState = [Int: Int]()
        var currentMeasure = -1

        // We need to walk through notes in order, tracking measure state per voice,
        // to know which beats actually produce an accidental symbol.
        var beatsNeedingAcc = Set<Double>()
        for voice in [chorale.soprano, chorale.alto, chorale.tenor, chorale.bass] {
            var ms = [Int: Int]()
            var cm = -1
            for note in voice.sorted(by: { $0.beatPosition < $1.beatPosition }) {
                let meas: Int = note.beatPosition < pickup ? 0
                    : 1 + Int((note.beatPosition - pickup) / 4.0)
                if meas != cm { cm = meas; ms = [:] }
                if accidentalSymbol(midi: Int(note.midiNote), scalePCs: scalePCs,
                                    preferSharps: preferSharps, measureState: &ms) != nil {
                    beatsNeedingAcc.insert(note.beatPosition)
                }
            }
        }

        // Base beat width and extra padding when an accidental is present
        let baseW: CGFloat = layout.beatWidth
        let accExtra: CGFloat = ls * 1.2   // extra space for an accidental
        // Minimum width per beat slot so short notes (sixteenths) don't crowd.
        // This makes measures with more notes wider (dynamic measure widths).
        let minSlotW: CGFloat = ls * 2.2

        // Build cumulative x map
        var map = [Double: CGFloat]()
        var curX = layout.leftMargin + ls * 1.0   // first note offset (matches drawNotes)
        for (idx, beat) in beatSet.enumerated() {
            map[beat] = curX
            // Width to allocate before the next beat
            if idx + 1 < beatSet.count {
                let nextBeat = beatSet[idx + 1]
                let nominalW = max(CGFloat(nextBeat - beat) * baseW, minSlotW)
                let extra    = beatsNeedingAcc.contains(nextBeat) ? accExtra : 0
                curX += nominalW + extra
            }
        }
        return map
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildLayout()
        if !chorale.isEmpty { redraw() }
    }

    // MARK: - Redraw

    private func redraw() {
        let savedOffset = scrollView.contentOffset

        canvas.subviews.forEach { $0.removeFromSuperview() }
        canvas.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        noteGlows  = []
        chordGlows = []
        chordPill.isHidden = true
        tieDots    = []

        let h = layout.totalHeight
        let w = contentWidth
        canvas.frame = CGRect(x: 0, y: 0, width: w, height: h)
        scrollView.contentSize = CGSize(width: w, height: h)
        scrollView.contentOffset = savedOffset

        imgLayer = CALayer()
        imgLayer.frame = canvas.bounds
        redrawImage()
        canvas.layer.addSublayer(imgLayer)

        setupGlowLayers()
        updateHighlights()
    }

    private func redrawImage() {
        UIGraphicsBeginImageContextWithOptions(canvas.bounds.size, false, UIScreen.main.scale)
        if let ctx = UIGraphicsGetCurrentContext() { drawAll(ctx: ctx, size: canvas.bounds.size) }
        imgLayer.contents = UIGraphicsGetImageFromCurrentImageContext()?.cgImage
        UIGraphicsEndImageContext()
    }

    private func setupGlowLayers() {
        let ls = layout.lineSpacing
        for (i, sd) in staves().enumerated() {
            let staffTopY = layout.staffTop(i)
            let c         = sd.voice.color
            let glowColor = UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1.0)
            let fillColor = UIColor(red: c.r, green: c.g, blue: c.b, alpha: 0.25).cgColor
            let dotColor  = UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1.0)

            for (seg, isTied) in splitAtBarLines(sd.notes) {
                let dispMidi = sd.tenorOctave ? Int(seg.midiNote) + 12 : Int(seg.midiNote)
                let x  = xFor(beat: seg.beatPosition)
                let sp = staffPos(midi: dispMidi, treble: sd.treble, ls: ls)
                let y  = staffTopY + sp
                let r  = layout.noteRadius
                let gr = ls * 1.5

                // Glow halo (active during playback)
                let glowLayer = CALayer()
                glowLayer.frame = CGRect(x: x - gr, y: y - gr, width: gr*2, height: gr*2)
                glowLayer.cornerRadius = gr
                glowLayer.backgroundColor = fillColor
                glowLayer.shadowColor   = glowColor.cgColor
                glowLayer.shadowRadius  = ls * 2.0
                glowLayer.shadowOpacity = 0.0
                glowLayer.shadowOffset  = .zero
                glowLayer.isHidden = true
                canvas.layer.addSublayer(glowLayer)

                noteGlows.append(NoteGlow(glowLayer: glowLayer,
                                          voice: sd.voice,
                                          beatPosition: seg.beatPosition,
                                          duration: seg.duration))

                // Travelling dot along tie arc
                if isTied {
                    let stemUp = sp > 2 * ls
                    let cv: CGFloat  = stemUp ? 1 : -1
                    let arcY: CGFloat = stemUp ? y + r*1.8 : y - r*1.8
                    let nx = xFor(beat: seg.beatPosition + seg.duration) + ls*0.55 - ls*1.0
                    let p0 = CGPoint(x: x + r,       y: arcY)
                    let p1 = CGPoint(x: (x+nx)/2,    y: arcY + cv*ls*0.5)
                    let p2 = CGPoint(x: nx - r,       y: arcY)

                    let dr = ls * 1.5   // same size as glow halo
                    let dotLayer = CALayer()
                    dotLayer.bounds = CGRect(x: 0, y: 0, width: dr*2, height: dr*2)
                    dotLayer.position = p0
                    dotLayer.cornerRadius = dr
                    dotLayer.backgroundColor = fillColor   // same semi-transparent fill as halo
                    dotLayer.shadowColor   = glowColor.cgColor
                    dotLayer.shadowRadius  = ls * 2.0
                    dotLayer.shadowOpacity = 0.0
                    dotLayer.shadowOffset  = .zero
                    dotLayer.isHidden = true
                    canvas.layer.addSublayer(dotLayer)
                    tieDots.append(TieDot(layer: dotLayer,
                                          voice: sd.voice,
                                          startBeat: seg.beatPosition,
                                          duration: seg.duration,
                                          p0: p0, p1: p1, p2: p2))
                }
            }
        }
    }

    private func staffAlpha(_ staffIndex: Int) -> CGFloat {
        mutedVoices.contains(Voice(rawValue: staffIndex)!) ? 0.18 : 1.0
    }

    private func staves() -> [StaffDesc] {
        [
            StaffDesc(voice: .soprano, notes: chorale.soprano, treble: true,  tenorOctave: false, name: "Soprano"),
            StaffDesc(voice: .alto,    notes: chorale.alto,    treble: true,  tenorOctave: false, name: "Alto"),
            StaffDesc(voice: .tenor,   notes: chorale.tenor,   treble: true,  tenorOctave: true,  name: "Tenor"),
            StaffDesc(voice: .bass,    notes: chorale.bass,    treble: false, tenorOctave: false,  name: "Bass"),
        ]
    }

    private func drawAll(ctx: CGContext, size: CGSize) {
        UIGraphicsPushContext(ctx)
        bgColor.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        drawStaves(ctx: ctx, size: size)
        drawClefs(ctx: ctx)
        drawKeySig(ctx: ctx)

        drawBarLines(ctx: ctx)
        drawNotes(ctx: ctx)
        drawFermatas(ctx: ctx)

        // chord label drawn as fixed pill overlay, not on canvas
        UIGraphicsPopContext()
    }

    // MARK: - Staves

    private func drawStaves(ctx: CGContext, size: CGSize) {
        let ls = layout.lineSpacing
        staffColor.setStroke()
        ctx.setLineWidth(0.8)
        let x0: CGFloat = layout.labelWidth
        let x1 = size.width - 4

        ctx.setLineWidth(0.8)
        for i in 0..<4 {
            ctx.setAlpha(staffAlpha(i))
            staffColor.setStroke()
            let topY = layout.staffTop(i)
            for line in 0..<5 {
                let y = topY + CGFloat(line) * ls
                ctx.move(to: CGPoint(x: x0, y: y))
                ctx.addLine(to: CGPoint(x: x1, y: y))
            }
            ctx.strokePath()
        }
        ctx.setAlpha(1.0)

        // Thin system line connecting all staves on the left
        clefColor.withAlphaComponent(0.45).setStroke()
        ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: x0, y: layout.staffTop(0)))
        ctx.addLine(to: CGPoint(x: x0, y: layout.staffTop(3) + layout.staffHeight))
        ctx.strokePath()

        // Voice name labels
        let allStaves = staves()
        UIGraphicsPushContext(ctx)
        let labelFont = UIFont.systemFont(ofSize: layout.labelFontSize, weight: .medium)
        for (i, sd) in allStaves.enumerated() {
            let topY = layout.staffTop(i)
            let centerY = topY + layout.staffHeight / 2
            let a = staffAlpha(i)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: labelColor.withAlphaComponent(a)
            ]
            let str = sd.name as NSString
            let sz  = str.size(withAttributes: attrs)
            str.draw(at: CGPoint(x: layout.labelWidth - sz.width - ls * 0.5,
                                 y: centerY - sz.height / 2), withAttributes: attrs)
        }
        UIGraphicsPopContext()
    }

    // MARK: - Bravura glyph helper

    @discardableResult
    private func drawBravura(_ codepoint: UInt32, x: CGFloat, baselineY: CGFloat,
                              fontSize: CGFloat, color: UIColor) -> CGFloat {
        guard let scalar = Unicode.Scalar(codepoint),
              let font   = UIFont(name: "Bravura", size: fontSize) else { return 0 }
        let str  = String(scalar) as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        str.draw(at: CGPoint(x: x, y: baselineY - font.ascender), withAttributes: attrs)
        return str.size(withAttributes: attrs).width
    }

    // MARK: - Clefs

    private func drawClefs(ctx: CGContext) {
        let ls  = layout.lineSpacing
        let x0  = layout.labelWidth
        let fs  = layout.clefFontSize
        UIGraphicsPushContext(ctx)
        for (i, sd) in staves().enumerated() {
            let topY  = layout.staffTop(i)
            let color = clefColor.withAlphaComponent(clefColor.cgColor.alpha * staffAlpha(i))
            if sd.treble {
                let clef: UInt32 = sd.tenorOctave ? 0xE052 : 0xE050
                drawBravura(clef, x: x0 + ls * 0.2, baselineY: topY + 3 * ls,
                            fontSize: fs, color: color)
            } else {
                drawBravura(0xE062, x: x0 + ls * 0.3, baselineY: topY + 1 * ls,
                            fontSize: fs, color: color)
            }
        }
        UIGraphicsPopContext()
    }

    // MARK: - Key signature

    private func drawKeySig(ctx: CGContext) {
        guard !chorale.isEmpty else { return }
        let (count, isSharps) = keySigInfo(keyRoot: chorale.keyRoot, isMinor: chorale.isMinor)
        guard count > 0 else { return }

        UIGraphicsPushContext(ctx)
        let ls   = layout.lineSpacing
        let fs   = layout.accFontSize
        let sym  = isSharps ? "♯" : "♭"
        let clefEndX = layout.labelWidth + ls * 3.4
        let stepX    = ls * 0.82

        for (i, sd) in staves().enumerated() {
            let topY   = layout.staffTop(i)
            let color  = clefColor.withAlphaComponent(clefColor.cgColor.alpha * staffAlpha(i))
            let staffAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fs, weight: .light),
                .foregroundColor: color
            ]
            let midis  = sd.treble
                ? (isSharps ? sharpMidiTreble : flatMidiTreble)
                : (isSharps ? sharpMidiBass   : flatMidiBass)
            for j in 0..<count {
                let x  = clefEndX + CGFloat(j) * stepX
                let sp = staffPos(midi: midis[j], treble: sd.treble, ls: ls)
                let y  = topY + sp - fs * 0.72
                (sym as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: staffAttrs)
            }
        }
        UIGraphicsPopContext()
    }

    // MARK: - Chord label highlight layers

    private func setupChordLayers() {
        guard !chorale.chordLabels.isEmpty else { return }
        let ls      = layout.lineSpacing
        let bassBot = layout.staffTop(3) + layout.staffHeight
        let labelY  = bassBot + ls * 3.2
        let rnSize: CGFloat = ls * 1.4
        let chSize: CGFloat = ls * 0.82
        let pillH   = rnSize + chSize + ls * 0.8
        let pad: CGFloat = ls * 0.45

        let rnAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: rnSize), .foregroundColor: rnColor]
        let chAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: chSize, weight: .medium),
            .foregroundColor: UIColor(white: 0.80, alpha: 1)]

        var deduped: [ChordLabel] = []
        for cl in chorale.chordLabels {
            if deduped.last?.degree != cl.degree { deduped.append(cl) }
        }

        // Pass 1: determine which labels are actually visible (pass the overlap check)
        struct VisibleChord { let cl: ChordLabel; let beatX: CGFloat; let pillW: CGFloat }
        var visible: [VisibleChord] = []
        var nextAvailableX: CGFloat = 0
        for cl in deduped {
            let beatX = xFor(beat: cl.beatPosition) + 2
            guard beatX >= nextAvailableX else { continue }
            let rnW   = cl.degree.isEmpty ? 0 : (cl.degree as NSString).size(withAttributes: rnAttrs).width
            let chW   = (cl.label as NSString).size(withAttributes: chAttrs).width
            let pillW = max(rnW, chW) + ls * 0.9
            nextAvailableX = beatX - pad + pillW + ls * 0.3
            visible.append(VisibleChord(cl: cl, beatX: beatX, pillW: pillW))
        }

        // Pass 2: create glow layers with duration = until next VISIBLE chord.
        // This prevents gaps where no label is highlighted.
        for (i, vc) in visible.enumerated() {
            let dur = i + 1 < visible.count
                ? visible[i + 1].cl.beatPosition - vc.cl.beatPosition
                : totalBeats - vc.cl.beatPosition

            let layer = CALayer()
            layer.frame           = CGRect(x: vc.beatX - pad, y: labelY - pad * 0.5,
                                           width: vc.pillW, height: pillH)
            layer.cornerRadius    = ls * 0.45
            layer.backgroundColor = rnColor.withAlphaComponent(0.18).cgColor
            layer.borderColor     = rnColor.cgColor
            layer.borderWidth     = 1.2
            layer.shadowColor     = rnColor.cgColor
            layer.shadowRadius    = ls * 2.0
            layer.shadowOffset    = .zero
            layer.shadowOpacity   = 0.0
            layer.isHidden        = true
            canvas.layer.addSublayer(layer)
            chordGlows.append(ChordGlow(layer: layer,
                                        beatPosition: vc.cl.beatPosition, duration: dur))
        }
    }

    // MARK: - Time signature


    // MARK: - Bar lines

    private func drawBarLines(ctx: CGContext) {
        guard !chorale.isEmpty else { return }
        let ls      = layout.lineSpacing
        let pickup  = chorale.pickupBeats
        barColor.setStroke()
        ctx.setLineWidth(0.8)
        // First barline after the pickup (or after 4 beats if no pickup)
        var beat = pickup > 0 ? pickup : 4.0
        while beat < totalBeats - 0.01 {
            let x = xFor(beat: beat) - ls * 1.0   // barline at left edge of beat (undo note offset)
            for i in 0..<4 {
                let topY = layout.staffTop(i)
                ctx.move(to: CGPoint(x: x, y: topY))
                ctx.addLine(to: CGPoint(x: x, y: topY + layout.staffHeight))
            }
            beat += 4.0
        }
        ctx.strokePath()

        // Final double bar spanning all staves
        let fx   = (beatXMap.keys.max().map { xFor(beat: $0) } ?? layout.leftMargin) + layout.beatWidth
        let topY = layout.staffTop(0)
        let botY = layout.staffTop(3) + layout.staffHeight
        ctx.setLineWidth(1.0)
        ctx.move(to: CGPoint(x: fx + ls*0.3, y: topY))
        ctx.addLine(to: CGPoint(x: fx + ls*0.3, y: botY))
        ctx.strokePath()
        clefColor.withAlphaComponent(0.85).setStroke()
        ctx.setLineWidth(ls * 0.35)
        ctx.move(to: CGPoint(x: fx + ls*0.78, y: topY))
        ctx.addLine(to: CGPoint(x: fx + ls*0.78, y: botY))
        ctx.strokePath()
    }

    // MARK: - Notes

    private func drawNotes(ctx: CGContext) {
        UIGraphicsPushContext(ctx)
        let ls = layout.lineSpacing
        let (scalePCs, preferSharps) = scaleInfo(keyRoot: chorale.keyRoot, isMinor: chorale.isMinor)

        for (i, sd) in staves().enumerated() {
            ctx.setAlpha(staffAlpha(i))
            let c         = sd.voice.color
            let noteColor = UIColor(red: c.r, green: c.g, blue: c.b, alpha: 0.92)
            let stemColor = UIColor(red: c.r*0.8, green: c.g*0.8, blue: c.b*0.8, alpha: 1)
            let staffTopY = layout.staffTop(i)
            let r         = layout.noteRadius
            let treble    = sd.treble
            // Tracks active accidentals per letter within the current measure
            var measureState = [Int: Int]()
            var currentMeasure = -1
            // Right edge of the last drawn element (note head or accidental), to avoid overlaps
            var lastRightEdge: CGFloat = 0
            var lastNoteheadRight: CGFloat = 0
            var lastBeat: Double = -1

            // ── Beam group detection ──────────────────────────────────────────────────
            // Rules:
            //  • Only sub-beat notes (dur < 1.0) can beam.
            //  • Group = consecutive sub-beat notes within the SAME integer beat AND
            //    the SAME measure. Mixed durations (e.g. ♪♬♬) are allowed.
            //  • Beams are drawn AFTER the main note loop using recorded stem tips so
            //    we always draw one straight line per group (never zigzag).
            let pickup = chorale.pickupBeats
            func measureOf(_ beat: Double) -> Int {
                beat < pickup ? 0 : 1 + Int((beat - pickup) / 4.0)
            }

            struct BeamGroup {
                var beats:     [Double]
                var durations: [Double]   // parallel to beats
                var stemUp:    Bool
            }
            var beamGroups: [BeamGroup] = []
            var beamStemUp = [Double: Bool]()

            let allSegs = splitAtBarLines(sd.notes).map { $0.0 }
            var ki = 0
            while ki < allSegs.count {
                let first = allSegs[ki]
                guard first.duration < 1.0 else { ki += 1; continue }

                var groupBeats = [first.beatPosition]
                var groupDurs  = [first.duration]
                var groupMidi  = [sd.tenorOctave ? Int(first.midiNote) + 12 : Int(first.midiNote)]
                var ji = ki + 1
                while ji < allSegs.count {
                    let prev = allSegs[ji - 1]; let nxt = allSegs[ji]
                    guard nxt.duration < 1.0,
                          abs((prev.beatPosition + prev.duration) - nxt.beatPosition) < 0.001,
                          floor(prev.beatPosition) == floor(nxt.beatPosition),
                          measureOf(prev.beatPosition) == measureOf(nxt.beatPosition)
                    else { break }
                    groupBeats.append(nxt.beatPosition)
                    groupDurs.append(nxt.duration)
                    groupMidi.append(sd.tenorOctave ? Int(nxt.midiNote) + 12 : Int(nxt.midiNote))
                    ji += 1
                }

                if groupBeats.count >= 2 {
                    let avgSp = groupMidi.map { staffPos(midi: $0, treble: treble, ls: ls) }
                                         .reduce(0, +) / CGFloat(groupMidi.count)
                    let up = avgSp > 2 * ls
                    beamGroups.append(BeamGroup(beats: groupBeats, durations: groupDurs, stemUp: up))
                    for b in groupBeats { beamStemUp[b] = up }
                    ki = ji
                } else {
                    ki += 1
                }
            }

            // Pre-compute the beam-line Y for every note in a beam group so that
            // each stem is drawn exactly to the beam, with no overshoot or shortfall.
            // Strategy: for each group, the beam goes from (x0,tipY0) to (xN,tipYN)
            // where tipY = notehead_y ± stemLen for the first and last note.
            // Every intermediate note's stem tip is the linear interpolation along that line.
            var beamTipY = [Double: CGFloat]()
            for group in beamGroups {
                guard group.beats.count >= 2 else { continue }
                let up = group.stemUp
                // x and notehead y for each beat in the group
                var xs     = [CGFloat](); var noteYs = [CGFloat]()
                for beat in group.beats {
                    guard let seg = allSegs.first(where: { abs($0.beatPosition - beat) < 0.001 }) else { continue }
                    let disp = sd.tenorOctave ? Int(seg.midiNote) + 12 : Int(seg.midiNote)
                    xs.append(xFor(beat: beat))
                    noteYs.append(staffTopY + staffPos(midi: disp, treble: treble, ls: ls))
                }
                guard xs.count == group.beats.count else { continue }
                let tip0 = noteYs.first! + (up ? -layout.stemLen : layout.stemLen)
                let tipN = noteYs.last!  + (up ? -layout.stemLen : layout.stemLen)
                let x0 = xs.first!; let xN = xs.last!; let spanX = xN - x0
                for (i, beat) in group.beats.enumerated() {
                    let t = spanX > 0 ? (xs[i] - x0) / spanX : 0
                    beamTipY[beat] = tip0 + t * (tipN - tip0)
                }
            }

            // stem tips recorded here; beams drawn after the main loop
            var stemTips = [Double: (x: CGFloat, y: CGFloat)]()

            for (seg, isTied) in splitAtBarLines(sd.notes) {
                // Tenor notes displayed an octave higher (8vb clef)
                let dispMidi = sd.tenorOctave ? Int(seg.midiNote) + 12 : Int(seg.midiNote)

                let x   = xFor(beat: seg.beatPosition)
                let sp  = staffPos(midi: dispMidi, treble: treble, ls: ls)
                let y   = staffTopY + sp
                let dur = seg.duration

                // At each new beat, reset lastRightEdge to the previous notehead's right
                // edge so accidentals don't overlap prior noteheads, but displaced
                // accidentals from prior beats don't cascade into unrelated beats.
                if seg.beatPosition != lastBeat {
                    lastRightEdge = lastNoteheadRight
                    lastBeat = seg.beatPosition
                }

                // Reset accidental state at each new measure
                let measure = measureOf(seg.beatPosition)
                if measure != currentMeasure {
                    currentMeasure = measure
                    measureState = [:]
                }

                // Ledger lines
                stemColor.withAlphaComponent(0.5).setStroke()
                ctx.setLineWidth(1.0)
                for ly in ledgerLines(midi: dispMidi, treble: treble, ls: ls) {
                    let p = UIBezierPath()
                    p.move(to: CGPoint(x: x - r*1.8, y: staffTopY + ly))
                    p.addLine(to: CGPoint(x: x + r*1.8, y: staffTopY + ly))
                    p.stroke()
                }

                // Accidental (shown to the left of the note head)
                let accSym = accidentalSymbol(midi: dispMidi, scalePCs: scalePCs,
                                              preferSharps: preferSharps, measureState: &measureState)
                let accWidth: CGFloat = ls * 1.1

                if let sym = accSym {
                    // Place accidental at ideal position, or push right if previous element overlaps
                    let idealAccX = x - ls * 1.5
                    let accX = lastRightEdge + ls * 0.1 > idealAccX ? lastRightEdge + ls * 0.1 : idealAccX
                    drawBravura(unicodeForAccidental(sym), x: accX, baselineY: y,
                                fontSize: ls * 2.8, color: noteColor)
                    lastRightEdge = accX + accWidth
                }

                // Note head — shift right if accidental consumed space
                let nhX = lastRightEdge + ls * 0.15 > x - ls * 0.45 && accSym != nil
                    ? lastRightEdge + ls * 0.15
                    : x - ls * 0.45
                let headCode: UInt32 = dur >= 4.0 ? 0xE0A2 : (dur >= 2.0 ? 0xE0A3 : 0xE0A4)
                let nhAdv = drawBravura(headCode, x: nhX, baselineY: y,
                                        fontSize: ls * 3.2, color: noteColor)
                lastRightEdge = max(lastRightEdge, nhX + nhAdv)
                lastNoteheadRight = nhX + nhAdv

                // Stem direction: if note is part of a beam group use the shared direction,
                // otherwise apply the classical per-note rule (up if below middle line).
                let stemUp = beamStemUp[seg.beatPosition] ?? (sp > 2 * ls)

                // Stem
                if dur < 4.0 {
                    stemColor.setStroke(); ctx.setLineWidth(1.3)
                    let sx = stemUp ? (nhX + nhAdv - 0.5) : (nhX + 0.5)
                    // Beamed notes: stem reaches exactly to the beam line (pre-computed).
                    let tipY = beamTipY[seg.beatPosition] ?? (stemUp ? y - layout.stemLen : y + layout.stemLen)
                    let p  = UIBezierPath()
                    p.move(to: CGPoint(x: sx, y: y))
                    p.addLine(to: CGPoint(x: sx, y: tipY))
                    p.stroke()
                    if dur < 1.0 {
                        stemTips[seg.beatPosition] = (sx, tipY)
                        // Flags only on isolated notes (not in any beam group)
                        if beamStemUp[seg.beatPosition] == nil {
                            let cv: CGFloat = stemUp ? 1 : -1
                            let numFlags = dur <= 0.25 ? 2 : 1
                            for fi in 0..<numFlags {
                                let flagOriginY = tipY + cv * CGFloat(fi) * ls * 0.55
                                let fp = UIBezierPath()
                                fp.move(to: CGPoint(x: sx, y: flagOriginY))
                                fp.addCurve(to: CGPoint(x: sx + ls, y: flagOriginY + cv*ls*1.2),
                                            controlPoint1: CGPoint(x: sx+ls, y: flagOriginY+cv*ls*0.4),
                                            controlPoint2: CGPoint(x: sx+ls, y: flagOriginY+cv*ls*0.9))
                                ctx.setLineWidth(1.6); fp.stroke()
                            }
                        }
                    }
                }

                // Dot for dotted notes
                if (dur >= 1.0 && dur.truncatingRemainder(dividingBy: 1.0) == 0.5) ||
                   (dur > 1.0 && dur.truncatingRemainder(dividingBy: 2.0) == 1.0) {
                    let dotR: CGFloat = r * 0.45
                    let dotX = nhX + nhAdv + dotR * 1.5
                    // If note is on a line, shift dot up into the space above
                    let dotY = y - (Int((sp / ls).rounded()) % 2 == 0 ? ls * 0.5 : 0)
                    noteColor.setFill()
                    UIBezierPath(ovalIn: CGRect(x: dotX - dotR, y: dotY - dotR,
                                               width: dotR*2, height: dotR*2)).fill()
                }

                // Tie arc (curves opposite to stem direction)
                if isTied {
                    let nx   = xFor(beat: seg.beatPosition + dur) + ls*0.55 - ls*1.0
                    let arcY = stemUp ? y + r*1.8 : y - r*1.8
                    let cv: CGFloat = stemUp ? 1 : -1
                    let tp = UIBezierPath()
                    tp.move(to: CGPoint(x: nhX + r, y: arcY))
                    tp.addQuadCurve(to: CGPoint(x: nx - r, y: arcY),
                                    controlPoint: CGPoint(x: (x+nx)/2, y: arcY + cv*ls*0.5))
                    noteColor.withAlphaComponent(0.6).setStroke(); ctx.setLineWidth(1.6); tp.stroke()
                }
            }   // end for (seg, isTied)

            // ── Draw beams (second pass, after all stem tips recorded) ──────────────
            let beamW:  CGFloat = ls * 0.8
            let beamGap: CGFloat = ls * 0.5   // spacing between primary and secondary beam

            for group in beamGroups {
                guard group.beats.count >= 2,
                      let tFirst = stemTips[group.beats.first!],
                      let tLast  = stemTips[group.beats.last!]
                else { continue }

                let up = group.stemUp
                let cv: CGFloat = up ? -1 : 1   // direction away from notehead

                // Helper: interpolate Y on the primary beam line at a given X
                let spanX = tLast.x - tFirst.x
                func beamY(atX x: CGFloat, offset: CGFloat = 0) -> CGFloat {
                    let t = spanX > 0 ? (x - tFirst.x) / spanX : 0
                    return tFirst.y + t * (tLast.y - tFirst.y) + offset
                }

                // Primary beam: straight line first → last
                stemColor.setStroke(); ctx.setLineWidth(beamW)
                let primary = UIBezierPath()
                primary.move(to: CGPoint(x: tFirst.x, y: tFirst.y))
                primary.addLine(to: CGPoint(x: tLast.x, y: tLast.y))
                primary.stroke()

                // Secondary beam for sixteenth-duration notes.
                // The second beam sits BETWEEN the primary beam and the noteheads,
                // so it offsets in the opposite direction to cv (toward the notehead).
                // Collect contiguous runs of 0.25 notes, then draw each run.
                let secOffset = -cv * beamGap
                var runs: [(Int, Int)] = []   // (startIdx, endIdx) inclusive
                var runStart: Int? = nil
                for i in 0...group.beats.count {
                    let isSixteenth = i < group.beats.count && group.durations[i] <= 0.25
                    if isSixteenth {
                        if runStart == nil { runStart = i }
                    } else if let s = runStart {
                        runs.append((s, i - 1))
                        runStart = nil
                    }
                }
                for (si, ei) in runs {
                    if si == ei {
                        // Lone sixteenth: half-beam stub toward the adjacent note
                        if let ts = stemTips[group.beats[si]] {
                            // Point right if first in group, left if last, else right
                            let isLast = (si == group.beats.count - 1)
                            let stubDir: CGFloat = isLast ? -1 : 1
                            let sy = beamY(atX: ts.x, offset: secOffset)
                            let stub = UIBezierPath()
                            stub.move(to: CGPoint(x: ts.x, y: sy))
                            stub.addLine(to: CGPoint(x: ts.x + stubDir * ls * 0.9, y: sy))
                            stub.stroke()
                        }
                    } else if let ts = stemTips[group.beats[si]],
                              let te = stemTips[group.beats[ei]] {
                        let sec = UIBezierPath()
                        sec.move(to: CGPoint(x: ts.x, y: beamY(atX: ts.x, offset: secOffset)))
                        sec.addLine(to: CGPoint(x: te.x, y: beamY(atX: te.x, offset: secOffset)))
                        sec.stroke()
                    }
                }
            }

            ctx.setAlpha(1.0)
        }
        UIGraphicsPopContext()
    }

    private func splitAtBarLines(_ notes: [ChoralNote]) -> [(ChoralNote, Bool)] {
        let pickup = chorale.pickupBeats
        var out: [(ChoralNote, Bool)] = []
        for note in notes {
            var rem = note.duration, pos = note.beatPosition
            while rem > 0.001 {
                // Next barline from current position
                let next: Double
                if pos < pickup {
                    next = pickup          // end of pickup measure
                } else {
                    next = pickup + (floor((pos - pickup) / 4) + 1) * 4
                }
                let chunk = min(rem, next - pos)
                let tie   = rem - chunk > 0.001 || (rem <= chunk + 0.001 && note.tiedToNext)
                out.append((ChoralNote(midiNote: note.midiNote, beatPosition: pos, duration: chunk), tie))
                rem -= chunk; pos += chunk
            }
        }
        return out
    }

    // MARK: - Fermatas (above soprano staff)

    private func drawFermatas(ctx: CGContext) {
        guard !chorale.fermataBeats.isEmpty else { return }
        UIGraphicsPushContext(ctx)
        let ls = layout.lineSpacing
        for beat in chorale.fermataBeats {
            let note  = chorale.soprano.first { abs($0.beatPosition - beat) < 0.01 }
            let midi  = Int(note?.midiNote ?? 72)
            let noteCenterBeat = beat + (note?.duration ?? 1.0) * 0.5
            let cx    = xFor(beat: noteCenterBeat)
            let sp    = staffPos(midi: midi, treble: true, ls: ls)
            let noteY = layout.staffTop(0) + sp
            let baseY = min(noteY - layout.stemLen - ls * 0.5, layout.staffTop(0) - ls * 1.2)
            drawFermata(ctx: ctx, cx: cx, baseY: baseY, r: ls * 0.78)
        }
        UIGraphicsPopContext()
    }

    private func drawFermata(ctx: CGContext, cx: CGFloat, baseY: CGFloat, r: CGFloat) {
        fermataColor.setStroke(); fermataColor.setFill()
        ctx.setLineWidth(1.8)
        let arc = UIBezierPath()
        arc.addArc(withCenter: CGPoint(x: cx, y: baseY),
                   radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
        arc.stroke()
        let dr   = r * 0.24
        let dotY = baseY - r * 0.38
        UIBezierPath(ovalIn: CGRect(x: cx - dr, y: dotY - dr, width: dr*2, height: dr*2)).fill()
    }

    // MARK: - Chord labels (below bass staff)

    private func drawChordLabels(ctx: CGContext) {
        UIGraphicsPushContext(ctx)
        let ls      = layout.lineSpacing
        let bassBot = layout.staffTop(3) + layout.staffHeight
        let labelY  = bassBot + ls * 3.2
        let rnSize  = ls * 1.4
        let chSize  = ls * 0.82
        let rnAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: rnSize),
            .foregroundColor: rnColor
        ]
        let chAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: chSize, weight: .medium),
            .foregroundColor: UIColor(white: 0.80, alpha: 1)
        ]
        let pillBg     = UIColor(red: 0.14, green: 0.10, blue: 0.22, alpha: 0.88)
        let pillBorder = rnColor.withAlphaComponent(0.35)

        // Deduplicate by degree (inversion-stripped): skip if same degree as previous
        var deduped: [ChordLabel] = []
        for cl in chorale.chordLabels {
            if deduped.last?.degree != cl.degree {
                deduped.append(cl)
            }
        }

        var nextAvailableX: CGFloat = 0
        for cl in deduped {
            let beatX = xFor(beat: cl.beatPosition) + 2
            guard beatX >= nextAvailableX else { continue }
            let x     = beatX
            let rnStr = cl.degree   // show degree only, no inversion
            let chStr = cl.label
            let rnW   = rnStr.isEmpty ? 0 : (rnStr as NSString).size(withAttributes: rnAttrs).width
            let chW   = (chStr as NSString).size(withAttributes: chAttrs).width
            let pillW = max(rnW, chW) + ls * 0.9
            let pillH = rnSize + chSize + ls * 0.8
            let pad   = ls * 0.45
            let pillRect = CGRect(x: x - pad, y: labelY - pad * 0.5, width: pillW, height: pillH)
            let path = UIBezierPath(roundedRect: pillRect, cornerRadius: ls * 0.45)
            pillBg.setFill(); path.fill()
            pillBorder.setStroke(); ctx.setLineWidth(0.8); path.stroke()
            if !rnStr.isEmpty {
                (rnStr as NSString).draw(at: CGPoint(x: x, y: labelY), withAttributes: rnAttrs)
            }
            (chStr as NSString).draw(at: CGPoint(x: x, y: labelY + rnSize + ls * 0.05),
                                     withAttributes: chAttrs)
            nextAvailableX = x - pad + pillW + ls * 0.3
        }
        UIGraphicsPopContext()
    }

    // MARK: - Note highlights + smooth scroll

    private func updateHighlights() {
        let beat = currentBeat

        // Show/hide glow layers (suppressed for muted voices)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for glow in noteGlows {
            let muted  = mutedVoices.contains(glow.voice)
            let active = !muted && beat >= glow.beatPosition && beat < glow.beatPosition + glow.duration
            glow.glowLayer.isHidden      = !active
            glow.glowLayer.shadowOpacity = active ? 0.85 : 0.0
        }
        for cg in chordGlows {
            let active = beat >= cg.beatPosition && beat < cg.beatPosition + cg.duration
            cg.layer.isHidden      = !active
            cg.layer.shadowOpacity = active ? 0.9 : 0.0
        }
        CATransaction.commit()

        // Update fixed chord pill
        if beat >= 0, let cl = currentChordLabel(at: beat) {
            chordDegreeLabel.text = cl.degree
            chordNameLabel.text   = cl.label
            chordPill.isHidden    = false
        } else {
            chordPill.isHidden = true
        }

        if beat >= 0 {
            // Anchor for smooth scroll interpolation
            anchorBeat = beat
            anchorTime = CACurrentMediaTime()
            beatsPerSecond = Double(chorale.tempo) / 60.0
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    private func currentChordLabel(at beat: Double) -> ChordLabel? {
        let labels = chorale.chordLabels
        guard !labels.isEmpty else { return nil }
        var result: ChordLabel? = nil
        for cl in labels {
            if cl.beatPosition <= beat { result = cl } else { break }
        }
        return result
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let dl = CADisplayLink(target: self, selector: #selector(scrollTick))
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func scrollTick() {
        guard currentBeat >= 0 else { stopDisplayLink(); return }
        let elapsed = CACurrentMediaTime() - anchorTime
        let beat    = anchorBeat + elapsed * beatsPerSecond

        // Animate tie dots along their Bézier arc
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for dot in tieDots {
            let t = CGFloat((beat - dot.startBeat) / dot.duration)
            if t >= 0 && t <= 1 && !mutedVoices.contains(dot.voice) {
                dot.layer.position      = quadBezier(t: t, dot.p0, dot.p1, dot.p2)
                dot.layer.isHidden      = false
                dot.layer.shadowOpacity = 0.85
            } else {
                dot.layer.isHidden      = true
                dot.layer.shadowOpacity = 0.0
            }
        }
        CATransaction.commit()

        // Update chord pill
        if let cl = currentChordLabel(at: beat) {
            chordDegreeLabel.text = cl.degree
            chordNameLabel.text   = cl.label
            chordPill.isHidden    = false
        }

        // Smooth scroll
        let x  = xFor(beat: beat)
        let vw = scrollView.bounds.width
        let tx = max(0, x - vw * 0.3)
        let mx = max(0, scrollView.contentSize.width - vw)
        scrollView.contentOffset = CGPoint(x: min(tx, mx), y: 0)
    }
}

// MARK: - SwiftUI wrapper

struct ChoraleScoreRepresentable: UIViewRepresentable {
    let chorale: ChoraleData
    let currentBeat: Double
    let mutedVoices: Set<Voice>

    func makeUIView(context: Context) -> ChoraleScoreUIView {
        let v = ChoraleScoreUIView()
        v.chorale = chorale; v.currentBeat = currentBeat; v.mutedVoices = mutedVoices; return v
    }
    func updateUIView(_ v: ChoraleScoreUIView, context: Context) {
        if v.chorale != chorale { v.chorale = chorale }
        if abs(v.currentBeat - currentBeat) > 0.05 { v.currentBeat = currentBeat }
        if v.mutedVoices != mutedVoices { v.mutedVoices = mutedVoices }
    }
}

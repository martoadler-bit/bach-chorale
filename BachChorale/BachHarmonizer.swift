import Foundation

// MARK: - BachHarmonizer
// Hybrid approach: rule-based voice leading + Bach corpus chord statistics

struct BachHarmonizer {

    // MARK: - Public API

    static func harmonize(soprano: [MelodyNote], keyRoot: Int, isMinor: Bool, tempo: Int) -> ChoraleData {
        guard !soprano.isEmpty else { return ChoraleData() }
        let totalBeats = soprano.map { $0.beatPosition + $0.duration }.max() ?? 4.0
        let measuresCount = max(1, Int(ceil(totalBeats / 4.0)))
        let chordPlan = buildChordPlan(soprano: soprano, keyRoot: keyRoot, isMinor: isMinor, totalBeats: totalBeats)
        let (alto, tenor, bass, labels) = voiceLeadAll(chordPlan: chordPlan, soprano: soprano,
                                                        keyRoot: keyRoot, isMinor: isMinor, totalBeats: totalBeats)
        var data = ChoraleData()
        data.soprano = soprano.map { ChoralNote(midiNote: $0.midiNote, beatPosition: $0.beatPosition, duration: $0.duration) }
        data.alto = alto
        data.tenor = tenor
        data.bass = bass
        data.tempo = tempo
        data.keyRoot = keyRoot
        data.isMinor = isMinor
        data.measuresCount = measuresCount
        data.chordLabels = labels
        let finalBeat = soprano.map { $0.beatPosition }.max() ?? 0
        data.fermataBeats = [finalBeat]
        return data
    }

    // Fermatas go on the last note of every 2-measure phrase and always at the very end.
    // We find the soprano note that lands closest to each phrase boundary.
    private static func fermataPositions(soprano: [ChoralNote], totalBeats: Double) -> [Double] {
        guard !soprano.isEmpty else { return [] }
        var beats: [Double] = []
        // Phrase endings: every 2 measures, always at the final measure
        var boundaries: [Double] = []
        var b = 8.0
        while b <= totalBeats {
            boundaries.append(b)
            b += 8.0
        }
        if !boundaries.contains(totalBeats) { boundaries.append(totalBeats) }

        for boundary in boundaries {
            // Find the soprano note whose end is at or just before this boundary
            let candidate = soprano
                .filter { $0.beatPosition + $0.duration <= boundary + 0.01 }
                .max(by: { ($0.beatPosition + $0.duration) < ($1.beatPosition + $1.duration) })
            if let c = candidate {
                let pos = c.beatPosition
                if !beats.contains(pos) { beats.append(pos) }
            }
        }
        return beats
    }

    static func generate(measuresCount: Int, keyRoot: Int, isMinor: Bool, tempo: Int) -> ChoraleData {
        let totalBeats = Double(measuresCount * 4)
        let soprano = generateSoprano(keyRoot: keyRoot, isMinor: isMinor, totalBeats: totalBeats)
        return harmonize(soprano: soprano, keyRoot: keyRoot, isMinor: isMinor, tempo: tempo)
    }

    // MARK: - Chord Model

    struct Chord: Equatable {
        let root: Int
        let quality: Quality
        let degree: Int
        var inversion: Int = 0   // 0=root, 1=first, 2=second

        enum Quality: Int {
            case major, minor, diminished, dom7, maj7, min7, halfDim7
        }

        var pitchClasses: [Int] {
            switch quality {
            case .major:    return [(root)%12,(root+4)%12,(root+7)%12]
            case .minor:    return [(root)%12,(root+3)%12,(root+7)%12]
            case .diminished: return [(root)%12,(root+3)%12,(root+6)%12]
            case .dom7:     return [(root)%12,(root+4)%12,(root+7)%12,(root+10)%12]
            case .maj7:     return [(root)%12,(root+4)%12,(root+7)%12,(root+11)%12]
            case .min7:     return [(root)%12,(root+3)%12,(root+7)%12,(root+10)%12]
            case .halfDim7: return [(root)%12,(root+3)%12,(root+6)%12,(root+10)%12]
            }
        }

        // Bass pitch class for given inversion
        var bassPC: Int {
            let pcs = pitchClasses
            return pcs[min(inversion, pcs.count - 1)]
        }

        func contains(pitchClass: Int) -> Bool { pitchClasses.contains(pitchClass % 12) }
    }

    // MARK: - Diatonic chords

    static func diatonicChords(keyRoot: Int, isMinor: Bool) -> [Chord] {
        let major: [(Int, Chord.Quality)] = [
            (0,.major),(2,.minor),(4,.minor),(5,.major),(7,.major),(9,.minor),(11,.diminished)
        ]
        // Natural minor with raised 7th for dom on V
        let minor: [(Int, Chord.Quality)] = [
            (0,.minor),(2,.diminished),(3,.major),(5,.minor),(7,.major),(8,.major),(11,.diminished)
        ]
        return (isMinor ? minor : major).enumerated().map { i, pair in
            Chord(root: (keyRoot + pair.0) % 12, quality: pair.1, degree: i+1)
        }
    }

    static func allChords(keyRoot: Int, isMinor: Bool) -> [Chord] {
        var chords = diatonicChords(keyRoot: keyRoot, isMinor: isMinor)
        // V7 (dominant seventh)
        chords.append(Chord(root: (keyRoot+7)%12, quality: .dom7, degree: 5))
        // ii7 or iiø7
        let ii7Q: Chord.Quality = isMinor ? .halfDim7 : .min7
        chords.append(Chord(root: (keyRoot+2)%12, quality: ii7Q, degree: 2))
        // Secondary dominant: V/V (II7)
        chords.append(Chord(root: (keyRoot+2)%12, quality: .dom7, degree: 8))
        // V/IV
        chords.append(Chord(root: (keyRoot+7)%12, quality: .major, degree: 9))
        // Picardy third: I major in minor keys (very common in Bach cadences)
        if isMinor {
            chords.append(Chord(root: keyRoot, quality: .major, degree: 1))
            // Subtonic ♭VII (natural minor VII): e.g. F major in G minor
            chords.append(Chord(root: (keyRoot + 10) % 12, quality: .major, degree: 7))
        }
        return chords
    }

    // MARK: - Chord plan (one chord per beat)

    struct BeatChord {
        let beat: Double
        let chord: Chord
        let sopranoMidi: Int
    }

    static func buildChordPlan(soprano: [MelodyNote], keyRoot: Int, isMinor: Bool, totalBeats: Double) -> [BeatChord] {
        let chords = allChords(keyRoot: keyRoot, isMinor: isMinor)
        var plan: [BeatChord] = []
        var prevDegree = 1
        var beat = 0.0

        while beat < totalBeats {
            let sopMidi = sopranoAt(beat: beat, melody: soprano)
            let sopPC = sopMidi % 12
            let isLastBeat = beat >= totalBeats - 1.0
            let isPenultimate = beat >= totalBeats - 4.0 && beat < totalBeats - 1.0
            let measureBeat = beat.truncatingRemainder(dividingBy: 4.0)

            let chord: Chord
            if isLastBeat {
                // Perfect authentic cadence: tonic in root position.
                // In minor, ~40% chance of Picardy third (major I).
                let usePicardy = isMinor && Int.random(in: 0..<5) < 2
                let tonicQuality: Chord.Quality = usePicardy ? .major : (isMinor ? .minor : .major)
                chord = chords.first(where: { $0.degree == 1 && $0.inversion == 0 && $0.quality == tonicQuality })
                     ?? chords.first(where: { $0.degree == 1 && $0.inversion == 0 })
                     ?? chords[0]
            } else if beat == totalBeats - 2.0 {
                // Penultimate: dominant
                chord = chords.first(where: { $0.quality == .dom7 }) ?? chords[4]
            } else if isPenultimate && measureBeat < 2.0 {
                // ii before dominant
                let ii = chords.first(where: { $0.degree == 2 }) ?? chords[1]
                chord = sopPC == ii.bassPC || ii.contains(pitchClass: sopPC) ? ii : pickChord(sopPC: sopPC, prevDegree: prevDegree, beat: beat, totalBeats: totalBeats, chords: chords, keyRoot: keyRoot, isMinor: isMinor)
            } else {
                chord = pickChord(sopPC: sopPC, prevDegree: prevDegree, beat: beat, totalBeats: totalBeats, chords: chords, keyRoot: keyRoot, isMinor: isMinor)
            }

            plan.append(BeatChord(beat: beat, chord: chord, sopranoMidi: sopMidi))
            prevDegree = chord.degree
            beat += 1.0
        }
        return plan
    }

    static func sopranoAt(beat: Double, melody: [MelodyNote]) -> Int {
        let note = melody.first(where: { $0.beatPosition <= beat && beat < $0.beatPosition + $0.duration })
            ?? melody.min(by: { abs($0.beatPosition - beat) < abs($1.beatPosition - beat) })
        return Int(note?.midiNote ?? 64)
    }

    static func pickChord(sopPC: Int, prevDegree: Int, beat: Double, totalBeats: Double,
                           chords: [Chord], keyRoot: Int, isMinor: Bool,
                           prevFigure: String? = nil) -> Chord {
        let candidates = chords.filter { $0.contains(pitchClass: sopPC) && $0.degree <= 7 }
        let pool = candidates.isEmpty ? chords.filter { $0.degree <= 7 } : candidates
        var best = pool[0]; var bestScore = -1.0

        let handcraftedWeights = transitionWeights(from: prevDegree, isMinor: isMinor)

        for chord in pool {
            let idx = chord.degree - 1
            let w   = idx < handcraftedWeights.count ? handcraftedWeights[idx] : 0.01
            if w > bestScore { bestScore = w; best = chord }
        }
        return best
    }

    // MARK: - Voice leading (all voices)

    static func voiceLeadAll(chordPlan: [BeatChord], soprano: [MelodyNote],
                              keyRoot: Int, isMinor: Bool, totalBeats: Double)
        -> ([ChoralNote], [ChoralNote], [ChoralNote], [ChordLabel]) {

        var altoNotes:  [ChoralNote] = []
        var tenorNotes: [ChoralNote] = []
        var bassNotes:  [ChoralNote] = []
        var labels:     [ChordLabel] = []

        var prevAlto  = 65   // F4
        var prevTenor = 60   // C4
        var prevBass  = 48   // C3
        var prevSop   = chordPlan.first?.sopranoMidi ?? 64

        var prevChordDeg = 1
        let leadingTone = (keyRoot + 11) % 12

        for (i, bc) in chordPlan.enumerated() {
            let chord = bc.chord
            let sopMidi = bc.sopranoMidi
            let beat = bc.beat
            let isLastBeat = beat >= totalBeats - 1.0
            let nextBC: BeatChord? = i + 1 < chordPlan.count ? chordPlan[i+1] : nil

            // --- Bass ---
            var bassMidi: Int
            if isLastBeat {
                // Root position tonic at end
                bassMidi = nearestPC(pc: chord.root, range: 40...62, target: prevBass)
            } else {
                bassMidi = computeBass(chord: chord, prevBass: prevBass,
                                       beat: beat, nextChord: nextBC,
                                       keyRoot: keyRoot, isMinor: isMinor)
            }

            // --- Alto & Tenor ---
            var (alto, tenor) = computeAltoTenor(chord: chord, sopMidi: sopMidi,
                                                  prevAlto: prevAlto, prevTenor: prevTenor,
                                                  bassMidi: bassMidi)

            // Resolve leading tone at cadence (V→I)
            if prevChordDeg == 5 && chord.degree == 1 {
                if prevAlto % 12 == leadingTone {
                    alto = prevAlto + 1
                    if alto > 72 { alto -= 12 }
                }
                if prevTenor % 12 == leadingTone {
                    tenor = prevTenor + 1
                    if tenor > 67 { tenor -= 12 }
                }
            }

            // Check parallel 5ths/8ths — fix if needed
            (alto, tenor) = fixParallels(sMidi: sopMidi, aMidi: alto, tMidi: tenor, bMidi: bassMidi,
                                          prevS: prevSop, prevA: prevAlto, prevT: prevTenor, prevB: prevBass,
                                          chord: chord)

            altoNotes.append(ChoralNote(midiNote: UInt8(clamping: alto),  beatPosition: beat, duration: 1.0))
            tenorNotes.append(ChoralNote(midiNote: UInt8(clamping: tenor), beatPosition: beat, duration: 1.0))
            bassNotes.append(ChoralNote(midiNote: UInt8(clamping: bassMidi), beatPosition: beat, duration: 1.0))

            prevAlto  = alto
            prevTenor = tenor
            prevSop   = sopMidi
            prevBass  = bassMidi
            prevChordDeg = chord.degree

            // Label every beat, but skip if it would be identical to the previous label
            let bassPC = bassMidi % 12
            let actualInversion: Int
            if let idx = chord.pitchClasses.firstIndex(of: bassPC) {
                actualInversion = idx
            } else {
                actualInversion = 0
            }
            var chordForLabel = chord
            chordForLabel.inversion = actualInversion
            let dominantPC = (keyRoot + 7) % 12
            let isCad64 = chordForLabel.degree == 1 && actualInversion == 2 && bassPC == dominantPC
            let rn  = isCad64 ? "I⁶₄" : romanNumeral(chord: chordForLabel, isMinor: isMinor)
            let lab = isCad64 ? "Cad.⁶₄" : chordName(chord: chordForLabel, keyRoot: keyRoot, isMinor: isMinor)
            if labels.last?.romanNumeral != rn || labels.last?.label != lab {
                labels.append(ChordLabel(beatPosition: beat, label: lab, romanNumeral: rn))
            }
        }

        // Merge repeated notes in ATB into longer durations, then occasionally add passing tones
        let finalAlto  = addPassingTones(consolidate(altoNotes),  range: 53...72, scale: buildScale(keyRoot: keyRoot, isMinor: isMinor), totalBeats: totalBeats)
        let finalTenor = addPassingTones(consolidate(tenorNotes), range: 48...67, scale: buildScale(keyRoot: keyRoot, isMinor: isMinor), totalBeats: totalBeats)
        return (finalAlto, finalTenor, consolidate(bassNotes), labels)
    }

    // MARK: - Bass computation (inversions + passing tones)

    static func computeBass(chord: Chord, prevBass: Int, beat: Double,
                             nextChord: BeatChord?, keyRoot: Int, isMinor: Bool) -> Int {
        let measureBeat = beat.truncatingRemainder(dividingBy: 4.0)

        // Beat 1: root position
        // Beat 3: root or first inversion (adds variety)
        // Beats 2,4: can use passing tone toward next chord

        if measureBeat == 0 || measureBeat == 2 {
            // Strong beats: root position
            return nearestPC(pc: chord.root, range: 40...62, target: prevBass)
        } else if measureBeat == 1 && Int.random(in: 0..<3) == 0 {
            // Occasional first inversion on beat 2
            let third = chord.pitchClasses[min(1, chord.pitchClasses.count-1)]
            return nearestPC(pc: third, range: 40...60, target: prevBass)
        } else if measureBeat == 3 {
            // Beat 4: try passing tone toward next chord root
            if let next = nextChord {
                let nextRoot = nearestPC(pc: next.chord.root, range: 40...62, target: prevBass)
                let currentRoot = nearestPC(pc: chord.root, range: 40...62, target: prevBass)
                let diff = nextRoot - currentRoot
                if abs(diff) == 2 {
                    // Step connection: use the in-between chromatic note or just hold
                    return currentRoot
                } else if abs(diff) == 4 || abs(diff) == 3 {
                    // Could pass through the step
                    let passing = currentRoot + (diff > 0 ? 2 : -2)
                    if passing >= 40 && passing <= 62 { return passing }
                }
            }
            return nearestPC(pc: chord.root, range: 40...62, target: prevBass)
        } else {
            return nearestPC(pc: chord.root, range: 40...62, target: prevBass)
        }
    }

    // MARK: - Alto and Tenor computation

    // MARK: - 4-voice solver: finds best (alto, tenor) pair satisfying all constraints

    static func computeAltoTenor(chord: Chord, sopMidi: Int,
                                  prevAlto: Int, prevTenor: Int, bassMidi: Int) -> (Int, Int) {
        let pcs = chord.pitchClasses
        // Strict ordering: bassMidi < tenor < alto < sopMidi
        // All voices must be on chord tones
        // Minimize total movement from previous positions (smooth voice leading)
        var best: (Int, Int)? = nil
        var bestCost = Int.max

        let altoLo  = max(53, bassMidi + 2)
        let altoHi  = min(72, sopMidi - 1)
        let tenorLo = max(48, bassMidi + 1)

        if altoLo <= altoHi {
        for alto in altoLo...altoHi {
            guard pcs.contains(alto % 12) else { continue }
            let tenorHi = min(67, alto - 1)
            guard tenorHi >= tenorLo else { continue }
            for tenor in tenorLo...tenorHi {
                guard pcs.contains(tenor % 12) else { continue }
                let cost = abs(alto - prevAlto) + abs(tenor - prevTenor)
                if cost < bestCost {
                    bestCost = cost
                    best = (alto, tenor)
                }
            }
        }
        } // end if altoLo <= altoHi

        // Fallback: relax all constraints
        if best == nil {
            let fAltoLo = max(48, bassMidi + 1);  let fAltoHi = min(72, sopMidi)
            if fAltoLo <= fAltoHi {
                for alto in fAltoLo...fAltoHi {
                    guard pcs.contains(alto % 12) else { continue }
                    let fTenorHi = min(67, alto)
                    let fTenorLo = max(40, bassMidi)
                    if fTenorLo <= fTenorHi {
                        for tenor in fTenorLo...fTenorHi {
                            guard pcs.contains(tenor % 12) else { continue }
                            let cost = abs(alto - prevAlto) + abs(tenor - prevTenor)
                            if cost < bestCost { bestCost = cost; best = (alto, tenor) }
                        }
                    }
                }
            }
        }

        return best ?? (prevAlto, prevTenor)
    }

    // MARK: - Parallel 5ths/8ths fix

    static func fixParallels(sMidi: Int, aMidi: Int, tMidi: Int, bMidi: Int,
                              prevS: Int, prevA: Int, prevT: Int, prevB: Int,
                              chord: Chord) -> (Int, Int) {
        var a = aMidi, t = tMidi
        let pcs = chord.pitchClasses

        func isParallel(_ v1: Int, _ v2: Int, _ pv1: Int, _ pv2: Int) -> Bool {
            let interval = abs(v1 - v2) % 12
            let prev = abs(pv1 - pv2) % 12
            guard interval == prev && (interval == 7 || interval == 0) else { return false }
            let m1 = (v1 - pv1).signum(); let m2 = (v2 - pv2).signum()
            return m1 != 0 && m2 != 0 && m1 == m2
        }

        func hasAnyParallel(ca: Int, ct: Int) -> Bool {
            isParallel(sMidi, ca, prevS, prevA) ||
            isParallel(sMidi, ct, prevS, prevT) ||
            isParallel(ca, ct, prevA, prevT)    ||
            isParallel(ca, bMidi, prevA, prevB) ||
            isParallel(ct, bMidi, prevT, prevB)
        }

        guard hasAnyParallel(ca: a, ct: t) else { return (a, t) }

        // Try adjusting alto
        for delta in [1, -1, 2, -2, 3, -3] {
            let ca = a + delta
            guard ca >= 53 && ca <= 72 && pcs.contains(ca % 12) && ca != sMidi && ca != t else { continue }
            if !hasAnyParallel(ca: ca, ct: t) { return (ca, t) }
        }
        // Try adjusting tenor
        for delta in [1, -1, 2, -2, 3, -3] {
            let ct = t + delta
            guard ct >= 48 && ct <= 67 && pcs.contains(ct % 12) && ct != a && ct != bMidi else { continue }
            if !hasAnyParallel(ca: a, ct: ct) { return (a, ct) }
        }
        // Try adjusting both
        for da in [1, -1, 2, -2] {
            let ca = a + da
            guard ca >= 53 && ca <= 72 && pcs.contains(ca % 12) && ca != sMidi else { continue }
            for dt in [1, -1, 2, -2] {
                let ct = t + dt
                guard ct >= 48 && ct <= 67 && pcs.contains(ct % 12) && ct != bMidi && ct != ca else { continue }
                if !hasAnyParallel(ca: ca, ct: ct) { return (ca, ct) }
            }
        }
        return (a, t)
    }

    // MARK: - Consolidate repeated notes into longer durations

    static func consolidate(_ notes: [ChoralNote]) -> [ChoralNote] {
        guard !notes.isEmpty else { return [] }
        var result: [ChoralNote] = []
        var current = notes[0]
        for i in 1..<notes.count {
            let next = notes[i]
            // Only merge if same pitch AND they're adjacent
            if next.midiNote == current.midiNote &&
               abs(next.beatPosition - (current.beatPosition + current.duration)) < 0.01 {
                current = ChoralNote(midiNote: current.midiNote,
                                     beatPosition: current.beatPosition,
                                     duration: current.duration + next.duration)
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }

    // MARK: - Passing tones for ATB voices

    // Occasionally splits a quarter note into two eighths with a diatonic passing tone.
    // ~20% chance on weak beats (2 and 4) when moving by a third.
    static func addPassingTones(_ notes: [ChoralNote], range: ClosedRange<Int>, scale: [Int], totalBeats: Double) -> [ChoralNote] {
        guard notes.count >= 2 else { return notes }
        let scalePCs = Set(scale.map { $0 % 12 })
        var result: [ChoralNote] = []
        for i in 0..<notes.count {
            let note = notes[i]
            let measureBeat = note.beatPosition.truncatingRemainder(dividingBy: 4.0)
            let isWeakBeat = measureBeat == 1.0 || measureBeat == 3.0
            guard note.duration == 1.0,
                  isWeakBeat,
                  note.beatPosition < totalBeats - 1.5,
                  Int.random(in: 0..<5) == 0
            else { result.append(note); continue }

            let currMidi = Int(note.midiNote)
            let nextMidi = Int(notes[i + 1].midiNote)
            let lo = min(currMidi, nextMidi)
            let hi = max(currMidi, nextMidi)
            // Need at least a minor third gap to fit a passing note between them
            guard hi - lo >= 3 else { result.append(note); continue }

            // Pick the first diatonic pitch strictly between currMidi and nextMidi
            let dir = nextMidi > currMidi ? 1 : -1
            let between = (lo + 1 ..< hi).filter { scalePCs.contains($0 % 12) }
            guard let passingMidi = dir > 0 ? between.first : between.last
            else { result.append(note); continue }

            result.append(ChoralNote(midiNote: UInt8(clamping: currMidi),    beatPosition: note.beatPosition,       duration: 0.5))
            result.append(ChoralNote(midiNote: UInt8(clamping: passingMidi), beatPosition: note.beatPosition + 0.5, duration: 0.5))
        }
        return result
    }

    // MARK: - Helpers

    static func nearestPC(pc: Int, range: ClosedRange<Int>, target: Int) -> Int {
        var best = range.lowerBound; var bestDist = Int.max
        for midi in range {
            if midi % 12 == pc {
                let dist = abs(midi - target)
                if dist < bestDist { bestDist = dist; best = midi }
            }
        }
        return best
    }

    static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(hi, v)) }

    // MARK: - Chord transitions (Bach corpus statistics)

    static func transitionWeights(from degree: Int, isMinor: Bool) -> [Double] {
        // Indices 0-6 = degrees I-VII
        if isMinor {
            switch degree {
            case 1: return [0.08, 0.12, 0.04, 0.22, 0.38, 0.12, 0.04]
            case 2: return [0.18, 0.04, 0.04, 0.12, 0.52, 0.06, 0.04]
            case 3: return [0.10, 0.10, 0.04, 0.42, 0.20, 0.10, 0.04]
            case 4: return [0.22, 0.12, 0.04, 0.04, 0.48, 0.06, 0.04]
            case 5: return [0.58, 0.04, 0.04, 0.10, 0.08, 0.12, 0.04]
            case 6: return [0.14, 0.12, 0.04, 0.26, 0.32, 0.08, 0.04]
            case 7: return [0.72, 0.04, 0.08, 0.04, 0.04, 0.04, 0.04]
            default: return [0.50, 0.10, 0.05, 0.15, 0.15, 0.04, 0.01]
            }
        } else {
            switch degree {
            case 1: return [0.08, 0.16, 0.04, 0.26, 0.36, 0.06, 0.04]
            case 2: return [0.22, 0.04, 0.04, 0.16, 0.50, 0.00, 0.04]
            case 3: return [0.10, 0.12, 0.04, 0.42, 0.16, 0.12, 0.04]
            case 4: return [0.26, 0.16, 0.04, 0.04, 0.46, 0.00, 0.04]
            case 5: return [0.58, 0.04, 0.04, 0.10, 0.04, 0.16, 0.04]
            case 6: return [0.14, 0.36, 0.04, 0.26, 0.16, 0.00, 0.04]
            case 7: return [0.72, 0.04, 0.10, 0.04, 0.00, 0.06, 0.04]
            default: return [0.50, 0.10, 0.05, 0.15, 0.15, 0.04, 0.01]
            }
        }
    }

    // MARK: - Roman numeral figured bass

    static func romanNumeral(chord: Chord, isMinor: Bool) -> String {
        let deg = chord.degree
        if deg == 8 { return "V⁷/V" }   // secondary dominant
        if deg == 9 { return "V" }
        let numerals = ["I","II","III","IV","V","VI","VII"]
        guard deg >= 1 && deg <= 7 else { return "" }
        var rn = numerals[deg - 1]

        // Lowercase for minor / diminished quality
        switch chord.quality {
        case .minor, .min7, .halfDim7, .diminished:
            rn = rn.lowercased()
        default: break
        }

        let inv = chord.inversion

        switch chord.quality {
        case .diminished:
            // Diminished triad: vii°, vii°⁶ (1st inv), vii°⁶₄ (2nd inv — rare)
            rn += "°"
            switch inv {
            case 1: rn += "⁶"
            case 2: rn += "⁶₄"
            default: break
            }

        case .halfDim7:
            // Half-diminished seventh: viiø⁷, viiø⁶₅, viiø⁴₃, viiø⁴₂
            rn += "ø"
            fallthrough
        case .dom7, .maj7, .min7:
            // Seventh chord figured bass by inversion
            switch inv {
            case 0: rn += "⁷"
            case 1: rn += "⁶₅"
            case 2: rn += "⁴₃"
            case 3: rn += "²"
            default: rn += "⁷"
            }
            // Δ for major seventh
            if chord.quality == .maj7 { rn = rn.replacingOccurrences(of: "⁷", with: "Δ⁷")
                                                .replacingOccurrences(of: "⁶₅", with: "Δ⁶₅") }

        default:
            // Major / minor triads: nothing, ⁶, ⁶₄
            switch inv {
            case 1: rn += "⁶"
            case 2: rn += "⁶₄"
            default: break
            }
        }

        return rn
    }

    // MARK: - Chord name

    static func chordName(chord: Chord, keyRoot: Int, isMinor: Bool) -> String {
        let names = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
        let root = names[chord.root]
        switch chord.quality {
        case .major:      return root
        case .minor:      return root + "m"
        case .diminished: return root + "°"
        case .dom7:       return root + "7"
        case .maj7:       return root + "Δ"
        case .min7:       return root + "m7"
        case .halfDim7:   return root + "ø7"
        }
    }

    // MARK: - Chord labels from real voices

    static func chordLabels(bass: [ChoralNote], soprano: [ChoralNote],
                             alto: [ChoralNote] = [], tenor: [ChoralNote] = [],
                             keyRoot: Int, isMinor: Bool) -> [ChordLabel] {
        let allChordsInKey = allChords(keyRoot: keyRoot, isMinor: isMinor)
        var labels: [ChordLabel] = []
        guard let totalBeats = bass.last.map({ $0.beatPosition + $0.duration }) else { return [] }
        var beat = 0.0
        while beat < totalBeats - 0.01 {
            let bassPC  = pitchClassAt(beat: beat, notes: bass) % 12
            let sopPC   = pitchClassAt(beat: beat, notes: soprano) % 12
            let altPC   = alto.isEmpty  ? -1 : pitchClassAt(beat: beat, notes: alto)  % 12
            let tenPC   = tenor.isEmpty ? -1 : pitchClassAt(beat: beat, notes: tenor) % 12

            // Bass is most informative (weight 3), inner voices confirm quality (weight 2 each),
            // soprano adds context (weight 1). Using all 4 voices prevents major/minor confusion.
            var best: Chord? = nil
            var bestScore = -1
            for chord in allChordsInKey {
                let pcs = chord.pitchClasses
                var score = 0
                if pcs.contains(bassPC) { score += 3 }
                if pcs.contains(sopPC)  { score += 1 }
                if altPC >= 0 && pcs.contains(altPC) { score += 2 }
                if tenPC >= 0 && pcs.contains(tenPC) { score += 2 }
                if score > bestScore { bestScore = score; best = chord }
            }

            if var chord = best {
                let inv = chord.pitchClasses.firstIndex(of: bassPC) ?? 0
                chord.inversion = inv

                // Cadential 6/4 detection: I or i in second inversion with dominant in bass
                // is a suspension over V, not a true tonic chord.
                let dominantPC = (keyRoot + 7) % 12
                let isCadential64 = chord.degree == 1 && inv == 2 && bassPC == dominantPC

                let rn  = isCadential64 ? "I⁶₄" : romanNumeral(chord: chord, isMinor: isMinor)
                let lab = isCadential64 ? "Cad.⁶₄" : chordName(chord: chord, keyRoot: keyRoot, isMinor: isMinor)
                if labels.last?.romanNumeral != rn || labels.last?.label != lab {
                    labels.append(ChordLabel(beatPosition: beat, label: lab, romanNumeral: rn))
                }
            }
            beat += 1.0
        }
        return labels
    }

    private static func pitchClassAt(beat: Double, notes: [ChoralNote]) -> Int {
        for n in notes.reversed() {
            if n.beatPosition <= beat + 0.01 { return Int(n.midiNote) % 12 }
        }
        return notes.first.map { Int($0.midiNote) % 12 } ?? 0
    }

    // MARK: - Key detection

    static func detectKey(melody: [MelodyNote]) -> (root: Int, isMinor: Bool) {
        var counts = Array(repeating: 0.0, count: 12)
        for note in melody { counts[Int(note.midiNote) % 12] += note.duration }
        let majorProfile: [Double] = [6.35,2.23,3.48,2.33,4.38,4.09,2.52,5.19,2.39,3.66,2.29,2.88]
        let minorProfile: [Double] = [6.33,2.68,3.52,5.38,2.60,3.53,2.54,4.75,3.98,2.69,3.34,3.17]
        var bestScore = -Double.infinity; var bestRoot = 0; var bestMinor = false
        for root in 0..<12 {
            for (minor, profile) in [(false, majorProfile), (true, minorProfile)] {
                var score = 0.0
                for i in 0..<12 { score += counts[(i+root)%12] * profile[i] }
                if score > bestScore { bestScore = score; bestRoot = root; bestMinor = minor }
            }
        }
        return (bestRoot, bestMinor)
    }

    // MARK: - Soprano generator

    static func generateSoprano(keyRoot: Int, isMinor: Bool, totalBeats: Double) -> [MelodyNote] {
        let scale = buildScale(keyRoot: keyRoot, isMinor: isMinor)
        guard !scale.isEmpty else { return [] }

        var notes: [MelodyNote] = []
        let measures = Int(ceil(totalBeats / 4.0))

        // Generate phrase by phrase (2 measures each)
        var pitchIdx = scale.firstIndex(where: { $0 >= 64 }) ?? scale.count / 2

        for measure in 0..<measures {
            let measureBeat = Double(measure * 4)
            let isLastMeasure = measure == measures - 1
            let isSecondToLast = measure == measures - 2

            if isLastMeasure {
                // Final cadence: tonic quarter note on beat 1 only (Bach style — ends on the downbeat)
                let tonicMidi = nearestPC(pc: keyRoot, range: 60...79, target: scale[pitchIdx])
                notes.append(MelodyNote(midiNote: UInt8(clamping: tonicMidi), beatPosition: measureBeat, duration: 1.0))
            } else if isSecondToLast {
                // Penultimate: approach dominant (leading to cadence)
                let domMidi = nearestPC(pc: (keyRoot+7)%12, range: 60...79, target: scale[pitchIdx])
                let ltMidi  = nearestPC(pc: (keyRoot+11)%12, range: 60...79, target: domMidi - 1)
                notes.append(MelodyNote(midiNote: UInt8(clamping: ltMidi), beatPosition: measureBeat, duration: 2.0))
                notes.append(MelodyNote(midiNote: UInt8(clamping: domMidi), beatPosition: measureBeat + 2, duration: 2.0))
                pitchIdx = scale.firstIndex(where: { $0 == domMidi }) ?? pitchIdx
            } else {
                // Regular measure: mix of half, quarter, and occasional eighth-note pairs
                var mBeat = 0.0
                while mBeat < 4.0 {
                    let remaining = 4.0 - mBeat
                    let dur: Double
                    if mBeat == 0 && remaining >= 2 && Int.random(in: 0..<3) == 0 {
                        dur = 2.0   // half note on beat 1
                    } else if remaining >= 1.0 && Int.random(in: 0..<5) == 0 {
                        // Eighth-note pair: two 0.5-beat notes (stepwise motion)
                        let move1 = chooseMotion(idx: pitchIdx, scale: scale)
                        pitchIdx = clamp(move1, 0, scale.count - 1)
                        notes.append(MelodyNote(midiNote: UInt8(clamping: scale[pitchIdx]),
                                                beatPosition: measureBeat + mBeat, duration: 0.5))
                        let step = Bool.random() ? 1 : -1
                        pitchIdx = clamp(pitchIdx + step, 0, scale.count - 1)
                        notes.append(MelodyNote(midiNote: UInt8(clamping: scale[pitchIdx]),
                                                beatPosition: measureBeat + mBeat + 0.5, duration: 0.5))
                        mBeat += 1.0
                        continue
                    } else if remaining <= 1.0 {
                        dur = remaining
                    } else {
                        dur = 1.0
                    }

                    let move = chooseMotion(idx: pitchIdx, scale: scale)
                    pitchIdx = clamp(move, 0, scale.count - 1)
                    notes.append(MelodyNote(midiNote: UInt8(clamping: scale[pitchIdx]),
                                            beatPosition: measureBeat + mBeat, duration: dur))
                    mBeat += dur
                }
            }
        }

        return notes
    }

    static func chooseMotion(idx: Int, scale: [Int]) -> Int {
        // Bach-like: mostly stepwise, occasional 3rd, rare 6th
        let r = Int.random(in: 0..<10)
        let dir = Bool.random() ? 1 : -1
        let step: Int
        switch r {
        case 0...5: step = 1   // step
        case 6...7: step = 2   // third
        case 8:     step = 3   // fourth
        default:    step = 0   // repeat
        }
        let newIdx = idx + dir * step
        return clamp(newIdx, 0, scale.count - 1)
    }

    static func buildScale(keyRoot: Int, isMinor: Bool) -> [Int] {
        let majorIntervals = [0,2,4,5,7,9,11]
        // Harmonic minor: raised 7th only. Raised 6th appears only as passing tone (via addPassingTones).
        let minorIntervals = [0,2,3,5,7,8,11]
        let intervals = isMinor ? minorIntervals : majorIntervals
        var result: [Int] = []
        for oct in 4...5 {
            for iv in intervals {
                let midi = (oct + 1) * 12 + keyRoot + iv
                if midi >= 60 && midi <= 79 { result.append(midi) }
            }
        }
        return Array(Set(result)).sorted()
    }
}

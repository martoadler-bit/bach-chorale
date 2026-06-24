"""
Extract Bach chorales from music21 corpus with chord analysis.
Outputs bach_chorales.json for the Choral Lab iOS app.

Usage: python3 extract_chorales.py
Output: bach_chorales.json  (copy to Xcode bundle)
"""

import json, re
from music21 import corpus, roman, pitch, chord as m21chord, note as m21note

PC_NAMES = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]

def pc_from_name(name):
    """Convert note name (e.g. 'G', 'Bb') to pitch class 0-11."""
    enharmonics = {"Cb":11,"Db":1,"Eb":3,"Fb":4,"Gb":6,"Ab":8,"Bb":10,
                   "C#":1,"D#":3,"E#":5,"F#":6,"G#":8,"A#":10,"B#":0}
    naturals = {"C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11}
    name = name.strip()
    return enharmonics.get(name, naturals.get(name[0], 0))

def extract_voice(part, pickup_offset):
    """Return list of [beat, midi, duration] from a part, offset-adjusted.
    Keeps only one note per beat (first encountered); handles Chord elements."""
    seen_beats = {}  # offset -> [beat, midi, duration] (keep first)
    for el in part.flat.notesAndRests:
        if el.isRest:
            continue
        offset = round(float(el.offset) - pickup_offset, 4)
        if offset < -0.01:
            continue
        if offset in seen_beats:
            continue  # skip duplicate beats (e.g. chord tones, tied notes)
        duration = round(float(el.duration.quarterLength), 4)
        if hasattr(el, 'pitch'):
            seen_beats[offset] = [offset, int(el.pitch.midi), duration]
        elif hasattr(el, 'pitches') and el.pitches:
            midi_vals = sorted(int(p.midi) for p in el.pitches)
            seen_beats[offset] = [offset, midi_vals[0], duration]
    return [seen_beats[k] for k in sorted(seen_beats)]

def simplify_figure(figure):
    """Clean up music21 roman numeral figure for display."""
    # music21 uses flat/sharp prefixes like bVII, #IV etc.
    return figure

def extract_chord_labels(score, k, pickup_offset):
    """Use music21's chordify + roman numeral analysis."""
    labels = []
    seen_beat = set()
    try:
        chordified = score.chordify()
        for c in chordified.flat.getElementsByClass('Chord'):
            offset = float(c.offset) - pickup_offset
            if offset < -0.01:
                continue
            beat = round(offset, 4)
            if beat in seen_beat:
                continue
            seen_beat.add(beat)
            try:
                rn = roman.romanNumeralFromChord(c, k)
                figure = rn.figure          # e.g. "viio6", "V65", "I"
                # Build a readable chord name
                root = rn.root().name       # e.g. "F#"
                quality = ""
                if rn.quality == "major":   quality = ""
                elif rn.quality == "minor": quality = "m"
                elif rn.quality == "diminished": quality = "dim"
                elif rn.quality == "augmented":  quality = "aug"
                elif "dominant-seventh" in rn.quality: quality = "7"
                elif "minor-seventh" in rn.quality: quality = "m7"
                label = root + quality
                labels.append({"b": beat, "l": label, "rn": figure})
            except Exception:
                pass
    except Exception:
        pass
    return labels

def get_satb_parts(score):
    """Identify S/A/T/B parts from a score. Returns dict or None."""
    parts = score.parts

    # First priority: find parts by name (handles cantatas with extra instruments)
    s_part = a_part = t_part = b_part = None
    for p in parts:
        name = (p.partName or p.id or '').strip().lower()
        if any(x in name for x in ('soprano', 'sopran')):
            s_part = p
        elif any(x in name for x in ('alto', 'alt')):
            a_part = p
        elif any(x in name for x in ('tenor')):
            t_part = p
        elif any(x in name for x in ('bass', 'basso')):
            b_part = p

    if s_part and a_part and t_part and b_part:
        return {'s': s_part, 'a': a_part, 'n': t_part, 'l': b_part}

    # Fallback: exactly 4 parts assumed S/A/T/B in order
    if len(parts) == 4:
        return {'s': parts[0], 'a': parts[1], 'n': parts[2], 'l': parts[3]}

    # Case: 2 parts each with 2 voices (piano-score style)
    if len(parts) == 2:
        try:
            voices0 = list(parts[0].getElementsByClass('Voice'))
            voices1 = list(parts[1].getElementsByClass('Voice'))
            if len(voices0) >= 2 and len(voices1) >= 2:
                return {'s': voices0[0], 'a': voices0[1],
                        'n': voices1[0], 'l': voices1[1]}
        except Exception:
            pass

    return None

def extract_chorale(path):
    """Parse one chorale and return JSON-ready dict, or None on failure."""
    try:
        score = corpus.parse(path)
    except Exception as e:
        return None

    # BWV number from filename
    fname = str(path.name)  # e.g. bwv10.7.mxl
    bwv_match = re.search(r'bwv(\d+[\.\d]*)', fname, re.IGNORECASE)
    if not bwv_match:
        return None
    bwv = bwv_match.group(1)

    # Key analysis
    try:
        k = score.analyze('key')
        tonic_pc = pc_from_name(k.tonic.name)
        is_minor = (k.mode == 'minor')
    except Exception:
        return None

    # Pickup (anacrusis) offset
    try:
        first_measure = score.parts[0].getElementsByClass('Measure')[0]
        pickup_offset = float(first_measure.offset) if float(first_measure.duration.quarterLength) < 4 else 0.0
        # More reliable: use the actual offset of bar 1 notes
        pickup_ql = float(first_measure.duration.quarterLength)
        if 0 < pickup_ql < 4:
            pickup_offset = pickup_ql
        else:
            pickup_offset = 0.0
    except Exception:
        pickup_offset = 0.0

    parts = get_satb_parts(score)
    if parts is None:
        return None

    s = extract_voice(parts['s'], pickup_offset)
    a = extract_voice(parts['a'], pickup_offset)
    n = extract_voice(parts['n'], pickup_offset)
    l = extract_voice(parts['l'], pickup_offset)

    if not s or not l:
        return None

    # Chord analysis
    chord_labels = extract_chord_labels(score, k, pickup_offset)

    # Tempo: default 72
    tempo = 72
    try:
        from music21 import tempo as m21tempo
        mm = score.flat.getElementsByClass('MetronomeMark')
        if mm:
            tempo = int(mm[0].number)
    except Exception:
        pass

    return {
        "b": bwv,
        "k": tonic_pc,
        "m": is_minor,
        "t": tempo,
        "p": round(pickup_offset, 4),
        "s": s,
        "a": a,
        "n": n,
        "l": l,
        "cl": chord_labels   # pre-computed chord labels from music21
    }

def main():
    import sys
    paths = [p for p in corpus.getComposer('bach') if 'bwv' in str(p).lower()]
    print(f"Processing {len(paths)} Bach pieces...", flush=True)

    results = []
    failed = 0
    for i, path in enumerate(paths):
        entry = extract_chorale(path)
        if entry:
            results.append(entry)
            print(f"  [{i+1}/{len(paths)}] BWV {entry['b']} OK  ({len(entry['cl'])} chords)", flush=True)
        else:
            failed += 1
            print(f"  [{i+1}/{len(paths)}] {path.name} SKIP", flush=True)

    out_path = "bach_chorales_with_analysis.json"
    with open(out_path, "w") as f:
        json.dump(results, f, separators=(',', ':'))

    print(f"\nDone: {len(results)} chorales, {failed} skipped.")
    print(f"Output: {out_path}")
    print(f"Copy to Xcode bundle as 'bach_chorales.json'")

if __name__ == "__main__":
    main()

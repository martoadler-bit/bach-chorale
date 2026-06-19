import Foundation

struct ChoraleMIDIExporter {

    static func export(chorale: ChoraleData) -> Data {
        let tempo = chorale.tempo
        let ticksPerBeat = 480
        let uspb = 60_000_000 / tempo

        func varlen(_ v: Int) -> Data {
            var val = v; var bytes: [UInt8] = []
            repeat { bytes.insert(UInt8(val & 0x7F), at: 0); val >>= 7 } while val > 0
            for i in 0..<bytes.count - 1 { bytes[i] |= 0x80 }
            return Data(bytes)
        }
        func event(delta: Int, data: [UInt8]) -> Data { varlen(delta) + Data(data) }
        func u16(_ v: UInt16) -> Data { Data([UInt8(v >> 8), UInt8(v & 0xFF)]) }
        func u32(_ v: UInt32) -> Data {
            Data([UInt8(v>>24), UInt8((v>>16)&0xFF), UInt8((v>>8)&0xFF), UInt8(v&0xFF)])
        }

        func buildTrack(notes: [ChoralNote], channel: UInt8, programNum: UInt8, name: String) -> Data {
            var track = Data()
            // Tempo
            track += event(delta: 0, data: [0xFF,0x51,0x03,
                UInt8((uspb>>16)&0xFF), UInt8((uspb>>8)&0xFF), UInt8(uspb&0xFF)])
            // Time sig 4/4
            track += event(delta: 0, data: [0xFF,0x58,0x04, 4, 2, 0x18, 0x08])
            // Track name
            let nameBytes = Array(name.utf8)
            track += event(delta: 0, data: [0xFF,0x03,UInt8(nameBytes.count)] + nameBytes)
            // Program change
            track += event(delta: 0, data: [0xC0 | channel, programNum])

            let sorted = notes.sorted { $0.beatPosition < $1.beatPosition }
            var lastTick = 0
            for note in sorted {
                let startTick = Int(note.beatPosition * Double(ticksPerBeat))
                let durTicks  = max(1, Int(note.duration * Double(ticksPerBeat) * 0.95))
                let delta = startTick - lastTick
                if delta < 0 { continue }
                track += event(delta: delta, data: [0x90 | channel, note.midiNote, 70])
                track += event(delta: durTicks, data: [0x80 | channel, note.midiNote, 0])
                lastTick = startTick + durTicks
            }
            track += event(delta: 0, data: [0xFF,0x2F,0x00])
            return track
        }

        // Programs: Flute(73), Oboe(68), Clarinet(71), Bassoon(70) for SATB
        let voiceData: [(notes: [ChoralNote], ch: UInt8, prog: UInt8, name: String)] = [
            (chorale.soprano, 0, 73, "Soprano"),
            (chorale.alto,    1, 68, "Alto"),
            (chorale.tenor,   2, 71, "Tenor"),
            (chorale.bass,    3, 70, "Bass")
        ]

        var midi = Data()
        midi += "MThd".data(using: .ascii)!
        midi += u32(6)
        midi += u16(1)   // format 1
        midi += u16(UInt16(voiceData.count))
        midi += u16(UInt16(ticksPerBeat))

        for v in voiceData {
            let track = buildTrack(notes: v.notes, channel: v.ch, programNum: v.prog, name: v.name)
            midi += "MTrk".data(using: .ascii)!
            midi += u32(UInt32(track.count))
            midi += track
        }
        return midi
    }
}

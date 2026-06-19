import Foundation

// Corpus-derived chord statistics extracted from J.S. Bach chorales via music21.
// Loaded once at startup; falls back gracefully if the file is missing.
final class ChordStats {
    static let shared = ChordStats()

    // transition[isMinor][fromFigure][toFigure] = probability
    private var transition: [Bool: [String: [String: Double]]] = [false: [:], true: [:]]
    // unigram[isMinor][figure] = probability
    private var unigram:    [Bool: [String: Double]]           = [false: [:], true: [:]]

    private init() { load() }

    private func load() {
        guard let url  = Bundle.main.url(forResource: "chord_stats", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        func parseModeTable(_ val: Any?) -> [String: [String: Double]] {
            guard let d = val as? [String: [String: Double]] else { return [:] }
            return d
        }
        func parseUnigram(_ val: Any?) -> [String: Double] {
            guard let d = val as? [String: Double] else { return [:] }
            return d
        }

        if let t = root["transition"] as? [String: Any] {
            transition[false] = parseModeTable(t["major"])
            transition[true]  = parseModeTable(t["minor"])
        }
        if let u = root["unigram"] as? [String: Any] {
            unigram[false] = parseUnigram(u["major"])
            unigram[true]  = parseUnigram(u["minor"])
        }
    }

    var hasData: Bool { !(unigram[false]?.isEmpty ?? true) }

    // P(toFigure | fromFigure, mode) — 0 if unknown
    func transitionProbability(from: String, to: String, isMinor: Bool) -> Double {
        transition[isMinor]?[from]?[to] ?? 0
    }

    // P(figure | mode)
    func unigramProbability(_ figure: String, isMinor: Bool) -> Double {
        unigram[isMinor]?[figure] ?? 0
    }

    // Transition weights for degree 1-7, derived from corpus transition matrix.
    // `fromFigure` is the Roman numeral of the previous chord (e.g. "I", "V7", "ii").
    // Returns array indexed [0..6] = degrees I-VII.
    func transitionWeights(fromFigure: String, isMinor: Bool) -> [Double]? {
        guard hasData,
              let row = transition[isMinor]?[fromFigure],
              !row.isEmpty
        else { return nil }

        var weights = [Double](repeating: 0.01, count: 7)
        for (fig, prob) in row {
            let deg = figureToApproxDegree(fig, isMinor: isMinor)
            if deg >= 1 && deg <= 7 {
                weights[deg - 1] = max(weights[deg - 1], prob)
            }
        }
        return weights
    }

    // Map a Roman numeral figure to an approximate diatonic degree (1-7).
    private func figureToApproxDegree(_ fig: String, isMinor: Bool) -> Int {
        let upper = fig.uppercased()
        // Strip quality markers
        for (prefix, deg) in [("VII",7),("VI",6),("V",5),("IV",4),("III",3),("II",2),("I",1)] {
            if upper.hasPrefix(prefix) { return deg }
        }
        return 0
    }
}

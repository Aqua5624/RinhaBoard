import Foundation

/// かな漢字変換（辞書引き＋簡易文節スコア方式）。
/// 辞書データは Mozc の辞書 (dictionary_oss) から生成した TSV を同梱する。
/// 形式: 1行 = 「読み<TAB>候補1|候補2|候補3」、読みの UTF-8 バイト順にソート済み。
/// 全件を Swift の Dictionary に展開せず、バイト列のまま二分探索するので
/// キーボード拡張のメモリ上限でも軽い（初回利用時に行オフセットだけ作る）。
final class KanjiDictionary {
    static let shared = KanjiDictionary()

    private var data: Data?
    private var lineOffsets: [Int] = []
    private var loadAttempted = false

    func loadIfNeeded() {
        guard !loadAttempted else { return }
        loadAttempted = true
        guard let url = Bundle(for: KeyboardViewController.self)
                .url(forResource: "kana-kanji", withExtension: "tsv"),
              let d = try? Data(contentsOf: url) else { return }
        data = d
        var offsets: [Int] = [0]
        offsets.reserveCapacity(200_000)
        d.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0..<bytes.count where bytes[i] == 0x0A {
                if i + 1 < d.count { offsets.append(i + 1) }
            }
        }
        lineOffsets = offsets
    }

    var entryCount: Int { lineOffsets.count }

    /// 読みを引いて候補（最大3件、辞書順＝コスト昇順）を返す
    func lookup(_ reading: String) -> [String] {
        loadIfNeeded()
        guard let data = data, !lineOffsets.isEmpty else { return [] }
        let target = [UInt8](reading.utf8)
        var lo = 0
        var hi = lineOffsets.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let start = lineOffsets[mid]
            let end = (mid + 1 < lineOffsets.count) ? lineOffsets[mid + 1] - 1 : data.count
            var tab = start
            while tab < end && data[tab] != 0x09 { tab += 1 }
            let lineReading = [UInt8](data[start..<tab])
            let cmp = compareBytes(lineReading, target)
            if cmp == 0 {
                guard tab + 1 <= end else { return [] }
                let candStr = String(bytes: data[(tab + 1)..<end], encoding: .utf8) ?? ""
                return candStr.split(separator: "|").map(String.init)
            } else if cmp < 0 {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return []
    }

    private func compareBytes(_ a: [UInt8], _ b: [UInt8]) -> Int {
        let n = min(a.count, b.count)
        for i in 0..<n where a[i] != b[i] {
            return a[i] < b[i] ? -1 : 1
        }
        if a.count == b.count { return 0 }
        return a.count < b.count ? -1 : 1
    }
}

struct ConversionCandidate {
    let text: String
    /// 入力中の文字列（かな）の先頭から何文字を消費するか
    let consumed: Int
}

enum KanjiConverter {
    /// 原文（かな）のままが自然な読み（助動詞・指示語など）。
    /// これらは辞書候補より原文のコストを低くして優先する。
    private static let keepKana: Set<String> = [
        "する", "です", "ます", "した", "して", "いる", "ある", "ない", "たい",
        "ありがとう", "おはよう", "こんにちは", "こんばんは",
        "これ", "それ", "あれ", "どれ", "これは", "それは",
        "この", "その", "あの", "ここ", "そこ", "あそこ",
        "でした", "ました", "だった",
        "から", "けど", "ので", "のに", "まで", "より", "でも", "ただ", "また", "もう", "まだ",
    ]

    /// 助詞など、1文字で文節の区切りになりやすい文字
    private static let particles: Set<Character> = [
        "は", "が", "を", "に", "へ", "と", "も", "の", "で", "や", "か", "ね", "よ",
    ]

    private struct SegmentOption {
        let text: String
        let consumed: Int
        let cost: Double
        let isParticleRaw: Bool
    }

    /// ある位置から始まる文節の選択肢（辞書候補＋原文＋カタカナ）
    private static func options(chars: [Character], from i: Int) -> [SegmentOption] {
        let n = chars.count
        var result: [SegmentOption] = []
        let maxLen = min(10, n - i)
        for len in 1...maxLen {
            let segment = String(chars[i..<(i + len)])
            // 辞書候補（原文と同形のものは原文側で扱うので除く。
            // 読みをそのままカタカナにしただけの候補は中間のコストにする：
            // 外来語（てすと→テスト）では正解だが、和語（わたしは→ワタシハ）では
            // 分割した変換の方が安くなるように）
            let found = KanjiDictionary.shared.lookup(segment)
            let kataSegment = toKatakana(segment)
            for (rank, cand) in found.enumerated() where cand != segment {
                let cost = (cand == kataSegment) ? 2.4 : 1.0 + 0.7 * Double(rank)
                result.append(SegmentOption(
                    text: cand, consumed: len,
                    cost: cost, isParticleRaw: false))
            }
            // 原文（かなのまま）
            let rawCost: Double
            var isParticle = false
            if len == 1 && particles.contains(chars[i]) {
                rawCost = 0.4
                isParticle = true
            } else if keepKana.contains(segment) {
                rawCost = 0.8
            } else {
                // 原文のままは長くなるほど不利にする（文全体を原文で通す誤判定の防止）
                rawCost = 1.7 + 0.5 * Double(len)
            }
            result.append(SegmentOption(text: segment, consumed: len, cost: rawCost, isParticleRaw: isParticle))
            // カタカナ（外来語など。辞書に無い場合の受け皿）
            if len >= 2 {
                result.append(SegmentOption(
                    text: toKatakana(segment), consumed: len, cost: 5.0, isParticleRaw: false))
            }
        }
        // 原文は残り全部を1文節にする選択肢も常に入れる（DPの到達可能性の保証）
        if n - i > maxLen {
            let rest = String(chars[i..<n])
            result.append(SegmentOption(
                text: rest, consumed: n - i,
                cost: 1.7 + 0.5 * Double(n - i), isParticleRaw: false))
        }
        return result
    }

    /// 入力中のかな文字列に対する候補一覧。
    /// 全体を最も自然に分割できる候補（文節スコア最小）を先頭にし、
    /// 先頭文節の他の選択肢も「その選択をしたときの文全体のスコア」順に並べる。
    static func candidates(for composing: String) -> [ConversionCandidate] {
        guard !composing.isEmpty else { return [] }
        let chars = Array(composing)
        let n = chars.count

        // 各位置の選択肢をキャッシュしつつ、後ろから最小コストを計算する
        var optionsCache: [Int: [SegmentOption]] = [:]
        func optionsAt(_ i: Int) -> [SegmentOption] {
            if let cached = optionsCache[i] { return cached }
            let opts = options(chars: chars, from: i)
            optionsCache[i] = opts
            return opts
        }
        var best = [Double](repeating: 0, count: n + 1)
        if n > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                var minCost = Double.greatestFiniteMagnitude
                for opt in optionsAt(i) {
                    let total = opt.cost + best[i + opt.consumed]
                    if total < minCost { minCost = total }
                }
                best[i] = minCost
            }
        }

        let firstOptions = optionsAt(0)
        let scored: [(option: SegmentOption, total: Double, order: Int)] =
            firstOptions.enumerated().map { (idx, opt) in
                (option: opt, total: opt.cost + best[opt.consumed], order: idx)
            }
        let sorted = scored.sorted { a, b in
            if a.total != b.total { return a.total < b.total }
            if a.option.isParticleRaw != b.option.isParticleRaw { return a.option.isParticleRaw }
            if a.option.consumed != b.option.consumed { return a.option.consumed < b.option.consumed }
            return a.order < b.order
        }
        var result: [ConversionCandidate] = []
        var seen = Set<String>()
        for entry in sorted {
            let text = entry.option.text
            guard !seen.contains(text) else { continue }
            seen.insert(text)
            result.append(ConversionCandidate(text: text, consumed: entry.option.consumed))
            if result.count >= 24 { break }
        }
        return result
    }

    static func toKatakana(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            if (0x3041...0x3096).contains(scalar.value),
               let kata = Unicode.Scalar(scalar.value + 0x60) {
                out.append(kata)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }
}

import Foundation

/// ローマ字 → ひらがな変換（漢字変換は持たない軽量版）。
/// 入力中のローマ字バッファを受け取り、確定できる部分だけかなに変換して返す。
enum RomajiKana {
    static let table: [String: String] = [
        // 3文字
        "shi": "し", "chi": "ち", "tsu": "つ",
        "sha": "しゃ", "shu": "しゅ", "sho": "しょ",
        "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ",
        "jya": "じゃ", "jyu": "じゅ", "jyo": "じょ",
        "kya": "きゃ", "kyu": "きゅ", "kyo": "きょ",
        "nya": "にゃ", "nyu": "にゅ", "nyo": "にょ",
        "hya": "ひゃ", "hyu": "ひゅ", "hyo": "ひょ",
        "mya": "みゃ", "myu": "みゅ", "myo": "みょ",
        "rya": "りゃ", "ryu": "りゅ", "ryo": "りょ",
        "gya": "ぎゃ", "gyu": "ぎゅ", "gyo": "ぎょ",
        "bya": "びゃ", "byu": "びゅ", "byo": "びょ",
        "pya": "ぴゃ", "pyu": "ぴゅ", "pyo": "ぴょ",
        "ja": "じゃ", "ju": "じゅ", "jo": "じょ", "ji": "じ",
        // 2文字
        "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
        "sa": "さ", "su": "す", "se": "せ", "so": "そ",
        "ta": "た", "te": "て", "to": "と",
        "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
        "ha": "は", "hi": "ひ", "fu": "ふ", "he": "へ", "ho": "ほ",
        "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
        "ya": "や", "yu": "ゆ", "yo": "よ",
        "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
        "wa": "わ", "wo": "を",
        "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
        "za": "ざ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
        "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",
        "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
        "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
        "zi": "じ",
        "xa": "ぁ", "xi": "ぃ", "xu": "ぅ", "xe": "ぇ", "xo": "ぉ",
        "la": "ぁ", "li": "ぃ", "lu": "ぅ", "le": "ぇ", "lo": "ぉ",
        "xtu": "っ", "ltu": "っ",
        // 1文字
        "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
        "-": "ー",
    ]

    private static let consonants = Set("bcdfghjklmpqrstvwxyz")

    /// バッファを処理する。
    /// - Returns: (確定して挿入してよい文字列, まだ入力中として残すローマ字)
    /// flush=true のときは残りも可能な限り確定する（n → ん、変換できない文字はそのまま）。
    static func process(_ buffer: String, flush: Bool) -> (committed: String, pending: String) {
        var rest = buffer
        var out = ""
        while !rest.isEmpty {
            // 促音：同じ子音が重なったら「っ」（n は除く）
            if rest.count >= 2 {
                let first = rest.first!
                let second = rest[rest.index(after: rest.startIndex)]
                if first == second, consonants.contains(first), first != "n" {
                    out += "っ"
                    rest = String(rest.dropFirst())
                    continue
                }
            }
            // 「ん」：n + 子音、または nn（ただし nn の直後が母音・y のときは
            // ん＋な行の可能性があるので、nn だけでは確定せず次を待つ。
            // 例: konnichiha → こんにちは、になる）
            if rest.first == "n" {
                if rest.hasPrefix("nn") {
                    if rest.count == 2 {
                        if flush {
                            out += "ん"
                            rest = ""
                            continue
                        }
                        break // 入力中として待つ
                    }
                    let third = rest[rest.index(rest.startIndex, offsetBy: 2)]
                    if "aiueoy".contains(third) {
                        out += "ん"
                        rest = String(rest.dropFirst()) // 2つ目の n は な行の頭として残す
                        continue
                    }
                    out += "ん"
                    rest = String(rest.dropFirst(2))
                    continue
                }
                if rest.count >= 2 {
                    let second = rest[rest.index(after: rest.startIndex)]
                    if consonants.contains(second), second != "y" {
                        out += "ん"
                        rest = String(rest.dropFirst())
                        continue
                    }
                } else if flush {
                    out += "ん"
                    rest = ""
                    continue
                }
            }
            // 最長一致で変換
            var matched = false
            for len in [3, 2, 1] {
                guard rest.count >= len else { continue }
                let key = String(rest.prefix(len))
                if let kana = table[key] {
                    // 3文字キーの途中（例: "sh" は "shi/sha…" の途中）かもしれない場合は
                    // flush でない限り待つ判定は下の prefix チェックで行う
                    out += kana
                    rest = String(rest.dropFirst(len))
                    matched = true
                    break
                }
            }
            if matched { continue }
            // どのキーにも一致しない先頭文字：
            // まだキー prefix の途中なら入力中として待つ（flush時はそのまま出す）
            let isPrefixOfKey = table.keys.contains { $0.hasPrefix(rest) }
            if isPrefixOfKey && !flush {
                break
            }
            if flush {
                out += String(rest.first!)
                rest = String(rest.dropFirst())
                continue
            }
            // 先頭1文字が prefix でも変換対象でもない（例: "k" 単体は prefix なのでここには来にくい）
            break
        }
        return (out, rest)
    }
}

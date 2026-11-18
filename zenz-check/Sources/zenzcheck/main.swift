import Foundation
import KanaKanjiConverterModule
import KanaKanjiConverterModuleWithDefaultDictionary

// アプリの commitConvertedAll（確定キー）と同じ手順を再現し、
// 候補の consumed（消費する読みの文字数）が正しいか、全確定の出力が
// おかしくならないかを検証する。
// Usage: zenzcheck <model.gguf>
let modelPath = CommandLine.arguments[1]
let dataDir = URL(fileURLWithPath: "/tmp/zenzcheck-data")
try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

let options = ConvertRequestOptions(
    N_best: 10,
    requireJapanesePrediction: .disabled,
    requireEnglishPrediction: .disabled,
    keyboardLanguage: .ja_JP,
    englishCandidateInRoman2KanaInput: true,
    fullWidthRomanCandidate: false,
    halfWidthKanaCandidate: false,
    learningType: .inputAndOutput,
    maxMemoryCount: 65536,
    shouldResetMemory: false,
    memoryDirectoryURL: dataDir,
    sharedContainerURL: dataDir,
    textReplacer: .withDefaultEmojiDictionary(),
    specialCandidateProviders: nil,
    zenzaiMode: .on(weight: URL(fileURLWithPath: modelPath),
                    inferenceLimit: 1, personalizationMode: nil,
                    versionDependentMode: .v3(.init())),
    metadata: .init(versionString: "zenzcheck")
)

func inputCount(of count: ComposingCount) -> Int {
    switch count {
    case .inputCount(let v): return v
    case .surfaceCount(let v): return v
    case .composite(let lhs, let rhs): return inputCount(of: lhs) + inputCount(of: rhs)
    @unknown default: return 0
    }
}

let converter = KanaKanjiConverter.withDefaultDictionary()

struct Cand { let text: String; let consumed: Int }

/// アプリの AzooKeyEngine.candidates と同じ組み立て（辞書・学習マージなし）
func appCandidates(for composing: String) -> [Cand] {
    var ct = ComposingText()
    ct.insertAtCursorPosition(composing, inputStyle: .direct)
    let results = converter.requestCandidates(ct, options: options)
    var result: [Cand] = []
    var seen = Set<String>()
    func append(_ c: Candidate) {
        guard c.inputable else { return }
        let text = c.text
        guard !text.isEmpty, !seen.contains(text) else { return }
        seen.insert(text)
        let consumed = inputCount(of: c.composingCount)
        guard consumed > 0 else { return }
        result.append(Cand(text: text, consumed: min(consumed, composing.count)))
    }
    for c in results.mainResults { append(c) }
    for c in results.firstClauseResults { append(c) }
    if !seen.contains(composing) {
        result.append(Cand(text: composing, consumed: composing.count))
    }
    let kata = composing.applyingTransform(.hiraganaToKatakana, reverse: false) ?? composing
    if !seen.contains(kata) {
        result.append(Cand(text: kata, consumed: composing.count))
    }
    return Array(result.prefix(24))
}

let inputs = [
    "とうきょうとっきょきょかきょくきょくちょう",
    "となりのきゃくはよくかきくうきゃくだ",
    "きょうはいいてんきですね",
    "ありがとうございます",
    "かいぎのしりょうをかくにんする",
    "あいあい",
    "でんしゃがおくれています",
    "あしたのよていをきめる",
    "にほんごをべんきょうしています",
    "かんじへんかんのてすとです",
]
for input in inputs {
    print("===== input: \(input) (count \(input.count))")
    for c in appCandidates(for: input).prefix(6) {
        print("  cand: \(c.text) consumed=\(c.consumed)")
    }
    var rest = input
    var out = ""
    var step = 0
    while !rest.isEmpty && step < 64 {
        step += 1
        let cands = appCandidates(for: rest)
        guard let f = cands.first, f.consumed > 0 else {
            print("  !! no candidate for rest=\(rest)")
            break
        }
        print("  step \(step): rest=\(rest) -> \(f.text) (consumed \(f.consumed))")
        out += f.text
        rest = String(rest.dropFirst(f.consumed))
    }
    print("  OUTPUT: \(out)")
}
print("DONE")

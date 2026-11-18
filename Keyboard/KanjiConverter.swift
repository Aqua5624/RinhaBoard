import Foundation
import KanaKanjiConverterModule
import KanaKanjiConverterModuleWithDefaultDictionary

/// 変換候補（候補バー表示用）
struct ConversionCandidate {
    let text: String
    /// 入力中の文字列（かな）の先頭から何文字を消費するか
    let consumed: Int
    /// azooKey の候補本体（学習通知に使う。自前候補では nil）
    var azooCandidate: Candidate? = nil
    /// ユーザー辞書由来かどうか
    var isUserDict: Bool = false
}

/// かな漢字変換エンジン: azooKey の AzooKeyKanaKanjiConverter を使う。
/// - 候補は firstClauseResults（最初の文節の候補）を軸に、
///   mainResults の先頭（文全体の変換）を加えたものを返す
/// - ユーザー辞書は importDynamicUserDictionary でエンジン側にも取り込みつつ、
///   確実に出るよう自前でも先頭にマージする
/// - 選択された候補は setCompletedData でエンジンの学習にも伝える
enum KanjiConverter {
    private static let engine = AzooKeyEngine()

    static func candidates(for composing: String) -> [ConversionCandidate] {
        engine.candidates(for: composing)
    }

    /// 初回変換の重さ（辞書読み込み等）をキーボード表示直後に済ませておく
    static func warmUp() {
        _ = engine.candidates(for: "あい")
    }

    /// 候補が選択・確定されたことをエンジン（学習）に伝える
    static func notifySelected(_ candidate: ConversionCandidate) {
        engine.notifySelected(candidate)
    }

    /// ユーザー辞書が変わったときに呼び直す
    static func reloadUserDictionary() {
        engine.reloadUserDictionary()
    }

    static func toKatakana(_ s: String) -> String {
        s.katakanaConverted()
    }
}

private final class AzooKeyEngine {
    private let converter = KanaKanjiConverter.withDefaultDictionary()
    private var importedUserDictSignature: String = ""

    init() {
        reloadUserDictionary()
    }

    // MARK: オプション

    /// 学習・ユーザ辞書データの保存先（App Group が使えれば共有、無ければ拡張の書類フォルダ）
    private func storageDirectory() -> URL {
        let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("AzooKeyData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeOptions() -> ConvertRequestOptions {
        let dir = storageDirectory()
        return ConvertRequestOptions(
            N_best: 10,
            requireJapanesePrediction: .autoMix,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            englishCandidateInRoman2KanaInput: true,
            fullWidthRomanCandidate: false,
            halfWidthKanaCandidate: false,
            learningType: .inputAndOutput,
            maxMemoryCount: 65536,
            shouldResetMemory: false,
            memoryDirectoryURL: dir,
            sharedContainerURL: dir,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: nil,
            metadata: .init(versionString: "Sparkle Key 0.3.2")
        )
    }

    // MARK: ユーザー辞書

    func reloadUserDictionary() {
        let entries = SharedStore.loadUserDict()
        let signature = entries.map { "\($0.reading)=\($0.word)=\($0.partOfSpeech.rawValue)" }
            .joined(separator: "\n")
        guard signature != importedUserDictSignature else { return }
        importedUserDictSignature = signature
        let elements = entries.map { entry -> DicdataElement in
            let cid: Int
            switch entry.partOfSpeech {
            case .general: cid = CIDData.一般名詞.cid
            case .proper: cid = CIDData.固有名詞.cid
            }
            return DicdataElement(
                word: entry.word,
                ruby: entry.reading.katakanaConverted(),
                lcid: cid, rcid: cid,
                mid: MIDData.一般.mid,
                value: -10
            )
        }
        converter.importDynamicUserDictionary(elements)
    }

    // MARK: 変換

    func candidates(for composing: String) -> [ConversionCandidate] {
        guard !composing.isEmpty else { return [] }
        reloadUserDictionary()

        var composingText = ComposingText()
        composingText.insertAtCursorPosition(composing, inputStyle: .direct)
        let results = converter.requestCandidates(composingText, options: makeOptions())

        var result: [ConversionCandidate] = []
        var seen = Set<String>()

        // ユーザー辞書（最優先・長い読みから）
        let entries = SharedStore.loadUserDict()
        if !entries.isEmpty {
            let chars = Array(composing)
            for len in stride(from: chars.count, through: 1, by: -1) {
                let prefix = String(chars.prefix(len))
                for entry in entries where entry.reading == prefix {
                    guard !seen.contains(entry.word) else { continue }
                    seen.insert(entry.word)
                    result.append(ConversionCandidate(
                        text: entry.word, consumed: len, azooCandidate: nil, isUserDict: true))
                }
            }
        }

        func appendAzoo(_ candidate: Candidate) {
            guard candidate.inputable else { return }
            let text = candidate.text
            guard !text.isEmpty, !seen.contains(text) else { return }
            seen.insert(text)
            let consumed = Self.inputCount(of: candidate.composingCount)
            guard consumed > 0 else { return }
            result.append(ConversionCandidate(
                text: text, consumed: min(consumed, composing.count), azooCandidate: candidate))
        }

        // 文全体の変換（最初の候補だけ）→ 最初の文節の候補 → 予測候補の順
        if let full = results.mainResults.first {
            appendAzoo(full)
        }
        for cand in results.firstClauseResults {
            appendAzoo(cand)
        }
        for cand in results.mainResults.dropFirst() {
            appendAzoo(cand)
        }

        // 受け皿：原文とカタカナ
        if !seen.contains(composing) {
            result.append(ConversionCandidate(text: composing, consumed: composing.count))
        }
        let kata = composing.katakanaConverted()
        if !seen.contains(kata) {
            result.append(ConversionCandidate(text: kata, consumed: composing.count))
        }
        return Array(result.prefix(24))
    }

    func notifySelected(_ candidate: ConversionCandidate) {
        guard let azoo = candidate.azooCandidate else { return }
        converter.setCompletedData(azoo)
        converter.commitUpdateLearningData()
    }

    /// ComposingCount から入力文字数の合計を取り出す
    static func inputCount(of count: ComposingCount) -> Int {
        switch count {
        case .inputCount(let v):
            return v
        case .surfaceCount(let v):
            return v
        case .composite(let lhs, let rhs):
            return inputCount(of: lhs) + inputCount(of: rhs)
        @unknown default:
            return 0
        }
    }
}

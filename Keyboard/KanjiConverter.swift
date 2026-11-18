import Foundation
import SparkleKeyCore  // @_exported 経由で KanaKanjiConverterModule 群が見える

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
    private static let lock = NSLock()

    static func candidates(for composing: String) -> [ConversionCandidate] {
        lock.lock()
        defer { lock.unlock() }
        return engine.candidates(for: composing)
    }

    /// 初回変換の重さ（辞書読み込み等）をキーボード表示直後に済ませておく
    static func warmUp() {
        lock.lock()
        defer { lock.unlock() }
        _ = engine.candidates(for: "あい", allowZenzai: false)
    }

    /// 候補が選択・確定されたことを学習に伝える（reading は消費した読み）
    static func notifySelected(_ candidate: ConversionCandidate, reading: String, weight: Int = 1) {
        lock.lock()
        defer { lock.unlock() }
        engine.notifySelected(candidate, reading: reading, weight: weight)
    }

    /// 文全体の変換結果を学習する（よく打つフレーズを丸ごと候補化する）
    static func recordPhrase(reading: String, text: String) {
        guard reading.count >= 2, !text.isEmpty, text != reading,
              text != reading.katakanaConverted() else { return }
        SharedStore.recordLearned(reading: reading, word: text, weight: 1)
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
    private var cachedOptions: ConvertRequestOptions?
    private var cachedZenzaiOptions: ConvertRequestOptions?
    private var cachedDictRaw: Data?
    private var cachedEntries: [UserDictEntry] = []

    init() {
        reloadUserDictionary()
    }

    // MARK: オプション

    /// 学習・ユーザ辞書データの保存先（App Group が使えれば共有、無ければ拡張の書類フォルダ）
    private lazy var storageDir: URL = {
        let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("AzooKeyData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func makeOptions(useZenzai: Bool) -> ConvertRequestOptions {
        if useZenzai, let cached = cachedZenzaiOptions { return cached }
        if !useZenzai, let cachedOptions = cachedOptions { return cachedOptions }
        let dir = storageDir
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
            memoryDirectoryURL: dir,
            sharedContainerURL: dir,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: nil,
            zenzaiMode: useZenzai ? zenzaiMode() : .off,
            metadata: .init(versionString: "Sparkle Key 0.7.0")
        )
        if useZenzai { cachedZenzaiOptions = options } else { cachedOptions = options }
        return options
    }

    /// Zenzai（AI変換）: モデルファイルが拡張バンドルにあれば有効化する。
    /// モデルは CI で HuggingFace の公式配布（Miwa-Keita/zenz-v3.2-small-gguf）
    /// から取得して同梱する。無ければ通常変換にフォールバック。
    private func zenzaiMode() -> ConvertRequestOptions.ZenzaiMode {
        guard SharedStore.zenzaiEnabled else { return .off }
        let weight = Bundle.main.bundleURL
            .appendingPathComponent("ggml-model-Q5_K_M.gguf")
        guard FileManager.default.fileExists(atPath: weight.path) else {
            return .off
        }
        return .on(weight: weight, inferenceLimit: 1, personalizationMode: nil,
                   versionDependentMode: .v3(.init()))
    }

    private var cachedLearnedRaw: Data?
    private var cachedLearned: [LearnedWord] = []

    /// 学習データのキャッシュ（保存データが変わったときだけ読み直す）
    private func learnedWords() -> [LearnedWord] {
        let raw = SharedStore.learnedWordsRawData()
        if raw != cachedLearnedRaw {
            cachedLearnedRaw = raw
            cachedLearned = SharedStore.loadLearnedWords()
        }
        return cachedLearned
    }

    /// ユーザー辞書のキャッシュ（保存データが変わったときだけ読み直す）
    private func userDictEntries() -> [UserDictEntry] {
        let raw = SharedStore.userDictRawData()
        if raw != cachedDictRaw {
            cachedDictRaw = raw
            cachedEntries = SharedStore.loadUserDict()
        }
        return cachedEntries
    }

    // MARK: ユーザー辞書

    func reloadUserDictionary() {
        let entries = userDictEntries()
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
        candidates(for: composing, allowZenzai: true)
    }

    func candidates(for composing: String, allowZenzai: Bool) -> [ConversionCandidate] {
        guard !composing.isEmpty else { return [] }
        reloadUserDictionary()

        var composingText = ComposingText()
        composingText.insertAtCursorPosition(composing, inputStyle: .direct)
        let results = converter.requestCandidates(
            composingText, options: makeOptions(useZenzai: allowZenzai))

        var result: [ConversionCandidate] = []
        var seen = Set<String>()

        // ユーザー辞書・学習は「読み全体に一致する候補」だけを先頭に置く。
        // 部分一致（例: 読み「の」→「の」）を文全体の変換より前に置くと、
        // 全確定が短い候補で文を細切れにしてしまう（「の野村龍太郎」の原因）。
        // 部分一致は文全体の変換の後ろに回す。
        var dictFull: [ConversionCandidate] = []
        var dictPartial: [ConversionCandidate] = []
        func collectDict(reading: String, word: String, isUserDict: Bool, len: Int) {
            guard !seen.contains(word) else { return }
            seen.insert(word)
            let cand = ConversionCandidate(
                text: word, consumed: len, azooCandidate: nil, isUserDict: isUserDict)
            if len == composing.count { dictFull.append(cand) } else { dictPartial.append(cand) }
        }
        let chars = Array(composing)
        let entries = userDictEntries()
        for len in stride(from: chars.count, through: 1, by: -1) {
            let prefix = String(chars.prefix(len))
            for entry in entries where entry.reading == prefix {
                collectDict(reading: entry.reading, word: entry.word, isUserDict: true, len: len)
            }
        }
        let learned = learnedWords()
        for len in stride(from: chars.count, through: 1, by: -1) {
            let prefix = String(chars.prefix(len))
            for entry in learned where entry.reading == prefix {
                collectDict(reading: entry.reading, word: entry.word, isUserDict: false, len: len)
            }
        }
        result += dictFull

        // 原文（かな）・カタカナのままの候補は、変換候補がある限り後ろに回す。
        // エンジンが原文を先頭に返すことがあり、そのままだとスペースを
        // 押しても「変わらない」ように見えるため。
        var deferredRaw: [ConversionCandidate] = []
        let kataOfComposing = composing.katakanaConverted()
        func appendAzoo(_ candidate: Candidate) {
            guard candidate.inputable else { return }
            let text = candidate.text
            guard !text.isEmpty, !seen.contains(text) else { return }
            seen.insert(text)
            let consumed = Self.inputCount(of: candidate.composingCount)
            guard consumed > 0 else { return }
            let conv = ConversionCandidate(
                text: text, consumed: min(consumed, composing.count), azooCandidate: candidate)
            if text == composing || text == kataOfComposing {
                deferredRaw.append(conv)
            } else {
                result.append(conv)
            }
        }

        // 文全体の変換（全候補）→ 最初の文節の候補、の順。
        // 文節候補を文全体より前に出すと、タップした候補で文が細切れに
        // 確定されて変換が不安定に見えるため、文全体を優先する。
        for cand in results.mainResults {
            appendAzoo(cand)
        }
        result += dictPartial
        for cand in results.firstClauseResults {
            appendAzoo(cand)
        }

        result += deferredRaw

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

    func notifySelected(_ candidate: ConversionCandidate, reading: String, weight: Int = 1) {
        // エンジン側の学習（文脈込みの順位付けに効く）
        if let azoo = candidate.azooCandidate {
            converter.setCompletedData(azoo)
            converter.commitUpdateLearningData()
        }
        // アプリ側の学習（読み→選んだ表記）。かな・カタカナそのままと
        // ユーザー辞書（登録済み）は対象外。次回から候補の先頭に出す。
        guard !candidate.isUserDict,
              candidate.text != reading,
              candidate.text != reading.katakanaConverted() else { return }
        SharedStore.recordLearned(reading: reading, word: candidate.text, weight: weight)
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

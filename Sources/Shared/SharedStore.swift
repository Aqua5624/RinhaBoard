import Foundation

/// クリップボード履歴の1件
struct ClipItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var pinned: Bool = false
    var createdAt: Date = Date()
}

/// ユーザー辞書の品詞（azooKey の CID に対応させる）
enum UserDictPartOfSpeech: String, Codable, CaseIterable, Identifiable {
    case general   // 一般名詞
    case proper    // 固有名詞
    var id: String { rawValue }
    var label: String {
        switch self {
        case .general: return "一般名詞"
        case .proper: return "固有名詞"
        }
    }
}

/// 学習した変換の1件（読み→選んだ表記）
struct LearnedWord: Codable, Identifiable, Equatable {
    var id: String { reading + "\u{1}" + word }
    /// 読み（ひらがな）
    var reading: String
    /// ユーザーが選んだ表記
    var word: String
    /// 選ばれた回数
    var count: Int = 1
    var lastUsed: Date = Date()
}

/// ユーザー辞書の1件
struct UserDictEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// 読み（ひらがなに正規化して保存する）
    var reading: String
    /// 単語（変換候補として出したい表記）
    var word: String
    var partOfSpeech: UserDictPartOfSpeech = .proper
    var createdAt: Date = Date()
}

extension String {
    /// カタカナ→ひらがな変換＋前後の空白除去（ユーザー辞書の読み正規化用）
    func hiraganaNormalized() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        var out = String.UnicodeScalarView()
        for scalar in trimmed.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value),
               let hira = Unicode.Scalar(scalar.value - 0x60) {
                out.append(hira)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    /// ひらがな→カタカナ変換（azooKey 辞書のルビ表記用）
    func katakanaConverted() -> String {
        var out = String.UnicodeScalarView()
        for scalar in unicodeScalars {
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

/// 数字モードの並び方（「123」を押したときのレイアウト）
/// かな入力の方式（QWERTYローマ字 / フリック）
enum KanaStyle: String, CaseIterable, Identifiable {
    case qwerty, flick
    var id: String { rawValue }
    var label: String {
        switch self {
        case .qwerty: return "QWERTY"
        case .flick: return "フリック"
        }
    }
}

enum NumberStyle: String, CaseIterable, Identifiable {
    case qwerty   // 数字・記号をQWERTY風の横並びで出す
    case tenkey   // 数字テンキー（レール付きパッド）で出す
    case flick    // フリック入力パッド（12キー）で出す
    var id: String { rawValue }
    var label: String {
        switch self {
        case .qwerty: return "QWERTY数字"
        case .tenkey: return "テンキー"
        case .flick: return "フリック"
        }
    }
}

/// 本体アプリとキーボード拡張で共有する保存領域。
/// App Group が使える環境では共有スイートを使い、使えない環境
/// （LiveContainer 等でグループ権限が落ちる場合）では標準領域にフォールバックする。
/// その場合でもキーボード単体での履歴保存・挿入はそのまま動く。
enum SharedStore {
    /// 実際に使える App Group ID。
    /// AltStore 等で再署名されるとグループ ID がチーム付きに書き換わるため、
    /// embedded.mobileprovision の Entitlements から実物を読む。
    /// 読めない環境（未署名ビルド等）ではプロジェクト既定の ID を使う。
    static let appGroupID: String = discoverAppGroupID()

    private static func discoverAppGroupID() -> String {
        let fallback = "group.com.aqua5624.RinhaBoard"
        var urls = [Bundle.main.bundleURL
            .appendingPathComponent("embedded.mobileprovision")]
        // 拡張（.appex）からは2つ上が .app 本体
        urls.append(Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("embedded.mobileprovision"))
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .isoLatin1),
                  let start = text.range(of: "<plist"),
                  let end = text.range(of: "</plist>") else { continue }
            let xml = String(text[start.lowerBound...end.upperBound])
            guard let xmlData = xml.data(using: .utf8),
                  let obj = try? PropertyListSerialization.propertyList(
                    from: xmlData, options: [], format: nil) as? [String: Any],
                  let entitlements = obj["Entitlements"] as? [String: Any],
                  let groups = entitlements[
                    "com.apple.security.application-groups"] as? [String],
                  let group = groups.first else { continue }
            return group
        }
        return fallback
    }

    /// App Group の共有コンテナが本当に使えるか。
    /// UserDefaults(suiteName:) は権限が無くてもインスタンスを返すため、
    /// 共有できているかはこちらで判定する（本体と拡張で別々の保存領域を
    /// 読んでしまうと、設定が届かない・データが食い違う原因になる）。
    static var groupAvailable: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    private static var didMigrate = false

    static var defaults: UserDefaults {
        if groupAvailable, let suite = UserDefaults(suiteName: appGroupID) {
            migrateToSuiteIfNeeded(suite)
            return suite
        }
        return UserDefaults.standard
    }

    /// 共有が効いていなかった間に各プロセスの標準領域へ貯まった rb_* を、
    /// 共有スイートへ一度だけ引き継ぐ（スイート側にある値を優先）。
    private static func migrateToSuiteIfNeeded(_ suite: UserDefaults) {
        if didMigrate { return }
        didMigrate = true
        let std = UserDefaults.standard
        for (key, value) in std.dictionaryRepresentation()
        where key.hasPrefix("rb_") {
            if suite.object(forKey: key) == nil {
                suite.set(value, forKey: key)
            }
        }
    }

    private static let keyClipItems = "rb_clipItems_v1"
    private static let keyNumberStyle = "rb_numberStyle"
    private static let keyAutoCapture = "rb_autoCaptureClipboard"
    private static let keyShowNumberRow = "rb_showNumberRow"
    private static let keyLastChangeCount = "rb_lastPasteboardChangeCount"
    private static let keyInputLangKana = "rb_inputLangKana"
    private static let keyZenzaiEnabled = "rb_zenzaiEnabled"
    private static let keyAutoConvert = "rb_autoConvertEnabled"
    private static let keyRecentEmoji = "rb_recentEmoji_v1"

    // MARK: - 設定

    private static let keyKanaStyle = "rb_kanaStyle_v1"
    /// かな入力の方式。未設定なら旧「123の並び」がフリックだった場合に引き継ぐ
    static var kanaStyle: KanaStyle {
        get {
            if let raw = defaults.string(forKey: keyKanaStyle),
               let style = KanaStyle(rawValue: raw) {
                return style
            }
            return numberStyle == .flick ? .flick : .qwerty
        }
        set { defaults.set(newValue.rawValue, forKey: keyKanaStyle) }
    }

    static var numberStyle: NumberStyle {
        get {
            if let raw = defaults.string(forKey: keyNumberStyle),
               let style = NumberStyle(rawValue: raw) {
                return style
            }
            return .qwerty
        }
        set { defaults.set(newValue.rawValue, forKey: keyNumberStyle) }
    }

    /// キーボードを開いたとき、今のクリップボードを自動で履歴に取り込むか
    static var autoCaptureClipboard: Bool {
        get {
            if defaults.object(forKey: keyAutoCapture) == nil { return true }
            return defaults.bool(forKey: keyAutoCapture)
        }
        set { defaults.set(newValue, forKey: keyAutoCapture) }
    }

    /// Gboard風：英字モードの上に数字行を常時表示するか
    static var showNumberRow: Bool {
        get { defaults.bool(forKey: keyShowNumberRow) }
        set { defaults.set(newValue, forKey: keyShowNumberRow) }
    }

    /// 入力言語（かな ⇄ EN）。キーボード拡張は iOS に再起動されることがあるため、
    /// 拡張のメモリではなく共有領域に保存して復元する。デフォルトはかな入力。
    static var inputLangIsKana: Bool {
        get {
            if defaults.object(forKey: keyInputLangKana) == nil { return true }
            return defaults.bool(forKey: keyInputLangKana)
        }
        set { defaults.set(newValue, forKey: keyInputLangKana) }
    }

    /// AI変換（Zenzai）を使うか。本体アプリの設定から切り替え可能。
    /// 拡張がメモリ不足で落ちる場合の切り分け・回避用。デフォルト ON。
    // MARK: - 見た目（テーマ色・片手モード・高さ）

    private static let keyAccentIndex = "rb_accentIndex_v1"
    /// テーマ色プリセットの番号（0=青 1=紫 2=ピンク 3=緑 4=グレー）
    static var accentIndex: Int {
        get { defaults.integer(forKey: keyAccentIndex) }
        set { defaults.set(newValue, forKey: keyAccentIndex) }
    }

    private static let keyOneHanded = "rb_oneHandedMode_v1"
    /// 片手モード（0=オフ 1=右寄せ 2=左寄せ）
    static var oneHandedMode: Int {
        get { defaults.integer(forKey: keyOneHanded) }
        set { defaults.set(newValue, forKey: keyOneHanded) }
    }

    private static let keyHeightScale = "rb_keyboardHeightScale_v1"
    /// キーボードの高さ倍率（0.85〜1.15、未設定なら 1.0）
    static var keyboardHeightScale: Double {
        get {
            let v = defaults.double(forKey: keyHeightScale)
            return v == 0 ? 1.0 : min(1.15, max(0.85, v))
        }
        set { defaults.set(newValue, forKey: keyHeightScale) }
    }

    static var zenzaiEnabled: Bool {
        get {
            if defaults.object(forKey: keyZenzaiEnabled) == nil { return true }
            return defaults.bool(forKey: keyZenzaiEnabled)
        }
        set { defaults.set(newValue, forKey: keyZenzaiEnabled) }
    }

    /// 自動変換（確定キーで入力中の残りをまとめて変換するか）。
    /// OFF のときは確定キーでかなのまま確定する。デフォルト ON。
    static var autoConvertEnabled: Bool {
        get {
            if defaults.object(forKey: keyAutoConvert) == nil { return true }
            return defaults.bool(forKey: keyAutoConvert)
        }
        set { defaults.set(newValue, forKey: keyAutoConvert) }
    }

    // MARK: - 最近使った絵文字

    static func loadRecentEmoji() -> [String] {
        guard let data = defaults.data(forKey: keyRecentEmoji),
              let items = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return items
    }

    static func addRecentEmoji(_ emoji: String) {
        var items = loadRecentEmoji()
        items.removeAll { $0 == emoji }
        items.insert(emoji, at: 0)
        if items.count > 40 { items = Array(items.prefix(40)) }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: keyRecentEmoji)
        }
    }

    static var lastPasteboardChangeCount: Int {
        get { defaults.integer(forKey: keyLastChangeCount) }
        set { defaults.set(newValue, forKey: keyLastChangeCount) }
    }

    // MARK: - クリップボード履歴

    static func loadClipItems() -> [ClipItem] {
        guard let data = defaults.data(forKey: keyClipItems),
              let items = try? JSONDecoder().decode([ClipItem].self, from: data) else {
            return []
        }
        return items
    }

    static func saveClipItems(_ items: [ClipItem]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: keyClipItems)
        }
    }

    /// 先頭に追加する。同文が既にあれば先頭へ移動（重複は作らない）。
    /// 上限100件。ピン留めは上限超過でも消さない。
    @discardableResult
    static func addClipItem(text rawText: String) -> [ClipItem] {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return loadClipItems() }
        var items = loadClipItems()
        if let idx = items.firstIndex(where: { $0.text == text }) {
            let existing = items.remove(at: idx)
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipItem(text: text), at: 0)
        }
        if items.count > 100 {
            // 後ろから、ピン留めでないものを落とす
            var trimmed = items
            var i = trimmed.count - 1
            while trimmed.count > 100 && i >= 0 {
                if !trimmed[i].pinned {
                    trimmed.remove(at: i)
                }
                i -= 1
            }
            items = trimmed
        }
        saveClipItems(items)
        return items
    }

    static func removeClipItem(id: UUID) {
        var items = loadClipItems()
        items.removeAll { $0.id == id }
        saveClipItems(items)
    }

    static func togglePinClipItem(id: UUID) {
        var items = loadClipItems()
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].pinned.toggle()
        }
        saveClipItems(items)
    }

    static func clearUnpinnedClipItems() {
        saveClipItems(loadClipItems().filter { $0.pinned })
    }

    // MARK: - 変換の学習（読み → 最後に選んだ候補）

    private static let keyLearned = "rb_learnedConversions_v1"

    static func loadLearnedConversions() -> [String: String] {
        guard let data = defaults.data(forKey: keyLearned),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return map
    }

    // MARK: - 学習（選択した変換を覚える）

    private static let keyLearnedWords = "rb_learnedWords_v1"

    /// 学習の保存データそのもの（変更検知用）
    static func learnedWordsRawData() -> Data? {
        defaults.data(forKey: keyLearnedWords)
    }

    /// 学習一覧。よく選ぶ順（回数→新しい順）で返す
    static func loadLearnedWords() -> [LearnedWord] {
        guard let data = defaults.data(forKey: keyLearnedWords),
              let items = try? JSONDecoder().decode([LearnedWord].self, from: data) else {
            return []
        }
        return items.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.lastUsed > $1.lastUsed
        }
    }

    static func saveLearnedWords(_ items: [LearnedWord]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: keyLearnedWords)
        }
    }

    /// 変換が確定したときに呼ぶ。同じ読み→表記の組は回数を増やす（上限2000件）。
    /// weight は信号の強さ：候補を自分で選んだときは大きく、
    /// 全確定でそのまま通したときは小さくする（直す意思を優先するため）。
    static func recordLearned(reading: String, word: String, weight: Int = 1) {
        guard !reading.isEmpty, !word.isEmpty else { return }
        var items = loadLearnedWords()
        if let i = items.firstIndex(where: { $0.reading == reading && $0.word == word }) {
            items[i].count += weight
            items[i].lastUsed = Date()
        } else {
            var w = LearnedWord(reading: reading, word: word)
            w.count = weight
            items.append(w)
        }
        items.sort {
            $0.count != $1.count ? $0.count > $1.count : $0.lastUsed > $1.lastUsed
        }
        if items.count > 2000 { items = Array(items.prefix(2000)) }
        saveLearnedWords(items)
    }

    static func clearLearnedWords() {
        defaults.removeObject(forKey: keyLearnedWords)
    }

    // MARK: - ユーザー辞書

    private static let keyUserDict = "rb_userDictionary_v1"

    /// ユーザー辞書の保存データそのもの（変更検知用）
    static func userDictRawData() -> Data? {
        defaults.data(forKey: keyUserDict)
    }

    static func loadUserDict() -> [UserDictEntry] {
        guard let data = defaults.data(forKey: keyUserDict),
              let items = try? JSONDecoder().decode([UserDictEntry].self, from: data) else {
            return []
        }
        return items
    }

    static func saveUserDict(_ items: [UserDictEntry]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: keyUserDict)
        }
    }

    @discardableResult
    static func addUserDictEntry(reading rawReading: String, word rawWord: String,
                                 partOfSpeech: UserDictPartOfSpeech) -> [UserDictEntry] {
        let reading = rawReading.hiraganaNormalized()
        let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reading.isEmpty, !word.isEmpty else { return loadUserDict() }
        var items = loadUserDict()
        items.removeAll { $0.reading == reading && $0.word == word }
        items.insert(UserDictEntry(reading: reading, word: word, partOfSpeech: partOfSpeech), at: 0)
        saveUserDict(items)
        return items
    }

    static func removeUserDictEntry(id: UUID) {
        saveUserDict(loadUserDict().filter { $0.id != id })
    }

    static func recordLearnedConversion(reading: String, chosen: String) {
        guard !reading.isEmpty, reading != chosen else { return }
        var map = loadLearnedConversions()
        map[reading] = chosen
        if map.count > 500 {
            // 古いものから間引く（順序は保証しないが上限だけ守る）
            for key in Array(map.keys).prefix(map.count - 500) {
                map.removeValue(forKey: key)
            }
        }
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: keyLearned)
        }
    }
}

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
enum NumberStyle: String, CaseIterable, Identifiable {
    case qwerty   // 数字・記号をQWERTY風の横並びで出す
    case tenkey   // テンキー（電話パッド風 3×4）で出す
    var id: String { rawValue }
    var label: String {
        switch self {
        case .qwerty: return "QWERTY数字"
        case .tenkey: return "テンキー"
        }
    }
}

/// 本体アプリとキーボード拡張で共有する保存領域。
/// App Group が使える環境では共有スイートを使い、使えない環境
/// （LiveContainer 等でグループ権限が落ちる場合）では標準領域にフォールバックする。
/// その場合でもキーボード単体での履歴保存・挿入はそのまま動く。
enum SharedStore {
    static let appGroupID = "group.com.aqua5624.RinhaBoard"

    static var defaults: UserDefaults {
        if let suite = UserDefaults(suiteName: appGroupID) {
            return suite
        }
        return UserDefaults.standard
    }

    private static let keyClipItems = "rb_clipItems_v1"
    private static let keyNumberStyle = "rb_numberStyle"
    private static let keyAutoCapture = "rb_autoCaptureClipboard"
    private static let keyShowNumberRow = "rb_showNumberRow"
    private static let keyLastChangeCount = "rb_lastPasteboardChangeCount"
    private static let keyInputLangKana = "rb_inputLangKana"
    private static let keyZenzaiEnabled = "rb_zenzaiEnabled"

    // MARK: - 設定

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
    static var zenzaiEnabled: Bool {
        get {
            if defaults.object(forKey: keyZenzaiEnabled) == nil { return true }
            return defaults.bool(forKey: keyZenzaiEnabled)
        }
        set { defaults.set(newValue, forKey: keyZenzaiEnabled) }
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

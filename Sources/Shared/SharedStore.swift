import Foundation

/// クリップボード履歴の1件
struct ClipItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var pinned: Bool = false
    var createdAt: Date = Date()
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

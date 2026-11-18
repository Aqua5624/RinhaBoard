import SwiftUI
import UIKit

struct ContentView: View {
    @State private var numberStyle: NumberStyle = SharedStore.numberStyle
    @State private var autoCapture: Bool = SharedStore.autoCaptureClipboard
    @State private var showNumberRow: Bool = SharedStore.showNumberRow
    @State private var zenzaiEnabled: Bool = SharedStore.zenzaiEnabled
    @State private var autoConvert: Bool = SharedStore.autoConvertEnabled
    @State private var clipItems: [ClipItem] = SharedStore.loadClipItems()
    @State private var newClipText: String = ""
    @State private var userDict: [UserDictEntry] = SharedStore.loadUserDict()
    @State private var learnedCount: Int = SharedStore.loadLearnedWords().count
    @State private var newReading: String = ""
    @State private var newWord: String = ""
    @State private var newPOS: UserDictPartOfSpeech = .proper

    var body: some View {
        NavigationView {
            List {
                headerSection
                setupSection
                keyboardSettingsSection
                userDictSection
                clipboardSection
                notesSection
            }
            .navigationTitle("Sparkle Key")
            .onAppear { reload() }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - セクション

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Gboard風の自作キーボード")
                    .font(.headline)
                Text("QWERTY配列、地球儀キーで他のキーボードへ切替、数字は「QWERTY数字／テンキー」の2種類、クリップボード履歴つき。ツールバーの「あ」ボタンでローマ字入力＋かな漢字変換もできます。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var setupSection: some View {
        Section(header: Text("有効化の手順")) {
            VStack(alignment: .leading, spacing: 8) {
                step(1, "下のボタンから設定アプリを開く")
                step(2, "一般 → キーボード → キーボード → 新しいキーボードを追加 → Sparkle Key")
                step(3, "追加した Sparkle Key を開いて「フルアクセスを許可」をON（クリップボード履歴に必要）")
                step(4, "どのアプリでも、キーボードの地球儀キーを押せば Sparkle Key に切り替わります")
            }
            .font(.subheadline)
            Button("設定アプリを開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n).")
                .fontWeight(.semibold)
            Text(text)
        }
    }

    private var keyboardSettingsSection: some View {
        Section(header: Text("キーボード設定"),
                footer: Text("設定はキーボード側にも即反映されます。数字の並び方は、キーボードのツールバーからも切り替えられます。")) {
            Picker("「123」の数字の並び", selection: $numberStyle) {
                ForEach(NumberStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: numberStyle) { _, newValue in
                SharedStore.numberStyle = newValue
            }

            Toggle("AI変換（Zenzai）を使う", isOn: $zenzaiEnabled)
                .onChange(of: zenzaiEnabled) { _, newValue in
                    SharedStore.zenzaiEnabled = newValue
                }
            Toggle("自動変換（確定で残りをまとめて変換）", isOn: $autoConvert)
                .onChange(of: autoConvert) { _, newValue in
                    SharedStore.autoConvertEnabled = newValue
                }
            Toggle("数字行を常に表示（英字の上）", isOn: $showNumberRow)
                .onChange(of: showNumberRow) { _, newValue in
                    SharedStore.showNumberRow = newValue
                }

            Toggle("クリップボードを自動で保存", isOn: $autoCapture)
                .onChange(of: autoCapture) { _, newValue in
                    SharedStore.autoCaptureClipboard = newValue
                }

            HStack {
                Text("学習した変換")
                Spacer()
                Text("\(learnedCount)件")
                    .foregroundStyle(.secondary)
            }
            if learnedCount > 0 {
                Button("学習をリセット", role: .destructive) {
                    SharedStore.clearLearnedWords()
                    learnedCount = 0
                }
            }
        }
    }

    private var userDictSection: some View {
        Section(header: Text("ユーザー辞書 (\(userDict.count)件)"),
                footer: Text("登録した単語は、キーボードの変換候補の先頭に出ます。人名や固有名詞、よく使う言い回しの登録にどうぞ。読みはひらがなで入力してください（カタカナでも自動でひらがなになります）。")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("読み")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .leading)
                    TextField("れもん", text: $newReading)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("単語")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .leading)
                    TextField("🍋", text: $newWord)
                        .textFieldStyle(.roundedBorder)
                }
                Picker("品詞", selection: $newPOS) {
                    ForEach(UserDictPartOfSpeech.allCases) { pos in
                        Text(pos.label).tag(pos)
                    }
                }
                .pickerStyle(.segmented)
                Button("登録する") {
                    let reading = newReading.hiraganaNormalized()
                    let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !reading.isEmpty, !word.isEmpty else { return }
                    SharedStore.addUserDictEntry(reading: reading, word: word, partOfSpeech: newPOS)
                    newReading = ""
                    newWord = ""
                    reload()
                }
                .disabled(newReading.trimmingCharacters(in: .whitespaces).isEmpty
                          || newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.vertical, 4)
            if userDict.isEmpty {
                Text("まだ登録がありません")
                    .foregroundColor(.secondary)
            }
            ForEach(userDict) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.word)
                        Text("\(entry.reading) ・ \(entry.partOfSpeech.label)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        SharedStore.removeUserDictEntry(id: entry.id)
                        reload()
                    } label: { Label("削除", systemImage: "trash") }
                }
            }
        }
    }

    private var clipboardSection: some View {
        Section(header: Text("クリップボード履歴 (\(clipItems.count)件)"),
                footer: Text("キーボードを開いたタイミングで、今のクリップボードが自動保存されます（フルアクセス許可時）。タップでコピー、左スワイプで削除。📌はピン留め（「ピン以外を消す」でも残ります）。")) {
            HStack {
                TextField("手動で追加するテキスト", text: $newClipText)
                Button("追加") {
                    guard !newClipText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    SharedStore.addClipItem(text: newClipText)
                    newClipText = ""
                    reload()
                }
                .disabled(newClipText.isEmpty)
            }
            Button("今のクリップボードを保存") {
                if let s = UIPasteboard.general.string {
                    SharedStore.addClipItem(text: s)
                    reload()
                }
            }
            if clipItems.isEmpty {
                Text("まだ何も保存されていません")
                    .foregroundColor(.secondary)
            }
            ForEach(clipItems) { item in
                Button {
                    UIPasteboard.general.string = item.text
                } label: {
                    HStack {
                        if item.pinned {
                            Text("📌")
                        }
                        Text(item.text)
                            .lineLimit(2)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        SharedStore.removeClipItem(id: item.id)
                        reload()
                    } label: { Label("削除", systemImage: "trash") }
                    Button {
                        SharedStore.togglePinClipItem(id: item.id)
                        reload()
                    } label: { Label(item.pinned ? "ピン解除" : "ピン留め", systemImage: "pin") }
                    .tint(.orange)
                }
            }
            if !clipItems.isEmpty {
                Button("ピン留め以外を全部消す", role: .destructive) {
                    SharedStore.clearUnpinnedClipItems()
                    reload()
                }
            }
        }
    }

    private var notesSection: some View {
        Section(header: Text("仕様メモ")) {
            Text("・ 地球儀キーはタップで次のキーボード、長押しでキーボード一覧が出ます（iOS標準の動き）。")
            Text("・ パスワード入力欄などでは、iOSの仕様で自動的に標準キーボードに切り替わります。")
            Text("・ かな漢字変換は azooKey の変換エンジン（AzooKeyKanaKanjiConverter）です。文全体をまとめて変換でき、選んだ候補は学習されます。スペースで先頭候補を確定、候補をタップで選択、✓確定で文全体を変換しながら確定します。")
            Text("・ バージョン 0.3.0")
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        .font(.subheadline)
    }

    private func reload() {
        numberStyle = SharedStore.numberStyle
        autoCapture = SharedStore.autoCaptureClipboard
        showNumberRow = SharedStore.showNumberRow
        zenzaiEnabled = SharedStore.zenzaiEnabled
        autoConvert = SharedStore.autoConvertEnabled
        clipItems = SharedStore.loadClipItems()
        userDict = SharedStore.loadUserDict()
        learnedCount = SharedStore.loadLearnedWords().count
    }
}

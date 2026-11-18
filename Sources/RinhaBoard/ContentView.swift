import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Sparkle Key 本体アプリ（設定画面）
/// キーボードと同じ Material You 風デザイン: 水色グレーの地に白カード、青アクセント
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
    @State private var accentIndex: Int = SharedStore.accentIndex
    @State private var heightScale: Double = SharedStore.keyboardHeightScale
    @State private var oneHanded: Int = SharedStore.oneHandedMode
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var importMessage: String?

    // MARK: - パレット

    private var boardColor: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.075, green: 0.075, blue: 0.078, alpha: 1)
                : UIColor(red: 0.914, green: 0.933, blue: 0.965, alpha: 1)
        })
    }

    private var cardColor: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
                : .white
        })
    }

    private var fieldColor: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.19, green: 0.19, blue: 0.21, alpha: 1)
                : UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1)
        })
    }

    static let accentColors: [Color] = [
        Color(red: 0.043, green: 0.341, blue: 0.816), // 青 #0B57D0
        Color(red: 0.48, green: 0.35, blue: 0.90),    // 紫
        Color(red: 0.85, green: 0.10, blue: 0.38),    // ピンク
        Color(red: 0.00, green: 0.47, blue: 0.42),    // 緑
        Color(red: 0.31, green: 0.35, blue: 0.40),    // グレー
    ]
    static let accentNames = ["青", "紫", "ピンク", "緑", "グレー"]

    private var accent: Color {
        Self.accentColors[min(max(accentIndex, 0), Self.accentColors.count - 1)]
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    setupCard
                    keyboardCard
                    userDictCard
                    dataCard
                    clipboardCard
                    notesCard
                    Text("Sparkle Key バージョン \(appVersion)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                }
                .padding(16)
            }
            .background(boardColor.ignoresSafeArea())
            .navigationTitle("Sparkle Key")
            .onAppear { reload() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 共通部品

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    private func iconChip(_ systemName: String, _ tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func toggleRow(icon: String, tint: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            iconChip(icon, tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(accent)
        }
    }

    private func pillButton(title: String, filled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(filled ? accent : fieldColor)
                .foregroundColor(filled ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - ヘッダー

    private var headerCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.55, green: 0.36, blue: 0.96),
                             Color(red: 0.85, green: 0.30, blue: 0.75)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 56, height: 56)
                .overlay(
                    Text("✦")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("Sparkle Key")
                    .font(.title3.weight(.bold))
                Text("Gboard風の自作キーボード。QWERTYローマ字入力とフリック入力、azooKey＋Zenzai の変換、クリップボード履歴つき。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    // MARK: - 有効化の手順

    private var setupCard: some View {
        card(title: "有効化の手順") {
            stepRow(1, "下のボタンから設定アプリを開く")
            stepRow(2, "一般 → キーボード → キーボード → 新しいキーボードを追加 → Sparkle Key")
            stepRow(3, "追加した Sparkle Key を開いて「フルアクセスを許可」をON（クリップボード履歴に必要）")
            stepRow(4, "どのアプリでも、キーボードの地球儀キーを押せば Sparkle Key に切り替わります")
            HStack {
                Spacer()
                pillButton(title: "設定アプリを開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    private func stepRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.footnote.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(accent)
                .clipShape(Circle())
            Text(text)
                .font(.body)
            Spacer()
        }
    }

    // MARK: - キーボード設定

    private var keyboardCard: some View {
        card(title: "キーボード設定") {
            HStack(spacing: 12) {
                iconChip("paintpalette.fill", accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("テーマ色")
                    Text("確定キーやボタンの色です（今は\(Self.accentNames[min(max(accentIndex, 0), 4)])）")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: 12) {
                ForEach(0..<Self.accentColors.count, id: \.self) { i in
                    Button {
                        accentIndex = i
                        SharedStore.accentIndex = i
                    } label: {
                        Circle()
                            .fill(Self.accentColors[i])
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .opacity(accentIndex == i ? 1 : 0))
                            .overlay(
                                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            Divider()
            HStack(spacing: 12) {
                iconChip("arrow.up.and.down", Color(red: 0.35, green: 0.5, blue: 0.9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("キーボードの高さ")
                    Text("今は \(Int(heightScale * 100))% です")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            Slider(value: $heightScale, in: 0.85...1.15, step: 0.05)
                .tint(accent)
                .onChange(of: heightScale) { _, newValue in
                    SharedStore.keyboardHeightScale = newValue
                }
            Divider()
            HStack(spacing: 12) {
                iconChip("sidebar.right", Color(red: 0.5, green: 0.4, blue: 0.85))
                VStack(alignment: .leading, spacing: 2) {
                    Text("片手モード")
                    Text("キーボードを左右どちらかに寄せます。キーボード上のボタンでも切り替えできます")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Button {
                        oneHanded = i
                    } label: {
                        Text(["オフ", "右寄せ", "左寄せ"][i])
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(oneHanded == i ? cardColor : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(fieldColor)
            .clipShape(Capsule())
            .onChange(of: oneHanded) { _, newValue in
                SharedStore.oneHandedMode = newValue
            }
            Divider()
            HStack(spacing: 12) {
                iconChip("123.rectangle", Color(red: 0.85, green: 0.45, blue: 0.1))
                VStack(alignment: .leading, spacing: 2) {
                    Text("「123」の並び")
                    Text("テンキーは数字パッド、フリックは12キー入力です")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: 4) {
                ForEach(NumberStyle.allCases) { style in
                    Button {
                        numberStyle = style
                    } label: {
                        Text(style.label)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(numberStyle == style ? cardColor : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(fieldColor)
            .clipShape(Capsule())
            .onChange(of: numberStyle) { _, newValue in
                SharedStore.numberStyle = newValue
            }

            Divider()
            toggleRow(icon: "sparkles", tint: Color(red: 0.55, green: 0.36, blue: 0.96),
                      title: "AI変換（Zenzai）を使う",
                      subtitle: "ニューラル変換で文脈に合った候補を出します",
                      isOn: $zenzaiEnabled)
                .onChange(of: zenzaiEnabled) { _, newValue in
                    SharedStore.zenzaiEnabled = newValue
                }
            Divider()
            toggleRow(icon: "text.badge.checkmark", tint: Color(red: 0.1, green: 0.55, blue: 0.35),
                      title: "自動変換",
                      subtitle: "確定キーで入力中の残りをまとめて変換します。OFFだとかなのまま確定",
                      isOn: $autoConvert)
                .onChange(of: autoConvert) { _, newValue in
                    SharedStore.autoConvertEnabled = newValue
                }
            Divider()
            toggleRow(icon: "rectangle.topthird.inset.filled", tint: Color(red: 0.1, green: 0.45, blue: 0.85),
                      title: "数字行を常に表示",
                      subtitle: "英字キーボードの上に数字の行を追加します",
                      isOn: $showNumberRow)
                .onChange(of: showNumberRow) { _, newValue in
                    SharedStore.showNumberRow = newValue
                }
            Divider()
            toggleRow(icon: "doc.on.clipboard", tint: Color(red: 0.85, green: 0.55, blue: 0.1),
                      title: "クリップボードを自動で保存",
                      subtitle: "キーボードを開くたびに今のクリップボードを履歴へ",
                      isOn: $autoCapture)
                .onChange(of: autoCapture) { _, newValue in
                    SharedStore.autoCaptureClipboard = newValue
                }
            Divider()
            HStack(spacing: 12) {
                iconChip("brain", Color(red: 0.8, green: 0.3, blue: 0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text("学習した変換")
                    Text("選んだ候補を覚えて、次から候補の先頭に出します")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(learnedCount)件")
                    .foregroundColor(.secondary)
            }
            if learnedCount > 0 {
                HStack {
                    Spacer()
                    pillButton(title: "学習をリセット", filled: false) {
                        SharedStore.clearLearnedWords()
                        learnedCount = 0
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - ユーザー辞書

    private var userDictCard: some View {
        card(title: "ユーザー辞書（\(userDict.count)件）") {
            Text("登録した単語は変換候補の先頭に出ます。読みはひらがなで入力してください（カタカナでも自動でひらがなになります）。")
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("読み").font(.footnote).foregroundColor(.secondary)
                    TextField("れもん", text: $newReading)
                        .padding(10)
                        .background(fieldColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("単語").font(.footnote).foregroundColor(.secondary)
                    TextField("🍋", text: $newWord)
                        .padding(10)
                        .background(fieldColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            HStack(spacing: 4) {
                ForEach(UserDictPartOfSpeech.allCases) { pos in
                    Button {
                        newPOS = pos
                    } label: {
                        Text(pos.label)
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(newPOS == pos ? cardColor : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(fieldColor)
            .clipShape(Capsule())
            HStack {
                Spacer()
                pillButton(title: "登録する") {
                    let reading = newReading.hiraganaNormalized()
                    let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !reading.isEmpty, !word.isEmpty else { return }
                    SharedStore.addUserDictEntry(reading: reading, word: word, partOfSpeech: newPOS)
                    newReading = ""
                    newWord = ""
                    reload()
                }
                .opacity(newReading.trimmingCharacters(in: .whitespaces).isEmpty
                         || newWord.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .disabled(newReading.trimmingCharacters(in: .whitespaces).isEmpty
                          || newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if userDict.isEmpty {
                Text("まだ登録がありません")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ForEach(userDict) { entry in
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.word)
                        Text("\(entry.reading) ・ \(entry.partOfSpeech.label)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        SharedStore.removeUserDictEntry(id: entry.id)
                        reload()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - データの書き出し・読み込み

    private struct Backup: Codable {
        var userDictionary: [UserDictEntry]
        var learnedWords: [LearnedWord]
    }

    private var dataCard: some View {
        card(title: "データの書き出し・読み込み") {
            Text("ユーザー辞書と学習した変換を JSON ファイルに書き出せます。機種変更や入れ直しのときに読み込めば元に戻せます。読み込むと今の辞書と学習は上書きされます。")
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Text("書き出す")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(accent)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                pillButton(title: "読み込む", filled: false) {
                    showImporter = true
                }
                Spacer()
            }
            if let importMessage {
                Text(importMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func makeExport() {
        let backup = Backup(userDictionary: SharedStore.loadUserDict(),
                            learnedWords: SharedStore.loadLearnedWords())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(backup) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("sparklekey-backup.json")
            if (try? data.write(to: url)) != nil {
                exportURL = url
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url),
           let backup = try? JSONDecoder().decode(Backup.self, from: data) {
            SharedStore.saveUserDict(backup.userDictionary)
            SharedStore.saveLearnedWords(backup.learnedWords)
            reload()
            importMessage = "読み込みました（辞書 \(backup.userDictionary.count)件・学習 \(backup.learnedWords.count)件）"
        } else {
            importMessage = "読み込めませんでした。Sparkle Key の書き出しファイルを選んでください"
        }
    }

    // MARK: - クリップボード

    private var clipboardCard: some View {
        card(title: "クリップボード履歴（\(clipItems.count)件）") {
            Text("キーボードを開いたタイミングで自動保存されます（フルアクセス許可時）。タップでコピーできます。")
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField("手動で追加するテキスト", text: $newClipText)
                    .padding(10)
                    .background(fieldColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                pillButton(title: "追加") {
                    guard !newClipText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    SharedStore.addClipItem(text: newClipText)
                    newClipText = ""
                    reload()
                }
                .opacity(newClipText.isEmpty ? 0.4 : 1)
                .disabled(newClipText.isEmpty)
            }
            HStack {
                pillButton(title: "今のクリップボードを保存", filled: false) {
                    if let s = UIPasteboard.general.string {
                        SharedStore.addClipItem(text: s)
                        reload()
                    }
                }
                Spacer()
            }
            if clipItems.isEmpty {
                Text("まだ何も保存されていません")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ForEach(clipItems) { item in
                Divider()
                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = item.text
                    } label: {
                        HStack(spacing: 6) {
                            if item.pinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            Text(item.text)
                                .lineLimit(2)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    Button {
                        SharedStore.togglePinClipItem(id: item.id)
                        reload()
                    } label: {
                        Image(systemName: item.pinned ? "pin.slash" : "pin")
                            .foregroundColor(.orange)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    Button {
                        SharedStore.removeClipItem(id: item.id)
                        reload()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !clipItems.isEmpty {
                HStack {
                    Spacer()
                    pillButton(title: "ピン留め以外を全部消す", filled: false) {
                        SharedStore.clearUnpinnedClipItems()
                        reload()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - 仕様メモ

    private var notesCard: some View {
        card(title: "仕様メモ") {
            noteLine("地球儀キーはタップで次のキーボード、長押しでキーボード一覧が出ます（iOS標準の動き）。")
            noteLine("パスワード入力欄などでは、iOSの仕様で自動的に標準キーボードに切り替わります。")
            noteLine("かな漢字変換は azooKey の変換エンジン＋Zenzai です。スペースで先頭候補を確定、候補タップで選択、変換中は確定キーで文全体を変換して確定します。")
            noteLine("フリック入力は「123」の並びで「フリック」を選ぶと使えます。数字は各キーの長押し、濁点・小文字は句読点キーの下フリックです。")
        }
        .font(.subheadline)
    }

    private func noteLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("・").foregroundColor(.secondary)
            Text(text).foregroundColor(.secondary)
            Spacer()
        }
        .font(.subheadline)
    }

    private func reload() {
        accentIndex = SharedStore.accentIndex
        heightScale = SharedStore.keyboardHeightScale
        oneHanded = SharedStore.oneHandedMode
        makeExport()
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

import SwiftUI
import UIKit

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

    private let accent = Color(red: 0.043, green: 0.341, blue: 0.816) // #0B57D0

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    setupCard
                    keyboardCard
                    userDictCard
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
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 共通部品

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
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
                    .font(.caption)
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
                    .font(.caption)
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
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(accent)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    // MARK: - キーボード設定

    private var keyboardCard: some View {
        card(title: "キーボード設定") {
            HStack(spacing: 12) {
                iconChip("123.rectangle", Color(red: 0.85, green: 0.45, blue: 0.1))
                VStack(alignment: .leading, spacing: 2) {
                    Text("「123」の並び")
                    Text("テンキーはフリック入力パッドになります")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: 4) {
                ForEach(NumberStyle.allCases) { style in
                    Button {
                        numberStyle = style
                    } label: {
                        Text(style == .tenkey ? "テンキー（フリック）" : style.label)
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
                        .font(.caption)
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
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("読み").font(.caption).foregroundColor(.secondary)
                    TextField("れもん", text: $newReading)
                        .padding(10)
                        .background(fieldColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("単語").font(.caption).foregroundColor(.secondary)
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
                            .font(.caption.weight(.medium))
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
                            .font(.caption)
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

    // MARK: - クリップボード

    private var clipboardCard: some View {
        card(title: "クリップボード履歴（\(clipItems.count)件）") {
            Text("キーボードを開いたタイミングで自動保存されます（フルアクセス許可時）。タップでコピーできます。")
                .font(.caption)
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
            noteLine("フリック入力は「123 → テンキー」で使えます。数字は各キーの長押し、濁点・小文字は句読点キーの下フリックです。")
        }
        .font(.subheadline)
    }

    private func noteLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("・").foregroundColor(.secondary)
            Text(text).foregroundColor(.secondary)
            Spacer()
        }
        .font(.footnote)
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

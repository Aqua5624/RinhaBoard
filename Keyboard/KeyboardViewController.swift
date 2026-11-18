import UIKit

// MARK: - キーのアクション

enum KeyAction {
    case text(String)
    case shift
    case backspace
    case space
    case returnKey
    case globe
    case langToggle            // EN ⇄ あ（ローマ字かな）
    case showLetters
    case showNumbers
    case showSymbols
    case numberStyleToggle     // 数字モード：QWERTY数字 ⇄ テンキー
    case toggleClipboard
    case saveClipboardNow
    case clearClips
    case insertClip(String)
    case pinClip(UUID)
    case deleteClip(UUID)
    case candidate(Int)        // 変換候補の選択
    case commitComposing       // 入力中を変換した状態で全部確定
    case clearComposing        // 入力中を破棄
}

final class KBButton: UIButton {
    var action: KeyAction?
    /// 押している間の背景色（標準キーボードのような押下フィードバック用）
    var normalBg: UIColor?
    var pressedBg: UIColor?
    override var isHighlighted: Bool {
        didSet {
            guard let normalBg = normalBg, let pressedBg = pressedBg else { return }
            backgroundColor = isHighlighted ? pressedBg : normalBg
        }
    }
}

enum KBMode {
    case letters, numbers, symbols, clipboard
}

enum InputLang {
    case en, kana
}

enum ShiftState {
    case off, once, locked
}

// MARK: - 本体

final class KeyboardViewController: UIInputViewController {

    private var mode: KBMode = .letters
    private var lang: InputLang = SharedStore.inputLangIsKana ? .kana : .en
    private var shiftState: ShiftState = .off
    /// かなモードで変換確定前のローマ字の残り（例 "sh"）
    private var pendingRomaji: String = ""
    /// かなモードで変換確定前のかな（例 "きょうは"）。文書にはまだ入っていない
    private var composingKana: String = ""
    private var currentCandidates: [ConversionCandidate] = []
    private var lastShiftTapAt: Date?

    private let toolbar = UIStackView()
    private let toolbarLabel = UILabel()
    private var toolbarButtons: [KBButton] = []
    private let contentStack = UIStackView()
    private let stripScroll = UIScrollView()
    private let stripStack = UIStackView()
    private var stripHeightConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    private var backspaceTimer: Timer?
    private let feedback = UIImpactFeedbackGenerator(style: .light)
    private var lastStripSignature: String?

    // MARK: ライフサイクル

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
                : UIColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1)
        }

        let root = UIStackView()
        root.axis = .vertical
        root.spacing = 6
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])

        // 変換候補バー（かな入力中だけ出す）
        stripScroll.showsHorizontalScrollIndicator = false
        stripStack.axis = .horizontal
        stripStack.spacing = 6
        stripStack.alignment = .fill
        stripStack.translatesAutoresizingMaskIntoConstraints = false
        stripScroll.addSubview(stripStack)
        NSLayoutConstraint.activate([
            stripStack.leadingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.leadingAnchor),
            stripStack.trailingAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.trailingAnchor),
            stripStack.topAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.topAnchor),
            stripStack.bottomAnchor.constraint(equalTo: stripScroll.contentLayoutGuide.bottomAnchor),
            stripStack.heightAnchor.constraint(equalTo: stripScroll.frameLayoutGuide.heightAnchor),
        ])
        let sh = stripScroll.heightAnchor.constraint(equalToConstant: 0)
        sh.isActive = true
        stripHeightConstraint = sh
        root.addArrangedSubview(stripScroll)

        // ツールバー（Gboard風の上の帯）
        toolbar.axis = .horizontal
        toolbar.spacing = 6
        toolbar.alignment = .center
        toolbar.heightAnchor.constraint(equalToConstant: 36).isActive = true
        root.addArrangedSubview(toolbar)

        toolbarLabel.font = .systemFont(ofSize: 14)
        toolbarLabel.textColor = .secondaryLabel
        toolbarLabel.textAlignment = .center
        toolbarLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        contentStack.axis = .vertical
        contentStack.spacing = 6
        contentStack.distribution = .fillEqually
        root.addArrangedSubview(contentStack)

        feedback.prepare()
        // 変換エンジンの初期化（辞書読み込み）を表示直後に済ませ、
        // 最初のかな入力で固まらないようにする
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            KanjiConverter.warmUp()
        }

        let h = view.heightAnchor.constraint(equalToConstant: 264)
        h.priority = UILayoutPriority(999)
        h.isActive = true
        heightConstraint = h

        rebuildAll()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captureClipboardIfNeeded()
        if mode == .clipboard { rebuildAll() }
    }

    // MARK: ツールバー

    private func rebuildAll() {
        rebuildToolbar()
        rebuildContent()
        refreshCandidates()
    }

    private func rebuildToolbar() {
        toolbar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        toolbarButtons.removeAll()

        func toolButton(symbol: String?, title: String?, action: KeyAction) -> KBButton {
            let b = KBButton(type: .system)
            if let symbol = symbol, let img = UIImage(systemName: symbol) {
                b.setImage(img, for: .normal)
            }
            if let title = title {
                b.setTitle(title, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            }
            b.tintColor = .label
            b.action = action
            b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            if symbol != nil {
                b.widthAnchor.constraint(equalToConstant: 44).isActive = true
            } else {
                b.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            }
            b.heightAnchor.constraint(equalToConstant: 32).isActive = true
            toolbarButtons.append(b)
            return b
        }

        toolbar.addArrangedSubview(toolButton(
            symbol: mode == .clipboard ? "keyboard" : "doc.on.clipboard",
            title: nil,
            action: .toggleClipboard))

        if mode == .letters {
            toolbar.addArrangedSubview(toolButton(
                symbol: nil,
                title: lang == .en ? "あ" : "EN",
                action: .langToggle))
        } else if mode == .numbers {
            toolbar.addArrangedSubview(toolButton(
                symbol: nil,
                title: SharedStore.numberStyle == .qwerty ? "テンキー" : "123列",
                action: .numberStyleToggle))
        }

        toolbar.addArrangedSubview(toolbarLabel)
        updateToolbarLabel()

        if mode == .clipboard {
            toolbar.addArrangedSubview(toolButton(
                symbol: "doc.badge.plus", title: nil, action: .saveClipboardNow))
            toolbar.addArrangedSubview(toolButton(
                symbol: "trash", title: nil, action: .clearClips))
        }
    }

    private func updateToolbarLabel() {
        if mode == .clipboard {
            let count = SharedStore.loadClipItems().count
            toolbarLabel.text = hasFullAccess ? "クリップボード \(count)件" : "フルアクセスが必要です"
        } else if lang == .kana && mode == .letters {
            toolbarLabel.text = effectiveComposing().isEmpty ? "ローマ字入力中" : ""
        } else {
            toolbarLabel.text = ""
        }
    }

    private func updateHeight() {
        let base: CGFloat
        switch mode {
        case .letters:
            base = SharedStore.showNumberRow ? 304 : 262
        case .numbers:
            base = SharedStore.numberStyle == .tenkey ? 312 : 262
        case .symbols:
            base = 262
        case .clipboard:
            base = 312
        }
        // かな入力中は候補が空でもバー分の高さを常時確保する。
        // 候補の出入りでキーボードが伸縮するとキーの位置がずれて打ちにくいため。
        let stripReserved = (lang == .kana && mode == .letters)
        let strip: CGFloat = stripReserved ? 42 : 0
        heightConstraint?.constant = base + strip
        stripHeightConstraint?.constant = stripReserved ? 36 : 0
    }

    // MARK: 変換候補バー

    /// 入力中のかな全体（確定済みかな＋ローマ字残りを無理やりかな化したもの）
    private func effectiveComposing() -> String {
        if pendingRomaji.isEmpty { return composingKana }
        return composingKana + RomajiKana.process(pendingRomaji, flush: true).committed
    }

    /// ローマ字残りをかなとして composingKana に取り込む
    private func materializeComposing() {
        guard !pendingRomaji.isEmpty else { return }
        composingKana += RomajiKana.process(pendingRomaji, flush: true).committed
        pendingRomaji = ""
    }

    private func refreshCandidates() {
        let eff = effectiveComposing()
        if lang == .kana && mode == .letters && !eff.isEmpty {
            // 学習は azooKey エンジン側が持つので、候補はそのまま使う
            currentCandidates = KanjiConverter.candidates(for: eff)
        } else {
            currentCandidates = []
        }
        // 候補列が前回と同じなら再構築しない（打鍵ごとのレイアウト暴れ防止）
        let signature = eff + "\u{1}" + currentCandidates.map { $0.text }.joined(separator: "\u{2}")
        if signature != lastStripSignature {
            let wasEmpty = (lastStripSignature == nil) || lastStripSignature!.hasPrefix("\u{1}")
            lastStripSignature = signature
            rebuildStrip()
            if wasEmpty && !eff.isEmpty {
                stripScroll.setContentOffset(.zero, animated: false)
            }
        }
        updateHeight()
        updateToolbarLabel()
    }

    private func rebuildStrip() {
        stripStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !currentCandidates.isEmpty else { return }

        let composingLabel = UILabel()
        composingLabel.text = effectiveComposing()
        composingLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        composingLabel.textColor = .secondaryLabel
        stripStack.addArrangedSubview(composingLabel)

        for (i, cand) in currentCandidates.enumerated() {
            let b = KBButton(type: .system)
            b.setTitle(cand.text, for: .normal)
            b.setTitleColor(.label, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 16)
            b.backgroundColor = normalKeyColor()
            b.layer.cornerRadius = 6
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            b.action = .candidate(i)
            b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            stripStack.addArrangedSubview(b)
        }

        let commit = KBButton(type: .system)
        commit.setTitle("✓確定", for: .normal)
        commit.setTitleColor(.systemBlue, for: .normal)
        commit.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        commit.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        commit.action = .commitComposing
        commit.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        stripStack.addArrangedSubview(commit)

        let clear = KBButton(type: .system)
        clear.setTitle("✕", for: .normal)
        clear.setTitleColor(.secondaryLabel, for: .normal)
        clear.titleLabel?.font = .systemFont(ofSize: 14)
        clear.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        clear.action = .clearComposing
        clear.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        stripStack.addArrangedSubview(clear)

    }

    /// 候補を1つ確定する：文書へ挿入し、消費した分だけ入力中から引く。
    /// 表示中の候補列（currentCandidates）をそのまま使う（表示と確定の不一致を避ける）。
    private func commitCandidate(at index: Int) {
        materializeComposing()
        let ordered = currentCandidates.isEmpty
            ? KanjiConverter.candidates(for: composingKana)
            : currentCandidates
        guard ordered.indices.contains(index) else { return }
        let cand = ordered[index]
        textDocumentProxy.insertText(cand.text)
        // azooKey エンジン側の学習へ通知（ユーザ辞書・自前候補は対象外）
        KanjiConverter.notifySelected(cand)
        composingKana = String(composingKana.dropFirst(cand.consumed))
        refreshCandidates()
    }

    /// 入力中を「先頭候補で変換しながら」全部確定する
    private func commitConvertedAll() {
        materializeComposing()
        var guardCount = 0
        while !composingKana.isEmpty && guardCount < 64 {
            guardCount += 1
            let before = composingKana
            commitCandidate(at: 0)
            if composingKana == before { break }
        }
        refreshCandidates()
    }

    /// 入力中をかなのまま全部確定する
    private func commitRawAll() {
        materializeComposing()
        if !composingKana.isEmpty {
            textDocumentProxy.insertText(composingKana)
            composingKana = ""
        }
        refreshCandidates()
    }

    private var hasComposing: Bool {
        !composingKana.isEmpty || !pendingRomaji.isEmpty
    }

    // MARK: 本体レイアウト

    private struct Spec {
        let label: String
        let action: KeyAction
        var weight: CGFloat = 1
        var symbol: String? = nil
        var small: Bool = false
        init(_ label: String, _ action: KeyAction, weight: CGFloat = 1, symbol: String? = nil, small: Bool = false) {
            self.label = label
            self.action = action
            self.weight = weight
            self.symbol = symbol
            self.small = small
        }
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        contentStack.distribution = (mode == .clipboard) ? .fill : .fillEqually
        switch mode {
        case .letters: buildLetters()
        case .numbers:
            if SharedStore.numberStyle == .tenkey { buildTenkey() } else { buildNumbersQwerty() }
        case .symbols: buildSymbols()
        case .clipboard: buildClipboard()
        }
    }

    private func makeRow(_ specs: [Spec]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fill
        let total = specs.reduce(CGFloat(0)) { $0 + $1.weight }
        for spec in specs {
            let b = makeKey(spec)
            row.addArrangedSubview(b)
            let m = spec.weight / total
            let c = -6 * CGFloat(specs.count - 1) * m
            b.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: m, constant: c).isActive = true
        }
        return row
    }

    private func makeKey(_ spec: Spec) -> KBButton {
        let b = KBButton(type: .system)
        if let symbol = spec.symbol, let img = UIImage(systemName: symbol) {
            b.setImage(img, for: .normal)
            b.tintColor = .label
        } else {
            b.setTitle(spec.label, for: .normal)
            b.setTitleColor(.label, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: spec.small ? 15 : 21)
            if case .text = spec.action {
                b.titleLabel?.font = .systemFont(ofSize: spec.small ? 16 : 23)
            }
        }
        let isSpecial: Bool
        switch spec.action {
        case .text, .space:
            isSpecial = false
        default:
            isSpecial = true
        }
        if case .space = spec.action { b.backgroundColor = normalKeyColor() }
        else {
            b.backgroundColor = isSpecial ? specialKeyColor() : normalKeyColor()
        }
        b.normalBg = b.backgroundColor
        b.pressedBg = isSpecial ? pressedSpecialKeyColor() : pressedKeyColor()
        b.layer.cornerRadius = 6
        b.layer.shadowColor = UIColor.black.cgColor
        b.layer.shadowOpacity = 0.25
        b.layer.shadowRadius = 0
        b.layer.shadowOffset = CGSize(width: 0, height: 1)
        b.action = spec.action

        if case .globe = spec.action {
            // 地球儀：タップで次のキーボード、長押しで一覧（iOS標準の仕組み）
            b.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        } else {
            b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        }
        if case .backspace = spec.action {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(backspaceLongPress(_:)))
            lp.minimumPressDuration = 0.45
            b.addGestureRecognizer(lp)
        }
        return b
    }

    private func normalKeyColor() -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.32, green: 0.32, blue: 0.34, alpha: 1)
                : .white
        }
    }

    private func pressedKeyColor() -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1)
                : UIColor(red: 0.72, green: 0.75, blue: 0.80, alpha: 1)
        }
    }

    private func pressedSpecialKeyColor() -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.30, green: 0.30, blue: 0.33, alpha: 1)
                : UIColor(red: 0.55, green: 0.58, blue: 0.64, alpha: 1)
        }
    }

    private func specialKeyColor() -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
                : UIColor(red: 0.66, green: 0.69, blue: 0.74, alpha: 1)
        }
    }

    private func bottomRow(firstLabel: String, firstAction: KeyAction) -> UIStackView {
        makeRow([
            Spec(firstLabel, firstAction, weight: 1.5, small: true),
            Spec("", .globe, weight: 1.0, symbol: "globe"),
            Spec(lang == .kana ? "、" : ",", .text(","), weight: 0.7),
            Spec(" ", .space, weight: 3.6),
            Spec(lang == .kana ? "。" : ".", .text("."), weight: 0.7),
            Spec(returnLabel(), .returnKey, weight: 1.6, small: true),
        ])
    }

    private func returnLabel() -> String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .search: return "検索"
        case .send: return "送信"
        case .done: return "完了"
        case .go, .next: return "次へ"
        default: return "⏎"
        }
    }

    // MARK: 各モード

    private func buildLetters() {
        if SharedStore.showNumberRow {
            contentStack.addArrangedSubview(makeRow(
                "1234567890".map { Spec(String($0), .text(String($0)), small: true) }))
        }
        let upper = shiftState != .off
        func letterRow(_ s: String) -> UIStackView {
            makeRow(s.map { ch in
                let label = upper ? String(ch).uppercased() : String(ch)
                return Spec(label, .text(String(ch)))
            })
        }
        contentStack.addArrangedSubview(letterRow("qwertyuiop"))
        contentStack.addArrangedSubview(letterRow("asdfghjkl"))
        var third: [Spec] = [Spec("", .shift, weight: 1.4, symbol: shiftState == .off ? "shift" : (shiftState == .locked ? "capslock.fill" : "shift.fill"))]
        third += "zxcvbnm".map { Spec(upper ? String($0).uppercased() : String($0), .text(String($0))) }
        third.append(Spec("", .backspace, weight: 1.4, symbol: "delete.left"))
        contentStack.addArrangedSubview(makeRow(third))
        contentStack.addArrangedSubview(bottomRow(firstLabel: "123", firstAction: .showNumbers))
    }

    private func buildNumbersQwerty() {
        contentStack.addArrangedSubview(makeRow(
            "1234567890".map { Spec(String($0), .text(String($0))) }))
        contentStack.addArrangedSubview(makeRow(
            ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map { Spec($0, .text($0)) }))
        var third: [Spec] = [Spec("#+=", .showSymbols, weight: 1.4, small: true)]
        third += [".", ",", "?", "!", "'"].map { Spec($0, .text($0)) }
        third.append(Spec("", .backspace, weight: 1.4, symbol: "delete.left"))
        contentStack.addArrangedSubview(makeRow(third))
        contentStack.addArrangedSubview(bottomRow(firstLabel: "ABC", firstAction: .showLetters))
    }

    private func buildTenkey() {
        contentStack.addArrangedSubview(makeRow([
            Spec("1", .text("1")), Spec("2", .text("2")), Spec("3", .text("3")),
            Spec("", .backspace, symbol: "delete.left"),
        ]))
        contentStack.addArrangedSubview(makeRow([
            Spec("4", .text("4")), Spec("5", .text("5")), Spec("6", .text("6")),
            Spec("+", .text("+")),
        ]))
        contentStack.addArrangedSubview(makeRow([
            Spec("7", .text("7")), Spec("8", .text("8")), Spec("9", .text("9")),
            Spec("-", .text("-")),
        ]))
        contentStack.addArrangedSubview(makeRow([
            Spec("#+=", .showSymbols, small: true),
            Spec(",", .text(",")),
            Spec("0", .text("0")),
            Spec(".", .text(".")),
        ]))
        contentStack.addArrangedSubview(makeRow([
            Spec("ABC", .showLetters, weight: 1.5, small: true),
            Spec("", .globe, weight: 1.0, symbol: "globe"),
            Spec(" ", .space, weight: 3.6),
            Spec(returnLabel(), .returnKey, weight: 1.6, small: true),
        ]))
    }

    private func buildSymbols() {
        contentStack.addArrangedSubview(makeRow(
            ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { Spec($0, .text($0)) }))
        contentStack.addArrangedSubview(makeRow(
            ["_", "\\", "|", "~", "<", ">", "¥", "€", "£", "•"].map { Spec($0, .text($0)) }))
        var third: [Spec] = [Spec("123", .showNumbers, weight: 1.4, small: true)]
        third += [".", ",", "?", "!", "'"].map { Spec($0, .text($0)) }
        third.append(Spec("", .backspace, weight: 1.4, symbol: "delete.left"))
        contentStack.addArrangedSubview(makeRow(third))
        contentStack.addArrangedSubview(bottomRow(firstLabel: "ABC", firstAction: .showLetters))
    }

    private func buildClipboard() {
        if !hasFullAccess {
            let label = UILabel()
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 14)
            label.textColor = .secondaryLabel
            label.text = "クリップボード履歴を使うには「フルアクセスを許可」が必要です。\n設定アプリ → 一般 → キーボード → キーボード → Sparkle Key → フルアクセスを許可"
            contentStack.addArrangedSubview(label)
            let bottom = bottomRow(firstLabel: "ABC", firstAction: .showLetters)
            bottom.heightAnchor.constraint(equalToConstant: 52).isActive = true
            contentStack.addArrangedSubview(bottom)
            return
        }
        let items = SharedStore.loadClipItems()
        if items.isEmpty {
            let label = UILabel()
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 14)
            label.textColor = .secondaryLabel
            label.text = "保存されたテキストはまだありません。\n何かコピーしてからキーボードを開くと自動で保存されます。\n（ツールバーの＋ボタンで今のクリップボードを手動保存もできます）"
            contentStack.addArrangedSubview(label)
        } else {
            let scroll = UIScrollView()
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            ])
            for item in items {
                let row = UIStackView()
                row.axis = .horizontal
                row.spacing = 6
                row.heightAnchor.constraint(equalToConstant: 42).isActive = true

                let insert = KBButton(type: .system)
                insert.setTitle((item.pinned ? "📌 " : "") + item.text.replacingOccurrences(of: "\n", with: " "), for: .normal)
                insert.setTitleColor(.label, for: .normal)
                insert.titleLabel?.font = .systemFont(ofSize: 15)
                insert.titleLabel?.lineBreakMode = .byTruncatingTail
                insert.contentHorizontalAlignment = .left
                insert.backgroundColor = normalKeyColor()
                insert.layer.cornerRadius = 6
                insert.action = .insertClip(item.text)
                insert.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                row.addArrangedSubview(insert)

                let pin = KBButton(type: .system)
                pin.setImage(UIImage(systemName: item.pinned ? "pin.fill" : "pin"), for: .normal)
                pin.tintColor = .label
                pin.backgroundColor = specialKeyColor()
                pin.layer.cornerRadius = 6
                pin.widthAnchor.constraint(equalToConstant: 42).isActive = true
                pin.action = .pinClip(item.id)
                pin.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                row.addArrangedSubview(pin)

                let del = KBButton(type: .system)
                del.setImage(UIImage(systemName: "trash"), for: .normal)
                del.tintColor = .label
                del.backgroundColor = specialKeyColor()
                del.layer.cornerRadius = 6
                del.widthAnchor.constraint(equalToConstant: 42).isActive = true
                del.action = .deleteClip(item.id)
                del.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                row.addArrangedSubview(del)

                stack.addArrangedSubview(row)
            }
            contentStack.addArrangedSubview(scroll)
        }
        let bottom = bottomRow(firstLabel: "ABC", firstAction: .showLetters)
        bottom.heightAnchor.constraint(equalToConstant: 52).isActive = true
        contentStack.addArrangedSubview(bottom)
    }

    // MARK: クリップボード取り込み

    private func captureClipboardIfNeeded() {
        guard hasFullAccess else { return }
        let pb = UIPasteboard.general
        guard pb.changeCount != SharedStore.lastPasteboardChangeCount else { return }
        SharedStore.lastPasteboardChangeCount = pb.changeCount
        guard SharedStore.autoCaptureClipboard else { return }
        if let s = pb.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SharedStore.addClipItem(text: s)
        }
    }

    // MARK: アクション処理

    @objc private func keyTapped(_ sender: KBButton) {
        guard let action = sender.action else { return }
        handle(action)
    }

    private func handle(_ action: KeyAction) {
        switch action {
        case .text(let raw):
            insertTextSmart(raw)
        case .shift:
            let now = Date()
            if let last = lastShiftTapAt, now.timeIntervalSince(last) < 0.35, shiftState == .once {
                shiftState = .locked
            } else {
                shiftState = shiftState == .off ? .once : .off
            }
            lastShiftTapAt = now
            rebuildAll()
        case .backspace:
            deleteBackwardSmart()
        case .space:
            if lang == .kana && mode == .letters && hasComposing {
                // 変換：先頭候補を確定（残りは入力中のまま）
                commitCandidate(at: 0)
            } else {
                textDocumentProxy.insertText(" ")
            }
        case .returnKey:
            if lang == .kana && hasComposing { commitConvertedAll() }
            textDocumentProxy.insertText("\n")
        case .globe:
            advanceToNextInputMode()
        case .langToggle:
            if hasComposing { commitConvertedAll() }
            lang = lang == .en ? .kana : .en
            SharedStore.inputLangIsKana = (lang == .kana)
            rebuildAll()
        case .showLetters:
            if hasComposing { commitConvertedAll() }
            mode = .letters
            rebuildAll()
        case .showNumbers:
            if hasComposing { commitConvertedAll() }
            mode = .numbers
            rebuildAll()
        case .showSymbols:
            if hasComposing { commitConvertedAll() }
            mode = .symbols
            rebuildAll()
        case .numberStyleToggle:
            SharedStore.numberStyle = SharedStore.numberStyle == .qwerty ? .tenkey : .qwerty
            rebuildAll()
        case .toggleClipboard:
            if mode == .clipboard {
                mode = .letters
            } else {
                if hasComposing { commitConvertedAll() }
                captureClipboardIfNeeded()
                mode = .clipboard
            }
            rebuildAll()
        case .saveClipboardNow:
            if hasFullAccess, let s = UIPasteboard.general.string {
                SharedStore.addClipItem(text: s)
                SharedStore.lastPasteboardChangeCount = UIPasteboard.general.changeCount
            }
            rebuildAll()
        case .clearClips:
            SharedStore.clearUnpinnedClipItems()
            rebuildAll()
        case .insertClip(let text):
            if hasComposing { commitConvertedAll() }
            textDocumentProxy.insertText(text)
            mode = .letters
            rebuildAll()
        case .pinClip(let id):
            SharedStore.togglePinClipItem(id: id)
            rebuildAll()
        case .deleteClip(let id):
            SharedStore.removeClipItem(id: id)
            rebuildAll()
        case .candidate(let index):
            commitCandidate(at: index)
        case .commitComposing:
            commitConvertedAll()
        case .clearComposing:
            composingKana = ""
            pendingRomaji = ""
            refreshCandidates()
        }
        tapFeedback()
    }

    private func deleteBackwardSmart() {
        if lang == .kana && mode == .letters && hasComposing {
            if !pendingRomaji.isEmpty {
                pendingRomaji.removeLast()
            } else {
                composingKana.removeLast()
            }
            refreshCandidates()
        } else {
            textDocumentProxy.deleteBackward()
        }
    }

    /// 文字キー：かなモードでは変換バッファへ、英字モードでは Shift を反映して直接挿入
    private func insertTextSmart(_ raw: String) {
        if lang == .kana && mode == .letters {
            if raw == "," {
                commitConvertedAll()
                textDocumentProxy.insertText("、")
                return
            }
            if raw == "." {
                commitConvertedAll()
                textDocumentProxy.insertText("。")
                return
            }
            if raw.count == 1, let ch = raw.first, ch.isLetter, ch.isASCII {
                pendingRomaji += raw.lowercased()
                let result = RomajiKana.process(pendingRomaji, flush: false)
                if !result.committed.isEmpty {
                    composingKana += result.committed
                }
                pendingRomaji = result.pending
                refreshCandidates()
                return
            }
            // 数字行など：入力中を確定してからそのまま挿入
            commitRawAll()
            textDocumentProxy.insertText(raw)
            return
        }
        // 英字モード（および数字・記号モード）
        if hasComposing { commitRawAll() }
        if shiftState != .off, raw.count == 1, raw.first!.isLetter {
            textDocumentProxy.insertText(raw.uppercased())
            if shiftState == .once {
                shiftState = .off
                rebuildAll()
            }
        } else {
            textDocumentProxy.insertText(raw)
        }
    }

    @objc private func backspaceLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            backspaceTimer?.invalidate()
            backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                self?.deleteBackwardSmart()
            }
        case .ended, .cancelled, .failed:
            backspaceTimer?.invalidate()
            backspaceTimer = nil
        default:
            break
        }
    }

    private func tapFeedback() {
        guard hasFullAccess else { return }
        feedback.impactOccurred()
        feedback.prepare()
    }
}

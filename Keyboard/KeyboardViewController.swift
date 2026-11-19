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
    case toggleCursor
    case cursorMove(Int)
    case autoConvertToggle
    case noop
    case copyText
    case cutText
    case pasteText
    case toggleEmoji
    case emojiInsert(String)
    case emojiCategory(Int)
    case englishSuggest(String)
    case oneHandedToggle
    case expandCandidates
    case candidateListClose
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

class KBButton: UIButton {
    var action: KeyAction?
    /// 候補ボタン用：表示した候補そのもの（確定時にリストを引き直さない）
    var candidateValue: ConversionCandidate?
    /// 押している間の背景色（標準キーボードのような押下フィードバック用）
    var normalBg: UIColor?
    var pressedBg: UIColor?
    /// 右上の小さな長押しヒント文字（Gboard 式）
    var subText: String?
    var longPressFired = false
    /// 丸薬型（カプセル）キー
    var isPill = false

    override func layoutSubviews() {
        super.layoutSubviews()
        if isPill { layer.cornerRadius = bounds.height / 2 }
    }
    override var isHighlighted: Bool {
        didSet {
            guard let normalBg = normalBg, let pressedBg = pressedBg else { return }
            backgroundColor = isHighlighted ? pressedBg : normalBg
        }
    }
}

/// フリック入力キー（中央＋上下左右の5値、指の移動方向で選ぶ）
final class FlickButton: KBButton {
    var values: [String?] = []
    var onCommit: ((String) -> Void)?
    var onPreview: ((String?) -> Void)?
    var suppressCommit = false
    private var startPoint: CGPoint = .zero
    private var currentIndex = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let t = touches.first else { return }
        startPoint = t.location(in: self)
        currentIndex = 0
        suppressCommit = false
        isHighlighted = true
        onPreview?(values[0])
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        let dx = p.x - startPoint.x
        let dy = p.y - startPoint.y
        var idx = 0
        if abs(dx) > 26 || abs(dy) > 26 {
            idx = abs(dx) > abs(dy) ? (dx < 0 ? 1 : 3) : (dy < 0 ? 2 : 4)
        }
        if idx != currentIndex {
            currentIndex = idx
            onPreview?(values[idx] ?? values[0])
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        isHighlighted = false
        onPreview?(nil)
        if !suppressCommit, let v = values[currentIndex] ?? values[0] {
            onCommit?(v)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        isHighlighted = false
        onPreview?(nil)
    }

    func cancelPreview() {
        onPreview?(nil)
        isHighlighted = false
    }
}

enum KBMode {
    case letters, numbers, symbols, clipboard, emoji, cursor, candidateList
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
    /// 自分がマーク付きテキストを表示中かどうか（unmark の誤確定を防ぐ）
    private var markedTextShown = false
    private var lastShiftTapAt: Date?

    private let toolbar = UIStackView()
    private let toolbarLabel = UILabel()
    private var toolbarButtons: [KBButton] = []
    private let contentStack = UIStackView()
    private let stripScroll = UIScrollView()
    private let stripStack = UIStackView()
    private var heightConstraint: NSLayoutConstraint?

    private var backspaceTimer: Timer?
    private let feedback = UIImpactFeedbackGenerator(style: .light)
    private var lastStripSignature: String?
    /// 候補リクエストの世代（古い非同期結果を捨てるため）
    private var candidateGeneration = 0
    /// currentCandidates がどの入力文字列に対するものか
    private var candidatesFor: String = ""
    private let candidateQueue = DispatchQueue(label: "sparklekey.candidate-queue")
    /// スペースキーのドラッグによるカーソル移動
    private var spaceDragApplied = 0
    private var spaceDragMoved = false
    private var suppressNextSpaceTap = false
    /// 自動で Shift を入れたかどうか（手動 Shift と区別する）
    private var autoShiftArmed = false
    /// 確定キー（変換中はラベルが「確定」になる）
    private weak var returnKeyButton: KBButton?
    private var emojiTabIsRecent = true
    private var emojiCategoryIndex = 0
    private let stripExpandButton = KBButton(type: .system)
    private var contextSnapshotAtMark: String?
    private var emojiScrollView: UIScrollView?
    private var emojiSectionAnchors: [UIView] = []
    private var emojiHasRecentSection = false

    // 英語の予測候補（UITextChecker）
    private var englishWord = ""
    private var englishSuggestions: [String] = []
    private let textChecker = UITextChecker()

    // 片手モード用のルート制約
    private let rootStack = UIStackView()
    private var rootLeading: NSLayoutConstraint?
    private var rootTrailing: NSLayoutConstraint?

    // Twemoji スプライト（絵文字パネルの表示用）
    private var twemojiSprite: UIImage?
    private var twemojiMap: [String: Int] = [:]
    private var twemojiCell: Int = 72
    private var twemojiCols: Int = 20
    private var twemojiCache: [String: UIImage] = [:]

    /// フリック入力パッドが表示中か（かな入力方式がフリックで、かな文字盤のとき）
    private var flickActive: Bool {
        mode == .letters && lang == .kana && SharedStore.kanaStyle == .flick
    }

    /// 変換中のかなを入力欄・候補バーに表示すべき状態か
    /// （ローマ字入力中か、フリック入力中）
    private var composingActive: Bool {
        (lang == .kana && mode == .letters) || flickActive
    }

    private func flickPreview(_ button: KBButton, text: String?) {
        guard let text else { popupView.isHidden = true; return }
        popupLabel.text = text
        let frame = button.convert(button.bounds, to: view)
        let w = max(frame.width + 16, 46)
        let h: CGFloat = 54
        var x = frame.midX - w / 2
        x = min(max(x, 2), view.bounds.width - w - 2)
        let y = max(frame.minY - h - 2, 0)
        popupView.frame = CGRect(x: x, y: y, width: w, height: h)
        popupView.isHidden = false
        view.bringSubviewToFront(popupView)
    }

    /// 変換中は確定キーの表示を「確定」に変える（Gboard と同じ）
    private func updateReturnKeyLabel() {
        guard let b = returnKeyButton else { return }
        let label = ((lang == .kana || flickActive) && hasComposing) ? "確定" : returnLabel()
        if b.title(for: .normal) != label {
            b.setTitle(label, for: .normal)
        }
    }

    // キー押下プレビュー（Gboard 風ポップアップ）
    private let popupView = UIView()
    private let popupLabel = UILabel()

    @objc private func showKeyPopup(_ sender: KBButton) {
        guard let text = sender.title(for: .normal), !text.isEmpty else { return }
        popupLabel.text = text
        let frame = sender.convert(sender.bounds, to: view)
        let w = max(frame.width + 16, 46)
        let h: CGFloat = 54
        var x = frame.midX - w / 2
        x = min(max(x, 2), view.bounds.width - w - 2)
        let y = max(frame.minY - h - 2, 0)
        popupView.frame = CGRect(x: x, y: y, width: w, height: h)
        popupView.isHidden = false
        view.bringSubviewToFront(popupView)
    }

    @objc private func keyLongPressed(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began, let b = gr.view as? KBButton, let sub = b.subText else { return }
        b.longPressFired = true
        if let fb = b as? FlickButton {
            fb.suppressCommit = true
            fb.cancelPreview()
        }
        popupLabel.text = sub
        insertTextSmart(sub)
        tapFeedback()
    }

    @objc private func hideKeyPopup() {
        popupView.isHidden = true
    }

    // MARK: ライフサイクル

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.075, green: 0.075, blue: 0.078, alpha: 1)
                : UIColor(red: 0.925, green: 0.933, blue: 0.945, alpha: 1)
        }

        let root = rootStack
        root.axis = .vertical
        root.spacing = 6
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        rootLeading = root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4)
        rootTrailing = root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4)
        NSLayoutConstraint.activate([
            rootLeading!, rootTrailing!,
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])

        // 候補一覧ボタン（変換中だけ候補バーの右端に出す）
        stripExpandButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        stripExpandButton.tintColor = .secondaryLabel
        stripExpandButton.action = .expandCandidates
        stripExpandButton.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        stripExpandButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        stripExpandButton.isHidden = true

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
        // 候補バーはツールバーの中に入れる（rebuildToolbar が配置する）
        stripScroll.heightAnchor.constraint(equalToConstant: 36).isActive = true
        stripScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stripScroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

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

        // 押下プレビューの見た目
        popupView.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.23, green: 0.23, blue: 0.25, alpha: 1)
                : .white
        }
        popupView.layer.cornerRadius = 8
        popupView.layer.shadowColor = UIColor.black.cgColor
        popupView.layer.shadowOpacity = 0.3
        popupView.layer.shadowRadius = 4
        popupView.layer.shadowOffset = CGSize(width: 0, height: 2)
        popupView.isUserInteractionEnabled = false
        popupView.isHidden = true
        popupLabel.font = .systemFont(ofSize: 28)
        popupLabel.textAlignment = .center
        popupLabel.translatesAutoresizingMaskIntoConstraints = false
        popupView.addSubview(popupLabel)
        NSLayoutConstraint.activate([
            popupLabel.centerXAnchor.constraint(equalTo: popupView.centerXAnchor),
            popupLabel.centerYAnchor.constraint(equalTo: popupView.centerYAnchor),
        ])
        view.addSubview(popupView)

        feedback.prepare()
        // 変換エンジンの初期化（辞書読み込み）を表示直後に済ませ、
        // 最初のかな入力で固まらないようにする
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
            KanjiConverter.warmUp()
        }

        let h = view.heightAnchor.constraint(equalToConstant: 276)
        h.priority = UILayoutPriority(999)
        h.isActive = true
        heightConstraint = h

        rebuildAll()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        checkExternalCommit()
        updateAutoShift()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        checkExternalCommit()
    }

    /// 英語モード：文頭と「. 」等の直後では自動で Shift を入れる（標準キーボード風）
    private func updateAutoShift() {
        guard lang == .en, mode == .letters, shiftState != .locked else { return }
        let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
        let shouldCap = ctx.isEmpty || ctx.hasSuffix(". ") || ctx.hasSuffix("! ")
            || ctx.hasSuffix("? ") || ctx.hasSuffix("\n")
        if shouldCap, shiftState == .off {
            shiftState = .once
            autoShiftArmed = true
            rebuildAll()
        } else if !shouldCap, shiftState == .once, autoShiftArmed {
            shiftState = .off
            autoShiftArmed = false
            rebuildAll()
        }
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
        // 候補バー（stripScroll）はツールバーの住人として永続させる
        toolbar.arrangedSubviews.forEach { if $0 !== stripScroll { $0.removeFromSuperview() } }
        if stripScroll.superview != nil { stripScroll.removeFromSuperview() }
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

        toolbar.addArrangedSubview(toolButton(
            symbol: mode == .emoji ? "keyboard" : "face.smiling",
            title: nil,
            action: .toggleEmoji))

        toolbar.addArrangedSubview(toolButton(
            symbol: mode == .cursor ? "keyboard" : "arrow.left.and.right",
            title: nil,
            action: .toggleCursor))

        toolbar.addArrangedSubview(toolButton(
            symbol: SharedStore.oneHandedMode == 2 ? "sidebar.left" : "sidebar.right",
            title: nil,
            action: .oneHandedToggle))

        // クリップボードボタンの隣が変換候補の表示場所（右端に一覧ボタン）
        let stripBox = UIStackView(arrangedSubviews: [stripScroll, stripExpandButton])
        stripBox.axis = .horizontal
        stripBox.alignment = .center
        stripBox.spacing = 2
        toolbar.addArrangedSubview(stripBox)
        stripScroll.isHidden = (mode != .letters) && !flickActive
        stripExpandButton.isHidden = !(hasComposing && !currentCandidates.isEmpty)

        if mode == .numbers {
            toolbar.addArrangedSubview(toolButton(
                symbol: nil,
                title: SharedStore.numberStyle == .qwerty ? "テンキー" : "123列",
                action: .numberStyleToggle))
        }

        toolbar.addArrangedSubview(toolbarLabel)
        toolbarLabel.isHidden = (mode != .clipboard)
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
        } else {
            toolbarLabel.text = ""
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyOneHanded()
    }

    /// 片手モード（右寄せ/左寄せ）をルートの左右マージンで実現する
    private func applyOneHanded() {
        let w = view.bounds.width
        guard w > 100, let lead = rootLeading, let trail = rootTrailing else { return }
        let inset = w * 0.22
        switch SharedStore.oneHandedMode {
        case 1: lead.constant = inset + 4; trail.constant = -4
        case 2: lead.constant = 4; trail.constant = -inset - 4
        default: lead.constant = 4; trail.constant = -4
        }
    }

    private func updateHeight() {
        let base: CGFloat
        switch mode {
        case .letters:
            base = flickActive ? 332 : (SharedStore.showNumberRow ? 318 : 276)
        case .numbers:
            base = SharedStore.numberStyle == .qwerty ? 276 : 332
        case .symbols:
            base = 276
        case .clipboard:
            base = 312
        case .emoji:
            base = 312
        case .cursor:
            base = 312
        case .candidateList:
            base = 312
        }
        // 候補バーはツールバーの中に入ったので、高さはモードの基本値だけ。
        // 設定の高さ倍率を掛ける。同じ値の再代入でもレイアウトが走るので、
        // 変わるときだけ代入する
        let scaled = base * CGFloat(SharedStore.keyboardHeightScale)
        if heightConstraint?.constant != scaled {
            heightConstraint?.constant = scaled
        }
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

    // MARK: マーク付きテキスト（入力中を入力欄に表示する）

    /// 入力欄に表示する変換中テキスト。未確定のローマ字（n、sh など）は
    /// ん等に化けさせずローマ字のまま見せる（Gboard と同じ挙動）。
    /// 変換エンジンに渡す文字列は effectiveComposing()（flush 済み）を使う。
    private func displayComposing() -> String {
        let r = RomajiKana.process(pendingRomaji, flush: false)
        // "nn" は「ん」でほぼ確定なので表示も ん にする（この後ろに母音が
        // 来たら ん＋な行として処理される）。単独の "n" は な行か ん か
        // 未定なのでローマ字のまま見せる。
        let tail = (r.pending == "nn") ? "ん" : r.pending
        return composingKana + r.committed + tail
    }

    /// 入力中テキストを入力欄にマーク付きテキスト（下線表示）として反映する。
    private func updateMarkedText() {
        if composingActive && hasComposing {
            let disp = displayComposing()
            textDocumentProxy.setMarkedText(
                disp, selectedRange: NSRange(location: disp.count, length: 0))
            if !markedTextShown {
                // マーク開始時点の「カーソル前テキスト」を覚える。
                // マーク中はこの値は変わらないはず（マーク文字列は含まれない）
                contextSnapshotAtMark = textDocumentProxy.documentContextBeforeInput
            }
            markedTextShown = true
        } else if markedTextShown {
            // unmarkText() 単体だと表示中のマーク文字列がそのまま「確定」されて
            // 残ってしまう（最後の1文字を消したのに消えず確定される／同じ語が
            // 二重に出る原因）。空文字にしてからマークを外す。
            textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            textDocumentProxy.unmarkText()
            markedTextShown = false
            contextSnapshotAtMark = nil
        }
    }

    /// ホスト側でマーク中テキストが確定・編集されたら、バッファを捨てて同期する。
    /// 入力欄タップ等でホストが勝手に確定すると、こちらのバッファだけが残り、
    /// 次の確定でもう一度同じ語が入ってしまう（二重入力）のを防ぐ。
    /// ここでは絶対にテキストを挿入しない（見るだけ）ので再帰しない。
    private func checkExternalCommit() {
        guard hasComposing, markedTextShown,
              let snapshot = contextSnapshotAtMark else { return }
        let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
        if ctx == snapshot { return }
        composingKana = ""
        pendingRomaji = ""
        currentCandidates = []
        candidatesFor = ""
        markedTextShown = false
        contextSnapshotAtMark = nil
        lastStripSignature = nil
        refreshCandidates()
    }

    /// マーク付きテキストを消してから確定文字列を挿入する
    /// （insertText のマーク置換挙動はアプリ依存なので、先に明示的に消す）
    private func insertCommitted(_ text: String) {
        textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        textDocumentProxy.unmarkText()
        markedTextShown = false
        if !text.isEmpty {
            textDocumentProxy.insertText(text)
        }
    }

    private func refreshCandidates() {
        updateMarkedText()
        let eff = effectiveComposing()
        // 表示（入力中のかな）は即時更新する。変換候補の取得は重いので
        // バックグラウンドで行い、届いたら差し替える（打鍵の反応を遅らせない）
        applyStrip()
        updateHeight()
        updateReturnKeyLabel()
        updateToolbarLabel()
        guard composingActive && !eff.isEmpty else {
            if !currentCandidates.isEmpty {
                currentCandidates = []
                candidatesFor = ""
                applyStrip()
            }
            return
        }
        candidateGeneration += 1
        let gen = candidateGeneration
        candidateQueue.async { [weak self] in
            guard let self = self else { return }
            // 打鍵のたびにキューが積まれるので、開始時点で古くなっている
            // リクエストは推論を回さず捨てる（レスポンス改善）
            guard gen == self.candidateGeneration else { return }
            let cands = KanjiConverter.candidates(for: eff)
            DispatchQueue.main.async {
                guard gen == self.candidateGeneration,
                      eff == self.effectiveComposing() else { return }
                self.currentCandidates = cands
                self.candidatesFor = eff
                self.applyStrip()
            }
        }
    }

    /// 候補バーの再構築（中身が前回と同じなら何もしない）
    /// 変換中（候補表示中）はツールバー左のアイコン類を隠し、候補バーを全幅にする
    private func updateToolbarIconVisibility() {
        let stripActive = hasComposing || !englishSuggestions.isEmpty
        for b in toolbarButtons { b.isHidden = stripActive }
        stripExpandButton.isHidden = !(hasComposing && !currentCandidates.isEmpty)
    }

    private func applyStrip() {
        if mode == .letters && lang == .en {
            let signature = "EN\u{1}" + englishSuggestions.joined(separator: "\u{2}")
            guard signature != lastStripSignature else { return }
            lastStripSignature = signature
            rebuildStrip()
            updateToolbarIconVisibility()
            return
        }
        let eff = effectiveComposing()
        let signature = eff + "\u{1}" + currentCandidates.map { $0.text }.joined(separator: "\u{2}")
        guard signature != lastStripSignature else { return }
        let wasEmpty = (lastStripSignature == nil) || (lastStripSignature?.hasPrefix("\u{1}") ?? false)
        lastStripSignature = signature
        rebuildStrip()
        updateToolbarIconVisibility()
        if wasEmpty && !eff.isEmpty {
            stripScroll.setContentOffset(.zero, animated: false)
        }
    }

    private func rebuildStrip() {
        stripStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if mode == .letters && lang == .en {
            for word in englishSuggestions {
                let b = KBButton(type: .system)
                b.setTitle(word, for: .normal)
                b.setTitleColor(.label, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 17)
                b.backgroundColor = .clear
                b.normalBg = .clear
                b.pressedBg = pressedKeyColor()
                b.layer.cornerRadius = 8
                b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
                b.action = .englishSuggest(word)
                b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                stripStack.addArrangedSubview(b)
            }
            return
        }
        guard !currentCandidates.isEmpty else { return }

        for (i, cand) in currentCandidates.enumerated() {
            let b = KBButton(type: .system)
            b.setTitle(cand.text, for: .normal)
            b.setTitleColor(.label, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 17)
            b.backgroundColor = .clear
            b.normalBg = .clear
            b.pressedBg = pressedKeyColor()
            b.layer.cornerRadius = 8
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            b.action = .candidate(i)
            b.candidateValue = cand
            b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            stripStack.addArrangedSubview(b)
        }

        let commit = KBButton(type: .system)
        commit.setTitle("✓確定", for: .normal)
        commit.setTitleColor(accentKeyColor(), for: .normal)
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
        // 候補は「取得した時点の入力」に対するもの。入力が伸びた後に古い候補を
        // 使うと consumed（消費する読み）が今の入力と合わず、文が細切れに
        // 確定される（「の野村龍太郎」の原因）。一致する時だけ再利用し、
        // それ以外はその場で同期取得する。
        if candidatesFor != composingKana {
            currentCandidates = KanjiConverter.candidates(for: composingKana)
            candidatesFor = composingKana
        }
        let ordered = currentCandidates
        guard ordered.indices.contains(index) else { return }
        let cand = ordered[index]
        insertCommitted(cand.text)
        // 学習へ通知（消費した読みとセットで）
        KanjiConverter.notifySelected(
            cand, reading: String(composingKana.prefix(cand.consumed)), weight: 3)
        composingKana = String(composingKana.dropFirst(cand.consumed))
        refreshCandidates()
    }

    /// 入力中を「先頭候補で変換しながら」全部確定する
    private func commitConvertedAll() {
        materializeComposing()
        let fullReading = composingKana
        var fullOutput = ""
        var guardCount = 0
        var firstPass = true
        while !composingKana.isEmpty && guardCount < 64 {
            guardCount += 1
            // 最初の文節は、表示中だった候補列をそのまま使う（再推論しない）
            let cands: [ConversionCandidate]
            if firstPass && candidatesFor == composingKana && !currentCandidates.isEmpty {
                cands = currentCandidates
            } else {
                cands = KanjiConverter.candidates(for: composingKana)
            }
            firstPass = false
            guard let first = cands.first, first.consumed > 0 else { break }
            insertCommitted(first.text)
            fullOutput += first.text
            KanjiConverter.notifySelected(
                first, reading: String(composingKana.prefix(first.consumed)))
            let before = composingKana
            composingKana = String(composingKana.dropFirst(first.consumed))
            if composingKana == before { break }
        }
        // 文全体をフレーズとして学習（次回は丸ごと候補に出す）
        if composingKana.isEmpty, !fullReading.isEmpty {
            KanjiConverter.recordPhrase(reading: fullReading, text: fullOutput)
        }
        currentCandidates = []
        candidatesFor = ""
        refreshCandidates()
    }

    /// 入力中をかなのまま全部確定する
    /// 候補一覧を開いているときだけ、文字盤へ戻る
    private func leaveCandidateList() {
        if mode == .candidateList {
            mode = .letters
            rebuildAll()
        }
    }

    /// 自動変換の設定に従って入力中を全部確定する。
    /// 句読点やモード切替などの「ついで確定」は必ずこちらを通す
    /// （commitConvertedAll を直接呼ぶと自動変換 OFF でも変換されてしまう）。
    private func commitAllAutoAware() {
        if SharedStore.autoConvertEnabled { commitConvertedAll() }
        else { commitRawAll() }
    }

    private func commitRawAll() {
        materializeComposing()
        if !composingKana.isEmpty {
            let raw = composingKana
            composingKana = ""
            insertCommitted(raw)
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
        var sub: String? = nil
        var pill: Bool = false
        init(_ label: String, _ action: KeyAction, weight: CGFloat = 1, symbol: String? = nil, small: Bool = false, sub: String? = nil, pill: Bool = false) {
            self.label = label
            self.action = action
            self.weight = weight
            self.symbol = symbol
            self.small = small
            self.sub = sub
            self.pill = pill
        }
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        contentStack.distribution = (mode == .clipboard || mode == .emoji || mode == .cursor || mode == .candidateList) ? .fill : .fillEqually
        switch mode {
        case .letters:
            if flickActive { buildFlickPad() } else { buildLetters() }
        case .numbers:
            switch SharedStore.numberStyle {
            case .qwerty: buildNumbersQwerty()
            case .tenkey, .flick: buildTenkey()
            }
        case .symbols: buildSymbols()
        case .clipboard: buildClipboard()
        case .emoji: buildEmoji()
        case .cursor: buildCursor()
        case .candidateList: buildCandidateList()
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
        if case .returnKey = spec.action {
            b.backgroundColor = pillKeyColor()
            b.setTitleColor(pillTitleColor(), for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            b.isPill = true
        } else if spec.pill {
            b.backgroundColor = pillKeyColor()
            b.setTitleColor(pillTitleColor(), for: .normal)
            b.isPill = true
        } else if case .space = spec.action {
            b.backgroundColor = normalKeyColor()
            b.setTitleColor(.secondaryLabel, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13)
        } else {
            b.backgroundColor = isSpecial ? specialKeyColor() : normalKeyColor()
        }
        b.normalBg = b.backgroundColor
        let isReturnKey: Bool
        if case .returnKey = spec.action { isReturnKey = true } else { isReturnKey = false }
        if isReturnKey || spec.pill {
            b.pressedBg = pressedPillKeyColor()
        } else {
            b.pressedBg = isSpecial ? pressedSpecialKeyColor() : pressedKeyColor()
        }
        b.layer.cornerRadius = 10
        b.action = spec.action

        if case .text = spec.action, spec.label.count == 1 {
            // Gboard 風: 押した文字をキーの上に大きくプレビューする
            b.addTarget(self, action: #selector(showKeyPopup(_:)), for: .touchDown)
            b.addTarget(self, action: #selector(hideKeyPopup), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }
        if let sub = spec.sub {
            // Gboard 風: 右上に長押しヒント、長押しでその文字を入力
            b.subText = sub
            let hint = UILabel()
            hint.text = sub
            hint.font = .systemFont(ofSize: 10)
            hint.textColor = .secondaryLabel
            hint.isUserInteractionEnabled = false
            hint.translatesAutoresizingMaskIntoConstraints = false
            b.addSubview(hint)
            NSLayoutConstraint.activate([
                hint.topAnchor.constraint(equalTo: b.topAnchor, constant: 3),
                hint.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -5),
            ])
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(keyLongPressed(_:)))
            lp.minimumPressDuration = 0.35
            b.addGestureRecognizer(lp)
        }
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
        if case .space = spec.action {
            // スペースを左右にドラッグでカーソル移動（標準キーボード風）
            let pan = UIPanGestureRecognizer(target: self, action: #selector(spacePan(_:)))
            pan.cancelsTouchesInView = false
            b.addGestureRecognizer(pan)
        }
        return b
    }

    @objc private func spacePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            spaceDragApplied = 0
            spaceDragMoved = false
        case .changed:
            guard !hasComposing else { return }
            let dx = gesture.translation(in: view).x
            let chars = Int(dx / 14)
            if chars != spaceDragApplied {
                textDocumentProxy.adjustTextPosition(byCharacterOffset: chars - spaceDragApplied)
                spaceDragApplied = chars
            }
            if abs(dx) > 10 { spaceDragMoved = true }
        case .ended, .cancelled, .failed:
            if spaceDragMoved { suppressNextSpaceTap = true }
            spaceDragApplied = 0
            spaceDragMoved = false
        default:
            break
        }
    }

    // Gboard（Material You）風パレット: 白キー＋薄グレーの盤面、特殊キーは一段濃いグレー
    private func normalKeyColor() -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1)
                : .white
        }
    }

    private func pressedKeyColor() -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.23, green: 0.23, blue: 0.25, alpha: 1)
                : UIColor(red: 0.875, green: 0.89, blue: 0.91, alpha: 1)
        }
    }

    private func pressedSpecialKeyColor() -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.33, green: 0.33, blue: 0.36, alpha: 1)
                : UIColor(red: 0.62, green: 0.74, blue: 0.93, alpha: 1)
        }
    }

    private func specialKeyColor() -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.27, green: 0.27, blue: 0.29, alpha: 1)
                : UIColor(red: 0.78, green: 0.86, blue: 0.97, alpha: 1)
        }
    }

    /// 確定キー用のアクセント（Gboard の検索/確定キーと同じ青）
    /// テーマ色プリセット（本体アプリの設定と番号を共有）
    private func accentPair() -> (light: UIColor, dark: UIColor,
                                  lightPressed: UIColor, darkPressed: UIColor,
                                  darkTitle: UIColor) {
        switch SharedStore.accentIndex {
        case 1: // 紫
            return (UIColor(red: 0.48, green: 0.35, blue: 0.90, alpha: 1),
                    UIColor(red: 0.78, green: 0.66, blue: 0.98, alpha: 1),
                    UIColor(red: 0.40, green: 0.28, blue: 0.78, alpha: 1),
                    UIColor(red: 0.68, green: 0.55, blue: 0.94, alpha: 1),
                    UIColor(red: 0.20, green: 0.10, blue: 0.35, alpha: 1))
        case 2: // ピンク
            return (UIColor(red: 0.85, green: 0.10, blue: 0.38, alpha: 1),
                    UIColor(red: 0.98, green: 0.55, blue: 0.72, alpha: 1),
                    UIColor(red: 0.74, green: 0.07, blue: 0.31, alpha: 1),
                    UIColor(red: 0.94, green: 0.44, blue: 0.63, alpha: 1),
                    UIColor(red: 0.35, green: 0.05, blue: 0.16, alpha: 1))
        case 3: // 緑
            return (UIColor(red: 0.00, green: 0.47, blue: 0.42, alpha: 1),
                    UIColor(red: 0.45, green: 0.85, blue: 0.78, alpha: 1),
                    UIColor(red: 0.00, green: 0.38, blue: 0.34, alpha: 1),
                    UIColor(red: 0.36, green: 0.76, blue: 0.69, alpha: 1),
                    UIColor(red: 0.03, green: 0.20, blue: 0.18, alpha: 1))
        case 4: // グレー
            return (UIColor(red: 0.31, green: 0.35, blue: 0.40, alpha: 1),
                    UIColor(red: 0.72, green: 0.76, blue: 0.80, alpha: 1),
                    UIColor(red: 0.24, green: 0.28, blue: 0.32, alpha: 1),
                    UIColor(red: 0.62, green: 0.66, blue: 0.71, alpha: 1),
                    UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1))
        default: // 青
            return (UIColor(red: 0.043, green: 0.34, blue: 0.82, alpha: 1),
                    UIColor(red: 0.54, green: 0.71, blue: 0.97, alpha: 1),
                    UIColor(red: 0.03, green: 0.27, blue: 0.68, alpha: 1),
                    UIColor(red: 0.45, green: 0.63, blue: 0.92, alpha: 1),
                    UIColor(red: 0.06, green: 0.14, blue: 0.30, alpha: 1))
        }
    }

    private func pillKeyColor() -> UIColor {
        let pair = accentPair()
        return UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? pair.dark
                : pair.light.withAlphaComponent(0.20)
        }
    }

    private func pressedPillKeyColor() -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.70, green: 0.70, blue: 0.80, alpha: 1)
                : UIColor(red: 0.62, green: 0.76, blue: 0.96, alpha: 1)
        }
    }

    private func pillTitleColor() -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.13, green: 0.13, blue: 0.17, alpha: 1)
                : UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        }
    }

    private func accentKeyColor() -> UIColor {
        let pair = accentPair()
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? pair.dark : pair.light
        }
    }

    private func pressedAccentKeyColor() -> UIColor {
        let pair = accentPair()
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? pair.darkPressed : pair.lightPressed
        }
    }

    private func accentTitleColor() -> UIColor {
        let pair = accentPair()
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? pair.darkTitle : .white
        }
    }

    private func bottomRow(firstLabel: String, firstAction: KeyAction, includeLang: Bool = false) -> UIStackView {
        var specs: [Spec] = [
            Spec(firstLabel, firstAction, weight: 1.5, small: true, pill: true),
            Spec("", .globe, weight: 1.0, symbol: "globe"),
        ]
        if includeLang {
            // 日本語⇄英語の切替は下段（Gboard と同じ考え方）
            specs.append(Spec(lang == .en ? "あ" : "EN", .langToggle, weight: 1.1, small: true))
        }
        specs += [
            Spec(lang == .kana ? "、" : ",", .text(","), weight: 0.7),
            Spec(lang == .kana ? "日本語" : "English", .space, weight: includeLang ? 3.0 : 3.6, small: true),
            Spec(lang == .kana ? "。" : ".", .text("."), weight: 0.7),
            Spec(returnLabel(), .returnKey, weight: 1.6, small: true),
        ]
        let row = makeRow(specs)
        returnKeyButton = row.arrangedSubviews.last as? KBButton
        return row
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
        // 右上の小さな文字は長押しで入力できる（Gboard と同じ配置）
        let subs1 = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let subs2 = ["@", "#", "$", "-", "&", "-", "+", "(", ")"]
        let subs3 = ["*", "\"", "'", ":", ";", "!", "?"]
        func letterRow(_ s: String, subs: [String]) -> UIStackView {
            makeRow(s.enumerated().map { i, ch in
                let label = upper ? String(ch).uppercased() : String(ch)
                return Spec(label, .text(String(ch)), sub: subs[i])
            })
        }
        contentStack.addArrangedSubview(letterRow("qwertyuiop", subs: subs1))
        if lang == .kana {
            // JIS 配列と同じく L の隣に長音キー（コンピュータ等の入力用）
            var row2 = "asdfghjkl".enumerated().map { i, ch -> Spec in
                let label = upper ? String(ch).uppercased() : String(ch)
                return Spec(label, .text(String(ch)), sub: subs2[i])
            }
            row2.append(Spec("ー", .text("-")))
            contentStack.addArrangedSubview(makeRow(row2))
        } else {
            contentStack.addArrangedSubview(letterRow("asdfghjkl", subs: subs2))
        }
        var third: [Spec] = [Spec("", .shift, weight: 1.4, symbol: shiftState == .off ? "shift" : (shiftState == .locked ? "capslock.fill" : "shift.fill"))]
        third += "zxcvbnm".enumerated().map { i, ch in
            Spec(upper ? String(ch).uppercased() : String(ch), .text(String(ch)), sub: subs3[i])
        }
        third.append(Spec("", .backspace, weight: 1.4, symbol: "delete.left"))
        contentStack.addArrangedSubview(makeRow(third))
        contentStack.addArrangedSubview(bottomRow(firstLabel: "?123", firstAction: .showNumbers, includeLang: true))
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

    private func makeFlickKey(_ values: [String?], sub: String?, title: String? = nil, fontSize: CGFloat = 24) -> FlickButton {
        let b = FlickButton(type: .system)
        b.values = values
        b.setTitle(title ?? values[0] ?? "", for: .normal)
        b.setTitleColor(.label, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: fontSize)
        b.backgroundColor = normalKeyColor()
        b.normalBg = b.backgroundColor
        b.pressedBg = pressedKeyColor()
        b.layer.cornerRadius = 10
        b.onCommit = { [weak self] v in self?.flickInput(v) }
        b.onPreview = { [weak self, weak b] text in
            guard let self, let b else { return }
            self.flickPreview(b, text: text)
        }
        if let sub {
            b.subText = sub
            let hint = UILabel()
            hint.text = sub
            hint.font = .systemFont(ofSize: 10)
            hint.textColor = .secondaryLabel
            hint.isUserInteractionEnabled = false
            hint.translatesAutoresizingMaskIntoConstraints = false
            b.addSubview(hint)
            NSLayoutConstraint.activate([
                hint.topAnchor.constraint(equalTo: b.topAnchor, constant: 3),
                hint.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -5),
            ])
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(keyLongPressed(_:)))
            lp.minimumPressDuration = 0.35
            b.addGestureRecognizer(lp)
        }
        return b
    }

    /// 数字テンキー（2枚目のスクショのレール配置で、中身は数字）
    private func buildTenkey() {
        let pad = UIStackView()
        pad.axis = .horizontal
        pad.spacing = 6
        pad.distribution = .fill

        // 左レール: ◀ / 絵文字 / 記号 / ABC
        let left = UIStackView()
        left.axis = .vertical
        left.spacing = 6
        left.distribution = .fillEqually
        left.addArrangedSubview(makeKey(Spec("", .cursorMove(-1), symbol: "chevron.left")))
        left.addArrangedSubview(makeKey(Spec("", .toggleEmoji, symbol: "face.smiling")))
        left.addArrangedSubview(makeKey(Spec("#+=", .showSymbols, small: true)))
        left.addArrangedSubview(makeKey(Spec("ABC", .showLetters, small: true)))

        // 中央: 数字 3列×4行
        let center = UIStackView()
        center.axis = .vertical
        center.spacing = 6
        center.distribution = .fillEqually
        for rowChars in ["123", "456", "789"] {
            center.addArrangedSubview(makeRow(rowChars.map { Spec(String($0), .text(String($0))) }))
        }
        center.addArrangedSubview(makeRow([
            Spec(",", .text(",")),
            Spec("0", .text("0")),
            Spec(".", .text(".")),
        ]))

        // 右レール: ⌫ / ▶ / スペース / 確定
        let right = UIStackView()
        right.axis = .vertical
        right.spacing = 6
        right.distribution = .fillEqually
        right.addArrangedSubview(makeKey(Spec("", .backspace, symbol: "delete.left")))
        right.addArrangedSubview(makeKey(Spec("", .cursorMove(1), symbol: "chevron.right")))
        right.addArrangedSubview(makeKey(Spec("␣", .space)))
        let returnButton = makeKey(Spec(returnLabel(), .returnKey, small: true))
        returnKeyButton = returnButton
        right.addArrangedSubview(returnButton)

        pad.addArrangedSubview(left)
        pad.addArrangedSubview(center)
        pad.addArrangedSubview(right)
        left.widthAnchor.constraint(equalTo: pad.widthAnchor, multiplier: 0.17).isActive = true
        right.widthAnchor.constraint(equalTo: pad.widthAnchor, multiplier: 0.17).isActive = true
        contentStack.addArrangedSubview(pad)
    }

    /// フリック入力パッド（Gboard の12キー配列、Aqua のスクショ準拠）
    private func buildFlickPad() {
        let pad = UIStackView()
        pad.axis = .horizontal
        pad.spacing = 6
        pad.distribution = .fill

        // 左レール: 文字盤では 123 / ◀ / 記号 / 英字切替、
        // 数字盤では 取消 / ◀ / 記号 / 文字盤へ
        let left = UIStackView()
        left.axis = .vertical
        left.spacing = 6
        left.distribution = .fillEqually
        if mode == .letters {
            left.addArrangedSubview(makeKey(Spec("123", .showNumbers, small: true)))
            left.addArrangedSubview(makeKey(Spec("", .cursorMove(-1), symbol: "chevron.left")))
            left.addArrangedSubview(makeKey(Spec("☺記", .showSymbols, small: true)))
            left.addArrangedSubview(makeKey(Spec("aあ", .langToggle, small: true)))
        } else {
            left.addArrangedSubview(makeKey(Spec("", .clearComposing, symbol: "arrow.uturn.backward")))
            left.addArrangedSubview(makeKey(Spec("", .cursorMove(-1), symbol: "chevron.left")))
            left.addArrangedSubview(makeKey(Spec("☺記", .showSymbols, small: true)))
            left.addArrangedSubview(makeKey(Spec("あa1", .showLetters, small: true)))
        }

        // 中央: 3列×4行のフリックキー（値は [中央, 左, 上, 右, 下]）
        let center = UIStackView()
        center.axis = .vertical
        center.spacing = 6
        center.distribution = .fillEqually
        func flickRow(_ keys: [FlickButton]) -> UIStackView {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 6
            row.distribution = .fillEqually
            keys.forEach { row.addArrangedSubview($0) }
            return row
        }
        center.addArrangedSubview(flickRow([
            makeFlickKey(["あ", "い", "う", "え", "お"], sub: "1"),
            makeFlickKey(["か", "き", "く", "け", "こ"], sub: "2"),
            makeFlickKey(["さ", "し", "す", "せ", "そ"], sub: "3"),
        ]))
        center.addArrangedSubview(flickRow([
            makeFlickKey(["た", "ち", "つ", "て", "と"], sub: "4"),
            makeFlickKey(["な", "に", "ぬ", "ね", "の"], sub: "5"),
            makeFlickKey(["は", "ひ", "ふ", "へ", "ほ"], sub: "6"),
        ]))
        center.addArrangedSubview(flickRow([
            makeFlickKey(["ま", "み", "む", "め", "も"], sub: "7"),
            makeFlickKey(["や", "「", "ゆ", "」", "よ"], sub: "8"),
            makeFlickKey(["ら", "り", "る", "れ", "ろ"], sub: "9"),
        ]))
        // 最下段: 地球儀 / わ / 句読点（下フリックで濁点・小文字）
        let bottomCenter = UIStackView()
        bottomCenter.axis = .horizontal
        bottomCenter.spacing = 6
        bottomCenter.distribution = .fillEqually
        bottomCenter.addArrangedSubview(makeKey(Spec("", .globe, symbol: "globe")))
        bottomCenter.addArrangedSubview(makeFlickKey(["わ", "ー", "を", "ゎ", "ん"], sub: "0"))
        bottomCenter.addArrangedSubview(makeFlickKey(["、", "。", "？", "！", "゛"], sub: nil, title: "、。？！", fontSize: 13))
        center.addArrangedSubview(bottomCenter)

        // 右レール: ⌫ / ▶ / スペース / 確定
        let right = UIStackView()
        right.axis = .vertical
        right.spacing = 6
        right.distribution = .fillEqually
        right.addArrangedSubview(makeKey(Spec("", .backspace, symbol: "delete.left")))
        right.addArrangedSubview(makeKey(Spec("", .cursorMove(1), symbol: "chevron.right")))
        right.addArrangedSubview(makeKey(Spec("␣", .space)))
        let returnButton = makeKey(Spec(returnLabel(), .returnKey, small: true))
        returnKeyButton = returnButton
        right.addArrangedSubview(returnButton)

        pad.addArrangedSubview(left)
        pad.addArrangedSubview(center)
        pad.addArrangedSubview(right)
        left.widthAnchor.constraint(equalTo: pad.widthAnchor, multiplier: 0.17).isActive = true
        right.widthAnchor.constraint(equalTo: pad.widthAnchor, multiplier: 0.17).isActive = true
        contentStack.addArrangedSubview(pad)
    }

    // MARK: フリック入力

    private func flickInput(_ value: String) {
        // ローマ字の未確定分が残っていたら先に流し込む
        if !pendingRomaji.isEmpty {
            let r = RomajiKana.process(pendingRomaji, flush: true)
            composingKana += r.committed
            pendingRomaji = r.pending
        }
        switch value {
        case "、", "。", "？", "！":
            if hasComposing { commitAllAutoAware() }
            textDocumentProxy.insertText(value)
        case "゛":
            applyDakutenTransform()
        default:
            composingKana += value
            refreshCandidates()
        }
        tapFeedback()
    }

    /// 濁点・半濁点・小文字の付け外し（入力中の最後の文字に適用、循環）
    private func applyDakutenTransform() {
        guard !composingKana.isEmpty else { return }
        let last = String(composingKana.last!)
        let cycles: [[String]] = [
            ["か", "が"], ["き", "ぎ"], ["く", "ぐ"], ["け", "げ"], ["こ", "ご"],
            ["さ", "ざ"], ["し", "じ"], ["す", "ず"], ["せ", "ぜ"], ["そ", "ぞ"],
            ["た", "だ"], ["ち", "ぢ"], ["つ", "づ", "っ"], ["て", "で"], ["と", "ど"],
            ["は", "ば", "ぱ"], ["ひ", "び", "ぴ"], ["ふ", "ぶ", "ぷ"], ["へ", "べ", "ぺ"], ["ほ", "ぼ", "ぽ"],
            ["う", "ゔ"],
            ["あ", "ぁ"], ["い", "ぃ"], ["え", "ぇ"], ["お", "ぉ"],
            ["や", "ゃ"], ["ゆ", "ゅ"], ["よ", "ょ"], ["わ", "ゎ"],
        ]
        for cycle in cycles {
            if let i = cycle.firstIndex(of: last) {
                let next = cycle[(i + 1) % cycle.count]
                composingKana.removeLast()
                composingKana += next
                refreshCandidates()
                return
            }
        }
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

    // MARK: カーソル移動・テキスト編集パネル

    /// 変換候補の一覧（▼から開く。標準キーボード風：候補が幅に合わせて
    /// 行に流れ込み、行ごとに罫線。1行目の右端に ∧（閉じる））
    private func buildCandidateList() {
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        let list = UIStackView()
        list.axis = .vertical
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            list.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            list.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])

        // 候補を文字幅で測って行に詰める（標準キーボードの折り返し方）
        let font = UIFont.systemFont(ofSize: 22)
        let panelWidth = (view.bounds.width > 0 ? view.bounds.width
                          : UIScreen.main.bounds.width) - 4
        var rows: [[Int]] = []
        var current: [Int] = []
        var currentWidth: CGFloat = 0
        for (i, cand) in currentCandidates.enumerated() {
            let w = (cand.text as NSString).size(
                withAttributes: [.font: font]).width + 30
            let limit = panelWidth - (rows.isEmpty ? 46 : 0)
            if !current.isEmpty && currentWidth + w > limit {
                rows.append(current)
                current = []
                currentWidth = 0
            }
            current.append(i)
            currentWidth += w
        }
        if !current.isEmpty { rows.append(current) }

        func candidateButton(_ i: Int) -> KBButton {
            let cand = currentCandidates[i]
            let b = KBButton(type: .system)
            b.setTitle(cand.text, for: .normal)
            b.setTitleColor(.label, for: .normal)
            b.titleLabel?.font = font
            b.titleLabel?.lineBreakMode = .byTruncatingTail
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.7
            b.backgroundColor = .clear
            b.normalBg = .clear
            b.pressedBg = pressedKeyColor()
            b.action = .candidate(i)
            b.candidateValue = cand
            b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            return b
        }
        func separator() -> UIView {
            let sep = UIView()
            sep.backgroundColor = .separator
            sep.heightAnchor.constraint(
                equalToConstant: 1 / UIScreen.main.scale).isActive = true
            return sep
        }

        for (r, rowIdxs) in rows.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            for i in rowIdxs { rowStack.addArrangedSubview(candidateButton(i)) }
            rowStack.heightAnchor.constraint(equalToConstant: 58).isActive = true
            if r == 0 {
                let chevron = KBButton(type: .system)
                chevron.setImage(UIImage(systemName: "chevron.up"), for: .normal)
                chevron.tintColor = .secondaryLabel
                chevron.action = .candidateListClose
                chevron.addTarget(self, action: #selector(keyTapped(_:)),
                                  for: .touchUpInside)
                chevron.widthAnchor.constraint(equalToConstant: 46).isActive = true
                let topRow = UIStackView(arrangedSubviews: [rowStack, chevron])
                topRow.axis = .horizontal
                topRow.alignment = .center
                list.addArrangedSubview(topRow)
            } else {
                list.addArrangedSubview(rowStack)
            }
            if r < rows.count - 1 { list.addArrangedSubview(separator()) }
        }
        contentStack.addArrangedSubview(scroll)
    }

    private func buildCursor() {
        let moveRow = makeRow([
            Spec("←", .cursorMove(-1)),
            Spec("→", .cursorMove(1)),
        ])
        contentStack.addArrangedSubview(moveRow)

        let editRow = makeRow([
            Spec("コピー", .copyText, small: true),
            Spec("カット", .cutText, small: true),
            Spec("ペースト", .pasteText, small: true),
            Spec("", .backspace, symbol: "delete.left"),
        ])
        editRow.heightAnchor.constraint(equalToConstant: 52).isActive = true
        contentStack.addArrangedSubview(editRow)

        // 自動変換の状態表示と切り替え（キーボード側から見た今の設定。
        // 本体アプリの設定と食い違う場合は、ここで切り替えれば確実に効く）
        let settingRow = makeRow([
            Spec(SharedStore.autoConvertEnabled ? "自動変換 ON" : "自動変換 OFF",
                 .autoConvertToggle, small: true),
        ])
        settingRow.heightAnchor.constraint(equalToConstant: 52).isActive = true
        contentStack.addArrangedSubview(settingRow)

        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        var info = "Sparkle Key \(version) / 設定共有 \(SharedStore.groupAvailable ? "OK" : "NG")"
        if !SharedStore.groupAvailable {
            info += SharedStore.profileFound
                ? " / ID…\(SharedStore.appGroupID.suffix(16))"
                : " / profile×"
        }
        let infoRow = makeRow([
            Spec(info, .noop, small: true),
        ])
        infoRow.heightAnchor.constraint(equalToConstant: 40).isActive = true
        contentStack.addArrangedSubview(infoRow)

        let bottom = bottomRow(firstLabel: "ABC", firstAction: .showLetters)
        bottom.heightAnchor.constraint(equalToConstant: 48).isActive = true
        contentStack.addArrangedSubview(bottom)
    }

    // MARK: 絵文字パネル

    private func currentEmojiItems() -> [String] {
        if emojiTabIsRecent {
            let recent = SharedStore.loadRecentEmoji()
            if !recent.isEmpty { return recent }
        }
        return EmojiData.categories[emojiCategoryIndex].items
    }

    // MARK: Twemoji（絵文字パネルの表示用スプライト）

    private func loadTwemojiIfNeeded() {
        guard twemojiSprite == nil else { return }
        guard let imgURL = Bundle.main.url(forResource: "twemoji-sprite", withExtension: "png"),
              let img = UIImage(contentsOfFile: imgURL.path),
              let idxURL = Bundle.main.url(forResource: "twemoji-index", withExtension: "json"),
              let data = try? Data(contentsOf: idxURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let map = obj["map"] as? [String: Int] else { return }
        twemojiSprite = img
        twemojiMap = map
        twemojiCell = obj["cell"] as? Int ?? 72
        twemojiCols = obj["cols"] as? Int ?? 20
    }

    private func twemojiImage(for emoji: String) -> UIImage? {
        loadTwemojiIfNeeded()
        if let cached = twemojiCache[emoji] { return cached }
        guard let sprite = twemojiSprite, let cg = sprite.cgImage,
              let idx = twemojiMap[emoji] else { return nil }
        let rect = CGRect(x: (idx % twemojiCols) * twemojiCell,
                          y: (idx / twemojiCols) * twemojiCell,
                          width: twemojiCell, height: twemojiCell)
        guard let crop = cg.cropping(to: rect) else { return nil }
        // .system ボタンは画像をテンプレートとして tint で塗るので、原画指定が必須
        let image = UIImage(cgImage: crop, scale: sprite.scale, orientation: .up)
            .withRenderingMode(.alwaysOriginal)
        twemojiCache[emoji] = image
        return image
    }

    private func buildEmoji() {
        // カテゴリタブ（タップでそのセクションへスクロールする）
        let tabs = UIStackView()
        tabs.axis = .horizontal
        tabs.distribution = .fillEqually
        tabs.spacing = 2
        tabs.heightAnchor.constraint(equalToConstant: 36).isActive = true

        func tabButton(symbol: String, fallback: String, fallbackFont: CGFloat = 18, action: KeyAction) -> KBButton {
            let b = KBButton(type: .system)
            if !symbol.isEmpty, let img = UIImage(systemName: symbol) {
                b.setImage(img, for: .normal)
                b.tintColor = .secondaryLabel
            } else {
                b.setTitle(fallback, for: .normal)
                b.setTitleColor(.secondaryLabel, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: fallbackFont)
            }
            b.action = action
            b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            return b
        }

        let recent = SharedStore.loadRecentEmoji()
        emojiHasRecentSection = !recent.isEmpty
        if !recent.isEmpty {
            tabs.addArrangedSubview(tabButton(
                symbol: "clock", fallback: "🕐", action: .emojiCategory(-1)))
        }
        for (i, cat) in EmojiData.categories.enumerated() {
            tabs.addArrangedSubview(tabButton(
                symbol: cat.symbol, fallback: cat.fallback,
                fallbackFont: cat.wide ? 10 : 18,
                action: .emojiCategory(i)))
        }
        contentStack.addArrangedSubview(tabs)

        // 全カテゴリを1つの縦スクロールに並べる（無限スクロール風）
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        emojiScrollView = scroll
        emojiSectionAnchors = []
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 2
        grid.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            grid.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            grid.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            grid.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])

        func addSection(title: String, items: [String], wide: Bool) {
            let header = UILabel()
            header.text = title
            header.font = .systemFont(ofSize: 12, weight: .semibold)
            header.textColor = .secondaryLabel
            header.heightAnchor.constraint(equalToConstant: 22).isActive = true
            grid.addArrangedSubview(header)
            emojiSectionAnchors.append(header)
            let cols = wide ? 3 : 8
            for start in stride(from: 0, to: items.count, by: cols) {
                let row = UIStackView()
                row.axis = .horizontal
                row.distribution = .fillEqually
                row.spacing = 2
                row.heightAnchor.constraint(equalToConstant: 44).isActive = true
                for j in 0..<cols {
                    if start + j < items.count {
                        let e = items[start + j]
                        let b = KBButton(type: .system)
                        if wide {
                            b.setTitle(e, for: .normal)
                            b.setTitleColor(.label, for: .normal)
                            b.titleLabel?.font = .systemFont(ofSize: 17)
                            b.titleLabel?.lineBreakMode = .byTruncatingTail
                        } else if let img = twemojiImage(for: e) {
                            b.setImage(img, for: .normal)
                            b.imageView?.contentMode = .scaleAspectFit
                            b.imageEdgeInsets = UIEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
                        } else {
                            b.setTitle(e, for: .normal)
                            b.titleLabel?.font = .systemFont(ofSize: 28)
                        }
                        b.action = .emojiInsert(e)
                        b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                        row.addArrangedSubview(b)
                    } else {
                        row.addArrangedSubview(UIView())
                    }
                }
                grid.addArrangedSubview(row)
            }
        }

        if !recent.isEmpty {
            addSection(title: "最近使ったもの", items: recent, wide: false)
        }
        for cat in EmojiData.categories {
            addSection(title: cat.title, items: cat.items, wide: cat.wide)
        }
        contentStack.addArrangedSubview(scroll)

        let bottom = bottomRow(firstLabel: "ABC", firstAction: .showLetters)
        bottom.heightAnchor.constraint(equalToConstant: 48).isActive = true
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
        if sender.longPressFired {
            sender.longPressFired = false
            return
        }
        guard let action = sender.action else { return }
        if case .candidate = action, let cand = sender.candidateValue {
            // 表示されていた候補そのものを確定する（リストの再取得で化けない）
            commitCandidateValue(cand)
            tapFeedback()
            return
        }
        handle(action)
    }

    /// 候補バーに表示されていた候補そのものを確定する
    private func commitCandidateValue(_ cand: ConversionCandidate) {
        materializeComposing()
        var target = cand
        if !(cand.consumed > 0 && cand.consumed <= composingKana.count) {
            // 表示の後に入力が変わっていて消費数が合わない。別の候補を勝手に
            // 確定はせず、取り直した候補の中に同じ表記があればそれを使う。
            let fresh = KanjiConverter.candidates(for: composingKana)
            currentCandidates = fresh
            candidatesFor = composingKana
            guard let found = fresh.first(where: {
                $0.text == cand.text && $0.consumed > 0 && $0.consumed <= composingKana.count
            }) else {
                applyStrip()
                return
            }
            target = found
        }
        insertCommitted(target.text)
        KanjiConverter.notifySelected(
            target, reading: String(composingKana.prefix(target.consumed)), weight: 3)
        composingKana = String(composingKana.dropFirst(target.consumed))
        refreshCandidates()
        leaveCandidateList()
    }

    private func handle(_ action: KeyAction) {
        switch action {
        case .text(let raw):
            insertTextSmart(raw)
        case .shift:
            autoShiftArmed = false
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
            if suppressNextSpaceTap {
                // スペースのドラッグ（カーソル移動）直後のタップは無視する
                suppressNextSpaceTap = false
                return
            }
            if lang == .kana && (mode == .letters || flickActive) && hasComposing {
                // 変換：先頭候補を確定（残りは入力中のまま）。
                // 自動変換 OFF のときはかなのまま全部確定する
                if SharedStore.autoConvertEnabled { commitCandidate(at: 0) }
                else { commitRawAll() }
            } else if lang == .en && mode == .letters,
                      let ctx = textDocumentProxy.documentContextBeforeInput,
                      ctx.hasSuffix(" "), !ctx.hasSuffix("  ") {
                // 英語：単語の直後でスペースを2回続けて押したら「. 」にする（標準動作）
                let before = ctx.dropLast()
                if let last = before.last, last.isLetter || last.isNumber {
                    textDocumentProxy.deleteBackward()
                    textDocumentProxy.insertText(". ")
                } else {
                    textDocumentProxy.insertText(" ")
                }
            } else {
                textDocumentProxy.insertText(" ")
            }
        case .returnKey:
            if (lang == .kana || flickActive) && hasComposing {
                // 変換中は「確定」: 確定するだけ（改行しない）
                if SharedStore.autoConvertEnabled { commitConvertedAll() }
                else { commitRawAll() }
            } else {
                textDocumentProxy.insertText("\n")
            }
        case .globe:
            advanceToNextInputMode()
        case .langToggle:
            if hasComposing { commitAllAutoAware() }
            lang = lang == .en ? .kana : .en
            SharedStore.inputLangIsKana = (lang == .kana)
            rebuildAll()
        case .showLetters:
            if hasComposing { commitAllAutoAware() }
            mode = .letters
            rebuildAll()
        case .showNumbers:
            if hasComposing { commitAllAutoAware() }
            mode = .numbers
            rebuildAll()
        case .showSymbols:
            if hasComposing { commitAllAutoAware() }
            mode = .symbols
            rebuildAll()
        case .numberStyleToggle:
            SharedStore.numberStyle =
                SharedStore.numberStyle == .qwerty ? .tenkey : .qwerty
            rebuildAll()
        case .autoConvertToggle:
            SharedStore.autoConvertEnabled = !SharedStore.autoConvertEnabled
            rebuildContent()
        case .noop:
            break
        case .toggleCursor:
            mode = (mode == .cursor) ? .letters : .cursor
            rebuildAll()
        case .cursorMove(let n):
            textDocumentProxy.adjustTextPosition(byCharacterOffset: n)
        case .copyText:
            if let sel = textDocumentProxy.selectedText, !sel.isEmpty {
                UIPasteboard.general.string = sel
            }
        case .cutText:
            if let sel = textDocumentProxy.selectedText, !sel.isEmpty {
                UIPasteboard.general.string = sel
                textDocumentProxy.insertText("")
            }
        case .pasteText:
            if hasFullAccess, let str = UIPasteboard.general.string, !str.isEmpty {
                if hasComposing { commitRawAll() }
                textDocumentProxy.insertText(str)
            }
        case .toggleEmoji:
            mode = (mode == .emoji) ? .letters : .emoji
            rebuildAll()
        case .emojiInsert(let emoji):
            if hasComposing { commitRawAll() }
            textDocumentProxy.insertText(emoji)
            SharedStore.addRecentEmoji(emoji)
        case .emojiCategory(let index):
            // 連続スクロール: タブはセクションへのジャンプ
            let target = index < 0 ? 0 : (emojiHasRecentSection ? index + 1 : index)
            if emojiSectionAnchors.indices.contains(target),
               let scroll = emojiScrollView {
                let y = emojiSectionAnchors[target].frame.minY
                scroll.setContentOffset(CGPoint(x: 0, y: max(0, y - 2)), animated: true)
            }
        case .englishSuggest(let word):
            for _ in 0..<englishWord.count { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(word + " ")
            englishWord = ""
            englishSuggestions = []
            applyStrip()
        case .expandCandidates:
            if hasComposing {
                mode = .candidateList
                rebuildAll()
                // 開くアニメーション（下からスライド＋フェード）
                contentStack.alpha = 0
                contentStack.transform = CGAffineTransform(
                    translationX: 0, y: 18)
                UIView.animate(withDuration: 0.28, delay: 0,
                               usingSpringWithDamping: 0.92,
                               initialSpringVelocity: 0.3,
                               options: [.curveEaseOut]) {
                    self.contentStack.alpha = 1
                    self.contentStack.transform = .identity
                }
            }
        case .candidateListClose:
            mode = .letters
            rebuildAll()
        case .oneHandedToggle:
            SharedStore.oneHandedMode = (SharedStore.oneHandedMode + 1) % 3
            applyOneHanded()
            rebuildToolbar()
        case .toggleClipboard:
            if mode == .clipboard {
                mode = .letters
            } else {
                if hasComposing { commitAllAutoAware() }
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
            if hasComposing { commitAllAutoAware() }
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
            if SharedStore.autoConvertEnabled { commitConvertedAll() }
            else { commitRawAll() }
            leaveCandidateList()
        case .clearComposing:
            // マーク付きテキストごと消す（unmark だけだと文字が残ってしまう）
            textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            textDocumentProxy.unmarkText()
            markedTextShown = false
            composingKana = ""
            pendingRomaji = ""
            refreshCandidates()
            leaveCandidateList()
        }
        tapFeedback()
    }

    private func deleteBackwardSmart() {
        if composingActive && hasComposing {
            if !pendingRomaji.isEmpty {
                pendingRomaji.removeLast()
            } else {
                composingKana.removeLast()
            }
            refreshCandidates()
        } else {
            if mode == .letters && lang == .en, !englishWord.isEmpty,
               let last = (textDocumentProxy.documentContextBeforeInput ?? "").last,
               last.isASCII && last.isLetter {
                englishWord.removeLast()
            }
            textDocumentProxy.deleteBackward()
            if mode == .letters && lang == .en { updateEnglishSuggestions() }
        }
    }

    /// 文字キー：かなモードでは変換バッファへ、英字モードでは Shift を反映して直接挿入
    private func insertTextSmart(_ raw: String) {
        if lang == .kana && mode == .letters {
            if raw == "-" {
                composingKana += "ー"
                refreshCandidates()
                return
            }
            if raw == "," {
                commitAllAutoAware()
                textDocumentProxy.insertText("、")
                return
            }
            if raw == "." {
                commitAllAutoAware()
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
        if shiftState == .once { autoShiftArmed = false }
        if shiftState != .off, raw.count == 1, raw.first!.isLetter {
            textDocumentProxy.insertText(raw.uppercased())
            if shiftState == .once {
                shiftState = .off
                rebuildAll()
            }
        } else {
            textDocumentProxy.insertText(raw)
        }
        // 英語モードでは入力中の単語を追って予測候補を出す
        if mode == .letters && lang == .en {
            if raw.count == 1, let ch = raw.first, ch.isASCII && ch.isLetter {
                englishWord += raw.lowercased()
            } else {
                englishWord = ""
            }
            updateEnglishSuggestions()
        }
    }

    /// 英語の予測候補をシステム辞書（UITextChecker）から引く
    private func updateEnglishSuggestions() {
        guard mode == .letters, lang == .en, englishWord.count >= 2 else {
            if !englishSuggestions.isEmpty {
                englishSuggestions = []
                applyStrip()
            }
            return
        }
        let word = englishWord
        let range = NSRange(location: 0, length: (word as NSString).length)
        let found = textChecker.completions(
            forPartialWordRange: range, in: word, language: "en_US") ?? []
        englishSuggestions = Array(found.filter { $0.lowercased() != word }.prefix(3))
        applyStrip()
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

import UIKit

/// 拼音键盘主视图。形态对齐微信 / 百度 / 讯飞 / 搜狗这类主流中文输入法：
///   - 候选栏：拼音串 + 横滑候选 + 清空 + 展开更多候选
///   - 26 键：系统键宽比例，键帽右上角上滑副标、按下放大预览、长按符号备选
///   - 数字 / 中文标点 / 符号 / 表情四个页面，长按删除连删，空格上屏首候选
///   - 更多候选宫格、联想候选、按键音与振动、深浅色自适应
/// 全部纯 UIKit，键盘扩展不引第三方 framework。
final class TypingKeyboardView: UIView, UIInputViewAudioFeedback,
                                UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    weak var controller: KeyboardViewController?

    var enableInputClicksWhenVisible: Bool { true }

    // MARK: - 类型

    private enum Page {
        case letters
        case numbers
        case symbols
        case emoji
    }

    private enum KeyKind {
        case character(String)      // 字母：中文态进拼音缓冲，英文态直输
        case insert(String)         // 数字 / 标点 / 符号：直接上屏
        case shift
        case delete
        case page(Page)
        case language
        case next
        case space
        case enter
        case more
        case spacer
    }

    private struct KeySpec {
        let title: String
        let kind: KeyKind
        let weight: CGFloat
        let function: Bool
        let size: CGFloat
        let hint: String
        let extras: [String]

        init(_ title: String, _ kind: KeyKind, _ weight: CGFloat = 1,
             function: Bool = false, size: CGFloat = 22,
             hint: String = "", extras: [String] = []) {
            self.title = title
            self.kind = kind
            self.weight = weight
            self.function = function
            self.size = size
            self.hint = hint
            self.extras = extras
        }
    }

    /// 一行键按权重分配 frame。v11 修掉的坑：UIStackView.fillEqually 会把
    /// 功能键和字母键拉平、把空格挤成 1/5 屏宽，所以这里坚持手算 frame。
    private final class KeyRow: UIView {
        var weights: [CGFloat] = []
        var items: [UIView] = []
        private let gap: CGFloat = 6
        private let side: CGFloat = 3

        override func layoutSubviews() {
            super.layoutSubviews()
            guard items.count == weights.count, !items.isEmpty else { return }
            let total = weights.reduce(0, +)
            guard total > 0 else { return }
            let usable = bounds.width - side * 2 - gap * CGFloat(items.count - 1)
            var x = side
            for (index, item) in items.enumerated() {
                let width = usable * weights[index] / total
                item.frame = CGRect(x: x, y: 0, width: width, height: bounds.height).integral
                x += width + gap
            }
        }
    }

    /// 自定义键帽：自己接管 touches，才能同时做「短按 / 上滑 / 长按 / 长按滑动选择」。
    /// 用 UIButton + 多个手势识别器会互相抢事件，这里一套状态机全包了。
    private final class KeyCap: UIView {
        var spec = KeySpec("", .spacer)
        weak var owner: TypingKeyboardView?
        var baseColor: UIColor = .clear
        var pressedColor: UIColor = .clear

        private let titleLabel = UILabel()
        private let hintLabel = UILabel()
        private var start = CGPoint.zero
        private var swiped = false
        private var longFired = false
        private var longTimer: Timer?

        private var pressed = false {
            didSet {
                backgroundColor = pressed ? pressedColor : baseColor
                owner?.capPressed(self, pressed)
            }
        }

        func configure(_ spec: KeySpec, owner: TypingKeyboardView,
                       baseColor: UIColor, pressedColor: UIColor) {
            self.spec = spec
            self.owner = owner
            self.baseColor = baseColor
            self.pressedColor = pressedColor
            backgroundColor = baseColor
            layer.cornerRadius = 5
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.18
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowRadius = 0
            isMultipleTouchEnabled = false

            titleLabel.text = spec.title
            titleLabel.font = .systemFont(ofSize: spec.size)
            titleLabel.textColor = .label
            titleLabel.textAlignment = .center
            titleLabel.backgroundColor = .clear
            titleLabel.isHidden = spec.title.isEmpty

            hintLabel.text = spec.hint
            hintLabel.font = .systemFont(ofSize: 10)
            hintLabel.textColor = .secondaryLabel
            hintLabel.textAlignment = .center
            hintLabel.backgroundColor = .clear
            hintLabel.isHidden = spec.hint.isEmpty

            if titleLabel.superview == nil { addSubview(titleLabel) }
            if hintLabel.superview == nil { addSubview(hintLabel) }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            titleLabel.frame = bounds
            hintLabel.frame = CGRect(x: bounds.width - 19, y: 2, width: 17, height: 14)
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 5).cgPath
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            start = touch.location(in: self)
            swiped = false
            longFired = false
            pressed = true
            let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
                guard let strong = self else { return }
                strong.longFired = true
                strong.owner?.capLongBegan(strong)
            }
            RunLoop.main.add(timer, forMode: .common)
            longTimer = timer
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first, let host = owner else { return }
            let point = touch.location(in: self)
            if longFired {
                owner?.capLongMoved(self, point: touch.location(in: host))
                return
            }
            if !swiped, !spec.hint.isEmpty, start.y - point.y > 20 {
                swiped = true
                longTimer?.invalidate()
                longTimer = nil
                owner?.capSwipedUp(self)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches, cancelled: false)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches, cancelled: true)
        }

        private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
            longTimer?.invalidate()
            longTimer = nil
            pressed = false
            var point = CGPoint.zero
            if let host = owner, let touch = touches.first {
                point = touch.location(in: host)
            }
            if !cancelled {
                if longFired {
                    owner?.capLongEnded(self, point: point)
                } else if !swiped {
                    owner?.capTapped(self)
                }
            }
            swiped = false
            longFired = false
        }
    }

    /// 长按弹出的备选条，手指左右滑动选一个，松手上屏。
    private final class ExtraPopup: UIView {
        var items: [String] = [] {
            didSet { rebuild() }
        }
        var selected = 0 {
            didSet { update() }
        }
        private var labels: [UILabel] = []

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(white: 0.26, alpha: 1)
                    : UIColor(white: 0.97, alpha: 1)
            }
            layer.cornerRadius = 7
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.22
            layer.shadowOffset = CGSize(width: 0, height: 2)
            layer.shadowRadius = 4
            clipsToBounds = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func rebuild() {
            for label in labels { label.removeFromSuperview() }
            labels = items.map { text in
                let label = UILabel()
                label.text = text
                label.font = .systemFont(ofSize: 19)
                label.textAlignment = .center
                label.textColor = .label
                label.layer.cornerRadius = 5
                label.clipsToBounds = true
                addSubview(label)
                return label
            }
            setNeedsLayout()
            update()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard !labels.isEmpty else { return }
            let width = bounds.width / CGFloat(labels.count)
            for (index, label) in labels.enumerated() {
                label.frame = CGRect(x: width * CGFloat(index), y: 3,
                                     width: width, height: bounds.height - 6).integral
            }
        }

        private func update() {
            for (index, label) in labels.enumerated() {
                label.backgroundColor = index == selected ? UIColor.systemBlue.withAlphaComponent(0.22) : .clear
                label.textColor = index == selected ? .systemBlue : .label
            }
        }

        func indexForLocal(_ point: CGPoint) -> Int {
            guard !labels.isEmpty else { return 0 }
            let width = max(1, bounds.width / CGFloat(labels.count))
            return max(0, min(labels.count - 1, Int(point.x / width)))
        }
    }

    private final class GridCell: UICollectionViewCell {
        let label = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 24)
            label.textColor = .label
            label.backgroundColor = .clear
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
                label.topAnchor.constraint(equalTo: contentView.topAnchor),
                label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    // MARK: - 键位数据

    private static let letterRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
    private static let numberHints = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private static let row2Hints = ["@", "#", "¥", "%", "&", "*", "-", "+", "("]
    private static let row3Hints = ["。", "，", "？", "！", "、", "：", "；"]
    private static let numberTop = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private static let chinesePunctuation = ["。", "？", "！", "、", "：", "；", "（", "）", "…", "「"]
    private static let latinPunctuation = [",", ".", "?", "!", "'", "+", "=", "/"]
    private static let symbolRow1 = ["【", "】", "｛", "｝", "〔", "〕", "〈", "〉", "《", "》"]
    private static let symbolRow2 = ["＋", "－", "×", "÷", "＝", "≠", "≈", "≤", "≥", "∞"]
    private static let symbolRow3 = ["￥", "＄", "€", "％", "‰", "℃", "°", "§"]

    private static let emojiTitles = ["😀", "👋", "❤️", "🐶", "🍔", "⚽", "✨", "颜"]
    private static let emojiGroups: [[String]] = [
        "😀😃😄😁😆😅😂🤣😊😇🙂🙃😉😌😍🥰😘😋😛😝😜🤪🤨🧐🤓😎🥳😏😒😞😔😟😕🙁😣😖😫😩🥺😢😭😤😠😡🤯😳🥵🥶😱😨😰😥😓🤗🤔🤭🤫🤥😶😐😑😬🙄😯😦😧😮😲😴😪😵🤐🥴🤢🤮🤧😷🤒🤕".map { String($0) },
        "👋🤚🖐✋👌🤏✌️🤞🤟🤘🤙👈👉👆👇👍👎✊👊🤛🤜👏🙌👐🤲🤝🙏✍️💪🦾🦵🦶👂👃🧠🦷🦴👀👅👄💋👐".map { String($0) },
        "❤️🧡💛💚💙💜🖤🤍🤎💔❣️💕💞💓💗💖💘💝💟💌💐🌹🌺🌻🌼🌸💮🏵️⭐🌟✨⚡🔥💥💫🎉🎊🎈🎁🎀🎂🍰".map { String($0) },
        "🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🐔🐧🐦🐤🦆🦉🐴🦄🐝🐛🦋🐌🐞🐢🐍🦎🐙🦑🦐🐠🐟🐬🐳🦈🐊🐘🦒🦓🐪🐿️🦔🐾".map { String($0) },
        "🍎🍊🍋🍌🍉🍇🍓🍑🍒🍍🥭🥝🍅🥑🥦🥕🌽🌶️🥔🍠🥐🍞🧀🥚🍳🥞🧇🥓🍔🍟🍕🌮🌯🍜🍝🍣🍤🍦🍰☕🍵🍺🍻🥂🍷".map { String($0) },
        "⚽🏀🏈⚾🎾🏐🏉🎱🏓🏸🥅⛳🏹🎣🥊🥋🎽🛹🛷⛸️🥌🎿🏂🏄🏊🚴🏋️🤸🤼🤺🏆🥇🥈🥉🏅🎖️🎗️🎯🎮🎲🎰🧩🎨🎬🎤🎧🎼🎹🥁🎺🎻".map { String($0) },
        "✅❌⭕❗❓❔❕💯🔔🔕🔊📢📣💬💭💡🔍🔎🔑🔒🔓🔗📎📌📍📅📆📈📉📊📋📁📂✏️✒️📝📖📚📦📮📯📱💻⌚⏰⏳⏱️🌍🌎🌏☀️🌙⭐☁️☂️☃️🌈🌊".map { String($0) },
        ["(・∀・)", "(￣▽￣)", "(´･ᴗ･`)", "(｡•́︿•̀｡)", "ヽ(°▽°)ノ", "(๑•̀ㅂ•́)و✧", "(*´∀`)~♥", "(╯°□°）╯", "orz", "2333", "666", "hhh", "(=・ω・=)", "(｀・ω・´)", "(°ロ°)☝", "φ(≧ω≦*)♪"],
    ]

    // MARK: - 状态与视图

    private let engine = PinyinEngine.shared
    private let prefs = KeyboardPrefs.shared
    private let feedback = UISelectionFeedbackGenerator()

    private let candidateBar = UIView()
    private let composingLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let candidateScroll = UIScrollView()
    private let candidateStack = UIStackView()
    private let moreButton = UIButton(type: .system)

    private let keysArea = UIView()
    private let keysStack = UIStackView()
    private let emojiPanel = UIView()
    private let emojiSegment = UISegmentedControl()
    private var emojiCollection: UICollectionView?
    private let morePanel = UIView()
    private var moreCollection: UICollectionView?

    private let previewView = UILabel()
    private let extraPopup = ExtraPopup(frame: .zero)

    private var page: Page = .letters
    private var shifted = false
    private var chineseMode = true
    private var emojiCategory = 0
    private var moreVisible = false
    private var deleteTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
        rebuild()
        refreshCandidates()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        deleteTimer?.invalidate()
    }

    // MARK: - 外观

    private static func keyBase(_ function: Bool) -> UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return function ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.32, alpha: 1)
            }
            return function
                ? UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
                : .white
        }
    }

    private static func keyPressed(_ function: Bool) -> UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle == .dark { return UIColor(white: 0.50, alpha: 1) }
            return function ? .white : UIColor(white: 0.88, alpha: 1)
        }
    }

    // MARK: - 布局

    private func buildUI() {
        backgroundColor = .clear

        buildCandidateBar()
        buildKeysArea()
        buildEmojiPanel()
        buildMorePanel()

        previewView.textAlignment = .center
        previewView.font = .systemFont(ofSize: 27)
        previewView.textColor = .label
        previewView.backgroundColor = Self.keyBase(false)
        previewView.layer.cornerRadius = 7
        previewView.layer.shadowColor = UIColor.black.cgColor
        previewView.layer.shadowOpacity = 0.22
        previewView.layer.shadowOffset = CGSize(width: 0, height: 2)
        previewView.layer.shadowRadius = 4
        previewView.isHidden = true
        previewView.translatesAutoresizingMaskIntoConstraints = false

        extraPopup.isHidden = true
        extraPopup.translatesAutoresizingMaskIntoConstraints = false

        addSubview(candidateBar)
        addSubview(keysArea)
        addSubview(previewView)
        addSubview(extraPopup)
        NSLayoutConstraint.activate([
            candidateBar.topAnchor.constraint(equalTo: topAnchor),
            candidateBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: 40),

            keysArea.topAnchor.constraint(equalTo: candidateBar.bottomAnchor, constant: 6),
            keysArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            keysArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            keysArea.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        candidateBar.layer.zPosition = 1
    }

    private func buildCandidateBar() {
        composingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        composingLabel.textColor = .systemBlue
        composingLabel.lineBreakMode = .byTruncatingHead
        composingLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        composingLabel.translatesAutoresizingMaskIntoConstraints = false

        clearButton.setTitle("×", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 20)
        clearButton.setTitleColor(.secondaryLabel, for: .normal)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        candidateScroll.showsHorizontalScrollIndicator = false
        candidateScroll.alwaysBounceHorizontal = true
        candidateScroll.translatesAutoresizingMaskIntoConstraints = false

        candidateStack.axis = .horizontal
        candidateStack.alignment = .fill
        candidateStack.spacing = 0
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        candidateScroll.addSubview(candidateStack)
        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.trailingAnchor),
            candidateStack.topAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateScroll.frameLayoutGuide.heightAnchor),
        ])

        moreButton.setTitle("▾", for: .normal)
        moreButton.titleLabel?.font = .systemFont(ofSize: 17)
        moreButton.setTitleColor(.secondaryLabel, for: .normal)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)

        let hairline = UIView()
        hairline.backgroundColor = .separator
        hairline.translatesAutoresizingMaskIntoConstraints = false

        candidateBar.addSubview(composingLabel)
        candidateBar.addSubview(clearButton)
        candidateBar.addSubview(candidateScroll)
        candidateBar.addSubview(moreButton)
        candidateBar.addSubview(hairline)
        candidateBar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            composingLabel.leadingAnchor.constraint(equalTo: candidateBar.leadingAnchor, constant: 6),
            composingLabel.centerYAnchor.constraint(equalTo: candidateBar.centerYAnchor),
            composingLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 110),

            clearButton.leadingAnchor.constraint(equalTo: composingLabel.trailingAnchor, constant: 2),
            clearButton.centerYAnchor.constraint(equalTo: candidateBar.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 20),
            clearButton.heightAnchor.constraint(equalToConstant: 32),

            moreButton.trailingAnchor.constraint(equalTo: candidateBar.trailingAnchor, constant: -2),
            moreButton.centerYAnchor.constraint(equalTo: candidateBar.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 28),
            moreButton.heightAnchor.constraint(equalToConstant: 34),

            candidateScroll.leadingAnchor.constraint(equalTo: clearButton.trailingAnchor, constant: 2),
            candidateScroll.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -2),
            candidateScroll.topAnchor.constraint(equalTo: candidateBar.topAnchor),
            candidateScroll.bottomAnchor.constraint(equalTo: candidateBar.bottomAnchor),

            hairline.leadingAnchor.constraint(equalTo: candidateBar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: candidateBar.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: candidateBar.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    private func buildKeysArea() {
        keysStack.axis = .vertical
        keysStack.distribution = .fillEqually
        keysStack.spacing = 8
        keysStack.translatesAutoresizingMaskIntoConstraints = false

        keysArea.addSubview(keysStack)
        keysArea.addSubview(emojiPanel)
        keysArea.addSubview(morePanel)
        keysArea.translatesAutoresizingMaskIntoConstraints = false

        for panel in [keysStack, emojiPanel, morePanel] {
            NSLayoutConstraint.activate([
                panel.topAnchor.constraint(equalTo: keysArea.topAnchor),
                panel.leadingAnchor.constraint(equalTo: keysArea.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: keysArea.trailingAnchor),
                panel.bottomAnchor.constraint(equalTo: keysArea.bottomAnchor),
            ])
        }
        emojiPanel.isHidden = true
        morePanel.isHidden = true
        emojiPanel.backgroundColor = .clear
        morePanel.backgroundColor = .secondarySystemBackground
    }

    private func buildEmojiPanel() {
        emojiSegment.removeAllSegments()
        for (index, title) in TypingKeyboardView.emojiTitles.enumerated() {
            emojiSegment.insertSegment(withTitle: title, at: index, animated: false)
        }
        emojiSegment.selectedSegmentIndex = 0
        emojiSegment.selectedSegmentTintColor = .systemBlue
        emojiSegment.addTarget(self, action: #selector(emojiCategoryChanged), for: .valueChanged)
        emojiSegment.translatesAutoresizingMaskIntoConstraints = false

        let back = UIButton(type: .system)
        back.setTitle("ABC", for: .normal)
        back.titleLabel?.font = .systemFont(ofSize: 12)
        back.addTarget(self, action: #selector(backToLetters), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false

        let collection = makeCollection()
        emojiCollection = collection

        let header = UIView()
        header.addSubview(emojiSegment)
        header.addSubview(back)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emojiSegment.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            emojiSegment.trailingAnchor.constraint(equalTo: back.leadingAnchor, constant: -6),
            emojiSegment.topAnchor.constraint(equalTo: header.topAnchor),
            emojiSegment.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            back.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -4),
            back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 38),
        ])

        emojiPanel.addSubview(header)
        emojiPanel.addSubview(collection)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: emojiPanel.topAnchor),
            header.leadingAnchor.constraint(equalTo: emojiPanel.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: emojiPanel.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 30),
            collection.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            collection.leadingAnchor.constraint(equalTo: emojiPanel.leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: emojiPanel.trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: emojiPanel.bottomAnchor),
        ])
    }

    private func buildMorePanel() {
        let title = UILabel()
        title.text = "更多候选"
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = .secondaryLabel
        title.translatesAutoresizingMaskIntoConstraints = false

        let back = UIButton(type: .system)
        back.setTitle("返回", for: .normal)
        back.titleLabel?.font = .systemFont(ofSize: 13)
        back.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false

        let header = UIView()
        header.addSubview(title)
        header.addSubview(back)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            back.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        let collection = makeCollection()
        moreCollection = collection
        morePanel.addSubview(header)
        morePanel.addSubview(collection)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: morePanel.topAnchor),
            header.leadingAnchor.constraint(equalTo: morePanel.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: morePanel.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 30),
            collection.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            collection.leadingAnchor.constraint(equalTo: morePanel.leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: morePanel.trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: morePanel.bottomAnchor),
        ])
    }

    private func makeCollection() -> UICollectionView {
        let flow = UICollectionViewFlowLayout()
        flow.minimumLineSpacing = 0
        flow.minimumInteritemSpacing = 0
        flow.sectionInset = .zero
        let collection = UICollectionView(frame: .zero, collectionViewLayout: flow)
        collection.dataSource = self
        collection.delegate = self
        collection.backgroundColor = .clear
        collection.showsVerticalScrollIndicator = true
        collection.register(GridCell.self, forCellWithReuseIdentifier: "cell")
        collection.translatesAutoresizingMaskIntoConstraints = false
        return collection
    }

    // MARK: - 候选栏

    private func refreshCandidates() {
        for sub in candidateStack.arrangedSubviews {
            candidateStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        let fontSize = prefs.candidateFont
        if !engine.candidates.isEmpty {
            for (index, item) in engine.candidates.enumerated() {
                let button = makeCandidateButton(
                    item.word + (item.needsContinuation ? " ›" : ""),
                    tag: index, fontSize: fontSize, tint: .label
                )
                candidateStack.addArrangedSubview(button)
                addSeparator()
            }
        } else if !engine.suggestions.isEmpty {
            let tag = UILabel()
            tag.text = "联想"
            tag.font = .systemFont(ofSize: 11)
            tag.textColor = .systemBlue
            tag.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            candidateStack.addArrangedSubview(tag)
            addSeparator()
            for (index, word) in engine.suggestions.enumerated() {
                let button = makeCandidateButton(word, tag: index, fontSize: fontSize, tint: .label)
                candidateStack.addArrangedSubview(button)
                addSeparator()
            }
        } else {
            let hint = UILabel()
            hint.font = .systemFont(ofSize: 13)
            hint.textColor = .tertiaryLabel
            hint.text = chineseMode
                ? (engine.isEmpty ? "拼音输入 · 词库 \(engine.diagnostic)" : "暂无候选")
                : "英文直输"
            hint.setContentHuggingPriority(.defaultLow, for: .horizontal)
            candidateStack.addArrangedSubview(hint)
        }

        composingLabel.text = chineseMode ? engine.displayText : "EN"
        clearButton.isHidden = engine.isEmpty
        moreButton.isHidden = engine.candidates.isEmpty
        candidateScroll.setContentOffset(.zero, animated: false)
        if moreVisible { moreCollection?.reloadData() }
    }

    private func makeCandidateButton(_ title: String, tag: Int,
                                     fontSize: CGFloat, tint: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: fontSize)
        button.setTitleColor(tint, for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 11, bottom: 0, right: 11)
        button.tag = tag
        button.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
        return button
    }

    private func addSeparator() {
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        candidateStack.addArrangedSubview(separator)
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        let index = sender.tag
        if !engine.candidates.isEmpty {
            guard let word = engine.commit(at: index) else { return }
            insertWord(word)
        } else if index < engine.suggestions.count {
            let word = engine.suggestions[index]
            insertWord(word)
            engine.commitSuggestion(word)
        }
        refreshCandidates()
    }

    @objc private func clearTapped() {
        engine.clear()
        refreshCandidates()
    }

    @objc private func moreTapped() {
        guard !engine.candidates.isEmpty || moreVisible else { return }
        if page == .emoji { page = .letters }
        moreVisible.toggle()
        applyPanelVisibility()
        if moreVisible { moreCollection?.reloadData() }
    }

    private func applyPanelVisibility() {
        keysStack.isHidden = moreVisible || page == .emoji
        emojiPanel.isHidden = moreVisible || page != .emoji
        morePanel.isHidden = !moreVisible
    }

    func showEmoji() {
        page = .emoji
        moreVisible = false
        rebuild()
        refreshCandidates()
    }

    /// 工具条「更多」：展开候选宫格。没有拼音缓冲时直接忽略。
    func showMoreCandidates() {
        guard !engine.candidates.isEmpty else { return }
        if page == .emoji { page = .letters }
        moreVisible = true
        applyPanelVisibility()
        moreCollection?.reloadData()
    }

    func applySettings() {
        rebuild()
        refreshCandidates()
    }

    // MARK: - 键区

    private func rebuild() {
        for sub in keysStack.arrangedSubviews {
            keysStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        for specs in rowSpecs() {
            let row = KeyRow()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.weights = specs.map { $0.weight }
            row.items = specs.map { makeCap($0) }
            for item in row.items { row.addSubview(item) }
            keysStack.addArrangedSubview(row)
        }
        applyPanelVisibility()
    }

    private func rowSpecs() -> [[KeySpec]] {
        var rows: [[KeySpec]] = []
        let hints = prefs.keyHints

        switch page {
        case .letters:
            rows.append(Self.letterRows[0].enumerated().map { pair -> KeySpec in
                let letter = pair.element
                let digit = Self.numberHints[pair.offset]
                return KeySpec(shifted ? letter.uppercased() : letter,
                               .character(letter),
                               hint: hints ? digit : "",
                               extras: [digit, letter, letter.uppercased()])
            })

            var second: [KeySpec] = [KeySpec("", .spacer, 0.5)]
            second.append(contentsOf: Self.letterRows[1].enumerated().map { pair -> KeySpec in
                let letter = pair.element
                let mark = Self.row2Hints[pair.offset]
                return KeySpec(shifted ? letter.uppercased() : letter,
                               .character(letter),
                               hint: hints ? mark : "",
                               extras: [mark, letter, letter.uppercased()])
            })
            second.append(KeySpec("", .spacer, 0.5))
            rows.append(second)

            var third: [KeySpec] = [KeySpec("⇧", .shift, 1.5, function: true, size: 20)]
            third.append(contentsOf: Self.letterRows[2].enumerated().map { pair -> KeySpec in
                let letter = pair.element
                let mark = Self.row3Hints[pair.offset]
                return KeySpec(shifted ? letter.uppercased() : letter,
                               .character(letter),
                               hint: hints ? mark : "",
                               extras: [mark, letter, letter.uppercased()])
            })
            third.append(KeySpec("⌫", .delete, 1.5, function: true, size: 20))
            rows.append(third)

        case .numbers:
            rows.append(Self.numberTop.map { KeySpec($0, .insert($0), size: 22) })
            rows.append(Self.chinesePunctuation.map { KeySpec($0, .insert($0), size: 20) })
            var third: [KeySpec] = [KeySpec("，", .insert("，"), 1.5, function: true, size: 20)]
            third.append(contentsOf: Self.latinPunctuation.map { KeySpec($0, .insert($0), size: 20) })
            third.append(KeySpec("⌫", .delete, 1.5, function: true, size: 20))
            rows.append(third)

        case .symbols:
            rows.append(Self.symbolRow1.map { KeySpec($0, .insert($0), size: 19) })
            rows.append(Self.symbolRow2.map { KeySpec($0, .insert($0), size: 19) })
            var third: [KeySpec] = [KeySpec("⌫", .delete, 1, function: true, size: 19)]
            third.append(contentsOf: Self.symbolRow3.map { KeySpec($0, .insert($0), size: 19) })
            third.append(KeySpec("⌫", .delete, 1, function: true, size: 19))
            rows.append(third)

        case .emoji:
            break
        }

        // 底行：空格占 4.4 键宽，功能键比例与系统键盘一致。
        let firstTitle: String
        let firstPage: Page
        switch page {
        case .letters:
            firstTitle = "123"
            firstPage = .numbers
        case .numbers:
            firstTitle = "ABC"
            firstPage = .letters
        case .symbols:
            firstTitle = "123"
            firstPage = .numbers
        case .emoji:
            firstTitle = "ABC"
            firstPage = .letters
        }

        let secondTitle: String
        let secondPage: Page
        if page == .numbers {
            secondTitle = "符号"
            secondPage = .symbols
        } else if page == .symbols {
            secondTitle = "数字"
            secondPage = .numbers
        } else {
            secondTitle = chineseMode ? "中" : "En"
            secondPage = .letters
        }

        let firstKey = KeySpec(firstTitle, .page(firstPage), 1.4, function: true, size: 14)
        let secondKey: KeySpec = (page == .numbers || page == .symbols)
            ? KeySpec(secondTitle, .page(secondPage), 1.0, function: true, size: 13)
            : KeySpec(secondTitle, .language, 1.0, function: true, size: 15)

        rows.append([
            firstKey,
            secondKey,
            KeySpec("🌐", .next, 1.0, function: true, size: 18),
            KeySpec("空格", .space, 4.4, size: 15),
            KeySpec(enterTitle(), .enter, 2.2, function: true, size: 14),
        ])
        return rows
    }

    /// 回车键标题跟宿主输入框的 returnKeyType 走。用 == 比较而不是 switch，
    /// 因为 UITextInputTraits 的 returnKeyType 在不同 SDK 里可能是 optional requirement。
    private func enterTitle() -> String {
        guard let proxy = controller?.textDocumentProxy,
              let traits = proxy as? UITextInputTraits else { return "换行" }
        let type = traits.returnKeyType
        if type == .search { return "搜索" }
        if type == .go { return "前往" }
        if type == .send { return "发送" }
        return "换行"
    }

    private func makeCap(_ spec: KeySpec) -> UIView {
        if case .spacer = spec.kind {
            let spacer = UIView()
            spacer.isUserInteractionEnabled = false
            return spacer
        }
        let cap = KeyCap()
        cap.configure(spec, owner: self,
                      baseColor: Self.keyBase(spec.function),
                      pressedColor: Self.keyPressed(spec.function))
        return cap
    }

    // MARK: - 输入动作

    private func insertWord(_ word: String) {
        controller?.textDocumentProxy.insertText(word)
    }

    private func playFeedback() {
        if prefs.keyClick { UIDevice.current.playInputClick() }
        if prefs.haptic { feedback.selectionChanged() }
    }

    private func flushComposing() {
        if !engine.isEmpty {
            engine.clear()
            refreshCandidates()
        }
    }

    private func commitFirst() {
        if let word = engine.commit(at: 0) {
            insertWord(word)
        } else {
            let raw = engine.composing
            engine.clear()
            insertWord(raw)
        }
        refreshCandidates()
    }

    private func deleteOnce() {
        guard let proxy = controller?.textDocumentProxy else { return }
        if !engine.isEmpty {
            engine.delete()
            refreshCandidates()
        } else {
            proxy.deleteBackward()
        }
    }

    private func toggleChinese() {
        chineseMode.toggle()
        shifted = false
        engine.clear()
        rebuild()
        refreshCandidates()
    }

    private func startDeleteRepeat() {
        stopDeleteRepeat()
        let timer = Timer(timeInterval: 0.11, repeats: true) { [weak self] _ in
            self?.deleteOnce()
        }
        RunLoop.main.add(timer, forMode: .common)
        deleteTimer = timer
    }

    private func stopDeleteRepeat() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    // MARK: - KeyCap 回调

    private func capPressed(_ cap: KeyCap, _ down: Bool) {
        if down {
            if case .character(let value) = cap.spec.kind, page == .letters {
                showPreview(text: shifted ? value.uppercased() : value, for: cap)
            }
        } else {
            previewView.isHidden = true
        }
    }

    private func capSwipedUp(_ cap: KeyCap) {
        guard !cap.spec.hint.isEmpty else { return }
        flushComposing()
        insertWord(cap.spec.hint)
        showPreview(text: cap.spec.hint, for: cap)
        playFeedback()
    }

    private func capLongBegan(_ cap: KeyCap) {
        switch cap.spec.kind {
        case .delete:
            deleteOnce()
            startDeleteRepeat()
        case .space:
            toggleChinese()
        case .character:
            showExtraPopup(cap, cap.spec.extras)
        default:
            break
        }
    }

    private func capLongMoved(_ cap: KeyCap, point: CGPoint) {
        guard !extraPopup.isHidden else { return }
        let local = convert(point, to: extraPopup)
        extraPopup.selected = extraPopup.indexForLocal(local)
    }

    private func capLongEnded(_ cap: KeyCap, point: CGPoint) {
        stopDeleteRepeat()
        guard !extraPopup.isHidden else { return }
        let local = convert(point, to: extraPopup)
        let index = extraPopup.indexForLocal(local)
        if index >= 0, index < extraPopup.items.count {
            flushComposing()
            insertWord(extraPopup.items[index])
        }
        extraPopup.isHidden = true
    }

    private func capTapped(_ cap: KeyCap) {
        playFeedback()
        guard let proxy = controller?.textDocumentProxy else { return }
        let spec = cap.spec
        switch spec.kind {
        case .character(let value):
            if chineseMode && page == .letters {
                engine.append(value.lowercased())
                refreshCandidates()
            } else {
                flushComposing()
                proxy.insertText((page == .letters && shifted) ? value.uppercased() : value)
                if shifted {
                    shifted = false
                    rebuild()
                }
            }
        case .insert(let value):
            flushComposing()
            proxy.insertText(value)
        case .delete:
            deleteOnce()
        case .space:
            if !engine.isEmpty {
                commitFirst()
            } else {
                proxy.insertText(" ")
            }
        case .enter:
            if !engine.isEmpty {
                commitFirst()
            } else {
                proxy.insertText("\n")
            }
        case .shift:
            shifted.toggle()
            rebuild()
        case .language:
            toggleChinese()
        case .page(let target):
            page = target
            shifted = false
            moreVisible = false
            flushComposing()
            rebuild()
            refreshCandidates()
        case .next:
            flushComposing()
            controller?.switchToNextKeyboard()
        case .more:
            moreTapped()
        case .spacer:
            break
        }
    }

    private func showPreview(text: String, for cap: KeyCap) {
        previewView.text = text
        let rect = cap.convert(cap.bounds, to: self)
        let width = max(46, rect.width + 16)
        var x = rect.midX - width / 2
        x = max(2, min(x, bounds.width - width - 2))
        previewView.frame = CGRect(x: x, y: max(0, rect.minY - 46),
                                   width: width, height: 44)
        previewView.isHidden = false
        bringSubviewToFront(previewView)
    }

    private func showExtraPopup(_ cap: KeyCap, _ items: [String]) {
        guard items.count > 1 else { return }
        extraPopup.items = items
        extraPopup.selected = 0
        let rect = cap.convert(cap.bounds, to: self)
        let width = CGFloat(items.count) * 42
        var x = rect.midX - width / 2
        x = max(4, min(x, bounds.width - width - 4))
        extraPopup.frame = CGRect(x: x, y: max(2, rect.minY - 48),
                                  width: width, height: 44)
        extraPopup.isHidden = false
        previewView.isHidden = true
        bringSubviewToFront(extraPopup)
    }

    // MARK: - 表情与更多候选

    @objc private func emojiCategoryChanged() {
        emojiCategory = max(0, emojiSegment.selectedSegmentIndex)
        emojiCollection?.reloadData()
        emojiCollection?.setContentOffset(.zero, animated: false)
    }

    @objc private func backToLetters() {
        page = .letters
        rebuild()
        refreshCandidates()
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        if collectionView === emojiCollection {
            guard emojiCategory < TypingKeyboardView.emojiGroups.count else { return 0 }
            return TypingKeyboardView.emojiGroups[emojiCategory].count
        }
        return engine.candidates.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "cell", for: indexPath
        ) as? GridCell else {
            return UICollectionViewCell()
        }
        if collectionView === emojiCollection {
            cell.label.font = .systemFont(ofSize: 24)
            if emojiCategory < TypingKeyboardView.emojiGroups.count,
               indexPath.item < TypingKeyboardView.emojiGroups[emojiCategory].count {
                cell.label.text = TypingKeyboardView.emojiGroups[emojiCategory][indexPath.item]
            } else {
                cell.label.text = ""
            }
        } else {
            cell.label.font = .systemFont(ofSize: prefs.candidateFont)
            if indexPath.item < engine.candidates.count {
                let item = engine.candidates[indexPath.item]
                cell.label.text = item.word + (item.needsContinuation ? " ›" : "")
            } else {
                cell.label.text = ""
            }
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns: CGFloat = (collectionView === emojiCollection) ? 8 : 4
        let width = floor(max(1, collectionView.bounds.width) / columns)
        return CGSize(width: width, height: 40)
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        if collectionView === emojiCollection {
            guard emojiCategory < TypingKeyboardView.emojiGroups.count,
                  indexPath.item < TypingKeyboardView.emojiGroups[emojiCategory].count else { return }
            flushComposing()
            insertWord(TypingKeyboardView.emojiGroups[emojiCategory][indexPath.item])
        } else {
            guard let word = engine.commit(at: indexPath.item) else { return }
            insertWord(word)
            moreVisible = false
            applyPanelVisibility()
            refreshCandidates()
        }
    }
}

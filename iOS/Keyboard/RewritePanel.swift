import UIKit

/// One version in the ✨ picker.
enum RewriteVersion: Equatable {
    case loading
    case done(Rewrite)
    case failed
}

/// The ✨ picker, over the whole keyboard: the selection proofread, in Hieu's voice and Natural, one card each in that
/// order (no style names on them, Hieu), filling in as each answer comes. The proofread card marks what changed from the
/// original (removed struck through, added highlighted); Natural's punchier alternative, when there is one, is a card
/// of its own. A tap on a finished card puts its plain text in place of the selection; a tap on a failed one asks again; Cancel, top right on the title's line (Hieu), keeps the original.
/// VI | EN, just left of Cancel (Hieu), asks all three again in the other language; ↻ (More), left of that, asks all
/// three again for versions unlike the ones already shown. Nothing changes in the app before a tap.
final class RewritePanel: UIView {
    var onPick: ((RewriteStyle) -> Void)?
    var onPickAlternative: ((RewriteStyle) -> Void)?
    var onCancel: (() -> Void)?
    var onToggleLanguage: (() -> Void)?
    var onMore: (() -> Void)?
    var dark = false { didSet { restyle() } }
    /// The versions' language: the lit half of VI | EN.
    var vietnamese = true { didSet { restyle(); setNeedsLayout() } }
    /// The selection the versions rewrite: the proofread card's diff is against it.
    var original = "" { didSet { restyle(); setNeedsLayout() } }
    private(set) var versions: [RewriteVersion] = Array(repeating: .loading, count: RewriteStyle.allCases.count)
    private let title = UILabel()
    private let scroll = UIScrollView()
    private var cards: [Card] = []          // one per style, each followed by its alternative's (hidden when none)
    private let cancel = UIButton(type: .system)
    private let language = UIButton(type: .custom)
    private let more = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.text = "✨ " + String(localized: "Viết lại").uppercased()
        scroll.showsVerticalScrollIndicator = true
        scroll.alwaysBounceVertical = true
        scroll.contentInsetAdjustmentBehavior = .never
        if #available(iOS 26.0, *) {   // no soft blur where the cards meet the title (iOS 26's scroll edge effect)
            scroll.topEdgeEffect.isHidden = true
            scroll.bottomEdgeEffect.isHidden = true
        }
        for style in RewriteStyle.allCases {
            for alt in [false, true] {
                let c = Card(style: style, alternative: alt)
                c.addTarget(self, action: #selector(tapCard(_:)), for: .touchUpInside)
                c.accessibilityIdentifier = "rewrite.\(style)" + (alt ? ".alternative" : "")
                scroll.addSubview(c); cards.append(c)
            }
        }
        cancel.setTitle(String(localized: "Huỷ"), for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cancel.layer.cornerRadius = 15; cancel.layer.cornerCurve = .continuous
        cancel.accessibilityIdentifier = "rewrite.cancel"
        cancel.addTarget(self, action: #selector(tapCancel), for: .touchUpInside)
        language.layer.cornerRadius = 15; language.layer.cornerCurve = .continuous
        language.accessibilityIdentifier = "rewrite.language"
        language.accessibilityLabel = String(localized: "Ngôn ngữ viết lại")
        language.accessibilityHint = String(localized: "Viết lại bằng ngôn ngữ kia")
        language.addTarget(self, action: #selector(tapLanguage), for: .touchUpInside)
        more.setImage(UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        more.layer.cornerRadius = 15; more.layer.cornerCurve = .continuous
        more.accessibilityIdentifier = "rewrite.more"
        more.accessibilityLabel = String(localized: "Viết bản khác")
        more.addTarget(self, action: #selector(tapMore), for: .touchUpInside)
        [title, scroll, more, language, cancel].forEach(addSubview)
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ versions: [RewriteVersion]) {
        self.versions = versions
        restyle()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let W = bounds.width, M: CGFloat = 12
        // Cancel: a pill on the title's line, right-aligned with the cards
        let cw0 = ceil(cancel.titleLabel?.intrinsicContentSize.width ?? 40) + 28
        cancel.frame = CGRect(x: W - M - cw0, y: 8, width: cw0, height: 30)
        // VI | EN: a pill of the same height, just left of Cancel
        let lw = ceil(language.titleLabel?.intrinsicContentSize.width ?? 50) + 28
        language.frame = CGRect(x: cancel.frame.minX - 8 - lw, y: 8, width: lw, height: 30)
        // ↻: a round pill of the same height, just left of VI | EN
        more.frame = CGRect(x: language.frame.minX - 8 - 44, y: 8, width: 44, height: 30)
        title.frame = CGRect(x: M + 4, y: 14, width: max(0, more.frame.minX - M - 12), height: 18)
        scroll.frame = CGRect(x: 0, y: 46, width: W, height: max(0, bounds.height - 46))
        scroll.contentInset.bottom = 8
        var y: CGFloat = 0
        let cw = W - 2 * M
        for c in cards where !c.isHidden {
            let h = c.height(forWidth: cw)
            c.frame = CGRect(x: M, y: y, width: cw, height: h)
            y += h + 8
        }
        scroll.contentSize = CGSize(width: W, height: max(0, y - 8))
    }

    private func restyle() {
        let fg: UIColor = dark ? .white : .black
        title.textColor = dark ? UIColor(white: 1, alpha: 0.6) : UIColor(white: 0, alpha: 0.5)
        let key = dark ? UIColor(white: 1, alpha: 0.165) : UIColor(red: 0.992, green: 1, blue: 1, alpha: 0.99)
        cancel.backgroundColor = key
        cancel.setTitleColor(fg, for: .normal)
        language.backgroundColor = key
        more.backgroundColor = key
        more.tintColor = fg
        language.setAttributedTitle(languageTitle(fg), for: .normal)
        language.setAttributedTitle(languageTitle(fg.withAlphaComponent(0.5)), for: .highlighted)
        language.accessibilityValue = vietnamese ? "Tiếng Việt" : "English"
        for c in cards {
            let i = c.style.rawValue
            c.set(i < versions.count ? versions[i] : .loading, original: original, dark: dark, background: key)
        }
    }

    @objc private func tapCard(_ c: Card) { c.alternative ? onPickAlternative?(c.style) : onPick?(c.style) }
    @objc private func tapCancel() { onCancel?() }
    @objc private func tapLanguage() { onToggleLanguage?() }
    @objc private func tapMore() { onMore?() }

    /// "VI | EN" with the versions' language lit and the other one faint.
    private func languageTitle(_ fg: UIColor) -> NSAttributedString {
        let on: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: fg]
        let off: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: fg.withAlphaComponent(0.35)]
        let s = NSMutableAttributedString(string: "VI", attributes: vietnamese ? on : off)
        s.append(NSAttributedString(string: "  |  ", attributes: off))
        s.append(NSAttributedString(string: "EN", attributes: vietnamese ? off : on))
        return s
    }

    /// One style: the rewritten text (proofread: with its changes marked), "Writing…" with a spinner, or "Couldn't
    /// rewrite · Retry"; or that style's alternative, shown only when there is one. VoiceOver still reads the style's name.
    private final class Card: UIControl {
        let style: RewriteStyle
        let alternative: Bool
        private let body = UILabel()
        private let spinner = UIActivityIndicatorView(style: .medium)
        private static let pad: CGFloat = 12

        init(style: RewriteStyle, alternative: Bool) {
            self.style = style
            self.alternative = alternative
            super.init(frame: .zero)
            layer.cornerRadius = 12; layer.cornerCurve = .continuous
            isAccessibilityElement = true
            body.font = .systemFont(ofSize: 17)
            body.numberOfLines = 0
            spinner.hidesWhenStopped = true
            [body, spinner].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
        }
        required init?(coder: NSCoder) { fatalError() }

        func set(_ v: RewriteVersion, original: String, dark: Bool, background: UIColor) {
            let fg: UIColor = dark ? .white : .black
            backgroundColor = background
            spinner.color = fg
            if alternative {   // only a finished version's alternative
                guard case .done(let r) = v, let alt = r.alternative else { isHidden = true; return }
                isHidden = false
                body.text = alt.trimmingCharacters(in: .whitespacesAndNewlines); body.textColor = fg
                spinner.stopAnimating(); isEnabled = true
                accessibilityLabel = style.title + ", " + String(localized: "bản khác") + ", " + (body.text ?? "")
                setNeedsLayout()
                return
            }
            switch v {
            case .loading:
                body.text = String(localized: "Đang viết…"); body.textColor = fg.withAlphaComponent(0.45)
                spinner.startAnimating(); isEnabled = false
            case .done(let r):
                let text = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                body.text = text; body.textColor = fg
                if style == .proofread {
                    body.attributedText = RewriteDiff.attributed(original.trimmingCharacters(in: .whitespacesAndNewlines), text,
                                                                 font: body.font, fg: fg, dark: dark)
                }
                spinner.stopAnimating(); isEnabled = true
            case .failed:
                body.text = String(localized: "Không viết lại được · Thử lại"); body.textColor = fg.withAlphaComponent(0.6)
                spinner.stopAnimating(); isEnabled = true
            }
            if case .done(let r) = v {   // the version itself, not the struck-through words
                accessibilityLabel = style.title + ", " + r.text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else { accessibilityLabel = style.title + ", " + (body.text ?? "") }
            setNeedsLayout()
        }

        /// The text's width: room for the spinner on the right while loading.
        private func textWidth(_ w: CGFloat) -> CGFloat { w - 2 * Self.pad - (spinner.isAnimating ? 28 : 0) }

        private func bodyHeight(_ w: CGFloat) -> CGFloat {
            max(22, ceil(body.sizeThatFits(CGSize(width: textWidth(w), height: .greatestFiniteMagnitude)).height))
        }
        func height(forWidth w: CGFloat) -> CGFloat { Self.pad + bodyHeight(w) + Self.pad }

        override func layoutSubviews() {
            super.layoutSubviews()
            body.frame = CGRect(x: Self.pad, y: Self.pad, width: textWidth(bounds.width), height: bodyHeight(bounds.width))
            spinner.center = CGPoint(x: bounds.width - Self.pad - 10, y: bounds.midY)
        }

        override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }
    }
}

/// The proofread card's view of what changed: a word-level diff of the version against the original, with removed
/// words struck through in red and added ones highlighted in green. Only the card shows it; the plain version goes in.
enum RewriteDiff {
    enum Part: Equatable { case same(String), removed(String), added(String) }

    /// Words, runs of spaces, and each punctuation mark on its own ("file." → "file", "."), so a fixed comma shows
    /// as just the comma.
    static func tokens(_ s: String) -> [String] {
        enum Kind { case word, space, mark }
        func kind(_ c: Character) -> Kind { c.isWhitespace ? .space : (c.isLetter || c.isNumber) ? .word : .mark }
        var out: [String] = [], cur = "", curKind: Kind?
        for c in s {
            let k = kind(c)
            if !cur.isEmpty, k != curKind || k == .mark { out.append(cur); cur = "" }
            cur.append(c); curKind = k
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// The longest common run of tokens kept as is; the rest removed or added.
    static func parts(_ original: String, _ revised: String) -> [Part] {
        let a = tokens(original), b = tokens(revised), n = a.count, m = b.count
        guard n * m <= 250_000 else { return original == revised ? [.same(original)] : [.removed(original), .added(revised)] }
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [Part] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] { out.append(.same(a[i])); i += 1; j += 1 }
            else if j >= m || (i < n && lcs[i + 1][j] >= lcs[i][j + 1]) { out.append(.removed(a[i])); i += 1 }
            else { out.append(.added(b[j])); j += 1 }
        }
        // a space kept between two changes goes inside them: "~~toi di~~ tôi đi", not "~~toi~~ tôi ~~di~~ đi"
        var spaced: [Part] = []
        for (k, p) in out.enumerated() {
            if case .same(let sp) = p, sp.allSatisfy(\.isWhitespace), k > 0, k + 1 < out.count,
               !isSame(out[k - 1]), !isSame(out[k + 1]) {
                let around = [out[k - 1], out[k + 1]]
                if around.contains(where: { if case .removed = $0 { return true } else { return false } }) { spaced.append(.removed(sp)) }
                if around.contains(where: { if case .added = $0 { return true } else { return false } }) { spaced.append(.added(sp)) }
            } else { spaced.append(p) }
        }
        return merge(spaced)
    }
    private static func isSame(_ p: Part) -> Bool { if case .same = p { return true } else { return false } }
    /// Neighbouring parts joined: within each run of changes, one removal then one addition.
    private static func merge(_ parts: [Part]) -> [Part] {
        var out: [Part] = [], removed = "", added = ""
        func flush() {
            if !removed.isEmpty { out.append(.removed(removed)) }
            if !added.isEmpty { out.append(.added(added)) }
            removed = ""; added = ""
        }
        for p in parts {
            switch p {
            case .same(let t):
                flush()
                if case .same(let x)? = out.last { out[out.count - 1] = .same(x + t) } else { out.append(p) }
            case .removed(let s): removed += s
            case .added(let s): added += s
            }
        }
        flush()
        return out
    }

    static func attributed(_ original: String, _ revised: String, font: UIFont, fg: UIColor, dark: Bool) -> NSAttributedString {
        let s = NSMutableAttributedString()
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
        let removed: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.systemRed.withAlphaComponent(0.85),
                                                     .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                                     .strikethroughColor: UIColor.systemRed]
        let added: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg,
                                                   .backgroundColor: UIColor.systemGreen.withAlphaComponent(dark ? 0.4 : 0.25)]
        let parts = parts(original, revised)
        for (i, p) in parts.enumerated() {
            switch p {
            case .same(let t): s.append(NSAttributedString(string: t, attributes: plain))
            case .removed(let t):
                s.append(NSAttributedString(string: t, attributes: removed))
                if i + 1 < parts.count, case .added = parts[i + 1] { s.append(NSAttributedString(string: " ", attributes: plain)) }
            case .added(let t): s.append(NSAttributedString(string: t, attributes: added))
            }
        }
        return s
    }
}

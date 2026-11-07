import UIKit

/// The ✨ key's rewrites, over the whole keyboard like the proofread preview: one card per style, filled in as
/// Apple Intelligence answers. A tap on a card puts it in place of the selection; Cancel where the bottom row was.
final class RewritePanel: UIView {
    enum Draft: Equatable { case working, done(String), failed }

    var onPick: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    var dark = false { didSet { if dark != oldValue { restyle() } } }
    private let title = UILabel()
    private let scroll = UIScrollView()
    private let cancel = UIButton(type: .system)
    private var cards: [Card] = []
    private var drafts: [Draft] = []

    init(styles: [String]) {
        super.init(frame: .zero)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.text = "✨ " + String(localized: "Viết lại").uppercased()
        scroll.showsVerticalScrollIndicator = true
        scroll.alwaysBounceVertical = false
        cancel.setTitle(String(localized: "Huỷ"), for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancel.layer.cornerRadius = 8.5; cancel.layer.cornerCurve = .continuous
        cancel.accessibilityIdentifier = "rewrite.cancel"
        cancel.addTarget(self, action: #selector(tapCancel), for: .touchUpInside)
        for (i, s) in styles.enumerated() {
            let c = Card()
            c.style.text = s
            c.tag = i
            c.accessibilityIdentifier = "rewrite.card.\(i)"
            c.addTarget(self, action: #selector(tapCard(_:)), for: .touchUpInside)
            cards.append(c); scroll.addSubview(c)
        }
        drafts = Array(repeating: .working, count: styles.count)
        [title, scroll, cancel].forEach(addSubview)
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ drafts: [Draft]) {
        guard drafts != self.drafts else { return }
        self.drafts = drafts
        restyle()
        setNeedsLayout()
    }

    /// What a card says now (tests).
    func text(at i: Int) -> String? { i < cards.count ? cards[i].body.text : nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Cancel sits where the bottom row of keys is: the same side margin, height and bottom inset
        let W = bounds.width, side: CGFloat = 6.67, M: CGFloat = 16, gap: CGFloat = 6
        let bh: CGFloat = KeyboardView.tallKeys ? 45 : 43, bottom: CGFloat = KeyboardView.tallKeys ? 5.67 : 3
        let by = bounds.height - bh - bottom
        title.frame = CGRect(x: M, y: 14, width: W - 2 * M, height: 18)
        cancel.frame = CGRect(x: side, y: by, width: W - 2 * side, height: bh)
        scroll.frame = CGRect(x: 0, y: 38, width: W, height: max(0, by - 38 - gap))
        let cw = max(0, W - 2 * side)
        var y: CGFloat = 0
        for c in cards {
            let h = c.height(forWidth: cw)
            c.frame = CGRect(x: side, y: y, width: cw, height: h)
            y += h + gap
        }
        scroll.contentSize = CGSize(width: W, height: max(0, y - gap))
    }

    private func restyle() {
        let fg: UIColor = dark ? .white : .black
        let brand = dark ? UIColor(red: 0.62, green: 0.60, blue: 1, alpha: 1) : UIColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1)
        let key: UIColor = dark ? UIColor(white: 1, alpha: 0.165) : UIColor(red: 0.992, green: 1, blue: 1, alpha: 0.99)
        title.textColor = dark ? UIColor(white: 1, alpha: 0.6) : UIColor(white: 0, alpha: 0.5)
        cancel.backgroundColor = key
        cancel.setTitleColor(fg, for: .normal)
        for (i, c) in cards.enumerated() {
            c.backgroundColor = key
            c.style.textColor = brand
            let d: Draft = i < drafts.count ? drafts[i] : .working
            switch d {
            case .working:
                c.body.text = String(localized: "Đang viết…"); c.body.textColor = fg.withAlphaComponent(0.45); c.isEnabled = false
            case .failed:
                c.body.text = String(localized: "Không viết được"); c.body.textColor = fg.withAlphaComponent(0.45); c.isEnabled = false
            case .done(let t):
                c.body.text = t.trimmingCharacters(in: .whitespacesAndNewlines); c.body.textColor = fg; c.isEnabled = true
            }
            c.accessibilityLabel = (c.style.text ?? "") + ": " + (c.body.text ?? "")
        }
    }

    @objc private func tapCard(_ c: Card) { onPick?(c.tag) }
    @objc private func tapCancel() { onCancel?() }

    /// One style: its name in the brand colour, then the whole rewrite.
    final class Card: UIControl {
        let style = UILabel(), body = UILabel()
        private static let pad: CGFloat = 12, top: CGFloat = 9, styleH: CGFloat = 16, bottom: CGFloat = 10

        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.cornerRadius = 8.5; layer.cornerCurve = .continuous
            isAccessibilityElement = true; accessibilityTraits = .button
            style.font = .systemFont(ofSize: 12, weight: .semibold)
            body.font = .systemFont(ofSize: 16)
            body.numberOfLines = 0
            [style, body].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
        }
        required init?(coder: NSCoder) { fatalError() }

        override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.55 : 1 } }

        func height(forWidth w: CGFloat) -> CGFloat {
            let tw = max(0, w - 2 * Self.pad)
            let th = ceil(body.sizeThatFits(CGSize(width: tw, height: .greatestFiniteMagnitude)).height)
            return Self.top + Self.styleH + 2 + th + Self.bottom
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let tw = max(0, bounds.width - 2 * Self.pad)
            style.frame = CGRect(x: Self.pad, y: Self.top, width: tw, height: Self.styleH)
            let y = Self.top + Self.styleH + 2
            body.frame = CGRect(x: Self.pad, y: y, width: tw, height: max(0, bounds.height - y - Self.bottom))
        }
    }
}

import UIKit

/// One version in the ✨ picker.
enum RewriteVersion: Equatable {
    case loading
    case done(String)
    case failed
}

/// The ✨ picker, over the whole keyboard: the selection rewritten Polished, Funny and Engaging, one card each in that
/// order (no style names on them, Hieu), filling in as each answer comes. A tap on a finished card puts it in place of
/// the selection; a tap on a failed one asks again; Cancel, top right on the title's line (Hieu), keeps the original.
/// Nothing changes in the app before a tap.
final class RewritePanel: UIView {
    var onPick: ((RewriteStyle) -> Void)?
    var onCancel: (() -> Void)?
    var dark = false { didSet { restyle() } }
    private(set) var versions: [RewriteVersion] = Array(repeating: .loading, count: RewriteStyle.allCases.count)
    private let title = UILabel()
    private let scroll = UIScrollView()
    private var cards: [Card] = []
    private let cancel = UIButton(type: .system)

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
            let c = Card(style: style)
            c.addTarget(self, action: #selector(tapCard(_:)), for: .touchUpInside)
            c.accessibilityIdentifier = "rewrite.\(style)"
            scroll.addSubview(c); cards.append(c)
        }
        cancel.setTitle(String(localized: "Huỷ"), for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cancel.layer.cornerRadius = 15; cancel.layer.cornerCurve = .continuous
        cancel.accessibilityIdentifier = "rewrite.cancel"
        cancel.addTarget(self, action: #selector(tapCancel), for: .touchUpInside)
        [title, scroll, cancel].forEach(addSubview)
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
        title.frame = CGRect(x: M + 4, y: 14, width: cancel.frame.minX - M - 12, height: 18)
        scroll.frame = CGRect(x: 0, y: 46, width: W, height: max(0, bounds.height - 46))
        scroll.contentInset.bottom = 8
        var y: CGFloat = 0
        let cw = W - 2 * M
        for c in cards {
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
        for (i, c) in cards.enumerated() { c.set(i < versions.count ? versions[i] : .loading, dark: dark, background: key) }
    }

    @objc private func tapCard(_ c: Card) { onPick?(c.style) }
    @objc private func tapCancel() { onCancel?() }

    /// One style: the rewritten text, "Writing…" with a spinner, or "Couldn't rewrite · Retry". VoiceOver still
    /// reads the style's name.
    private final class Card: UIControl {
        let style: RewriteStyle
        private let body = UILabel()
        private let spinner = UIActivityIndicatorView(style: .medium)
        private static let pad: CGFloat = 12

        init(style: RewriteStyle) {
            self.style = style
            super.init(frame: .zero)
            layer.cornerRadius = 12; layer.cornerCurve = .continuous
            isAccessibilityElement = true
            body.font = .systemFont(ofSize: 17)
            body.numberOfLines = 0
            spinner.hidesWhenStopped = true
            [body, spinner].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
        }
        required init?(coder: NSCoder) { fatalError() }

        func set(_ v: RewriteVersion, dark: Bool, background: UIColor) {
            let fg: UIColor = dark ? .white : .black
            backgroundColor = background
            spinner.color = fg
            switch v {
            case .loading:
                body.text = String(localized: "Đang viết…"); body.textColor = fg.withAlphaComponent(0.45)
                spinner.startAnimating(); isEnabled = false
            case .done(let t):
                body.text = t.trimmingCharacters(in: .whitespacesAndNewlines); body.textColor = fg
                spinner.stopAnimating(); isEnabled = true
            case .failed:
                body.text = String(localized: "Không viết lại được · Thử lại"); body.textColor = fg.withAlphaComponent(0.6)
                spinner.stopAnimating(); isEnabled = true
            }
            accessibilityLabel = style.title + ", " + (body.text ?? "")
            setNeedsLayout()
        }

        /// The text's width: room for the spinner on the right while loading.
        private func textWidth(_ w: CGFloat) -> CGFloat { w - 2 * Self.pad - (spinner.isAnimating ? 28 : 0) }

        func height(forWidth w: CGFloat) -> CGFloat {
            let bodyH = body.sizeThatFits(CGSize(width: textWidth(w), height: .greatestFiniteMagnitude)).height
            return Self.pad + max(22, ceil(bodyH)) + Self.pad
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            body.frame = CGRect(x: Self.pad, y: Self.pad, width: textWidth(bounds.width), height: bounds.height - Self.pad * 2)
            spinner.center = CGPoint(x: bounds.width - Self.pad - 10, y: bounds.midY)
        }

        override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }
    }
}

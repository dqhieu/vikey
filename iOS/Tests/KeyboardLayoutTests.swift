import XCTest
import UIKit

/// Field-specific layouts like the system keyboard (email, URL, web search, number pads), rendered for a look.
final class KeyboardLayoutTests: XCTestCase {
    private func render(_ type: UIKeyboardType, layer: KeyboardView.Layer = .letters, _ name: String) -> KeyboardView {
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.fieldType = type
        kb.layer_ = layer
        kb.backgroundColor = UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
        kb.layoutIfNeeded()
        let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { ctx in kb.layer.render(in: ctx.cgContext) }
        try? FileManager.default.createDirectory(atPath: "/tmp/claude-501/layouts", withIntermediateDirectories: true)
        try? img.pngData()?.write(to: URL(fileURLWithPath: "/tmp/claude-501/layouts/\(name).png"))
        return kb
    }
    private func titles(_ kb: KeyboardView) -> [String] { kb.subviews.compactMap { ($0 as? KeyCap)?.label.text } }

    /// Paste takes the emoji key's place in the bottom row, and is in email, URL, web search and Twitter fields too.
    func testPasteReplacesEmoji() {
        func caps(_ kb: KeyboardView, symbol: String) -> [KeyCap] {   // a symbol image's description names it
            kb.subviews.compactMap { $0 as? KeyCap }.filter { $0.icon.image?.description.contains("system: \(symbol)") == true }
        }
        for layer in [KeyboardView.Layer.letters, .numbers, .symbols] {
            let kb = render(.default, layer: layer, "paste_\(layer)")
            let paste = caps(kb, symbol: "clipboard")
            XCTAssertEqual(paste.count, 1, "\(layer): one Paste key")
            XCTAssertGreaterThan(paste.first?.frame.minY ?? 0, 150, "\(layer): in the bottom row")
            XCTAssertTrue(caps(kb, symbol: "face.smiling").isEmpty, "\(layer): no emoji key")
        }
        // email, URL, web search (Safari's address bar) and Twitter fields keep Paste, with a usable space bar
        for (type, name) in [(UIKeyboardType.emailAddress, "email"), (.URL, "url"), (.webSearch, "websearch"), (.twitter, "twitter")] {
            let kb = render(type, "paste_\(name)")
            XCTAssertEqual(caps(kb, symbol: "clipboard").count, 1, "\(name): one Paste key")
            if let space = kb.subviews.compactMap({ $0 as? KeyCap }).first(where: { $0.label.text == kb.languageTitle }) {
                XCTAssertGreaterThanOrEqual(space.frame.width, 40, "\(name): the space bar still fits")
                // too narrow for "Tiếng Việt" (email, Twitter): a blank bar, not a cut-off name
                XCTAssertEqual(space.label.isHidden, space.frame.width < KeyboardView.spaceLabelMinWidth, "\(name): space label")
            } else if type != .URL { XCTFail("\(name): a space bar") }
        }
        let plain = render(.default, "paste_default_space")
        XCTAssertEqual(plain.subviews.compactMap { $0 as? KeyCap }.first { $0.label.text == plain.languageTitle }?.label.isHidden, false,
                       "the normal space bar keeps its label")
        let mail = render(.emailAddress, "paste_email_space")
        XCTAssertEqual(mail.subviews.compactMap { $0 as? KeyCap }.first { $0.label.text == mail.languageTitle }?.label.isHidden, true,
                       "email: the narrow space bar shows no label")
        // next to a globe key (Touch ID iPhones) there is no room: those fields go without Paste
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 375, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.showsGlobe = true; kb.fieldType = .emailAddress
        kb.layoutIfNeeded()
        XCTAssertTrue(caps(kb, symbol: "clipboard").isEmpty, "email with a globe key: no Paste")
    }

    /// VI/EN sits in the bottom row right after Paste, with the suggestion strip on or off.
    func testLanguageKeyNextToPaste() {
        KeyboardView.langStyle = 0
        defer { KeyboardView.barOn = false }
        for bar in [true, false] {
            KeyboardView.barOn = bar
            let kb = render(.default, bar ? "language_strip" : "language_nostrip")
            let caps = kb.subviews.compactMap { $0 as? KeyCap }.filter { !$0.isHidden }
            let bottom = caps.map(\.frame.minY).max() ?? 0
            let row = caps.filter { abs($0.frame.minY - bottom) < 1 }.sorted { $0.frame.minX < $1.frame.minX }
            let paste = row.firstIndex { $0.icon.image?.description.contains("system: clipboard") == true }
            let language = row.firstIndex { $0.label.text == "VI" }
            XCTAssertNotNil(paste, "strip \(bar): Paste in the bottom row")
            XCTAssertEqual(language, paste.map { $0 + 1 }, "strip \(bar): VI right after Paste")
            XCTAssertTrue(kb.mark.isHidden, "strip \(bar): no corner pill")
        }
    }

    func testEmailHasAtAndDot() { let t = titles(render(.emailAddress, "email")); XCTAssertTrue(t.contains("@") && t.contains(".")) }
    func testURLHasSlashAndDotCom() { let t = titles(render(.URL, "url")); XCTAssertTrue(t.contains("/") && t.contains(".com")) }
    func testWebSearchHasDot() { XCTAssertTrue(titles(render(.webSearch, "websearch")).contains(".")) }
    func testNumberPad() {
        let kb = render(.numberPad, layer: .numpad, "numberpad")
        XCTAssertEqual(Set(titles(kb).filter { !$0.isEmpty }), Set("1234567890".map(String.init)))
    }
    func testDecimalAndPhonePads() {
        XCTAssertTrue(titles(render(.decimalPad, layer: .numpad, "decimalpad")).contains(Locale.current.decimalSeparator ?? "."))
        XCTAssertTrue(titles(render(.phonePad, layer: .numpad, "phonepad")).contains("+"))
    }
    func testDefaultUnchanged() { let t = titles(render(.default, "default")); XCTAssertFalse(t.contains("@")) }
}

/// Design proposals: the VI/EN key in the top-left corner of the suggestion strip (Tony). Renders only.
final class LanguageKeyProposalTests: XCTestCase {
    func testRenderProposals() {
        KeyboardView.barOn = true
        for dark in [false, true] {
            for style in 0...3 {
                KeyboardView.langStyle = style
                let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
                kb.dark = dark
                kb.languageShort = "VI"; kb.languageTitle = "Tiếng Việt"
                kb.backgroundColor = dark ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
                kb.suggestions = [Suggestion(text: "tooi", quoted: true), Suggestion(text: "tôi", highlighted: true), Suggestion(text: "tối")]
                kb.layoutIfNeeded()
                let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { ctx in kb.layer.render(in: ctx.cgContext) }
                try? img.pngData()?.write(to: URL(fileURLWithPath: "/tmp/claude-501/layouts/lang_\(style)_\(dark ? "dark" : "light").png"))
            }
        }
        KeyboardView.langStyle = 1
    }

    func testPillStates() {
        KeyboardView.barOn = true; KeyboardView.langStyle = 1
        for (lang, title) in [("VI", "Tiếng Việt"), ("EN", "English")] {
            let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
            kb.languageShort = lang; kb.languageTitle = title
            kb.backgroundColor = UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
            kb.layoutIfNeeded()
            let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { ctx in kb.layer.render(in: ctx.cgContext) }
            try? img.pngData()?.write(to: URL(fileURLWithPath: "/tmp/claude-501/layouts/pill_\(lang).png"))
            let caps = kb.subviews.compactMap { $0 as? KeyCap }
            // the language key stays in the corner (it takes the taps); the corner element draws VI/EN over it
            XCTAssertTrue(caps.contains { $0.frame.minY < 40 && $0.frame.minX < 20 }, "the pill sits in the strip's corner")
            XCTAssertFalse(kb.mark.isHidden)
            XCTAssertEqual(kb.mark.vietnamese, lang == "VI")
        }
        KeyboardView.barOn = false
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.layoutIfNeeded()
        XCTAssertTrue(kb.subviews.compactMap { $0 as? KeyCap }.contains { $0.label.text == "VI" && $0.frame.minY > 150 }, "no strip: back in the bottom row")
    }
}


/// Key frames vs the iOS 26.5 system keyboard, measured from simulator screenshots of iPhone 17 Pro Max (440 pt).
final class SystemKeyboardGeometryTests: XCTestCase {
    func testMatchesSystemKeyboardAt440() throws {
        guard KeyboardView.tallKeys else { throw XCTSkip("needs a Pro Max-size simulator") }
        KeyboardView.barOn = true; KeyboardView.langStyle = 1
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 440, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.layoutIfNeeded()
        let caps = kb.subviews.compactMap { $0 as? KeyCap }
        func frame(_ label: String) -> CGRect? { caps.first { $0.label.text == label }?.frame }
        let q = try XCTUnwrap(frame("q")), a = try XCTUnwrap(frame("a")), z = try XCTUnwrap(frame("z")), p = try XCTUnwrap(frame("p"))
        let top = q.minY
        func near(_ v: CGFloat, _ want: CGFloat, _ what: String) { XCTAssertEqual(v, want, accuracy: 0.5, what) }
        near(q.minX, 6.67, "q x"); near(q.width, 37.33, "letter width")
        near(q.height, 48, "key height (taller than the system's 45)")
        near(p.maxX, 433.67, "p right edge")
        near(a.minX, 28.0, "a x"); near(a.minY - top, 54, "row pitch: rows 6 pt apart")
        near(z.minX, 71.33, "z x"); near(z.minY - top, 108, "row 3")
        // row 3 sides: shift 6.67 w 50.0, delete 383.33 w 50.33; bottom row: 123 w 48 at 6.67, return 331.33 w 102.33
        let row3 = caps.filter { abs($0.frame.minY - z.minY) < 1 }.sorted { $0.frame.minX < $1.frame.minX }
        near(row3.first!.frame.width, 50, "shift width"); near(row3.last!.frame.minX, 383.33, "delete x")
        let bottom = caps.filter { abs($0.frame.minY - (top + 162)) < 1 }.sorted { $0.frame.minX < $1.frame.minX }
        near(bottom.first!.frame.width, 48, "123 width"); near(bottom.last!.frame.minX, 331.33, "return x"); near(bottom.last!.frame.width, 102.33, "return width")
    }
}

/// The brand on the right of an empty suggestion strip (Tony). Renders only.
final class StripBrandTests: XCTestCase {
    func testRenderEmptyAndFullStrip() {
        KeyboardView.barOn = true
        KeyboardView.langStyle = 1
        for dark in [false, true] {
            for (name, s) in [("empty", [Suggestion]()), ("words", [Suggestion(text: "tooi", quoted: true), Suggestion(text: "tôi", highlighted: true), Suggestion(text: "tối")])] {
                let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
                kb.dark = dark
                kb.languageShort = "VI"; kb.languageTitle = "Tiếng Việt"
                kb.backgroundColor = dark ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
                kb.suggestions = s
                kb.layoutIfNeeded()
                let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { ctx in kb.layer.render(in: ctx.cgContext) }
                try? FileManager.default.createDirectory(atPath: "/tmp/claude-501/layouts", withIntermediateDirectories: true)
                try? img.pngData()?.write(to: URL(fileURLWithPath: "/tmp/claude-501/layouts/brand_\(name)_\(dark ? "dark" : "light").png"))
            }
        }
    }
}

/// The corner mark's opening plays at most once every 10 minutes (Tony).
final class MarkIntroThrottleTests: XCTestCase {
    func testIntroAtMostEveryTenMinutes() {
        KeyboardView.barOn = true; KeyboardView.langStyle = 1
        let key = "markIntroLast"
        UserDefaults.standard.removeObject(forKey: key)
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.layoutIfNeeded()
        kb.playMarkIntro()
        let first = UserDefaults.standard.double(forKey: key)
        XCTAssertGreaterThan(first, 0, "the first opening plays")
        kb.playMarkIntro()
        XCTAssertEqual(UserDefaults.standard.double(forKey: key), first, "a second opening right after does not")
        UserDefaults.standard.set(first - 601, forKey: key)
        kb.playMarkIntro()
        XCTAssertGreaterThan(UserDefaults.standard.double(forKey: key), first - 601, "after 10 minutes it plays again")
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// The key under the corner element never shows, even when the strip came on after the keyboard was built
/// (Tony, build 51: a key-coloured square behind the pill in dark mode).
final class CornerKeyInvisibleTests: XCTestCase {
    func testLanguageKeyClearAfterStripTurnsOn() {
        KeyboardView.barOn = false; KeyboardView.langStyle = 1
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.dark = true
        kb.layoutIfNeeded()
        KeyboardView.barOn = true
        kb.setNeedsLayout(); kb.layoutIfNeeded()
        let cap = kb.subviews.compactMap { $0 as? KeyCap }.first { $0.frame.minY < 40 && $0.frame.minX < 20 }
        XCTAssertNotNil(cap)
        XCTAssertEqual(cap?.fill, .clear)
        XCTAssertEqual(cap?.normalColor, .clear)
    }
}

/// A tap iOS held back at the screen's edge (outer edge of shift, delete, 123, return) still vibrates (Hieu); only a
/// backlog of touches (a key already vibrated since this finger landed) stays quiet.
final class LateTouchHapticTests: XCTestCase {
    func testLateTouchVibratesUnlessBacklog() {
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.haptics = true
        kb.layoutIfNeeded()
        let cap = kb.subviews.compactMap { $0 as? KeyCap }.first!
        let start = Diag.haptics

        kb.press(cap, landed: CACurrentMediaTime() - 0.3)   // held back 300 ms, nothing else pressed
        XCTAssertEqual(Diag.haptics, start + 1, "a lone late touch vibrates")

        Thread.sleep(forTimeInterval: 0.06)                  // past the one-vibration-per-press window
        kb.press(cap, landed: CACurrentMediaTime() - 0.3)   // landed before the last vibration: a backlog
        XCTAssertEqual(Diag.haptics, start + 1, "a backlog touch stays quiet")

        Thread.sleep(forTimeInterval: 0.06)
        kb.press(cap, landed: CACurrentMediaTime())          // on time
        XCTAssertEqual(Diag.haptics, start + 2, "an on-time touch vibrates")
    }
}

/// The shift key is always blue with a white arrow (Hieu), in light and dark, on every letter page state.
final class ShiftTintTests: XCTestCase {
    func testShiftIsBlue() {
        for dark in [false, true] {
            let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
            kb.dark = dark
            kb.layoutIfNeeded()
            for state in [KeyboardView.Shift.off, .on, .locked] {
                kb.shift = state
                let shift = kb.subviews.compactMap { $0 as? KeyCap }.first { $0.icon.image?.description.contains("system: shift") == true || $0.icon.image?.description.contains("system: capslock") == true }
                XCTAssertEqual(shift?.fill, .systemBlue, "dark \(dark), \(state): blue")
                XCTAssertEqual(shift?.icon.tintColor, .white, "dark \(dark), \(state): white arrow")
            }
        }
    }
}

/// The delete key is always red with a white icon (Hieu), in light and dark, on every page.
final class DeleteTintTests: XCTestCase {
    func testDeleteIsRed() {
        for dark in [false, true] {
            let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
            kb.dark = dark
            for layer in [KeyboardView.Layer.letters, .numbers, .symbols] {
                kb.layer_ = layer
                kb.layoutIfNeeded()
                let delete = kb.subviews.compactMap { $0 as? KeyCap }.first { $0.icon.image?.description.contains("system: delete.left") == true }
                XCTAssertEqual(delete?.fill, .systemRed, "dark \(dark), \(layer): red")
                XCTAssertEqual(delete?.icon.tintColor, .white, "dark \(dark), \(layer): white icon")
            }
        }
    }
}

/// VI is indigo with a white label, EN the plain key with an indigo label; Paste is tinted only with something to
/// paste; a pressed key keeps its colour at half the opacity instead of turning white (Hieu).
final class KeyTintTests: XCTestCase {
    private func make(dark: Bool) -> KeyboardView {
        KeyboardView.langStyle = 0
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.dark = dark
        kb.layoutIfNeeded()
        return kb
    }
    private func caps(_ kb: KeyboardView) -> [KeyCap] { kb.subviews.compactMap { $0 as? KeyCap } }
    private func symbol(_ kb: KeyboardView, _ name: String) -> KeyCap? { caps(kb).first { $0.icon.image?.description.contains("system: \(name)") == true } }
    private func alpha(_ c: UIColor?) -> CGFloat { c?.cgColor.alpha ?? -1 }

    func testLanguageKeyTint() {
        for dark in [false, true] {
            let kb = make(dark: dark)
            let plain = caps(kb).first { $0.label.text == "Q" || $0.label.text == "q" }!.fill
            kb.languageShort = "VI"
            let vi = caps(kb).first { $0.label.text == "VI" }!
            XCTAssertNotEqual(vi.fill, plain, "dark \(dark): VI is tinted")
            XCTAssertEqual(alpha(vi.fill), 1, "dark \(dark): a solid indigo")
            XCTAssertEqual(vi.label.textColor, .white)
            kb.languageShort = "EN"
            let en = caps(kb).first { $0.label.text == "EN" }!
            XCTAssertEqual(en.fill, plain, "dark \(dark): EN is the plain key")
            XCTAssertNotEqual(en.label.textColor, .white, "dark \(dark): EN keeps the indigo label")
        }
    }

    func testPasteTintOnlyWithSomethingToPaste() {
        let kb = make(dark: false)
        let plain = caps(kb).first { $0.label.text == "Q" || $0.label.text == "q" }!.fill
        XCTAssertEqual(symbol(kb, "clipboard")?.fill, plain, "nothing to paste: plain")
        kb.pasteReady = true
        XCTAssertEqual(symbol(kb, "clipboard")?.fill, KeyboardView.pasteTint)
        XCTAssertEqual(symbol(kb, "clipboard")?.icon.tintColor, .white)
        kb.pasteReady = false
        XCTAssertEqual(symbol(kb, "clipboard")?.fill, plain)
    }

    func testPressedKeepsTheColourAtHalfOpacity() {
        let kb = make(dark: false)
        for cap in [symbol(kb, "shift"), symbol(kb, "delete.left"), caps(kb).first { $0.label.text == "Q" || $0.label.text == "q" }] {
            guard let cap else { return XCTFail("key missing") }
            XCTAssertEqual(cap.pressedColor, KeyboardView.pressed(cap.normalColor))
            XCTAssertEqual(alpha(cap.pressedColor), alpha(cap.normalColor) * 0.5, accuracy: 0.001)
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        symbol(kb, "shift")!.pressedColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
        UIColor.systemBlue.resolvedColor(with: kb.traitCollection).getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        XCTAssertEqual(b, b0, accuracy: 0.01, "pressed shift stays blue, not white")
    }
}

import XCTest
import UIKit

/// Performance lock for the keyboard (Tony: "tests that guarantee performance").
/// What made build 2 laggy was cross-process work per key, not the engine, so these tests count it:
/// at most one read of the text field per key, no shared-settings reads while typing, shadows with a
/// fixed path, and a time budget per key.
class CountingProxy: NSObject, UITextDocumentProxy {
    var text = ""
    var reads = 0, deletes = 0, inserts = 0
    var documentContextBeforeInput: String? { reads += 1; return text }
    var documentContextAfterInput: String? { nil }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier: UUID { UUID() }
    var hasText: Bool { !text.isEmpty }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
    func insertText(_ t: String) { inserts += 1; text += t }
    func deleteBackward() { deletes += 1; if !text.isEmpty { text.removeLast() } }
}

final class KeyboardPerformanceTests: XCTestCase {
    // mixed Vietnamese/English, typed in Telex, ~2,000 keys
    static let sample = String(repeating: "tooi ddi hocj sorry em i love phowr order traf suwax nhes booking phongf chuaw meeting lucs ba giowf nhes mixx verr ", count: 18)

    private func makeKeyboard() -> (KeyboardViewController, CountingProxy) {
        let vc = KeyboardViewController()
        let p = CountingProxy()
        vc.proxy = p
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)   // lays the keys out (auto-correct needs them)
        vc.view.layoutIfNeeded()
        vc.viewWillAppear(false)
        vc.setLanguageForTests(1)
        return (vc, p)
    }

    private let sender = KeyboardView()
    private func type(_ s: String, into vc: KeyboardViewController) {
        for ch in s {
            if ch == " " { vc.keyboard(sender, didTap: .space) }
            else { vc.keyboard(sender, didTap: .char(String(ch))) }
        }
    }

    /// The letter keys of the 402 pt layout (same geometry as KeyboardView).
    static func letterRects() -> [VKKeyRect] {
        let W: Float = 402, side: Float = 6.67, gap: Float = 6, key = (W - 2 * side - 9 * gap) / 10
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"], x0: [Float] = [side, side + (key + gap) / 2, side + (key + gap) * 1.5]
        var r: [VKKeyRect] = []
        for (i, row) in rows.enumerated() {
            for (j, ch) in row.enumerated() {
                r.append(VKKeyRect(letter: CChar(ch.asciiValue!), x: x0[i] + Float(j) * (key + gap), y: Float(i) * 54, w: key, h: 43))
            }
        }
        return r
    }

    func testFatFingerPicksLikelyLetterAtBorder() {
        let keys = Self.letterRects()
        func pick(_ prefix: String, _ vn: Bool, between a: Character, _ b: Character) -> Character {
            let ka = keys.first { $0.letter == CChar(a.asciiValue!) }!, kb = keys.first { $0.letter == CChar(b.asciiValue!) }!
            let x = ((ka.x + ka.w / 2) + (kb.x + kb.w / 2)) / 2, y = ka.y + ka.h / 2
            let c = prefix.withCString { VKPickLetter(x, y, $0, vn ? 1 : 0, keys, Int32(keys.count)) }
            return Character(UnicodeScalar(UInt8(bitPattern: c)))
        }
        XCTAssertEqual(pick("kh", true, between: "o", "p"), "o")      // "kho…", never "khp"
        XCTAssertEqual(pick("th", false, between: "e", "r"), "e")     // "the"
        XCTAssertEqual(pick("ng", true, between: "u", "y"), "u")      // "ngu…"
        // a clear tap in the middle of a key always types that key, however unlikely
        let p = keys.first { $0.letter == CChar(Character("p").asciiValue!) }!
        let c = "kh".withCString { VKPickLetter(p.x + p.w / 2, p.y + p.h / 2, $0, 1, keys, Int32(keys.count)) }
        XCTAssertEqual(Character(UnicodeScalar(UInt8(bitPattern: c))), "p")
    }

    func testTypesCorrectly() {
        let (vc, p) = makeKeyboard()
        type("tooi ddi hocj sorry em ", into: vc)
        XCTAssertEqual(p.text, "Tôi đi học sorry em ")
    }

    func testAutoCorrectAtSpaceAndBackspaceUndo() {
        let (vc, p) = makeKeyboard()
        vc.setLanguageForTests(0)
        type("i love teh ", into: vc)
        XCTAssertTrue(p.text.hasSuffix("the "), "auto-correct: \(p.text)")
        vc.keyboard(sender, didTap: .backspace)          // right after: put back what was typed
        XCTAssertTrue(p.text.hasSuffix("teh"), "undo: \(p.text)")
        vc.keyboard(sender, didTap: .space)              // and keep it this time
        XCTAssertTrue(p.text.hasSuffix("teh "), "kept: \(p.text)")
    }

    func testContractions() {
        let (vc, p) = makeKeyboard()
        vc.setLanguageForTests(0)
        type("i dont know youre ill. ", into: vc)       // "ill" is a word: stays
        XCTAssertEqual(p.text, "I don't know you're ill. ")
        type("Ill be there, cant", into: vc)              // capital I: "I'll"
        vc.keyboard(sender, didTap: .char("!"))
        XCTAssertTrue(p.text.hasSuffix("I'll be there, can't!"), p.text)
        vc.keyboard(sender, didTap: .backspace)           // right after: undo the fix
        XCTAssertTrue(p.text.hasSuffix("I'll be there, cant"), p.text)
        // Vietnamese mode: a real word stays, an English contraction still gets fixed
        p.text = ""; vc.setLanguageForTests(1)
        type(" im lawngj ", into: vc)
        XCTAssertTrue(p.text.hasSuffix(" im lặng "), p.text)
        type("thats ", into: vc)
        XCTAssertTrue(p.text.hasSuffix("that's "), p.text)
    }

    func testAutoCorrectLeavesRealWordsAndShorthand() {
        let (vc, p) = makeKeyboard()
        // clean mixed typing must come out exactly as typed: no correction of real words / VN shorthand
        type("tooi ddi hocj sorry em ", into: vc)
        XCTAssertEqual(p.text, "Tôi đi học sorry em ")
    }

    private func waitFor(_ done: () -> Bool, timeout: TimeInterval = 5) {
        let end = Date().addingTimeInterval(timeout)
        repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } while !done() && Date() < end
    }

    func testSuggestionStrip() {
        let (vc, _) = makeKeyboard()
        vc.setLanguageForTests(0)
        type("helo", into: vc)
        // the strip updates right after the key (on the next main-queue turn; CI machines can take a while)
        waitFor { !vc.keyboardViewForTests.suggestions.isEmpty }
        let cells = vc.keyboardViewForTests.suggestions.map(\.text)
        XCTAssertEqual(cells.first, "Helo")                         // start of the field: capital
        XCTAssertTrue(cells.contains("Hello"), "suggestions: \(cells)")
        type(" ", into: vc)
        waitFor { !vc.keyboardViewForTests.suggestions.contains { $0.kind == .word } }
        XCTAssertFalse(vc.keyboardViewForTests.suggestions.contains { $0.kind == .word }, "after a space: next words only")
    }

    func testAtMostOneTextReadPerKey() {
        let (vc, p) = makeKeyboard()
        let readsBefore = p.reads
        let keys = Self.sample.count
        type(Self.sample, into: vc)
        let perKey = Double(p.reads - readsBefore) / Double(keys)
        XCTAssertLessThanOrEqual(perKey, 1.0, "text field reads per key: \(perKey) (each one is a cross-process call on device)")
    }

    func testNoSettingsReadsWhileTyping() {
        let (vc, _) = makeKeyboard()
        let before = VKSettings.reads
        type(Self.sample, into: vc)
        XCTAssertEqual(VKSettings.reads, before, "shared settings were read while typing")
    }

    func testFewEditsPerKey() {
        let (vc, p) = makeKeyboard()
        let keys = Self.sample.count
        type(Self.sample, into: vc)
        let calls = Double(p.deletes + p.inserts) / Double(keys)
        print("keyboard: \(String(format: "%.2f", calls)) text edits per key")
        XCTAssertLessThan(calls, 1.6, "\(calls) delete/insert calls per key: send only the characters that change")
    }

    /// Shared CI machines differ a lot in speed (the same code measured 297 to 2782 µs per key there, and 973 at
    /// best of 5): the best of a few runs drops noise (it only ever adds time), and on CI the limit only catches a
    /// gross slowdown. The real lock is the local limit, run on the dev Mac before every ship.
    private static let onCI = ProcessInfo.processInfo.environment["VIKEY_CI"] != nil
    private static func limit(_ us: Double) -> Double { onCI ? us * 10 : us }
    private func bestOf(_ runs: Int, _ measure: () -> Double) -> Double { (0..<runs).map { _ in measure() }.min()! }

    func testTimePerKey() {
        let keys = Self.sample.count
        let perKeyUs = bestOf(5) {
            let (vc, _) = makeKeyboard()
            let start = CFAbsoluteTimeGetCurrent()
            type(Self.sample, into: vc)
            return (CFAbsoluteTimeGetCurrent() - start) / Double(keys) * 1e6
        }
        print("keyboard: \(Int(perKeyUs)) µs per key (best of 5)")
        XCTAssertLessThan(perKeyUs, Self.limit(300), "keyboard logic takes \(Int(perKeyUs)) µs per key")
    }

    func testSuggestionTimePerKey() {
        // the strip runs after each key's text is sent; it still has to keep up with fast typing
        let us = bestOf(3) {
            let (vc, _) = makeKeyboard()
            var total = 0.0, n = 0
            for ch in Self.sample.prefix(600) {
                if ch == " " { vc.keyboard(sender, didTap: .space) } else { vc.keyboard(sender, didTap: .char(String(ch))) }
                let t = CFAbsoluteTimeGetCurrent(); vc.updateSuggestions(); total += CFAbsoluteTimeGetCurrent() - t; n += 1
            }
            return total / Double(n) * 1e6
        }
        print("keyboard: suggestions \(Int(us)) µs per key (best of 3)")
        XCTAssertLessThan(us, Self.limit(2000), "suggestion strip takes \(Int(us)) µs per key")
    }

    func testGapsBetweenKeysReceiveTouches() {
        // iOS drops touches on fully transparent parts of a keyboard: the view must never be clear
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: 265))
        var a: CGFloat = 0
        kb.backgroundColor?.getWhite(nil, alpha: &a)
        XCTAssertGreaterThan(a, 0, "keyboard background is fully transparent: taps between keys are lost")
    }

    func testRenderPopups() {
        // renders key popups (top row and second row) to an image for a visual check
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.backgroundColor = UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
        kb.layoutIfNeeded()
        let caps = kb.subviews.compactMap { $0 as? KeyCap }
        let pop1 = KeyPopup(); kb.addSubview(pop1); pop1.show(over: caps[4], in: kb)     // t
        let pop2 = KeyPopup(); kb.addSubview(pop2); pop2.show(over: caps[17], in: kb)    // k
        let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { ctx in kb.layer.render(in: ctx.cgContext) }
        try? img.pngData()?.write(to: URL(fileURLWithPath: "/tmp/claude-501/popup_test.png"))
        XCTAssertGreaterThanOrEqual(pop1.frame.minY, 0)
    }

    func testRenderSuggestionStrip() {
        KeyboardView.barOn = true
        for dark in [false, true] {
            let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
            kb.backgroundColor = dark ? UIColor(white: 0.17, alpha: 1) : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
            kb.dark = dark
            kb.suggestions = [Suggestion(text: "teh", quoted: true), Suggestion(text: "the", highlighted: true), Suggestion(text: "tech")]
            kb.layoutIfNeeded()
            let img = UIGraphicsImageRenderer(bounds: kb.bounds).image { ctx in kb.layer.render(in: ctx.cgContext) }
            try? img.pngData()?.write(to: URL(fileURLWithPath: "/tmp/claude-501/strip_\(dark ? "dark" : "light").png"))
        }
        XCTAssertGreaterThan(KeyboardView.keyboardHeight(compactHeight: false), 250)
    }

    func testKeyShadowsHaveFixedPaths() {
        let kb = KeyboardView(frame: CGRect(x: 0, y: 0, width: 402, height: KeyboardView.keyboardHeight(compactHeight: false)))
        kb.layoutIfNeeded()
        let caps = kb.subviews.compactMap { $0 as? KeyCap }
        XCTAssertGreaterThan(caps.count, 30)
        for c in caps where c.layer.shadowOpacity > 0 {   // glass keys (iOS 26+) draw no shadow
            c.layoutIfNeeded(); XCTAssertNotNil(c.layer.shadowPath, "a key shadow without a path is re-rendered offscreen every frame")
        }
    }
}

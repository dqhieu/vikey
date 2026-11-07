import XCTest
import UIKit

/// Next words (the table, Apple Intelligence on top); ✨ on the VI/EN key's place rewrites a selection proofread,
/// in Hieu's voice and Natural in a picker, and a tap on a version puts it in. The model is stubbed: these test the keyboard's
/// flow, not Claude's answers.
final class AIAssistFlowTests: XCTestCase {
    private let sender = KeyboardView()

    override func tearDown() { AIAssist.stub = nil; KeyboardViewController.rewriteTimeout = 60; super.tearDown() }

    private func make(_ lang: Int = 0) -> (KeyboardViewController, CursorProxy) {
        let vc = KeyboardViewController()
        let p = CursorProxy()
        vc.proxy = p
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 300)
        vc.view.layoutIfNeeded()
        vc.viewWillAppear(false)
        vc.setLanguageForTests(lang)
        return (vc, p)
    }
    private func type(_ s: String, _ vc: KeyboardViewController) {
        for ch in s { vc.keyboard(sender, didTap: ch == " " ? .space : .char(String(ch).lowercased())) }
    }
    /// Lets the queued strip update and the model's (stubbed) answers land.
    /// With a condition, waits up to 10 s for it (CI machines are slow); without one, just lets the queued work run.
    private func settle(_ until: (() -> Bool)? = nil, timeout: TimeInterval? = nil) {
        let end = Date().addingTimeInterval(timeout ?? (until == nil ? 0.5 : 10))
        let until = until ?? { false }
        repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) } while !until() && Date() < end
    }
    private func strip(_ vc: KeyboardViewController) -> [Suggestion] { vc.keyboardViewForTests.suggestions }
    private func key(_ vc: KeyboardViewController) -> KeyboardView.AIKey { vc.keyboardViewForTests.aiKey }
    private func tapAI(_ vc: KeyboardViewController) { vc.keyboard(sender, didTap: .language) }
    private func versions(_ vc: KeyboardViewController) -> [RewriteVersion] { vc.rewritePanelForTests?.versions ?? [] }
    private func allIn(_ vc: KeyboardViewController) -> Bool { !versions(vc).isEmpty && !versions(vc).contains(.loading) }
    private func select(_ p: CursorProxy, _ vc: KeyboardViewController, _ part: String) {
        let r = p.text.range(of: part)!
        p.cursor = p.text.distance(from: p.text.startIndex, to: r.lowerBound); p.selection = part.count
        vc.selectionDidChange(nil)
    }
    /// A stub that answers each style with its name in front: "proofread …", "voice …", "natural …".
    private func tagged() -> AIAssist.Stub { .init(rewrite: { t, s, _ in "\(s) \(t)" }) }

    // the table
    func testTableVietnameseAndEnglish() {
        XCTAssertEqual(NextWords.shared.predict(before: "cảm ơn ").first, "bạn")
        XCTAssertTrue(NextWords.shared.predict(before: "thank you ").contains("for"))
        XCTAssertTrue(NextWords.shared.predict(before: "cảm ơn").isEmpty, "only after a space")
    }

    func testNextWordsAfterASpaceAndPick() {
        let (vc, p) = make(1)
        type("camr own ", vc)
        settle { self.strip(vc).first?.kind == .next }
        XCTAssertEqual(strip(vc).first?.text, "bạn")
        XCTAssertTrue(strip(vc).allSatisfy { $0.kind == .next })
        vc.keyboard(sender, pickSuggestion: 0)
        XCTAssertEqual(p.text, "Cảm ơn bạn ")
        settle { self.strip(vc).first?.kind == .next }
        XCTAssertFalse(strip(vc).isEmpty, "and the next ones")
    }

    // ✨: the picker, three versions, a tap puts one in
    func testSparkleOpensThePickerWithThreeVersionsAndATapPutsOneIn() {
        AIAssist.stub = tagged()
        let (vc, p) = make()
        p.text = "can u send me the file"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        XCTAssertTrue(strip(vc).isEmpty, "nothing in the strip")
        XCTAssertNil(vc.rewritePanelForTests, "nothing asked before ✨")
        tapAI(vc)
        XCTAssertNotNil(vc.rewritePanelForTests, "the picker opens at once")
        XCTAssertTrue(vc.keyboardViewForTests.isHidden, "over the whole keyboard")
        settle { self.allIn(vc) }
        XCTAssertEqual(versions(vc), [.done("proofread can u send me the file"), .done("voice can u send me the file"), .done("natural can u send me the file")])
        XCTAssertEqual(p.text, "can u send me the file", "nothing changes before a tap")
        vc.rewritePanelForTests?.onPick?(.voice)
        XCTAssertEqual(p.text, "voice can u send me the file")
        XCTAssertNil(vc.rewritePanelForTests)
        XCTAssertFalse(vc.keyboardViewForTests.isHidden)
        settle()
        XCTAssertEqual(key(vc), .off, "VI/EN again, no Undo")
        XCTAssertEqual(vc.aiStateForTests, .none)
    }

    /// Natural's alternative is its own card, and a tap on it puts it in.
    func testTheAlternativeCanBePicked() {
        AIAssist.stub = .init(rewriteFull: { t, s, _ in
            s == .natural ? Rewrite(text: "natural \(t)", alternative: "punchy \(t)") : Rewrite(text: "\(s) \(t)")
        })
        let (vc, p) = make()
        p.text = "can u send me the file"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        settle { self.allIn(vc) }
        XCTAssertEqual(versions(vc)[RewriteStyle.natural.rawValue],
                       .done(Rewrite(text: "natural can u send me the file", alternative: "punchy can u send me the file")))
        vc.rewritePanelForTests?.onPickAlternative?(.natural)
        XCTAssertEqual(p.text, "punchy can u send me the file", "the alternative")
        XCTAssertNil(vc.rewritePanelForTests)
    }

    /// The proofread card marks what changed: removed words struck through, added ones highlighted.
    func testProofreadDiff() {
        typealias P = RewriteDiff.Part
        XCTAssertEqual(RewriteDiff.parts("can u send me the file", "Can you send me the file."),
                       [P.removed("can u"), .added("Can you"), .same(" send me the file"), .added(".")])
        XCTAssertEqual(RewriteDiff.parts("toi di hoc", "tôi đi học"), [P.removed("toi di hoc"), .added("tôi đi học")])
        XCTAssertEqual(RewriteDiff.parts("send file", "send the file"), [P.same("send "), .added("the "), .same("file")])
        XCTAssertEqual(RewriteDiff.parts("All good.", "All good."), [P.same("All good.")])
        let a = RewriteDiff.attributed("can u go", "can you go", font: .systemFont(ofSize: 17), fg: .black, dark: false)
        XCTAssertEqual(a.string, "can u you go", "the removed word, a space, then the added one")
        XCTAssertNotNil(a.attribute(.strikethroughStyle, at: 4, effectiveRange: nil), "u struck through")
        XCTAssertNotNil(a.attribute(.backgroundColor, at: 6, effectiveRange: nil), "you highlighted")
    }

    /// No style is tied to a language and no explanation is asked for: VI | EN alone decides the language.
    func testPromptsFollowTheLanguageToggleOnly() {
        for style in RewriteStyle.allCases {
            let vi = ClaudeRewrite.system(style, vietnamese: true), en = ClaudeRewrite.system(style, vietnamese: false)
            XCTAssertFalse(en.contains("Vietnamese"), "\(style)")
            XCTAssertFalse(vi.contains("in English."), "\(style)")
            XCTAssertFalse(vi.lowercased().contains("explain") && !vi.contains("no explanation"), "\(style)")
            XCTAssertFalse(vi.contains("\"note\""), "\(style)")
        }
    }

    /// The model picked in the app goes in the request; Sonnet and Opus ask for the server-side fallback, Haiku can't.
    func testRequestUsesTheChosenModel() throws {
        for model in ClaudeModel.allCases {
            let r = try XCTUnwrap(Claude.messagesRequest(system: "s", user: "u", schema: ClaudeRewrite.schema, key: "k", model: model))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(r.httpBody)) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, model.rawValue)
            XCTAssertEqual(body["fallbacks"] as? String, model == .haiku ? nil : "default", "\(model)")
            XCTAssertEqual(r.value(forHTTPHeaderField: "anthropic-beta"), model == .haiku ? nil : "server-side-fallback-2026-07-01")
            XCTAssertEqual(r.value(forHTTPHeaderField: "x-api-key"), "k")
            XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "high")
            XCTAssertEqual(body["max_tokens"] as? Int, 16000)
        }
        XCTAssertEqual(ClaudeModel.allCases.map(\.rawValue), ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"])
    }

    /// ↻ asks all three again, each told every version already shown (so far, across taps); VI | EN starts over.
    func testMoreAsksAgainForDifferentVersions() {
        var round = 0
        var seen: [RewriteStyle: [String]] = [:]
        let lock = NSLock()
        AIAssist.stub = .init(rewriteFull: { t, s, _ in
            lock.lock(); defer { lock.unlock() }
            return Rewrite(text: "\(s) \(round) \(t)", alternative: s == .natural ? "alt \(round)" : nil)
        }, avoiding: { s, shown in lock.lock(); seen[s] = shown; lock.unlock() })
        let (vc, p) = make()
        p.text = "can u send me the file"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        settle { self.allIn(vc) }
        XCTAssertEqual(seen[.voice], [], "nothing shown yet")
        lock.lock(); round = 1; lock.unlock()
        vc.rewritePanelForTests?.onMore?()
        XCTAssertEqual(versions(vc), Array(repeating: .loading, count: 3), "all three asked again")
        settle { self.allIn(vc) }
        XCTAssertEqual(versions(vc)[RewriteStyle.voice.rawValue], .done("voice 1 can u send me the file"))
        XCTAssertEqual(seen[.voice], ["voice 0 can u send me the file"])
        XCTAssertEqual(seen[.natural], ["natural 0 can u send me the file", "alt 0"], "the alternative too")
        lock.lock(); round = 2; lock.unlock()
        vc.rewritePanelForTests?.onMore?()
        settle { self.allIn(vc) }
        XCTAssertEqual(seen[.proofread], ["proofread 0 can u send me the file", "proofread 1 can u send me the file"], "every round so far")
        vc.rewritePanelForTests?.onToggleLanguage?()
        settle { self.allIn(vc) }
        XCTAssertEqual(seen[.voice], [], "the other language starts over")
        vc.rewritePanelForTests?.onPick?(.voice)
        XCTAssertEqual(p.text, "voice 2 can u send me the file")
    }

    /// After ↻ the prompt lists what was shown: Voice and Natural must differ from it, Proofread checks again.
    func testMorePrompt() {
        XCTAssertEqual(ClaudeRewrite.user("hi there", style: .voice, avoiding: []), "<text>\nhi there\n</text>")
        let voice = ClaudeRewrite.user("hi there", style: .voice, avoiding: ["Hi there!", "Hey you"])
        XCTAssertTrue(voice.contains("<version>\nHi there!\n</version>\n<version>\nHey you\n</version>"))
        XCTAssertTrue(voice.contains("clearly different"))
        let proof = ClaudeRewrite.user("hi there", style: .proofread, avoiding: ["Hi there."])
        XCTAssertTrue(proof.contains("Check my text again"))
        XCTAssertFalse(proof.contains("clearly different"), "a proofread isn't made different for its own sake")
    }

    func testVersionsFillInOneByOne() {
        let gate = DispatchSemaphore(value: 0)
        AIAssist.stub = .init(rewrite: { t, s, _ in
            if s == .voice { _ = gate.wait(timeout: .now() + 5) }   // voice comes late
            return "\(s) \(t)"
        })
        let (vc, p) = make()
        p.text = "see you soon"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        settle { self.versions(vc).first != .loading && self.versions(vc).last != .loading }
        XCTAssertEqual(versions(vc)[1], .loading, "still coming")
        vc.rewritePanelForTests?.onPick?(.voice)                     // a loading card does nothing
        XCTAssertEqual(p.text, "see you soon")
        XCTAssertNotNil(vc.rewritePanelForTests)
        gate.signal()
        settle { self.allIn(vc) }
        XCTAssertEqual(versions(vc)[1], .done("voice see you soon"))
    }

    func testCancelKeepsTheTextAndGoesBackToSparkle() {
        AIAssist.stub = tagged()
        let (vc, p) = make()
        p.text = "fixd it now"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        settle { self.allIn(vc) }
        vc.rewritePanelForTests?.onCancel?()
        XCTAssertNil(vc.rewritePanelForTests)
        XCTAssertFalse(vc.keyboardViewForTests.isHidden)
        XCTAssertEqual(p.text, "fixd it now")
        XCTAssertEqual(vc.aiStateForTests, .ready("fixd it now"), "still selected: offer it again")
        XCTAssertEqual(key(vc), .sparkle)
    }

    func testVIENInThePickerAsksAgainInTheOtherLanguage() {
        AIAssist.stub = .init(rewrite: { t, s, vi in "\(s) \(vi ? "vi" : "en") \(t)" })
        let (vc, p) = make(0)                                              // typing in English
        p.text = "see you soon"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        settle { self.allIn(vc) }
        XCTAssertEqual(versions(vc).first, .done("proofread en see you soon"), "VI/EN's language first")
        XCTAssertEqual(vc.rewritePanelForTests?.vietnamese, false)
        vc.rewritePanelForTests?.onToggleLanguage?()
        XCTAssertEqual(vc.rewritePanelForTests?.vietnamese, true)
        settle { self.allIn(vc) && self.versions(vc).first != .done("proofread en see you soon") }
        XCTAssertEqual(versions(vc), [.done("proofread vi see you soon"), .done("voice vi see you soon"), .done("natural vi see you soon")])
        vc.rewritePanelForTests?.onPick?(.voice)
        XCTAssertEqual(p.text, "voice vi see you soon")
    }

    func testAFailedVersionSaysSoAndATapAsksAgain() {
        var naturalWorks = false
        AIAssist.stub = .init(rewrite: { t, s, _ in s == .natural && !naturalWorks ? nil : "\(s) \(t)" })
        let (vc, p) = make()
        p.text = "we was late today"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        settle { self.allIn(vc) }
        XCTAssertEqual(versions(vc)[2], .failed)
        XCTAssertEqual(versions(vc)[0], .done("proofread we was late today"), "the others still come")
        naturalWorks = true
        vc.rewritePanelForTests?.onPick?(.natural)                    // retry
        settle { self.versions(vc)[2] != .failed && self.versions(vc)[2] != .loading }
        XCTAssertEqual(versions(vc)[2], .done("natural we was late today"))
        XCTAssertEqual(p.text, "we was late today", "a retry doesn't put it in")
    }

    func testChattyAnswersAreRejected() {
        AIAssist.stub = .init(rewrite: { _, s, _ in s == .proofread ? "Sure! I'd love to help. What would you like me to write?" : "Hey, the meeting moved to 3pm." })
        let (vc, p) = make()
        p.text = "the meeting is moved to 3pm"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        settle { self.allIn(vc) }
        XCTAssertEqual(versions(vc)[0], .failed)
        XCTAssertEqual(versions(vc)[1], .done("Hey, the meeting moved to 3pm."))
    }

    func testRewriteCheck() {
        XCTAssertNil(RewriteCheck.clean("Sure, I'd be happy to help you write an email! Who is it for?", original: "can you help me write an email"))
        XCTAssertNil(RewriteCheck.clean(String(repeating: "a long answer ", count: 40), original: "hi there"))
        XCTAssertEqual(RewriteCheck.clean("Here is the funny version: I will arrive at 5 pm.", original: "ill be there at 5"), "I will arrive at 5 pm.")
        XCTAssertEqual(RewriteCheck.clean("\"Hẹn gặp lại bạn nhé!\"", original: "see you"), "Hẹn gặp lại bạn nhé!")
        XCTAssertEqual(RewriteCheck.clean("<<<\nSee you soon.\n>>>", original: "see ya"), "See you soon.")
    }

    // language: the keyboard's VI/EN decides (Hieu)
    func testTheKeyboardsLanguageDecides() {
        let lock = NSLock()
        var asked: [Bool] = []
        AIAssist.stub = .init(rewrite: { t, _, vi in lock.lock(); asked.append(vi); lock.unlock(); return t })
        let (vc, p) = make(1)
        p.text = "see you soon"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        settle { self.allIn(vc) }
        XCTAssertEqual(asked, [true, true, true], "VI: rewritten in Vietnamese")
    }

    func testSpacesAroundASelectionStay() {
        AIAssist.stub = .init(rewrite: { _, _, _ in "Hello world." })
        let (vc, p) = make()
        p.text = "a  helo wrld \nb"; p.cursor = 1; p.selection = 12   // "  helo wrld " (spaces only around it)
        vc.selectionDidChange(nil)
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        settle { self.allIn(vc) }
        vc.rewritePanelForTests?.onPick?(.proofread)
        XCTAssertEqual(p.text, "a  Hello world. \nb", "the spaces around it stay")
    }

    // what gets ✨
    func testOneWordGetsNoSparkle() {
        AIAssist.stub = tagged()
        let (vc, p) = make()
        p.text = "We was late"; p.cursor = 0
        select(p, vc, "was")
        settle()
        XCTAssertEqual(key(vc), .off, "a single word: VI/EN stays")
        XCTAssertEqual(vc.aiStateForTests, .none)
    }

    func testOnlyEmojiOrPunctuationIsIgnored() {
        AIAssist.stub = tagged()
        let (vc, p) = make()
        p.text = "ok 😀 !! fine"; p.cursor = 3
        select(p, vc, "😀 !!")
        settle()
        XCTAssertEqual(vc.aiStateForTests, .none)
    }

    func testMultiLineAndLongSelectionsAreOffered() {   // no paragraph or length limit (Hieu)
        AIAssist.stub = .init(rewrite: { _, _, _ in "Line one.\nLine two." })
        let (vc, p) = make()
        p.text = "line one\nline two"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        settle { self.allIn(vc) }
        vc.rewritePanelForTests?.onPick?(.proofread)
        XCTAssertEqual(p.text, "Line one.\nLine two.")
        p.text = String(repeating: "some words here ", count: 200); p.cursor = 0
        select(p, vc, p.text)
        settle()
        XCTAssertEqual(key(vc), .sparkle)
    }

    func testNoSparkleWithoutAppleIntelligence() {
        guard !AIAssist.available else { return }   // a simulator/phone with the model: nothing to check here
        let (vc, p) = make()
        p.text = "some words here"; p.cursor = 0
        select(p, vc, p.text)
        settle()
        XCTAssertEqual(key(vc), .off, "the key stays VI/EN")
    }

    func testTheVIENKeyIsSparkleOnlyWhileTextIsSelected() {
        AIAssist.stub = tagged()
        let (vc, p) = make(1)
        let kv = vc.keyboardViewForTests
        p.text = "fixd it now"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        XCTAssertEqual(kv.languageShort, "VI", "✨, not a language switch")
        vc.rewritePanelForTests?.onCancel?()
        p.selection = 0; vc.selectionDidChange(nil)
        settle()
        XCTAssertEqual(key(vc), .off)
        vc.keyboard(sender, didTap: .language)
        XCTAssertEqual(kv.languageShort, "EN", "VI/EN again without a selection")
    }

    func testPasteStaysPasteWhileTextIsSelected() {
        var asked = 0
        AIAssist.stub = .init(rewrite: { t, _, _ in asked += 1; return t })
        let (vc, p) = make()
        p.text = "fixd it now"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        vc.keyboard(sender, didTap: .paste)
        settle()
        XCTAssertEqual(asked, 0)
        XCTAssertNil(vc.rewritePanelForTests)
    }

    func testShiftKeepsTheSelectionState() {
        AIAssist.stub = tagged()
        let (vc, p) = make()
        p.text = "fixd it now"; p.cursor = 0
        select(p, vc, p.text)
        settle { vc.aiStateForTests == .ready("fixd it now") }
        vc.keyboard(sender, didTap: .shift)
        settle()
        XCTAssertEqual(vc.aiStateForTests, .ready("fixd it now"))
        XCTAssertEqual(key(vc), .sparkle)
    }

    // state: nothing from one selection outlives it
    func testALateAnswerForAnOldSelectionIsDropped() {
        let gate = DispatchSemaphore(value: 0)
        AIAssist.stub = .init(rewrite: { t, s, _ in _ = gate.wait(timeout: .now() + 5); return "\(s) \(t)" })
        let (vc, p) = make()
        p.text = "fixd text here and more words"; p.cursor = 0
        select(p, vc, "fixd text here")
        settle { vc.aiStateForTests == .ready("fixd text here") }
        tapAI(vc)                                                 // asked…
        select(p, vc, "more words")                              // …and moved on before the answers
        for _ in 0..<3 { gate.signal() }
        settle()
        XCTAssertNil(vc.rewritePanelForTests, "no picker for text that isn't selected any more")
        XCTAssertEqual(vc.aiStateForTests, .ready("more words"))
    }

    func testPickNeedsTheSameSelection() {
        AIAssist.stub = tagged()
        let (vc, p) = make()
        p.text = "two wrds"; p.cursor = 0
        select(p, vc, p.text)
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        settle { self.allIn(vc) }
        p.selection = 0; p.cursor = 3            // the user moved away meanwhile
        vc.rewritePanelForTests?.onPick?(.proofread)
        XCTAssertEqual(p.text, "two wrds", "never replaces the wrong text")
    }

    func testSelectingOtherTextClosesThePicker() {
        AIAssist.stub = tagged()
        let (vc, p) = make()
        p.text = "two wrds and other text"; p.cursor = 0
        select(p, vc, "two wrds")
        settle { self.key(vc) == .sparkle }
        tapAI(vc)
        settle { self.allIn(vc) }
        select(p, vc, "other text")
        XCTAssertNil(vc.rewritePanelForTests)
        XCTAssertFalse(vc.keyboardViewForTests.isHidden)
        XCTAssertEqual(vc.aiStateForTests, .ready("other text"))
    }

    // review findings (each was a way to write the wrong text or show a stale state)
    func testTypingOverASelectedJustTypedWordReplacesIt() {
        AIAssist.stub = tagged()
        let (vc, p) = make(1)
        type("the toi", vc)
        select(p, vc, "toi")                                   // the word the engine was still typing
        type("s", vc)
        XCTAssertEqual(p.text, "The s")
    }

    func testNoNextWordsWhileTextIsSelected() {
        let (vc, p) = make()                                       // no Claude key (no stub)
        p.text = "hello there and more"; p.cursor = 6
        select(p, vc, "there and")
        settle()
        XCTAssertFalse(strip(vc).contains { $0.kind == .next }, "a tap would replace the selection")
    }

    func testTappingTheStripNeverTypesAKey() {
        AIAssist.stub = tagged()
        let (vc, p) = make()
        p.text = "All good here."; p.cursor = 0
        select(p, vc, p.text)
        settle { vc.aiStateForTests == .ready("All good here.") }
        let kv = vc.keyboardViewForTests
        XCTAssertNil(kv.capForTests(at: CGPoint(x: 100, y: 20)), "the strip is not the Q-row")
        XCTAssertNotNil(kv.capForTests(at: CGPoint(x: 100, y: kv.bounds.height - 30)))
    }
}

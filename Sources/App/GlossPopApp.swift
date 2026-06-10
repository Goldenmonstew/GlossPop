import AppKit
import Carbon.HIToolbox
import Sparkle

// GlossPop — app entry. Menu-bar agent (LSUIElement / .accessory), no Dock icon.
// M2 walking skeleton: hotkey → AX capture → non-activating near-cursor panel showing the captured text.

@main
enum GlossPopApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate            // NSApplication.delegate is weak…
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {   // …so keep it alive past ARC's last-use release
            app.run()
        }
    }
}

// Dev aid: vivid stripes for --demo-card screenshots (proves the card's behind-window blur).
private final class DemoStripesView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
        let stripe = bounds.width / CGFloat(colors.count)
        for (i, c) in colors.enumerated() {
            c.setFill()
            NSRect(x: CGFloat(i) * stripe, y: 0, width: stripe, height: bounds.height).fill()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var hotKeyDisplay: String { HotKeyConfig.displayString }

    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private let panel = TranslatePanelController()
    private let fmEngine = FoundationModelsEngine()
    private let settingsController = SettingsWindowController()
    // Sparkle auto-update (M6). startingUpdater:false → started in didFinishLaunching (skipped under XCTest).
    private let updaterController = SPUStandardUpdaterController(startingUpdater: false,
                                                                updaterDelegate: nil, userDriverDelegate: nil)
    private var currentTranslation: Task<Void, Never>?
    private var requestSeq = 0
    private var pendingAIWord: (source: String, kind: InputKind, src: String, tgt: String)?   // offline-miss "用 AI 解释一次" button
    let state = AppState()

    private var hotKeyOK = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under XCTest, GlossPop is only the test HOST — skip the agent lifecycle (the single-instance
        // guard would otherwise terminate the host when another GlossPop is running, breaking the test boot).
        if NSClassFromString("XCTestCase") != nil { return }
        // Single-instance: a 2nd launch adds a 2nd menu icon and silently fails to grab the hotkey.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.wanruncong.glosspop"
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil); return
        }
        BYOKConfig.migrateURLSplitIfNeeded()   // split a legacy full base URL into host + path (one-time)
        TargetLanguage.migrate()               // legacy single target.override → first/second language (one-time)
        DictionaryConfig.migrate()             // legacy dictionary on/off → DictionaryMode (one-time)
        NSApp.mainMenu = Self.makeMainMenu() // LSUIElement app has no menu → wire Edit (⌘C/V/X/A) + Window (⌘W)
        // No bare TCC dialog at launch — the prompt fires on FIRST USE from handleHotKey,
        // where our card explains WHY alongside the system dialog.
        panel.onDismiss = { [weak self] in self?.cancelCurrentTranslation() }
        panel.onOpenSettings = { [weak self] in self?.settingsController.show() }
        panel.onRunAIDictionary = { [weak self] in self?.runAIDictionaryButton() }
        registerHotKey()   // before the menu so it can reflect registration failure
        setUpMenuBar()
        updaterController.startUpdater()   // Sparkle: begin background update checks (not under XCTest)
        if CommandLine.arguments.contains("--open-settings") { settingsController.show() } // dev/verify aid
        if CommandLine.arguments.contains("--demo-card") { presentDemoCard() }   // dev/verify aid: silent screenshots
    }

    /// Dev aid (--demo-card): a populated word card without driving input, so chrome/typography
    /// changes can be verified from a window screenshot. Lays a striped backdrop UNDER the card so
    /// the behind-window blur is provable in a screenshot.
    private var demoBackdrop: NSWindow?
    private func presentDemoCard() {
        // The striped backdrop (for proving behind-window blur) startles anyone at the machine —
        // it now needs its OWN flag on top of --demo-card.
        if CommandLine.arguments.contains("--demo-stripes") {
            let mouse = NSEvent.mouseLocation
            let bw = NSWindow(contentRect: NSRect(x: mouse.x - 420, y: mouse.y - 330, width: 900, height: 620),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            bw.contentView = DemoStripesView()
            bw.level = .floating           // same level as the panel, ordered first → sits below it
            bw.orderFrontRegardless()
            demoBackdrop = bw
        }
        let raw = "会议 huìyì noun ① （指集会） meeting▸ 出席会议 attend a meeting ▸ 结束会议 close a meeting ② （指机构） council▸ 部长会议 council of ministers"
        guard let entry = SystemDictionary.parse(raw: raw, term: "会议") else { return }
        resetWordCard()
        panel.model.systemEntry = entry
        panel.model.subtitle = String(localized: "System dictionary · offline · entries follow your Dictionary.app setup")
        panel.present()
        panel.disarmDismissForDemo()   // stays up for screenshots despite clicks/scrolls elsewhere
    }

    // MARK: - Capture flow

    private func registerHotKey() {
        // User-configurable chord (default ⌃⌘T). NOTE: ⌃⌘D is macOS "Look Up in Dictionary" — avoided.
        hotKey = HotKey(keyCode: HotKeyConfig.keyCode,
                        modifiers: HotKeyConfig.modifiers) { [weak self] in
            self?.handleHotKey()
        }
        hotKeyOK = (hotKey != nil)
    }

    // While the Settings recorder is open, drop the global hotkey so the bound chord doesn't fire a
    // translation over Settings (and so the recorder actually sees that chord).
    func suspendHotKey() { hotKey = nil }
    func resumeHotKey() { registerHotKey() }

    /// Settings toggled 简洁浮窗 → re-render an already-open panel immediately.
    func applyPanelCompact() {
        panel.model.compact = PanelConfig.compact
        if panel.isVisible { panel.refresh() }
    }

    /// Atomically switch to a new chord. Commits to HotKeyConfig ONLY if registration succeeds; otherwise
    /// restores the previous chord (so a rejected chord can't leave the app with no hotkey).
    func applyHotKey(_ candidate: KeyChord.Candidate) -> Bool {
        hotKey = nil // deinit unregisters the old (Carbon EventHotKeyID id:1 can't be double-registered)
        if let new = HotKey(keyCode: candidate.keyCode, modifiers: candidate.modifiers, onKeyDown: { [weak self] in
            self?.handleHotKey()
        }) {
            hotKey = new
            hotKeyOK = true
            HotKeyConfig.keyCode = candidate.keyCode
            HotKeyConfig.modifiers = candidate.modifiers
            HotKeyConfig.displayKey = candidate.displayKey
            return true
        }
        registerHotKey()                 // re-register the still-saved previous config
        hotKeyOK = (hotKey != nil)
        return false
    }

    private var lastHotKeyFire = Date.distantPast
    private func handleHotKey() {
        // Collapse double-fires (Carbon hotkey + the menu's display key-equivalent — the M2-era incident
        // that originally forced the shortcut OUT of the menu; competitors like Easydict/Bob show it).
        let now = Date()
        guard now.timeIntervalSince(lastHotKeyFire) > 0.25 else { return }
        lastHotKeyFire = now
        // Cancel + invalidate any prior request first (covers Esc / failure / new-request races).
        cancelCurrentTranslation()
        switch TextCapture.capture() {
        case .text(let selection, _):
            let id = requestSeq
            let classified = InputClassifier.classify(selection)
            let tgt = TargetLanguage.displayCode(TargetLanguage.resolve(source: classified.source))
            // Source detection is unreliable for short words (NL misdetects "data"→ro etc.) — show "auto".
            let src = classified.confident ? classified.sourceCode : "auto"

            currentTranslation = Task { [weak self] in
                guard let self else { return }
                guard !Task.isCancelled, id == self.requestSeq else { return }
                if classified.kind == .sentence {
                    // Sentence → progressive: stream the translation, then append the syntax analysis.
                    if BYOKConfig.sentenceAnalysisEnabled, let engine = self.structuredRefiner() {
                        await self.runSentence(id: id, source: selection, src: src, tgt: tgt, engine: engine)
                    } else {
                        let refiner = await self.activeRefiner()
                        guard !Task.isCancelled, id == self.requestSeq else { return } // re-guard AFTER the await —
                        if let refiner {                                               // a late "未配置" card must not
                            await self.runPrimary(id: id, source: selection, src: src, tgt: tgt, refiner: refiner)
                        } else {                                                       // clobber a newer request
                            self.presentNeedsModel()
                        }
                    }
                } else {
                    // Word / phrase → mode-driven: system dictionary and/or AI bilingual dictionary.
                    await self.runWordPhrase(id: id, kind: classified.kind, source: selection, src: src, tgt: tgt)
                }
            }
        case .accessibilityDenied:
            AccessibilityPermission.promptIfNeeded()   // system dialog only ever shows once; card persists
            present(instant: String(localized: "GlossPop needs Accessibility permission to read your selection."),
                    subtitle: String(localized: "System Settings ▸ Privacy & Security ▸ Accessibility"),
                    action: .openAccessibility)
        case .empty:
            present(instant: String(localized: "No text selected."), subtitle: String(localized: "Select some text, then press \(Self.hotKeyDisplay)"))
        case .unreadable:
            present(instant: String(localized: "The selection can't be read here."),
                    subtitle: String(localized: "This app doesn't expose its selection — turn on the copy fallback in Settings"))
        }
    }

    /// Show a single-line card (messages / prompts).
    private func present(instant: String, subtitle: String, action: CardAction = .none) {
        panel.model.instant = instant
        panel.model.refined = ""
        panel.model.subtitle = subtitle
        panel.model.action = action
        panel.model.refining = false
        panel.model.essentialSubtitle = false
        panel.model.structured = false
        panel.model.analysis = nil
        panel.model.systemEntry = nil
        panel.model.aiEntry = nil
        panel.model.aiState = .none
        panel.model.aiNote = ""
        panel.present()
    }

    // MARK: - Word / phrase dictionary (macOS system + AI bilingual, mode-driven)

    private func presentNeedsModel() {
        present(instant: String(localized: "No translation model configured."),
                subtitle: String(localized: "Pick a provider and model in Settings (cloud / relay / local Ollama)"), action: .openSettings)
    }

    /// Reset the card to a fresh word/phrase state.
    private func resetWordCard() {
        panel.model.instant = ""; panel.model.refined = ""
        panel.model.structured = false; panel.model.analysis = nil
        panel.model.systemEntry = nil; panel.model.aiEntry = nil; panel.model.aiState = .none
        panel.model.aiProvenance = ""; panel.model.aiNote = ""
        panel.model.action = .none; panel.model.refining = false
        panel.model.essentialSubtitle = false
    }

    /// A field counts as content only if it isn't an echoed template placeholder ("(in zh-Hans)") and
    /// isn't just the source word echoed back.
    private func meaningful(_ v: String, source: String) -> Bool {
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if t.hasPrefix("(in "), t.hasSuffix(")") { return false }
        return t.caseInsensitiveCompare(source) != .orderedSame
    }

    private func entryHasContent(_ e: DictionaryEntry, source: String) -> Bool {
        e.senses.contains { meaningful($0.translation, source: source) || meaningful($0.definition, source: source) }
            || e.idioms.contains { meaningful($0.meaning, source: source) } // idiom-only entries count
    }

    /// Blank out echoed template placeholders so the card never renders "(in zh-Hans)" in any field —
    /// the content gate alone doesn't stop a mixed entry (valid translation + placeholder definition).
    private func sanitized(_ e: DictionaryEntry) -> DictionaryEntry {
        func strip(_ v: String) -> String {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t.hasPrefix("(in ") && t.hasSuffix(")")) ? "" : v
        }
        var out = e
        out.senses = e.senses.map { s in
            var x = s
            x.definition = strip(s.definition); x.translation = strip(s.translation)
            x.examples = s.examples.map { Example(source: strip($0.source), target: strip($0.target)) }
            x.synonyms = s.synonyms.map(strip)
            return x
        }
        out.idioms = e.idioms.map { Idiom(phrase: strip($0.phrase), meaning: strip($0.meaning)) }
        return out
    }

    /// First meaningful content of an AI entry for a history summary (senses, then idioms).
    private func aiSummary(_ e: DictionaryEntry, source: String) -> String? {
        for s in e.senses { for v in [s.translation, s.definition] where meaningful(v, source: source) { return v } }
        for i in e.idioms { for v in [i.meaning, i.phrase] where meaningful(v, source: source) { return v } }
        return nil
    }

    /// Word/phrase routing per DictionaryMode: offline-only NEVER auto-sends to the cloud.
    private func runWordPhrase(id: Int, kind: InputKind, source: String, src: String, tgt: String) async {
        guard !Task.isCancelled, id == requestSeq else { return }
        let mode = DictionaryConfig.mode
        let systemHit = mode.usesSystem ? SystemDictionary.lookup(source) : nil

        if let sys = systemHit {
            resetWordCard()
            panel.model.systemEntry = sys
            // Restore the v0.1.13 English-only nudge: a pure-English entry usually means no 中文 dictionary
            // is enabled — point at Dictionary.app instead of a generic claim.
            let sysSubtitle = sys.hasCJK ? String(localized: "System dictionary · offline · entries follow your Dictionary.app setup")
                                         : String(localized: "System dictionary · offline · add dictionaries in Dictionary.app for your language")
            // Honest footer: when an AI request is about to go out, don't show a pure-offline label.
            panel.model.subtitle = mode.alwaysAI ? String(localized: "System dictionary · offline · querying the AI dictionary…") : sysSubtitle
            panel.model.aiState = mode.alwaysAI ? .loading : .none
            panel.present()
            HistoryStore.record(source: source, result: sys.body.isEmpty ? sys.headword : sys.body, subtitle: sysSubtitle)
            if mode.alwaysAI { await runAIDictionary(id: id, kind: kind, source: source, src: src, tgt: tgt, hasSystem: true) }
            return
        }
        // System miss (or system off).
        if mode.autoAI {
            resetWordCard()
            panel.model.aiState = .loading
            panel.model.subtitle = String(localized: "Querying the AI dictionary…")
            panel.present()
            await runAIDictionary(id: id, kind: kind, source: source, src: src, tgt: tgt, hasSystem: false)
        } else {
            // Offline-only + miss → tell the user, offer a ONE-TIME AI lookup (no automatic cloud send).
            pendingAIWord = (source, kind, src, tgt)
            present(instant: String(localized: "“\(source)” isn't in the system dictionary."),
                    subtitle: String(localized: "Enable more dictionaries in Dictionary.app, or —"), action: .aiDictionary)
        }
    }

    /// AI bilingual dictionary (definition in 第二语言, meaning in 第一语言). `hasSystem`: a system entry is
    /// already shown above (progressive append); otherwise the AI card is the primary result.
    /// Fallback ladder (parity with v0.1.13): no BYOK → Apple FM plain translation; structured
    /// miss/failure with no system entry → plain translation on the SAME engine (provenance preserved).
    private func runAIDictionary(id: Int, kind: InputKind, source: String, src: String, tgt: String,
                                 hasSystem: Bool) async {
        guard !Task.isCancelled, id == requestSeq else { return }
        let sysPrefix = String(localized: "System dictionary · offline")
        guard let engine = structuredRefiner() else {
            if hasSystem {
                panel.model.aiState = .failed
                panel.model.aiNote = String(localized: "AI not configured — pick a model in Settings")
                panel.model.essentialSubtitle = true
                panel.model.subtitle = String(localized: "\(sysPrefix) · AI not configured (pick a model in Settings)")
                panel.refresh()
            } else {
                let refiner = await activeRefiner()   // FM-only machine: plain translation, like v0.1.13
                guard !Task.isCancelled, id == requestSeq else { return } // re-guard AFTER the await
                if let refiner {
                    await runPrimary(id: id, source: source, src: src, tgt: tgt, refiner: refiner, reusesCard: true)
                } else {
                    presentNeedsModel()
                }
            }
            return
        }
        if panel.model.aiState != .loading { panel.model.aiState = .loading; panel.refresh() }
        do {
            let result = try await engine.structured(kind: kind == .sentence ? .word : kind, source: source,
                                                     firstLanguage: TargetLanguage.firstLanguage,
                                                     secondLanguage: TargetLanguage.secondLanguage)
            guard !Task.isCancelled, id == requestSeq else { return }
            if case .dictionary(let entry) = result, entryHasContent(entry, source: source) {
                panel.model.aiEntry = sanitized(entry)
                panel.model.aiProvenance = engine.provenance
                panel.model.aiState = .done
                // Honest provenance in the footer + history (don't label a cloud AI result as offline).
                panel.model.subtitle = hasSystem ? String(localized: "\(sysPrefix) + AI dictionary\(engine.provenance)") : String(localized: "AI dictionary\(engine.provenance)")
                panel.refresh()
                if !hasSystem {   // the system hit already recorded this lookup — don't double-record
                    let summary = aiSummary(entry, source: source) ?? source
                    if summary != source { HistoryStore.record(source: source, result: summary, subtitle: panel.model.subtitle) }
                }
            } else if hasSystem {
                panel.model.aiState = .failed   // AI miss (empty/echo); system entry stays
                panel.model.aiNote = String(localized: "AI dictionary: no result")
                panel.model.essentialSubtitle = true
                panel.model.subtitle = String(localized: "\(sysPrefix) · AI dictionary: no result\(engine.provenance)")
                panel.refresh()
            } else {
                // AI dictionary came back empty → plain translation on the same engine (old behavior).
                await runPrimary(id: id, source: source, src: src, tgt: tgt, refiner: engine, reusesCard: true)
            }
        } catch {
            guard !Task.isCancelled, id == requestSeq else { return }
            if hasSystem {
                panel.model.aiState = .failed
                panel.model.aiNote = String(localized: "AI dictionary failed")
                panel.model.essentialSubtitle = true
                panel.model.subtitle = String(localized: "\(sysPrefix) · AI dictionary failed\(engine.provenance) · \(error.localizedDescription)")
                panel.refresh()
            } else {
                // Structured call failed → plain translation on the same engine; its own error path is honest.
                await runPrimary(id: id, source: source, src: src, tgt: tgt, refiner: engine, reusesCard: true)
            }
        }
    }

    /// Triggered by the "用 AI 解释一次" button on an offline-miss card.
    private func runAIDictionaryButton() {
        guard let (source, kind, src, tgt) = pendingAIWord else { return }
        cancelCurrentTranslation()
        let id = requestSeq
        resetWordCard()
        panel.model.aiState = .loading
        panel.model.subtitle = String(localized: "Querying the AI dictionary…")
        panel.refresh()
        currentTranslation = Task { [weak self] in
            guard let self else { return }
            await self.runAIDictionary(id: id, kind: kind, source: source, src: src, tgt: tgt, hasSystem: false)
        }
    }

    /// Structured engine for the sentence-syntax stage. FM @Generable structured is a stub, so only BYOK
    /// provides structured output; without it the sentence path falls through to plain translation.
    private func structuredRefiner() -> StructuredRefineEngine? {
        BYOKConfig.snapshot().map { OpenAICompatibleEngine(snapshot: $0) }
    }

    /// Sentence = PROGRESSIVE: stream the translation first (instant feel), THEN append the syntax analysis,
    /// so the user isn't staring at a spinner while one big combined call completes.
    private func runSentence(id: Int, source: String, src: String, tgt: String, engine: StructuredRefineEngine) async {
        guard !Task.isCancelled, id == requestSeq else { return }
        panel.model.instant = ""; panel.model.refined = ""; panel.model.systemEntry = nil
        panel.model.aiEntry = nil; panel.model.aiState = .none
        panel.model.structured = false; panel.model.analysis = nil
        panel.model.action = .none; panel.model.refining = true
        panel.model.essentialSubtitle = false
        panel.model.subtitle = String(localized: "\(src) → \(tgt) · \(engine.label) translating…")
        panel.present()
        // Stage 1 — streamed translation.
        var translation = ""
        do {
            for try await text in engine.refine(source: source, draft: "", targetCode: tgt) {
                guard !Task.isCancelled, id == requestSeq else { return }
                translation = text; panel.model.refined = text; panel.refresh()
            }
        } catch {
            guard !Task.isCancelled, id == requestSeq else { return }
            panel.model.refining = false
            panel.model.refined = translation.isEmpty ? source : translation
            panel.model.subtitle = String(localized: "Translation failed (\(engine.label)\(engine.provenance)) · \(error.localizedDescription)")
            panel.model.essentialSubtitle = true   // failure note must survive 简洁浮窗
            panel.refresh()
            if !translation.isEmpty { HistoryStore.record(source: source, result: translation, subtitle: panel.model.subtitle) }
            return
        }
        guard !Task.isCancelled, id == requestSeq else { return }
        guard !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            panel.model.refining = false
            panel.model.refined = source
            panel.model.subtitle = String(localized: "Translation failed (\(engine.label)\(engine.provenance)) · empty model response")
            panel.model.essentialSubtitle = true
            panel.refresh(); return
        }
        // Stage 2 — syntax analysis appended (translation stays on screen).
        panel.model.subtitle = String(localized: "\(src) → \(tgt) · \(engine.label) analysing…")
        panel.refresh()
        var analysisFailed = false
        do {
            // firstLanguage carries the resolved TARGET; secondLanguage carries the user's NATIVE language
            // so grammar explanations are readable even when translating out of it (e.g. zh sentence → en).
            let result = try await engine.structured(kind: .sentence, source: source,
                                                     firstLanguage: tgt, secondLanguage: TargetLanguage.firstLanguage)
            guard !Task.isCancelled, id == requestSeq else { return }
            if case .sentence(var analysis) = result {
                analysis.refinedTranslation = translation   // keep the stage-1 translation stable (no flicker)
                panel.model.analysis = analysis
                panel.model.structured = true
            }
        } catch {
            guard !Task.isCancelled, id == requestSeq else { return } // syntax failed → keep the translation, but say so
            analysisFailed = true
        }
        panel.model.refining = false
        // Translation succeeded either way; be honest when only the syntax analysis failed.
        panel.model.subtitle = "\(src) → \(tgt) · \(engine.label)\(engine.provenance)" + (analysisFailed ? String(localized: " · analysis failed") : "")
        panel.model.essentialSubtitle = analysisFailed   // partial failure stays visible in 简洁浮窗
        panel.refresh()
        HistoryStore.record(source: source, result: translation, subtitle: panel.model.subtitle)
    }

    /// The user's CONFIGURED model wins: if BYOK is ready, use it — so the model, reasoning_effort, and
    /// custom prompt they set actually apply. Apple FM is only the fallback when no BYOK is set up.
    private func activeRefiner() async -> RefineEngine? {
        if let byok = BYOKConfig.snapshot().map({ OpenAICompatibleEngine(snapshot: $0) }) { return byok }
        if await fmEngine.isAvailable() { return fmEngine }
        return nil
    }

    /// Plain LLM translation, streamed (no NMT). `tgt` is resolved by the caller via TargetLanguage.
    /// `reusesCard`: true when called as a structured-fallback (card already presented → just refresh).
    private func runPrimary(id: Int, source: String, src: String, tgt: String, refiner: RefineEngine,
                           reusesCard: Bool = false) async {
        guard !Task.isCancelled, id == requestSeq else { return }
        panel.model.instant = ""
        panel.model.refined = ""
        panel.model.structured = false
        panel.model.analysis = nil
        panel.model.systemEntry = nil
        panel.model.aiEntry = nil
        panel.model.aiState = .none
        panel.model.action = .none
        panel.model.refining = true
        panel.model.essentialSubtitle = false
        panel.model.subtitle = String(localized: "\(src) → \(tgt) · \(refiner.label) translating…")
        if reusesCard { panel.refresh() } else { panel.present() }  // avoid a double-present flash on fallback
        var accumulated = ""
        do {
            for try await text in refiner.refine(source: source, draft: "", targetCode: tgt) {
                guard !Task.isCancelled, id == requestSeq else { return }
                accumulated = text
                panel.model.refined = text
                panel.refresh()
            }
            guard !Task.isCancelled, id == requestSeq else { return }
            // A 200 with no usable delta is NOT a success — there's no NMT floor now.
            guard !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RefineError.message(String(localized: "Empty model response"))
            }
            panel.model.refining = false
            panel.model.subtitle = "\(src) → \(tgt) · \(refiner.label)\(refiner.provenance)"
            panel.refresh()
            HistoryStore.record(source: source, result: accumulated, subtitle: panel.model.subtitle)
        } catch {
            guard !Task.isCancelled, id == requestSeq else { return }
            panel.model.refining = false
            let partial = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            if partial.isEmpty {
                // Nothing streamed → show the original + failure.
                panel.model.refined = source
                panel.model.subtitle = String(localized: "Translation failed (\(refiner.label)\(refiner.provenance)) · \(error.localizedDescription)")
                panel.model.essentialSubtitle = true   // failure note must survive 简洁浮窗
            } else {
                // Keep what streamed; mark it interrupted. Record the PARTIAL, never source→source.
                panel.model.subtitle = String(localized: "Translation interrupted (\(refiner.label)\(refiner.provenance)) · \(error.localizedDescription)")
                panel.model.essentialSubtitle = true
                HistoryStore.record(source: source, result: accumulated, subtitle: panel.model.subtitle)
            }
            panel.refresh()
        }
    }

    private func cancelCurrentTranslation() {
        currentTranslation?.cancel()
        currentTranslation = nil
        requestSeq &+= 1   // invalidate any in-flight result so a late snapshot can't render
    }

    @objc func openSettings() { settingsController.show() }

    /// Standard main menu so text fields get Cut/Copy/Paste/Select All (an LSUIElement app has none,
    /// so ⌘C/⌘V/⌘X/⌘A wouldn't reach the first responder — that's why Settings fields couldn't paste).
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "About GlossPop"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let prefs = NSMenuItem(title: String(localized: "Settings…"), action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        appMenu.addItem(prefs)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Hide GlossPop"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: String(localized: "Quit GlossPop"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // Window menu — without it ⌘W can't close the Settings window (whole main menu is custom).
        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: String(localized: "Minimise"), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        return main
    }

    private static func cocoaModifiers(fromCarbon m: UInt32) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if m & UInt32(cmdKey) != 0 { f.insert(.command) }
        if m & UInt32(optionKey) != 0 { f.insert(.option) }
        if m & UInt32(controlKey) != 0 { f.insert(.control) }
        if m & UInt32(shiftKey) != 0 { f.insert(.shift) }
        return f
    }

    // MARK: - Menu bar

    private func setUpMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble",
                                     accessibilityDescription: "GlossPop")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        let menu = NSMenu()
        menu.delegate = self          // repopulated on each open → fresh hotkey title + history
        item.menu = menu
        self.statusItem = item
    }

    // Rebuild the menu each time it opens so the chord title + history stay current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem.sectionHeader(title: "GlossPop \(state.versionString)"))   // system header style
        // No keyEquivalent — the chord is the GLOBAL Carbon hotkey; a menu key-equiv would double-fire.
        let chord = Self.hotKeyDisplay
        let captureTitle = hotKeyOK ? String(localized: "Translate Selection") : String(localized: "Translate Selection (\(chord) failed to register · click here)")
        let capture = NSMenuItem(title: captureTitle, action: #selector(captureFromMenu), keyEquivalent: "")
        // Right-aligned shortcut like every system menu (the debounce in handleHotKey guards the
        // historical double-fire). Single printable keys only — special keys keep the title form.
        if hotKeyOK, HotKeyConfig.displayKey.count == 1 {
            capture.keyEquivalent = HotKeyConfig.displayKey.lowercased()
            capture.keyEquivalentModifierMask = Self.cocoaModifiers(fromCarbon: HotKeyConfig.modifiers)
        } else if hotKeyOK {
            capture.title = String(localized: "Translate Selection (\(chord))")
        }
        capture.target = self
        menu.addItem(capture)

        let historyItem = NSMenuItem(title: String(localized: "Recent Translations"), action: nil, keyEquivalent: "")
        historyItem.submenu = buildHistoryMenu()
        menu.addItem(historyItem)

        let settings = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let updates = NSMenuItem(title: String(localized: "Check for Updates…"),
                                 action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updates.target = updaterController
        menu.addItem(updates)
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit GlossPop"),
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func buildHistoryMenu() -> NSMenu {
        let sub = NSMenu()
        guard HistoryStore.isEnabled else {   // off → don't decode the store on every menu open
            let off = NSMenuItem(title: String(localized: "History is off (Settings ▸ General)"), action: nil, keyEquivalent: ""); off.isEnabled = false
            sub.addItem(off)
            return sub
        }
        let entries = HistoryStore.all()
        if entries.isEmpty {
            let empty = NSMenuItem(title: String(localized: "(Empty)"), action: nil, keyEquivalent: ""); empty.isEnabled = false
            sub.addItem(empty)
            return sub
        }
        for entry in entries.prefix(15) {
            let title = "\(snippet(entry.source, 24)) → \(snippet(entry.result, 28))"
            let it = NSMenuItem(title: title, action: #selector(openHistory(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = entry
            it.toolTip = "\(entry.source) → \(entry.result)"   // hover reveals the full pair
            sub.addItem(it)
        }
        sub.addItem(.separator())
        let clear = NSMenuItem(title: String(localized: "Clear History"), action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        sub.addItem(clear)
        return sub
    }

    private func snippet(_ s: String, _ n: Int) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ")
        return one.count > n ? String(one.prefix(n)) + "…" : one
    }

    @objc private func captureFromMenu() { handleHotKey() }

    @objc private func openHistory(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? HistoryEntry else { return }
        cancelCurrentTranslation()
        present(instant: entry.result, subtitle: String(localized: "\(entry.subtitle) · history"))
    }

    @objc private func clearHistory() {
        HistoryStore.clear()
        statusItem?.menu?.cancelTracking() // close the menu so stale items aren't left visible/clickable (P2)
    }
}

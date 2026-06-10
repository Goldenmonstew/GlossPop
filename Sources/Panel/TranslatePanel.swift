import AppKit
import SwiftUI

enum CardAction: Equatable { case none, openAccessibility, openSettings, aiDictionary }
enum AIDictState: Equatable { case none, loading, done, failed }

// Observable card state — lets instant→refine stream into the SAME card (PLAN §2.2/§2.5).
@MainActor @Observable
final class PanelModel {
    var instant: String = ""        // a message line (prompts/errors); plain results stream into `refined`
    var refined: String = ""        // refined translation; streams in, empty until refine starts
    var subtitle: String = ""
    var action: CardAction = .none
    var refining: Bool = false      // show a small spinner while refine streams
    // M3.5 input-aware structured output (sentence syntax; word/phrase entries live in aiEntry below)
    var structured: Bool = false
    var analysis: SentenceAnalysis?
    // Word/phrase lookup: a combined card = macOS system section (instant/offline) + AI bilingual section.
    var systemEntry: SystemDictionary.Entry?
    var aiEntry: DictionaryEntry?          // AI bilingual dictionary result
    var aiState: AIDictState = .none       // AI section: none / loading / done / failed
    var aiProvenance: String = ""          // " · 云" / " · 本机" for the AI section label
    var aiNote: String = ""                // failed-state explanation (未配置 / 失败 / 暂无结果)
    var essentialSubtitle: Bool = false    // failure/interruption notes must survive 简洁浮窗
    var compact: Bool = PanelConfig.compact // mirrored so an OPEN panel re-renders when toggled
    var isWordCard: Bool { systemEntry != nil || aiState != .none }
}

// Near-cursor, non-activating result panel (PLAN §5.3). Borderless + .nonactivatingPanel — M0 confirmed
// it doesn't steal focus and the source selection survives. Card updates in place via PanelModel;
// dismiss monitors are transient (installed only while visible). The card grows DOWNWARD on streaming.
@MainActor
final class TranslatePanelController {
    let model = PanelModel()
    var onDismiss: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var panel: NSPanel?
    private var hosting: NSHostingView<ResultCard>?
    private var monitors: [Any] = []
    private var escTap: EscEventTap?

    /// First show for a request: set the model fields, then call this.
    func present() {
        model.compact = PanelConfig.compact   // pick up the Settings toggle for each new card
        let panel = panelInstance()
        resize(anchorTop: false)
        positionNearCursor()
        panel.orderFrontRegardless()
        installDismissMonitors()
    }

    /// After mutating the model during streaming — resizes keeping the top edge fixed.
    func refresh() { resize(anchorTop: true) }

    /// Dev aid (--demo-card): keep the card up while screenshots are taken — no dismiss monitors.
    func disarmDismissForDemo() { removeMonitors() }

    func dismiss() {
        removeMonitors()
        panel?.orderOut(nil)
        onDismiss?()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Panel

    private func panelInstance() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 64),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.backgroundColor = .clear
        p.isOpaque = false                       // transparent window — correct compositing/shadow
        p.animationBehavior = .utilityWindow     // system fade on show/hide, like every Apple transient surface
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: ResultCard(
            model: model,
            onAction: { [weak self] in self?.handleAction() },
            onDismiss: { [weak self] in self?.dismiss() }))
        // REAL chrome at the window level: SwiftUI materials can only blend within the
        // window — over a clear panel they tint without blurring, fake frost. Tahoe gets Liquid Glass;
        // macOS 15 gets the literal Look Up material (popover, behind-window).
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 16
            glass.contentView = host
            p.contentView = glass
        } else {
            let vev = NSVisualEffectView()
            vev.material = .popover
            vev.blendingMode = .behindWindow
            vev.state = .active
            vev.maskImage = Self.roundedMask(radius: 16)
            host.translatesAutoresizingMaskIntoConstraints = false
            vev.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: vev.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: vev.trailingAnchor),
                host.topAnchor.constraint(equalTo: vev.topAnchor),
                host.bottomAnchor.constraint(equalTo: vev.bottomAnchor),
            ])
            p.contentView = vev
        }
        hosting = host
        panel = p
        return p
    }

    /// Stretchable rounded-rect mask so the visual-effect blur clips to the card shape.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }

    private func resize(anchorTop: Bool) {
        guard let panel, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        var height = min(max(hosting.fittingSize.height, 56), 520) // cap; long content scrolls inside the card
        let oldTop = panel.frame.maxY
        if anchorTop, let vf = screenForCursor()?.visibleFrame {
            // Grow only within the space BELOW the fixed top edge. The old clamp instead shifted the whole
            // window up when growth hit the screen bottom — the card visibly jumped the moment the AI
            // section landed (user feedback). Content beyond this scrolls inside the card.
            height = min(height, max(oldTop - vf.minY, 56))
        }
        if anchorTop, panel.isVisible {
            // Streaming growth eases instead of snapping. Top edge stays fixed, so reading
            // mid-animation maxY is stable; repeated calls retarget the same animator.
            let target = NSRect(x: panel.frame.minX, y: oldTop - height, width: 360, height: height)
            guard abs(target.height - panel.frame.height) > 0.5 else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setContentSize(NSSize(width: 360, height: height))
            if anchorTop {
                var f = panel.frame
                f.origin.y = oldTop - f.height             // keep the top edge fixed → grow downward
                panel.setFrameOrigin(f.origin)
            }
        }
    }

    private func positionNearCursor() {
        guard let panel else { return }
        let size = panel.frame.size
        let mouse = NSEvent.mouseLocation
        let screen = screenForCursor()
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)
        if let vf = screen?.visibleFrame {
            // FLIP to the other side of the cursor when there's no room (like system popovers), instead of
            // clamping the card ONTO the cursor/selection.
            if origin.y < vf.minY { origin.y = mouse.y + 12 }
            if origin.x + size.width > vf.maxX { origin.x = mouse.x - size.width - 12 }
            origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
            origin.y = min(max(origin.y, vf.minY), vf.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
    }

    private func screenForCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    var onRunAIDictionary: (() -> Void)?

    private func handleAction() {
        switch model.action {
        case .openAccessibility: AccessibilityPermission.openSettings()
        case .openSettings: dismiss(); onOpenSettings?()
        case .aiDictionary: onRunAIDictionary?()
        case .none: break
        }
    }

    // MARK: - Transient dismiss monitors (Esc + outside click)

    private func installDismissMonitors() {
        removeMonitors()
        // Outside click OR scrolling the page behind dismisses — exactly the system Look Up behaviour.
        // (Global monitors never see events delivered to our own panel, so scrolling INSIDE the card is safe.)
        let outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] _ in
            self?.dismiss()
        }
        let localEsc = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.dismiss(); return nil } // Esc when the panel itself is key
            return event
        }
        var collected: [Any] = [outsideClick, localEsc].compactMap { $0 }
        // Consuming Esc tap (panel stays non-key, so a passive global monitor couldn't swallow Esc).
        let tap = EscEventTap { [weak self] in self?.dismiss() }
        if tap.start() {
            escTap = tap
        } else if let globalEsc = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            if event.keyCode == 53 { self?.dismiss() }   // fallback: can't consume, but still dismisses
        }) {
            collected.append(globalEsc)
        }
        monitors = collected
    }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        escTap?.stop()
        escTap = nil
    }
}

// MARK: - Card

private struct ResultCard: View {
    let model: PanelModel
    let onAction: () -> Void
    let onDismiss: () -> Void

    private var actionTitle: String? {
        switch model.action {
        case .openAccessibility: return String(localized: "Open Accessibility Settings")
        case .openSettings: return String(localized: "Open Settings")
        case .aiDictionary: return String(localized: "Explain with AI")
        case .none: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {                          // only the CONTENT scrolls; footer stays pinned
                    VStack(alignment: .leading, spacing: 8) {
                        if model.isWordCard {
                            WordPhraseCard(model: model)
                        } else if model.structured, let analysis = model.analysis {
                            SentenceCard(analysis: analysis)
                        } else {
                            plainBody
                        }
                    }
                    .textSelection(.enabled)   // the WHOLE card is copyable, not a lucky subset
                    .frame(width: 332, alignment: .leading)
                }
                .scrollIndicators(.never)   // no chunky legacy scroller in the card (Apple's Look Up popover
                                            // does the same); wheel/trackpad scrolling is unaffected
                .frame(width: 332)
                .frame(maxHeight: 440)
                // A long system entry hides the appended AI section below the fold — bring it into view
                // when the result lands so the user actually notices it arrived. Deferred one tick
                // and NOT animated: an animated scroll racing the panel's own resize made the whole card
                // bounce when the AI section landed (user feedback).
                .onChange(of: model.aiState) {
                    if model.aiState == .done, model.systemEntry != nil {
                        DispatchQueue.main.async { proxy.scrollTo("aiSection", anchor: .top) }
                    }
                }
            }
            footer                                    // provenance + spinner always visible
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        // chrome (blur/glass + corner) now lives on the WINDOW (NSGlassEffectView / NSVisualEffectView) —
        // a SwiftUI material here can't sample behind the window and double-draws over the real one
    }

    /// Nothing has arrived yet → show the loader on the FIRST content line, not buried in the footer
    /// (user feedback: a long sentence request looked like an empty box with a tiny corner spinner).
    private var showsInlineLoader: Bool {
        model.refining && model.refined.isEmpty && model.instant.isEmpty
    }

    @ViewBuilder private var plainBody: some View {
        if showsInlineLoader {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                if !model.compact {
                    Text("Translating…").font(.callout).foregroundStyle(.secondary)
                }
            }
        } else if !model.refined.isEmpty {
            Text(model.refined).font(.body).fixedSize(horizontal: false, vertical: true)
            if !model.instant.isEmpty {
                Text(model.instant).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(model.instant).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The card carries an actual RESULT (vs a message/error card whose guidance lives in the subtitle).
    private var hasResultContent: Bool {
        model.isWordCard || (model.structured && model.analysis != nil) || !model.refined.isEmpty
    }
    /// 简洁浮窗: hide the provenance/hint line on result cards only — message cards keep their guidance,
    /// and failure/interruption notes (essentialSubtitle) always show even on a result card.
    /// `refining` counts as a result card too: the initial "… 翻译中…" line is exactly the hint the user
    /// opted out of — the footer keeps its spinner, so the card still visibly works (user feedback).
    private var showSubtitle: Bool {
        !(model.compact && (hasResultContent || model.refining) && !model.essentialSubtitle)
    }

    @ViewBuilder private var footer: some View {
        // The footer spinner is redundant while the inline first-line loader is up; compact result cards
        // with nothing else to show get no footer row at all.
        let footerSpinner = model.refining && !showsInlineLoader
        if showSubtitle || footerSpinner || actionTitle != nil {
            HStack(spacing: 8) {
                if showSubtitle { Text(model.subtitle).font(.caption).foregroundStyle(.secondary) }
                if footerSpinner { ProgressView().controlSize(.mini) }
                Spacer()
                if let actionTitle { Button(actionTitle, action: onAction).controlSize(.small) }
            }
        }
    }
}

// MARK: - Input-aware cards (M3.5)

private struct DictionaryCard: View {
    let entry: DictionaryEntry
    // Drop placeholder entries the model echoes from the schema (empty phrase+meaning rendered as a stray ":").
    private var idioms: [Idiom] { entry.idioms.filter { !$0.phrase.isEmpty || !$0.meaning.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !entry.headword.isEmpty { Text(entry.headword).font(.title3).bold() }
                if !entry.pronunciation.isEmpty { Text(entry.pronunciation).font(.callout).foregroundStyle(.secondary) }
            }
            ForEach(Array(entry.senses.enumerated()), id: \.offset) { _, sense in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if !sense.partOfSpeech.isEmpty {
                            Text(sense.partOfSpeech).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                        Text(sense.translation).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    // Only show the definition when it adds something beyond the translation (no duplicate line).
                    if !sense.definition.isEmpty, sense.definition != sense.translation {
                        Text(sense.definition).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(sense.examples.filter { !$0.source.isEmpty || !$0.target.isEmpty }.prefix(2).enumerated()), id: \.offset) { _, ex in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("·").font(.caption).foregroundStyle(.secondary)
                            Text([ex.source, ex.target].filter { !$0.isEmpty }.joined(separator: " — "))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if sense.synonyms.contains(where: { !$0.isEmpty }) {
                        Text("≈ " + sense.synonyms.filter { !$0.isEmpty }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !idioms.isEmpty {
                Divider()
                ForEach(Array(idioms.enumerated()), id: \.offset) { _, idiom in
                    Text([idiom.phrase, idiom.meaning].filter { !$0.isEmpty }.joined(separator: "："))
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// Word/phrase: macOS system section (instant/offline) on top, AI bilingual section below (loading→result/fail).
// The system section is NEVER replaced by AI.
private struct WordPhraseCard: View {
    let model: PanelModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sys = model.systemEntry { SystemDictionaryCard(entry: sys) }
            if model.aiState != .none {
                if model.systemEntry != nil { Divider() }
                Group {
                    switch model.aiState {
                    case .loading:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            if !model.compact {   // 简洁浮窗: spinner only, no caption
                                Text("Loading the AI dictionary…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    case .failed:   // say WHY (未配置 / 失败 / 暂无结果), not a uniform shrug
                        Text(model.aiNote.isEmpty ? String(localized: "AI: no result") : model.aiNote)
                            .font(.caption).foregroundStyle(.secondary)
                    case .done:
                        if let ai = model.aiEntry {
                            VStack(alignment: .leading, spacing: 6) {
                                if model.systemEntry != nil, !model.compact {   // 简洁浮窗 hides the section label
                                    Text("AI dictionary\(model.aiProvenance)").font(.caption2).foregroundStyle(.tertiary)
                                }
                                DictionaryCard(entry: ai)
                            }
                        }
                    case .none: EmptyView()
                    }
                }
                .id("aiSection")   // scroll anchor — the appended AI result must be brought into view
            }
        }
    }
}

private struct SystemDictionaryCard: View {
    let entry: SystemDictionary.Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !entry.headword.isEmpty { Text(entry.headword).font(.title3).bold() }
                if !entry.pronunciation.isEmpty { Text(entry.pronunciation).font(.callout).foregroundStyle(.secondary) }
            }
            if !entry.body.isEmpty {
                Text(Self.styled(entry.body)).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Look Up-like hierarchy instead of one flat run: bold POS/section headers and sense markers,
    /// secondary-coloured example lines (classification lives in SystemDictionary — unit-tested).
    private static func styled(_ body: String) -> AttributedString {
        var out = AttributedString()
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        for (i, sub) in lines.enumerated() {
            let line = String(sub)
            var a = AttributedString(line)
            switch SystemDictionary.classifyLine(line) {
            case .example:
                a.foregroundColor = .secondary
            case .posHeader, .sectionHeader:
                a.font = .callout.bold()
            case .sense:
                let t = line.drop(while: { $0 == " " })
                if let marker = t.split(separator: " ").first,
                   let r = a.range(of: String(marker)) { a[r].font = .callout.bold() }
            case .plain:
                break
            }
            out += a
            if i < lines.count - 1 { out += AttributedString("\n") }
        }
        return out
    }
}

// 直译 was dropped on user request: the streamed stage-1 translation is already on screen, and the
// literal variant arrived late (with the syntax JSON) only to occupy a near-duplicate line.
private struct SentenceCard: View {
    let analysis: SentenceAnalysis
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(analysis.refinedTranslation).font(.body).fixedSize(horizontal: false, vertical: true)
            if !analysis.syntax.isEmpty {
                Divider()
                let s = analysis.syntax
                if !s.subject.isEmpty || !s.predicate.isEmpty {
                    Text("S: \(s.subject)   V: \(s.predicate)\(s.objects.isEmpty ? "" : String(localized: "   O: ") + s.objects.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(s.grammarPoints.filter { !$0.point.isEmpty || !$0.explanation.isEmpty }.prefix(4).enumerated()), id: \.offset) { _, gp in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("·").font(.caption).foregroundStyle(.secondary)
                        Text([gp.point, gp.explanation].filter { !$0.isEmpty }.joined(separator: "："))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if analysis.notes.contains(where: { !$0.isEmpty }) {
                Text(analysis.notes.filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

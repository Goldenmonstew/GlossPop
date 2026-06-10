import AppKit
import SwiftUI

// Minimal Settings window for BYOK config (PLAN §4). A user-invoked window MAY activate the app
// (unlike the translate panel). Text entry lives here, never in the non-activating panel.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var host: NSHostingController<SettingsView>?

    func show() {
        // Become a regular app while Settings is open so the window reliably comes to the front
        // (an .accessory app can't bring a window forward dependably). Reverted on close.
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            let h = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: h)
            w.title = String(localized: "GlossPop Settings")
            w.styleMask = [.titled, .closable, .miniaturizable]   // System Settings allows ⌘M too
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setContentSize(NSSize(width: 480, height: 760)) // Form has no intrinsic height — size explicitly
            // Frame restore happens HERE, once, at creation — calling setFrameUsingName again inside
            // show() left the window ordered OUT on relaunch (empirically reproducible). Centre on the
            // cursor screen only when no frame has ever been saved (first launch).
            w.setFrameAutosaveName("GlossPopSettings")
            if w.setFrameUsingName("GlossPopSettings") == false {
                let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.screens.first
                if let screen {
                    let vf = screen.visibleFrame
                    w.setFrameOrigin(NSPoint(x: vf.midX - w.frame.width / 2,
                                             y: vf.midY - w.frame.height / 2))
                }
            }
            host = h
            window = w
        } else if window?.isVisible != true {
            // Reopen after close → reload from the current saved config. Replacing rootView with the SAME
            // view type keeps SwiftUI @State alive (structural identity), so the old "reload" was a no-op
            // — recreate the hosting controller to genuinely reset the @State.
            // Already-visible window: just bring it forward — do NOT wipe unsaved edits.
            let h = NSHostingController(rootView: SettingsView())
            window?.contentViewController = h
            host = h
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // back to menu-bar agent
    }
}

private enum Provider: String, CaseIterable, Identifiable {
    case openai, deepseek, ollama, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .openai: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .ollama: return String(localized: "Ollama (local)")
        case .custom: return String(localized: "Custom / relay")
        }
    }
    var presetURL: String? {   // host base only; apiPath carries the /v1/chat/completions route
        switch self {
        case .openai: return "https://api.openai.com"
        case .deepseek: return "https://api.deepseek.com"
        case .ollama: return "http://localhost:11434"
        case .custom: return nil
        }
    }
    var defaultModel: String? {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .deepseek: return "deepseek-chat"
        case .ollama: return "qwen2.5"
        case .custom: return nil
        }
    }
    var isLocal: Bool { self == .ollama }
    /// Only classify as a preset when BOTH host and path match it — otherwise a custom localhost port/path or
    /// an openai.com-hosted relay would be mislabeled and have its editable fields hidden.
    static func from(base: String, path: String) -> Provider {
        let host = BYOKConfig.host(base).lowercased()
        let defaultPath = path.isEmpty || path == "/v1/chat/completions"
        if defaultPath, host.contains("openai.com") { return .openai }
        if defaultPath, host.contains("deepseek") { return .deepseek }
        if defaultPath, BYOKConfig.isLocal(base) { return .ollama }
        return .custom
    }
}

private struct SettingsView: View {
    @State private var provider = Provider.from(base: BYOKConfig.baseURL, path: BYOKConfig.apiPath)
    @State private var baseURL = BYOKConfig.baseURL
    @State private var model = BYOKConfig.model
    @State private var apiKey = BYOKConfig.apiKey
    @State private var models: [String] = []
    @State private var busy = false
    @State private var status: String?
    @State private var statusOK = false
    @State private var availableDicts: [String] = []   // macOS dictionaries available to enable in Dictionary.app
    @State private var inflight: Task<Void, Never>?
    @State private var apiPath = BYOKConfig.apiPath
    @State private var reasoningEffort = BYOKConfig.reasoningEffort
    @State private var dictMode = DictionaryConfig.mode
    @State private var sentenceEnabled = BYOKConfig.sentenceAnalysisEnabled
    @State private var customPromptEnabled = BYOKConfig.customPromptEnabled
    @State private var customSystemPrompt = BYOKConfig.customSystemPrompt
    @State private var customUserPrompt = BYOKConfig.customUserPrompt
    @State private var syntheticCopy = CaptureConfig.syntheticCopyEnabled
    @State private var firstLang = TargetLanguage.firstLanguage
    @State private var secondLang = TargetLanguage.secondLanguage
    @State private var launchAtLogin = LoginItem.isActive
    @State private var historyEnabled = HistoryStore.isEnabled
    @State private var compactPanel = PanelConfig.compact
    @State private var hotKeyDisplay = HotKeyConfig.displayString
    @State private var recording = false
    @State private var recordMonitor: Any?
    @State private var hotKeyStatus: String?
    @State private var loginStatus: String?
    private enum Field: Hashable { case base, path, key, model, sysPrompt, userPrompt }
    @FocusState private var focusedField: Field?

    private var trimmedBase: String { baseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedModel: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedPath: String {
        let p = apiPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? "/v1/chat/completions" : p
    }
    private var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "" }

    private var endpointKey: String { "\(baseURL)\u{1}\(apiPath)\u{1}\(apiKey)" }

    var body: some View {
        Form {
            headerSection
            generalSection
            modelSection
            systemDictSection
            outputSection
            advancedSection
            captureSection
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 760)   // pin so the flexible-height Form doesn't collapse the window
        .onAppear {
            launchAtLogin = LoginItem.isActive   // re-derive on (re)open so requiresApproval isn't lost
            loginStatus = LoginItem.requiresApproval ? String(localized: "Approve it in System Settings ▸ General ▸ Login Items") : nil
            if availableDicts.isEmpty { availableDicts = SystemDictionary.availableNames() }
        }
        .onDisappear { stopRecording(); inflight?.cancel(); commitText() } // flush pending edits on close
        .onChange(of: provider) {
            status = nil; models = []
            if let preset = provider.presetURL {   // a known provider: reset endpoint + model to its defaults
                baseURL = preset; apiPath = "/v1/chat/completions"
                if let dm = provider.defaultModel { model = dm }
            }
            commitText()
        }
        .onChange(of: endpointKey) { models = []; status = nil } // endpoint/key changed → stale model list
        // INSTANT APPLY (user decision — no 保存 button): pickers/toggles persist the moment they change;
        // text fields persist on focus loss / Return / window close (commitText).
        .onChange(of: focusedField) { commitText() }
        .onChange(of: reasoningEffort) { BYOKConfig.reasoningEffort = reasoningEffort }
        .onChange(of: dictMode) { DictionaryConfig.mode = dictMode }
        .onChange(of: sentenceEnabled) { BYOKConfig.sentenceAnalysisEnabled = sentenceEnabled }
        .onChange(of: customPromptEnabled) { BYOKConfig.customPromptEnabled = customPromptEnabled }
        .onChange(of: syntheticCopy) { CaptureConfig.syntheticCopyEnabled = syntheticCopy }
        .onChange(of: firstLang) { applyLanguages() }
        .onChange(of: secondLang) { applyLanguages() }
        .onChange(of: launchAtLogin) {
            if launchAtLogin == LoginItem.isActive {   // already in sync (our own programmatic write) → no loop
                loginStatus = LoginItem.requiresApproval ? String(localized: "Approve it in System Settings ▸ General ▸ Login Items") : nil
                return
            }
            _ = LoginItem.setEnabled(launchAtLogin)
            launchAtLogin = LoginItem.isActive   // keep ON for .requiresApproval too (no bounce)
            loginStatus = LoginItem.requiresApproval ? String(localized: "Approve it in System Settings ▸ General ▸ Login Items") : nil
        }
        .onChange(of: historyEnabled) { HistoryStore.isEnabled = historyEnabled }
        .onChange(of: compactPanel) {   // immediate, like the toggles above; re-render an open panel too
            PanelConfig.compact = compactPanel
            (NSApp.delegate as? AppDelegate)?.applyPanelCompact()
        }
    }

    @ViewBuilder private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GlossPop").font(.title3.bold())
                    Text("v\(version) · Selection translator").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder private var generalSection: some View {
        Section("General") {
            Toggle("Launch at login", isOn: $launchAtLogin)
            if let loginStatus { Text(loginStatus).font(.caption).foregroundStyle(.orange) }
            LabeledContent("Translation hotkey") {
                Button(recording ? String(localized: "Press a hotkey…  Esc cancels") : hotKeyDisplay) {
                    recording ? stopRecording() : startRecording()
                }
                .frame(minWidth: 140)
                .tint(recording ? .orange : nil)
            }
            if let hotKeyStatus { Text(hotKeyStatus).font(.caption).foregroundStyle(.orange) }
            Toggle("Keep translation history (stored in plain text on this Mac)", isOn: $historyEnabled)
            Toggle("Compact popup (hide the source hint line)", isOn: $compactPanel)
            if compactPanel {
                Text("Result cards drop the “System dictionary / AI · cloud / on-device” hints; errors and buttons still show.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var captureSection: some View {
        Section("Capture") {
            Toggle(isOn: $syntheticCopy) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copy fallback for apps that hide their selection")
                    Text("Normally the selection is read directly and the clipboard is never touched; for the few apps that block this (e.g. Safari), the selection is copied and your clipboard is restored immediately.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var modelSection: some View {
        Section("Translation model") {
            Picker("Provider", selection: $provider) {
                ForEach(Provider.allCases) { Text($0.label).tag($0) }
            }
            if provider == .custom {
                TextField("Endpoint", text: $baseURL, prompt: Text("https://your-relay-host")).focused($focusedField, equals: .base).onSubmit { commitText() }
                TextField("API path", text: $apiPath, prompt: Text("/v1/chat/completions")).focused($focusedField, equals: .path).onSubmit { commitText() }
            }
            if !provider.isLocal {
                SecureField("API key", text: $apiKey, prompt: Text("Stored only in your local Keychain")).focused($focusedField, equals: .key).onSubmit { commitText() }
            }
            LabeledContent("Model") {
                HStack(spacing: 6) {
                    TextField("", text: $model, prompt: Text("e.g. gpt-4o-mini")).multilineTextAlignment(.trailing).focused($focusedField, equals: .model).onSubmit { commitText() }
                    Menu {
                        Button(busy ? String(localized: "Fetching…") : String(localized: "Fetch model list")) { fetchModels() }
                            .disabled(trimmedBase.isEmpty || busy)
                        if !models.isEmpty {
                            Divider()
                            ForEach(models, id: \.self) { m in Button(m) { model = m } }
                        }
                    } label: { Image(systemName: "chevron.down.circle.fill").imageScale(.large) }
                    .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                }
            }
            Picker("Reasoning effort", selection: $reasoningEffort) {
                Text("Default").tag("default")
                Text("Minimal").tag("minimal")
                Text("Low (faster)").tag("low")
                Text("Medium").tag("medium")
                Text("High (more accurate)").tag("high")
            }
            HStack(spacing: 8) {
                Button("Test connection") { testConnection() }
                    .disabled(trimmedBase.isEmpty || trimmedModel.isEmpty || busy)
                if busy { ProgressView().controlSize(.mini) }
                if let status {
                    Label(status, systemImage: statusOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(statusOK ? .green : .red).lineLimit(2)
                }
                Spacer()
            }
            if let host = pendingConsentHost {
                Text("First time with this cloud service: clicking “Test connection” confirms sending selected text to \(host) (one-time) and enables translation.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text(provider.isLocal ? String(localized: "Local model — your text never leaves this Mac.")
                                  : String(localized: "Changes apply immediately. Translation sends your selected text to this service; the popup footer shows where it went. Reasoning effort only affects models that support it (e.g. gpt-5.x) — lower is faster."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func captionFor(_ mode: DictionaryMode) -> String {
        switch mode {
        case .offline:
            // The no-auto-network promise is per word/phrase; sentences still go to the model.
            return String(localized: "macOS system dictionary only (offline, instant). A miss shows an “Explain with AI” button — nothing is ever sent automatically. Sentences still use your translation model.")
        case .aiOnly:
            return String(localized: "Skip the system dictionary — words/phrases go straight to the AI dictionary: definition in your second language, meaning in your first.")
        case .offlineThenAI, .offlinePlusAI:
            return String(localized: "The system dictionary follows whatever you enable in Dictionary.app; the AI dictionary always gives a second-language definition plus a first-language meaning.")
        }
    }

    @ViewBuilder private var systemDictSection: some View {
        Section("Dictionary (words / phrases)") {
            Picker("Dictionary mode", selection: $dictMode) {
                ForEach(DictionaryMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Text(captionFor(dictMode)).font(.caption).foregroundStyle(.secondary)
            if dictMode.autoAI && trimmedModel.isEmpty {
                Text("This mode needs an AI model — none is configured under “Translation model” above.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if dictMode.usesSystem, !availableDicts.isEmpty {
                DisclosureGroup("Available system dictionaries (\(availableDicts.count)) — enable/download them in Dictionary.app") {
                    // rows belong to the Form directly — no scroller-within-a-scroller
                    ForEach(availableDicts, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
                LabeledContent("Manage system dictionaries") {
                    Button("Open Dictionary.app") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Dictionary.app"))
                    }
                }
            }
        }
    }

    /// Picker rows: the fixed choices, plus the current value when it isn't listed (e.g. a migrated system
    /// language like "pt") — a selection matching no tag would render an EMPTY picker.
    private func langChoices(including current: String) -> [String] {
        TargetLanguage.choices.contains(current) ? TargetLanguage.choices : TargetLanguage.choices + [current]
    }

    @ViewBuilder private var outputSection: some View {
        Section("Languages") {
            Picker("First language (native / translation target)", selection: $firstLang) {
                ForEach(langChoices(including: firstLang), id: \.self) { Text(TargetLanguage.label($0)).tag($0) }
            }
            Picker("Second language (study / AI definition language)", selection: $secondLang) {
                ForEach(langChoices(including: secondLang), id: \.self) { Text(TargetLanguage.label($0)).tag($0) }
            }
            Toggle("Sentences → translation + syntax analysis", isOn: $sentenceEnabled)
            Text("Translates into your first language; text already in it goes to the second. AI dictionary: second-language definition + first-language meaning.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var advancedSection: some View {
        Section("Advanced — custom prompts") {
            Toggle("Custom translation prompts", isOn: $customPromptEnabled)
            if customPromptEnabled {
                TextField("System", text: $customSystemPrompt, axis: .vertical).lineLimit(2...4).font(.callout).focused($focusedField, equals: .sysPrompt).onSubmit { commitText() }
                TextField("User", text: $customUserPrompt, axis: .vertical).lineLimit(2...4).font(.callout).focused($focusedField, equals: .userPrompt).onSubmit { commitText() }
                Text("Variables: $text (the selection), $target (target language). Plain translation only — dictionary/syntax keep the built-in prompts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func startRecording() {
        recording = true; hotKeyStatus = nil
        (NSApp.delegate as? AppDelegate)?.suspendHotKey()   // so the bound chord can be re-recorded
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { stopRecording(); return nil } // Esc cancels
            guard let candidate = KeyChord.candidate(from: event) else {
                hotKeyStatus = String(localized: "The hotkey needs ⌃ or ⌥")   // invalid — keep recording so they can retry
                return nil
            }
            // Atomic: applyHotKey already (re)registers the hotkey — new on success, old on failure — so we
            // must NOT resumeHotKey() afterward (that would double-register the same EventHotKeyID and kill it).
            if (NSApp.delegate as? AppDelegate)?.applyHotKey(candidate) == true {
                hotKeyDisplay = HotKeyConfig.displayString; hotKeyStatus = nil
            } else {
                hotKeyStatus = String(localized: "That hotkey is taken — keeping the previous one")
            }
            stopRecording(restoreHotKey: false)
            return nil // consume the chord
        }
    }

    private func stopRecording(restoreHotKey: Bool = true) {
        let wasRecording = recording
        if let m = recordMonitor { NSEvent.removeMonitor(m); recordMonitor = nil }
        recording = false
        // Only restore on CANCEL (Esc / window close) — when applyHotKey ran, it already set the hotkey.
        if wasRecording && restoreHotKey { (NSApp.delegate as? AppDelegate)?.resumeHotKey() }
    }

    /// A cloud host the user has typed but never confirmed — translation stays DISABLED for it until the
    /// one-time confirmation, which is the 测试连接 click itself (user decision: no modal, just this hint).
    private var pendingConsentHost: String? {
        guard !trimmedModel.isEmpty, let u = BYOKConfig.url(trimmedBase), !BYOKConfig.isLocal(trimmedBase),
              let host = u.host else { return nil }
        return BYOKConfig.consentedHost == host ? nil : host
    }

    /// Persist the text-field config (instant-apply: runs on focus loss / Return / provider switch / close).
    /// Folds the endpoint exactly like test/fetch, transactional on the Keychain write.
    private func commitText() {
        let folded = BYOKConfig.fold(base: trimmedBase, path: trimmedPath)
        baseURL = folded.base; apiPath = folded.path   // reflect the normalized split back into the fields
        if BYOKConfig.apiKey != trimmedKey {
            guard BYOKConfig.setAPIKey(trimmedKey) else { status = String(localized: "Keychain write failed"); statusOK = false; return }
        }
        BYOKConfig.baseURL = folded.base
        BYOKConfig.apiPath = folded.path
        BYOKConfig.model = trimmedModel
        BYOKConfig.customSystemPrompt = customSystemPrompt
        BYOKConfig.customUserPrompt = customUserPrompt
        refreshEnabled(foldedBase: folded.base)
    }

    /// Active = valid endpoint + model + (local OR consented cloud host). An un-consented cloud host stays
    /// disabled so nothing is ever auto-sent before the user's one-time confirmation.
    private func refreshEnabled(foldedBase: String) {
        let consented = BYOKConfig.isLocal(foldedBase) || BYOKConfig.consentedHost == BYOKConfig.host(foldedBase)
        BYOKConfig.isEnabled = (BYOKConfig.url(foldedBase) != nil && !trimmedModel.isEmpty && consented)
    }

    private func applyLanguages() {
        // Guard against first == second; the normalized value is reflected back into the picker.
        if TargetLanguage.sameLanguage(Locale.Language(identifier: firstLang),
                                       Locale.Language(identifier: secondLang)) {
            secondLang = TargetLanguage.defaultSecond(for: firstLang)
        }
        TargetLanguage.firstLanguage = firstLang
        TargetLanguage.secondLanguage = secondLang
    }

    private func fetchModels() {
        guard !busy else { return }
        let base = trimmedBase, key = trimmedKey, path = trimmedPath
        let folded = BYOKConfig.fold(base: base, path: path)   // hit the SAME endpoint save() will persist
        busy = true; status = nil
        inflight = Task {
            defer { busy = false }
            do {
                let result = try await BYOKClient.models(baseURL: folded.base, apiPath: folded.path, apiKey: key)
                guard base == trimmedBase, key == trimmedKey, path == trimmedPath else { return } // config changed mid-flight
                models = result
                status = String(localized: "Fetched \(result.count) models"); statusOK = true
                if trimmedModel.isEmpty, let first = result.first { model = first }
            } catch {
                guard base == trimmedBase, key == trimmedKey else { return }
                models = []; status = String(localized: "Couldn't fetch models: \(error.localizedDescription)"); statusOK = false
            }
        }
    }

    private func testConnection() {
        guard !busy else { return }
        commitText()   // persist what's typed before probing — the tested endpoint IS the live one
        // One-time consent: clicking test knowingly sends text to this host — that click is the confirmation.
        if let u = BYOKConfig.url(trimmedBase), !BYOKConfig.isLocal(trimmedBase), let host = u.host,
           BYOKConfig.consentedHost != host {
            BYOKConfig.consentedHost = host
            refreshEnabled(foldedBase: trimmedBase)
        }
        let base = trimmedBase, key = trimmedKey, mdl = trimmedModel, path = trimmedPath
        let folded = BYOKConfig.fold(base: base, path: path)
        busy = true; status = nil
        inflight = Task {
            defer { busy = false }
            do {
                try await BYOKClient.testChat(baseURL: folded.base, apiPath: folded.path, apiKey: key, model: mdl, reasoningEffort: reasoningEffort)
                guard base == trimmedBase, key == trimmedKey, mdl == trimmedModel, path == trimmedPath else { return }
                status = String(localized: "Connected ✓ configuration is live"); statusOK = true
            } catch {
                guard base == trimmedBase, key == trimmedKey, mdl == trimmedModel, path == trimmedPath else { return }
                status = String(localized: "Connection failed: \(error.localizedDescription)"); statusOK = false
            }
        }
    }
}

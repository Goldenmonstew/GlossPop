import AppKit
import SwiftUI

enum SettingsAssessmentDemo: String, CaseIterable {
    case running = "--demo-settings-assessment-running"
    case compatible = "--demo-settings-assessment-compatible"
    case translationOnly = "--demo-settings-assessment-translation-only"
    case incompatible = "--demo-settings-assessment-incompatible"
    case inconclusive = "--demo-settings-assessment-inconclusive"
    case anthropic = "--demo-settings-anthropic"
    case anthropicRelay = "--demo-settings-anthropic-relay"
    case anthropicWorkspace = "--demo-settings-anthropic-workspace"

    init?(arguments: [String]) {
        guard let match = Self.allCases.first(where: { arguments.contains($0.rawValue) }) else {
            return nil
        }
        self = match
    }

    var progress: ModelCapabilityStage? {
        self == .running ? .sentence : nil
    }

    var report: ModelCapabilityReport? {
        let passed = ModelCapabilityCheck(latency: .milliseconds(1_200), outcome: .passed)
        switch self {
        case .running:
            return nil
        case .compatible, .anthropic, .anthropicRelay, .anthropicWorkspace:
            return ModelCapabilityReport(
                translation: passed,
                dictionary: ModelCapabilityCheck(latency: .milliseconds(2_400), outcome: .passed),
                sentence: ModelCapabilityCheck(latency: .milliseconds(3_100), outcome: .passed),
                totalLatency: .milliseconds(6_700)
            )
        case .translationOnly:
            return ModelCapabilityReport(
                translation: passed,
                dictionary: ModelCapabilityCheck(
                    latency: .milliseconds(2_100),
                    outcome: .failed(.invalidDictionary)
                ),
                sentence: ModelCapabilityCheck(
                    latency: .milliseconds(2_800),
                    outcome: .failed(.invalidSentence)
                ),
                totalLatency: .milliseconds(6_100)
            )
        case .incompatible:
            return ModelCapabilityReport(
                translation: ModelCapabilityCheck(
                    latency: .milliseconds(900),
                    outcome: .failed(
                        .request(
                            message: "HTTP 400 from api.example.com — invalid model ID",
                            inconclusive: false
                        )
                    )
                ),
                dictionary: .skipped,
                sentence: .skipped,
                totalLatency: .milliseconds(900)
            )
        case .inconclusive:
            return ModelCapabilityReport(
                translation: ModelCapabilityCheck(
                    latency: .milliseconds(1_700),
                    outcome: .failed(
                        .request(
                            message: "HTTP 429 from api.example.com — rate limit exceeded",
                            inconclusive: true
                        )
                    )
                ),
                dictionary: .skipped,
                sentence: .skipped,
                totalLatency: .milliseconds(1_700)
            )
        }
    }
}

@MainActor
private struct SettingsSeed {
    let isDemo: Bool
    let provider: String
    let baseURL: String
    let model: String
    let apiKey: String
    let apiPath: String
    let apiFormat: BYOKAPIFormat
    let apiKeyHeader: BYOKAPIKeyHeader
    let reasoningEffort: String
    let dictMode: DictionaryMode
    let sentenceEnabled: Bool
    let customPromptEnabled: Bool
    let customSystemPrompt: String
    let customUserPrompt: String
    let syntheticCopy: Bool
    let firstLang: String
    let secondLang: String
    let launchAtLogin: Bool
    let historyEnabled: Bool
    let compactPanel: Bool
    let hotKeyDisplay: String
    let assessmentReport: ModelCapabilityReport?
    let assessmentProgress: ModelCapabilityStage?
    let scrollsToAssessment: Bool

    static func live() -> SettingsSeed {
        let preset = ProviderCatalog.match(
            base: BYOKConfig.baseURL,
            path: BYOKConfig.apiPath
        ).flatMap {
            $0.apiFormat == BYOKConfig.apiFormat && BYOKConfig.apiKeyHeader == .automatic ? $0 : nil
        }
        return SettingsSeed(
            isDemo: false,
            provider: preset?.id ?? "custom",
            baseURL: BYOKConfig.baseURL,
            model: BYOKConfig.model,
            apiKey: BYOKConfig.apiKey,
            apiPath: BYOKConfig.apiPath,
            apiFormat: BYOKConfig.apiFormat,
            apiKeyHeader: BYOKConfig.apiKeyHeader,
            reasoningEffort: BYOKConfig.reasoningEffort,
            dictMode: DictionaryConfig.mode,
            sentenceEnabled: BYOKConfig.sentenceAnalysisEnabled,
            customPromptEnabled: BYOKConfig.customPromptEnabled,
            customSystemPrompt: BYOKConfig.customSystemPrompt,
            customUserPrompt: BYOKConfig.customUserPrompt,
            syntheticCopy: CaptureConfig.syntheticCopyEnabled,
            firstLang: TargetLanguage.firstLanguage,
            secondLang: TargetLanguage.secondLanguage,
            launchAtLogin: LoginItem.isActive,
            historyEnabled: HistoryStore.isEnabled,
            compactPanel: PanelConfig.compact,
            hotKeyDisplay: HotKeyConfig.displayString,
            assessmentReport: nil,
            assessmentProgress: nil,
            scrollsToAssessment: false
        )
    }

    static func demo(_ demo: SettingsAssessmentDemo) -> SettingsSeed {
        let isAnthropicRelay = demo == .anthropicRelay
        let isAnthropicWorkspace = demo == .anthropicWorkspace
        let isCustomAnthropic = isAnthropicRelay || isAnthropicWorkspace
        let isAnthropic = demo == .anthropic || isCustomAnthropic
        return SettingsSeed(
            isDemo: true,
            provider: isCustomAnthropic ? "custom" : isAnthropic ? "dashscope-anthropic" : "custom",
            baseURL: isAnthropicWorkspace
                ? "https://workspace-id.cn-beijing.maas.aliyuncs.com"
                : isAnthropicRelay
                    ? "https://relay.example.com"
                    : isAnthropic ? "https://dashscope.aliyuncs.com" : "https://api.example.com",
            model: isAnthropic ? "deepseek-v4-pro" : "example-translation-model",
            apiKey: "demo-key-not-secret",
            apiPath: isAnthropicWorkspace
                ? "/apps/anthropic/v1/messages"
                : isAnthropicRelay
                    ? "/v1/messages"
                    : isAnthropic ? "/apps/anthropic/v1/messages" : "/v1/chat/completions",
            apiFormat: isAnthropic ? .anthropic : .openAI,
            apiKeyHeader: isAnthropicRelay ? .authorizationBearer : .automatic,
            reasoningEffort: "low",
            dictMode: .offlinePlusAI,
            sentenceEnabled: true,
            customPromptEnabled: false,
            customSystemPrompt: "",
            customUserPrompt: "",
            syntheticCopy: false,
            firstLang: "zh-Hans",
            secondLang: "en",
            launchAtLogin: true,
            historyEnabled: false,
            compactPanel: true,
            hotKeyDisplay: "⌃⌘T",
            assessmentReport: demo.report,
            assessmentProgress: demo.progress,
            scrollsToAssessment: !isCustomAnthropic
        )
    }
}

// Minimal Settings window for BYOK config (PLAN §4). A user-invoked window MAY activate the app
// (unlike the translate panel). Text entry lives here, never in the non-activating panel.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var host: NSHostingController<SettingsView>?

    func show(demo: SettingsAssessmentDemo? = nil) {
        let seed = demo.map(SettingsSeed.demo) ?? SettingsSeed.live()
        // Become a regular app while Settings is open so the window reliably comes to the front
        // (an .accessory app can't bring a window forward dependably). The app returns to accessory
        // only after every user window has closed.
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.userWindowDidOpen(self)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
        if window == nil {
            let h = NSHostingController(rootView: SettingsView(seed: seed))
            let w = NSWindow(contentViewController: h)
            w.title = String(localized: "GlossPop Settings")
            w.styleMask = [.titled, .closable, .miniaturizable]   // System Settings allows ⌘M too
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setContentSize(NSSize(width: 480, height: 760)) // Form has no intrinsic height — size explicitly
            // Frame restore happens HERE, once, at creation — calling setFrameUsingName again inside
            // show() left the window ordered OUT on relaunch (empirically reproducible). Centre on the
            // cursor screen only when no frame has ever been saved (first launch).
            if demo == nil {
                w.setFrameAutosaveName("GlossPopSettings")
            }
            if demo != nil || w.setFrameUsingName("GlossPopSettings") == false {
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
            let h = NSHostingController(rootView: SettingsView(seed: seed))
            window?.contentViewController = h
            host = h
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.userWindowWillClose(self)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}


private struct SettingsView: View {
    private let isDemo: Bool
    private let scrollsToAssessment: Bool
    @State private var provider: String
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey: String
    @State private var models: [String]
    @State private var fetchingModels: Bool
    @State private var assessing: Bool
    @State private var status: String?
    @State private var statusOK: Bool
    @State private var availableDicts: [String]   // macOS dictionaries available to enable in Dictionary.app
    @State private var inflight: Task<Void, Never>?
    @State private var apiPath: String
    @State private var apiFormat: BYOKAPIFormat
    @State private var apiKeyHeader: BYOKAPIKeyHeader
    @State private var reasoningEffort: String
    @State private var dictMode: DictionaryMode
    @State private var sentenceEnabled: Bool
    @State private var customPromptEnabled: Bool
    @State private var customSystemPrompt: String
    @State private var customUserPrompt: String
    @State private var syntheticCopy: Bool
    @State private var firstLang: String
    @State private var secondLang: String
    @State private var launchAtLogin: Bool
    @State private var historyEnabled: Bool
    @State private var compactPanel: Bool
    @State private var hotKeyDisplay: String
    @State private var recording: Bool
    @State private var recordMonitor: Any?
    @State private var hotKeyStatus: String?
    @State private var loginStatus: String?
    @State private var assessmentReport: ModelCapabilityReport?
    @State private var assessmentProgress: ModelCapabilityStage?
    @State private var activeAssessmentKey: String?
    private enum Field: Hashable { case base, path, key, model, sysPrompt, userPrompt }
    @FocusState private var focusedField: Field?

    init(seed: SettingsSeed) {
        isDemo = seed.isDemo
        scrollsToAssessment = seed.scrollsToAssessment
        _provider = State(initialValue: seed.provider)
        _baseURL = State(initialValue: seed.baseURL)
        _model = State(initialValue: seed.model)
        _apiKey = State(initialValue: seed.apiKey)
        _models = State(initialValue: [])
        _fetchingModels = State(initialValue: false)
        _assessing = State(initialValue: seed.assessmentProgress != nil)
        _status = State(initialValue: nil)
        _statusOK = State(initialValue: false)
        _availableDicts = State(initialValue: [])
        _inflight = State(initialValue: nil)
        _apiPath = State(initialValue: seed.apiPath)
        _apiFormat = State(initialValue: seed.apiFormat)
        _apiKeyHeader = State(initialValue: seed.apiKeyHeader)
        _reasoningEffort = State(initialValue: seed.reasoningEffort)
        _dictMode = State(initialValue: seed.dictMode)
        _sentenceEnabled = State(initialValue: seed.sentenceEnabled)
        _customPromptEnabled = State(initialValue: seed.customPromptEnabled)
        _customSystemPrompt = State(initialValue: seed.customSystemPrompt)
        _customUserPrompt = State(initialValue: seed.customUserPrompt)
        _syntheticCopy = State(initialValue: seed.syntheticCopy)
        _firstLang = State(initialValue: seed.firstLang)
        _secondLang = State(initialValue: seed.secondLang)
        _launchAtLogin = State(initialValue: seed.launchAtLogin)
        _historyEnabled = State(initialValue: seed.historyEnabled)
        _compactPanel = State(initialValue: seed.compactPanel)
        _hotKeyDisplay = State(initialValue: seed.hotKeyDisplay)
        _recording = State(initialValue: false)
        _recordMonitor = State(initialValue: nil)
        _hotKeyStatus = State(initialValue: nil)
        _loginStatus = State(initialValue: nil)
        _assessmentReport = State(initialValue: seed.assessmentReport)
        _assessmentProgress = State(initialValue: seed.assessmentProgress)
        _activeAssessmentKey = State(initialValue: nil)
    }

    private var selectedPreset: ProviderPreset? { ProviderCatalog.preset(id: provider) }
    private var isLocalProvider: Bool { selectedPreset?.isLocal ?? BYOKConfig.isLocal(baseURL) }
    private var supportsModelDiscovery: Bool {
        ProviderCatalog.supportsModelDiscovery(base: trimmedBase, path: trimmedPath, format: apiFormat)
    }
    private var trimmedBase: String { baseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedModel: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedPath: String {
        let p = apiPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? defaultAPIPath : p
    }
    private var defaultAPIPath: String {
        apiFormat == .anthropic ? "/v1/messages" : "/v1/chat/completions"
    }
    private var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "" }
    private var isBusy: Bool { fetchingModels || assessing }

    private var endpointKey: String {
        "\(baseURL)\u{1}\(apiPath)\u{1}\(apiKey)\u{1}\(apiFormat.rawValue)\u{1}\(apiKeyHeader.rawValue)"
    }
    private var assessmentKey: String {
        [
            baseURL,
            apiPath,
            apiKey,
            apiFormat.rawValue,
            apiKeyHeader.rawValue,
            model,
            reasoningEffort,
            firstLang,
            secondLang,
        ].joined(separator: "\u{1}")
    }

    var body: some View {
        ScrollViewReader { proxy in
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
            .allowsHitTesting(!isDemo)
            .onAppear {
                if isDemo {
                    guard scrollsToAssessment else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(
                            "model-assessment",
                            anchor: UnitPoint(x: 0.5, y: 0.38)
                        )
                    }
                    return
                }
                launchAtLogin = LoginItem.isActive   // re-derive on (re)open so requiresApproval isn't lost
                loginStatus = LoginItem.requiresApproval ? String(localized: "Approve it in System Settings ▸ General ▸ Login Items") : nil
                if availableDicts.isEmpty { availableDicts = SystemDictionary.availableNames() }
            }
            .onDisappear {
                guard !isDemo else { return }
                stopRecording()
                inflight?.cancel()
                commitText()
            } // flush pending edits on close
            .onChange(of: provider) {
                guard !isDemo else { return }
                status = nil; models = []
                assessmentReport = nil
                if let preset = selectedPreset {   // a known provider: reset endpoint + model to its defaults
                    baseURL = preset.baseURL
                    apiPath = preset.apiPath
                    apiFormat = preset.apiFormat
                    apiKeyHeader = .automatic
                    if !preset.defaultModel.isEmpty { model = preset.defaultModel }
                }
                commitText()
            }
            .onChange(of: apiFormat) { oldFormat, newFormat in
                guard !isDemo else { return }
                status = nil
                models = []
                if provider == "custom", apiPath == defaultPath(for: oldFormat) {
                    apiPath = defaultPath(for: newFormat)
                }
                commitText()
            }
            .onChange(of: endpointKey) {
                guard !isDemo else { return }
                models = []
                status = nil
            } // endpoint/key changed → stale model list
            .onChange(of: assessmentKey) {
                guard !isDemo else { return }
                assessmentReport = nil
                guard let activeAssessmentKey, activeAssessmentKey != assessmentKey else { return }
                inflight?.cancel()
                self.activeAssessmentKey = nil
                assessmentProgress = nil
                assessing = false
            }
            // INSTANT APPLY (user decision — no 保存 button): pickers/toggles persist the moment they change;
            // text fields persist on focus loss / Return / window close (commitText).
            .onChange(of: focusedField) { if !isDemo { commitText() } }
            .onChange(of: reasoningEffort) {
                if !isDemo { BYOKConfig.reasoningEffort = reasoningEffort }
            }
            .onChange(of: apiKeyHeader) {
                if !isDemo { commitText() }
            }
            .onChange(of: dictMode) { if !isDemo { DictionaryConfig.mode = dictMode } }
            .onChange(of: sentenceEnabled) {
                if !isDemo { BYOKConfig.sentenceAnalysisEnabled = sentenceEnabled }
            }
            .onChange(of: customPromptEnabled) {
                if !isDemo { BYOKConfig.customPromptEnabled = customPromptEnabled }
            }
            .onChange(of: syntheticCopy) {
                if !isDemo { CaptureConfig.syntheticCopyEnabled = syntheticCopy }
            }
            .onChange(of: firstLang) { if !isDemo { applyLanguages() } }
            .onChange(of: secondLang) { if !isDemo { applyLanguages() } }
            .onChange(of: launchAtLogin) {
                guard !isDemo else { return }
                if launchAtLogin == LoginItem.isActive {   // already in sync (our own programmatic write) → no loop
                    loginStatus = LoginItem.requiresApproval ? String(localized: "Approve it in System Settings ▸ General ▸ Login Items") : nil
                    return
                }
                _ = LoginItem.setEnabled(launchAtLogin)
                launchAtLogin = LoginItem.isActive   // keep ON for .requiresApproval too (no bounce)
                loginStatus = LoginItem.requiresApproval ? String(localized: "Approve it in System Settings ▸ General ▸ Login Items") : nil
            }
            .onChange(of: historyEnabled) {
                if !isDemo { HistoryStore.isEnabled = historyEnabled }
            }
            .onChange(of: compactPanel) {   // immediate, like the toggles above; re-render an open panel too
                guard !isDemo else { return }
                PanelConfig.compact = compactPanel
                (NSApp.delegate as? AppDelegate)?.applyPanelCompact()
            }
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
                Section("International") {
                    ForEach(ProviderCatalog.presets.filter { $0.region == .global }) { Text($0.name).tag($0.id) }
                }
                Section("China mainland") {
                    ForEach(ProviderCatalog.presets.filter { $0.region == .cn }) { Text($0.name).tag($0.id) }
                }
                Section("Local") {
                    ForEach(ProviderCatalog.presets.filter { $0.region == .local }) { Text($0.name).tag($0.id) }
                }
                Section {
                    Text("Custom / relay").tag("custom")
                }
            }
            if provider == "custom" {
                TextField("Endpoint", text: $baseURL, prompt: Text("https://your-relay-host")).focused($focusedField, equals: .base).onSubmit { commitText() }
                Picker("API format", selection: $apiFormat) {
                    Text("OpenAI-compatible").tag(BYOKAPIFormat.openAI)
                    Text("Anthropic-compatible").tag(BYOKAPIFormat.anthropic)
                }
                Picker("API key header", selection: $apiKeyHeader) {
                    Text("Automatic (protocol default)").tag(BYOKAPIKeyHeader.automatic)
                    Text(verbatim: "Authorization: Bearer").tag(BYOKAPIKeyHeader.authorizationBearer)
                    Text(verbatim: "x-api-key").tag(BYOKAPIKeyHeader.xAPIKey)
                    Text("No authentication").tag(BYOKAPIKeyHeader.none)
                }
                Text("Automatic uses Bearer for OpenAI, x-api-key for Anthropic, and no API key for localhost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("API path", text: $apiPath, prompt: Text(defaultAPIPath)).focused($focusedField, equals: .path).onSubmit { commitText() }
            } else if apiFormat == .anthropic {
                LabeledContent("API format") {
                    Text("Anthropic-compatible").foregroundStyle(.secondary)
                }
            }
            if provider == "custom" || !isLocalProvider {
                SecureField("API key", text: $apiKey, prompt: Text("Stored only in your local Keychain")).focused($focusedField, equals: .key).onSubmit { commitText() }
            }
            LabeledContent("Model") {
                HStack(spacing: 6) {
                    TextField(
                        "",
                        text: $model,
                        prompt: Text(
                            apiFormat == .anthropic
                                ? String(localized: "e.g. claude-haiku-4-5")
                                : String(localized: "e.g. gpt-4o-mini")
                        )
                    )
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .model)
                        .onSubmit { commitText() }
                    if supportsModelDiscovery {
                        Menu {
                            Button(fetchingModels ? String(localized: "Fetching…") : String(localized: "Fetch model list")) { fetchModels() }
                                .disabled(trimmedBase.isEmpty || isBusy)
                            if !models.isEmpty {
                                Divider()
                                ForEach(models, id: \.self) { m in Button(m) { model = m } }
                            }
                        } label: { Image(systemName: "chevron.down.circle.fill").imageScale(.large) }
                        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                    }
                }
            }
            if !supportsModelDiscovery {
                Text("Alibaba Cloud Model Studio's Anthropic endpoint does not provide a model list. Enter the model ID manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if apiFormat == .openAI {
                Picker("Reasoning effort", selection: $reasoningEffort) {
                    Text("Default").tag("default")
                    Text("Minimal").tag("minimal")
                    Text("Low (faster)").tag("low")
                    Text("Medium").tag("medium")
                    Text("High (more accurate)").tag("high")
                }
            }
            ModelAssessmentControl(
                assessing: assessing,
                progress: assessmentProgress,
                report: assessmentReport,
                disabled: trimmedBase.isEmpty || trimmedModel.isEmpty || isBusy,
                action: checkCompatibility
            )
            .id("model-assessment")
            if let status {
                Label(
                    status,
                    systemImage: statusOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(statusOK ? .green : .red)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let host = pendingConsentHost {
                Text("First time with this cloud service: “Check compatibility” sends built-in test text to \(host) and confirms that future selections may be sent there for translation.")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("The check uses built-in sample text and built-in prompts; custom prompts are not sent or evaluated. It tests streamed translation, the AI dictionary and sentence analysis, and never reads your selection, clipboard, history or vocabulary.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(
                isLocalProvider
                    ? String(localized: "Local model — your text never leaves this Mac.")
                    : apiFormat == .anthropic
                        ? String(localized: "Changes apply immediately. Translation sends your selected text to this service; the popup footer shows where it went.")
                        : String(localized: "Changes apply immediately. Translation sends your selected text to this service; the popup footer shows where it went. Reasoning effort only affects models that support it (e.g. gpt-5.x) — lower is faster.")
            )
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
                        guard !isDemo else { return }
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
        guard !isDemo else { return }
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
    /// one-time confirmation, which is the compatibility-check click itself (no modal, just this hint).
    private var pendingConsentHost: String? {
        guard !isDemo else { return nil }
        guard !trimmedModel.isEmpty, let u = BYOKConfig.url(trimmedBase), !BYOKConfig.isLocal(trimmedBase),
              let host = u.host else { return nil }
        return BYOKConfig.consentedHost == host ? nil : host
    }

    /// Persist the text-field config (instant-apply: runs on focus loss / Return / provider switch / close).
    /// Folds the endpoint exactly like test/fetch, transactional on the Keychain write.
    @discardableResult
    private func commitText() -> Bool {
        guard !isDemo else { return false }
        let folded = BYOKConfig.fold(base: trimmedBase, path: trimmedPath)
        baseURL = folded.base; apiPath = folded.path   // reflect the normalized split back into the fields
        if BYOKConfig.apiKey != trimmedKey {
            guard BYOKConfig.setAPIKey(trimmedKey) else {
                status = String(localized: "Keychain write failed")
                statusOK = false
                return false
            }
        }
        BYOKConfig.baseURL = folded.base
        BYOKConfig.apiPath = folded.path
        BYOKConfig.apiFormat = apiFormat
        BYOKConfig.apiKeyHeader = apiKeyHeader
        BYOKConfig.model = trimmedModel
        BYOKConfig.customSystemPrompt = customSystemPrompt
        BYOKConfig.customUserPrompt = customUserPrompt
        refreshEnabled(foldedBase: folded.base)
        return true
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
        guard !isDemo, !isBusy, supportsModelDiscovery else { return }
        let base = trimmedBase
        let key = trimmedKey
        let path = trimmedPath
        let format = apiFormat
        let keyHeader = apiKeyHeader
        let folded = BYOKConfig.fold(base: base, path: path)   // hit the SAME endpoint save() will persist
        fetchingModels = true; status = nil
        inflight = Task {
            defer { fetchingModels = false }
            do {
                let result = try await BYOKClient.models(
                    baseURL: folded.base,
                    apiPath: folded.path,
                    apiFormat: format,
                    apiKeyHeader: keyHeader,
                    apiKey: key
                )
                guard base == trimmedBase,
                      key == trimmedKey,
                      path == trimmedPath,
                      format == apiFormat,
                      keyHeader == apiKeyHeader
                else { return } // config changed mid-flight
                models = result
                status = String(localized: "Fetched \(result.count) models"); statusOK = true
                if trimmedModel.isEmpty, let first = result.first { model = first }
            } catch {
                guard base == trimmedBase,
                      key == trimmedKey,
                      path == trimmedPath,
                      format == apiFormat,
                      keyHeader == apiKeyHeader
                else { return }
                models = []; status = String(localized: "Couldn't fetch models: \(error.localizedDescription)"); statusOK = false
            }
        }
    }

    private func defaultPath(for format: BYOKAPIFormat) -> String {
        format == .anthropic ? "/v1/messages" : "/v1/chat/completions"
    }

    private func checkCompatibility() {
        guard !isDemo, !isBusy, commitText() else { return }
        // One-time consent: the check sends only built-in fixtures now and knowingly enables future
        // translations to this host. A persisted snapshot below is the exact configuration being assessed.
        if let u = BYOKConfig.url(trimmedBase), !BYOKConfig.isLocal(trimmedBase), let host = u.host,
           BYOKConfig.consentedHost != host {
            BYOKConfig.consentedHost = host
            refreshEnabled(foldedBase: trimmedBase)
        }
        guard let snapshot = BYOKConfig.snapshot() else {
            status = String(localized: "Invalid endpoint URL")
            statusOK = false
            return
        }
        let key = assessmentKey
        let first = firstLang
        let second = secondLang
        let assessor = ModelCapabilityAssessor(snapshot: snapshot)
        assessing = true
        status = nil
        assessmentReport = nil
        assessmentProgress = .translation
        activeAssessmentKey = key
        inflight = Task {
            defer {
                if activeAssessmentKey == key {
                    assessing = false
                    assessmentProgress = nil
                    activeAssessmentKey = nil
                }
            }
            do {
                let report = try await assessor.assess(
                    firstLanguage: first,
                    secondLanguage: second
                ) { stage in
                    guard activeAssessmentKey == key, assessmentKey == key else { return }
                    assessmentProgress = stage
                }
                guard activeAssessmentKey == key, assessmentKey == key else { return }
                assessmentReport = report
            } catch is CancellationError {
                return
            } catch {
                guard activeAssessmentKey == key, assessmentKey == key else { return }
                status = String(localized: "Couldn't complete the compatibility check: \(error.localizedDescription)")
                statusOK = false
            }
        }
    }
}

private struct ModelAssessmentControl: View {
    let assessing: Bool
    let progress: ModelCapabilityStage?
    let report: ModelCapabilityReport?
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Button("Check compatibility", action: action)
                    .disabled(disabled)
                if assessing {
                    ProgressView().controlSize(.mini)
                    if let progress {
                        Text(progressTitle(progress))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let report {
                let presentation = AssessmentPresentation(report: report)
                Label {
                    Text(presentation.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(presentation.colour)
                } icon: {
                    Image(systemName: presentation.systemImage)
                        .foregroundStyle(presentation.colour)
                }
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 5) {
                    assessmentRow(
                        String(localized: "Streaming translation"),
                        check: report.translation,
                        failureColour: report.level == .incompatible ? .red : .orange
                    )
                    assessmentRow(
                        String(localized: "AI dictionary"),
                        check: report.dictionary,
                        failureColour: .orange
                    )
                    assessmentRow(
                        String(localized: "Sentence analysis"),
                        check: report.sentence,
                        failureColour: .orange
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func assessmentRow(
        _ title: String,
        check: ModelCapabilityCheck,
        failureColour: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                switch check.outcome {
                case .passed:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(failureColour)
                case .skipped:
                    Image(systemName: "minus.circle").foregroundStyle(.secondary)
                }
                Text(title)
                Spacer(minLength: 8)
                switch check.outcome {
                case .passed, .failed:
                    Text(AssessmentPresentation.duration(check.latency))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                case .skipped:
                    Text("Not run").foregroundStyle(.secondary)
                }
            }
            if case .failed(let issue) = check.outcome {
                Text(AssessmentPresentation.issue(issue))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    private func progressTitle(_ stage: ModelCapabilityStage) -> String {
        switch stage {
        case .translation:
            return String(localized: "Testing translation…")
        case .dictionary:
            return String(localized: "Testing the AI dictionary…")
        case .sentence:
            return String(localized: "Testing sentence analysis…")
        }
    }
}

@MainActor
private struct AssessmentPresentation {
    let title: String
    let systemImage: String
    let colour: Color

    init(report: ModelCapabilityReport) {
        switch report.level {
        case .full:
            title = String(localized: "Fully compatible")
            systemImage = "checkmark.circle.fill"
            colour = .green
        case .translationOnly:
            title = String(localized: "Translation only")
            systemImage = "exclamationmark.triangle.fill"
            colour = .orange
        case .incompatible:
            title = String(localized: "Not compatible")
            systemImage = "xmark.circle.fill"
            colour = .red
        case .inconclusive:
            title = String(localized: "Couldn't assess")
            systemImage = "questionmark.circle.fill"
            colour = .orange
        }
    }

    static func issue(_ issue: ModelCapabilityIssue) -> String {
        switch issue {
        case .request(let message, _):
            return message
        case .emptyTranslation:
            return String(localized: "The model returned no streamed translation.")
        case .invalidDictionary:
            return String(localized: "The AI dictionary result was incomplete.")
        case .invalidSentence:
            return String(localized: "The sentence analysis result was incomplete.")
        case .wrongLanguage(let expectedCode, _):
            return String(
                localized: "The result was not written in \(TargetLanguage.label(expectedCode))."
            )
        case .uncertainLanguage(let expectedCode):
            return String(
                localized: "The result language couldn't be confirmed as \(TargetLanguage.label(expectedCode))."
            )
        case .missingSentenceFixture(let languageCode):
            return String(
                localized: "The sentence check has no built-in sample for \(TargetLanguage.label(languageCode))."
            )
        }
    }

    static func duration(_ duration: Duration) -> String {
        let components = duration.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitStyle = .short
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.minimumFractionDigits = seconds < 10 ? 1 : 0
        formatter.numberFormatter.maximumFractionDigits = seconds < 10 ? 1 : 0
        return formatter.string(from: Measurement(value: max(0, seconds), unit: UnitDuration.seconds))
    }
}

# GlossPop

**English** | [简体中文](README.zh-Hans.md)

**Swipe-to-translate for macOS.** Select text anywhere, press one hotkey, and get an **LLM translation that's also a dictionary and a grammar tutor** — streamed into a near-cursor panel that **leaves your clipboard untouched by default** and **never steals focus**.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple) ![Universal](https://img.shields.io/badge/Universal-Apple%20Silicon%20%2B%20Intel-blue) ![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-green) [![Latest release](https://img.shields.io/github/v/release/Goldenmonstew/GlossPop)](https://github.com/Goldenmonstew/GlossPop/releases/latest) ![Downloads](https://img.shields.io/github/downloads/Goldenmonstew/GlossPop/total)

<p align="center">
  <a href="https://github.com/Goldenmonstew/GlossPop/releases/latest"><b>⬇️&nbsp;&nbsp;Download GlossPop</b></a> — free, notarised by Apple, auto-updates
</p>

<p align="center">
  <img src="docs/card.png" width="440" alt="GlossPop near-cursor card: an instant bilingual dictionary entry for 会议, with bold senses and dimmed example sentences">
</p>

The UI follows your system language — English, 简体中文, 繁體中文, 日本語, 한국어, Français, Deutsch, Español, Русский.

## What makes it different

Most swipe-translators are fragile (resident event taps that lag the system, clipboard pollution) and just dump a flat translation. GlossPop is **input-aware** and reliable:

- 🧠 **It adapts to what you select.** A word or phrase → a full **dictionary** entry (pronunciation, part-of-speech senses, examples, synonyms, idioms). A sentence → **translation + analysis**: subject/predicate/object, grammar points, and notes on idioms or tricky terms — all explained in *your* language, not the source's. A whole paragraph keeps the translation and notes but skips the per-sentence breakdown. Plain phrases → a clean streamed translation.
- 🔑 **Your model.** Translation runs on the LLM you choose — **bring your own key** to an OpenAI- or Anthropic-compatible endpoint (cloud, a relay, or a local **Ollama** / **LM Studio**), or use on-device **Apple Foundation Models** where available.
- 🔒 **Zero side-effects.** Accessibility-first capture — no resident `CGEventTap`, the clipboard is never touched by default, focus never leaves your app. A provenance badge tells you exactly where your text went.

<p align="center">
  <img src="docs/sentence-card.png" width="440" alt="GlossPop sentence card: a Chinese translation, the subject/predicate/object kept in the original English, grammar points, and a note explaining the idiom 'call it a day' — the whole analysis written in the reader's own language">
</p>

## Install

1. Download the latest **`GlossPop-x.y.z.dmg`** from the [**Releases**](https://github.com/Goldenmonstew/GlossPop/releases/latest) page (notarized by Apple).
2. Open the DMG and drag **GlossPop** to **Applications**.
3. Launch it — a 💬 icon appears in the menu bar. On your first translation, grant **Accessibility** when prompted (System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable GlossPop). This is how it reads your selection without the clipboard.

Updates are delivered automatically via [Sparkle](https://sparkle-project.org) (or menu ▸ Check for Updates…).

## Use

- Select text in any app → press **⌃⌘T** → the panel pops up near your cursor.
- **Esc** or click away to dismiss. The selection in the source app stays intact.
- Open **Settings…** from the menu-bar icon to choose the target language, output mode, and translation engine.

## Personal vocabulary (v1.1)

- Use the result card actions to **copy the result** or save a word or phrase to your vocabulary.
- Open **Vocabulary** from the menu bar to search saved entries, filter them by language pair, and remove individual entries or clear the library.
- Export the whole library as CSV or as Anki-compatible UTF-8 text. CSV is intended for external use, not as a lossless backup, and GlossPop cannot currently import it.

## Bring your own model (BYOK)

<p align="center">
  <img src="docs/settings.png" width="420" alt="GlossPop settings: provider, model, reasoning effort and model compatibility assessment">
</p>

Settings ▸ *Translation model*:

1. **Provider / Endpoint** — choose an OpenAI or Anthropic Messages provider, or configure a custom relay/local endpoint. Alibaba Cloud Model Studio has separate built-in **OpenAI-compatible** and **Anthropic-compatible** presets; to use a workspace-specific API Host, select **Custom / relay** and enter that host with the matching API format and path.
2. **API key** — stored in your macOS **Keychain**, never anywhere else. Custom relays support Bearer, `x-api-key`, or no authentication; provider-specific OAuth and request-signing schemes are not supported. **Automatic** uses Bearer for OpenAI, `x-api-key` for Anthropic, and no API key for localhost.
3. **Model** — type its ID, or fetch the list when the endpoint exposes `/v1/models`. Alibaba Cloud Model Studio's Anthropic endpoint does not provide a model list, so enter its model ID manually. **Check compatibility** uses GlossPop's built-in sample text and prompts to exercise the real streamed-translation, AI-dictionary and sentence-analysis paths, check output language, and report each stage's latency. Custom prompts are neither sent nor assessed.
4. Changes apply immediately — the first check on a new cloud host sends only the disclosed built-in sample text and prompts, and doubles as your one-time consent for future selected text.

When the endpoint is a cloud/relay host, the panel's footer is badged **“cloud”** so you always know your text left the machine; loopback (`localhost`) is badged **“on-device”**. The UI is localised into English, 简体中文, 繁體中文, 日本語, 한국어, Français, Deutsch, Español and Русский, following your system language.

## Privacy

- **Zero clipboard by default**, and the word/phrase path can run fully offline (macOS system dictionary). Nothing is ever sent to a cloud host until you configure one and confirm it once via **Check compatibility**; that check reads no selection, clipboard, history or vocabulary, sends only its disclosed built-in sample text and prompts, and never sends or assesses your custom prompts.
- The optional Tier-2 “synthetic copy” fallback (for apps that don't expose selection, e.g. Safari/Electron) is **off by default**; when on, it restores your clipboard immediately.
- By default, your selection isn't stored or logged. If you enable **Translation History**, selections and their available results are kept locally in plain text; explicitly saving a word or phrase also stores that selected term and its dictionary results in the local vocabulary.
- Active vocabulary entries are kept locally in plain text and can be deleted individually, cleared together, or exported at any time. If GlossPop preserves a damaged vocabulary file during recovery, it shows the backup location so you can review or delete it in Finder.

## Build from source

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
make build   # xcodegen generate + xcodebuild
make run     # build + launch
make test    # unit tests
```

Maintainer release pipeline (Developer ID sign → notarize → DMG → Sparkle appcast) lives in [`scripts/release.sh`](scripts/release.sh).

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). macOS 15+, Universal (Apple Silicon + Intel), Swift 6 (strict concurrency).

## License

[AGPL-3.0-or-later](LICENSE). © 2026 wanruncong.

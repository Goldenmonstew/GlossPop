# GlossPop

[English](README.md) | **简体中文**

**macOS 划词翻译。** 在任何 App 里选中文字,按一个快捷键,得到一份**既是翻译、又是词典、还是语法老师**的 LLM 结果——流式呈现在光标旁的浮窗里,**绝不碰你的剪贴板**,**绝不抢焦点**。

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple) ![Universal](https://img.shields.io/badge/Universal-Apple%20Silicon%20%2B%20Intel-blue) ![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-green) [![Latest release](https://img.shields.io/github/v/release/Goldenmonstew/GlossPop)](https://github.com/Goldenmonstew/GlossPop/releases/latest) ![Downloads](https://img.shields.io/github/downloads/Goldenmonstew/GlossPop/total)

<p align="center">
  <a href="https://github.com/Goldenmonstew/GlossPop/releases/latest"><b>⬇️&nbsp;&nbsp;下载 GlossPop</b></a> — 免费,苹果公证,自动更新
</p>

<p align="center">
  <img src="docs/card.png" width="440" alt="GlossPop 光标旁卡片:「会议」的双语词典词条,义项加粗、例句弱化显示">
</p>

界面跟随系统语言——简体中文、繁體中文、English、日本語、한국어、Français、Deutsch、Español、Русский。

## 它有什么不一样

多数划词翻译要么脆弱(常驻事件监听拖慢系统、污染剪贴板),要么只会糊一段干巴巴的译文。GlossPop **能看懂你选的是什么**,而且足够可靠:

- 🧠 **按内容自适应。** 选单词/短语 → 完整**词典**词条(发音、词性义项、例句、近义词、习语);选句子 → **翻译 + 句法解析**(主谓宾、语法点);普通短语 → 干净的流式翻译。
- 🔑 **用你自己的模型。** 翻译跑在你选择的 LLM 上——**自带密钥**接任何 OpenAI 兼容端点(云端、中转、本地 **Ollama** / **LM Studio**),支持的设备上也可用端上 **Apple Foundation Models**。
- 🔒 **零副作用。** 辅助功能优先取词——无常驻 `CGEventTap`,默认不碰剪贴板,焦点永远留在你的 App。浮窗角标如实标注你的文字去了哪里。

## 安装

1. 从 [**Releases**](https://github.com/Goldenmonstew/GlossPop/releases/latest) 页面下载最新的 **`GlossPop-x.y.z.dmg`**(苹果公证)。
2. 打开 DMG,把 **GlossPop** 拖进 **Applications**。
3. 启动——菜单栏出现 💬 图标。首次使用按提示授予**辅助功能**权限(系统设置 ▸ 隐私与安全性 ▸ 辅助功能 ▸ 勾选 GlossPop),这是它不碰剪贴板就能读取选区的方式。

更新经 [Sparkle](https://sparkle-project.org) 自动推送(也可菜单 ▸ 检查更新…)。

## 使用

- 在任意 App 选中文字 → 按 **⌃⌘T** → 浮窗在光标旁弹出。
- 按 **Esc** 或点击别处关闭;源 App 的选区保持原样。
- 从菜单栏图标打开**设置…**,选择语言、词典模式和翻译引擎。

## 自带模型(BYOK)

<p align="center">
  <img src="docs/settings.png" width="420" alt="GlossPop 设置:服务商、模型、推理强度、词典模式——改动即时生效">
</p>

设置 ▸ *翻译模型*:

1. **服务商 / 端点** — 任何 OpenAI 兼容端点(OpenAI、DeepSeek、你的中转,或本地 Ollama 的 `http://localhost:11434`)。
2. **API 密钥** — 只存在 macOS **钥匙串**里,别处不留。
3. **模型** — 手动输入,或从 `/v1/models` 拉取列表;**测试连接**做端到端验证。
4. 改动即时生效——对新云端服务的首次测试同时就是你的一次性发送确认。

端点是云端/中转时,浮窗底部会标注**「云」**,让你始终知道文字离开了本机;回环地址(`localhost`)标注**「本机」**。界面已本地化为简体中文、繁體中文、English、日本語、한국어、Français、Deutsch、Español、Русский,跟随系统语言。

## 隐私

- **默认零剪贴板**,词/短语路径可完全离线(macOS 系统词典)。在你配置并通过**测试连接**确认之前,任何内容都不会发往云端。
- 可选的「合成复制」兜底(针对 Safari/Electron 等不暴露选区的 App)**默认关闭**;开启时也会立即恢复你原来的剪贴板。
- 除非你打开**翻译历史**(默认关闭;明文存本机,随时可清空),你的选中内容不会被存储或记录。

## 从源码构建

需要 Xcode 26+ 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)(`brew install xcodegen`)。

```bash
make build   # xcodegen generate + xcodebuild
make run     # 构建并启动
make test    # 单元测试
```

维护者发布流水线(Developer ID 签名 → 公证 → DMG → Sparkle appcast)见 [`scripts/release.sh`](scripts/release.sh)。

## 参与贡献

欢迎 Issue 和 PR——见 [CONTRIBUTING.md](CONTRIBUTING.md)。macOS 15+,通用二进制(Apple Silicon + Intel),Swift 6(严格并发)。

## 许可证

[AGPL-3.0-or-later](LICENSE)。© 2026 wanruncong。

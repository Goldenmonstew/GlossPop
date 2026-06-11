import Foundation

// Data-driven provider presets — one OpenAI-chat-completions engine, many endpoints. Every entry was
// verified against the vendor's official documentation; anything needing more than base+path+Bearer
// (Azure deployment URLs, Bedrock SigV4, Vertex OAuth) is deliberately excluded — "Custom" covers them
// via relays. Adding a vendor = adding one row here; the engine never changes.
struct ProviderPreset: Identifiable, Hashable, Sendable {
    enum Region: Sendable { case global, cn, local }
    let id: String
    let name: String          // brand names stay unlocalised; CN entries carry bilingual labels
    let baseURL: String       // host base only — BYOKConfig folds base/path
    let apiPath: String
    let defaultModel: String
    let region: Region
    var isLocal: Bool { region == .local }
}

enum ProviderCatalog {
    static let presets: [ProviderPreset] = [
        // ---- Global ----
        .init(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com",
              apiPath: "/v1/chat/completions", defaultModel: "gpt-5.4-mini", region: .global),
        .init(id: "anthropic", name: "Anthropic Claude", baseURL: "https://api.anthropic.com",
              apiPath: "/v1/chat/completions", defaultModel: "claude-haiku-4-5", region: .global),
        .init(id: "gemini", name: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com",
              apiPath: "/v1beta/openai/chat/completions", defaultModel: "gemini-flash-latest", region: .global),
        .init(id: "xai", name: "xAI Grok", baseURL: "https://api.x.ai",
              apiPath: "/v1/chat/completions", defaultModel: "grok-4.3", region: .global),
        .init(id: "mistral", name: "Mistral", baseURL: "https://api.mistral.ai",
              apiPath: "/v1/chat/completions", defaultModel: "mistral-small-latest", region: .global),
        .init(id: "groq", name: "Groq", baseURL: "https://api.groq.com",
              apiPath: "/openai/v1/chat/completions", defaultModel: "openai/gpt-oss-120b", region: .global),
        .init(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai",
              apiPath: "/api/v1/chat/completions", defaultModel: "openai/gpt-4o-mini", region: .global),
        .init(id: "together", name: "Together AI", baseURL: "https://api.together.ai",
              apiPath: "/v1/chat/completions", defaultModel: "openai/gpt-oss-20b", region: .global),
        .init(id: "fireworks", name: "Fireworks", baseURL: "https://api.fireworks.ai",
              apiPath: "/inference/v1/chat/completions",
              defaultModel: "accounts/fireworks/models/gpt-oss-20b", region: .global),
        .init(id: "perplexity", name: "Perplexity", baseURL: "https://api.perplexity.ai",
              apiPath: "/chat/completions", defaultModel: "sonar", region: .global),
        .init(id: "github", name: "GitHub Models", baseURL: "https://models.github.ai",
              apiPath: "/inference/chat/completions", defaultModel: "openai/gpt-4.1", region: .global),
        .init(id: "cerebras", name: "Cerebras", baseURL: "https://api.cerebras.ai",
              apiPath: "/v1/chat/completions", defaultModel: "gpt-oss-120b", region: .global),
        .init(id: "nvidia", name: "NVIDIA NIM", baseURL: "https://integrate.api.nvidia.com",
              apiPath: "/v1/chat/completions", defaultModel: "meta/llama-3.3-70b-instruct", region: .global),
        .init(id: "zai", name: "Z.ai (GLM Global)", baseURL: "https://api.z.ai",
              apiPath: "/api/paas/v4/chat/completions", defaultModel: "glm-5.1", region: .global),
        .init(id: "moonshot-global", name: "Moonshot (Global)", baseURL: "https://api.moonshot.ai",
              apiPath: "/v1/chat/completions", defaultModel: "kimi-k2.6", region: .global),
        .init(id: "minimax-global", name: "MiniMax (Global)", baseURL: "https://api.minimax.io",
              apiPath: "/v1/chat/completions", defaultModel: "MiniMax-M2.5", region: .global),

        // ---- China mainland ----
        .init(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com",
              apiPath: "/chat/completions", defaultModel: "deepseek-chat", region: .cn),
        .init(id: "dashscope", name: "通义千问 Qwen", baseURL: "https://dashscope.aliyuncs.com",
              apiPath: "/compatible-mode/v1/chat/completions", defaultModel: "qwen-plus", region: .cn),
        .init(id: "volcark", name: "豆包(火山方舟)", baseURL: "https://ark.cn-beijing.volces.com",
              apiPath: "/api/v3/chat/completions", defaultModel: "doubao-seed-1-6-flash-250828", region: .cn),
        .init(id: "zhipu", name: "智谱 GLM", baseURL: "https://open.bigmodel.cn",
              apiPath: "/api/paas/v4/chat/completions", defaultModel: "glm-4-flash", region: .cn),
        .init(id: "moonshot", name: "Kimi(月之暗面)", baseURL: "https://api.moonshot.cn",
              apiPath: "/v1/chat/completions", defaultModel: "kimi-k2.6", region: .cn),
        .init(id: "minimax", name: "MiniMax", baseURL: "https://api.minimaxi.com",
              apiPath: "/v1/chat/completions", defaultModel: "MiniMax-M2", region: .cn),
        .init(id: "qianfan", name: "百度千帆 ERNIE", baseURL: "https://qianfan.baidubce.com",
              apiPath: "/v2/chat/completions", defaultModel: "ernie-3.5-8k", region: .cn),
        .init(id: "hunyuan", name: "腾讯混元", baseURL: "https://api.hunyuan.cloud.tencent.com",
              apiPath: "/v1/chat/completions", defaultModel: "hunyuan-turbos-latest", region: .cn),
        .init(id: "spark", name: "讯飞星火", baseURL: "https://spark-api-open.xf-yun.com",
              apiPath: "/v1/chat/completions", defaultModel: "lite", region: .cn),
        .init(id: "stepfun", name: "阶跃星辰 StepFun", baseURL: "https://api.stepfun.ai",
              apiPath: "/v1/chat/completions", defaultModel: "step-3.7-flash", region: .cn),
        .init(id: "lingyiwanwu", name: "零一万物 Yi", baseURL: "https://api.lingyiwanwu.com",
              apiPath: "/v1/chat/completions", defaultModel: "yi-lightning", region: .cn),
        .init(id: "baichuan", name: "百川", baseURL: "https://api.baichuan-ai.com",
              apiPath: "/v1/chat/completions", defaultModel: "Baichuan4-Air", region: .cn),
        .init(id: "siliconflow", name: "硅基流动 SiliconFlow", baseURL: "https://api.siliconflow.cn",
              apiPath: "/v1/chat/completions", defaultModel: "deepseek-ai/DeepSeek-V3.2", region: .cn),
        .init(id: "modelscope", name: "魔搭 ModelScope", baseURL: "https://api-inference.modelscope.cn",
              apiPath: "/v1/chat/completions", defaultModel: "Qwen/Qwen3-32B", region: .cn),

        // ---- Local ----
        .init(id: "ollama", name: "Ollama", baseURL: "http://localhost:11434",
              apiPath: "/v1/chat/completions", defaultModel: "qwen3", region: .local),
        .init(id: "lmstudio", name: "LM Studio", baseURL: "http://localhost:1234",
              apiPath: "/v1/chat/completions", defaultModel: "", region: .local),
        .init(id: "vllm", name: "vLLM", baseURL: "http://localhost:8000",
              apiPath: "/v1/chat/completions", defaultModel: "", region: .local),
    ]

    static func preset(id: String) -> ProviderPreset? { presets.first { $0.id == id } }

    /// Classify a saved endpoint back to a preset, so the picker shows the right row after reopening
    /// Settings. Host, PORT and path must all match — a relay hosted on a vendor's domain, a custom
    /// localhost port (Ollama vs LM Studio vs vLLM) must stay distinct rather than mis-classified.
    static func match(base: String, path: String) -> ProviderPreset? {
        let normPath = path.isEmpty ? "/v1/chat/completions" : path
        guard let key = hostPort(base) else { return nil }
        return presets.first { hostPort($0.baseURL) == key && $0.apiPath == normPath }
    }

    private static func hostPort(_ base: String) -> String? {
        guard let u = BYOKConfig.url(base), let host = u.host?.lowercased() else { return nil }
        let port = u.port ?? (u.scheme?.lowercased() == "http" ? 80 : 443)
        return "\(host):\(port)"
    }
}

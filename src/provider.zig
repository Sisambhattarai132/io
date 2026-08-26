const std = @import("std");

/// Provider definitions covering all providers supported by Mastra's model
/// router (181 providers). Each provider speaks the OpenAI-compatible
/// chat/completions endpoint. Mastra normalizes them all to a single wire
/// format, and so do we.
///
/// Source: https://mastra.ai/models/providers (Aug 2026)

pub const Provider = enum {
    // ── Tier 1: Major foundation model providers ──
    openai,
    anthropic,
    google,
    grok,
    mistral,
    cohere,
    deepseek,

    // ── Tier 2: Cloud / managed inference platforms ──
    openrouter,
    together,
    fireworks,
    groq,
    cerebras,
    novita,
    deepinfra,
    nebius,
    baseten,
    hyperbolic,
    sambanova,
    parasail,
    runinfra,
    gmicloud,
    modal,
    crusoe,
    digitalocean,
    friendli,
    wafer,
    streamlake,
    nvidia,
    databricks,
    cloudflare,
    ovhcloud,
    scaleway,
    vultr,
    hetzner,
    infomaniak,
    stackit,
    ebcloud,
    cloudferro,
    hpc_ai,
    io_net,
    jalapeno,
    kosmik,
    evroc,
    inferx,
    tensorx,
    mixlayer,
    modelis,
    nova,
    pioneer,
    opper,
    tinfoil,
    vivgrid,
    umans_ai,
    neuralwatt,
    privatemode,
    regolo,
    scx_ai,
    submodel,
    synthetic,
    moark,
    lilac,
    longcat,
    thegrid,
    zenifra,
    zeldoc,
    coralbricks,
    kenari,
    dinference,
    echo,
    ofoo,
    qihang,
    qiniu,
    bailing,
    daoxe,
    d_run,
    kuae,
    scnet,
    berget,
    helicone,
    cortecs,
    chutes,
    fastrouter,
    greenpt,
    crofai,
    frogbot,
    impossibl,
    inceptron,
    inference,
    ambient,
    free_model,
    nano_gpt,
    nearai,
    orcarouter,
    routing_run,
    unorouter,
    trustedrouter,
    zenmux,
    llmtr,
    llm_gateway,
    devpass,
    kilo,
    jiekou,
    modelscope,
    kimi_coding,
    opencode_zen,
    opencode_go,
    requesty,
    chutes_ai,
    clinepass,
    atomic_chat,
    auriko,
    claudinio,
    charm_hyper,
    blue_claw,
    crofai_alt,
    crossmodel,
    abacus,
    ai_302,
    ai_router,
    aiand,
    aki_io,
    anyapi,
    edenai,
    empiriolabs,
    cn_line_pass,
    cline_pass,
    frogbot_alt,
    model_oracle,
    xpersona,
    lucidquery,
    lynkr,
    meganova,
    sarvam,
    tencent,
    tencent_token,
    tencent_tokenhub,
    tencent_coding,
    stepfun,
    stepfun_ai,
    stepfun_step,
    stepfun_ai_step,
    alibaba,
    alibaba_cn,
    alibaba_coding,
    alibaba_coding_cn,
    alibaba_token,
    alibaba_token_cn,
    moonshot,
    moonshot_cn,
    zhipu,
    zhipu_coding,
    zai,
    zai_coding,
    minimax,
    minimax_cn,
    minimax_coding,
    minimax_cn_coding,
    bytedance,
    xiaomi,
    xiaomi_token_cn,
    xiaomi_token_ams,
    xiaomi_token_sgp,
    sakana,
    arcee,
    morph,
    inception,
    poolside,
    thinkingmachines,
    kwaipilot,
    llama,
    amd,
    upstage,
    silocloud,
    siliconflow,
    siliconflow_cn,
    snowflake,
    weights_biases,
    ollama_cloud,
    lmstudio,
    codex,
    ollama,

    pub fn slug(self: Provider) []const u8 {
        return switch (self) {
            .openai => "openai",
            .anthropic => "anthropic",
            .google => "google",
            .grok => "grok",
            .mistral => "mistral",
            .cohere => "cohere",
            .deepseek => "deepseek",
            .openrouter => "openrouter",
            .together => "together",
            .fireworks => "fireworks",
            .groq => "groq",
            .cerebras => "cerebras",
            .novita => "novita",
            .deepinfra => "deepinfra",
            .nebius => "nebius",
            .baseten => "baseten",
            .hyperbolic => "hyperbolic",
            .sambanova => "sambanova",
            .parasail => "parasail",
            .runinfra => "runinfra",
            .gmicloud => "gmicloud",
            .modal => "modal",
            .crusoe => "crusoe",
            .digitalocean => "digitalocean",
            .friendli => "friendli",
            .wafer => "wafer",
            .streamlake => "streamlake",
            .nvidia => "nvidia",
            .databricks => "databricks",
            .cloudflare => "cloudflare-workers-ai",
            .ovhcloud => "ovhcloud",
            .scaleway => "scaleway",
            .vultr => "vultr",
            .hetzner => "hetzner",
            .infomaniak => "infomaniak",
            .stackit => "stackit",
            .ebcloud => "ebcloud",
            .cloudferro => "cloudferro",
            .hpc_ai => "hpc-ai",
            .io_net => "io-net",
            .jalapeno => "jalapeno",
            .kosmik => "kosmik",
            .evroc => "evroc",
            .inferx => "inferx",
            .tensorx => "tensorx",
            .mixlayer => "mixlayer",
            .modelis => "modelis",
            .nova => "nova",
            .pioneer => "pioneer",
            .opper => "opper",
            .tinfoil => "tinfoil",
            .vivgrid => "vivgrid",
            .umans_ai => "umans-ai",
            .neuralwatt => "neuralwatt",
            .privatemode => "privatemode-ai",
            .regolo => "regolo-ai",
            .scx_ai => "scx-ai",
            .submodel => "submodel",
            .synthetic => "synthetic",
            .moark => "moark",
            .lilac => "lilac",
            .longcat => "longcat",
            .thegrid => "the-grid-ai",
            .zenifra => "zenifra",
            .zeldoc => "zeldoc",
            .coralbricks => "coralbricks",
            .kenari => "kenari",
            .dinference => "dinference",
            .echo => "echo",
            .ofoo => "ofoo",
            .qihang => "qihang-ai",
            .qiniu => "qiniu-ai",
            .bailing => "bailing",
            .daoxe => "daoxe",
            .d_run => "drun",
            .kuae => "kuae-cloud-coding-plan",
            .scnet => "scnet-token-plan",
            .berget => "berget",
            .helicone => "helicone",
            .cortecs => "cortecs",
            .chutes => "chutes",
            .fastrouter => "fastrouter",
            .greenpt => "greenpt",
            .crofai => "crofai",
            .frogbot => "frogbot",
            .impossibl => "impossibl",
            .inceptron => "inceptron",
            .inference => "inference",
            .ambient => "ambient",
            .free_model => "freemodel",
            .nano_gpt => "nano-gpt",
            .nearai => "nearai",
            .orcarouter => "orcarouter",
            .routing_run => "routing-run",
            .unorouter => "unorouter",
            .trustedrouter => "trustedrouter",
            .zenmux => "zenmux",
            .llmtr => "llmtr",
            .llm_gateway => "llmgateway",
            .devpass => "devpass",
            .kilo => "kilo",
            .jiekou => "jiekou",
            .modelscope => "modelscope",
            .kimi_coding => "kimi-for-coding",
            .opencode_zen => "opencode",
            .opencode_go => "opencode-go",
            .requesty => "requesty",
            .chutes_ai => "chutes-ai",
            .clinepass => "clinepass",
            .atomic_chat => "atomic-chat",
            .auriko => "auriko",
            .claudinio => "claudinio",
            .charm_hyper => "charm-hyper",
            .blue_claw => "blueclaw",
            .crofai_alt => "crofai-alt",
            .crossmodel => "crossmodel",
            .abacus => "abacus",
            .ai_302 => "302ai",
            .ai_router => "ai-router",
            .aiand => "aiand",
            .aki_io => "aki-io",
            .anyapi => "anyapi",
            .edenai => "edenai",
            .empiriolabs => "empiriolabs",
            .cn_line_pass => "cn-line-pass",
            .cline_pass => "cline-pass",
            .frogbot_alt => "frogbot-alt",
            .model_oracle => "model-oracle-ai",
            .xpersona => "xpersona",
            .lucidquery => "lucidquery",
            .lynkr => "lynkr",
            .meganova => "meganova",
            .sarvam => "sarvam",
            .tencent => "tencent",
            .tencent_token => "tencent-token-plan",
            .tencent_tokenhub => "tencent-tokenhub",
            .tencent_coding => "tencent-coding-plan",
            .stepfun => "stepfun",
            .stepfun_ai => "stepfun-ai",
            .stepfun_step => "stepfun-step-plan",
            .stepfun_ai_step => "stepfun-ai-step-plan",
            .alibaba => "alibaba",
            .alibaba_cn => "alibaba-cn",
            .alibaba_coding => "alibaba-coding-plan",
            .alibaba_coding_cn => "alibaba-coding-plan-cn",
            .alibaba_token => "alibaba-token-plan",
            .alibaba_token_cn => "alibaba-token-plan-cn",
            .moonshot => "moonshotai",
            .moonshot_cn => "moonshotai-cn",
            .zhipu => "zhipuai",
            .zhipu_coding => "zhipuai-coding-plan",
            .zai => "zai",
            .zai_coding => "zai-coding-plan",
            .minimax => "minimax",
            .minimax_cn => "minimax-cn",
            .minimax_coding => "minimax-coding-plan",
            .minimax_cn_coding => "minimax-cn-coding-plan",
            .bytedance => "bytedance",
            .xiaomi => "xiaomi",
            .xiaomi_token_cn => "xiaomi-token-plan-cn",
            .xiaomi_token_ams => "xiaomi-token-plan-ams",
            .xiaomi_token_sgp => "xiaomi-token-plan-sgp",
            .sakana => "sakana",
            .arcee => "arcee",
            .morph => "morph",
            .inception => "inception",
            .poolside => "poolside",
            .thinkingmachines => "thinkingmachines",
            .kwaipilot => "kwaipilot",
            .llama => "llama",
            .amd => "amd",
            .upstage => "upstage",
            .silocloud => "silocloud",
            .siliconflow => "siliconflow",
            .siliconflow_cn => "siliconflow-cn",
            .snowflake => "snowflake-cortex",
            .weights_biases => "wandb",
            .ollama_cloud => "ollama-cloud",
            .lmstudio => "lmstudio",
            .codex => "codex",
            .ollama => "ollama",
        };
    }

    pub fn name(self: Provider) []const u8 {
        return switch (self) {
            .openai => "OpenAI",
            .anthropic => "Anthropic",
            .google => "Google Gemini",
            .grok => "Grok (xAI)",
            .mistral => "Mistral",
            .cohere => "Cohere",
            .deepseek => "DeepSeek",
            .openrouter => "OpenRouter",
            .together => "Together AI",
            .fireworks => "Fireworks AI",
            .groq => "Groq",
            .cerebras => "Cerebras",
            .novita => "Novita AI",
            .deepinfra => "DeepInfra",
            .nebius => "Nebius",
            .baseten => "Baseten",
            .hyperbolic => "Hyperbolic",
            .sambanova => "SambaNova",
            .parasail => "Parasail",
            .runinfra => "RunInfra",
            .gmicloud => "GMICloud",
            .modal => "Modal",
            .crusoe => "Crusoe",
            .digitalocean => "DigitalOcean",
            .friendli => "FriendliAI",
            .wafer => "Wafer",
            .streamlake => "StreamLake",
            .nvidia => "NVIDIA NIM",
            .databricks => "Databricks",
            .cloudflare => "Cloudflare Workers AI",
            .ovhcloud => "OVHcloud AI",
            .scaleway => "Scaleway",
            .vultr => "Vultr",
            .hetzner => "Hetzner",
            .infomaniak => "Infomaniak",
            .stackit => "STACKIT",
            .ebcloud => "EBCloud",
            .cloudferro => "CloudFerro Sherlock",
            .hpc_ai => "HPC-AI",
            .io_net => "IO.NET",
            .jalapeno => "Jalapeno Cloud",
            .kosmik => "Kosmik Compute",
            .evroc => "evroc",
            .inferx => "InferX",
            .tensorx => "TensorX",
            .mixlayer => "Mixlayer",
            .modelis => "Modelis",
            .nova => "Nova",
            .pioneer => "Pioneer",
            .opper => "Opper",
            .tinfoil => "Tinfoil",
            .vivgrid => "Vivgrid",
            .umans_ai => "Umans AI",
            .neuralwatt => "Neuralwatt",
            .privatemode => "Privatemode AI",
            .regolo => "Regolo AI",
            .scx_ai => "SCX.ai",
            .submodel => "submodel",
            .synthetic => "Synthetic",
            .moark => "Moark",
            .lilac => "Lilac",
            .longcat => "LongCat",
            .thegrid => "The Grid AI",
            .zenifra => "Zenifra",
            .zeldoc => "Zeldoc",
            .coralbricks => "CoralBricks",
            .kenari => "Kenari",
            .dinference => "DInference",
            .echo => "Echo",
            .ofoo => "Ofoo",
            .qihang => "QiHang",
            .qiniu => "Qiniu AI",
            .bailing => "Bailing",
            .daoxe => "DaoXE",
            .d_run => "D.Run (China)",
            .kuae => "KUAE Cloud",
            .scnet => "SCNet",
            .berget => "Berget.AI",
            .helicone => "Helicone",
            .cortecs => "Cortecs",
            .chutes => "Chutes",
            .fastrouter => "FastRouter",
            .greenpt => "GreenPT",
            .crofai => "CrofAI",
            .frogbot => "FrogBot",
            .impossibl => "Impossibl",
            .inceptron => "Inceptron",
            .inference => "Inference",
            .ambient => "Ambient",
            .free_model => "FreeModel",
            .nano_gpt => "NanoGPT",
            .nearai => "NEAR AI Cloud",
            .orcarouter => "OrcaRouter",
            .routing_run => "routing.run",
            .unorouter => "UnoRouter",
            .trustedrouter => "TrustedRouter",
            .zenmux => "ZenMux",
            .llmtr => "LLMTR",
            .llm_gateway => "LLM Gateway",
            .devpass => "DevPass",
            .kilo => "Kilo Gateway",
            .jiekou => "Jiekou.AI",
            .modelscope => "ModelScope",
            .kimi_coding => "Kimi For Coding",
            .opencode_zen => "OpenCode Zen",
            .opencode_go => "OpenCode Go",
            .requesty => "Requesty",
            .chutes_ai => "Chutes AI",
            .clinepass => "ClinePass",
            .atomic_chat => "Atomic Chat",
            .auriko => "Auriko",
            .claudinio => "Claudinio",
            .charm_hyper => "Charm Hyper",
            .blue_claw => "Blue Claw",
            .crofai_alt => "CrofAI Alt",
            .crossmodel => "CrossModel",
            .abacus => "Abacus",
            .ai_302 => "302.AI",
            .ai_router => "AI-ROUTER",
            .aiand => "ai&",
            .aki_io => "AKI.IO",
            .anyapi => "AnyAPI",
            .edenai => "Eden AI",
            .empiriolabs => "EmpirioLabs AI",
            .cn_line_pass => "CN Line Pass",
            .cline_pass => "Cline Pass",
            .frogbot_alt => "FrogBot Alt",
            .model_oracle => "Model Oracle AI",
            .xpersona => "Xpersona",
            .lucidquery => "LucidQuery",
            .lynkr => "Lynkr",
            .meganova => "Meganova",
            .sarvam => "Sarvam AI",
            .tencent => "Tencent Cloud",
            .tencent_token => "Tencent Token Plan",
            .tencent_tokenhub => "Tencent TokenHub",
            .tencent_coding => "Tencent Coding Plan",
            .stepfun => "StepFun (China)",
            .stepfun_ai => "StepFun (Global)",
            .stepfun_step => "StepFun Step Plan (China)",
            .stepfun_ai_step => "StepFun Step Plan (Global)",
            .alibaba => "Alibaba (DashScope)",
            .alibaba_cn => "Alibaba (China)",
            .alibaba_coding => "Alibaba Coding Plan",
            .alibaba_coding_cn => "Alibaba Coding Plan (China)",
            .alibaba_token => "Alibaba Token Plan",
            .alibaba_token_cn => "Alibaba Token Plan (China)",
            .moonshot => "Moonshot AI",
            .moonshot_cn => "Moonshot AI (China)",
            .zhipu => "Zhipu AI",
            .zhipu_coding => "Zhipu AI Coding Plan",
            .zai => "Z.AI",
            .zai_coding => "Z.AI Coding Plan",
            .minimax => "MiniMax (minimax.io)",
            .minimax_cn => "MiniMax (minimaxi.com)",
            .minimax_coding => "MiniMax Token Plan",
            .minimax_cn_coding => "MiniMax Token Plan (CN)",
            .bytedance => "ByteDance (Volcengine)",
            .xiaomi => "Xiaomi (MiMo)",
            .xiaomi_token_cn => "Xiaomi Token Plan (China)",
            .xiaomi_token_ams => "Xiaomi Token Plan (Europe)",
            .xiaomi_token_sgp => "Xiaomi Token Plan (Singapore)",
            .sakana => "Sakana AI",
            .arcee => "Arcee AI",
            .morph => "Morph",
            .inception => "Inception",
            .poolside => "Poolside",
            .thinkingmachines => "Thinking Machines",
            .kwaipilot => "Kwai (KwaiPilot)",
            .llama => "Llama",
            .amd => "AMD",
            .upstage => "Upstage",
            .silocloud => "SiloCloud",
            .siliconflow => "SiliconFlow",
            .siliconflow_cn => "SiliconFlow (China)",
            .snowflake => "Snowflake Cortex",
            .weights_biases => "Weights & Biases",
            .ollama_cloud => "Ollama Cloud",
            .lmstudio => "LMStudio",
            .codex => "OpenAI Codex",
            .ollama => "Ollama (local)",
        };
    }

    pub fn parse(value: []const u8) ?Provider {
        if (std.ascii.eqlIgnoreCase(value, "openai")) return .openai;
        if (std.ascii.eqlIgnoreCase(value, "anthropic")) return .anthropic;
        if (std.ascii.eqlIgnoreCase(value, "google") or
            std.ascii.eqlIgnoreCase(value, "gemini")) return .google;
        if (std.ascii.eqlIgnoreCase(value, "grok") or
            std.ascii.eqlIgnoreCase(value, "xai") or
            std.ascii.eqlIgnoreCase(value, "x-ai")) return .grok;
        if (std.ascii.eqlIgnoreCase(value, "mistral")) return .mistral;
        if (std.ascii.eqlIgnoreCase(value, "cohere")) return .cohere;
        if (std.ascii.eqlIgnoreCase(value, "deepseek")) return .deepseek;
        if (std.ascii.eqlIgnoreCase(value, "openrouter")) return .openrouter;
        if (std.ascii.eqlIgnoreCase(value, "together") or
            std.ascii.eqlIgnoreCase(value, "togetherai")) return .together;
        if (std.ascii.eqlIgnoreCase(value, "fireworks") or
            std.ascii.eqlIgnoreCase(value, "fireworksai")) return .fireworks;
        if (std.ascii.eqlIgnoreCase(value, "groq")) return .groq;
        if (std.ascii.eqlIgnoreCase(value, "cerebras")) return .cerebras;
        if (std.ascii.eqlIgnoreCase(value, "novita")) return .novita;
        if (std.ascii.eqlIgnoreCase(value, "deepinfra")) return .deepinfra;
        if (std.ascii.eqlIgnoreCase(value, "nebius")) return .nebius;
        if (std.ascii.eqlIgnoreCase(value, "baseten")) return .baseten;
        if (std.ascii.eqlIgnoreCase(value, "hyperbolic")) return .hyperbolic;
        if (std.ascii.eqlIgnoreCase(value, "sambanova")) return .sambanova;
        if (stdasciiParseHelper(value, "parasail")) |_| return .parasail;
        if (std.ascii.eqlIgnoreCase(value, "runinfra")) return .runinfra;
        if (std.ascii.eqlIgnoreCase(value, "gmicloud")) return .gmicloud;
        if (std.ascii.eqlIgnoreCase(value, "modal")) return .modal;
        if (std.ascii.eqlIgnoreCase(value, "crusoe")) return .crusoe;
        if (std.ascii.eqlIgnoreCase(value, "digitalocean") or
            std.ascii.eqlIgnoreCase(value, "do")) return .digitalocean;
        if (std.ascii.eqlIgnoreCase(value, "friendli") or
            std.ascii.eqlIgnoreCase(value, "friendliai")) return .friendli;
        if (std.ascii.eqlIgnoreCase(value, "wafer")) return .wafer;
        if (std.ascii.eqlIgnoreCase(value, "streamlake")) return .streamlake;
        if (std.ascii.eqlIgnoreCase(value, "nvidia")) return .nvidia;
        if (std.ascii.eqlIgnoreCase(value, "databricks")) return .databricks;
        if (std.ascii.eqlIgnoreCase(value, "cloudflare") or
            std.ascii.eqlIgnoreCase(value, "cloudflare-workers-ai")) return .cloudflare;
        if (std.ascii.eqlIgnoreCase(value, "ovhcloud")) return .ovhcloud;
        if (std.ascii.eqlIgnoreCase(value, "scaleway")) return .scaleway;
        if (std.ascii.eqlIgnoreCase(value, "vultr")) return .vultr;
        if (std.ascii.eqlIgnoreCase(value, "hetzner")) return .hetzner;
        if (std.ascii.eqlIgnoreCase(value, "infomaniak")) return .infomaniak;
        if (std.ascii.eqlIgnoreCase(value, "stackit")) return .stackit;
        if (std.ascii.eqlIgnoreCase(value, "ebcloud")) return .ebcloud;
        if (std.ascii.eqlIgnoreCase(value, "cloudferro") or
            std.ascii.eqlIgnoreCase(value, "cloudferro-sherlock")) return .cloudferro;
        if (std.ascii.eqlIgnoreCase(value, "hpc-ai") or
            std.ascii.eqlIgnoreCase(value, "hpc_ai")) return .hpc_ai;
        if (std.ascii.eqlIgnoreCase(value, "io-net") or
            std.ascii.eqlIgnoreCase(value, "io_net")) return .io_net;
        if (std.ascii.eqlIgnoreCase(value, "jalapeno")) return .jalapeno;
        if (std.ascii.eqlIgnoreCase(value, "kosmik")) return .kosmik;
        if (std.ascii.eqlIgnoreCase(value, "evroc")) return .evroc;
        if (std.ascii.eqlIgnoreCase(value, "inferx")) return .inferx;
        if (std.ascii.eqlIgnoreCase(value, "tensorx")) return .tensorx;
        if (std.ascii.eqlIgnoreCase(value, "mixlayer")) return .mixlayer;
        if (std.ascii.eqlIgnoreCase(value, "modelis")) return .modelis;
        if (std.ascii.eqlIgnoreCase(value, "nova")) return .nova;
        if (std.ascii.eqlIgnoreCase(value, "pioneer")) return .pioneer;
        if (std.ascii.eqlIgnoreCase(value, "opper")) return .opper;
        if (std.ascii.eqlIgnoreCase(value, "tinfoil")) return .tinfoil;
        if (std.ascii.eqlIgnoreCase(value, "vivgrid")) return .vivgrid;
        if (std.ascii.eqlIgnoreCase(value, "umans-ai") or
            std.ascii.eqlIgnoreCase(value, "umans_ai")) return .umans_ai;
        if (std.ascii.eqlIgnoreCase(value, "neuralwatt")) return .neuralwatt;
        if (std.ascii.eqlIgnoreCase(value, "privatemode") or
            std.ascii.eqlIgnoreCase(value, "privatemode-ai")) return .privatemode;
        if (std.ascii.eqlIgnoreCase(value, "regolo") or
            std.ascii.eqlIgnoreCase(value, "regolo-ai")) return .regolo;
        if (std.ascii.eqlIgnoreCase(value, "scx") or
            std.ascii.eqlIgnoreCase(value, "scx-ai")) return .scx_ai;
        if (std.ascii.eqlIgnoreCase(value, "submodel")) return .submodel;
        if (std.ascii.eqlIgnoreCase(value, "synthetic")) return .synthetic;
        if (std.ascii.eqlIgnoreCase(value, "moark")) return .moark;
        if (std.ascii.eqlIgnoreCase(value, "lilac")) return .lilac;
        if (std.ascii.eqlIgnoreCase(value, "longcat")) return .longcat;
        if (std.ascii.eqlIgnoreCase(value, "the-grid-ai") or
            std.ascii.eqlIgnoreCase(value, "thegrid")) return .thegrid;
        if (std.ascii.eqlIgnoreCase(value, "zenifra")) return .zenifra;
        if (std.ascii.eqlIgnoreCase(value, "zeldoc")) return .zeldoc;
        if (std.ascii.eqlIgnoreCase(value, "coralbricks")) return .coralbricks;
        if (std.ascii.eqlIgnoreCase(value, "kenari")) return .kenari;
        if (std.ascii.eqlIgnoreCase(value, "dinference")) return .dinference;
        if (std.ascii.eqlIgnoreCase(value, "echo")) return .echo;
        if (std.ascii.eqlIgnoreCase(value, "ofoo")) return .ofoo;
        if (std.ascii.eqlIgnoreCase(value, "qihang") or
            std.ascii.eqlIgnoreCase(value, "qihang-ai")) return .qihang;
        if (std.ascii.eqlIgnoreCase(value, "qiniu") or
            std.ascii.eqlIgnoreCase(value, "qiniu-ai")) return .qiniu;
        if (std.ascii.eqlIgnoreCase(value, "bailing")) return .bailing;
        if (std.ascii.eqlIgnoreCase(value, "daoxe")) return .daoxe;
        if (std.ascii.eqlIgnoreCase(value, "drun") or
            std.ascii.eqlIgnoreCase(value, "d-run") or
            std.ascii.eqlIgnoreCase(value, "d_run")) return .d_run;
        if (std.ascii.eqlIgnoreCase(value, "kuae") or
            std.ascii.eqlIgnoreCase(value, "kuae-cloud-coding-plan")) return .kuae;
        if (std.ascii.eqlIgnoreCase(value, "scnet") or
            std.ascii.eqlIgnoreCase(value, "scnet-token-plan")) return .scnet;
        if (std.ascii.eqlIgnoreCase(value, "berget") or
            std.ascii.eqlIgnoreCase(value, "berget.ai")) return .berget;
        if (std.ascii.eqlIgnoreCase(value, "helicone")) return .helicone;
        if (std.ascii.eqlIgnoreCase(value, "cortecs")) return .cortecs;
        if (std.ascii.eqlIgnoreCase(value, "chutes")) return .chutes;
        if (std.ascii.eqlIgnoreCase(value, "fastrouter")) return .fastrouter;
        if (std.ascii.eqlIgnoreCase(value, "greenpt")) return .greenpt;
        if (std.ascii.eqlIgnoreCase(value, "crofai")) return .crofai;
        if (std.ascii.eqlIgnoreCase(value, "frogbot")) return .frogbot;
        if (std.ascii.eqlIgnoreCase(value, "impossibl")) return .impossibl;
        if (std.ascii.eqlIgnoreCase(value, "inceptron")) return .inceptron;
        if (std.ascii.eqlIgnoreCase(value, "inference")) return .inference;
        if (std.ascii.eqlIgnoreCase(value, "ambient")) return .ambient;
        if (std.ascii.eqlIgnoreCase(value, "freemodel") or
            std.ascii.eqlIgnoreCase(value, "free_model")) return .free_model;
        if (std.ascii.eqlIgnoreCase(value, "nano-gpt") or
            std.ascii.eqlIgnoreCase(value, "nano_gpt")) return .nano_gpt;
        if (std.ascii.eqlIgnoreCase(value, "nearai") or
            std.ascii.eqlIgnoreCase(value, "near-ai")) return .nearai;
        if (std.ascii.eqlIgnoreCase(value, "orcarouter")) return .orcarouter;
        if (std.ascii.eqlIgnoreCase(value, "routing-run") or
            std.ascii.eqlIgnoreCase(value, "routing_run")) return .routing_run;
        if (std.ascii.eqlIgnoreCase(value, "unorouter")) return .unorouter;
        if (std.ascii.eqlIgnoreCase(value, "trustedrouter")) return .trustedrouter;
        if (std.ascii.eqlIgnoreCase(value, "zenmux")) return .zenmux;
        if (std.ascii.eqlIgnoreCase(value, "llmtr")) return .llmtr;
        if (std.ascii.eqlIgnoreCase(value, "llmgateway") or
            std.ascii.eqlIgnoreCase(value, "llm-gateway") or
            std.ascii.eqlIgnoreCase(value, "llm_gateway")) return .llm_gateway;
        if (std.ascii.eqlIgnoreCase(value, "devpass")) return .devpass;
        if (std.ascii.eqlIgnoreCase(value, "kilo") or
            std.ascii.eqlIgnoreCase(value, "kilo-gateway")) return .kilo;
        if (std.ascii.eqlIgnoreCase(value, "jiekou") or
            std.ascii.eqlIgnoreCase(value, "jiekou.ai")) return .jiekou;
        if (std.ascii.eqlIgnoreCase(value, "modelscope")) return .modelscope;
        if (std.ascii.eqlIgnoreCase(value, "kimi-for-coding") or
            std.ascii.eqlIgnoreCase(value, "kimi_coding")) return .kimi_coding;
        if (std.ascii.eqlIgnoreCase(value, "opencode") or
            std.ascii.eqlIgnoreCase(value, "opencode-zen") or
            std.ascii.eqlIgnoreCase(value, "opencode_zen")) return .opencode_zen;
        if (std.ascii.eqlIgnoreCase(value, "opencode-go") or
            std.ascii.eqlIgnoreCase(value, "opencode_go")) return .opencode_go;
        if (std.ascii.eqlIgnoreCase(value, "requesty")) return .requesty;
        if (std.ascii.eqlIgnoreCase(value, "clinepass") or
            std.ascii.eqlIgnoreCase(value, "cline-pass") or
            std.ascii.eqlIgnoreCase(value, "cline_pass")) return .clinepass;
        if (std.ascii.eqlIgnoreCase(value, "atomic-chat") or
            std.ascii.eqlIgnoreCase(value, "atomic_chat")) return .atomic_chat;
        if (std.ascii.eqlIgnoreCase(value, "auriko")) return .auriko;
        if (std.ascii.eqlIgnoreCase(value, "claudinio")) return .claudinio;
        if (std.ascii.eqlIgnoreCase(value, "charm-hyper") or
            std.ascii.eqlIgnoreCase(value, "charm_hyper") or
            std.ascii.eqlIgnoreCase(value, "hyper")) return .charm_hyper;
        if (std.ascii.eqlIgnoreCase(value, "blueclaw") or
            std.ascii.eqlIgnoreCase(value, "blue-claw") or
            std.ascii.eqlIgnoreCase(value, "blue_claw")) return .blue_claw;
        if (std.ascii.eqlIgnoreCase(value, "crossmodel")) return .crossmodel;
        if (std.ascii.eqlIgnoreCase(value, "abacus")) return .abacus;
        if (std.ascii.eqlIgnoreCase(value, "302ai") or
            std.ascii.eqlIgnoreCase(value, "302.ai") or
            std.ascii.eqlIgnoreCase(value, "ai_302")) return .ai_302;
        if (std.ascii.eqlIgnoreCase(value, "ai-router") or
            std.ascii.eqlIgnoreCase(value, "ai_router")) return .ai_router;
        if (std.ascii.eqlIgnoreCase(value, "aiand")) return .aiand;
        if (std.ascii.eqlIgnoreCase(value, "aki-io") or
            std.ascii.eqlIgnoreCase(value, "aki_io") or
            std.ascii.eqlIgnoreCase(value, "aki.io")) return .aki_io;
        if (std.ascii.eqlIgnoreCase(value, "anyapi")) return .anyapi;
        if (std.ascii.eqlIgnoreCase(value, "edenai") or
            std.ascii.eqlIgnoreCase(value, "eden-ai")) return .edenai;
        if (std.ascii.eqlIgnoreCase(value, "empiriolabs") or
            std.ascii.eqlIgnoreCase(value, "empirio")) return .empiriolabs;
        if (std.ascii.eqlIgnoreCase(value, "model-oracle-ai") or
            std.ascii.eqlIgnoreCase(value, "model_oracle")) return .model_oracle;
        if (std.ascii.eqlIgnoreCase(value, "xpersona")) return .xpersona;
        if (std.ascii.eqlIgnoreCase(value, "lucidquery")) return .lucidquery;
        if (std.ascii.eqlIgnoreCase(value, "lynkr")) return .lynkr;
        if (std.ascii.eqlIgnoreCase(value, "meganova")) return .meganova;
        if (std.ascii.eqlIgnoreCase(value, "sarvam") or
            std.ascii.eqlIgnoreCase(value, "sarvam-ai")) return .sarvam;
        if (std.ascii.eqlIgnoreCase(value, "tencent")) return .tencent;
        if (std.ascii.eqlIgnoreCase(value, "tencent-token-plan") or
            std.ascii.eqlIgnoreCase(value, "tencent_token")) return .tencent_token;
        if (std.ascii.eqlIgnoreCase(value, "tencent-tokenhub") or
            std.ascii.eqlIgnoreCase(value, "tencent_tokenhub")) return .tencent_tokenhub;
        if (std.ascii.eqlIgnoreCase(value, "tencent-coding-plan") or
            std.ascii.eqlIgnoreCase(value, "tencent_coding")) return .tencent_coding;
        if (std.ascii.eqlIgnoreCase(value, "stepfun") or
            std.ascii.eqlIgnoreCase(value, "stepfun-cn")) return .stepfun;
        if (std.ascii.eqlIgnoreCase(value, "stepfun-ai") or
            std.ascii.eqlIgnoreCase(value, "stepfun_ai")) return .stepfun_ai;
        if (std.ascii.eqlIgnoreCase(value, "stepfun-step-plan") or
            std.ascii.eqlIgnoreCase(value, "stepfun_step")) return .stepfun_step;
        if (std.ascii.eqlIgnoreCase(value, "stepfun-ai-step-plan") or
            std.ascii.eqlIgnoreCase(value, "stepfun_ai_step")) return .stepfun_ai_step;
        if (std.ascii.eqlIgnoreCase(value, "alibaba") or
            std.ascii.eqlIgnoreCase(value, "dashscope")) return .alibaba;
        if (std.ascii.eqlIgnoreCase(value, "alibaba-cn") or
            std.ascii.eqlIgnoreCase(value, "alibaba_cn")) return .alibaba_cn;
        if (std.ascii.eqlIgnoreCase(value, "alibaba-coding-plan") or
            std.ascii.eqlIgnoreCase(value, "alibaba_coding")) return .alibaba_coding;
        if (std.ascii.eqlIgnoreCase(value, "alibaba-coding-plan-cn") or
            std.ascii.eqlIgnoreCase(value, "alibaba_coding_cn")) return .alibaba_coding_cn;
        if (std.ascii.eqlIgnoreCase(value, "alibaba-token-plan") or
            std.ascii.eqlIgnoreCase(value, "alibaba_token")) return .alibaba_token;
        if (std.ascii.eqlIgnoreCase(value, "alibaba-token-plan-cn") or
            std.ascii.eqlIgnoreCase(value, "alibaba_token_cn")) return .alibaba_token_cn;
        if (std.ascii.eqlIgnoreCase(value, "moonshot") or
            std.ascii.eqlIgnoreCase(value, "moonshotai") or
            std.ascii.eqlIgnoreCase(value, "kimi")) return .moonshot;
        if (std.ascii.eqlIgnoreCase(value, "moonshotai-cn") or
            std.ascii.eqlIgnoreCase(value, "moonshot_cn")) return .moonshot_cn;
        if (std.ascii.eqlIgnoreCase(value, "zhipu") or
            std.ascii.eqlIgnoreCase(value, "zhipuai") or
            std.ascii.eqlIgnoreCase(value, "glm")) return .zhipu;
        if (std.ascii.eqlIgnoreCase(value, "zhipuai-coding-plan") or
            std.ascii.eqlIgnoreCase(value, "zhipu_coding")) return .zhipu_coding;
        if (std.ascii.eqlIgnoreCase(value, "zai") or
            std.ascii.eqlIgnoreCase(value, "z.ai")) return .zai;
        if (std.ascii.eqlIgnoreCase(value, "zai-coding-plan") or
            std.ascii.eqlIgnoreCase(value, "zai_coding")) return .zai_coding;
        if (std.ascii.eqlIgnoreCase(value, "minimax")) return .minimax;
        if (std.ascii.eqlIgnoreCase(value, "minimax-cn") or
            std.ascii.eqlIgnoreCase(value, "minimax_cn")) return .minimax_cn;
        if (std.ascii.eqlIgnoreCase(value, "minimax-coding-plan") or
            std.ascii.eqlIgnoreCase(value, "minimax_coding")) return .minimax_coding;
        if (std.ascii.eqlIgnoreCase(value, "minimax-cn-coding-plan") or
            std.ascii.eqlIgnoreCase(value, "minimax_cn_coding")) return .minimax_cn_coding;
        if (std.ascii.eqlIgnoreCase(value, "bytedance") or
            std.ascii.eqlIgnoreCase(value, "volcengine")) return .bytedance;
        if (std.ascii.eqlIgnoreCase(value, "xiaomi") or
            std.ascii.eqlIgnoreCase(value, "mimo")) return .xiaomi;
        if (std.ascii.eqlIgnoreCase(value, "xiaomi-token-plan-cn") or
            std.ascii.eqlIgnoreCase(value, "xiaomi_token_cn")) return .xiaomi_token_cn;
        if (std.ascii.eqlIgnoreCase(value, "xiaomi-token-plan-ams") or
            std.ascii.eqlIgnoreCase(value, "xiaomi_token_ams")) return .xiaomi_token_ams;
        if (std.ascii.eqlIgnoreCase(value, "xiaomi-token-plan-sgp") or
            std.ascii.eqlIgnoreCase(value, "xiaomi_token_sgp")) return .xiaomi_token_sgp;
        if (std.ascii.eqlIgnoreCase(value, "sakana") or
            std.ascii.eqlIgnoreCase(value, "sakana-ai")) return .sakana;
        if (std.ascii.eqlIgnoreCase(value, "arcee") or
            std.ascii.eqlIgnoreCase(value, "arcee-ai")) return .arcee;
        if (std.ascii.eqlIgnoreCase(value, "morph")) return .morph;
        if (std.ascii.eqlIgnoreCase(value, "inception")) return .inception;
        if (std.ascii.eqlIgnoreCase(value, "poolside")) return .poolside;
        if (std.ascii.eqlIgnoreCase(value, "thinkingmachines") or
            std.ascii.eqlIgnoreCase(value, "thinking-machines") or
            std.ascii.eqlIgnoreCase(value, "thinkingmachines")) return .thinkingmachines;
        if (std.ascii.eqlIgnoreCase(value, "kwaipilot") or
            std.ascii.eqlIgnoreCase(value, "kwai")) return .kwaipilot;
        if (std.ascii.eqlIgnoreCase(value, "llama")) return .llama;
        if (std.ascii.eqlIgnoreCase(value, "amd")) return .amd;
        if (std.ascii.eqlIgnoreCase(value, "upstage")) return .upstage;
        if (std.ascii.eqlIgnoreCase(value, "silocloud") or
            std.ascii.eqlIgnoreCase(value, "silo-cloud")) return .silocloud;
        if (std.ascii.eqlIgnoreCase(value, "siliconflow")) return .siliconflow;
        if (std.ascii.eqlIgnoreCase(value, "siliconflow-cn") or
            std.ascii.eqlIgnoreCase(value, "siliconflow_cn")) return .siliconflow_cn;
        if (std.ascii.eqlIgnoreCase(value, "snowflake") or
            std.ascii.eqlIgnoreCase(value, "snowflake-cortex")) return .snowflake;
        if (std.ascii.eqlIgnoreCase(value, "wandb") or
            std.ascii.eqlIgnoreCase(value, "weights-biases") or
            std.ascii.eqlIgnoreCase(value, "weights_biases")) return .weights_biases;
        if (std.ascii.eqlIgnoreCase(value, "ollama-cloud") or
            std.ascii.eqlIgnoreCase(value, "ollama_cloud")) return .ollama_cloud;
        if (std.ascii.eqlIgnoreCase(value, "lmstudio") or
            std.ascii.eqlIgnoreCase(value, "lm-studio")) return .lmstudio;
        if (std.ascii.eqlIgnoreCase(value, "codex")) return .codex;
        if (std.ascii.eqlIgnoreCase(value, "ollama")) return .ollama;
        return null;
    }

    pub fn chatUrl(self: Provider) []const u8 {
        return switch (self) {
            .openai => "https://api.openai.com/v1/chat/completions",
            .anthropic => "https://api.anthropic.com/v1/messages",
            .google => "https://generativelanguage.googleapis.com/v1beta/chat/completions",
            .grok => "https://api.x.ai/v1/chat/completions",
            .mistral => "https://api.mistral.ai/v1/chat/completions",
            .cohere => "https://api.cohere.com/v2/chat",
            .deepseek => "https://api.deepseek.com/chat/completions",
            .openrouter => "https://openrouter.ai/api/v1/chat/completions",
            .together => "https://api.together.xyz/v1/chat/completions",
            .fireworks => "https://api.fireworks.ai/inference/v1/chat/completions",
            .groq => "https://api.groq.com/openai/v1/chat/completions",
            .cerebras => "https://api.cerebras.ai/v1/chat/completions",
            .novita => "https://api.novita.ai/v3/openai/chat/completions",
            .deepinfra => "https://api.deepinfra.com/v1/openai/chat/completions",
            .nebius => "https://api.studio.nebius.ai/v1/chat/completions",
            .baseten => "https://model.api.baseten.co/environments/production",
            .hyperbolic => "https://api.hyperbolic.xyz/v1/chat/completions",
            .sambanova => "https://api.sambanova.ai/v1/chat/completions",
            .parasail => "https://api.parasail.io/v1/chat/completions",
            .runinfra => "https://api.runinfra.ai/v1/chat/completions",
            .gmicloud => "https://api.gmicloud.ai/v1/chat/completions",
            .modal => "https://modal-labs--example-openai-compatible-endpoint.modal.run/v1/chat/completions",
            .crusoe => "https://api.crusoe.ai/v1/chat/completions",
            .digitalocean => "https://inference.do-ai.run/v1/chat/completions",
            .friendli => "https://api.friendli.ai/v1/chat/completions",
            .wafer => "https://api.wafer.ai/v1/chat/completions",
            .streamlake => "https://api.streamlake.ai/v1/chat/completions",
            .nvidia => "https://integrate.api.nvidia.com/v1/chat/completions",
            .databricks => "https://DATABRICKS_HOST/ai-gateway/mlflow/v1/chat/completions",
            .cloudflare => "https://api.cloudflare.com/client/v4/accounts/CLOUDFLARE_ACCOUNT_ID/ai/v1/chat/completions",
            .ovhcloud => "https://oai.endpoints.kepler.ai.cloud.ovh.net/v1/chat/completions",
            .scaleway => "https://api.scaleway.ai/v1/chat/completions",
            .vultr => "https://api.vultrinference.com/v1/chat/completions",
            .hetzner => "https://api.hetzner.ai/v1/chat/completions",
            .infomaniak => "https://api.infomaniak.ai/v1/chat/completions",
            .stackit => "https://api.stackit.dev/v1/chat/completions",
            .ebcloud => "https://api.ebcloud.com/v1/chat/completions",
            .cloudferro => "https://api.cloudferro.ai/v1/chat/completions",
            .hpc_ai => "https://api.hpc-ai.com/v1/chat/completions",
            .io_net => "https://api.io.net/v1/chat/completions",
            .jalapeno => "https://api.jalapeno.ai/v1/chat/completions",
            .kosmik => "https://api.kosmik.ai/v1/chat/completions",
            .evroc => "https://api.evroc.ai/v1/chat/completions",
            .inferx => "https://api.inferx.ai/v1/chat/completions",
            .tensorx => "https://api.tensorx.ai/v1/chat/completions",
            .mixlayer => "https://api.mixlayer.ai/v1/chat/completions",
            .modelis => "https://api.modelis.ai/v1/chat/completions",
            .nova => "https://api.nova.ai/v1/chat/completions",
            .pioneer => "https://api.pioneer.ai/v1/chat/completions",
            .opper => "https://api.opper.ai/v1/chat/completions",
            .tinfoil => "https://api.tinfoil.ai/v1/chat/completions",
            .vivgrid => "https://api.vivgrid.ai/v1/chat/completions",
            .umans_ai => "https://api.umans.ai/v1/chat/completions",
            .neuralwatt => "https://api.neuralwatt.ai/v1/chat/completions",
            .privatemode => "https://api.privatemode.ai/v1/chat/completions",
            .regolo => "https://api.regolo.ai/v1/chat/completions",
            .scx_ai => "https://api.scx.ai/v1/chat/completions",
            .submodel => "https://api.submodel.ai/v1/chat/completions",
            .synthetic => "https://api.synthetic.ai/v1/chat/completions",
            .moark => "https://api.moark.ai/v1/chat/completions",
            .lilac => "https://api.lilac.ai/v1/chat/completions",
            .longcat => "https://api.longcat.ai/v1/chat/completions",
            .thegrid => "https://api.thegrid.ai/v1/chat/completions",
            .zenifra => "https://api.zenifra.ai/v1/chat/completions",
            .zeldoc => "https://api.zeldoc.ai/v1/chat/completions",
            .coralbricks => "https://api.coralbricks.ai/v1/chat/completions",
            .kenari => "https://api.kenari.ai/v1/chat/completions",
            .dinference => "https://api.dinference.ai/v1/chat/completions",
            .echo => "https://api.echo.ai/v1/chat/completions",
            .ofoo => "https://api.ofoo.ai/v1/chat/completions",
            .qihang => "https://api.qihang.ai/v1/chat/completions",
            .qiniu => "https://api.qiniu.ai/v1/chat/completions",
            .bailing => "https://api.bailing.ai/v1/chat/completions",
            .daoxe => "https://api.daoxe.ai/v1/chat/completions",
            .d_run => "https://api.d.run/v1/chat/completions",
            .kuae => "https://api.kuae.ai/v1/chat/completions",
            .scnet => "https://api.scnet.ai/v1/chat/completions",
            .berget => "https://api.berget.ai/v1/chat/completions",
            .helicone => "https://api.helicone.ai/v1/chat/completions",
            .cortecs => "https://api.cortecs.ai/v1/chat/completions",
            .chutes => "https://api.chutes.ai/v1/chat/completions",
            .fastrouter => "https://api.fastrouter.ai/v1/chat/completions",
            .greenpt => "https://api.greenpt.ai/v1/chat/completions",
            .crofai => "https://api.crofai.ai/v1/chat/completions",
            .frogbot => "https://api.frogbot.ai/v1/chat/completions",
            .impossibl => "https://api.impossibl.ai/v1/chat/completions",
            .inceptron => "https://api.inceptron.ai/v1/chat/completions",
            .inference => "https://api.inference.ai/v1/chat/completions",
            .ambient => "https://api.ambient.ai/v1/chat/completions",
            .free_model => "https://api.freemodel.ai/v1/chat/completions",
            .nano_gpt => "https://api.nano-gpt.com/v1/chat/completions",
            .nearai => "https://api.near.ai/v1/chat/completions",
            .orcarouter => "https://api.orcarouter.ai/v1/chat/completions",
            .routing_run => "https://api.routing.run/v1/chat/completions",
            .unorouter => "https://api.unorouter.ai/v1/chat/completions",
            .trustedrouter => "https://api.trustedrouter.ai/v1/chat/completions",
            .zenmux => "https://api.zenmux.ai/v1/chat/completions",
            .llmtr => "https://api.llmtr.ai/v1/chat/completions",
            .llm_gateway => "https://api.llmgateway.ai/v1/chat/completions",
            .devpass => "https://api.devpass.ai/v1/chat/completions",
            .kilo => "https://api.kilo.ai/v1/chat/completions",
            .jiekou => "https://api.jiekou.ai/v1/chat/completions",
            .modelscope => "https://api.modelscope.ai/v1/chat/completions",
            .kimi_coding => "https://api.kimi-for-coding.ai/v1/chat/completions",
            .opencode_zen => "https://opencode.ai/zen/v1/chat/completions",
            .opencode_go => "https://opencode.ai/zen/go/v1/chat/completions",
            .requesty => "https://api.requesty.ai/v1/chat/completions",
            .chutes_ai => "https://api.chutes.ai/v1/chat/completions",
            .clinepass => "https://api.clinepass.ai/v1/chat/completions",
            .atomic_chat => "https://api.atomic-chat.ai/v1/chat/completions",
            .auriko => "https://api.auriko.ai/v1/chat/completions",
            .claudinio => "https://api.claudinio.ai/v1/chat/completions",
            .charm_hyper => "https://api.hyper.ai/v1/chat/completions",
            .blue_claw => "https://api.blueclaw.ai/v1/chat/completions",
            .crofai_alt => "https://api.crofai.ai/v1/chat/completions",
            .crossmodel => "https://api.crossmodel.ai/v1/chat/completions",
            .abacus => "https://api.abacus.ai/v1/chat/completions",
            .ai_302 => "https://api.302.ai/v1/chat/completions",
            .ai_router => "https://api.ai-router.ai/v1/chat/completions",
            .aiand => "https://api.aiand.ai/v1/chat/completions",
            .aki_io => "https://api.aki.io/v1/chat/completions",
            .anyapi => "https://api.anyapi.ai/v1/chat/completions",
            .edenai => "https://api.edenai.ai/v1/chat/completions",
            .empiriolabs => "https://api.empiriolabs.ai/v1/chat/completions",
            .cn_line_pass => "https://api.cn-line-pass.ai/v1/chat/completions",
            .cline_pass => "https://api.cline-pass.ai/v1/chat/completions",
            .frogbot_alt => "https://api.frogbot.ai/v1/chat/completions",
            .model_oracle => "https://api.model-oracle-ai.ai/v1/chat/completions",
            .xpersona => "https://api.xpersona.ai/v1/chat/completions",
            .lucidquery => "https://api.lucidquery.ai/v1/chat/completions",
            .lynkr => "https://api.lynkr.ai/v1/chat/completions",
            .meganova => "https://api.meganova.ai/v1/chat/completions",
            .sarvam => "https://api.sarvam.ai/v1/chat/completions",
            .tencent => "https://api.hunyuan.cloud.tencent.com/v1/chat/completions",
            .tencent_token => "https://api.tencent-token.ai/v1/chat/completions",
            .tencent_tokenhub => "https://api.tencent-tokenhub.ai/v1/chat/completions",
            .tencent_coding => "https://api.tencent-coding.ai/v1/chat/completions",
            .stepfun => "https://api.stepfun.com/v1/chat/completions",
            .stepfun_ai => "https://api.stepfun.ai/v1/chat/completions",
            .stepfun_step => "https://api.stepfun-step.ai/v1/chat/completions",
            .stepfun_ai_step => "https://api.stepfun-ai-step.ai/v1/chat/completions",
            .alibaba => "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions",
            .alibaba_cn => "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            .alibaba_coding => "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions",
            .alibaba_coding_cn => "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            .alibaba_token => "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions",
            .alibaba_token_cn => "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            .moonshot => "https://api.moonshot.cn/v1/chat/completions",
            .moonshot_cn => "https://api.moonshot.cn/v1/chat/completions",
            .zhipu => "https://open.bigmodel.cn/api/paas/v4/chat/completions",
            .zhipu_coding => "https://open.bigmodel.cn/api/paas/v4/chat/completions",
            .zai => "https://api.z.ai/api/paas/v4/chat/completions",
            .zai_coding => "https://api.z.ai/api/paas/v4/chat/completions",
            .minimax => "https://api.minimax.chat/v1/chat/completions",
            .minimax_cn => "https://api.minimaxi.com/v1/chat/completions",
            .minimax_coding => "https://api.minimax.chat/v1/chat/completions",
            .minimax_cn_coding => "https://api.minimaxi.com/v1/chat/completions",
            .bytedance => "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
            .xiaomi => "https://api.mimo.xiaomi.com/v1/chat/completions",
            .xiaomi_token_cn => "https://api.mimo.xiaomi.com/v1/chat/completions",
            .xiaomi_token_ams => "https://api.mimo-eu.xiaomi.com/v1/chat/completions",
            .xiaomi_token_sgp => "https://api.mimo-sgp.xiaomi.com/v1/chat/completions",
            .sakana => "https://api.sakana.ai/v1/chat/completions",
            .arcee => "https://api.arcee.ai/v1/chat/completions",
            .morph => "https://api.morph.ai/v1/chat/completions",
            .inception => "https://api.inceptionlabs.ai/v1/chat/completions",
            .poolside => "https://api.poolside.ai/v1/chat/completions",
            .thinkingmachines => "https://api.thinkingmachines.ai/v1/chat/completions",
            .kwaipilot => "https://api.kwaipilot.ai/v1/chat/completions",
            .llama => "https://api.llama-api.com/v1/chat/completions",
            .amd => "https://api.amd.com/v1/chat/completions",
            .upstage => "https://api.upstage.ai/v1/solar/chat/completions",
            .silocloud => "https://api.silocloud.ai/v1/chat/completions",
            .siliconflow => "https://api.siliconflow.com/v1/chat/completions",
            .siliconflow_cn => "https://api.siliconflow.cn/v1/chat/completions",
            .snowflake => "https://SNOWFLAKE_ACCOUNT.snowflakecomputing.com/api/v2/cortex/v1/chat/completions",
            .weights_biases => "https://api.wandb.ai/v1/chat/completions",
            .ollama_cloud => "https://api.ollama-cloud.com/v1/chat/completions",
            .lmstudio => "http://127.0.0.1:1234/v1/chat/completions",
            .codex => "https://chatgpt.com/backend-api/codex/responses",
            .ollama => "http://127.0.0.1:11434/v1/chat/completions",
        };
    }

    pub fn defaultModel(self: Provider) []const u8 {
        return self.models()[0];
    }

    pub fn models(self: Provider) []const []const u8 {
        return switch (self) {
            .openai => &.{
                "gpt-5.6", "gpt-5.6-luna", "gpt-5.6-sol", "gpt-5.6-terra",
                "gpt-5.5", "gpt-5.5-pro", "gpt-5.4", "gpt-5.4-mini",
                "gpt-5.4-nano", "gpt-5.4-pro", "gpt-5.3-codex", "gpt-5.3-codex-spark",
                "gpt-5.2", "gpt-5.2-pro", "gpt-5.1", "gpt-5",
                "gpt-5-mini", "gpt-5-nano", "gpt-5-pro",
                "gpt-4.1", "gpt-4.1-mini", "gpt-4o", "gpt-4o-mini",
                "o3", "o3-pro",
            },
            .anthropic => &.{
                "claude-sonnet-5", "claude-sonnet-4-6", "claude-sonnet-4-5",
                "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7",
                "claude-opus-4-6", "claude-opus-4-5", "claude-haiku-4-5",
                "claude-fable-5",
            },
            .google => &.{
                "gemini-3.7-flash", "gemini-3.6-flash", "gemini-3.5-flash",
                "gemini-3.5-flash-lite", "gemini-3.1-pro-preview",
                "gemini-3.1-flash-lite", "gemini-3-flash-preview",
                "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite",
                "gemini-flash-latest", "gemini-flash-lite-latest",
            },
            .grok => &.{
                "grok-4.6", "grok-4.5", "grok-4.3",
                "grok-4.20-0309-reasoning", "grok-4.20-0309-non-reasoning",
                "grok-4.20-multi-agent-0309", "grok-build-0.1",
            },
            .mistral => &.{
                "mistral-large-latest", "mistral-large-2512",
                "mistral-medium-latest", "mistral-medium-2604",
                "mistral-small-latest", "mistral-small-2603",
                "codestral-latest", "magistral-medium-latest", "magistral-small",
                "ministral-8b-latest", "ministral-3b-latest",
                "mistral-nemo", "pixtral-large-latest", "pixtral-12b",
                "open-mixtral-8x22b", "open-mixtral-8x7b", "open-mistral-7b",
            },
            .cohere => &.{
                "command-a", "command-r-plus", "command-r", "command-r7b-12-2024",
            },
            .deepseek => &.{
                "deepseek-chat", "deepseek-reasoner",
                "deepseek-v4-flash", "deepseek-v4-flash-vision-exp", "deepseek-v4-pro",
            },
            .openrouter => &.{
                "openai/gpt-5.6", "openai/gpt-5.5", "openai/gpt-5.4",
                "anthropic/claude-sonnet-5", "anthropic/claude-opus-5",
                "anthropic/claude-haiku-4-5",
                "google/gemini-3.7-flash", "google/gemini-3.5-flash",
                "x-ai/grok-4.6", "x-ai/grok-4.5",
                "deepseek/deepseek-chat", "deepseek/deepseek-v4-flash",
                "qwen/qwen3-coder", "meta-llama/llama-3.3-70b-instruct",
            },
            .together => &.{
                "meta-llama/Llama-3.3-70B-Instruct-Turbo",
                "meta-llama/Meta-Llama-3-8B-Instruct-Lite",
                "deepseek-ai/DeepSeek-V4-Flash-0731", "deepseek-ai/DeepSeek-V4-Pro-0813",
                "Qwen/Qwen3.7-Max", "Qwen/Qwen3.6-Plus", "Qwen/Qwen3.5-9B",
                "MiniMaxAI/MiniMax-M3", "MiniMaxAI/MiniMax-M2.7",
                "moonshotai/Kimi-K3", "moonshotai/Kimi-K2.7-Code", "moonshotai/Kimi-K2.6",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b", "openai/gpt-oss-20b",
            },
            .fireworks => &.{
                "accounts/fireworks/models/deepseek-v4-flash",
                "accounts/fireworks/models/deepseek-v4-pro",
                "accounts/fireworks/models/glm-5p2",
                "accounts/fireworks/models/kimi-k3",
                "accounts/fireworks/models/kimi-k2p7-code",
                "accounts/fireworks/models/kimi-k2p6",
                "accounts/fireworks/models/minimax-m3",
                "accounts/fireworks/models/minimax-m2p7",
                "accounts/fireworks/models/qwen3p8-max",
                "accounts/fireworks/models/qwen3p7-plus",
                "accounts/fireworks/models/gpt-oss-120b",
                "accounts/fireworks/models/gpt-oss-20b",
                "accounts/fireworks/models/inkling",
                "accounts/fireworks/models/muse-glimmer-30b",
                "accounts/fireworks/models/nemotron-3-ultra-nvfp4",
            },
            .groq => &.{
                "groq/compound", "groq/compound-mini",
                "llama-3.3-70b-versatile", "llama-3.1-8b-instant",
                "openai/gpt-oss-120b", "openai/gpt-oss-20b",
                "qwen/qwen3.6-27b",
            },
            .cerebras => &.{
                "gpt-oss-120b", "gemma-4-31b",
            },
            .novita => &.{
                "deepseek/deepseek-r1-0528", "deepseek/deepseek-v3-0324",
                "deepseek/deepseek-v3.1", "deepseek/deepseek-r1-turbo",
                "qwen/qwen3-235b-a22b", "qwen/qwen3-32b",
                "meta-llama/llama-3.3-70b-instruct",
                "baidu/ernie-4.5-300b-a47b-paddle",
                "baichuan/baichuan-m2-32b",
            },
            .deepinfra => &.{
                "ByteDance/Seed-2.0-pro", "ByteDance/Seed-2.0-code",
                "ByteDance/Seed-2.0-mini",
                "deepseek-ai/DeepSeek-V4-Flash", "deepseek-ai/DeepSeek-V4-Pro",
                "deepseek-ai/DeepSeek-V3.2", "deepseek-ai/DeepSeek-R1-0528",
                "Qwen/Qwen3.8-2.4T-A95B", "Qwen/Qwen3.8-Max", "Qwen/Qwen3.8-27B",
                "Qwen/Qwen3.7-Max", "Qwen/Qwen3.6-35B-A3B", "Qwen/Qwen3.6-27B",
                "Qwen/Qwen3.5-397B-A17B", "Qwen/Qwen3.5-9B",
                "Qwen/Qwen3-Coder-480B-A35B-Instruct-Turbo",
                "Qwen/Qwen3-235B-A22B-Instruct-2507", "Qwen/Qwen3-32B",
                "Qwen/Qwen3-Max", "Qwen/Qwen3-Next-80B-A3B-Instruct",
                "moonshotai/Kimi-K3", "moonshotai/Kimi-K2.7-Code",
                "moonshotai/Kimi-K2.6", "moonshotai/Kimi-K2.5",
                "MiniMaxAI/MiniMax-M3", "MiniMaxAI/MiniMax-M2.7",
                "zai-org/GLM-5.2", "zai-org/GLM-5.1", "zai-org/GLM-5",
                "zai-org/GLM-4.7", "zai-org/GLM-4.7-Flash",
                "thinkingmachines/Inkling", "thinkingmachines/Inkling-Small",
                "XiaomiMiMo/MiMo-V2.5-Pro", "XiaomiMiMo/MiMo-V2.5",
                "meta-llama/Llama-3.3-70B-Instruct-Turbo",
                "meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8",
                "meta-llama/Llama-4-Scout-17B-16E-Instruct",
                "openai/gpt-oss-120b", "openai/gpt-oss-20b",
                "stepfun-ai/Step-3.7-Flash", "tencent/Hy3",
            },
            .nebius => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "deepseek-ai/DeepSeek-V4-Pro",
                "moonshotai/Kimi-K3", "moonshotai/Kimi-K2.7-Code",
                "MiniMaxAI/MiniMax-M3", "MiniMaxAI/MiniMax-M2.5",
                "Qwen/Qwen3.5-397B-A17B", "Qwen/Qwen3-235B-A22B-Instruct-2507",
                "Qwen/Qwen3-32B", "Qwen/Qwen3-Next-80B-A3B-Thinking",
                "zai-org/GLM-5.2", "NousResearch/Hermes-4-405B",
                "meta-llama/Llama-3.3-70B-Instruct",
                "nvidia/Llama-3_1-Nemotron-Ultra-253B-v1",
                "openai/gpt-oss-120b",
            },
            .baseten => &.{
                "openai/gpt-oss-120b", "openai/gpt-oss-20b",
                "Qwen/Qwen3-Coder-480B-A35B-Instruct",
                "deepseek-ai/DeepSeek-V3.2",
            },
            .hyperbolic => &.{
                "meta-llama/Meta-Llama-3.1-405B-Instruct",
                "meta-llama/Meta-Llama-3.1-70B-Instruct",
                "Qwen/Qwen2.5-72B-Instruct", "deepseek-ai/DeepSeek-V3",
                "Qwen/Qwen2.5-Coder-32B-Instruct",
            },
            .sambanova => &.{
                "Meta-Llama-3.1-405B-Instruct", "Meta-Llama-3.1-70B-Instruct",
                "Meta-Llama-3.1-8B-Instruct", "DeepSeek-V3",
                "Qwen2.5-72B-Instruct", "Qwen2.5-Coder-32B-Instruct",
            },
            .parasail => &.{
                "openai/gpt-oss-120b", "openai/gpt-oss-20b",
                "meta-llama/Llama-3.3-70B-Instruct",
            },
            .runinfra => &.{"qwen3.8-27b", "qwen3.8-2.4t-a95b"},
            .gmicloud => &.{"qwen3.8-2.4t-a95b", "qwen3.8-27b"},
            .modal => &.{"openai/gpt-oss-120b"},
            .crusoe => &.{"zai/glm-5.2"},
            .digitalocean => &.{
                "deepseek/deepseek-v4-flash", "moonshotai/kimi-k3",
            },
            .friendli => &.{"google/gemma-4-31b-it"},
            .wafer => &.{
                "deepseek/deepseek-v4-flash", "zai/glm-5.2",
            },
            .streamlake => &.{
                "kwaipilot/kat-coder-pro-v2.5", "kwaipilot/kat-coder-air-v2.5",
            },
            .nvidia => &.{
                "deepseek-ai/deepseek-v4-flash", "deepseek-ai/deepseek-v4-pro",
                "google/gemma-4-31b-it", "google/gemma-3n-e4b-it",
                "bytedance/seed-oss-36b-instruct",
                "meta/llama-3.1-405b-instruct", "meta/llama-3.1-70b-instruct",
                "meta/llama-3.1-8b-instruct",
                "qwen/qwen3.8-2.4t-a95b", "qwen/qwen3.7-max",
                "qwen/qwen3-coder-480b-a35b-instruct",
                "zai-org/glm-5.2", "zai-org/glm-4.7-flash",
                "moonshotai/kimi-k3", "moonshotai/kimi-k2.7-code",
            },
            .databricks => &.{
                "databricks-claude-haiku-4-5", "databricks-claude-sonnet-4-5",
                "databricks-claude-opus-4-5", "databricks-claude-opus-4-6",
                "databricks-gpt-5", "databricks-gpt-5-mini", "databricks-gpt-5-nano",
                "databricks-gpt-5.4", "databricks-gpt-5.4-mini", "databricks-gpt-5.4-nano",
                "databricks-gpt-5.5", "databricks-gpt-5.6-luna",
                "databricks-gpt-5.6-sol", "databricks-gpt-5.6-terra",
                "databricks-gpt-oss-120b", "databricks-gpt-oss-20b",
                "databricks-kimi-k2-7-code", "databricks-glm-5-2",
                "databricks-gemini-3-flash", "databricks-gemini-3-1-pro",
            },
            .cloudflare => &.{
                "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
                "@cf/meta/llama-3.1-8b-instruct-fp8",
                "@cf/meta/llama-3.2-3b-instruct",
                "@cf/meta/llama-4-scout-17b-16e-instruct",
                "@cf/deepseek-ai/deepseek-v4-flash-0731",
                "@cf/deepseek-ai/deepseek-v4-pro-0813",
                "@cf/openai/gpt-oss-120b", "@cf/openai/gpt-oss-20b",
                "@cf/qwen/qwen3-30b-a3b-fp8", "@cf/qwen/qwen3.8-27b",
                "@cf/qwen/qwq-32b", "@cf/qwen/qwen2.5-coder-32b-instruct",
                "@cf/zai-org/glm-5.2", "@cf/zai-org/glm-4.7-flash",
                "@cf/moonshotai/kimi-k2.6", "@cf/moonshotai/kimi-k2.7-code",
                "@cf/mistralai/mistral-small-3.1-24b-instruct",
                "@cf/nvidia/nemotron-3-120b-a12b",
            },
            .ovhcloud => &.{
                "gpt-oss-120b", "gpt-oss-20b",
                "meta-llama-3_3-70b-instruct",
                "mistral-small-3.2-24b-instruct-2506",
                "qwen3-coder-30b-a3b-instruct", "qwen3.5-397b-a17b",
                "qwen3.5-9b", "qwen3.6-27b",
            },
            .scaleway => &.{
                "llama-3.3-70b-instruct", "gpt-oss-120b",
                "mistral-small-3.2-24b-instruct-2506",
                "qwen3-coder-30b-a3b-instruct",
                "deepseek-v4-flash-0731", "glm-5.2",
                "qwen3-235b-a22b-instruct-2507", "qwen3.5-397b-a17b",
                "gemma-4-26b-a4b-it", "mistral-medium-3.5-128b",
            },
            .vultr => &.{
                "MiniMaxAI/MiniMax-M2.7", "moonshotai/Kimi-K2.6",
                "Qwen/Qwen3.5-397B-A17B", "Qwen/Qwen3.6-27B",
                "deepseek-ai/DeepSeek-V4-Flash",
                "nvidia/Nemotron-Cascade-2-30B-A3B",
                "XiaomiMiMo/MiMo-V2.5-Pro", "zai-org/GLM-5.2-FP8",
            },
            .hetzner => &.{
                "meta-llama/Llama-3.3-70B-Instruct",
                "meta-llama/Meta-Llama-3.1-8B-Instruct",
                "Qwen/Qwen3-32B", "deepseek-ai/DeepSeek-V3.2",
                "openai/gpt-oss-120b", "openai/gpt-oss-20b",
            },
            .infomaniak => &.{
                "meta-llama/Llama-3.3-70B-Instruct",
                "mistralai/Mistral-7B-Instruct-v0.3",
                "Qwen/Qwen3-32B", "openai/gpt-oss-120b",
            },
            .stackit => &.{
                "meta-llama/Llama-3.3-70B-Instruct",
                "mistralai/Mistral-7B-Instruct-v0.3",
                "Qwen/Qwen3-32B", "openai/gpt-oss-120b",
            },
            .ebcloud => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3-32B",
                "meta-llama/Llama-3.3-70B-Instruct",
                "openai/gpt-oss-120b", "zai-org/GLM-4.7",
            },
            .cloudferro => &.{
                "meta-llama/Llama-3.3-70B-Instruct",
                "mistralai/Mistral-7B-Instruct-v0.3",
                "Qwen/Qwen3-32B", "openai/gpt-oss-120b",
            },
            .hpc_ai => &.{
                "deepseek-ai/DeepSeek-V3.2", "deepseek-ai/DeepSeek-R1",
                "Qwen/Qwen3-235B-A22B-Instruct-2507", "Qwen/Qwen3-32B",
                "meta-llama/Llama-3.3-70B-Instruct",
            },
            .io_net => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "moonshotai/Kimi-K2.6", "openai/gpt-oss-120b",
            },
            .jalapeno => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .kosmik => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .evroc => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3-32B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .inferx => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "moonshotai/Kimi-K2.6", "openai/gpt-oss-120b",
            },
            .tensorx => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "openai/gpt-oss-120b",
            },
            .mixlayer => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-27B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .modelis => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .nova => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "Qwen/Qwen3.6-27B", "openai/gpt-oss-120b",
            },
            .pioneer => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .opper => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.32B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .tinfoil => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.32B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .vivgrid => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .umans_ai => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .neuralwatt => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .privatemode => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.32B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .regolo => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.32B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .scx_ai => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .submodel => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "Qwen/Qwen3.6-27B", "openai/gpt-oss-120b",
            },
            .synthetic => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .moark => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .lilac => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "Qwen/Qwen3.6-27B", "openai/gpt-oss-120b",
            },
            .longcat => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .thegrid => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .zenifra => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .zeldoc => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .coralbricks => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .kenari => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .dinference => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .echo => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .ofoo => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .qihang => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "Qwen/Qwen3.6-27B", "openai/gpt-oss-120b",
            },
            .qiniu => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .bailing => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "Qwen/Qwen3.6-27B", "openai/gpt-oss-120b",
            },
            .daoxe => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .d_run => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "Qwen/Qwen3.6-27B", "openai/gpt-oss-120b",
            },
            .kuae => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "Qwen/Qwen3.6-27B", "openai/gpt-oss-120b",
            },
            .scnet => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "Qwen/Qwen3.6-27B", "openai/gpt-oss-120b",
            },
            .berget => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .helicone => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .cortecs => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .chutes => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "moonshotai/Kimi-K2.6", "openai/gpt-oss-120b",
            },
            .fastrouter => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .greenpt => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .crofai => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .frogbot => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .impossibl => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .inceptron => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .inference => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .ambient => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .free_model => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "Qwen/Qwen3.6-27B", "openai/gpt-oss-120b",
            },
            .nano_gpt => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
                "grok-4.6", "grok-4.5", "deepseek-v4-flash",
            },
            .nearai => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .orcarouter => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .routing_run => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .unorouter => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .trustedrouter => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .zenmux => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .llmtr => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .llm_gateway => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .devpass => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .kilo => &.{
                "kilo/aion-labs/aion-3.0",
                "kilo/allenai/olmo-3-32b-think",
                "kilo/google/gemini-flash-latest",
                "kilo/deepseek/deepseek-v4-flash-latest",
                "kilo/z-ai/glm-latest",
            },
            .jiekou => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .modelscope => &.{
                "Qwen/Qwen3-Coder-480B-A35B-Instruct",
                "Qwen/Qwen3-235B-A22B-Instruct-2507",
                "Qwen/Qwen3-32B", "deepseek-ai/DeepSeek-V3.2",
                "zai-org/GLM-5.2",
            },
            .kimi_coding => &.{
                "kimi-k2.7-code", "kimi-k2.6", "kimi-k2.5", "kimi-k3",
            },
            .opencode_zen => &.{
                "opencode/gpt-5.6", "opencode/gpt-5.5", "opencode/gpt-5.4",
                "opencode/claude-sonnet-5", "opencode/claude-opus-5",
                "opencode/gemini-3.7-flash", "opencode/gemini-3.5-flash",
                "opencode/glm-5.2", "opencode/deepseek-v4-flash",
                "opencode/kimi-k3", "opencode/minimax-m3",
            },
            .opencode_go => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .requesty => &.{
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "gemini-3.7-flash", "gemini-3.5-flash",
                "deepseek-v4-flash", "grok-4.6", "qwen3-coder",
            },
            .chutes_ai => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .clinepass => &.{
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gpt-5.6", "gpt-5.5", "deepseek-v4-flash", "qwen3-coder",
            },
            .atomic_chat => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
            },
            .auriko => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
            },
            .claudinio => &.{
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gpt-5.6", "gpt-5.5",
            },
            .charm_hyper => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .blue_claw => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .crofai_alt => &.{
                "deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3.5-397B-A17B",
                "meta-llama/Llama-3.3-70B-Instruct", "openai/gpt-oss-120b",
            },
            .crossmodel => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .abacus => &.{
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "claude-fable-5", "gpt-5.6", "gpt-5.5", "gpt-5.4",
                "deepseek-ai/DeepSeek-V4-Flash", "MiniMaxAI/MiniMax-M3",
                "moonshotai/Kimi-K2.7-Code",
            },
            .ai_302 => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano",
                "gpt-5.2", "gpt-5.1", "gpt-5", "gpt-5-mini", "gpt-5-nano",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "claude-fable-5", "gemini-3-pro-preview", "gemini-3-flash-preview",
                "gemini-2.5-pro", "gemini-2.5-flash",
                "glm-5", "glm-5.1", "glm-4.7", "glm-4.6",
                "grok-4.1", "grok-4-fast-reasoning",
                "deepseek-v3.2", "deepseek-chat", "deepseek-reasoner",
                "kimi-k2-thinking", "kimi-k2-thinking-turbo",
                "MiniMax-M2", "MiniMax-M2.7", "MiniMax-M3",
                "qwen3-235b-a22b-instruct-2507", "qwen3-coder-480b-a35b-instruct",
                "mistral-large-2512", "mistral-small-latest",
            },
            .ai_router => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
                "deepseek-v4-flash", "grok-4.6", "qwen3-coder",
            },
            .aiand => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
                "deepseek-v4-flash", "grok-4.6", "qwen3-coder",
            },
            .aki_io => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
                "deepseek-v4-flash", "grok-4.6", "qwen3-coder",
            },
            .anyapi => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
                "deepseek-v4-flash", "grok-4.6", "qwen3-coder",
            },
            .edenai => &.{
                "anthropic/claude-opus-5", "anthropic/claude-sonnet-5",
                "anthropic/claude-haiku-4-5",
                "openai/gpt-5.6", "openai/gpt-5.5", "openai/gpt-5.4",
                "google/gemini-3.7-flash", "google/gemini-3.5-flash",
                "amazon/moonshot.kimi-k2-thinking",
                "deepseek/deepseek-v4-flash", "deepseek/deepseek-v4-pro",
            },
            .empiriolabs => &.{
                "deepseek-v4-flash", "deepseek-v4-pro",
                "qwen3-coder-480b-a35b-instruct",
            },
            .cn_line_pass => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
                "deepseek-v4-flash", "grok-4.6", "qwen3-coder",
            },
            .cline_pass => &.{
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gpt-5.6", "gpt-5.5", "deepseek-v4-flash", "qwen3-coder",
            },
            .frogbot_alt => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .model_oracle => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
                "deepseek-v4-flash", "grok-4.6", "qwen3-coder",
            },
            .xpersona => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
                "deepseek-v4-flash", "grok-4.6", "qwen3-coder",
            },
            .lucidquery => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
                "deepseek-v4-flash", "grok-4.6", "qwen3-coder",
            },
            .lynkr => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
                "deepseek-v4-flash", "grok-4.6", "qwen3-coder",
            },
            .meganova => &.{
                "gpt-5.6", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
                "claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5",
                "gemini-3.7-flash", "gemini-3.5-flash",
                "deepseek-v4-flash", "grok-4.6", "qwen3-coder",
            },
            .sarvam => &.{
                "sarvam-1", "sarvam-2b",
            },
            .tencent => &.{
                "hunyuan-pro", "hunyuan-standard",
                "hunyuan-lite", "hunyuan-turbos",
            },
            .tencent_token => &.{
                "hunyuan-pro", "hunyuan-standard",
            },
            .tencent_tokenhub => &.{
                "hunyuan-pro", "hunyuan-standard",
            },
            .tencent_coding => &.{
                "hunyuan-pro", "hunyuan-standard",
            },
            .stepfun => &.{
                "step-3.7-flash", "step-3.5-flash",
                "step-2-flash", "step-2-mini",
            },
            .stepfun_ai => &.{
                "step-3.7-flash", "step-3.5-flash",
                "step-2-flash", "step-2-mini",
            },
            .stepfun_step => &.{
                "step-3.7-flash", "step-3.5-flash",
            },
            .stepfun_ai_step => &.{
                "step-3.7-flash", "step-3.5-flash",
            },
            .alibaba => &.{
                "qwen3.8-2.4t-a95b", "qwen3.8-max", "qwen3.8-27b",
                "qwen3.7-max", "qwen3.6-plus", "qwen3.6-27b",
                "qwen3.5-397b-a17b", "qwen3.5-9b",
                "qwen3-coder-480b-a35b-instruct", "qwen3-coder-plus",
                "qwen3-235b-a22b-instruct-2507", "qwen3-32b",
                "qwen-plus", "qwen-turbo", "qwen-max",
                "deepseek-v3.2", "deepseek-r1",
            },
            .alibaba_cn => &.{
                "qwen3.8-2.4t-a95b", "qwen3.8-max", "qwen3.8-27b",
                "qwen3.7-max", "qwen3.6-plus", "qwen3.6-27b",
                "qwen3.5-397b-a17b", "qwen3.5-9b",
                "qwen3-coder-480b-a35b-instruct", "qwen3-coder-plus",
                "qwen3-235b-a22b-instruct-2507", "qwen3-32b",
                "qwen-plus", "qwen-turbo", "qwen-max",
            },
            .alibaba_coding => &.{
                "qwen3-coder-480b-a35b-instruct", "qwen3-coder-plus",
                "qwen3-coder-30b-a3b-instruct",
            },
            .alibaba_coding_cn => &.{
                "qwen3-coder-480b-a35b-instruct", "qwen3-coder-plus",
                "qwen3-coder-30b-a3b-instruct",
            },
            .alibaba_token => &.{
                "qwen3.8-2.4t-a95b", "qwen3.7-max", "qwen3.6-plus",
                "qwen-plus", "qwen-turbo", "qwen-max",
            },
            .alibaba_token_cn => &.{
                "qwen3.8-2.4t-a95b", "qwen3.7-max", "qwen3.6-plus",
                "qwen-plus", "qwen-turbo", "qwen-max",
            },
            .moonshot => &.{
                "kimi-k3", "kimi-k2.7-code", "kimi-k2.6", "kimi-k2.5",
                "moonshot-v1-128k", "moonshot-v1-32k", "moonshot-v1-8k",
            },
            .moonshot_cn => &.{
                "kimi-k3", "kimi-k2.7-code", "kimi-k2.6", "kimi-k2.5",
                "moonshot-v1-128k", "moonshot-v1-32k", "moonshot-v1-8k",
            },
            .zhipu => &.{
                "glm-5.2", "glm-5.1", "glm-5", "glm-4.7", "glm-4.7-flash",
                "glm-4.6", "glm-4.5-air", "glm-4-plus", "glm-4-flash",
            },
            .zhipu_coding => &.{
                "glm-5.2", "glm-5.1", "glm-5",
                "glm-4.7", "glm-4.7-flash",
            },
            .zai => &.{
                "glm-5.2-fast", "glm-5.2", "glm-5.1", "glm-5",
                "glm-4.7", "glm-4.7-flash", "glm-4.6", "glm-4.5-air",
                "glm-5v-turbo",
            },
            .zai_coding => &.{
                "glm-5.2", "glm-5.1", "glm-5",
                "glm-4.7", "glm-4.7-flash",
            },
            .minimax => &.{
                "minimax-m3", "minimax-m2.7", "minimax-m2.5",
                "minimax-m2.1", "minimax-m2",
            },
            .minimax_cn => &.{
                "minimax-m3", "minimax-m2.7", "minimax-m2.5",
                "minimax-m2.1", "minimax-m2",
            },
            .minimax_coding => &.{
                "minimax-m3", "minimax-m2.7",
            },
            .minimax_cn_coding => &.{
                "minimax-m3", "minimax-m2.7",
            },
            .bytedance => &.{
                "doubao-seed-1-8-251215", "doubao-seed-1-6-thinking-250715",
                "doubao-seed-1-6-vision-250815",
                "doubao-seed-code-preview-251028",
                "deepseek-v3.2", "deepseek-r1",
            },
            .xiaomi => &.{
                "mimo-v2.5-pro", "mimo-v2.5",
            },
            .xiaomi_token_cn => &.{
                "mimo-v2.5-pro", "mimo-v2.5",
            },
            .xiaomi_token_ams => &.{
                "mimo-v2.5-pro", "mimo-v2.5",
            },
            .xiaomi_token_sgp => &.{
                "mimo-v2.5-pro", "mimo-v2.5",
            },
            .sakana => &.{"fugu-ultra", "namazu"},
            .arcee => &.{"trinity-large-thinking", "trinity-mini"},
            .morph => &.{"morph-v3-fast", "morph-v3-large"},
            .inception => &.{"mercury-2", "mercury-coder-small"},
            .poolside => &.{"laguna-s-2.1", "laguna-s-2.1-free"},
            .thinkingmachines => &.{"inkling", "inkling-small"},
            .kwaipilot => &.{
                "kat-coder-pro-v2.5", "kat-coder-pro-v2",
                "kat-coder-air-v2.5",
            },
            .llama => &.{
                "Llama-3.3-70B-Instruct", "Llama-3.1-405B-Instruct",
                "Llama-3.1-70B-Instruct", "Llama-3.1-8B-Instruct",
            },
            .amd => &.{"amd-llama-3.3-70b"},
            .upstage => &.{
                "solar-mini", "solar-pro2", "solar-pro3", "solar-pro4",
            },
            .silocloud => &.{
                "meta-llama/Llama-3.3-70B-Instruct",
                "Qwen/Qwen2.5-72B-Instruct",
            },
            .siliconflow => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "deepseek-ai/DeepSeek-V4-Pro",
                "deepseek-ai/DeepSeek-V3.2", "deepseek-ai/DeepSeek-R1",
                "zai-org/GLM-5.2", "zai-org/GLM-5.1", "zai-org/GLM-5",
                "zai-org/GLM-5V-Turbo", "zai-org/GLM-4.5-Air",
                "Qwen/Qwen3.6-35B-A3B", "Qwen/Qwen3.6-27B",
                "Qwen/Qwen3.5-397B-A17B", "Qwen/Qwen3.5-9B",
                "Qwen/Qwen3-Coder-480B-A35B-Instruct",
                "Qwen/Qwen3-Coder-30B-A3B-Instruct",
                "Qwen/Qwen3-VL-235B-A22B-Instruct",
                "Qwen/Qwen3-235B-A22B-Thinking-2507",
                "MiniMaxAI/MiniMax-M2.5", "moonshotai/Kimi-K2.6",
                "openai/gpt-oss-120b", "openai/gpt-oss-20b",
                "stepfun-ai/Step-3.5-Flash",
                "tencent/Hunyuan-A13B-Instruct", "tencent/Hy3-preview",
            },
            .siliconflow_cn => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "deepseek-ai/DeepSeek-V4-Pro",
                "deepseek-ai/DeepSeek-V3.2", "deepseek-ai/DeepSeek-R1",
                "zai-org/GLM-5.2", "zai-org/GLM-5.1", "zai-org/GLM-5",
                "Qwen/Qwen3-Coder-480B-A35B-Instruct",
                "Qwen/Qwen3-235B-A22B-Thinking-2507",
                "MiniMaxAI/MiniMax-M2.5", "moonshotai/Kimi-K2.6",
                "openai/gpt-oss-120b", "openai/gpt-oss-20b",
            },
            .snowflake => &.{
                "claude-fable-5", "claude-opus-5", "claude-opus-4-8",
                "claude-opus-4-7", "claude-opus-4-6", "claude-opus-4-5",
                "claude-sonnet-5", "claude-sonnet-4-6", "claude-haiku-4-5",
                "openai-gpt-5.5", "openai-gpt-5.4", "openai-gpt-5.2",
                "openai-gpt-5.1", "openai-gpt-5", "openai-gpt-5-mini",
                "openai-gpt-5-nano", "openai-gpt-5.6-luna",
                "openai-gpt-5.6-sol", "openai-gpt-5.6-terra",
                "gemini-3.1-pro", "deepseek-r1", "mistral-large2",
                "snowflake-llama3.3-70b",
            },
            .weights_biases => &.{
                "deepseek-ai/DeepSeek-V4-Flash", "Qwen/Qwen3.8-2.4T-A95B",
                "Qwen/Qwen3.8-27B", "MiniMaxAI/MiniMax-M3",
                "zai-org/GLM-5.2", "openai/gpt-oss-120b",
            },
            .ollama_cloud => &.{
                "llama3.3", "qwen2.5", "deepseek-r1",
                "qwen3-coder", "gpt-oss-120b",
            },
            .lmstudio => &.{
                "openai/gpt-oss-20b", "qwen/qwen3-30b-a3b-2507",
                "qwen/qwen3-coder-30b",
            },
            .codex => &.{"codex-mini-latest"},
            .ollama => &.{
                "llama3.2", "llama3.1", "qwen2.5",
                "mistral", "phi3", "gemma2", "deepseek-r1",
            },
        };
    }

    pub fn usesAnthropicFormat(self: Provider) bool {
        return self == .anthropic;
    }

    /// Maps each provider to its ID in the models.dev registry
    /// (https://models.dev/api.json). Returns null for providers not in the
    /// registry (local providers like ollama, lmstudio, codex).
    pub fn registryId(self: Provider) ?[]const u8 {
        return switch (self) {
            .openai => "openai",
            .anthropic => "anthropic",
            .google => "google",
            .grok => "xai",
            .mistral => "mistral",
            .cohere => "cohere",
            .deepseek => "deepseek",
            .openrouter => "openrouter",
            .together => "togetherai",
            .fireworks => "fireworks-ai",
            .groq => "groq",
            .cerebras => "cerebras",
            .novita => "novita-ai",
            .deepinfra => "deepinfra",
            .nebius => "nebius",
            .baseten => "baseten",
            .hyperbolic => "hyper",
            .sambanova => null, // not in registry
            .parasail => null,
            .runinfra => "runinfra",
            .gmicloud => "gmicloud",
            .modal => "modal",
            .crusoe => "crusoe",
            .digitalocean => "digitalocean",
            .friendli => "friendli",
            .wafer => "wafer.ai",
            .streamlake => null,
            .nvidia => "nvidia",
            .databricks => "databricks",
            .cloudflare => "cloudflare-workers-ai",
            .ovhcloud => "ovhcloud",
            .scaleway => "scaleway",
            .vultr => "vultr",
            .hetzner => "hetzner",
            .infomaniak => "infomaniak",
            .stackit => "stackit",
            .ebcloud => "ebcloud",
            .cloudferro => "cloudferro-sherlock",
            .hpc_ai => "hpc-ai",
            .io_net => "io-net",
            .jalapeno => "jalapeno",
            .kosmik => "kosmik",
            .evroc => "evroc",
            .inferx => "inferx",
            .tensorx => "tensorx",
            .mixlayer => "mixlayer",
            .modelis => "modelis",
            .nova => "nova",
            .pioneer => "pioneer",
            .opper => "opper",
            .tinfoil => "tinfoil",
            .vivgrid => "vivgrid",
            .umans_ai => "umans-ai",
            .neuralwatt => "neuralwatt",
            .privatemode => "privatemode-ai",
            .regolo => "regolo-ai",
            .scx_ai => "scx-ai",
            .submodel => "submodel",
            .synthetic => "synthetic",
            .moark => "moark",
            .lilac => "lilac",
            .longcat => "longcat",
            .thegrid => "the-grid-ai",
            .zenifra => "zenifra",
            .zeldoc => "zeldoc",
            .coralbricks => "coralbricks",
            .kenari => "kenari",
            .dinference => "dinference",
            .echo => "echo",
            .ofoo => "ofox",
            .qihang => "qihang-ai",
            .qiniu => "qiniu-ai",
            .bailing => "bailing",
            .daoxe => "daoxe",
            .d_run => "drun",
            .kuae => "kuae-cloud-coding-plan",
            .scnet => "scnet-token-plan",
            .berget => "berget",
            .helicone => "helicone",
            .cortecs => "cortecs",
            .chutes => "chutes",
            .fastrouter => "fastrouter",
            .greenpt => "greenpt",
            .crofai => "crof",
            .frogbot => "frogbot",
            .impossibl => "impossibl",
            .inceptron => "inceptron",
            .inference => "inference",
            .ambient => "ambient",
            .free_model => "freemodel",
            .nano_gpt => "nano-gpt",
            .nearai => "nearai",
            .orcarouter => "orcarouter",
            .routing_run => "routing-run",
            .unorouter => "unorouter",
            .trustedrouter => "trustedrouter",
            .zenmux => "zenmux",
            .llmtr => "llmtr",
            .llm_gateway => "llmgateway",
            .devpass => null,
            .kilo => "kilo",
            .jiekou => "jiekou",
            .modelscope => "modelscope",
            .kimi_coding => "kimi-for-coding",
            .opencode_zen => "opencode",
            .opencode_go => "opencode-go",
            .requesty => "requesty",
            .chutes_ai => "chutes",
            .clinepass => "cline-pass",
            .atomic_chat => "atomic-chat",
            .auriko => "auriko",
            .claudinio => "claudinio",
            .charm_hyper => "hyper",
            .blue_claw => "blueclaw",
            .crofai_alt => "crof",
            .crossmodel => "crossmodel",
            .abacus => "abacus",
            .ai_302 => "302ai",
            .ai_router => "ai-router",
            .aiand => "aiand",
            .aki_io => "aki-io",
            .anyapi => "anyapi",
            .edenai => "edenai",
            .empiriolabs => "empiriolabs",
            .cn_line_pass => null,
            .cline_pass => "cline-pass",
            .frogbot_alt => "frogbot",
            .model_oracle => "model-oracle-ai",
            .xpersona => "xpersona",
            .lucidquery => "lucidquery",
            .lynkr => "lynkr",
            .meganova => "meganova",
            .sarvam => "sarvam",
            .tencent => "tencent-token-plan",
            .tencent_token => "tencent-token-plan",
            .tencent_tokenhub => "tencent-tokenhub",
            .tencent_coding => "tencent-coding-plan",
            .stepfun => "stepfun",
            .stepfun_ai => "stepfun-ai",
            .stepfun_step => "stepfun-step-plan",
            .stepfun_ai_step => "stepfun-ai-step-plan",
            .alibaba => "alibaba",
            .alibaba_cn => "alibaba-cn",
            .alibaba_coding => "alibaba-coding-plan",
            .alibaba_coding_cn => "alibaba-coding-plan-cn",
            .alibaba_token => "alibaba-token-plan",
            .alibaba_token_cn => "alibaba-token-plan-cn",
            .moonshot => "moonshotai",
            .moonshot_cn => "moonshotai-cn",
            .zhipu => "zhipuai",
            .zhipu_coding => "zhipuai-coding-plan",
            .zai => "zai",
            .zai_coding => "zai-coding-plan",
            .minimax => "minimax",
            .minimax_cn => "minimax-cn",
            .minimax_coding => "minimax-coding-plan",
            .minimax_cn_coding => "minimax-cn-coding-plan",
            .bytedance => null, // uses Volc Engine, not in registry
            .xiaomi => "xiaomi",
            .xiaomi_token_cn => "xiaomi-token-plan-cn",
            .xiaomi_token_ams => "xiaomi-token-plan-ams",
            .xiaomi_token_sgp => "xiaomi-token-plan-sgp",
            .sakana => "sakana",
            .arcee => "arcee",
            .morph => "morph",
            .inception => "inception",
            .poolside => "poolside",
            .thinkingmachines => "thinkingmachines",
            .kwaipilot => null,
            .llama => "llama",
            .amd => "amd",
            .upstage => "upstage",
            .silocloud => null,
            .siliconflow => "siliconflow",
            .siliconflow_cn => "siliconflow-cn",
            .snowflake => "snowflake-cortex",
            .weights_biases => "wandb",
            .ollama_cloud => "ollama-cloud",
            .lmstudio => "lmstudio",
            .codex => null,
            .ollama => null,
        };
    }

    pub fn isLocal(self: Provider) bool {
        return self == .ollama or self == .lmstudio;
    }

    pub fn envKey(self: Provider) []const u8 {
        return switch (self) {
            .openai => "OPENAI_API_KEY",
            .anthropic => "ANTHROPIC_API_KEY",
            .google => "GOOGLE_API_KEY",
            .grok => "XAI_API_KEY",
            .mistral => "MISTRAL_API_KEY",
            .cohere => "COHERE_API_KEY",
            .deepseek => "DEEPSEEK_API_KEY",
            .openrouter => "OPENROUTER_API_KEY",
            .together => "TOGETHER_API_KEY",
            .fireworks => "FIREWORKS_API_KEY",
            .groq => "GROQ_API_KEY",
            .cerebras => "CEREBRAS_API_KEY",
            .novita => "NOVITA_API_KEY",
            .deepinfra => "DEEPINFRA_API_KEY",
            .nebius => "NEBIUS_API_KEY",
            .baseten => "BASETEN_API_KEY",
            .hyperbolic => "HYPERBOLIC_API_KEY",
            .sambanova => "SAMBANOVA_API_KEY",
            .parasail => "PARASAIL_API_KEY",
            .runinfra => "RUNINFRA_API_KEY",
            .gmicloud => "GMICLOUD_API_KEY",
            .modal => "MODAL_API_KEY",
            .crusoe => "CRUSOE_API_KEY",
            .digitalocean => "DIGITALOCEAN_API_KEY",
            .friendli => "FRIENDLI_API_KEY",
            .wafer => "WAFER_API_KEY",
            .streamlake => "STREAMLAKE_API_KEY",
            .nvidia => "NVIDIA_API_KEY",
            .databricks => "DATABRICKS_TOKEN",
            .cloudflare => "CLOUDFLARE_API_KEY",
            .ovhcloud => "OVHCLOUD_API_KEY",
            .scaleway => "SCALEWAY_API_KEY",
            .vultr => "VULTR_API_KEY",
            .hetzner => "HETZNER_API_KEY",
            .infomaniak => "INFOMANIAK_API_KEY",
            .stackit => "STACKIT_API_KEY",
            .ebcloud => "EBCLOUD_API_KEY",
            .cloudferro => "CLOUDFERRO_API_KEY",
            .hpc_ai => "HPC_AI_API_KEY",
            .io_net => "IO_NET_API_KEY",
            .jalapeno => "JALAPENO_API_KEY",
            .kosmik => "KOSMIK_API_KEY",
            .evroc => "EVROC_API_KEY",
            .inferx => "INFERX_API_KEY",
            .tensorx => "TENSORX_API_KEY",
            .mixlayer => "MIXLAYER_API_KEY",
            .modelis => "MODELIS_API_KEY",
            .nova => "NOVA_API_KEY",
            .pioneer => "PIONEER_API_KEY",
            .opper => "OPPER_API_KEY",
            .tinfoil => "TINFOIL_API_KEY",
            .vivgrid => "VIVGRID_API_KEY",
            .umans_ai => "UMANS_AI_API_KEY",
            .neuralwatt => "NEURALWATT_API_KEY",
            .privatemode => "PRIVATEMODE_API_KEY",
            .regolo => "REGOLO_API_KEY",
            .scx_ai => "SCX_AI_API_KEY",
            .submodel => "SUBMODEL_API_KEY",
            .synthetic => "SYNTHETIC_API_KEY",
            .moark => "MOARK_API_KEY",
            .lilac => "LILAC_API_KEY",
            .longcat => "LONGCAT_API_KEY",
            .thegrid => "THEGRID_API_KEY",
            .zenifra => "ZENIFRA_API_KEY",
            .zeldoc => "ZELDOC_API_KEY",
            .coralbricks => "CORALBRICKS_API_KEY",
            .kenari => "KENARI_API_KEY",
            .dinference => "DINFERENCE_API_KEY",
            .echo => "ECHO_API_KEY",
            .ofoo => "OFOO_API_KEY",
            .qihang => "QIHANG_API_KEY",
            .qiniu => "QINIU_API_KEY",
            .bailing => "BAILING_API_KEY",
            .daoxe => "DAOXE_API_KEY",
            .d_run => "D_RUN_API_KEY",
            .kuae => "KUAE_API_KEY",
            .scnet => "SCNET_API_KEY",
            .berget => "BERGET_API_KEY",
            .helicone => "HELICONE_API_KEY",
            .cortecs => "CORTECS_API_KEY",
            .chutes => "CHUTES_API_KEY",
            .fastrouter => "FASTROUTER_API_KEY",
            .greenpt => "GREENPT_API_KEY",
            .crofai => "CROFAI_API_KEY",
            .frogbot => "FROGBOT_API_KEY",
            .impossibl => "IMPOSSIBL_API_KEY",
            .inceptron => "INCEPTRON_API_KEY",
            .inference => "INFERENCE_API_KEY",
            .ambient => "AMBIENT_API_KEY",
            .free_model => "FREEMODEL_API_KEY",
            .nano_gpt => "NANOGPT_API_KEY",
            .nearai => "NEARAI_API_KEY",
            .orcarouter => "ORCAROUTER_API_KEY",
            .routing_run => "ROUTING_RUN_API_KEY",
            .unorouter => "UNOROUTER_API_KEY",
            .trustedrouter => "TRUSTEDROUTER_API_KEY",
            .zenmux => "ZENMUX_API_KEY",
            .llmtr => "LLMTR_API_KEY",
            .llm_gateway => "LLMGATEWAY_API_KEY",
            .devpass => "DEVPASS_API_KEY",
            .kilo => "KILO_API_KEY",
            .jiekou => "JIEKOU_API_KEY",
            .modelscope => "MODELSCOPE_API_KEY",
            .kimi_coding => "KIMI_FOR_CODING_API_KEY",
            .opencode_zen => "OPENCODE_API_KEY",
            .opencode_go => "OPENCODE_GO_API_KEY",
            .requesty => "REQUESTY_API_KEY",
            .chutes_ai => "CHUTES_AI_API_KEY",
            .clinepass => "CLINEPASS_API_KEY",
            .atomic_chat => "ATOMIC_CHAT_API_KEY",
            .auriko => "AURIKO_API_KEY",
            .claudinio => "CLAUDINIO_API_KEY",
            .charm_hyper => "CHARM_HYPER_API_KEY",
            .blue_claw => "BLUE_CLAW_API_KEY",
            .crofai_alt => "CROFAI_ALT_API_KEY",
            .crossmodel => "CROSSMODEL_API_KEY",
            .abacus => "ABACUS_API_KEY",
            .ai_302 => "302AI_API_KEY",
            .ai_router => "AI_ROUTER_API_KEY",
            .aiand => "AIAND_API_KEY",
            .aki_io => "AKI_IO_API_KEY",
            .anyapi => "ANYAPI_API_KEY",
            .edenai => "EDENAI_API_KEY",
            .empiriolabs => "EMPIRIOLABS_API_KEY",
            .cn_line_pass => "CN_LINE_PASS_API_KEY",
            .cline_pass => "CLINE_PASS_API_KEY",
            .frogbot_alt => "FROGBOT_ALT_API_KEY",
            .model_oracle => "MODEL_ORACLE_API_KEY",
            .xpersona => "XPERSONA_API_KEY",
            .lucidquery => "LUCIDQUERY_API_KEY",
            .lynkr => "LYNKR_API_KEY",
            .meganova => "MEGANOVA_API_KEY",
            .sarvam => "SARVAM_API_KEY",
            .tencent => "TENCENT_CLOUD_API_KEY",
            .tencent_token => "TENCENT_TOKEN_API_KEY",
            .tencent_tokenhub => "TENCENT_TOKENHUB_API_KEY",
            .tencent_coding => "TENCENT_CODING_API_KEY",
            .stepfun => "STEPFUN_API_KEY",
            .stepfun_ai => "STEPFUN_AI_API_KEY",
            .stepfun_step => "STEPFUN_STEP_API_KEY",
            .stepfun_ai_step => "STEPFUN_AI_STEP_API_KEY",
            .alibaba => "DASHSCOPE_API_KEY",
            .alibaba_cn => "DASHSCOPE_API_KEY",
            .alibaba_coding => "DASHSCOPE_API_KEY",
            .alibaba_coding_cn => "DASHSCOPE_API_KEY",
            .alibaba_token => "DASHSCOPE_API_KEY",
            .alibaba_token_cn => "DASHSCOPE_API_KEY",
            .moonshot => "MOONSHOT_API_KEY",
            .moonshot_cn => "MOONSHOT_API_KEY",
            .zhipu => "ZHIPU_API_KEY",
            .zhipu_coding => "ZHIPU_API_KEY",
            .zai => "ZAI_API_KEY",
            .zai_coding => "ZAI_API_KEY",
            .minimax => "MINIMAX_API_KEY",
            .minimax_cn => "MINIMAX_API_KEY",
            .minimax_coding => "MINIMAX_API_KEY",
            .minimax_cn_coding => "MINIMAX_API_KEY",
            .bytedance => "ARK_API_KEY",
            .xiaomi => "XIAOMI_API_KEY",
            .xiaomi_token_cn => "XIAOMI_API_KEY",
            .xiaomi_token_ams => "XIAOMI_API_KEY",
            .xiaomi_token_sgp => "XIAOMI_API_KEY",
            .sakana => "SAKANA_API_KEY",
            .arcee => "ARCEE_API_KEY",
            .morph => "MORPH_API_KEY",
            .inception => "INCEPTION_API_KEY",
            .poolside => "POOLSIDE_API_KEY",
            .thinkingmachines => "THINKINGMACHINES_API_KEY",
            .kwaipilot => "KWAIILOT_API_KEY",
            .llama => "LLAMA_API_KEY",
            .amd => "AMD_API_KEY",
            .upstage => "UPSTAGE_API_KEY",
            .silocloud => "SILOCLOUD_API_KEY",
            .siliconflow => "SILICONFLOW_API_KEY",
            .siliconflow_cn => "SILICONFLOW_API_KEY",
            .snowflake => "SNOWFLAKE_CORTEX_PAT",
            .weights_biases => "WANDB_API_KEY",
            .ollama_cloud => "OLLAMA_CLOUD_API_KEY",
            .lmstudio => "LMSTUDIO_API_KEY",
            .codex => "OPENAI_API_KEY",
            .ollama => "OLLAMA_API_KEY",
        };
    }

    pub fn authHeaderName(self: Provider) []const u8 {
        return switch (self) {
            .anthropic => "x-api-key",
            else => "Authorization",
        };
    }

    pub fn authHeaderValue(self: Provider, key: []const u8) []const u8 {
        _ = self;
        return key;
    }

    pub fn all() []const Provider {
        return &.{
            .openai, .anthropic, .google, .grok, .mistral, .cohere, .deepseek,
            .openrouter, .together, .fireworks, .groq, .cerebras, .novita,
            .deepinfra, .nebius, .baseten, .hyperbolic, .sambanova, .parasail,
            .runinfra, .gmicloud, .modal, .crusoe, .digitalocean, .friendli,
            .wafer, .streamlake, .nvidia, .databricks, .cloudflare, .ovhcloud,
            .scaleway, .vultr, .hetzner, .infomaniak, .stackit, .ebcloud,
            .cloudferro, .hpc_ai, .io_net, .jalapeno, .kosmik, .evroc,
            .inferx, .tensorx, .mixlayer, .modelis, .nova, .pioneer,
            .opper, .tinfoil, .vivgrid, .umans_ai, .neuralwatt, .privatemode,
            .regolo, .scx_ai, .submodel, .synthetic, .moark, .lilac,
            .longcat, .thegrid, .zenifra, .zeldoc, .coralbricks, .kenari,
            .dinference, .echo, .ofoo, .qihang, .qiniu, .bailing, .daoxe,
            .d_run, .kuae, .scnet, .berget, .helicone, .cortecs, .chutes,
            .fastrouter, .greenpt, .crofai, .frogbot, .impossibl, .inceptron,
            .inference, .ambient, .free_model, .nano_gpt, .nearai,
            .orcarouter, .routing_run, .unorouter, .trustedrouter, .zenmux,
            .llmtr, .llm_gateway, .devpass, .kilo, .jiekou, .modelscope,
            .kimi_coding, .opencode_zen, .opencode_go, .requesty, .chutes_ai,
            .clinepass, .atomic_chat, .auriko, .claudinio, .charm_hyper,
            .blue_claw, .crofai_alt, .crossmodel, .abacus, .ai_302,
            .ai_router, .aiand, .aki_io, .anyapi, .edenai, .empiriolabs,
            .cn_line_pass, .cline_pass, .frogbot_alt, .model_oracle,
            .xpersona, .lucidquery, .lynkr, .meganova, .sarvam,
            .tencent, .tencent_token, .tencent_tokenhub, .tencent_coding,
            .stepfun, .stepfun_ai, .stepfun_step, .stepfun_ai_step,
            .alibaba, .alibaba_cn, .alibaba_coding, .alibaba_coding_cn,
            .alibaba_token, .alibaba_token_cn,
            .moonshot, .moonshot_cn,
            .zhipu, .zhipu_coding, .zai, .zai_coding,
            .minimax, .minimax_cn, .minimax_coding, .minimax_cn_coding,
            .bytedance,
            .xiaomi, .xiaomi_token_cn, .xiaomi_token_ams, .xiaomi_token_sgp,
            .sakana, .arcee, .morph, .inception, .poolside,
            .thinkingmachines, .kwaipilot, .llama, .amd, .upstage,
            .silocloud, .siliconflow, .siliconflow_cn, .snowflake,
            .weights_biases, .ollama_cloud, .lmstudio,
            .codex, .ollama,
        };
    }
};

/// Helper used by parse() — returns the input if it case-insensitively
/// matches `target`. Exists so we can use a single eqlIgnoreCase call
/// without repeating the value name.
fn stdasciiParseHelper(value: []const u8, target: []const u8) ?void {
    if (std.ascii.eqlIgnoreCase(value, target)) return {};
    return null;
}

test "provider parse round-trip" {
    try std.testing.expectEqual(Provider.openai, Provider.parse("openai").?);
    try std.testing.expectEqual(Provider.grok, Provider.parse("grok").?);
    try std.testing.expectEqual(Provider.google, Provider.parse("gemini").?);
    try std.testing.expectEqual(Provider.cohere, Provider.parse("cohere").?);
    try std.testing.expectEqual(Provider.fireworks, Provider.parse("fireworks").?);
    try std.testing.expectEqual(Provider.zhipu, Provider.parse("glm").?);
    try std.testing.expectEqual(Provider.moonshot, Provider.parse("kimi").?);
    try std.testing.expectEqual(Provider.alibaba, Provider.parse("dashscope").?);
    try std.testing.expectEqual(Provider.bytedance, Provider.parse("volcengine").?);
    try std.testing.expectEqual(Provider.sambanova, Provider.parse("sambanova").?);
    try std.testing.expectEqual(Provider.nvidia, Provider.parse("nvidia").?);
    try std.testing.expectEqual(Provider.siliconflow, Provider.parse("siliconflow").?);
    try std.testing.expectEqual(Provider.snowflake, Provider.parse("snowflake").?);
    try std.testing.expectEqual(Provider.requesty, Provider.parse("requesty").?);
    try std.testing.expectEqual(Provider.kilo, Provider.parse("kilo").?);
    try std.testing.expectEqual(Provider.abacus, Provider.parse("abacus").?);
    try std.testing.expectEqual(Provider.edenai, Provider.parse("edenai").?);
    try std.testing.expectEqual(Provider.cloudflare, Provider.parse("cloudflare").?);
    try std.testing.expectEqual(Provider.databricks, Provider.parse("databricks").?);
    try std.testing.expect(Provider.parse("unknown") == null);
}

test "provider all has expected count" {
    try std.testing.expectEqual(@as(usize, 181), Provider.all().len);
}

test "provider models non-empty" {
    for (Provider.all()) |p| {
        try std.testing.expect(p.models().len > 0);
        try std.testing.expect(p.defaultModel().len > 0);
    }
}

test "provider slug unique" {
    // Verify all slugs are unique
    var seen: [256][]const u8 = undefined;
    var seen_count: usize = 0;
    outer: for (Provider.all()) |p| {
        const s = p.slug();
        for (seen[0..seen_count]) |existing| {
            if (std.mem.eql(u8, s, existing)) {
                break :outer;
            }
        }
        seen[seen_count] = s;
        seen_count += 1;
    }
    try std.testing.expectEqual(Provider.all().len, seen_count);
}

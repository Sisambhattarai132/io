const std = @import("std");
const provider = @import("provider.zig");
const config_mod = @import("config.zig");
const session = @import("session.zig");
const chat = @import("chat.zig");
const setup = @import("setup.zig");
const registry = @import("registry.zig");

pub const version = "0.1.0";

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;
    const environ = init.environ_map;

    var config_mgr: config_mod.ConfigManager = .{};
    config_mgr.load(gpa, environ);
    defer config_mgr.deinit(gpa);
    try config_mgr.ensureDataDir(io);

    // Load saved config from disk (env vars still override at load() time above,
    // but this fills fields left at their defaults).
    config_mgr.loadFile(gpa, io);

    // First-run: if no config file exists yet, run interactive setup before
    // proceeding (unless the user explicitly asked for a non-interactive
    // subcommand like --help/--version/providers, handled below).
    const has_config_file = blk: {
        const path = std.fmt.allocPrint(gpa, "{s}/config", .{config_mgr.config.data_dir}) catch break :blk false;
        defer gpa.free(path);
        _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch break :blk false;
        break :blk true;
    };

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();

    _ = args.next(); // skip program name

    var subcommand: Subcommand = .chat;
    var prompt_parts: std.ArrayList([]const u8) = .empty;
    defer prompt_parts.deinit(gpa);
    var resume_id: ?i64 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp(io);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            const stdout = std.Io.File.stdout();
            var bw: [128]u8 = undefined;
            var w = stdout.writer(io, &bw);
            w.interface.print("ai {s}\n", .{version}) catch {};
            w.flush() catch {};
            return 0;
        } else if (std.mem.eql(u8, arg, "--provider") or std.mem.eql(u8, arg, "-p")) {
            const val = args.next() orelse {
                printError(io, "missing value for --provider");
                return 1;
            };
            if (provider.Provider.parse(val)) |p| {
                config_mgr.config.provider = p;
            } else {
                printError(io, "unknown provider");
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--model") or std.mem.eql(u8, arg, "-m")) {
            const val = args.next() orelse {
                printError(io, "missing value for --model");
                return 1;
            };
            config_mgr.config.model = val;
        } else if (std.mem.eql(u8, arg, "--api-key") or std.mem.eql(u8, arg, "-k")) {
            const val = args.next() orelse {
                printError(io, "missing value for --api-key");
                return 1;
            };
            config_mgr.config.api_key = val;
        } else if (std.mem.eql(u8, arg, "--system") or std.mem.eql(u8, arg, "-s")) {
            const val = args.next() orelse {
                printError(io, "missing value for --system");
                return 1;
            };
            config_mgr.config.system_prompt = val;
        } else if (std.mem.eql(u8, arg, "ask")) {
            subcommand = .ask;
        } else if (std.mem.eql(u8, arg, "sessions")) {
            subcommand = .sessions;
        } else if (std.mem.eql(u8, arg, "providers")) {
            subcommand = .providers;
        } else if (std.mem.eql(u8, arg, "models")) {
            subcommand = .models;
        } else if (std.mem.eql(u8, arg, "setup")) {
            subcommand = .setup;
        } else if (std.mem.eql(u8, arg, "resume")) {
            subcommand = .resume_session;
            const val = args.next() orelse {
                printError(io, "missing session ID for resume");
                return 1;
            };
            if (std.mem.eql(u8, val, "last")) {
                // will resolve later
            } else {
                resume_id = std.fmt.parseInt(i64, val, 10) catch {
                    printError(io, "invalid session ID");
                    return 1;
                };
            }
        } else if (arg.len > 0 and arg[0] != '-') {
            try prompt_parts.append(gpa, arg);
        }
    }

    config_mgr.config.resolveDefaultModel();

    // First-run setup: if no config file and no explicit subcommand args,
    // and the resolved subcommand needs a key, launch the wizard.
    if (!has_config_file and subcommand == .chat and config_mgr.config.api_key.len == 0 and config_mgr.config.provider != .ollama) {
        const first_arg: ?[]const u8 = if (prompt_parts.items.len > 0) prompt_parts.items[0] else null;
        if (first_arg == null) {
            try setup.run(gpa, io, &config_mgr);
            config_mgr.saveFile(gpa, io) catch {};
        }
    }

    return switch (subcommand) {
        .chat => runChat(gpa, io, &config_mgr, null),
        .ask => runAsk(gpa, io, &config_mgr.config, prompt_parts.items),
        .sessions => runSessions(gpa, io, &config_mgr.config),
        .providers => runProviders(io),
        .models => runModels(gpa, io, &config_mgr.config),
        .setup => runSetup(gpa, io, &config_mgr),
        .resume_session => runChat(gpa, io, &config_mgr, resume_id),
    };
}

const Subcommand = enum {
    chat,
    ask,
    sessions,
    providers,
    models,
    setup,
    resume_session,
};

fn runChat(alloc: std.mem.Allocator, io: std.Io, mgr: *config_mod.ConfigManager, resume_id: ?i64) !u8 {
    const config = &mgr.config;
    if (config.api_key.len == 0 and config.provider != .ollama) {
        printError(io, "no API key set");
        printKeyHelp(io, config.provider);
        return 1;
    }
    try chat.chatSession(alloc, io, mgr, resume_id);
    return 0;
}

fn runAsk(alloc: std.mem.Allocator, io: std.Io, config: *config_mod.Config, parts: []const []const u8) !u8 {
    if (parts.len == 0) {
        printError(io, "no prompt provided");
        return 1;
    }
    if (config.api_key.len == 0 and config.provider != .ollama) {
        printError(io, "no API key set");
        printKeyHelp(io, config.provider);
        return 1;
    }

    // Join prompt parts
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(alloc);
    for (parts, 0..) |p, i| {
        if (i > 0) try buf.append(alloc, ' ');
        try buf.appendSlice(alloc, p);
    }

    try chat.askOnce(alloc, io, config, buf.items);
    return 0;
}

fn runSessions(alloc: std.mem.Allocator, io: std.Io, config: *config_mod.Config) !u8 {
    var sess = try session.Session.open(alloc, io, config.db_path);
    defer sess.close();
    try sess.listSessions(io);
    return 0;
}

fn runProviders(io: std.Io) !u8 {
    const stdout = std.Io.File.stdout();
    var bw: [4096]u8 = undefined;
    var w = stdout.writer(io, &bw);

    try w.interface.writeAll("Supported providers:\n\n");
    for (provider.Provider.all()) |p| {
        try w.interface.print("  {s:<12} \x1b[2m{s}\x1b[0m\n", .{ p.slug(), p.name() });
        try w.interface.print("  {s:<12} \x1b[2mmodel: {s}\x1b[0m\n", .{ "", p.defaultModel() });
        try w.interface.print("  {s:<12} \x1b[2mkey: {s}\x1b[0m\n\n", .{ "", p.envKey() });
    }
    try w.flush();
    return 0;
}

fn runSetup(alloc: std.mem.Allocator, io: std.Io, mgr: *config_mod.ConfigManager) !u8 {
    try setup.run(alloc, io, mgr);
    mgr.saveFile(alloc, io) catch {
        printError(io, "failed to save config");
    };
    return 0;
}

fn runModels(alloc: std.mem.Allocator, io: std.Io, config: *config_mod.Config) !u8 {
    const stdout = std.Io.File.stdout();
    var bw: [4096]u8 = undefined;
    var w = stdout.writer(io, &bw);

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    const models = registry.fetchModels(arena.allocator(), io, config.data_dir, config.provider);

    try w.interface.print("Models for {s} ({d}):\n\n", .{ config.provider.name(), models.len });
    for (models, 0..) |m, i| {
        const marker: []const u8 = if (i == 0) " \x1b[2m(default)\x1b[0m" else "";
        try w.interface.print("  {s}{s}\n", .{ m, marker });
    }
    try w.flush();
    return 0;
}

fn printHelp(io: std.Io) void {
    const text =
        \\io - tiny multi-provider LLM agent
        \\
        \\USAGE:
        \\  io                        Interactive chat session (default)
        \\  io setup                  First-time setup: choose provider & model
        \\  io ask "your prompt"      One-shot: ask a question, get an answer
        \\  io resume <id|last>       Resume a saved session
        \\  io sessions               List saved sessions
        \\  io providers               List supported providers
        \\  io models                  List available models for current provider
        \\
        \\OPTIONS:
        \\  -p, --provider <name>    Provider: openai, anthropic, google, groq,
        \\                           grok, mistral, openrouter, ollama, codex,
        \\                           deepseek, together
        \\  -m, --model <name>       Model name (defaults to provider default)
        \\  -k, --api-key <key>      API key (overrides env var)
        \\  -s, --system <prompt>    System prompt
        \\  -h, --help               Show this help
        \\  -v, --version            Show version
        \\
        \\ENVIRONMENT:
        \\  AI_PROVIDER              Default provider
        \\  AI_MODEL                 Default model
        \\  AI_API_KEY               Default API key
        \\  AI_DATA_DIR              Data directory (default: ~/.ai)
        \\  AI_SYSTEM_PROMPT          System prompt
        \\  AI_MAX_TOKENS            Max output tokens
        \\  OPENAI_API_KEY            OpenAI key
        \\  ANTHROPIC_API_KEY        Anthropic key
        \\  GOOGLE_API_KEY           Google key
        \\  XAI_API_KEY              xAI/Grok key
        \\  ... (see: io providers)
        \\
        \\Sessions are auto-saved to ~/.ai/sessions.jsonl
        \\
    ;
    const stdout = std.Io.File.stdout();
    var bw: [4096]u8 = undefined;
    var w = stdout.writer(io, &bw);
    w.interface.writeAll(text) catch {};
    w.flush() catch {};
}

fn printError(io: std.Io, msg: []const u8) void {
    const stderr = std.Io.File.stderr();
    var bw: [256]u8 = undefined;
    var w = stderr.writer(io, &bw);
    w.interface.print("error: {s}\n", .{msg}) catch {};
    w.flush() catch {};
}

fn printKeyHelp(io: std.Io, prov: provider.Provider) void {
    const stderr = std.Io.File.stderr();
    var bw: [512]u8 = undefined;
    var w = stderr.writer(io, &bw);
    w.interface.print("Set the {s} environment variable or use --api-key.\n", .{prov.envKey()}) catch {};
    w.flush() catch {};
}

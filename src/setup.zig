const std = @import("std");
const provider = @import("provider.zig");
const config_mod = @import("config.zig");
const registry = @import("registry.zig");
const term = @import("term.zig");

/// Interactive first-time setup with a scrollable, searchable TUI.
///
/// The user picks a provider from a filterable list (arrow keys + type to
/// search), then picks a model the same way, then enters an API key.
/// Everything is rendered with ANSI escape codes in raw terminal mode.

const Item = struct {
    label: []const u8,
    sublabel: []const u8,
};

pub fn run(alloc: std.mem.Allocator, io: std.Io, mgr: *config_mod.ConfigManager) !void {
    const config = &mgr.config;
    const stdout = std.Io.File.stdout();
    var out_buf: [8192]u8 = undefined;
    var out = stdout.writer(io, &out_buf);

    const stdin = std.Io.File.stdin();
    var in_buf: [256]u8 = undefined;
    var stdin_reader = stdin.reader(io, &in_buf);

    var guard = term.TermGuard.enable() catch {
        try out.interface.writeAll("\r\nFalling back to numbered selection (not a TTY).\r\n\r\n");
        try out.flush();
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        return runSimple(alloc, arena.allocator(), &stdin_reader, &out, io, mgr);
    };
    defer guard.disable();

    try out.interface.writeAll("\x1b[?25l\x1b[2J\x1b[H");
    try out.interface.writeAll("Welcome to io! Let's get you set up.\r\n\r\n");
    try out.flush();

    // --- 1. Choose provider ---
    const providers = provider.Provider.all();
    var prov_items: [256]Item = undefined;
    for (providers, 0..) |p, i| {
        prov_items[i] = .{ .label = p.slug(), .sublabel = p.name() };
    }

    const prov_idx = try pickFromList(io, &stdin_reader, &out, "Choose a provider", prov_items[0..providers.len]);
    if (prov_idx) |idx| {
        config.provider = providers[idx];
    } else {
        return;
    }

    // --- 2. Choose model ---
    // Fetch live models from models.dev registry (falls back to hardcoded).
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const models = registry.fetchModels(arena.allocator(), io, config.data_dir, config.provider);
    var model_items: [256]Item = undefined;
    for (models, 0..) |m, i| {
        model_items[i] = .{
            .label = m,
            .sublabel = if (i == 0) "default" else "",
        };
    }

    const model_idx = try pickFromList(io, &stdin_reader, &out, "Choose a model", model_items[0..models.len]);
    if (model_idx) |idx| {
        mgr.setOwnedModel(alloc, models[idx]);
    } else {
        return;
    }

    // --- 3. API key ---
    try out.interface.writeAll("\x1b[2J\x1b[H");
    try out.interface.print("Setup: {s} / {s}\r\n\r\n", .{ config.provider.name(), config.model });
    try out.flush();

    if (!config.provider.isLocal()) {
        const env_key = config.provider.envKey();
        try out.interface.print("Enter your API key (env: {s})\r\n", .{env_key});
        try out.interface.writeAll("Type your key, or Enter to use env var instead.\r\n> ");
        try out.flush();

        var key_buf: [512]u8 = undefined;
        const key = readLineRaw(&stdin_reader, &out, &key_buf);
        if (key.len > 0) {
            mgr.setKeyFor(alloc, config.provider, key);
        } else {
            try out.interface.print("\r\n\x1b[2mSet {s} before running io.\x1b[0m\r\n", .{env_key});
            try out.flush();
        }
    } else {
        try out.interface.writeAll("Ollama runs locally — no API key needed.\r\n");
        try out.flush();
    }

    // --- 4. System prompt ---
    try out.interface.writeAll("\r\nSystem prompt (blank for default): ");
    try out.flush();
    var sp_buf: [1024]u8 = undefined;
    const sp = readLineRaw(&stdin_reader, &out, &sp_buf);
    if (sp.len > 0) mgr.setOwnedSystemPrompt(alloc, sp);

    // --- 5. Summary ---
    try out.interface.print("\r\n\x1b[1mSetup complete:\x1b[0m\r\n", .{});
    try out.interface.print("  provider:  {s}\r\n", .{config.provider.slug()});
    try out.interface.print("  model:     {s}\r\n", .{config.model});
    try out.interface.print("  api key:   {s}\r\n", .{if (config.api_key.len > 0) "set" else "(via env)"});
    try out.interface.print("  system:    {s}\r\n", .{if (config.system_prompt.len > 0) config.system_prompt else "(default)"});
    try out.interface.writeAll("\r\n");
    try out.flush();
}

/// Maximum items we can filter at once (covers all 181 Mastra providers).
const MAX_FILTERED = 256;

/// Interactive scrollable, searchable list picker.
/// Returns the original index into `items`, or null if cancelled (Esc).
fn pickFromList(
    io: std.Io,
    stdin_reader: *std.Io.File.Reader,
    out: *std.Io.File.Writer,
    title: []const u8,
    items: []const Item,
) !?usize {
    var query: [256]u8 = undefined;
    var query_len: usize = 0;
    var selected: usize = 0;
    var scroll: usize = 0;
    const term_rows = getTerminalRows(io);
    const max_visible: usize = if (term_rows > 8) term_rows - 8 else 10;

    while (true) {
        // Build filtered index list
        var filtered: [MAX_FILTERED]usize = undefined;
        var filtered_len: usize = 0;
        for (items, 0..) |item, i| {
            if (query_len == 0 or
                std.ascii.indexOfIgnoreCase(item.label, query[0..query_len]) != null or
                std.ascii.indexOfIgnoreCase(item.sublabel, query[0..query_len]) != null)
            {
                if (filtered_len < MAX_FILTERED) {
                    filtered[filtered_len] = i;
                    filtered_len += 1;
                }
            }
        }

        if (filtered_len == 0) {
            selected = 0;
        } else if (selected >= filtered_len) {
            selected = filtered_len - 1;
        }

        if (selected < scroll) scroll = selected;
        if (selected >= scroll + max_visible) scroll = selected - max_visible + 1;

        // Render
        try out.interface.writeAll("\x1b[2J\x1b[H");
        try out.interface.print("\x1b[1m{s}\x1b[0m\r\n", .{title});
        if (query_len > 0) {
            try out.interface.print("\x1b[2mfilter:\x1b[0m {s}\r\n", .{query[0..query_len]});
        } else {
            try out.interface.writeAll("\x1b[2mtype to search, \xe2\x86\x91\xe2\x86\x93 to move, Enter to select\x1b[0m\r\n");
        }
        try out.interface.writeAll("\r\n");

        const visible_count = @min(max_visible, filtered_len);
        for (0..visible_count) |i| {
            const idx = filtered[scroll + i];
            const item = items[idx];

            if (i == selected - scroll) {
                try out.interface.writeAll("\x1b[1;36m\xe2\x9d\xaf ");
            } else {
                try out.interface.writeAll("  ");
            }
            try out.interface.writeAll(item.label);

            if (item.sublabel.len > 0) {
                if (i == selected - scroll) {
                    try out.interface.print(" \x1b[2;36m{s}\x1b[0m", .{item.sublabel});
                } else {
                    try out.interface.print(" \x1b[2m{s}\x1b[0m", .{item.sublabel});
                }
            }
            try out.interface.writeAll("\r\n");
        }

        if (filtered_len == 0) {
            try out.interface.writeAll("\x1b[2m  no matches\x1b[0m\r\n");
        }

        try out.interface.print(
            "\r\n\x1b[2m{d}/{d} shown  \xc2\xb7  Enter=select  Esc=cancel\x1b[0m",
            .{ visible_count, filtered_len },
        );
        try out.flush();

        const key = try readKey(stdin_reader);
        switch (key) {
            .up => {
                if (selected > 0) selected -= 1;
            },
            .down => {
                if (selected + 1 < filtered_len) selected += 1;
            },
            .enter => {
                if (filtered_len == 0) continue;
                return filtered[selected];
            },
            .escape => return null,
            .char => |c| {
                if (c == 0x7f or c == 0x08) {
                    if (query_len > 0) {
                        query_len -= 1;
                        selected = 0;
                        scroll = 0;
                    }
                } else if (c >= 0x20 and c < 0x7f and query_len < query.len) {
                    query[query_len] = c;
                    query_len += 1;
                    selected = 0;
                    scroll = 0;
                }
            },
        }
    }
}

const Key = union(enum) {
    up,
    down,
    enter,
    escape,
    char: u8,
};

fn readKey(stdin_reader: *std.Io.File.Reader) !Key {
    var b: [1]u8 = undefined;
    _ = stdin_reader.interface.readSliceShort(&b) catch return .escape;
    const c = b[0];

    if (c == 0x1b) {
        var seq: [2]u8 = undefined;
        const n1 = stdin_reader.interface.readSliceShort(seq[0..1]) catch return .escape;
        if (n1 == 0) return .escape;
        if (seq[0] == '[') {
            const n2 = stdin_reader.interface.readSliceShort(seq[1..2]) catch return .escape;
            if (n2 == 0) return .escape;
            return switch (seq[1]) {
                'A' => .up,
                'B' => .down,
                else => .escape,
            };
        }
        return .escape;
    }

    if (c == '\r' or c == '\n') return .enter;
    return .{ .char = c };
}

fn readLineRaw(
    stdin_reader: *std.Io.File.Reader,
    out: *std.Io.File.Writer,
    buf: []u8,
) []const u8 {
    var len: usize = 0;
    while (len < buf.len) {
        var b: [1]u8 = undefined;
        const n = stdin_reader.interface.readSliceShort(&b) catch break;
        if (n == 0) break;
        const c = b[0];
        if (c == '\r' or c == '\n') {
            out.interface.writeAll("\r\n") catch {};
            out.flush() catch {};
            break;
        }
        if (c == 0x7f or c == 0x08) {
            if (len > 0) {
                len -= 1;
                out.interface.writeAll("\x08 \x08") catch {};
                out.flush() catch {};
            }
            continue;
        }
        if (c >= 0x20 and c < 0x7f) {
            buf[len] = c;
            len += 1;
            out.interface.writeByte(c) catch {};
            out.flush() catch {};
        }
    }
    return buf[0..len];
}

fn getTerminalRows(io: std.Io) usize {
    _ = io;
    return term.height();
}

/// Simple fallback for non-TTY (piped) input.
fn runSimple(
    alloc: std.mem.Allocator,
    arena: std.mem.Allocator,
    stdin_reader: *std.Io.File.Reader,
    out: *std.Io.File.Writer,
    io: std.Io,
    mgr: *config_mod.ConfigManager,
) !void {
    const config = &mgr.config;
    const providers = provider.Provider.all();

    while (true) {
        try out.interface.writeAll("Choose a provider:\n\n");
        for (providers, 0..) |p, i| {
            try out.interface.print("  {d:>2}) {s:<14} {s}\n", .{ i + 1, p.slug(), p.name() });
        }
        try out.interface.writeAll("\nNumber: ");
        try out.flush();

        const line = (stdin_reader.interface.takeDelimiter('\n') catch return) orelse return;
        const choice = std.fmt.parseInt(usize, std.mem.trim(u8, line, " \t\r"), 10) catch {
            try out.interface.writeAll("Invalid, try again.\n\n");
            continue;
        };
        if (choice == 0 or choice > providers.len) {
            try out.interface.writeAll("Out of range, try again.\n\n");
            continue;
        }
        config.provider = providers[choice - 1];
        break;
    }
    try out.interface.print("\nUsing {s}.\n\n", .{config.provider.name()});
    try out.flush();

    const models = registry.fetchModels(arena, io, config.data_dir, config.provider);
    while (true) {
        try out.interface.writeAll("Choose a model:\n\n");
        for (models, 0..) |m, i| {
            const marker: []const u8 = if (i == 0) " (default)" else "";
            try out.interface.print("  {d:>2}) {s}{s}\n", .{ i + 1, m, marker });
        }
        try out.interface.print("\nNumber [1-{d}]: ", .{models.len});
        try out.flush();

        const line = (stdin_reader.interface.takeDelimiter('\n') catch return) orelse return;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) {
            mgr.setOwnedModel(alloc, models[0]);
            break;
        }
        const choice = std.fmt.parseInt(usize, trimmed, 10) catch {
            try out.interface.writeAll("Invalid, try again.\n\n");
            continue;
        };
        if (choice == 0 or choice > models.len) {
            try out.interface.writeAll("Out of range, try again.\n\n");
            continue;
        }
        mgr.setOwnedModel(alloc, models[choice - 1]);
        break;
    }
    try out.interface.print("\nUsing {s}.\n\n", .{config.model});
    try out.flush();

    if (!config.provider.isLocal()) {
        const env_key = config.provider.envKey();
        try out.interface.print("Enter your API key (env: {s})\n(blank to use env var): ", .{env_key});
        try out.flush();
        const line = (stdin_reader.interface.takeDelimiter('\n') catch return) orelse return;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0) mgr.setOwnedApiKey(alloc, trimmed);
    }

    try out.interface.writeAll("\nSystem prompt (blank for default): ");
    try out.flush();
    const sp_line = (stdin_reader.interface.takeDelimiter('\n') catch return) orelse return;
    const sp = std.mem.trim(u8, sp_line, " \t\r");
    if (sp.len > 0) mgr.setOwnedSystemPrompt(alloc, sp);

    try out.interface.print("\nSetup complete: {s} / {s}\n", .{ config.provider.slug(), config.model });
    try out.flush();
}

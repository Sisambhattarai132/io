const std = @import("std");
const session = @import("session.zig");
const provider = @import("provider.zig");
const config_mod = @import("config.zig");
const json = @import("json.zig");
const http_client = @import("http_client.zig");

/// Approximate characters per token (English text average).
/// Real tokenizers vary, but this heuristic is good enough for
/// deciding *when* to compact — we don't need exact counts.
const CHARS_PER_TOKEN: usize = 4;

/// Compaction triggers when estimated tokens reach this fraction
/// of the configured context window.
pub const THRESHOLD: f64 = 0.8;

/// Number of recent messages to keep verbatim after compaction.
/// Large enough to preserve the last 2–3 turns (user + assistant +
/// tool results) so the agent doesn't lose its current task context.
pub const KEEP_RECENT: usize = 10;

/// Result of a successful compaction, for display to the user.
pub const CompactResult = struct {
    before_tokens: usize,
    after_tokens: usize,
};

/// Rough token estimate for the full message list + system prompt.
pub fn estimateTokens(messages: []const session.Message, system_prompt: []const u8) usize {
    var total: usize = system_prompt.len / CHARS_PER_TOKEN;
    for (messages) |msg| {
        total += msg.content.len / CHARS_PER_TOKEN + 4; // +4 for role/framing
        if (msg.tool_calls) |tcs| {
            for (tcs) |tc| {
                total += (tc.name.len + tc.arguments.len) / CHARS_PER_TOKEN + 8;
            }
        }
    }
    return total;
}

/// Returns true if the conversation has grown large enough to compact.
pub fn needsCompact(
    messages: []const session.Message,
    system_prompt: []const u8,
    context_window: usize,
) bool {
    const limit = @as(usize, @intFromFloat(@as(f64, @floatFromInt(context_window)) * THRESHOLD));
    return estimateTokens(messages, system_prompt) >= limit;
}

/// Frees a message's owned memory (content, tool_calls, tool_call_id).
fn freeMessage(alloc: std.mem.Allocator, msg: session.Message) void {
    alloc.free(msg.content);
    if (msg.tool_calls) |tcs| {
        for (tcs) |tc| {
            alloc.free(tc.id);
            alloc.free(tc.name);
            alloc.free(tc.arguments);
        }
        alloc.free(tcs);
    }
    if (msg.tool_call_id) |id| alloc.free(id);
}

/// Finds a safe split point: the start of the "recent" block.
/// Walks forward from `len - KEEP_RECENT` until it hits a `user`
/// message, so we never break a tool-call sequence (a `tool`
/// message must always follow an `assistant` message with matching
/// `tool_calls`).
fn findSplitPoint(messages: []const session.Message) usize {
    if (messages.len <= KEEP_RECENT) return 0;
    var split = messages.len - KEEP_RECENT;
    while (split < messages.len and messages[split].role != .user) {
        split += 1;
    }
    return split;
}

/// Checks if compaction is needed, performs it, and returns the
/// before/after token counts. Returns null if no compaction was
/// needed or the summarization request failed.
pub fn maybeCompact(
    alloc: std.mem.Allocator,
    io: std.Io,
    config: *config_mod.Config,
    messages: *std.ArrayList(session.Message),
) ?CompactResult {
    if (!needsCompact(messages.items, config.system_prompt, config.context_window)) return null;

    const before = estimateTokens(messages.items, config.system_prompt);

    compact(alloc, io, config, messages) catch return null;

    const after = estimateTokens(messages.items, config.system_prompt);
    return .{ .before_tokens = before, .after_tokens = after };
}

/// Performs the compaction: asks the LLM to summarize the older
/// messages, then replaces them with a single summary message while
/// keeping the most recent messages verbatim.
fn compact(
    alloc: std.mem.Allocator,
    io: std.Io,
    config: *config_mod.Config,
    messages: *std.ArrayList(session.Message),
) !void {
    const split = findSplitPoint(messages.items);
    if (split == 0) return; // nothing to compact

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    // Build a flat text transcript of the old messages for summarization.
    // Using plain text avoids tool-call serialization issues across
    // OpenAI and Anthropic formats.
    var transcript: std.ArrayList(u8) = .empty;
    defer transcript.deinit(a);

    try transcript.appendSlice(a,
        \\Summarize the conversation below. Preserve key context, decisions
        \\made, files read or edited, tool results, errors encountered, and
        \\the current task state. Be concise but do not lose important details.
        \\
        \\
    );

    for (messages.items[0..split]) |msg| {
        const label = switch (msg.role) {
            .user => "User",
            .assistant => "Assistant",
            .tool => "Tool result",
            .system => "System",
        };
        try transcript.print(a, "{s}: {s}\n", .{ label, msg.content });
        if (msg.tool_calls) |tcs| {
            for (tcs) |tc| {
                try transcript.print(a, "  [called tool: {s}({s})]\n", .{ tc.name, tc.arguments });
            }
        }
    }

    // Summarization request: system instruction + single user message.
    const sum_messages = [_]session.Message{
        .{ .role = .system, .content = "You are a conversation summarizer. Create a concise summary that preserves all important context needed to continue the conversation." },
        .{ .role = .user, .content = transcript.items },
    };

    const payload = try json.buildPayload(
        a,
        config.provider,
        config.model,
        &sum_messages,
        "",
        @min(config.max_tokens, 2048),
        config.temperature,
        false,
    );

    // Non-streaming POST to get the full summary in one shot.
    var body: std.Io.Writer.Allocating = .init(a);
    defer body.deinit();

    const status = http_client.postChat(a, io, config.provider, config.provider.chatUrl(), config.api_key, payload, &body.writer) catch return error.HttpFailed;
    if (@intFromEnum(status) >= 400) return error.HttpBadStatus;

    const response_body = body.toOwnedSlice() catch return error.OutOfMemory;
    const summary = extractContent(a, config.provider, response_body) catch return error.ParseFailed;
    if (summary.len == 0) return error.ParseFailed;

    // --- Rebuild the message list ---

    // 1. Save references to recent messages (their content is still allocated).
    const recent_count = messages.items.len - split;
    const recent = try a.alloc(session.Message, recent_count);
    for (messages.items[split..], 0..) |m, i| recent[i] = m;

    // 2. Free old messages (indices 0..split).
    for (messages.items[0..split]) |m| freeMessage(alloc, m);

    // 3. Clear the list (keeps capacity, doesn't touch items).
    messages.clearRetainingCapacity();

    // 4. Insert the summary as a system message.
    const summary_text = try std.fmt.allocPrint(alloc, "[Previous conversation, compacted for context]\n{s}", .{summary});
    try messages.append(alloc, .{ .role = .system, .content = summary_text });

    // 5. Re-append recent messages (ownership of their content transfers).
    for (recent) |m| try messages.append(alloc, m);
}

/// Extracts the assistant's text from a non-streaming API response.
/// Handles OpenAI-compatible and Anthropic response formats.
fn extractContent(arena: std.mem.Allocator, prov: provider.Provider, body: []const u8) ![]const u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, arena, body, .{}) catch return error.ParseFailed;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.ParseFailed;

    if (prov.usesAnthropicFormat()) {
        // {"content":[{"type":"text","text":"..."}]}
        const content = root.object.get("content") orelse return error.ParseFailed;
        if (content != .array) return error.ParseFailed;
        for (content.array.items) |item| {
            if (item != .object) continue;
            const t = item.object.get("type") orelse continue;
            if (t == .string and std.mem.eql(u8, t.string, "text")) {
                if (item.object.get("text")) |text| {
                    if (text == .string) return try arena.dupe(u8, text.string);
                }
            }
        }
        return error.ParseFailed;
    }

    // OpenAI: {"choices":[{"message":{"content":"..."}}]}
    const choices = root.object.get("choices") orelse return error.ParseFailed;
    if (choices != .array or choices.array.items.len == 0) return error.ParseFailed;
    const choice = choices.array.items[0];
    if (choice != .object) return error.ParseFailed;
    const message = choice.object.get("message") orelse return error.ParseFailed;
    if (message != .object) return error.ParseFailed;
    const content_val = message.object.get("content") orelse return error.ParseFailed;
    if (content_val != .string) return error.ParseFailed;
    return try arena.dupe(u8, content_val.string);
}

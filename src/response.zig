const std = @import("std");
const provider = @import("provider.zig");
const tools = @import("tools.zig");

/// Extracts the text content delta from a streaming SSE JSON chunk.
/// Handles both OpenAI-compatible and Anthropic streaming formats.
/// Returns a borrowed slice into `chunk` (no allocation).
/// Returns null if the chunk has no content delta (e.g. role-only chunks).
pub fn extractDelta(alloc: std.mem.Allocator, prov: provider.Provider, chunk: []const u8) !?[]const u8 {
    _ = alloc;

    // Quick reject: empty or error-only chunks
    if (chunk.len < 10) return null;

    if (prov.usesAnthropicFormat()) {
        return extractAnthropicDelta(chunk);
    }
    return extractOpenAIDelta(chunk);
}

/// Extracts tool call fragments from a streaming SSE chunk.
/// OpenAI format accumulates function arguments across deltas:
///   {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_x","function":{"name":"websearch","arguments":"{\"quer"}}]}}]}
/// Returns a list of tool-call fragments found in this chunk (arena-allocated).
pub fn extractToolCallDeltas(
    arena: std.mem.Allocator,
    prov: provider.Provider,
    chunk: []const u8,
) ![]ToolCallDelta {
    _ = prov;

    if (chunk.len < 20) return &.{};
    if (std.mem.indexOf(u8, chunk, "tool_calls") == null) return &.{};

    var list: std.ArrayList(ToolCallDelta) = .empty;

    // Parse the JSON properly
    var parsed = std.json.parseFromSlice(std.json.Value, arena, chunk, .{}) catch return &.{};
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return &.{};
    const choices = root.object.get("choices") orelse return &.{};
    if (choices != .array or choices.array.items.len == 0) return &.{};

    const choice = choices.array.items[0];
    if (choice != .object) return &.{};
    const delta = choice.object.get("delta") orelse return &.{};
    if (delta != .object) return &.{};
    const tool_calls = delta.object.get("tool_calls") orelse return &.{};
    if (tool_calls != .array) return &.{};

    for (tool_calls.array.items) |tc| {
        if (tc != .object) continue;
        var frag: ToolCallDelta = .{ .index = 0, .id = null, .name = null, .arguments = null };

        if (tc.object.get("index")) |idx| {
            if (idx == .integer) frag.index = @intCast(idx.integer);
        }
        if (tc.object.get("id")) |id| {
            if (id == .string) frag.id = try arena.dupe(u8, id.string);
        }
        const fn_obj = tc.object.get("function") orelse continue;
        if (fn_obj != .object) continue;
        if (fn_obj.object.get("name")) |name| {
            if (name == .string) frag.name = try arena.dupe(u8, name.string);
        }
        if (fn_obj.object.get("arguments")) |args| {
            if (args == .string) frag.arguments = try arena.dupe(u8, args.string);
        }

        try list.append(arena, frag);
    }

    return list.items;
}

/// A tool-call fragment from a single SSE chunk.
pub const ToolCallDelta = struct {
    index: usize,
    id: ?[]const u8,
    name: ?[]const u8,
    arguments: ?[]const u8,
};

/// Accumulates tool-call fragments across multiple SSE chunks into complete calls.
/// Keyed by the tool-call index (0, 1, 2, ...).
pub const ToolCallAccumulator = struct {
    alloc: std.mem.Allocator,
    entries: std.ArrayList(AccEntry) = .empty,

    pub const AccEntry = struct {
        index: usize,
        id: []const u8,
        name: []const u8,
        arguments: std.ArrayList(u8) = .empty,
    };

    pub fn init(alloc: std.mem.Allocator) ToolCallAccumulator {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *ToolCallAccumulator) void {
        for (self.entries.items) |*entry| {
            self.alloc.free(entry.id);
            self.alloc.free(entry.name);
            entry.arguments.deinit(self.alloc);
        }
        self.entries.deinit(self.alloc);
    }

    fn findEntry(self: *ToolCallAccumulator, index: usize) ?*AccEntry {
        for (self.entries.items) |*entry| {
            if (entry.index == index) return entry;
        }
        return null;
    }

    /// Adds a delta fragment. If this fragment has an id/name, it starts a new entry.
    /// If it only has arguments, they're appended to the existing entry.
    pub fn addDelta(self: *ToolCallAccumulator, delta: ToolCallDelta) !void {
        if (self.findEntry(delta.index)) |entry| {
            // Update id/name if provided (first chunk for this index has them)
            if (delta.id) |id| {
                if (entry.id.len == 0) {
                    self.alloc.free(entry.id);
                    entry.id = try self.alloc.dupe(u8, id);
                }
            }
            if (delta.name) |name| {
                if (entry.name.len == 0) {
                    self.alloc.free(entry.name);
                    entry.name = try self.alloc.dupe(u8, name);
                }
            }
            if (delta.arguments) |args| {
                try entry.arguments.appendSlice(self.alloc, args);
            }
        } else {
            try self.entries.append(self.alloc, .{
                .index = delta.index,
                .id = if (delta.id) |id| try self.alloc.dupe(u8, id) else try self.alloc.dupe(u8, ""),
                .name = if (delta.name) |name| try self.alloc.dupe(u8, name) else try self.alloc.dupe(u8, ""),
                .arguments = .empty,
            });
            if (delta.arguments) |args| {
                try self.entries.items[self.entries.items.len - 1].arguments.appendSlice(self.alloc, args);
            }
        }
    }

    /// Returns true if at least one tool call has been accumulated.
    pub fn hasToolCalls(self: *ToolCallAccumulator) bool {
        return self.entries.items.len > 0;
    }

    /// Returns a list of complete tool calls (arena-allocated).
    pub fn collect(self: *ToolCallAccumulator, arena: std.mem.Allocator) ![]tools.ToolCall {
        var list: std.ArrayList(tools.ToolCall) = .empty;

        // Sort by index
        std.mem.sort(AccEntry, self.entries.items, {}, struct {
            fn lt(_: void, a: AccEntry, b: AccEntry) bool {
                return a.index < b.index;
            }
        }.lt);

        for (self.entries.items) |entry| {
            try list.append(arena, .{
                .id = try arena.dupe(u8, entry.id),
                .name = try arena.dupe(u8, entry.name),
                .arguments = try arena.dupe(u8, entry.arguments.items),
            });
        }

        return list.items;
    }
};

/// OpenAI-compatible format:
/// {"choices":[{"delta":{"content":"text"}}],...}
fn extractOpenAIDelta(chunk: []const u8) ?[]const u8 {
    // Look for "content":" inside the chunk
    const marker = "\"content\":\"";
    var start = std.mem.indexOf(u8, chunk, marker) orelse return null;
    start += marker.len;

    // Find the closing quote, handling escape sequences
    var i = start;
    while (i < chunk.len) : (i += 1) {
        if (chunk[i] == '\\') {
            i += 1;
            continue;
        }
        if (chunk[i] == '"') break;
    }
    if (i >= chunk.len) return null;

    return chunk[start..i];
}

/// Anthropic streaming format:
/// event: content_block_delta
/// data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hello"}}
fn extractAnthropicDelta(chunk: []const u8) ?[]const u8 {
    // Only process content_block_delta events
    if (std.mem.indexOf(u8, chunk, "text_delta") == null) return null;

    const marker = "\"text\":\"";
    var start = std.mem.indexOf(u8, chunk, marker) orelse return null;
    start += marker.len;

    var i = start;
    while (i < chunk.len) : (i += 1) {
        if (chunk[i] == '\\') {
            i += 1;
            continue;
        }
        if (chunk[i] == '"') break;
    }
    if (i >= chunk.len) return null;

    return chunk[start..i];
}

/// Extracts the full content from a non-streaming JSON response.
/// OpenAI format: {"choices":[{"message":{"content":"..."}}]}
/// Anthropic format: {"content":[{"type":"text","text":"..."}]}
pub fn extractFullContent(alloc: std.mem.Allocator, prov: provider.Provider, body: []const u8) !?[]const u8 {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    const parsed = std.json.parseFromSlice(std.json.Value, a, body, .{}) catch return null;
    const root = parsed.value;

    if (prov.usesAnthropicFormat()) {
        // {"content":[{"type":"text","text":"..."}]}
        if (root != .object) return null;
        const content_arr = root.object.get("content") orelse return null;
        if (content_arr != .array) return null;

        // Concatenate all text blocks
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(alloc);
        for (content_arr.array.items) |item| {
            if (item != .object) continue;
            const text_val = item.object.get("text") orelse continue;
            if (text_val != .string) continue;
            try buf.appendSlice(alloc, text_val.string);
        }
        if (buf.items.len == 0) return null;
        return try alloc.dupe(u8, buf.items);
    }

    // OpenAI format
    if (root != .object) return null;
    const choices = root.object.get("choices") orelse return null;
    if (choices != .array or choices.array.items.len == 0) return null;

    const first = choices.array.items[0];
    if (first != .object) return null;
    const message = first.object.get("message") orelse return null;
    if (message != .object) return null;
    const content = message.object.get("content") orelse return null;
    if (content != .string) return null;

    return try alloc.dupe(u8, content.string);
}

test "extract openai delta" {
    const chunk = "{\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}";
    const result = extractOpenAIDelta(chunk).?;
    try std.testing.expectEqualStrings("hello", result);
}

test "extract openai delta with escaped quote" {
    const chunk = "{\"choices\":[{\"delta\":{\"content\":\"say \\\"hi\\\"\"}}]}";
    const result = extractOpenAIDelta(chunk).?;
    try std.testing.expectEqualStrings("say \\\"hi\\\"", result);
}

test "extract openai delta no content" {
    const chunk = "{\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}";
    const result = extractOpenAIDelta(chunk);
    try std.testing.expect(result == null);
}

test "extract full content openai" {
    const body = "{\"choices\":[{\"message\":{\"content\":\"full reply\"}}]}";
    const result = try extractFullContent(std.testing.allocator, .openai, body);
    defer if (result) |r| std.testing.allocator.free(r);
    try std.testing.expectEqualStrings("full reply", result.?);
}

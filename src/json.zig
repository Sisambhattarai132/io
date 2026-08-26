const std = @import("std");
const provider = @import("provider.zig");
const session = @import("session.zig");
const tools = @import("tools.zig");

/// Builds a JSON request body for the OpenAI-compatible chat/completions API.
pub fn buildOpenAIPayload(
    alloc: std.mem.Allocator,
    model: []const u8,
    messages: []const session.Message,
    system_prompt: []const u8,
    max_tokens: u32,
    temperature: f64,
    stream: bool,
) ![]u8 {
    return buildOpenAIPayloadWithTools(alloc, model, messages, system_prompt, max_tokens, temperature, stream, false);
}

/// Builds a JSON request body for the OpenAI-compatible chat/completions API,
/// optionally including tool definitions and tool_choice.
pub fn buildOpenAIPayloadWithTools(
    alloc: std.mem.Allocator,
    model: []const u8,
    messages: []const session.Message,
    system_prompt: []const u8,
    max_tokens: u32,
    temperature: f64,
    stream: bool,
    include_tools: bool,
) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(alloc);

    try buf.appendSlice(alloc, "{\"model\":");
    try writeJsonString(alloc, &buf, model);
    try buf.appendSlice(alloc, ",\"messages\":[");

    if (system_prompt.len > 0) {
        try buf.appendSlice(alloc, "{\"role\":\"system\",\"content\":");
        try writeJsonString(alloc, &buf, system_prompt);
        try buf.appendSlice(alloc, "}");
    }

    var first = system_prompt.len == 0;
    for (messages) |msg| {
        if (!first) try buf.append(alloc, ',');
        first = false;
        try buf.appendSlice(alloc, "{\"role\":\"");
        try buf.appendSlice(alloc, msg.role.toString());

        // If this is an assistant message with tool_calls, emit tool_calls array
        if (msg.role == .assistant and msg.tool_calls != null) {
            const tcs = msg.tool_calls.?;
            try buf.appendSlice(alloc, "\",\"content\":");
            if (msg.content.len > 0) {
                try writeJsonString(alloc, &buf, msg.content);
            } else {
                try buf.appendSlice(alloc, "\"\"");
            }
            try buf.appendSlice(alloc, ",\"tool_calls\":[");
            for (tcs, 0..) |tc, i| {
                if (i > 0) try buf.append(alloc, ',');
                try buf.appendSlice(alloc, "{\"id\":");
                try writeJsonString(alloc, &buf, tc.id);
                try buf.appendSlice(alloc, ",\"type\":\"function\",\"function\":{\"name\":");
                try writeJsonString(alloc, &buf, tc.name);
                try buf.appendSlice(alloc, ",\"arguments\":");
                try writeJsonString(alloc, &buf, tc.arguments);
                try buf.appendSlice(alloc, "}}");
            }
            try buf.append(alloc, ']');
            try buf.append(alloc, '}'); // close assistant message object
        } else if (msg.role == .tool) {
            // Tool result message: {"role":"tool","tool_call_id":"...","content":"..."}
            try buf.appendSlice(alloc, "\",\"tool_call_id\":");
            try writeJsonString(alloc, &buf, msg.tool_call_id orelse "");
            try buf.appendSlice(alloc, ",\"content\":");
            try writeJsonString(alloc, &buf, msg.content);
            try buf.append(alloc, '}');
            continue;
        } else {
            try buf.appendSlice(alloc, "\",\"content\":");
            try writeJsonString(alloc, &buf, msg.content);
            try buf.append(alloc, '}');
        }
    }

    try buf.appendSlice(alloc, "],\"max_tokens\":");
    try buf.print(alloc, "{d}", .{max_tokens});
    try buf.appendSlice(alloc, ",\"temperature\":");
    try buf.print(alloc, "{d}", .{temperature});
    if (stream) {
        try buf.appendSlice(alloc, ",\"stream\":true");
    }

    if (include_tools) {
        try buf.appendSlice(alloc, ",\"tools\":");
        try buf.appendSlice(alloc, tools.toolsJson());
        try buf.appendSlice(alloc, ",\"tool_choice\":\"auto\"");
    }

    try buf.append(alloc, '}');

    return try buf.toOwnedSlice(alloc);
}

/// Builds a JSON request body for the Anthropic Messages API.
pub fn buildAnthropicPayload(
    alloc: std.mem.Allocator,
    model: []const u8,
    messages: []const session.Message,
    system_prompt: []const u8,
    max_tokens: u32,
    temperature: f64,
    stream: bool,
) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(alloc);

    try buf.appendSlice(alloc, "{\"model\":");
    try writeJsonString(alloc, &buf, model);

    if (system_prompt.len > 0) {
        try buf.appendSlice(alloc, ",\"system\":");
        try writeJsonString(alloc, &buf, system_prompt);
    }

    try buf.appendSlice(alloc, ",\"max_tokens\":");
    try buf.print(alloc, "{d}", .{max_tokens});

    try buf.appendSlice(alloc, ",\"messages\":[");
    var first = true;
    for (messages) |msg| {
        if (!first) try buf.append(alloc, ',');
        first = false;
        try buf.appendSlice(alloc, "{\"role\":\"");
        try buf.appendSlice(alloc, msg.role.toString());
        try buf.appendSlice(alloc, "\",\"content\":");
        try writeJsonString(alloc, &buf, msg.content);
        try buf.append(alloc, '}');
    }
    try buf.append(alloc, ']');

    if (stream) {
        try buf.appendSlice(alloc, ",\"stream\":true");
    }

    try buf.appendSlice(alloc, ",\"temperature\":");
    try buf.print(alloc, "{d}", .{temperature});
    try buf.append(alloc, '}');

    return try buf.toOwnedSlice(alloc);
}

pub fn buildPayload(
    alloc: std.mem.Allocator,
    prov: provider.Provider,
    model: []const u8,
    messages: []const session.Message,
    system_prompt: []const u8,
    max_tokens: u32,
    temperature: f64,
    stream: bool,
) ![]u8 {
    if (prov.usesAnthropicFormat()) {
        return buildAnthropicPayload(alloc, model, messages, system_prompt, max_tokens, temperature, stream);
    }
    return buildOpenAIPayload(alloc, model, messages, system_prompt, max_tokens, temperature, stream);
}

/// Like buildPayload but includes tool definitions for the agent loop.
pub fn buildPayloadWithTools(
    alloc: std.mem.Allocator,
    prov: provider.Provider,
    model: []const u8,
    messages: []const session.Message,
    system_prompt: []const u8,
    max_tokens: u32,
    temperature: f64,
    stream: bool,
) ![]u8 {
    if (prov.usesAnthropicFormat()) {
        // Anthropic uses a different tool format; fall back to no tools for now
        return buildAnthropicPayload(alloc, model, messages, system_prompt, max_tokens, temperature, stream);
    }
    return buildOpenAIPayloadWithTools(alloc, model, messages, system_prompt, max_tokens, temperature, stream, true);
}

/// Writes a properly-escaped JSON string into buf.
fn writeJsonString(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    try buf.append(alloc, '"');
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(alloc, "\\\""),
            '\\' => try buf.appendSlice(alloc, "\\\\"),
            '\n' => try buf.appendSlice(alloc, "\\n"),
            '\r' => try buf.appendSlice(alloc, "\\r"),
            '\t' => try buf.appendSlice(alloc, "\\t"),
            0x08 => try buf.appendSlice(alloc, "\\b"),
            0x0C => try buf.appendSlice(alloc, "\\f"),
            else => {
                if (c < 0x20) {
                    try buf.print(alloc, "\\u{x:0>4}", .{c});
                } else {
                    try buf.append(alloc, c);
                }
            },
        }
    }
    try buf.append(alloc, '"');
}

test "json escape" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try writeJsonString(std.testing.allocator, &buf, "hello\"world\n");
    try std.testing.expectEqualStrings("\"hello\\\"world\\n\"", buf.items);
}

test "build openai payload" {
    const messages = [_]session.Message{
        .{ .role = .user, .content = "hello" },
    };
    const payload = try buildOpenAIPayload(
        std.testing.allocator,
        "gpt-4o",
        &messages,
        "sys",
        100,
        0.5,
        false,
    );
    defer std.testing.allocator.free(payload);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"model\":\"gpt-4o\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"role\":\"system\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"role\":\"user\"") != null);
}

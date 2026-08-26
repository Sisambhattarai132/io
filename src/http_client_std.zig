const std = @import("std");
const provider = @import("provider.zig");

pub const HttpError = error{
    HttpRequestFailed,
    HttpBadStatus,
    OutOfMemory,
    InvalidUrl,
};

fn buildHeaders(
    prov: provider.Provider,
    api_key: []const u8,
    auth_buf: *[512]u8,
    hdr_buf: *[4]std.http.Header,
) struct { headers: []std.http.Header, auth_val: []const u8 } {
    var count: usize = 0;
    const auth_val = if (prov == .anthropic)
        api_key
    else
        std.fmt.bufPrint(auth_buf, "Bearer {s}", .{api_key}) catch api_key;

    hdr_buf[count] = .{ .name = prov.authHeaderName(), .value = auth_val };
    count += 1;
    hdr_buf[count] = .{ .name = "Content-Type", .value = "application/json" };
    count += 1;

    if (prov == .anthropic) {
        hdr_buf[count] = .{ .name = "anthropic-version", .value = "2023-06-01" };
        count += 1;
    }

    return .{ .headers = hdr_buf[0..count], .auth_val = auth_val };
}

/// Performs an HTTP POST and returns the full response body via `out`.
pub fn postChat(
    alloc: std.mem.Allocator,
    io: std.Io,
    prov: provider.Provider,
    url: []const u8,
    api_key: []const u8,
    payload: []const u8,
    out: *std.Io.Writer,
) HttpError!std.http.Status {
    var client: std.http.Client = .{ .allocator = alloc, .io = io };
    defer client.deinit();

    var auth_buf: [512]u8 = undefined;
    var hdr_buf: [4]std.http.Header = undefined;
    const h = buildHeaders(prov, api_key, &auth_buf, &hdr_buf);

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = payload,
        .response_writer = out,
        .extra_headers = h.headers,
    }) catch return error.HttpRequestFailed;

    return result.status;
}

/// Performs an HTTP GET and returns the full response body via `out`.
pub fn fetchJson(
    alloc: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    out: *std.Io.Writer,
) HttpError!std.http.Status {
    var client: std.http.Client = .{ .allocator = alloc, .io = io };
    defer client.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = out,
    }) catch return error.HttpRequestFailed;

    return result.status;
}

/// Performs a raw HTTP POST (no auth headers) and returns the full body via `out`.
/// Used by tool execution (e.g. Exa MCP search).
pub fn postRaw(
    alloc: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    payload: []const u8,
    out: *std.Io.Writer,
) HttpError!std.http.Status {
    var client: std.http.Client = .{ .allocator = alloc, .io = io };
    defer client.deinit();

    const hdr = [_]std.http.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        // MCP Streamable HTTP transport requires Accept negotiation
        .{ .name = "Accept", .value = "application/json, text/event-stream" },
    };

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = payload,
        .response_writer = out,
        .extra_headers = &hdr,
    }) catch return error.HttpRequestFailed;

    return result.status;
}

/// Performs a raw HTTP GET and returns the full body via `out`.
/// Used by tool execution (e.g. webfetch).
pub fn fetchUrl(
    alloc: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    out: *std.Io.Writer,
) HttpError!std.http.Status {
    var client: std.http.Client = .{ .allocator = alloc, .io = io };
    defer client.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = out,
    }) catch return error.HttpRequestFailed;

    return result.status;
}

/// libc sleep for retry backoff.
extern "c" fn sleep(seconds: c_uint) c_uint;

/// The SSE stream terminator used by OpenAI-compatible providers.
const sse_done = "[DONE]";

const MAX_RETRIES = 3;
const BASE_DELAY_SEC = 1;

/// Returns true if the HTTP status code is retryable.
fn isRetryable(status_code: u16) bool {
    return status_code == 429 or status_code == 500 or status_code == 502 or status_code == 503 or status_code == 504;
}

/// Streams an SSE response. Calls `on_chunk` for each JSON data payload.
/// Retries on 429/500/502/503/504 with exponential backoff.
/// Calls `on_retry` before each retry attempt (if non-null).
/// Calls `on_error` with the HTTP status code and error body on the final
/// failed attempt (if non-null), so callers can surface it to the user.
pub fn streamChat(
    alloc: std.mem.Allocator,
    io: std.Io,
    prov: provider.Provider,
    url: []const u8,
    api_key: []const u8,
    payload: []const u8,
    on_chunk: *const fn (ctx: *anyopaque, chunk: []const u8) void,
    on_done: *const fn (ctx: *anyopaque) void,
    on_retry: ?*const fn (ctx: *anyopaque, attempt: u8, total: u8) void,
    on_error: ?*const fn (ctx: *anyopaque, status_code: u16, body: []const u8) void,
    ctx: *anyopaque,
) HttpError!void {
    var attempt: u8 = 0;
    while (attempt < MAX_RETRIES) : (attempt += 1) {
        const is_final = attempt + 1 >= MAX_RETRIES;
        const result = streamChatOnce(alloc, io, prov, url, api_key, payload, on_chunk, on_done, ctx, is_final, on_error) catch |err| {
            // Network-level failure: retry if attempts remain
            if (!is_final and err == error.HttpRequestFailed) {
                if (on_retry) |cb| cb(ctx, attempt + 2, MAX_RETRIES);
                const delay = BASE_DELAY_SEC * (@as(c_uint, 1) << @intCast(attempt));
                _ = sleep(delay);
                continue;
            }
            return err;
        };
        // result is 0 on success, or the HTTP status code if >= 400
        if (result != 0 and isRetryable(result) and !is_final) {
            if (on_retry) |cb| cb(ctx, attempt + 2, MAX_RETRIES);
            const delay = BASE_DELAY_SEC * (@as(c_uint, 1) << @intCast(attempt));
            _ = sleep(delay);
            continue;
        }
        return if (result != 0) error.HttpBadStatus else {};
    }
    return error.HttpBadStatus;
}

/// Single attempt of streamChat. Returns 0 on success, or the HTTP status
/// code (as u16) if the server returned an error status >= 400.
/// Calls `on_error` with the status and body on the final failed attempt
/// (if non-null). Does NOT call on_done on error — only on success.
fn streamChatOnce(
    alloc: std.mem.Allocator,
    io: std.Io,
    prov: provider.Provider,
    url: []const u8,
    api_key: []const u8,
    payload: []const u8,
    on_chunk: *const fn (ctx: *anyopaque, chunk: []const u8) void,
    on_done: *const fn (ctx: *anyopaque) void,
    ctx: *anyopaque,
    is_final: bool,
    on_error: ?*const fn (ctx: *anyopaque, status_code: u16, body: []const u8) void,
) HttpError!u16 {
    var client: std.http.Client = .{ .allocator = alloc, .io = io };
    defer client.deinit();

    const uri = std.Uri.parse(url) catch return error.InvalidUrl;

    var auth_buf: [512]u8 = undefined;
    var hdr_buf: [4]std.http.Header = undefined;
    const h = buildHeaders(prov, api_key, &auth_buf, &hdr_buf);

    var req = client.request(.POST, uri, .{
        .extra_headers = h.headers,
    }) catch return error.HttpRequestFailed;
    defer req.deinit();

    req.transfer_encoding = .{ .content_length = payload.len };
    var body = req.sendBodyUnflushed(&.{}) catch return error.HttpRequestFailed;
    body.writer.writeAll(payload) catch return error.HttpRequestFailed;
    body.end() catch return error.HttpRequestFailed;
    req.connection.?.flush() catch return error.HttpRequestFailed;

    var redirect_buf: [8192]u8 = undefined;
    var response = req.receiveHead(&redirect_buf) catch return error.HttpRequestFailed;

    const status_code: u16 = @intFromEnum(response.head.status);

    if (status_code >= 400) {
        if (is_final) {
            var err_buf: std.Io.Writer.Allocating = .init(alloc);
            defer err_buf.deinit();
            var err_transfer: [4096]u8 = undefined;
            var err_reader = response.reader(&err_transfer);
            _ = err_reader.streamRemaining(&err_buf.writer) catch {};
            const err_slice = try err_buf.toOwnedSlice();
            defer alloc.free(err_slice);

            // Deliver the error body to the caller so it can be surfaced in
            // the chat UI (stderr is invisible in TUI mode).
            if (on_error) |cb| cb(ctx, status_code, err_slice);
        }

        // Do NOT call on_done on error — caller (streamChat) handles retries
        return status_code;
    }

    var transfer_buf: [4096]u8 = undefined;
    var reader = response.reader(&transfer_buf);

    while (true) {
        const maybe_line = reader.takeDelimiter('\n') catch return error.HttpRequestFailed;
        const line = maybe_line orelse break;
        if (line.len == 0) continue;

        const trimmed = if (line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;

        if (trimmed.len > 6 and std.mem.eql(u8, trimmed[0..6], "data: ")) {
            const data = trimmed[6..];
            if (std.mem.eql(u8, data, sse_done)) break;
            on_chunk(ctx, data);
        }
    }

    on_done(ctx);
    return 0;
}

/// macOS HTTP client backed by libcurl.
///
/// libcurl.4.dylib is always present in the macOS dyld shared cache, so
/// linking it costs zero bytes in the binary. All TLS/crypto stays in the
/// system library — only our app code and a thin FFI wrapper are compiled
/// into the binary.
const std = @import("std");
const provider = @import("provider.zig");

pub const HttpError = error{
    HttpRequestFailed,
    HttpBadStatus,
    OutOfMemory,
    InvalidUrl,
};

// ── libcurl FFI ──────────────────────────────────────────────────────────

const CURL = opaque {};
const CurlSlist = opaque {};

extern fn curl_easy_init() ?*CURL;
extern fn curl_easy_setopt(handle: *CURL, opt: c_int, ...) c_int;
extern fn curl_easy_perform(handle: *CURL) c_int;
extern fn curl_easy_getinfo(handle: *CURL, info: c_int, ...) c_int;
extern fn curl_easy_cleanup(handle: *CURL) void;
extern fn curl_slist_append(slist: ?*CurlSlist, str: [*:0]const u8) ?*CurlSlist;
extern fn curl_slist_free_all(slist: ?*CurlSlist) void;
extern fn curl_global_init(flags: c_long) c_int;
extern "c" fn sleep(seconds: c_uint) c_uint;

// CURLOPT values (curl.h: LONG=0, OBJECTPOINT=10000, FUNCTIONPOINT=20000)
const CURLOPT_URL: c_int = 10002;
const CURLOPT_WRITEFUNCTION: c_int = 20011;
const CURLOPT_WRITEDATA: c_int = 10001;
const CURLOPT_POSTFIELDS: c_int = 10015;
const CURLOPT_POSTFIELDSIZE: c_int = 60;
const CURLOPT_HTTPHEADER: c_int = 10023;
const CURLOPT_FOLLOWLOCATION: c_int = 52;
const CURLOPT_HEADERFUNCTION: c_int = 20079;
const CURLOPT_HEADERDATA: c_int = 10029;

// CURLINFO (CURLINFO_LONG = 0x200000)
const CURLINFO_RESPONSE_CODE: c_int = 0x200002;

const CURLE_OK: c_int = 0;
const CURL_GLOBAL_DEFAULT: c_long = 3;

var global_initialized = false;

fn ensureGlobalInit() void {
    if (!global_initialized) {
        _ = curl_global_init(CURL_GLOBAL_DEFAULT);
        global_initialized = true;
    }
}

// ── Helpers ──

fn appendHeader(
    alloc: std.mem.Allocator,
    slist: ?*CurlSlist,
    name: []const u8,
    value: []const u8,
) ?*CurlSlist {
    const formatted = std.fmt.allocPrint(alloc, "{s}: {s}\x00", .{ name, value }) catch return slist;
    defer alloc.free(formatted);
    const formatted_z: [*:0]const u8 = @ptrCast(formatted.ptr);
    return curl_slist_append(slist, formatted_z);
}

fn buildAuthHeaders(
    alloc: std.mem.Allocator,
    prov: provider.Provider,
    api_key: []const u8,
) ?*CurlSlist {
    var slist: ?*CurlSlist = null;
    var auth_buf: [512]u8 = undefined;
    const auth_val = if (prov == .anthropic)
        api_key
    else
        std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{api_key}) catch api_key;
    slist = appendHeader(alloc, slist, prov.authHeaderName(), auth_val);
    slist = appendHeader(alloc, slist, "Content-Type", "application/json");
    if (prov == .anthropic) {
        slist = appendHeader(alloc, slist, "anthropic-version", "2023-06-01");
    }
    return slist;
}

fn statusFromCode(code: c_long) std.http.Status {
    return @enumFromInt(@as(u16, @intCast(code)));
}

// ── Write callback for non-streaming responses ──

fn writeCallback(
    ptr: [*]u8,
    size: usize,
    nmemb: usize,
    userdata: ?*anyopaque,
) callconv(.c) usize {
    const total = size * nmemb;
    const out: *std.Io.Writer = @ptrCast(@alignCast(userdata.?));
    out.writeAll(ptr[0..total]) catch return 0;
    return total;
}

// ── Public API: non-streaming ──

pub fn postChat(
    alloc: std.mem.Allocator,
    io: std.Io,
    prov: provider.Provider,
    url: []const u8,
    api_key: []const u8,
    payload: []const u8,
    out: *std.Io.Writer,
) HttpError!std.http.Status {
    _ = io;
    ensureGlobalInit();

    const handle = curl_easy_init() orelse return error.HttpRequestFailed;
    defer curl_easy_cleanup(handle);

    const url_z = alloc.dupeZ(u8, url) catch return error.OutOfMemory;
    defer alloc.free(url_z);

    const slist = buildAuthHeaders(alloc, prov, api_key);
    defer if (slist) |s| curl_slist_free_all(s);

    _ = curl_easy_setopt(handle, CURLOPT_URL, @as([*:0]const u8, url_z.ptr));
    _ = curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
    _ = curl_easy_setopt(handle, CURLOPT_POSTFIELDS, payload.ptr);
    _ = curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(payload.len)));
    if (slist) |s| _ = curl_easy_setopt(handle, CURLOPT_HTTPHEADER, s);
    _ = curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, &writeCallback);
    _ = curl_easy_setopt(handle, CURLOPT_WRITEDATA, @as(?*anyopaque, @ptrCast(out)));

    if (curl_easy_perform(handle) != CURLE_OK) return error.HttpRequestFailed;

    var code: c_long = 0;
    _ = curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &code);
    return statusFromCode(code);
}

pub fn fetchJson(
    alloc: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    out: *std.Io.Writer,
) HttpError!std.http.Status {
    _ = io;
    ensureGlobalInit();

    const handle = curl_easy_init() orelse return error.HttpRequestFailed;
    defer curl_easy_cleanup(handle);

    const url_z = alloc.dupeZ(u8, url) catch return error.OutOfMemory;
    defer alloc.free(url_z);

    _ = curl_easy_setopt(handle, CURLOPT_URL, @as([*:0]const u8, url_z.ptr));
    _ = curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
    _ = curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, &writeCallback);
    _ = curl_easy_setopt(handle, CURLOPT_WRITEDATA, @as(?*anyopaque, @ptrCast(out)));

    if (curl_easy_perform(handle) != CURLE_OK) return error.HttpRequestFailed;

    var code: c_long = 0;
    _ = curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &code);
    return statusFromCode(code);
}

pub fn postRaw(
    alloc: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    payload: []const u8,
    out: *std.Io.Writer,
) HttpError!std.http.Status {
    _ = io;
    ensureGlobalInit();

    const handle = curl_easy_init() orelse return error.HttpRequestFailed;
    defer curl_easy_cleanup(handle);

    const url_z = alloc.dupeZ(u8, url) catch return error.OutOfMemory;
    defer alloc.free(url_z);

    var slist: ?*CurlSlist = null;
    slist = appendHeader(alloc, slist, "Content-Type", "application/json");
    slist = appendHeader(alloc, slist, "Accept", "application/json, text/event-stream");
    defer if (slist) |s| curl_slist_free_all(s);

    _ = curl_easy_setopt(handle, CURLOPT_URL, @as([*:0]const u8, url_z.ptr));
    _ = curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
    _ = curl_easy_setopt(handle, CURLOPT_POSTFIELDS, payload.ptr);
    _ = curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(payload.len)));
    if (slist) |s| _ = curl_easy_setopt(handle, CURLOPT_HTTPHEADER, s);
    _ = curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, &writeCallback);
    _ = curl_easy_setopt(handle, CURLOPT_WRITEDATA, @as(?*anyopaque, @ptrCast(out)));

    if (curl_easy_perform(handle) != CURLE_OK) return error.HttpRequestFailed;

    var code: c_long = 0;
    _ = curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &code);
    return statusFromCode(code);
}

pub fn fetchUrl(
    alloc: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    out: *std.Io.Writer,
) HttpError!std.http.Status {
    _ = io;
    ensureGlobalInit();

    const handle = curl_easy_init() orelse return error.HttpRequestFailed;
    defer curl_easy_cleanup(handle);

    const url_z = alloc.dupeZ(u8, url) catch return error.OutOfMemory;
    defer alloc.free(url_z);

    _ = curl_easy_setopt(handle, CURLOPT_URL, @as([*:0]const u8, url_z.ptr));
    _ = curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
    _ = curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, &writeCallback);
    _ = curl_easy_setopt(handle, CURLOPT_WRITEDATA, @as(?*anyopaque, @ptrCast(out)));

    if (curl_easy_perform(handle) != CURLE_OK) return error.HttpRequestFailed;

    var code: c_long = 0;
    _ = curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &code);
    return statusFromCode(code);
}

// ── SSE Streaming ──

const sse_done = "[DONE]";
const MAX_RETRIES = 3;
const BASE_DELAY_SEC = 1;

fn isRetryable(status_code: u16) bool {
    return status_code == 429 or status_code == 500 or status_code == 502 or
        status_code == 503 or status_code == 504;
}

const StreamCtx = struct {
    alloc: std.mem.Allocator,
    on_chunk: *const fn (ctx: *anyopaque, chunk: []const u8) void,
    on_done: *const fn (ctx: *anyopaque) void,
    user_ctx: *anyopaque,
    is_final: bool,
    status_code: u16 = 0,
    done: bool = false,
    line_buf: std.ArrayList(u8) = .empty,
    err_buf: std.ArrayList(u8) = .empty,
};

/// Parses the HTTP status line to capture the response code.
fn headerCallback(
    buffer: [*]u8,
    size: usize,
    nitems: usize,
    userdata: ?*anyopaque,
) callconv(.c) usize {
    const total = size * nitems;
    const ctx: *StreamCtx = @ptrCast(@alignCast(userdata.?));
    const line = buffer[0..total];

    // Status line: "HTTP/1.1 200 OK\r\n"
    if (line.len >= 5 and std.mem.eql(u8, line[0..5], "HTTP/")) {
        var i: usize = 5;
        while (i < line.len and line[i] != ' ') i += 1;
        i += 1; // skip space
        if (i + 3 <= line.len) {
            ctx.status_code = std.fmt.parseInt(u16, line[i..][0..3], 10) catch 0;
        }
    }
    return total;
}

/// Receives SSE body chunks, splits on newlines, and feeds `data: ` lines
/// to `on_chunk`. For error responses (status >= 400), buffers the body
/// for stderr printing instead.
fn streamWriteCallback(
    ptr: [*]u8,
    size: usize,
    nmemb: usize,
    userdata: ?*anyopaque,
) callconv(.c) usize {
    const total = size * nmemb;
    const ctx: *StreamCtx = @ptrCast(@alignCast(userdata.?));

    if (ctx.done) return total;

    if (ctx.status_code >= 400) {
        ctx.err_buf.appendSlice(ctx.alloc, ptr[0..total]) catch return 0;
        return total;
    }

    for (ptr[0..total]) |byte| {
        if (byte == '\n') {
            var line = ctx.line_buf.items;
            if (line.len > 0 and line[line.len - 1] == '\r') {
                line = line[0 .. line.len - 1];
            }
            if (line.len > 6 and std.mem.eql(u8, line[0..6], "data: ")) {
                const sse_data = line[6..];
                if (std.mem.eql(u8, sse_data, sse_done)) {
                    ctx.done = true;
                } else {
                    ctx.on_chunk(ctx.user_ctx, sse_data);
                }
            }
            ctx.line_buf.clearRetainingCapacity();
        } else {
            ctx.line_buf.append(ctx.alloc, byte) catch return 0;
        }
    }
    return total;
}

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
            if (!is_final and err == error.HttpRequestFailed) {
                if (on_retry) |cb| cb(ctx, attempt + 2, MAX_RETRIES);
                const delay = BASE_DELAY_SEC * (@as(c_uint, 1) << @intCast(attempt));
                _ = sleep(delay);
                continue;
            }
            return err;
        };
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

fn streamChatOnce(
    alloc: std.mem.Allocator,
    io: std.Io,
    prov: provider.Provider,
    url: []const u8,
    api_key: []const u8,
    payload: []const u8,
    on_chunk: *const fn (ctx: *anyopaque, chunk: []const u8) void,
    on_done: *const fn (ctx: *anyopaque) void,
    user_ctx: *anyopaque,
    is_final: bool,
    on_error: ?*const fn (ctx: *anyopaque, status_code: u16, body: []const u8) void,
) HttpError!u16 {
    _ = io; // libcurl uses C stdio internally; io only needed by std backend
    ensureGlobalInit();

    const handle = curl_easy_init() orelse return error.HttpRequestFailed;
    defer curl_easy_cleanup(handle);

    const url_z = alloc.dupeZ(u8, url) catch return error.OutOfMemory;
    defer alloc.free(url_z);

    const slist = buildAuthHeaders(alloc, prov, api_key);
    defer if (slist) |s| curl_slist_free_all(s);

    var stream_ctx: StreamCtx = .{
        .alloc = alloc,
        .on_chunk = on_chunk,
        .on_done = on_done,
        .user_ctx = user_ctx,
        .is_final = is_final,
    };
    defer stream_ctx.line_buf.deinit(alloc);
    defer stream_ctx.err_buf.deinit(alloc);

    _ = curl_easy_setopt(handle, CURLOPT_URL, @as([*:0]const u8, url_z.ptr));
    _ = curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
    _ = curl_easy_setopt(handle, CURLOPT_POSTFIELDS, payload.ptr);
    _ = curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(payload.len)));
    if (slist) |s| _ = curl_easy_setopt(handle, CURLOPT_HTTPHEADER, s);
    _ = curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, &streamWriteCallback);
    _ = curl_easy_setopt(handle, CURLOPT_WRITEDATA, @as(?*anyopaque, @ptrCast(&stream_ctx)));
    _ = curl_easy_setopt(handle, CURLOPT_HEADERFUNCTION, &headerCallback);
    _ = curl_easy_setopt(handle, CURLOPT_HEADERDATA, @as(?*anyopaque, @ptrCast(&stream_ctx)));

    const perf_result = curl_easy_perform(handle);

    // Network-level failure with no response headers received
    if (perf_result != CURLE_OK and stream_ctx.status_code < 400) {
        return error.HttpRequestFailed;
    }

    // HTTP error status
    if (stream_ctx.status_code >= 400) {
        if (is_final) {
            // Deliver the error body to the caller so it can be surfaced in
            // the chat UI (stderr is invisible in TUI mode).
            if (on_error) |cb| cb(user_ctx, stream_ctx.status_code, stream_ctx.err_buf.items);
        }
        return stream_ctx.status_code;
    }

    // Success
    on_done(user_ctx);
    return 0;
}

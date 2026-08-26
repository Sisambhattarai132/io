const std = @import("std");
const http_client = @import("http_client.zig");

/// Tools the agent can use.
/// Modeled after opencode/fx's tool registry:
///   Read-only: read, list_files, grep, glob, websearch, webfetch
///   Editing:   write, edit, delete, mkdir, rename
///   Utility:   bash

pub const ToolError = error{
    InvalidArguments,
    FileNotFound,
    ReadFailed,
    HttpFailed,
    OutOfMemory,
};

/// A tool call parsed from the SSE stream.
pub const ToolCall = struct {
    id: []const u8,
    name: []const u8,
    arguments: []const u8, // raw JSON string
};

/// Result of executing a tool.
pub const ToolResult = struct {
    name: []const u8,
    content: []const u8, // owned by arena
};

/// The JSON schema definitions sent to the model.
/// Returns a static JSON string slice (no allocation needed).
pub fn toolsJson() []const u8 {
    return
        \\[{"type":"function","function":{"name":"read","description":"Read a text file from the filesystem. Returns the file content with line numbers. Limited to 200 lines and 50KB output. For large files, use offset and limit to page.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Absolute or relative file path to read"},"offset":{"type":"integer","description":"1-based line number to start reading from"},"limit":{"type":"integer","description":"Maximum number of lines to read (max 200)"}},"required":["path"]}}},{"type":"function","function":{"name":"list_files","description":"List files and directories at a given path. Returns names and types (file/directory). Limited to 200 entries.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Directory path to list"}},"required":["path"]}}},{"type":"function","function":{"name":"grep","description":"Search for a pattern in file contents within a directory. Returns matching lines with file paths and line numbers. Limited to 50 matches.","parameters":{"type":"object","properties":{"pattern":{"type":"string","description":"Literal text to search for"},"path":{"type":"string","description":"Directory to search in (default: current directory)"}},"required":["pattern"]}}},{"type":"function","function":{"name":"glob","description":"Find files matching a glob pattern (e.g. **/*.zig, src/*.ts). Returns matching file paths. Limited to 100 results.","parameters":{"type":"object","properties":{"pattern":{"type":"string","description":"Glob pattern to match (supports *, **, and ?)"},"path":{"type":"string","description":"Directory to search in (default: current directory)"}},"required":["pattern"]}}},{"type":"function","function":{"name":"write","description":"Create or overwrite a file with the given content. Creates parent directories if needed. Use this to create new files or replace entire file contents.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"File path to write to"},"content":{"type":"string","description":"The full content to write to the file"}},"required":["path","content"]}}},{"type":"function","function":{"name":"edit","description":"Edit a file by replacing an exact string with new content. The old_string must match exactly once in the file. Use this for targeted edits without rewriting the whole file.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"File path to edit"},"old_string":{"type":"string","description":"The exact text to find in the file"},"new_string":{"type":"string","description":"The text to replace old_string with"}},"required":["path","old_string","new_string"]}}},{"type":"function","function":{"name":"delete","description":"Delete a file or empty directory. Fails if the directory is not empty.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"File or empty directory path to delete"}},"required":["path"]}}},{"type":"function","function":{"name":"mkdir","description":"Create a directory, including parent directories if needed.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Directory path to create"}},"required":["path"]}}},{"type":"function","function":{"name":"rename","description":"Rename or move a file or directory.","parameters":{"type":"object","properties":{"old_path":{"type":"string","description":"Current file or directory path"},"new_path":{"type":"string","description":"New file or directory path"}},"required":["old_path","new_path"]}}},{"type":"function","function":{"name":"bash","description":"Run a shell command and return stdout and stderr. Use for running tests, builds, git commands, or any CLI tool. Output is limited to 20KB.","parameters":{"type":"object","properties":{"command":{"type":"string","description":"The shell command to execute"},"cwd":{"type":"string","description":"Working directory (default: current directory)"}},"required":["command"]}}},{"type":"function","function":{"name":"websearch","description":"Search the web for current information. Returns search results with titles, URLs, and content highlights.","parameters":{"type":"object","properties":{"query":{"type":"string","description":"The search query"}},"required":["query"]}}},{"type":"function","function":{"name":"webfetch","description":"Fetch content from a URL and return it as text. Useful for reading web pages, API docs, or JSON endpoints. Output limited to 20KB.","parameters":{"type":"object","properties":{"url":{"type":"string","description":"The HTTP or HTTPS URL to fetch"}},"required":["url"]}}}]
    ;
}

/// Returns the display verb for a tool (past tense, e.g. "Read", "Searched").
pub fn toolVerb(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "read")) return "Read";
    if (std.mem.eql(u8, name, "list_files")) return "Listed";
    if (std.mem.eql(u8, name, "grep")) return "Searched";
    if (std.mem.eql(u8, name, "glob")) return "Found";
    if (std.mem.eql(u8, name, "write")) return "Wrote";
    if (std.mem.eql(u8, name, "edit")) return "Edited";
    if (std.mem.eql(u8, name, "delete")) return "Deleted";
    if (std.mem.eql(u8, name, "mkdir")) return "Created dir";
    if (std.mem.eql(u8, name, "rename")) return "Renamed";
    if (std.mem.eql(u8, name, "bash")) return "Ran";
    if (std.mem.eql(u8, name, "websearch")) return "Searched";
    if (std.mem.eql(u8, name, "webfetch")) return "Fetched";
    return name;
}

/// Returns the primary argument value for display (file path, search query, URL).
pub fn toolDetail(name: []const u8, arguments: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "read")) return extractStringArg(arguments, "path") orelse "";
    if (std.mem.eql(u8, name, "list_files")) return extractStringArg(arguments, "path") orelse "";
    if (std.mem.eql(u8, name, "grep")) return extractStringArg(arguments, "pattern") orelse "";
    if (std.mem.eql(u8, name, "glob")) return extractStringArg(arguments, "pattern") orelse "";
    if (std.mem.eql(u8, name, "write")) return extractStringArg(arguments, "path") orelse "";
    if (std.mem.eql(u8, name, "edit")) return extractStringArg(arguments, "path") orelse "";
    if (std.mem.eql(u8, name, "delete")) return extractStringArg(arguments, "path") orelse "";
    if (std.mem.eql(u8, name, "mkdir")) return extractStringArg(arguments, "path") orelse "";
    if (std.mem.eql(u8, name, "rename")) return extractStringArg(arguments, "old_path") orelse "";
    if (std.mem.eql(u8, name, "bash")) return extractStringArg(arguments, "command") orelse "";
    if (std.mem.eql(u8, name, "websearch")) return extractStringArg(arguments, "query") orelse "";
    if (std.mem.eql(u8, name, "webfetch")) return extractStringArg(arguments, "url") orelse "";
    return "";
}

/// Returns a short singular label for the tool type used in the summary breakdown.
pub fn toolTypeLabel(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "read")) return "read";
    if (std.mem.eql(u8, name, "list_files")) return "list";
    if (std.mem.eql(u8, name, "grep")) return "search";
    if (std.mem.eql(u8, name, "glob")) return "search";
    if (std.mem.eql(u8, name, "write")) return "write";
    if (std.mem.eql(u8, name, "edit")) return "edit";
    if (std.mem.eql(u8, name, "delete")) return "delete";
    if (std.mem.eql(u8, name, "mkdir")) return "mkdir";
    if (std.mem.eql(u8, name, "rename")) return "rename";
    if (std.mem.eql(u8, name, "bash")) return "bash";
    if (std.mem.eql(u8, name, "websearch")) return "search";
    if (std.mem.eql(u8, name, "webfetch")) return "fetch";
    return "tool";
}

/// Execute a tool call, returning the result text (arena-allocated).
pub fn execute(
    arena: std.mem.Allocator,
    io: std.Io,
    call: ToolCall,
) !ToolResult {
    if (std.mem.eql(u8, call.name, "read")) {
        return execRead(arena, io, call.arguments);
    }
    if (std.mem.eql(u8, call.name, "list_files")) {
        return execListFiles(arena, io, call.arguments);
    }
    if (std.mem.eql(u8, call.name, "grep")) {
        return execGrep(arena, io, call.arguments);
    }
    if (std.mem.eql(u8, call.name, "glob")) {
        return execGlob(arena, io, call.arguments);
    }
    if (std.mem.eql(u8, call.name, "write")) {
        return execWrite(arena, io, call.arguments);
    }
    if (std.mem.eql(u8, call.name, "edit")) {
        return execEdit(arena, io, call.arguments);
    }
    if (std.mem.eql(u8, call.name, "delete")) {
        return execDelete(arena, io, call.arguments);
    }
    if (std.mem.eql(u8, call.name, "mkdir")) {
        return execMkdir(arena, io, call.arguments);
    }
    if (std.mem.eql(u8, call.name, "rename")) {
        return execRename(arena, io, call.arguments);
    }
    if (std.mem.eql(u8, call.name, "bash")) {
        return execBash(arena, io, call.arguments);
    }
    if (std.mem.eql(u8, call.name, "websearch")) {
        return execWebSearch(arena, io, call.arguments);
    }
    if (std.mem.eql(u8, call.name, "webfetch")) {
        return execWebFetch(arena, io, call.arguments);
    }
    return .{
        .name = call.name,
        .content = try arena.dupe(u8, "Unknown tool"),
    };
}

// --- Argument extraction helpers ---

fn extractStringArg(json: []const u8, key: []const u8) ?[]const u8 {
    // Search for "key":"value" pattern
    var search_buf: [256]u8 = undefined;
    const pattern = std.fmt.bufPrint(&search_buf, "\"{s}\":\"", .{key}) catch return null;

    var start = std.mem.indexOf(u8, json, pattern) orelse return null;
    start += pattern.len;

    var i = start;
    while (i < json.len) : (i += 1) {
        if (json[i] == '\\') {
            i += 1;
            continue;
        }
        if (json[i] == '"') break;
    }
    if (i >= json.len) return null;
    return json[start..i];
}

fn extractIntArg(json: []const u8, key: []const u8) ?i64 {
    var search_buf: [256]u8 = undefined;
    const pattern = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{key}) catch return null;

    var start = std.mem.indexOf(u8, json, pattern) orelse return null;
    start += pattern.len;

    // Skip whitespace
    while (start < json.len and (json[start] == ' ' or json[start] == '\t')) start += 1;
    if (start >= json.len) return null;

    var end = start;
    if (json[start] == '-') end += 1;
    while (end < json.len and json[end] >= '0' and json[end] <= '9') end += 1;
    if (end == start) return null;

    return std.fmt.parseInt(i64, json[start..end], 10) catch null;
}

// --- Tool implementations ---

fn execRead(arena: std.mem.Allocator, io: std.Io, args: []const u8) !ToolResult {
    const path = extractStringArg(args, "path") orelse return .{
        .name = "read",
        .content = try arena.dupe(u8, "Error: missing 'path' argument"),
    };
    const offset = extractIntArg(args, "offset") orelse 1;
    // Cap line limit to prevent dumping huge files
    const limit_requested = extractIntArg(args, "limit") orelse 200;
    const limit = @min(limit_requested, 200);

    const cwd = std.Io.Dir.cwd();
    // Cap file read to 256KB to prevent memory exhaustion
    const file_content = cwd.readFileAlloc(io, path, arena, .limited(256 * 1024)) catch |err| {
        const msg = std.fmt.allocPrint(arena, "Error reading {s}: {t}", .{ path, err }) catch "Read error";
        return .{ .name = "read", .content = msg };
    };

    // Apply offset/limit on lines
    var lines: std.ArrayList(u8) = .empty;
    var line_iter = std.mem.splitScalar(u8, file_content, '\n');
    var line_num: i64 = 0;
    var count: i64 = 0;
    var total_bytes: usize = 0;
    const max_bytes = 50 * 1024; // 50KB output cap
    while (line_iter.next()) |line| {
        line_num += 1;
        if (line_num < offset) continue;
        if (count >= limit) break;
        if (total_bytes + line.len > max_bytes) {
            lines.print(arena, "{d}: [output truncated at 50KB limit]\n", .{line_num}) catch {};
            break;
        }
        count += 1;
        total_bytes += line.len + 1;
        try lines.print(arena, "{d}: {s}\n", .{ line_num, line });
    }
    if (count == 0 and line_num == 0) {
        return .{ .name = "read", .content = try arena.dupe(u8, "(empty file)") };
    }
    return .{ .name = "read", .content = lines.items };
}

fn execListFiles(arena: std.mem.Allocator, io: std.Io, args: []const u8) !ToolResult {
    const path = extractStringArg(args, "path") orelse ".";

    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch |err| {
        const msg = std.fmt.allocPrint(arena, "Error opening {s}: {t}", .{ path, err }) catch "Dir error";
        return .{ .name = "list_files", .content = msg };
    };
    defer dir.close(io);

    var iter = dir.iterate();
    var buf: std.ArrayList(u8) = .empty;
    var entry_count: usize = 0;
    const max_entries: usize = 200;

    while (iter.next(io) catch null) |entry| {
        if (entry_count >= max_entries) {
            buf.print(arena, "... (truncated at {d} entries)\n", .{max_entries}) catch {};
            break;
        }
        const kind_str: []const u8 = switch (entry.kind) {
            .directory => "dir ",
            .file => "file",
            else => "other",
        };
        buf.print(arena, "{s}  {s}\n", .{ kind_str, entry.name }) catch {};
        entry_count += 1;
    }
    if (buf.items.len == 0) {
        buf.print(arena, "(empty directory)\n", .{}) catch {};
    }
    return .{ .name = "list_files", .content = buf.items };
}

fn execGrep(arena: std.mem.Allocator, io: std.Io, args: []const u8) !ToolResult {
    const pattern = extractStringArg(args, "pattern") orelse return .{
        .name = "grep",
        .content = try arena.dupe(u8, "Error: missing 'pattern' argument"),
    };
    const path = extractStringArg(args, "path") orelse ".";

    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch |err| {
        const msg = std.fmt.allocPrint(arena, "Error opening {s}: {t}", .{ path, err }) catch "Dir error";
        return .{ .name = "grep", .content = msg };
    };
    defer dir.close(io);

    var buf: std.ArrayList(u8) = .empty;
    var match_count: usize = 0;
    const max_matches: usize = 50;

    try grepDir(arena, io, dir, path, pattern, &buf, &match_count, max_matches);

    if (match_count == 0) {
        buf.print(arena, "No matches found for '{s}'\n", .{pattern}) catch {};
    }
    return .{ .name = "grep", .content = buf.items };
}

fn grepDir(
    arena: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    base_path: []const u8,
    pattern: []const u8,
    buf: *std.ArrayList(u8),
    match_count: *usize,
    max: usize,
) !void {
    var iter = dir.iterate();
    while (iter.next(io) catch null) |entry| {
        if (match_count.* >= max) return;
        if (entry.kind == .directory) {
            // Skip hidden dirs and common large dirs
            if (entry.name[0] == '.') continue;
            if (std.mem.eql(u8, entry.name, "node_modules") or
                std.mem.eql(u8, entry.name, "zig-out") or
                std.mem.eql(u8, entry.name, ".zig-cache")) continue;

            var sub = dir.openDir(io, entry.name, .{ .iterate = true }) catch continue;
            defer sub.close(io);
            const sub_path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ base_path, entry.name });
            try grepDir(arena, io, sub, sub_path, pattern, buf, match_count, max);
        } else if (entry.kind == .file) {
            if (entry.name[0] == '.') continue;
            const file_path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ base_path, entry.name });
            grepFile(arena, io, dir, entry.name, file_path, pattern, buf, match_count, max) catch {};
        }
    }
}

fn grepFile(
    arena: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    name: []const u8,
    display_path: []const u8,
    pattern: []const u8,
    buf: *std.ArrayList(u8),
    match_count: *usize,
    max: usize,
) !void {
    _ = name;
    _ = dir;
    // Actually read the file by name from cwd
    const cwd = std.Io.Dir.cwd();
    const file_content = cwd.readFileAlloc(io, display_path, arena, .limited(256 * 1024)) catch return;

    var line_iter = std.mem.splitScalar(u8, file_content, '\n');
    var line_num: usize = 0;
    while (line_iter.next()) |line| {
        line_num += 1;
        if (std.mem.indexOf(u8, line, pattern) != null) {
            buf.print(arena, "{s}:{d}: {s}\n", .{ display_path, line_num, line }) catch {};
            match_count.* += 1;
            if (match_count.* >= max) return;
        }
    }
}

// --- Editing tools: write, edit, delete, mkdir, rename, bash, glob ---

fn execWrite(arena: std.mem.Allocator, io: std.Io, args: []const u8) !ToolResult {
    const path = extractStringArg(args, "path") orelse return .{
        .name = "write",
        .content = try arena.dupe(u8, "Error: missing 'path' argument"),
    };
    const content = extractStringArg(args, "content") orelse return .{
        .name = "write",
        .content = try arena.dupe(u8, "Error: missing 'content' argument"),
    };

    // Create parent directories if needed.
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len > 0) {
            std.Io.Dir.cwd().createDirPath(io, dir) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => {
                    const msg = std.fmt.allocPrint(arena, "Error creating parent dir for {s}: {t}", .{ path, err }) catch "Write error";
                    return .{ .name = "write", .content = msg };
                },
            };
        }
    }

    std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = content,
    }) catch |err| {
        const msg = std.fmt.allocPrint(arena, "Error writing {s}: {t}", .{ path, err }) catch "Write error";
        return .{ .name = "write", .content = msg };
    };

    const msg = std.fmt.allocPrint(arena, "Wrote {d} bytes to {s}", .{ content.len, path }) catch "OK";
    return .{ .name = "write", .content = msg };
}

fn execEdit(arena: std.mem.Allocator, io: std.Io, args: []const u8) !ToolResult {
    const path = extractStringArg(args, "path") orelse return .{
        .name = "edit",
        .content = try arena.dupe(u8, "Error: missing 'path' argument"),
    };
    const old_string = extractStringArg(args, "old_string") orelse return .{
        .name = "edit",
        .content = try arena.dupe(u8, "Error: missing 'old_string' argument"),
    };
    const new_string = extractStringArg(args, "new_string") orelse return .{
        .name = "edit",
        .content = try arena.dupe(u8, "Error: missing 'new_string' argument"),
    };

    // Read the file.
    const cwd = std.Io.Dir.cwd();
    const content = cwd.readFileAlloc(io, path, arena, .limited(1024 * 1024)) catch |err| {
        const msg = std.fmt.allocPrint(arena, "Error reading {s}: {t}", .{ path, err }) catch "Read error";
        return .{ .name = "edit", .content = msg };
    };

    // Find old_string — must match exactly once.
    const count = std.mem.count(u8, content, old_string);
    if (count == 0) {
        const msg = std.fmt.allocPrint(arena, "Error: old_string not found in {s}", .{path}) catch "Not found";
        return .{ .name = "edit", .content = msg };
    }
    if (count > 1) {
        const msg = std.fmt.allocPrint(arena, "Error: old_string found {d} times in {s} (must be unique)", .{ count, path }) catch "Not unique";
        return .{ .name = "edit", .content = msg };
    }

    // Build the new file content: replace old_string with new_string.
    var result: std.ArrayList(u8) = .empty;
    const idx = std.mem.indexOf(u8, content, old_string).?;
    try result.appendSlice(arena, content[0..idx]);
    try result.appendSlice(arena, new_string);
    try result.appendSlice(arena, content[idx + old_string.len ..]);

    // Write back.
    std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = result.items,
    }) catch |err| {
        const msg = std.fmt.allocPrint(arena, "Error writing {s}: {t}", .{ path, err }) catch "Write error";
        return .{ .name = "edit", .content = msg };
    };

    const msg = std.fmt.allocPrint(arena, "Edited {s}: replaced {d} bytes with {d} bytes", .{ path, old_string.len, new_string.len }) catch "OK";
    return .{ .name = "edit", .content = msg };
}

fn execDelete(arena: std.mem.Allocator, io: std.Io, args: []const u8) !ToolResult {
    const path = extractStringArg(args, "path") orelse return .{
        .name = "delete",
        .content = try arena.dupe(u8, "Error: missing 'path' argument"),
    };

    const cwd = std.Io.Dir.cwd();

    // Try deleting as a file first; if that fails with IsDir, try as empty dir.
    cwd.deleteFile(io, path) catch |err| switch (err) {
        error.IsDir => {
            cwd.deleteDir(io, path) catch |err2| {
                const msg = std.fmt.allocPrint(arena, "Error deleting directory {s}: {t}", .{ path, err2 }) catch "Delete error";
                return .{ .name = "delete", .content = msg };
            };
        },
        else => {
            const msg = std.fmt.allocPrint(arena, "Error deleting {s}: {t}", .{ path, err }) catch "Delete error";
            return .{ .name = "delete", .content = msg };
        },
    };

    const msg = std.fmt.allocPrint(arena, "Deleted {s}", .{path}) catch "OK";
    return .{ .name = "delete", .content = msg };
}

fn execMkdir(arena: std.mem.Allocator, io: std.Io, args: []const u8) !ToolResult {
    const path = extractStringArg(args, "path") orelse return .{
        .name = "mkdir",
        .content = try arena.dupe(u8, "Error: missing 'path' argument"),
    };

    std.Io.Dir.cwd().createDirPath(io, path) catch |err| switch (err) {
        error.PathAlreadyExists => {
            const msg = std.fmt.allocPrint(arena, "Directory already exists: {s}", .{path}) catch "Exists";
            return .{ .name = "mkdir", .content = msg };
        },
        else => {
            const msg = std.fmt.allocPrint(arena, "Error creating {s}: {t}", .{ path, err }) catch "Mkdir error";
            return .{ .name = "mkdir", .content = msg };
        },
    };

    const msg = std.fmt.allocPrint(arena, "Created directory {s}", .{path}) catch "OK";
    return .{ .name = "mkdir", .content = msg };
}

fn execRename(arena: std.mem.Allocator, io: std.Io, args: []const u8) !ToolResult {
    const old_path = extractStringArg(args, "old_path") orelse return .{
        .name = "rename",
        .content = try arena.dupe(u8, "Error: missing 'old_path' argument"),
    };
    const new_path = extractStringArg(args, "new_path") orelse return .{
        .name = "rename",
        .content = try arena.dupe(u8, "Error: missing 'new_path' argument"),
    };

    // Create parent dir of destination if needed.
    if (std.fs.path.dirname(new_path)) |dir| {
        if (dir.len > 0) {
            std.Io.Dir.cwd().createDirPath(io, dir) catch {};
        }
    }

    const cwd = std.Io.Dir.cwd();
    cwd.rename(old_path, cwd, new_path, io) catch |err| {
        const msg = std.fmt.allocPrint(arena, "Error renaming {s} -> {s}: {t}", .{ old_path, new_path, err }) catch "Rename error";
        return .{ .name = "rename", .content = msg };
    };

    const msg = std.fmt.allocPrint(arena, "Renamed {s} -> {s}", .{ old_path, new_path }) catch "OK";
    return .{ .name = "rename", .content = msg };
}

fn execBash(arena: std.mem.Allocator, io: std.Io, args: []const u8) !ToolResult {
    const command = extractStringArg(args, "command") orelse return .{
        .name = "bash",
        .content = try arena.dupe(u8, "Error: missing 'command' argument"),
    };
    const cwd_path = extractStringArg(args, "cwd") orelse ".";
    const cwd_opt: std.process.Child.Cwd = if (std.mem.eql(u8, cwd_path, "."))
        .inherit
    else
        .{ .path = cwd_path };

    // Run via /bin/sh -c to support pipes, redirects, etc.
    const argv = [_][]const u8{ "/bin/sh", "-c", command };

    const result = std.process.run(arena, io, .{
        .argv = @constCast(&argv),
        .cwd = cwd_opt,
        .stdout_limit = .limited(20 * 1024),
        .stderr_limit = .limited(20 * 1024),
    }) catch |err| {
        const msg = std.fmt.allocPrint(arena, "Error running command: {t}", .{err}) catch "Bash error";
        return .{ .name = "bash", .content = msg };
    };

    // Format output with exit code, stdout, and stderr.
    var buf: std.ArrayList(u8) = .empty;
    const exit_code: u8 = switch (result.term) {
        .exited => |c| c,
        else => 1,
    };
    buf.print(arena, "Exit: {d}\n", .{exit_code}) catch {};
    if (result.stdout.len > 0) {
        buf.appendSlice(arena, "stdout:\n") catch {};
        buf.appendSlice(arena, result.stdout) catch {};
        if (result.stdout.len > 0 and result.stdout[result.stdout.len - 1] != '\n')
            buf.appendSlice(arena, "\n") catch {};
    }
    if (result.stderr.len > 0) {
        buf.appendSlice(arena, "stderr:\n") catch {};
        buf.appendSlice(arena, result.stderr) catch {};
        if (result.stderr.len > 0 and result.stderr[result.stderr.len - 1] != '\n')
            buf.appendSlice(arena, "\n") catch {};
    }
    if (buf.items.len == 0) {
        buf.appendSlice(arena, "(no output)") catch {};
    }
    return .{ .name = "bash", .content = buf.items };
}

fn execGlob(arena: std.mem.Allocator, io: std.Io, args: []const u8) !ToolResult {
    const pattern = extractStringArg(args, "pattern") orelse return .{
        .name = "glob",
        .content = try arena.dupe(u8, "Error: missing 'pattern' argument"),
    };
    const path = extractStringArg(args, "path") orelse ".";

    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch |err| {
        const msg = std.fmt.allocPrint(arena, "Error opening {s}: {t}", .{ path, err }) catch "Dir error";
        return .{ .name = "glob", .content = msg };
    };
    defer dir.close(io);

    var buf: std.ArrayList(u8) = .empty;
    var match_count: usize = 0;
    const max_matches: usize = 100;

    globWalk(arena, io, dir, path, pattern, &buf, &match_count, max_matches);

    if (match_count == 0) {
        buf.print(arena, "No files matching '{s}'\n", .{pattern}) catch {};
    }
    return .{ .name = "glob", .content = buf.items };
}

/// Recursively walks a directory, matching file paths against a glob pattern.
fn globWalk(
    arena: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    base_path: []const u8,
    pattern: []const u8,
    buf: *std.ArrayList(u8),
    match_count: *usize,
    max: usize,
) void {
    var iter = dir.iterate();
    while (iter.next(io) catch null) |entry| {
        if (match_count.* >= max) return;
        // Skip hidden and VCS/build dirs
        if (entry.kind == .directory) {
            if (entry.name[0] == '.') continue;
            if (std.mem.eql(u8, entry.name, "node_modules") or
                std.mem.eql(u8, entry.name, "zig-out") or
                std.mem.eql(u8, entry.name, ".git")) continue;

            var sub = dir.openDir(io, entry.name, .{ .iterate = true }) catch continue;
            defer sub.close(io);
            const sub_path = std.fmt.allocPrint(arena, "{s}/{s}", .{ base_path, entry.name }) catch continue;
            globWalk(arena, io, sub, sub_path, pattern, buf, match_count, max);
        } else if (entry.kind == .file) {
            if (entry.name[0] == '.') continue;
            const file_path = std.fmt.allocPrint(arena, "{s}/{s}", .{ base_path, entry.name }) catch continue;
            if (globMatch(pattern, file_path)) {
                buf.print(arena, "{s}\n", .{file_path}) catch {};
                match_count.* += 1;
                if (match_count.* >= max) return;
            }
        }
    }
}

/// Simple glob matcher: supports *, **, and ?.
/// ** matches any number of path segments. * matches within a segment.
fn globMatch(pattern: []const u8, path: []const u8) bool {
    return globMatchHelper(pattern, 0, path, 0);
}

fn globMatchHelper(pat: []const u8, pi: usize, text: []const u8, ti: usize) bool {
    // Check for ** (double-star) — matches any path prefix
    if (pi + 2 < pat.len and pat[pi] == '*' and pat[pi + 1] == '*') {
        // Skip the ** and following / if present
        const rest_start = if (pi + 2 < pat.len and pat[pi + 2] == '/') pi + 3 else pi + 2;
        // Try matching at every position in the text
        var j = ti;
        while (true) {
            if (globMatchHelper(pat, rest_start, text, j)) return true;
            if (j >= text.len) return false;
            j += 1;
        }
    }

    if (pi >= pat.len) return ti >= text.len;
    if (ti >= text.len) {
        // Remaining pattern must be all wildcards
        var k = pi;
        while (k < pat.len and (pat[k] == '*' or pat[k] == '?')) k += 1;
        return k >= pat.len;
    }

    const pc = pat[pi];
    if (pc == '*') {
        // Single * — matches within a segment (not across /)
        // Try zero-length match or consume one char
        if (globMatchHelper(pat, pi + 1, text, ti)) return true;
        if (text[ti] != '/') return globMatchHelper(pat, pi, text, ti + 1);
        return false;
    }
    if (pc == '?') {
        if (text[ti] == '/') return false;
        return globMatchHelper(pat, pi + 1, text, ti + 1);
    }
    if (pc == text[ti]) return globMatchHelper(pat, pi + 1, text, ti + 1);
    return false;
}

fn execWebSearch(arena: std.mem.Allocator, io: std.Io, args: []const u8) !ToolResult {
    const query = extractStringArg(args, "query") orelse return .{
        .name = "websearch",
        .content = try arena.dupe(u8, "Error: missing 'query' argument"),
    };

    // Use Exa MCP endpoint (same as opencode)
    const exa_url = "https://mcp.exa.ai/mcp";

    // Build MCP JSON-RPC request using a buf to avoid fmt brace escaping issues
    var req_buf: std.ArrayList(u8) = .empty;
    try req_buf.appendSlice(arena, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"web_search_exa\",\"arguments\":{\"query\":\"");
    // Escape query for JSON
    for (query) |c| {
        switch (c) {
            '"' => try req_buf.appendSlice(arena, "\\\""),
            '\\' => try req_buf.appendSlice(arena, "\\\\"),
            '\n' => try req_buf.appendSlice(arena, "\\n"),
            else => try req_buf.append(arena, c),
        }
    }
    try req_buf.appendSlice(arena, "\",\"type\":\"auto\",\"numResults\":5,\"livecrawl\":\"fallback\"}}}");
    const req_body = req_buf.items;

    var body: std.Io.Writer.Allocating = .init(arena);
    defer body.deinit();

    const status = http_client.postRaw(arena, io, exa_url, req_body, &body.writer) catch {
        return .{ .name = "websearch", .content = try arena.dupe(u8, "Error: web search request failed") };
    };
    if (@intFromEnum(status) >= 400) {
        const msg = std.fmt.allocPrint(arena, "Error: search returned status {d}", .{@intFromEnum(status)}) catch "Search error";
        return .{ .name = "websearch", .content = msg };
    }

    // Parse the MCP response to extract the text content
    const body_slice = try body.toOwnedSlice();
    const text = parseMcpResponse(arena, body_slice) catch body_slice;
    return .{ .name = "websearch", .content = text };
}

/// Parse MCP JSON-RPC response: {"result":{"content":[{"type":"text","text":"..."}]}}
fn parseMcpResponse(arena: std.mem.Allocator, body: []const u8) ![]const u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, arena, body, .{}) catch return body;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return body;

    const result = root.object.get("result") orelse return body;
    if (result != .object) return body;

    const content = result.object.get("content") orelse return body;
    if (content != .array) return body;

    var buf: std.ArrayList(u8) = .empty;
    for (content.array.items) |item| {
        if (item != .object) continue;
        const text_val = item.object.get("text") orelse continue;
        if (text_val != .string) continue;
        try buf.appendSlice(arena, text_val.string);
    }
    if (buf.items.len == 0) return body;
    return buf.items;
}

fn execWebFetch(arena: std.mem.Allocator, io: std.Io, args: []const u8) !ToolResult {
    const url = extractStringArg(args, "url") orelse return .{
        .name = "webfetch",
        .content = try arena.dupe(u8, "Error: missing 'url' argument"),
    };

    var body: std.Io.Writer.Allocating = .init(arena);
    defer body.deinit();

    const status = http_client.fetchUrl(arena, io, url, &body.writer) catch {
        return .{ .name = "webfetch", .content = try arena.dupe(u8, "Error: fetch failed") };
    };
    if (@intFromEnum(status) >= 400) {
        const msg = std.fmt.allocPrint(arena, "Error: HTTP {d}", .{@intFromEnum(status)}) catch "Fetch error";
        return .{ .name = "webfetch", .content = msg };
    }

    // Strip HTML tags for a clean text output, capped at 20KB
    const body_slice = try body.toOwnedSlice();
    const text = stripHtml(arena, body_slice);
    if (text.len > 20 * 1024) {
        return .{ .name = "webfetch", .content = text[0 .. 20 * 1024] };
    }
    return .{ .name = "webfetch", .content = text };
}

/// Naive HTML-to-text: removes tags, scripts, styles, and collapses whitespace.
fn stripHtml(arena: std.mem.Allocator, html: []const u8) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    var in_tag = false;
    var in_script = false;

    while (i < html.len) {
        if (!in_tag and !in_script) {
            if (i + 7 < html.len and std.mem.eql(u8, html[i .. i + 7], "<script")) {
                in_script = true;
                in_tag = true;
                i += 7;
                continue;
            }
            if (i + 6 < html.len and std.mem.eql(u8, html[i .. i + 6], "<style")) {
                in_script = true;
                in_tag = true;
                i += 6;
                continue;
            }
        }

        if (html[i] == '<') {
            in_tag = true;
            i += 1;
            continue;
        }
        if (html[i] == '>' and in_tag) {
            in_tag = false;
            i += 1;
            continue;
        }

        if (in_script) {
            if (i + 8 < html.len and html[i] == '<' and std.mem.eql(u8, html[i .. i + 8], "</script>")) {
                in_script = false;
                i += 8;
                continue;
            }
            if (i + 7 < html.len and html[i] == '<' and std.mem.eql(u8, html[i .. i + 7], "</style>")) {
                in_script = false;
                i += 7;
                continue;
            }
            i += 1;
            continue;
        }

        if (!in_tag) {
            out.append(arena, html[i]) catch break;
        }
        i += 1;
    }

    // Collapse excessive whitespace
    return out.items;
}

test "extract string arg" {
    const args = "{\"path\":\"/tmp/test.txt\"}";
    const result = extractStringArg(args, "path").?;
    try std.testing.expectEqualStrings("/tmp/test.txt", result);
}

test "extract int arg" {
    const args = "{\"offset\":5,\"limit\":10}";
    try std.testing.expectEqual(@as(i64, 5), extractIntArg(args, "offset").?);
    try std.testing.expectEqual(@as(i64, 10), extractIntArg(args, "limit").?);
}

test "extract missing arg" {
    const args = "{\"foo\":\"bar\"}";
    try std.testing.expect(extractStringArg(args, "path") == null);
}

test "glob match exact" {
    try std.testing.expect(globMatch("foo.zig", "foo.zig"));
    try std.testing.expect(!globMatch("foo.zig", "bar.zig"));
}

test "glob match star" {
    try std.testing.expect(globMatch("*.zig", "foo.zig"));
    try std.testing.expect(globMatch("*.zig", "bar.zig"));
    try std.testing.expect(!globMatch("*.zig", "foo.ts"));
}

test "glob match double star" {
    try std.testing.expect(globMatch("**/*.zig", "src/foo.zig"));
    try std.testing.expect(globMatch("**/*.zig", "src/sub/bar.zig"));
    try std.testing.expect(globMatch("**/*.zig", "foo.zig"));
    try std.testing.expect(!globMatch("**/*.zig", "foo.ts"));
}

test "glob match question mark" {
    try std.testing.expect(globMatch("foo?.zig", "foo1.zig"));
    try std.testing.expect(!globMatch("foo?.zig", "foo12.zig"));
}

const std = @import("std");

/// A chat message: role + content.
pub const Role = enum {
    user,
    assistant,
    system,
    tool,

    pub fn toString(self: Role) []const u8 {
        return switch (self) {
            .user => "user",
            .assistant => "assistant",
            .system => "system",
            .tool => "tool",
        };
    }
};

/// A tool call made by the assistant, to be replayed in subsequent requests.
pub const ToolCallRef = struct {
    id: []const u8,
    name: []const u8,
    arguments: []const u8,
};

pub const Message = struct {
    role: Role,
    content: []const u8,
    /// For assistant messages that triggered tool calls.
    tool_calls: ?[]const ToolCallRef = null,
    /// For tool messages: the tool_call_id this responds to.
    tool_call_id: ?[]const u8 = null,
};

/// On-disk session record.
const SessionRecord = struct {
    id: i64,
    title: []const u8,
    provider: []const u8,
    model: []const u8,
    created_at: []const u8,
    updated_at: []const u8,
};

/// On-disk message record.
const MessageRecord = struct {
    id: i64,
    session_id: i64,
    role: []const u8,
    content: []const u8,
    created_at: []const u8,
};

/// A simple append-only JSON-line store that replaces SQLite.
/// Two files: sessions.jsonl and messages.jsonl in the data directory.
/// Each line is a JSON object. The store is loaded into memory on open,
/// and persisted by rewriting the file (sessions are small).
pub const Session = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    dir: []const u8,
    id: i64 = 0,
    next_session_id: i64 = 1,
    next_message_id: i64 = 1,
    sessions: std.ArrayList(SessionRecord) = .empty,
    messages: std.ArrayList(MessageRecord) = .empty,

    pub fn open(alloc: std.mem.Allocator, io: std.Io, db_path: []const u8) !Session {
        // The db_path passed in is the old SQLite path like ~/.ai/sessions.db.
        // We use its parent directory and store JSONL files there.
        const dir = std.fs.path.dirname(db_path) orelse ".";

        var self = Session{
            .alloc = alloc,
            .io = io,
            .dir = try alloc.dupe(u8, dir),
        };

        try self.loadFromFile();
        return self;
    }

    pub fn close(self: *Session) void {
        for (self.sessions.items) |s| {
            self.alloc.free(s.title);
            self.alloc.free(s.provider);
            self.alloc.free(s.model);
            self.alloc.free(s.created_at);
            self.alloc.free(s.updated_at);
        }
        self.sessions.deinit(self.alloc);
        for (self.messages.items) |m| {
            self.alloc.free(m.role);
            self.alloc.free(m.content);
            self.alloc.free(m.created_at);
        }
        self.messages.deinit(self.alloc);
        self.alloc.free(self.dir);
    }

    fn sessionsPath(self: *Session) ![]u8 {
        return std.fmt.allocPrint(self.alloc, "{s}/sessions.jsonl", .{self.dir});
    }

    fn messagesPath(self: *Session) ![]u8 {
        return std.fmt.allocPrint(self.alloc, "{s}/messages.jsonl", .{self.dir});
    }

    /// Loads both JSONL files into memory.
    fn loadFromFile(self: *Session) !void {
        self.loadSessions() catch {};
        self.loadMessagesFile() catch {};
    }

    fn loadSessions(self: *Session) !void {
        const path = try self.sessionsPath();
        defer self.alloc.free(path);

        var file = std.Io.Dir.cwd().openFile(self.io, path, .{}) catch return;
        defer file.close(self.io);

        const stat = try file.stat(self.io);
        const content = try self.alloc.alloc(u8, stat.size);
        defer self.alloc.free(content);
        _ = file.readPositionalAll(self.io, content, 0) catch return;

        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            const rec = try self.parseSessionLine(line);
            try self.sessions.append(self.alloc, rec);
            if (rec.id >= self.next_session_id) self.next_session_id = rec.id + 1;
        }
    }

    fn loadMessagesFile(self: *Session) !void {
        const path = try self.messagesPath();
        defer self.alloc.free(path);

        var file = std.Io.Dir.cwd().openFile(self.io, path, .{}) catch return;
        defer file.close(self.io);

        const stat = try file.stat(self.io);
        const content = try self.alloc.alloc(u8, stat.size);
        defer self.alloc.free(content);
        _ = file.readPositionalAll(self.io, content, 0) catch return;

        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            const rec = try self.parseMessageLine(line);
            try self.messages.append(self.alloc, rec);
            if (rec.id >= self.next_message_id) self.next_message_id = rec.id + 1;
        }
    }

    /// Parses a single JSON line: {"id":1,"title":"...","provider":"...","model":"...","created_at":"...","updated_at":"..."}
    fn parseSessionLine(self: *Session, line: []const u8) !SessionRecord {
        var rec = SessionRecord{
            .id = 0,
            .title = "",
            .provider = "",
            .model = "",
            .created_at = "",
            .updated_at = "",
        };
        try self.parseJsonFields(line, &.{
            .{ "id", &rec.id },
            .{ "title", &rec.title },
            .{ "provider", &rec.provider },
            .{ "model", &rec.model },
            .{ "created_at", &rec.created_at },
            .{ "updated_at", &rec.updated_at },
        });
        // Deep-copy string fields since `line` is borrowed
        rec.title = try self.alloc.dupe(u8, rec.title);
        rec.provider = try self.alloc.dupe(u8, rec.provider);
        rec.model = try self.alloc.dupe(u8, rec.model);
        rec.created_at = try self.alloc.dupe(u8, rec.created_at);
        rec.updated_at = try self.alloc.dupe(u8, rec.updated_at);
        return rec;
    }

    fn parseMessageLine(self: *Session, line: []const u8) !MessageRecord {
        var rec = MessageRecord{
            .id = 0,
            .session_id = 0,
            .role = "",
            .content = "",
            .created_at = "",
        };
        try self.parseJsonFields(line, &.{
            .{ "id", &rec.id },
            .{ "session_id", &rec.session_id },
            .{ "role", &rec.role },
            .{ "content", &rec.content },
            .{ "created_at", &rec.created_at },
        });
        // Deep-copy string fields
        rec.role = try self.alloc.dupe(u8, rec.role);
        rec.content = try self.alloc.dupe(u8, rec.content);
        rec.created_at = try self.alloc.dupe(u8, rec.created_at);
        return rec;
    }

    /// Generic JSON field extractor for flat objects with string and integer fields.
    /// `fields` is a tuple of (key_name, pointer_to_field) where the pointer
    /// points to either []const u8 or i64.
    fn parseJsonFields(self: *Session, line: []const u8, fields: anytype) !void {
        _ = self;
        var pos: usize = 0;
        while (pos < line.len) {
            // Find key
            const key_start = std.mem.indexOfPos(u8, line, pos, "\"") orelse break;
            const key_end = std.mem.indexOfPos(u8, line, key_start + 1, "\"") orelse break;
            const key = line[key_start + 1 .. key_end];
            pos = key_end + 1;

            // Find colon
            const colon = std.mem.indexOfPos(u8, line, pos, ":") orelse break;
            pos = colon + 1;
            // Skip whitespace
            while (pos < line.len and (line[pos] == ' ' or line[pos] == '\t')) pos += 1;
            if (pos >= line.len) break;

            // Determine value type
            if (line[pos] == '"') {
                // String value
                const val_start = pos + 1;
                var val_end = val_start;
                while (val_end < line.len) {
                    if (line[val_end] == '\\') {
                        val_end += 2;
                        continue;
                    }
                    if (line[val_end] == '"') break;
                    val_end += 1;
                }
                const raw_val = line[val_start..val_end];

                inline for (fields) |f| {
                    if (std.mem.eql(u8, key, f[0])) {
                        if (@TypeOf(f[1].*) == []const u8) {
                            f[1].* = raw_val;
                        }
                    }
                }
                pos = val_end + 1;
            } else {
                // Number value (i64)
                var num_end = pos;
                while (num_end < line.len and line[num_end] != ',' and line[num_end] != '}') num_end += 1;
                const num_str = std.mem.trim(u8, line[pos..num_end], " \t");

                inline for (fields) |f| {
                    if (std.mem.eql(u8, key, f[0])) {
                        if (@TypeOf(f[1].*) == i64) {
                            f[1].* = std.fmt.parseInt(i64, num_str, 10) catch 0;
                        }
                    }
                }
                pos = num_end;
            }
        }
    }

    fn timestamp(self: *Session) ![]u8 {
        const ts = std.Io.Timestamp.now(self.io, .real);
        const epoch_secs = ts.toSeconds();
        return self.formatDatetime(epoch_secs);
    }

    /// Converts epoch seconds to "YYYY-MM-DD HH:MM:SS" string.
    fn formatDatetime(self: *Session, epoch_secs: i64) ![]u8 {
        const days = @divTrunc(epoch_secs, 86400);
        const secs_in_day = @mod(epoch_secs, 86400);
        const hour = @divTrunc(secs_in_day, 3600);
        const min = @divTrunc(@mod(secs_in_day, 3600), 60);
        const sec = @mod(secs_in_day, 60);

        // Convert days since epoch to date (algorithm from Howard Hinnant)
        const z = days + 719468;
        const era = @divTrunc(if (z >= 0) z else z - 146096, 146097);
        const doe = z - era * 146097;
        const yoe = @divTrunc(doe - @divTrunc(doe, 1460) + @divTrunc(doe, 36524) - @divTrunc(doe, 146096), 365);
        const y = yoe + era * 400;
        const doy = doe - (365 * yoe + @divTrunc(yoe, 4) - @divTrunc(yoe, 100));
        const mp = @divTrunc(5 * doy + 2, 153);
        const d = doy - @divTrunc(153 * mp + 2, 5) + 1;
        const m = if (mp < 10) mp + 3 else mp - 9;
        const year = if (m <= 2) y + 1 else y;

        return std.fmt.allocPrint(self.alloc, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
            @as(u32, @intCast(year)), @as(u32, @intCast(m)), @as(u32, @intCast(d)),
            @as(u32, @intCast(hour)), @as(u32, @intCast(min)), @as(u32, @intCast(sec)),
        });
    }

    pub fn createSession(self: *Session, title: []const u8, provider_name: []const u8, model: []const u8) !i64 {
        const ts = try self.timestamp();
        const id = self.next_session_id;
        self.next_session_id += 1;

        const rec = SessionRecord{
            .id = id,
            .title = try self.alloc.dupe(u8, title),
            .provider = try self.alloc.dupe(u8, provider_name),
            .model = try self.alloc.dupe(u8, model),
            .created_at = ts,
            .updated_at = try self.alloc.dupe(u8, ts),
        };
        try self.sessions.append(self.alloc, rec);
        try self.persistSessions();
        return id;
    }

    pub fn resumeLast(self: *Session) !?i64 {
        if (self.sessions.items.len == 0) return null;

        // Find session with the highest updated_at (string comparison works for ISO format)
        var best_id: i64 = self.sessions.items[0].id;
        var best_ts: []const u8 = self.sessions.items[0].updated_at;
        for (self.sessions.items[1..]) |s| {
            if (std.mem.order(u8, s.updated_at, best_ts) == .gt) {
                best_id = s.id;
                best_ts = s.updated_at;
            }
        }
        return best_id;
    }

    pub fn resumeById(self: *Session, id: i64) !bool {
        for (self.sessions.items) |s| {
            if (s.id == id) return true;
        }
        return false;
    }

    pub fn addMessage(self: *Session, session_id: i64, role: Role, content: []const u8) !void {
        const ts = try self.timestamp();
        const id = self.next_message_id;
        self.next_message_id += 1;

        const rec = MessageRecord{
            .id = id,
            .session_id = session_id,
            .role = try self.alloc.dupe(u8, role.toString()),
            .content = try self.alloc.dupe(u8, content),
            .created_at = ts,
        };
        try self.messages.append(self.alloc, rec);

        // Update session's updated_at
        for (self.sessions.items) |*s| {
            if (s.id == session_id) {
                self.alloc.free(s.updated_at);
                s.updated_at = try self.alloc.dupe(u8, ts);
                break;
            }
        }

        // Append-only: just append the message line
        try self.appendMessage(rec);
        try self.persistSessions();
    }

    /// Load all messages for a session into the provided allocator.
    /// Returns an owned slice of Message structs (content is owned).
    pub fn loadMessages(self: *Session, session_id: i64) ![]Message {
        var list: std.ArrayList(Message) = .empty;
        defer list.deinit(self.alloc);

        for (self.messages.items) |m| {
            if (m.session_id != session_id) continue;

            const role: Role = if (std.mem.eql(u8, m.role, "user"))
                .user
            else if (std.mem.eql(u8, m.role, "assistant"))
                .assistant
            else
                .system;

            const content = try self.alloc.dupe(u8, m.content);
            try list.append(self.alloc, .{ .role = role, .content = content });
        }

        return try list.toOwnedSlice(self.alloc);
    }

    pub fn freeMessages(self: *Session, messages: []Message) void {
        for (messages) |m| self.alloc.free(m.content);
        self.alloc.free(messages);
    }

    pub fn listSessions(self: *Session, io: std.Io) !void {
        const stdout = std.Io.File.stdout();
        var bw: [4096]u8 = undefined;
        var w = stdout.writer(io, &bw);

        w.interface.print("  ID  Title                          Provider         Model\n", .{}) catch {};
        w.interface.print("  --  -----                          --------         -----\n", .{}) catch {};

        // Sort by updated_at descending (in-place not needed, just iterate)
        var indices = try self.alloc.alloc(usize, self.sessions.items.len);
        defer self.alloc.free(indices);
        for (indices, 0..) |*idx, i| idx.* = i;

        // Simple selection sort by updated_at descending
        for (indices, 0..) |_, i| {
            var max_idx = i;
            for (indices[i + 1 ..], i + 1..) |_, j| {
                if (std.mem.order(u8, self.sessions.items[indices[j]].updated_at, self.sessions.items[indices[max_idx]].updated_at) == .gt) {
                    max_idx = j;
                }
            }
            const tmp = indices[i];
            indices[i] = indices[max_idx];
            indices[max_idx] = tmp;
        }

        const limit = @min(indices.len, 20);
        for (indices[0..limit]) |idx| {
            const s = self.sessions.items[idx];
            w.interface.print("  {d:<3} {s:<30} {s:<16} {s}\n", .{ @as(u64, @intCast(s.id)), s.title, s.provider, s.model }) catch {};
        }
        w.flush() catch {};
    }

    pub fn setSessionTitle(self: *Session, session_id: i64, title: []const u8) !void {
        for (self.sessions.items) |*s| {
            if (s.id == session_id) {
                self.alloc.free(s.title);
                s.title = try self.alloc.dupe(u8, title);
                try self.persistSessions();
                return;
            }
        }
    }

    /// Rewrites the entire sessions.jsonl file.
    fn persistSessions(self: *Session) !void {
        const path = try self.sessionsPath();
        defer self.alloc.free(path);

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.alloc);

        for (self.sessions.items) |s| {
            try buf.print(self.alloc, "{{\"id\":{d},\"title\":", .{s.id});
            try writeJsonString(self.alloc, &buf, s.title);
            try buf.appendSlice(self.alloc, ",\"provider\":");
            try writeJsonString(self.alloc, &buf, s.provider);
            try buf.appendSlice(self.alloc, ",\"model\":");
            try writeJsonString(self.alloc, &buf, s.model);
            try buf.appendSlice(self.alloc, ",\"created_at\":");
            try writeJsonString(self.alloc, &buf, s.created_at);
            try buf.appendSlice(self.alloc, ",\"updated_at\":");
            try writeJsonString(self.alloc, &buf, s.updated_at);
            try buf.appendSlice(self.alloc, "}\n");
        }

        try std.Io.Dir.cwd().writeFile(self.io, .{
            .sub_path = path,
            .data = buf.items,
        });
    }

    /// Appends a single message line to messages.jsonl.
    fn appendMessage(self: *Session, rec: MessageRecord) !void {
        const path = try self.messagesPath();
        defer self.alloc.free(path);

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.alloc);

        try buf.print(self.alloc, "{{\"id\":{d},\"session_id\":{d},\"role\":", .{ rec.id, rec.session_id });
        try writeJsonString(self.alloc, &buf, rec.role);
        try buf.appendSlice(self.alloc, ",\"content\":");
        try writeJsonString(self.alloc, &buf, rec.content);
        try buf.appendSlice(self.alloc, ",\"created_at\":");
        try writeJsonString(self.alloc, &buf, rec.created_at);
        try buf.appendSlice(self.alloc, "}\n");

        // Append to file (create if not exists)
        var file = std.Io.Dir.cwd().createFile(self.io, path, .{}) catch |err| switch (err) {
            error.PathAlreadyExists => try std.Io.Dir.cwd().openFile(self.io, path, .{ .mode = .read_write }),
            else => return err,
        };
        defer file.close(self.io);

        // Append at end of file
        const stat = try file.stat(self.io);
        try file.writePositionalAll(self.io, buf.items, stat.size);
    }
};

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

test "session create and load messages" {
    // Use a temp directory
    const tmp_dir = "/tmp/io-test-sessions";
    const tio = std.testing.io;
    _ = std.Io.Dir.cwd().deleteTree(tio, tmp_dir) catch {};
    std.Io.Dir.cwd().createDirPath(tio, tmp_dir) catch {};

    const db_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/sessions.db", .{tmp_dir});
    defer std.testing.allocator.free(db_path);

    var sess = try Session.open(std.testing.allocator, tio, db_path);
    defer {
        sess.close();
        _ = std.Io.Dir.cwd().deleteTree(tio, tmp_dir) catch {};
    }

    const id = try sess.createSession("test", "openai", "gpt-4o");
    try sess.addMessage(id, .user, "hello");
    try sess.addMessage(id, .assistant, "hi there");

    const messages = try sess.loadMessages(id);
    defer sess.freeMessages(messages);

    try std.testing.expectEqual(@as(usize, 2), messages.len);
    try std.testing.expectEqual(Role.user, messages[0].role);
    try std.testing.expectEqualStrings("hello", messages[0].content);
    try std.testing.expectEqualStrings("hi there", messages[1].content);
}

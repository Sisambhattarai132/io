const std = @import("std");

/// Renders a single line of markdown to ANSI-formatted text, appending to buf.
/// `in_code_block` tracks whether we're inside a ``` fence (persists across calls).
/// Matches fx's rendering style: 2-space indent, gray inline code.
pub fn renderLine(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), in_code_block: *bool, line: []const u8) !void {
    // fx style: every line gets a 2-space indent
    const indent = "  ";

    if (in_code_block.*) {
        if (std.mem.startsWith(u8, line, "```")) {
            in_code_block.* = false;
            try buf.appendSlice(alloc, "\x1b[0m");
        } else {
            try buf.appendSlice(alloc, indent);
            try buf.appendSlice(alloc, "  "); // extra indent for code block body
            try buf.appendSlice(alloc, line);
        }
        return;
    }

    // Code block start
    if (std.mem.startsWith(u8, line, "```")) {
        in_code_block.* = true;
        try buf.appendSlice(alloc, "\x1b[2m");
        return;
    }

    // Headers
    if (std.mem.startsWith(u8, line, "### ")) {
        try buf.appendSlice(alloc, indent);
        try buf.appendSlice(alloc, "\x1b[1;35m");
        try buf.appendSlice(alloc, line[4..]);
        try buf.appendSlice(alloc, "\x1b[0m");
        return;
    }
    if (std.mem.startsWith(u8, line, "## ")) {
        try buf.appendSlice(alloc, indent);
        try buf.appendSlice(alloc, "\x1b[1;34m");
        try buf.appendSlice(alloc, line[3..]);
        try buf.appendSlice(alloc, "\x1b[0m");
        return;
    }
    if (std.mem.startsWith(u8, line, "# ")) {
        try buf.appendSlice(alloc, indent);
        try buf.appendSlice(alloc, "\x1b[1;36m");
        try buf.appendSlice(alloc, line[2..]);
        try buf.appendSlice(alloc, "\x1b[0m");
        return;
    }

    // Bullet list
    if (std.mem.startsWith(u8, line, "- ") or std.mem.startsWith(u8, line, "* ")) {
        try buf.appendSlice(alloc, indent);
        try buf.appendSlice(alloc, "\x1b[2m• \x1b[0m");
        try renderInline(alloc, buf, line[2..]);
        return;
    }

    // Numbered list: "1. ", "2. ", etc.
    var num_end: usize = 0;
    while (num_end < line.len and std.ascii.isDigit(line[num_end])) num_end += 1;
    if (num_end > 0 and num_end + 1 < line.len and
        line[num_end] == '.' and line[num_end + 1] == ' ')
    {
        try buf.appendSlice(alloc, indent);
        try buf.appendSlice(alloc, "\x1b[2m");
        try buf.appendSlice(alloc, line[0..num_end]);
        try buf.appendSlice(alloc, ". \x1b[0m");
        try renderInline(alloc, buf, line[num_end + 2 ..]);
        return;
    }

    // Regular line
    try buf.appendSlice(alloc, indent);
    try renderInline(alloc, buf, line);
}

/// Renders inline markdown: **bold**, `code`, *italic*, [text](url).
fn renderInline(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), text: []const u8) !void {
    var i: usize = 0;
    while (i < text.len) {
        // Bold: **text**
        if (i + 1 < text.len and text[i] == '*' and text[i + 1] == '*') {
            if (std.mem.indexOf(u8, text[i + 2 ..], "**")) |close| {
                try buf.appendSlice(alloc, "\x1b[1m");
                try renderInline(alloc, buf, text[i + 2 .. i + 2 + close]);
                try buf.appendSlice(alloc, "\x1b[0m");
                i = i + 2 + close + 2;
                continue;
            }
        }
        // Inline code: `text` — fx uses gray (38;5;245)
        if (text[i] == '`') {
            if (std.mem.indexOfScalar(u8, text[i + 1 ..], '`')) |close| {
                try buf.appendSlice(alloc, "\x1b[38;5;245m");
                try buf.appendSlice(alloc, text[i + 1 .. i + 1 + close]);
                try buf.appendSlice(alloc, "\x1b[0m");
                i = i + 1 + close + 1;
                continue;
            }
        }
        // Italic: *text* (but not **)
        if (text[i] == '*' and (i + 1 >= text.len or text[i + 1] != '*')) {
            if (std.mem.indexOfScalar(u8, text[i + 1 ..], '*')) |close| {
                if (close > 0) {
                    try buf.appendSlice(alloc, "\x1b[3m");
                    try buf.appendSlice(alloc, text[i + 1 .. i + 1 + close]);
                    try buf.appendSlice(alloc, "\x1b[0m");
                    i = i + 1 + close + 1;
                    continue;
                }
            }
        }
        // Link: [text](url)
        if (text[i] == '[') {
            if (std.mem.indexOfScalar(u8, text[i + 1 ..], ']')) |bracket_close| {
                const link_text = text[i + 1 .. i + 1 + bracket_close];
                const after = i + 1 + bracket_close + 1;
                if (after < text.len and text[after] == '(') {
                    if (std.mem.indexOfScalar(u8, text[after + 1 ..], ')')) |paren_close| {
                        const url = text[after + 1 .. after + 1 + paren_close];
                        try buf.appendSlice(alloc, "\x1b[4m");
                        try buf.appendSlice(alloc, link_text);
                        try buf.appendSlice(alloc, "\x1b[0m\x1b[2m (");
                        try buf.appendSlice(alloc, url);
                        try buf.appendSlice(alloc, ")\x1b[0m");
                        i = after + 1 + paren_close + 1;
                        continue;
                    }
                }
            }
        }
        // Regular character
        try buf.append(alloc, text[i]);
        i += 1;
    }
}

/// Renders a full text block as markdown (non-streaming).
pub fn render(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), text: []const u8) !void {
    var in_code_block = false;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        try renderLine(alloc, buf, &in_code_block, line);
        try buf.append(alloc, '\n');
    }
    if (in_code_block) {
        try buf.appendSlice(alloc, "\x1b[0m");
    }
}

/// Hard-wraps rendered ANSI text to fit `width` columns, re-applying a
/// 2-space indent on continuation lines so wrapped text stays aligned with
/// the first line's padding. ANSI escape sequences are passed through without
/// counting toward the visible width.
pub fn wrapText(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), text: []const u8, width: usize) !void {
    const indent = "  ";
    const wrap_w: usize = if (width > 4) width - 2 else 78; // leave room for indent

    var line_iter = std.mem.splitScalar(u8, text, '\n');
    var first_line = true;
    while (line_iter.next()) |line| {
        if (!first_line) try buf.append(alloc, '\n');
        first_line = false;
        try wrapLine(alloc, buf, line, indent, wrap_w);
    }
}

/// Wraps a single rendered line (may contain ANSI escapes) to wrap_w visible
/// columns, inserting indent + continuation on wrapped portions.
fn wrapLine(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), line: []const u8, indent: []const u8, wrap_w: usize) !void {
    var col: usize = 0;
    var i: usize = 0;
    var at_line_start = true;

    while (i < line.len) {
        // ANSI escape sequence: pass through without counting width
        if (line[i] == 0x1b) {
            const start = i;
            if (i + 1 < line.len and line[i + 1] == '[') {
                i += 2;
                while (i < line.len and !((line[i] >= 0x40 and line[i] <= 0x7e))) i += 1;
                if (i < line.len) i += 1; // consume final byte
            } else if (i + 1 < line.len) {
                // 2-byte escape like \x1b7
                i += 2;
            } else {
                i += 1;
            }
            try buf.appendSlice(alloc, line[start..i]);
            continue;
        }

        // Measure one character (handle UTF-8 continuation bytes)
        const ch_start = i;
        if (line[i] < 0x80) {
            i += 1;
        } else if (line[i] >= 0xf0) {
            i += 4;
        } else if (line[i] >= 0xe0) {
            i += 3;
        } else {
            i += 2;
        }
        if (i > line.len) i = line.len;
        const ch = line[ch_start..i];

        // Check if we need to wrap (before writing this char)
        if (!at_line_start and col >= wrap_w) {
            try buf.append(alloc, '\n');
            try buf.appendSlice(alloc, indent);
            col = 2; // indent width
        }

        try buf.appendSlice(alloc, ch);
        col += 1;
        at_line_start = false;
    }
}

test "render bold" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try renderInline(std.testing.allocator, &buf, "**hello**");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\x1b[1mhello\x1b[0m") != null);
}

test "render code span" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try renderInline(std.testing.allocator, &buf, "foo `bar` baz");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\x1b[33mbar\x1b[0m") != null);
}

test "render header" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    var icb = false;
    try renderLine(std.testing.allocator, &buf, &icb, "# Title");
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "\x1b[1;36mTitle\x1b[0m") != null);
}

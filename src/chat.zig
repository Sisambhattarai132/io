const std = @import("std");
const provider = @import("provider.zig");
const config_mod = @import("config.zig");
const session = @import("session.zig");
const json = @import("json.zig");
const http_client = @import("http_client.zig");
const response = @import("response.zig");
const tools = @import("tools.zig");
const spinner_mod = @import("spinner.zig");
const markdown = @import("markdown.zig");
const registry = @import("registry.zig");
const term = @import("term.zig");
const compact = @import("compact.zig");

const MAX_TOOL_ITERATIONS = 10;

/// Pastes shorter than this are shown inline; longer ones collapse to a
/// `[Pasted text, N lines]` placeholder. Mirrors fx's paste threshold.
const LARGE_PASTE_THRESHOLD: usize = 1000;

// ── Terminal raw mode (cross-platform via term.zig) ─────────────────────────

const TIMEOUT_MS: u32 = 100;

/// Returns the terminal width in columns, or 80 if it can't be determined.
fn termWidth() usize {
    return term.width();
}

/// Returns the terminal height in rows, or 24 if it can't be determined.
fn termHeight() usize {
    return term.height();
}

const SpinLock = struct {
    flag: std.atomic.Value(bool) = .{ .raw = false },

    fn lock(self: *SpinLock) void {
        while (self.flag.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
            std.Thread.yield() catch {};
        }
    }

    fn unlock(self: *SpinLock) void {
        self.flag.store(false, .release);
    }
};

/// Slash commands available in the REPL prompt, with short descriptions shown
/// in the autocomplete dropdown.
fn slashCommands() []const []const u8 {
    return &.{
        "/help", "/exit", "/quit", "/model", "/models", "/login", "/logout", "/clear", "/compact",
    };
}

fn slashDescriptions() []const []const u8 {
    return &.{
        "Show help",
        "Exit the app",
        "Quit the app",
        "Switch model",
        "List models",
        "Log in",
        "Log out",
        "Clear screen",
        "Compact context",
    };
}

// ── LiveUI: persistent prompt + streaming output above the prompt ───────────

/// Two-region terminal:
///   - Agent output scrolls above
///   - `❯` input prompt pinned at the bottom, always editable
/// A spinlock coordinates writes from the agent thread and the input reader.
const LiveUI = struct {
    alloc: std.mem.Allocator,
    out: *std.Io.File.Writer,
    mu: SpinLock = .{},
    input: std.ArrayList(u8) = .empty,
    /// Byte offset of the cursor within `input` (0 = start, len = end).
    cursor: usize = 0,
    /// When true, the prompt line shows `❯ ⠋` (spinner) instead of user text.
    thinking: bool = false,
    think_frame: usize = 0,
    /// When >0, input contains pasted multi-line text; show compact indicator.
    paste_lines: usize = 0,
    /// How many terminal rows the current prompt box occupies (0 = not drawn yet).
    prompt_rows: usize = 0,
    /// How many menu rows were drawn last time (for erasing).
    menu_rows_drawn: usize = 0,
    /// Slash-command dropdown menu state.
    menu_open: bool = false,
    menu_count: usize = 0,
    menu_selected: usize = 0,
    menu_matches: [16]usize = undefined,

    /// Erases all lines occupied by the prompt box AND dropdown menu.
    /// Cursor is on the top row of the old box after erasing.
    /// Resets prompt_rows to 0 so drawPromptLocked won't double-erase.
    fn clearPromptLocked(self: *LiveUI) void {
        if (self.prompt_rows > 0) {
            // Erase old menu rows below the bottom border first, if any.
            if (self.menu_rows_drawn > 0) {
                // Move down to bottom border, then down through each menu row.
                self.out.interface.writeAll("\x1b[1B\r") catch {};
                for (0..self.menu_rows_drawn) |_| {
                    self.out.interface.writeAll("\x1b[1B\r\x1b[2K") catch {};
                }
                // Move back up to the bottom border.
                for (0..self.menu_rows_drawn) |_| {
                    self.out.interface.writeAll("\x1b[1A\r") catch {};
                }
                // Erase the bottom border.
                self.out.interface.writeAll("\x1b[2K") catch {};
            } else {
                // No menu: move down to bottom border and erase it.
                self.out.interface.writeAll("\x1b[1B\r\x1b[2K") catch {};
            }
            // Erase remaining box lines upward (bottom border already erased).
            var i: usize = 1;
            while (i < self.prompt_rows) : (i += 1) {
                self.out.interface.writeAll("\x1b[1A\r\x1b[2K") catch {};
            }
            self.prompt_rows = 0;
            self.menu_rows_drawn = 0;
        }
    }

    /// Writes agent text: clears the prompt box, writes the text with a trailing
    /// newline, then redraws the prompt on the next line.
    fn writeAgent(self: *LiveUI, text: []const u8) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.clearPromptLocked();
        // Wrap text to terminal width, re-applying indent on wrapped lines
        var wrapped: std.ArrayList(u8) = .empty;
        defer wrapped.deinit(self.alloc);
        markdown.wrapText(self.alloc, &wrapped, text, termWidth()) catch {};
        self.out.interface.writeAll(wrapped.items) catch {};
        // Ensure we end on a new line before redrawing the prompt
        if (wrapped.items.len == 0 or wrapped.items[wrapped.items.len - 1] != '\n') {
            self.out.interface.writeAll("\n") catch {};
        }
        // Redraw the prompt on this new line
        self.drawPromptLocked();
    }

    /// Writes a complete formatted line above the prompt (single call).
    /// The text MUST end with \n.
    fn writeAgentLine(self: *LiveUI, text: []const u8) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.clearPromptLocked();
        var wrapped: std.ArrayList(u8) = .empty;
        defer wrapped.deinit(self.alloc);
        markdown.wrapText(self.alloc, &wrapped, text, termWidth()) catch {};
        self.out.interface.writeAll(wrapped.items) catch {};
        self.drawPromptLocked();
    }

    fn writeAgentByte(self: *LiveUI, byte: u8) void {
        var b: [1]u8 = .{byte};
        self.writeAgent(&b);
    }

    /// Redraws the prompt on the current line. Must hold the lock.
    /// Erases the previously-drawn box first, then draws a fresh one.
    fn drawPromptLocked(self: *LiveUI) void {
        const cols = termWidth();
        // Count how many content lines the input will occupy.
        var content_lines: usize = 1;
        for (self.input.items) |c| {
            if (c == '\n') content_lines += 1;
        }
        if (self.paste_lines > 0) content_lines = 1;
        // Extra row for spinner line drawn above the box (only when thinking)
        const spinner_row: usize = if (self.thinking) 1 else 0;
        // Total box rows (NOT counting menu): spinner + top border + content + bottom border
        const new_rows = spinner_row + content_lines + 2;
        // Menu rows drawn below the bottom border, tracked separately.
        const menu_rows = blk: {
            if (self.menu_open and self.menu_count > 0) {
                break :blk @min(self.menu_count, 8);
            }
            break :blk 0;
        };

        // ── Erase the old drawing ──
        // The box occupies `prompt_rows` rows (spinner + borders + content).
        // Menu rows are below the bottom border, tracked by `menu_rows_drawn`.
        if (self.prompt_rows > 0) {
            // Erase old menu rows (below the bottom border) first, if any.
            if (self.menu_rows_drawn > 0) {
                // Move down to bottom border, then down through each menu row.
                self.out.interface.writeAll("\x1b[1B\r") catch {};
                for (0..self.menu_rows_drawn) |_| {
                    self.out.interface.writeAll("\x1b[1B\r\x1b[2K") catch {};
                }
                // Move back up to the bottom border.
                for (0..self.menu_rows_drawn) |_| {
                    self.out.interface.writeAll("\x1b[1A\r") catch {};
                }
                // Erase the bottom border.
                self.out.interface.writeAll("\x1b[2K") catch {};
            } else {
                // No old menu: move down to bottom border and erase it.
                self.out.interface.writeAll("\x1b[1B\r\x1b[2K") catch {};
            }
            // Erase remaining box lines upward (bottom border already erased).
            var i: usize = 1;
            while (i < self.prompt_rows) : (i += 1) {
                self.out.interface.writeAll("\x1b[1A\r\x1b[2K") catch {};
            }
        }

        self.menu_rows_drawn = menu_rows;
        self.prompt_rows = new_rows;
        // One column short of the full width: writing into the very last
        // column puts the terminal in a "pending wrap" state, and terminal
        // emulators disagree about what a following \n does there (some
        // double-advance, inserting a phantom blank row). Staying off the
        // last column sidesteps that ambiguity entirely.
        const width = if (cols >= 1) cols else 80;
        const border_len = if (width > 1) width - 1 else width;

        // ── Spinner line (above the box, only when thinking) ──
        if (self.thinking) {
            const frame = spinner_mod.frames[self.think_frame % spinner_mod.frames.len];
            self.out.interface.print("\x1b[36m{s}\x1b[0m\x1b[K\n", .{frame}) catch {};
        }

        // ── Top border (plain line, no corners) ──
        self.writeHLine(border_len);
        self.out.interface.writeAll("\n") catch {};

        // ── Content line(s): no side borders, just ❯ and text ──
        if (self.paste_lines > 0) {
            self.out.interface.print("\x1b[36m❯\x1b[0m \x1b[38;5;245m[Pasted text, {d} {s}]\x1b[0m\x1b[K\n", .{ self.paste_lines, if (self.paste_lines == 1) "line" else "lines" }) catch {};
        } else {
            // Render each content line: first line "❯ text", rest "  text".
            var line_idx: usize = 0;
            var text_start: usize = 0;
            var i: usize = 0;
            while (i <= self.input.items.len) : (i += 1) {
                const at_end = (i == self.input.items.len);
                if (at_end or self.input.items[i] == '\n') {
                    const line_text = self.input.items[text_start..i];
                    if (line_idx == 0) {
                        self.out.interface.writeAll("\x1b[36m❯\x1b[0m ") catch {};
                    } else {
                        self.out.interface.writeAll("  ") catch {};
                    }
                    self.out.interface.writeAll(line_text) catch {};
                    self.out.interface.writeAll("\x1b[K") catch {};
                    if (!at_end) {
                        self.out.interface.writeAll("\n") catch {};
                    }
                    line_idx += 1;
                    text_start = i + 1;
                }
            }
            self.out.interface.writeAll("\n") catch {};
        }

        // ── Bottom border (plain line, no corners) ──
        self.writeHLine(border_len);

        // ── Dropdown menu (below the box) ──
        if (self.menu_open and self.menu_count > 0) {
            self.out.interface.writeAll("\n") catch {};
            const max_show: usize = 8;
            const show = @min(self.menu_count, max_show);
            for (0..show) |i| {
                const cmd_idx = self.menu_matches[i];
                const cmd = slashCommands()[cmd_idx];
                const desc = slashDescriptions()[cmd_idx];
                if (i == self.menu_selected) {
                    self.out.interface.print("\x1b[36m❯ {s}\x1b[0m  \x1b[2m{s}\x1b[0m\x1b[K", .{ cmd, desc }) catch {};
                } else {
                    self.out.interface.print("\x1b[2m  {s}  {s}\x1b[0m\x1b[K", .{ cmd, desc }) catch {};
                }
                // Newline between items, but not after the last one.
                if (i + 1 < show) {
                    self.out.interface.writeAll("\n") catch {};
                }
            }
        }

        // ── Cursor back to the cursor's line and column ──
        // Move up past: bottom border + menu rows
        const up_rows = 1 + menu_rows;
        self.out.interface.print("\x1b[{d}A\r", .{up_rows}) catch {};

        if (self.paste_lines > 0) {
            // Paste indicator: cursor at end of the indicator text.
            self.out.interface.print("\x1b[{d}C", .{2 + 20}) catch {};
        } else {
            // Figure out which content line the cursor is on, and the column.
            var cur_line: usize = 0;
            var cur_col: usize = 0;
            var i: usize = 0;
            while (i < self.cursor and i < self.input.items.len) : (i += 1) {
                if (self.input.items[i] == '\n') {
                    cur_line += 1;
                    cur_col = 0;
                } else {
                    cur_col += 1;
                }
            }
            // Move up from last content line to the cursor's line.
            // The last content line is at content_lines - 1 (0-indexed).
            // We're currently on the last content line (index content_lines - 1).
            // Cursor is on line cur_line, so move up (content_lines - 1 - cur_line).
            if (cur_line + 1 < content_lines) {
                self.out.interface.print("\x1b[{d}A", .{content_lines - 1 - cur_line}) catch {};
            } else if (cur_line + 1 > content_lines) {
                self.out.interface.print("\x1b[{d}B", .{cur_line + 1 - content_lines}) catch {};
            }
            // "❯ " (2 cols) on first line, "  " (2 cols) on rest, then cursor column.
            self.out.interface.print("\x1b[{d}C", .{2 + cur_col}) catch {};
        }
        self.out.flush() catch {};
    }

    /// Writes `n` horizontal line characters (─).
    fn writeHLine(self: *LiveUI, n: usize) void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            self.out.interface.writeAll("\x1b[36m─\x1b[0m") catch {};
        }
    }

    /// Redraws the prompt (acquires lock).
    fn redraw(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.drawPromptLocked();
    }

    /// Erases the prompt box and leaves it undrawn (acquires lock).
    /// Use before taking over stdin/stdout directly (e.g. readLineInline) so
    /// the prompt box isn't corrupted by out-of-band writes. Pair with
    /// `redraw()` once control returns to the normal event loop.
    fn clearPrompt(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.clearPromptLocked();
    }

    /// Returns true if input is empty (for Ctrl+D EOF behavior).
    fn inputEmpty(self: *LiveUI) bool {
        self.mu.lock();
        defer self.mu.unlock();
        return self.input.items.len == 0;
    }

    /// User typed a visible character. Inserts at the cursor position.
    fn onChar(self: *LiveUI, ch: u8) void {
        self.mu.lock();
        defer self.mu.unlock();
        // If there's a paste indicator, clear it — user is editing
        if (self.paste_lines > 0) {
            self.paste_lines = 0;
            self.input.clearRetainingCapacity();
            self.cursor = 0;
        }
        self.input.insert(self.alloc, self.cursor, ch) catch return;
        self.cursor += 1;
        self.updateMenu();
        self.drawPromptLocked();
    }

    /// Recomputes the dropdown menu matches from the current input.
    /// Opens the menu when input starts with '/', closes it otherwise.
    fn updateMenu(self: *LiveUI) void {
        const inp = self.input.items;
        if (inp.len == 0 or inp[0] != '/') {
            self.menu_open = false;
            self.menu_count = 0;
            return;
        }
        const cmds = slashCommands();
        self.menu_count = 0;
        for (cmds, 0..) |cmd, i| {
            if (self.menu_count >= self.menu_matches.len) break;
            if (std.mem.startsWith(u8, cmd, inp)) {
                self.menu_matches[self.menu_count] = i;
                self.menu_count += 1;
            }
        }
        self.menu_open = self.menu_count > 0;
        self.menu_selected = 0;
    }

    /// Accepts the currently selected menu item into input and closes the menu.
    fn acceptMenu(self: *LiveUI) void {
        if (!self.menu_open or self.menu_count == 0) return;
        const cmd_idx = self.menu_matches[self.menu_selected];
        const cmd = slashCommands()[cmd_idx];
        self.input.clearRetainingCapacity();
        self.input.appendSlice(self.alloc, cmd) catch return;
        self.cursor = self.input.items.len;
        self.menu_open = false;
        self.menu_count = 0;
        self.drawPromptLocked();
    }

    /// Move menu selection up (wrap around). No-op if menu closed.
    fn onMenuUp(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (!self.menu_open or self.menu_count == 0) return;
        self.menu_selected = if (self.menu_selected == 0)
            self.menu_count - 1
        else
            self.menu_selected - 1;
        self.drawPromptLocked();
    }

    /// Move menu selection down (wrap around). No-op if menu closed.
    fn onMenuDown(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (!self.menu_open or self.menu_count == 0) return;
        self.menu_selected = (self.menu_selected + 1) % self.menu_count;
        self.drawPromptLocked();
    }

    /// Close the dropdown menu without accepting.
    fn closeMenu(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (!self.menu_open) return;
        self.menu_open = false;
        self.menu_count = 0;
        self.drawPromptLocked();
    }

    /// Finalizes a paste: strips trailing newlines, then either shows the text
    /// inline (single-line, short) or collapses it to a placeholder (multi-line
    /// or large). Multi-line text can't be displayed on the single-line prompt,
    /// so it must be collapsed to avoid corrupting the display.
    fn finishPaste(self: *LiveUI, raw: []const u8) void {
        if (raw.len == 0) return;
        // Strip trailing newlines so they don't break the single-line prompt
        var text = raw;
        while (text.len > 0 and (text[text.len - 1] == '\n' or text[text.len - 1] == '\r')) {
            text = text[0 .. text.len - 1];
        }
        if (text.len == 0) return;
        self.mu.lock();
        defer self.mu.unlock();
        self.input.appendSlice(self.alloc, text) catch return;
        self.cursor = self.input.items.len;
        const is_multiline = std.mem.indexOfScalar(u8, text, '\n') != null;
        if (is_multiline or text.len >= LARGE_PASTE_THRESHOLD) {
            self.paste_lines = countLines(text);
            self.drawPromptLocked();
        } else {
            self.drawPromptLocked();
        }
    }

    /// User pressed backspace (delete char before cursor).
    fn onBackspace(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.paste_lines > 0) {
            // Clear pasted text entirely on backspace
            self.paste_lines = 0;
            self.input.clearRetainingCapacity();
            self.cursor = 0;
            self.drawPromptLocked();
            return;
        }
        if (self.cursor > 0) {
            // Delete the byte before the cursor.
            _ = self.input.orderedRemove(self.cursor - 1);
            self.cursor -= 1;
            self.updateMenu();
            self.drawPromptLocked();
        }
    }

    /// User pressed Delete (forward-delete char after cursor).
    fn onDelete(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.cursor < self.input.items.len) {
            _ = self.input.orderedRemove(self.cursor);
            self.updateMenu();
            self.drawPromptLocked();
        }
    }

    /// Move cursor one char left. No-op if already at start.
    fn onCursorLeft(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.cursor > 0) {
            self.cursor -= 1;
            self.drawPromptLocked();
        }
    }

    /// Move cursor one char right. No-op if already at end.
    fn onCursorRight(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.cursor < self.input.items.len) {
            self.cursor += 1;
            self.drawPromptLocked();
        }
    }

    /// Move cursor to start of line (Cmd+Left / Home).
    fn onLineStart(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        // Find start of the current line (after last newline before cursor).
        var pos = self.cursor;
        while (pos > 0 and self.input.items[pos - 1] != '\n') pos -= 1;
        self.cursor = pos;
        self.drawPromptLocked();
    }

    /// Move cursor to end of line (Cmd+Right / End).
    fn onLineEnd(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        // Find end of the current line (next newline or end of input).
        var pos = self.cursor;
        while (pos < self.input.items.len and self.input.items[pos] != '\n') pos += 1;
        self.cursor = pos;
        self.drawPromptLocked();
    }

    /// Move cursor one word backward (Option+Left).
    fn onWordLeft(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.cursor = wordBackward(self.input.items, self.cursor);
        self.drawPromptLocked();
    }

    /// Move cursor one word forward (Option+Right).
    fn onWordRight(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.cursor = wordForward(self.input.items, self.cursor);
        self.drawPromptLocked();
    }

    /// Delete one word backward (Option+Delete).
    fn onDeleteWord(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.paste_lines > 0) {
            self.paste_lines = 0;
            self.input.clearRetainingCapacity();
            self.cursor = 0;
            self.drawPromptLocked();
            return;
        }
        if (self.cursor == 0) return;
        const new_pos = wordBackward(self.input.items, self.cursor);
        const count = self.cursor - new_pos;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            _ = self.input.orderedRemove(new_pos);
        }
        self.cursor = new_pos;
        self.updateMenu();
        self.drawPromptLocked();
    }

    /// Delete one word forward (Ctrl+Delete).
    fn onDeleteWordForward(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.cursor >= self.input.items.len) return;
        const end = wordForward(self.input.items, self.cursor);
        const count = end - self.cursor;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            _ = self.input.orderedRemove(self.cursor);
        }
        self.updateMenu();
        self.drawPromptLocked();
    }

    /// Delete to end of line (Cmd+Delete or Ctrl+K).
    /// If the line is empty (nothing after cursor), delete the newline
    /// before the cursor to join with the previous line.
    fn onDeleteLine(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.paste_lines > 0) {
            self.paste_lines = 0;
            self.input.clearRetainingCapacity();
            self.cursor = 0;
            self.drawPromptLocked();
            return;
        }
        // Find end of current line (next newline or end of input).
        var line_end = self.cursor;
        while (line_end < self.input.items.len and self.input.items[line_end] != '\n') line_end += 1;
        if (line_end > self.cursor) {
            // Delete from cursor to line_end (content after cursor on this line).
            const count = line_end - self.cursor;
            var i: usize = 0;
            while (i < count) : (i += 1) {
                _ = self.input.orderedRemove(self.cursor);
            }
        } else if (self.cursor > 0 and self.input.items[self.cursor - 1] == '\n') {
            // Empty line: delete the newline before the cursor to join
            // with the previous line.
            _ = self.input.orderedRemove(self.cursor - 1);
            self.cursor -= 1;
        }
        self.updateMenu();
        self.drawPromptLocked();
    }

    /// Delete from start of line to cursor (Ctrl+U).
    /// If cursor is at line start, delete the newline before it to join lines.
    fn onDeleteToLineStart(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.cursor == 0) return;
        // Find start of the current line.
        var line_start = self.cursor;
        while (line_start > 0 and self.input.items[line_start - 1] != '\n') line_start -= 1;
        if (line_start < self.cursor) {
            // Delete from line_start to cursor (content before cursor on this line).
            const count = self.cursor - line_start;
            var i: usize = 0;
            while (i < count) : (i += 1) {
                _ = self.input.orderedRemove(line_start);
            }
            self.cursor = line_start;
        } else if (line_start > 0 and self.input.items[line_start - 1] == '\n') {
            // Cursor is at the start of a line (line_start == cursor):
            // delete the newline before it to join with the previous line.
            _ = self.input.orderedRemove(line_start - 1);
            self.cursor -= 1;
        }
        self.updateMenu();
        self.drawPromptLocked();
    }

    /// User pressed Tab: cycle selection down in the dropdown menu. If the menu
    /// isn't open, open it by matching the current input.
    fn onTab(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.paste_lines > 0) return;

        const inp = self.input.items;
        if (inp.len == 0 or inp[0] != '/') return;

        // If menu isn't open, compute matches and open it.
        if (!self.menu_open) {
            self.updateMenu();
            self.drawPromptLocked();
            return;
        }
        // Cycle selection down, wrap around.
        if (self.menu_count > 0) {
            self.menu_selected = (self.menu_selected + 1) % self.menu_count;
            self.drawPromptLocked();
        }
    }

    /// User pressed Shift+Enter (or Alt+Enter): insert a newline into input
    /// for multi-line editing. Does NOT submit.
    fn onNewline(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.paste_lines > 0) {
            // If showing paste indicator, clear it and keep just the newline
            self.paste_lines = 0;
            self.input.clearRetainingCapacity();
            self.cursor = 0;
        }
        self.input.insert(self.alloc, self.cursor, '\n') catch return;
        self.cursor += 1;
        self.drawPromptLocked();
    }

    /// Returns the current input (caller owns the returned slice; free with
    /// `self.alloc`) and clears the buffer.
    fn takeInput(self: *LiveUI) []u8 {
        self.mu.lock();
        defer self.mu.unlock();
        const result = self.input.toOwnedSlice(self.alloc) catch self.input.items;
        self.paste_lines = 0;
        self.cursor = 0;
        return result;
    }

    /// Shows thinking spinner on the prompt line.
    fn showThinking(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.thinking = true;
        self.think_frame = 0;
        self.drawPromptLocked();
    }

    /// Advances the spinner frame.
    fn tickThinking(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (!self.thinking) return;
        self.think_frame += 1;
        self.drawPromptLocked();
    }

    /// Clears thinking, shows plain prompt.
    fn stopThinking(self: *LiveUI) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.thinking = false;
        self.drawPromptLocked();
    }

    fn deinit(self: *LiveUI) void {
        self.input.deinit(self.alloc);
    }
};

// ── Spinner thread that drives LiveUI's thinking animation ──────────────────

const ThinkThread = struct {
    ui: *LiveUI,
    flag: *std.atomic.Value(bool),
    thread: ?std.Thread = null,

    fn spawn(alloc: std.mem.Allocator, ui: *LiveUI) !ThinkThread {
        const flag = try alloc.create(std.atomic.Value(bool));
        flag.* = .{ .raw = false };
        const t = std.Thread.spawn(.{}, loop, .{ ui, flag }) catch |err| {
            alloc.destroy(flag);
            return err;
        };
        return .{ .ui = ui, .flag = flag, .thread = t };
    }

    fn loop(ui: *LiveUI, flag: *std.atomic.Value(bool)) void {
        while (!flag.load(.acquire)) {
            ui.tickThinking();
            _ = spinner_mod.usleep(80_000); // 80ms
        }
    }

    fn stop(self: *ThinkThread) void {
        if (self.flag.raw) return;
        self.flag.store(true, .release);
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
    }

    fn deinit(self: *ThinkThread, alloc: std.mem.Allocator) void {
        self.stop();
        alloc.destroy(self.flag);
    }
};

/// Context passed to streaming callbacks. Accumulates text + tool-call deltas.
const StreamCtx = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    config: *config_mod.Config,
    full_reply: std.ArrayList(u8) = .empty,
    line_buf: std.ArrayList(u8) = .empty,
    in_code_block: bool = false,
    think: ?ThinkThread = null,
    tool_accum: response.ToolCallAccumulator,
    first_token: bool = true,
    out: ?*std.Io.File.Writer = null,
    start_ts: ?std.Io.Timestamp = null,
    ui: ?*LiveUI = null,
    /// Captured HTTP error message (status + body) for display in the chat UI.
    err_msg: ?[]u8 = null,

    fn stopThinking(self: *StreamCtx) void {
        if (self.first_token) {
            if (self.think) |*tt| tt.stop();
            if (self.ui) |ui| ui.stopThinking();
            self.first_token = false;
        }
    }

    /// Stops the current think thread (if any) and starts a fresh one.
    fn restartThinking(self: *StreamCtx) void {
        if (self.think) |*tt| tt.deinit(self.alloc);
        if (self.ui) |ui| {
            ui.showThinking();
            self.think = ThinkThread.spawn(self.alloc, ui) catch null;
        }
        self.first_token = true;
    }

    fn deinit(self: *StreamCtx) void {
        self.full_reply.deinit(self.alloc);
        self.line_buf.deinit(self.alloc);
        self.tool_accum.deinit();
        if (self.think) |*tt| tt.deinit(self.alloc);
        if (self.err_msg) |m| self.alloc.free(m);
    }

    /// Writes agent output above the prompt line.
    fn writeOut(self: *StreamCtx, bytes: []const u8) void {
        if (self.ui) |ui| {
            ui.writeAgent(bytes);
        } else if (self.out) |w| {
            w.interface.writeAll(bytes) catch {};
            w.flush() catch {};
        }
    }

    fn writeByteOut(self: *StreamCtx, byte: u8) void {
        var b: [1]u8 = .{byte};
        self.writeOut(&b);
    }

    fn flushOut(self: *StreamCtx) void {
        if (self.ui) |_| {
            // LiveUI manages its own flush
        } else if (self.out) |w| {
            w.flush() catch {};
        }
    }
};

/// Called before each retry attempt. Stops the spinner and shows a retry message.
fn onRetry(ctx: *anyopaque, attempt: u8, total: u8) void {
    const self: *StreamCtx = @ptrCast(@alignCast(ctx));
    // Stop current spinner so it doesn't overwrite our retry message
    self.stopThinking();
    if (self.ui) |ui| {
        ui.writeAgent("\x1b[2m↻ retry\x1b[0m\n");
    } else if (self.out) |w| {
        w.interface.print("\x1b[2m↻ retry {d}/{d}...\x1b[0m\n", .{ attempt, total }) catch {};
        w.flush() catch {};
    }
    // Start a fresh spinner for the next attempt
    self.restartThinking();
}

/// Called on the final failed HTTP attempt with the status code and error
/// body. Captures a formatted message into StreamCtx.err_msg so the agent
/// loop can surface it in the chat UI (stderr is invisible in TUI mode).
fn onError(ctx: *anyopaque, status_code: u16, body: []const u8) void {
    const self: *StreamCtx = @ptrCast(@alignCast(ctx));
    self.stopThinking();
    // Trim trailing whitespace from the server's error body.
    var trimmed = body;
    while (trimmed.len > 0 and (trimmed[trimmed.len - 1] == '\n' or trimmed[trimmed.len - 1] == '\r' or trimmed[trimmed.len - 1] == ' ')) {
        trimmed = trimmed[0 .. trimmed.len - 1];
    }
    self.err_msg = std.fmt.allocPrint(self.alloc, "HTTP {d}: {s}", .{ status_code, trimmed }) catch null;
}

fn onChunk(ctx: *anyopaque, chunk: []const u8) void {
    const self: *StreamCtx = @ptrCast(@alignCast(ctx));

    // Extract tool-call deltas (accumulated across chunks)
    {
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        const deltas = response.extractToolCallDeltas(arena.allocator(), self.config.provider, chunk) catch &.{};
        for (deltas) |delta| {
            self.stopThinking();
            self.tool_accum.addDelta(delta) catch {};
        }
    }

    // Extract text content delta
    const delta = response.extractDelta(self.alloc, self.config.provider, chunk) catch return;
    if (delta) |d| {
        self.stopThinking();

        var unescaped: std.ArrayList(u8) = .empty;
        defer unescaped.deinit(self.alloc);
        unescapeAppend(self.alloc, &unescaped, d) catch {};

        self.full_reply.appendSlice(self.alloc, unescaped.items) catch {};
        self.line_buf.appendSlice(self.alloc, unescaped.items) catch {};

        // Output complete lines through markdown renderer
        while (std.mem.indexOfScalar(u8, self.line_buf.items, '\n')) |nl| {
            var md_buf: std.ArrayList(u8) = .empty;
            defer md_buf.deinit(self.alloc);
            markdown.renderLine(self.alloc, &md_buf, &self.in_code_block, self.line_buf.items[0..nl]) catch {};
            // Append newline so writeAgent treats it as a complete line
            md_buf.append(self.alloc, '\n') catch {};
            self.writeOut(md_buf.items);

            // Shift remaining bytes to front of line_buf
            const rest = self.line_buf.items[nl + 1 ..];
            std.mem.copyForwards(u8, self.line_buf.items[0..rest.len], rest);
            self.line_buf.items.len = rest.len;
        }
        self.flushOut();
    }
}

fn onDone(ctx: *anyopaque) void {
    const self: *StreamCtx = @ptrCast(@alignCast(ctx));
    self.stopThinking();

    // Build the final output as a single buffer to avoid multiple writeAgent calls
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(self.alloc);

    // Render any remaining partial line
    if (self.line_buf.items.len > 0) {
        markdown.renderLine(self.alloc, &buf, &self.in_code_block, self.line_buf.items) catch {};
        self.line_buf.items.len = 0;
    }
    if (self.in_code_block) {
        buf.appendSlice(self.alloc, "\x1b[0m") catch {};
        self.in_code_block = false;
    }
    buf.append(self.alloc, '\n') catch {};
    self.writeOut(buf.items);
    self.flushOut();
}

/// Unescapes JSON string escapes and appends to the output buffer.
fn unescapeAppend(alloc: std.mem.Allocator, out: *std.ArrayList(u8), input: []const u8) !void {
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '\\' and i + 1 < input.len) {
            switch (input[i + 1]) {
                'n' => {
                    try out.append(alloc, '\n');
                    i += 2;
                },
                'r' => {
                    try out.append(alloc, '\r');
                    i += 2;
                },
                't' => {
                    try out.append(alloc, '\t');
                    i += 2;
                },
                '"' => {
                    try out.append(alloc, '"');
                    i += 2;
                },
                '\\' => {
                    try out.append(alloc, '\\');
                    i += 2;
                },
                '/' => {
                    try out.append(alloc, '/');
                    i += 2;
                },
                'u' => {
                    if (i + 6 > input.len) {
                        try out.append(alloc, input[i]);
                        i += 1;
                        continue;
                    }
                    const hex = input[i + 2 .. i + 6];
                    const codepoint = std.fmt.parseInt(u21, hex, 16) catch {
                        try out.append(alloc, input[i]);
                        i += 1;
                        continue;
                    };
                    var utf8: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(codepoint, &utf8) catch 0;
                    try out.appendSlice(alloc, utf8[0..len]);
                    i += 6;
                },
                else => {
                    try out.append(alloc, input[i]);
                    i += 1;
                },
            }
        } else {
            try out.append(alloc, input[i]);
            i += 1;
        }
    }
}

/// Frees all heap-owned fields of a message (content, tool_calls, tool_call_id).
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

/// Prints the timing stats line in fx style: "  3s"
fn printStats(out: *std.Io.File.Writer, start_ts: ?std.Io.Timestamp, io: std.Io) void {
    if (start_ts == null) return;
    const end_ts = std.Io.Timestamp.now(io, .awake);
    const dur_ns = start_ts.?.durationTo(end_ts).nanoseconds;
    const dur_ms = @divTrunc(dur_ns, std.time.ns_per_ms);
    const dur_s = @divTrunc(dur_ms, 1000);
    if (dur_s > 0) {
        out.interface.print("\x1b[38;5;245m  {d}s\x1b[0m\n", .{dur_s}) catch {};
    } else {
        out.interface.print("\x1b[38;5;245m  {d}ms\x1b[0m\n", .{dur_ms}) catch {};
    }
    out.flush() catch {};
}

/// Prints tool usage in the fx style:
///   ● N tool call(s) · 1 read · 2 searches
///   ├ Read /path/to/file
///   └ Searched pattern
fn printToolUsage(
    arena: std.mem.Allocator,
    out: *std.Io.File.Writer,
    tool_calls: []const tools.ToolCall,
    results: []const ?tools.ToolResult,
) !void {
    const dim = "\x1b[38;5;245m";
    const reset = "\x1b[0m";

    // Count by type
    var read_count: usize = 0;
    var search_count: usize = 0;
    var fetch_count: usize = 0;
    var list_count: usize = 0;
    var other_count: usize = 0;
    var failed_count: usize = 0;
    for (results) |res| {
        if (res == null) {
            failed_count += 1;
            continue;
        }
        const label = tools.toolTypeLabel(res.?.name);
        if (std.mem.eql(u8, label, "read")) read_count += 1 else if (std.mem.eql(u8, label, "search")) search_count += 1 else if (std.mem.eql(u8, label, "fetch")) fetch_count += 1 else if (std.mem.eql(u8, label, "list")) list_count += 1 else other_count += 1;
    }

    // Build breakdown string with parts
    var bd: std.ArrayList(u8) = .empty;
    defer bd.deinit(arena);

    const addPart = struct {
        fn run(b: *std.ArrayList(u8), a: std.mem.Allocator, singular: []const u8, plural: []const u8, count: usize, first_p: *bool) void {
            if (count == 0) return;
            if (!first_p.*) b.appendSlice(a, " · ") catch {};
            first_p.* = false;
            const word = if (count == 1) singular else plural;
            const part = std.fmt.allocPrint(a, "{d} {s}", .{ count, word }) catch return;
            b.appendSlice(a, part) catch {};
        }
    }.run;
    var first = true;
    addPart(&bd, arena, "read", "reads", read_count, &first);
    addPart(&bd, arena, "search", "searches", search_count, &first);
    addPart(&bd, arena, "fetch", "fetches", fetch_count, &first);
    addPart(&bd, arena, "list", "lists", list_count, &first);
    if (other_count > 0) addPart(&bd, arena, "tool", "tools", other_count, &first);
    if (failed_count > 0) addPart(&bd, arena, "failed", "failed", failed_count, &first);

    // Summary line: ● N tool call(s) · breakdown
    const n = tool_calls.len;
    try out.interface.writeAll("\n");
    try out.interface.writeAll("\x1b[38;5;255m●\x1b[0m ");
    if (n == 1) {
        try out.interface.print("{s}1 tool call{s}", .{ dim, reset });
    } else {
        try out.interface.print("{s}{d} tool calls{s}", .{ dim, n, reset });
    }
    if (bd.items.len > 0) {
        try out.interface.print(" {s}· {s}{s}", .{ dim, bd.items, reset });
    }
    try out.interface.writeAll("\n");

    // Tree lines: ├ / └
    for (tool_calls, 0..) |tc, i| {
        const connector = if (i < tool_calls.len - 1) "├ " else "└ ";
        const verb = tools.toolVerb(tc.name);
        const detail = tools.toolDetail(tc.name, tc.arguments);
        // Truncate long details
        const max_detail = 100;
        const display_detail = if (detail.len > max_detail) detail[0..max_detail] else detail;
        if (display_detail.len > 0) {
            try out.interface.print("{s}{s}{s} {s}{s}\n", .{ dim, connector, verb, display_detail, reset });
        } else {
            try out.interface.print("{s}{s}{s}{s}\n", .{ dim, connector, verb, reset });
        }
    }
}

/// Runs a one-shot chat: sends the prompt, streams the response with markdown
/// rendering and a spinner, saves to DB.
pub fn askOnce(
    alloc: std.mem.Allocator,
    io: std.Io,
    config: *config_mod.Config,
    prompt: []const u8,
) !void {
    var messages: std.ArrayList(session.Message) = .empty;
    defer {
        for (messages.items) |m| freeMessage(alloc, m);
        messages.deinit(alloc);
    }

    var sess = try session.Session.open(alloc, io, config.db_path);
    defer sess.close();

    const session_id = try sess.createSession(prompt[0..@min(prompt.len, 60)], config.provider.slug(), config.model);
    try sess.addMessage(session_id, .user, prompt);
    try messages.append(alloc, .{ .role = .user, .content = try alloc.dupe(u8, prompt) });

    const stdout = std.Io.File.stdout();
    var out_buf: [4096]u8 = undefined;
    var out_w = stdout.writer(io, &out_buf);

    // Agent loop
    const turn_start = std.Io.Timestamp.now(io, .awake);
    var iteration: usize = 0;
    while (iteration < MAX_TOOL_ITERATIONS) {
        iteration += 1;

        const payload = try json.buildPayloadWithTools(alloc, config.provider, config.model, messages.items, config.system_prompt, config.max_tokens, config.temperature, true);
        defer alloc.free(payload);

        var ctx: StreamCtx = .{
            .alloc = alloc,
            .io = io,
            .config = config,
            .tool_accum = response.ToolCallAccumulator.init(alloc),
            .out = &out_w,
            .start_ts = turn_start,
        };
        defer ctx.deinit();

        // No prefix — markdown renderer handles the 2-space indent (fx style)

        http_client.streamChat(alloc, io, config.provider, config.provider.chatUrl(), config.api_key, payload, onChunk, onDone, onRetry, onError, @ptrCast(&ctx)) catch |err| {
            // Stop spinner on any error so it doesn't keep spinning
            ctx.stopThinking();
            if (ctx.err_msg) |m| {
                const stderr = std.Io.File.stderr();
                var bw: [4096]u8 = undefined;
                var w = stderr.writer(io, &bw);
                w.interface.print("Error: {s}\n", .{m}) catch {};
                w.flush() catch {};
            } else if (err != error.HttpBadStatus) {
                const stderr = std.Io.File.stderr();
                var bw: [256]u8 = undefined;
                var w = stderr.writer(io, &bw);
                w.interface.print("Error: {t}\n", .{err}) catch {};
                w.flush() catch {};
            }
            return;
        };

        if (!ctx.tool_accum.hasToolCalls()) {
            if (ctx.full_reply.items.len > 0) {
                try sess.addMessage(session_id, .assistant, ctx.full_reply.items);
            }
            printStats(&out_w, ctx.start_ts, io);
            return;
        }

        // Execute tool calls
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const tool_calls = try ctx.tool_accum.collect(arena.allocator());
        if (tool_calls.len == 0) return;

        // Add assistant message with tool_calls
        const reply_copy = try alloc.dupe(u8, ctx.full_reply.items);
        const tcs_copy = try alloc.alloc(session.ToolCallRef, tool_calls.len);
        for (tool_calls, 0..) |tc, i| {
            tcs_copy[i] = .{
                .id = try alloc.dupe(u8, tc.id),
                .name = try alloc.dupe(u8, tc.name),
                .arguments = try alloc.dupe(u8, tc.arguments),
            };
        }
        try messages.append(alloc, .{ .role = .assistant, .content = reply_copy, .tool_calls = tcs_copy });

        // Execute all tool calls, collecting results for display
        const results = try arena.allocator().alloc(?tools.ToolResult, tool_calls.len);
        for (tool_calls, 0..) |tc, i| {
            results[i] = tools.execute(arena.allocator(), io, tc) catch null;
            if (results[i]) |result| {
                const result_copy = try alloc.dupe(u8, result.content);
                const id_copy = try alloc.dupe(u8, tc.id);
                try messages.append(alloc, .{
                    .role = .tool,
                    .content = result_copy,
                    .tool_call_id = id_copy,
                });
            }
        }
        // Print tool usage summary (fx style)
        printToolUsage(arena.allocator(), &out_w, tool_calls, results) catch {};
        out_w.flush() catch {};
    }
}

/// Runs an interactive chat session: loop of user input -> agent response.
/// The `❯` prompt stays active and editable while the agent streams.
pub fn chatSession(
    alloc: std.mem.Allocator,
    io: std.Io,
    mgr: *config_mod.ConfigManager,
    resume_id: ?i64,
) !void {
    const config = &mgr.config;
    var sess = try session.Session.open(alloc, io, config.db_path);
    defer sess.close();

    var session_id: i64 = undefined;
    var messages: std.ArrayList(session.Message) = .empty;
    defer {
        for (messages.items) |m| freeMessage(alloc, m);
        messages.deinit(alloc);
    }

    if (resume_id) |id| {
        session_id = id;
        const loaded = try sess.loadMessages(session_id);
        for (loaded) |m| {
            try messages.append(alloc, .{ .role = m.role, .content = try alloc.dupe(u8, m.content) });
        }
        sess.freeMessages(loaded);
    } else {
        session_id = try sess.createSession("chat", config.provider.slug(), config.model);
    }

    const stdout = std.Io.File.stdout();

    var out_buf: [4096]u8 = undefined;
    var out_w = stdout.writer(io, &out_buf);

    // Enter raw terminal mode
    var raw_guard = term.TermGuard.enable() catch {
        std.debug.print("Error: could not enter raw mode\n", .{});
        return;
    };
    defer raw_guard.disable();

    // Enable bracketed paste mode so multi-line paste doesn't submit per-line
    out_w.interface.writeAll("\x1b[?2004h") catch {};
    // Enable kitty keyboard protocol flag 1 (disambiguate escape sequences).
    // Makes Backspace/Enter/etc. send CSI u with modifier info, so
    // Option+Backspace sends \x1b[127;3u instead of bare 0x7f.
    out_w.interface.writeAll("\x1b[>1u") catch {};
    out_w.flush() catch {};
    defer {
        out_w.interface.writeAll("\x1b[?2004l") catch {};
        out_w.interface.writeAll("\x1b[<u") catch {}; // Disable kitty keyboard
        out_w.flush() catch {};
    }

    // Set up the live UI
    var ui = LiveUI{
        .alloc = alloc,
        .out = &out_w,
    };
    defer ui.deinit();

    // Print header (above the prompt line)
    // Clear the screen first so we start from a clean slate after setup or
    // a prior interactive flow — setup.run() leaves its "Setup complete"
    // summary on screen, and without clearing it our header gets appended
    // below the leftover text, corrupting the display.
    try out_w.interface.writeAll("\x1b[2J\x1b[H");
    try out_w.interface.print("io \x1b[2m{s} / {s}\x1b[0m  session #{d}\n", .{
        config.provider.name(),
        config.model,
        session_id,
    });

    // When resuming a session, print the loaded message history so the user
    // sees the conversation context before the prompt appears.
    if (resume_id != null and messages.items.len > 0) {
        try out_w.interface.writeAll("\n");
        var in_code_block: bool = false;
        for (messages.items) |m| {
            switch (m.role) {
                .user => {
                    const nl_count = std.mem.count(u8, m.content, "\n");
                    if (nl_count > 0) {
                        const total_lines = nl_count + 1;
                        const word = if (total_lines == 1) "line" else "lines";
                        try out_w.interface.print("\x1b[36m❯\x1b[0m \x1b[38;5;245m[Pasted text, {d} {s}]\x1b[0m\n", .{ total_lines, word });
                    } else {
                        try out_w.interface.print("\x1b[36m❯\x1b[0m \x1b[1m{s}\x1b[0m\n", .{m.content});
                    }
                },
                .assistant => {
                    // Render each line through the markdown renderer
                    var line_start: usize = 0;
                    var i: usize = 0;
                    while (i <= m.content.len) : (i += 1) {
                        if (i == m.content.len or m.content[i] == '\n') {
                            var md_buf: std.ArrayList(u8) = .empty;
                            defer md_buf.deinit(alloc);
                            try markdown.renderLine(alloc, &md_buf, &in_code_block, m.content[line_start..i]);
                            if (i < m.content.len) try md_buf.append(alloc, '\n');
                            try out_w.interface.writeAll(md_buf.items);
                            line_start = i + 1;
                        }
                    }
                    if (in_code_block) {
                        try out_w.interface.writeAll("\x1b[0m");
                        in_code_block = false;
                    }
                    try out_w.interface.writeAll("\n");
                },
                .tool => {
                    try out_w.interface.print("\x1b[2m  [tool result]\x1b[0m\n", .{});
                },
                .system => {},
            }
        }
        if (in_code_block) try out_w.interface.writeAll("\x1b[0m");
    }

    try out_w.interface.writeAll("Type your message. /help for commands, /exit to quit.\n\n");
    try out_w.flush();

    // Draw the initial prompt
    ui.redraw();

    // Main loop: read keys, handle agent in background
    var read_buf: [256]u8 = undefined;
    var agent_busy = false;
    var queued_msg: ?[]u8 = null;
    defer if (queued_msg) |m| alloc.free(m);
    var paste: PasteState = .{};
    defer paste.deinit(alloc);

    while (true) {
        // If agent is not busy and we have a queued message, send it
        if (!agent_busy and queued_msg != null) {
            const msg = queued_msg.?;
            queued_msg = null;
            defer alloc.free(msg);
            // Print the user message above the prompt as a chat message.
            // Multi-line pasted text collapses to a compact indicator.
            var line_buf: std.ArrayList(u8) = .empty;
            defer line_buf.deinit(alloc);
            const nl_count = std.mem.count(u8, msg, "\n");
            if (nl_count > 0) {
                const total_lines = nl_count + 1;
                const word = if (total_lines == 1) "line" else "lines";
                line_buf.appendSlice(alloc, "\x1b[36m❯\x1b[0m \x1b[38;5;245m[Pasted text, ") catch {};
                const part = std.fmt.allocPrint(alloc, "{d} {s}]\x1b[0m\n", .{ total_lines, word }) catch "";
                line_buf.appendSlice(alloc, part) catch {};
                alloc.free(part);
            } else {
                line_buf.appendSlice(alloc, "\x1b[36m❯\x1b[0m \x1b[1m") catch {};
                line_buf.appendSlice(alloc, msg) catch {};
                line_buf.appendSlice(alloc, "\x1b[0m\n") catch {};
            }
            // Blank-line spacer before the echo, drawn as its own erase/redraw
            // cycle (matches the spacer used after agent responses below) so
            // it doesn't get glued to the echo text and leave stray rows.
            ui.writeAgentLine("\n");
            ui.writeAgentLine(line_buf.items);

            // Process slash commands
            if (msg.len > 0 and msg[0] == '/') {
                if (std.mem.eql(u8, msg, "/exit") or std.mem.eql(u8, msg, "/quit")) {
                    ui.writeAgentLine("\x1b[38;5;245m  Bye.\x1b[0m\n");
                    break;
                }
                if (std.mem.eql(u8, msg, "/help")) {
                    ui.writeAgentLine(
                        \\Commands:
                        \\  /help     Show this help
                        \\  /exit     Quit the session
                        \\  /model    Show current model
                        \\  /models   Switch model for current provider
                        \\  /login    Add or switch a provider (enter API key)
                        \\  /logout   Pick a provider and remove its saved API key
                        \\  /clear    Clear conversation context (keeps DB history)
                        \\  /compact  Summarize and compact conversation context
                        \\
                    );
                    ui.redraw();
                    continue;
                }
                if (std.mem.eql(u8, msg, "/model")) {
                    var buf2: [512]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf2, "\x1b[38;5;245m  Provider: {s}\n  Model: {s}\x1b[0m\n", .{ config.provider.name(), config.model }) catch "";
                    ui.writeAgentLine(s);
                    ui.redraw();
                    continue;
                }
                if (std.mem.eql(u8, msg, "/models")) {
                    cmdModels(alloc, io, &ui, mgr, &messages, &sess, session_id);
                    continue;
                }
                if (std.mem.eql(u8, msg, "/login")) {
                    cmdLogin(alloc, io, &ui, mgr, &messages, &sess, session_id);
                    continue;
                }
                if (std.mem.eql(u8, msg, "/logout")) {
                    cmdLogout(alloc, io, &ui, mgr);
                    ui.redraw();
                    continue;
                }
                if (std.mem.eql(u8, msg, "/clear")) {
                    for (messages.items) |m| freeMessage(alloc, m);
                    messages.clearRetainingCapacity();
                    ui.writeAgentLine("\x1b[38;5;245m  Context cleared.\x1b[0m\n");
                    ui.redraw();
                    continue;
                }
                if (std.mem.eql(u8, msg, "/compact")) {
                    const tokens = compact.estimateTokens(messages.items, config.system_prompt);
                    if (tokens < 1000) {
                        var buf2: [256]u8 = undefined;
                        const s = std.fmt.bufPrint(&buf2, "\x1b[38;5;245m  Context is small ({d} est. tokens). Nothing to compact.\x1b[0m\n", .{tokens}) catch "";
                        ui.writeAgentLine(s);
                        ui.redraw();
                        continue;
                    }
                    ui.writeAgentLine("\x1b[38;5;245m  Compacting context...\x1b[0m\n");
                    ui.redraw();
                    if (compact.maybeCompact(alloc, io, config, &messages)) |result| {
                        var buf2: [256]u8 = undefined;
                        const s = std.fmt.bufPrint(&buf2, "\x1b[38;5;245m  Context compacted ({d} → {d} tokens).\x1b[0m\n", .{ result.before_tokens, result.after_tokens }) catch "";
                        ui.writeAgentLine(s);
                    } else {
                        ui.writeAgentLine("\x1b[38;5;245m  Compaction failed (summarization error).\x1b[0m\n");
                    }
                    ui.redraw();
                    continue;
                }
                var buf2: [256]u8 = undefined;
                const s = std.fmt.bufPrint(&buf2, "\x1b[38;5;245m  Unknown command: {s}\x1b[0m\n", .{msg}) catch "";
                ui.writeAgentLine(s);
                ui.redraw();
                continue;
            }

            // Add user message
            try sess.addMessage(session_id, .user, msg);
            try messages.append(alloc, .{ .role = .user, .content = try alloc.dupe(u8, msg) });

            // Blank-line spacer after the user echo, before the spinner.
            ui.writeAgentLine("\n");

            // Start agent in background thread
            agent_busy = true;
            ui.showThinking();

            // We run the agent in the current thread but use a background
            // spinner thread for the animation. Input reading resumes after.
            // Actually, to allow typing while agent runs, we need the agent
            // in a background thread. Let's do that.
            const turn_start = std.Io.Timestamp.now(io, .awake);

            const agent_ctx = try alloc.create(AgentCtx);
            agent_ctx.* = .{
                .alloc = alloc,
                .io = io,
                .config = config,
                .messages = &messages,
                .ui = &ui,
                .start_ts = turn_start,
                .done = false,
                .err = null,
                .sess = &sess,
                .session_id = session_id,
            };
            const agent_thread = try std.Thread.spawn(.{}, runAgent, .{ agent_ctx });

            // Read input while agent runs (poll with timeout so we can check done flag)
            while (!agent_ctx.done) {
                const n = readStdinTimeout(read_buf[0..]);
                if (n == 0) continue;
                // Heuristic: non-bracketed multi-line paste (2+ newlines in one read)
                if (!paste.active and paste.esc == 0 and n > 1 and read_buf[0] != 0x1b) {
                    const heuristic_nls = std.mem.count(u8, read_buf[0..n], "\n");
                    if (heuristic_nls >= 2) {
                        ui.finishPaste(read_buf[0..n]);
                        continue;
                    }
                }
                for (read_buf[0..n]) |byte| {
                    handleKey(&ui, byte, &queued_msg, alloc, &paste) catch {};
                }
            }
            agent_thread.join();
            if (agent_ctx.err_msg) |emsg| {
                var err_line: std.ArrayList(u8) = .empty;
                defer err_line.deinit(alloc);
                err_line.appendSlice(alloc, "\x1b[31m  Error: ") catch {};
                err_line.appendSlice(alloc, emsg) catch {};
                err_line.appendSlice(alloc, "\x1b[0m\n") catch {};
                ui.writeAgentLine(err_line.items);
                alloc.free(emsg);
            } else if (agent_ctx.err) |_| {
                ui.writeAgentLine("\x1b[31m  Error occurred.\x1b[0m\n");
            }
            alloc.destroy(agent_ctx);
            agent_busy = false;

            // Blank line between response and next prompt
            ui.writeAgentLine("\n");
            ui.redraw();
            continue;
        }

        // Read input (blocking, agent is idle) — poll with long timeout
        const n = readStdinTimeout(read_buf[0..]);
        if (n == 0) continue;
        // Heuristic: if not currently in a bracketed paste, but the read returned
        // multiple bytes containing at least 2 newlines, treat it as a non-bracketed paste.
        // Skip if the data starts with ESC (bracketed paste marker) — let handleKey parse it.
        if (!paste.active and paste.esc == 0 and n > 1 and read_buf[0] != 0x1b) {
            const heuristic_nls = std.mem.count(u8, read_buf[0..n], "\n");
            if (heuristic_nls >= 2) {
                ui.finishPaste(read_buf[0..n]);
                continue;
            }
        }
        for (read_buf[0..n]) |byte| {
            try handleKey(&ui, byte, &queued_msg, alloc, &paste);
        }
    }
}

// ── Slash command implementations: /models, /login, /logout ──────────────────

/// Saves config to disk. Prints a short error above the prompt if it fails.
fn persistConfig(alloc: std.mem.Allocator, io: std.Io, ui: *LiveUI, mgr: *config_mod.ConfigManager) void {
    mgr.saveFile(alloc, io) catch {
        ui.writeAgentLine("\x1b[31m  Failed to save config.\x1b[0m\n");
    };
}

// ── Full-screen interactive list picker ─────────────────────────────────────

const PickerItem = struct {
    label: []const u8,
    sublabel: []const u8 = "",
};

const PickerKey = union(enum) {
    up,
    down,
    enter,
    escape,
    char: u8,
};

/// Reads a single keypress from stdin (already in raw mode).
/// Uses poll with a short timeout to distinguish a bare ESC from the start
/// of an escape sequence (arrow keys etc).
fn readPickerKey() PickerKey {
    const c_opt = term.readByte();
    if (c_opt == null) return .escape;
    const c = c_opt.?;
    if (c == 0x1b) {
        // Check if more bytes follow quickly (arrow key) or if this is a bare ESC.
        if (!term.stdinReady(10)) return .escape;
        var seq: [2]u8 = undefined;
        if (term.readStdin(seq[0..1]) == 0) return .escape;
        if (seq[0] == '[') {
            if (term.readStdin(seq[1..2]) == 0) return .escape;
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

/// Full-screen scrollable, searchable list picker using the alternate screen
/// buffer. Returns the index of the chosen item, or null if cancelled.
///
/// The caller's prompt box is left on the main screen (NOT erased) before
/// entering the alt screen. The alt screen preserves the main screen, so
/// when we exit, the prompt box is still visible. We save the cursor position
/// with DECSC (\x1b7) before entering the alt screen and restore it with
/// DECRC (\x1b8) after exiting, so the cursor lands back on the prompt's
/// content line regardless of how the terminal handles cursor restoration
/// after `\x1b[?1049l`. The caller's `writeAgentLine` then erases the old
/// prompt and draws a fresh one.
fn runPicker(
    ui: *LiveUI,
    out: *std.Io.File.Writer,
    title: []const u8,
    items: []const PickerItem,
    current_idx: ?usize,
) ?usize {
    const rows = termHeight();
    const max_visible: usize = if (rows > 8) rows - 8 else 10;

    var query: [256]u8 = undefined;
    var query_len: usize = 0;
    var selected: usize = 0;
    var scroll: usize = 0;

    if (current_idx) |ci| {
        if (ci < items.len) selected = ci;
    }

    // Flush the UI writer so any buffered output reaches stdout before we
    // start writing alt-screen sequences through a separate writer.
    {
        ui.mu.lock();
        defer ui.mu.unlock();
        ui.out.flush() catch {};
    }

    // Enter alternate screen, hide cursor. Save cursor first with DECSC so we
    // can restore it after exiting — the terminal may not restore it
    // automatically after \x1b[?1049l. The prompt is left on the main screen
    // (NOT erased) because the alt screen preserves the main screen; when we
    // exit, writeAgentLine will erase the old prompt (using prompt_rows) and
    // draw a fresh one.
    out.interface.writeAll("\x1b7\x1b[?1049h\x1b[?25l") catch {};
    out.flush() catch {};

    while (true) {
        // Build filtered index list.
        var filtered: [512]usize = undefined;
        var filtered_len: usize = 0;
        for (items, 0..) |item, i| {
            if (query_len == 0 or
                std.ascii.indexOfIgnoreCase(item.label, query[0..query_len]) != null or
                std.ascii.indexOfIgnoreCase(item.sublabel, query[0..query_len]) != null)
            {
                if (filtered_len < filtered.len) {
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

        // Render.
        out.interface.writeAll("\x1b[2J\x1b[H") catch {};
        out.interface.print("\x1b[1m{s}\x1b[0m\n", .{title}) catch {};
        if (query_len > 0) {
            out.interface.print("\x1b[2mfilter:\x1b[0m {s}\n", .{query[0..query_len]}) catch {};
        } else {
            out.interface.writeAll("\x1b[2mtype to search, \xe2\x86\x91\xe2\x86\x93 to move, Enter to select, Esc to cancel\x1b[0m\n") catch {};
        }
        out.interface.writeAll("\n") catch {};

        const visible_count = @min(max_visible, filtered_len);
        for (0..visible_count) |i| {
            const idx = filtered[scroll + i];
            const item = items[idx];
            if (i == selected - scroll) {
                out.interface.writeAll("\x1b[1;36m\xe2\x9d\xaf ") catch {};
            } else {
                out.interface.writeAll("  ") catch {};
            }
            out.interface.writeAll(item.label) catch {};
            if (item.sublabel.len > 0) {
                if (i == selected - scroll) {
                    out.interface.print(" \x1b[2;36m{s}\x1b[0m", .{item.sublabel}) catch {};
                } else {
                    out.interface.print(" \x1b[2m{s}\x1b[0m", .{item.sublabel}) catch {};
                }
            }
            out.interface.writeAll("\n") catch {};
        }
        if (filtered_len == 0) {
            out.interface.writeAll("\x1b[2m  no matches\x1b[0m\n") catch {};
        }
        out.interface.print("\n\x1b[2m{d}/{d} shown  \xc2\xb7  Enter=select  Esc=cancel\x1b[0m", .{ visible_count, filtered_len }) catch {};
        out.interface.print("\x1b[{d};1H", .{rows}) catch {}; // move to last line
        out.interface.writeAll("\x1b[K") catch {}; // clear to end
        out.flush() catch {};

        const key = readPickerKey();
        switch (key) {
            .up => {
                if (selected > 0) selected -= 1;
            },
            .down => {
                if (selected + 1 < filtered_len) selected += 1;
            },
            .enter => {
                if (filtered_len == 0) continue;
                // Exit alt screen and restore cursor with DECRC. The main
                // screen (with the prompt box) is restored by the terminal; the
                // cursor is restored by \x1b8 to the content line. The caller's
                // writeAgentLine will erase the old prompt and draw a fresh one.
                out.interface.writeAll("\x1b[?25h\x1b[?1049l\x1b8") catch {};
                out.flush() catch {};
                return filtered[selected];
            },
            .escape => {
                out.interface.writeAll("\x1b[?25h\x1b[?1049l\x1b8") catch {};
                out.flush() catch {};
                return null;
            },
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

/// Interactive model picker for the current provider.
/// Uses a full-screen scrollable, searchable list (like setup).
fn cmdModels(
    alloc: std.mem.Allocator,
    io: std.Io,
    ui: *LiveUI,
    mgr: *config_mod.ConfigManager,
    messages: *std.ArrayList(session.Message),
    sess: *session.Session,
    session_id: i64,
) void {
    _ = sess;
    _ = session_id;
    _ = messages;

    // Fetch the model list (from registry cache or hardcoded fallback).
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const models = registry.fetchModels(arena.allocator(), io, mgr.config.data_dir, mgr.config.provider);

    // Build picker items.
    var items: [512]PickerItem = undefined;
    if (models.len > items.len) return;
    var cur_idx: ?usize = null;
    for (models, 0..) |m, i| {
        var sub: []const u8 = "";
        if (std.mem.eql(u8, m, mgr.config.model)) {
            sub = "current";
            cur_idx = i;
        } else if (i == 0) {
            sub = "default";
        }
        items[i] = .{ .label = m, .sublabel = sub };
    }

    var title_buf: [256]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "Models — {s}", .{mgr.config.provider.name()}) catch "Models";

    const stdout = std.Io.File.stdout();
    var out_buf: [8192]u8 = undefined;
    var out_w = stdout.writer(io, &out_buf);

    const choice = runPicker(ui, &out_w, title, items[0..models.len], cur_idx);
    if (choice) |idx| {
        mgr.setOwnedModel(alloc, models[idx]);
        persistConfig(alloc, io, ui, mgr);
        var buf2: [512]u8 = undefined;
        const s = std.fmt.bufPrint(&buf2, "\x1b[38;5;245m  Switched to {s} / {s}\x1b[0m\n", .{ mgr.config.provider.name(), mgr.config.model }) catch return;
        ui.writeAgentLine(s);
    } else {
        ui.writeAgentLine("\x1b[38;5;245m  Cancelled.\x1b[0m\n");
    }
}

/// Interactive provider login: pick a provider from the full list, then enter
/// an API key in the alt-screen (not inline in chat). Saves to the per-provider
/// key store and persists to disk.
fn cmdLogin(
    alloc: std.mem.Allocator,
    io: std.Io,
    ui: *LiveUI,
    mgr: *config_mod.ConfigManager,
    messages: *std.ArrayList(session.Message),
    sess: *session.Session,
    session_id: i64,
) void {
    _ = messages;
    _ = sess;
    _ = session_id;

    const providers = provider.Provider.all();

    // Build picker items.
    var items: [512]PickerItem = undefined;
    if (providers.len > items.len) return;
    var cur_idx: ?usize = null;
    for (providers, 0..) |p, i| {
        var sub: []const u8 = p.name();
        if (p == mgr.config.provider) {
            cur_idx = i;
            sub = "current";
        } else if (mgr.hasKey(p)) {
            sub = "key saved";
        }
        items[i] = .{ .label = p.slug(), .sublabel = sub };
    }

    const stdout = std.Io.File.stdout();
    var out_buf: [8192]u8 = undefined;
    var out_w = stdout.writer(io, &out_buf);

    const choice = runPicker(ui, &out_w, "Providers", items[0..providers.len], cur_idx);
    if (choice == null) {
        ui.writeAgentLine("\x1b[38;5;245m  Cancelled.\x1b[0m\n");
        return;
    }
    const new_prov = providers[choice.?];

    // Local providers don't need a key.
    if (new_prov.isLocal()) {
        mgr.setProvider(alloc, new_prov);
        persistConfig(alloc, io, ui, mgr);
        var buf2: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&buf2, "\x1b[38;5;245m  Logged in to {s} (local, no key needed).\x1b[0m\n", .{new_prov.name()}) catch return;
        ui.writeAgentLine(s);
        return;
    }

    // Prompt for API key inside the alt-screen so it doesn't corrupt the chat.
    // We reuse the alt-screen infrastructure: enter, show a prompt, read the key,
    // then exit back to the main screen.
    {
        // Flush the UI writer before taking over stdout.
        ui.mu.lock();
        defer ui.mu.unlock();
        ui.out.flush() catch {};
    }

    // Enter alt screen.
    out_w.interface.writeAll("\x1b7\x1b[?1049h\x1b[?25l") catch {};
    out_w.flush() catch {};

    var key_buf: std.ArrayList(u8) = .empty;
    defer key_buf.deinit(alloc);
    key_buf.appendSlice(alloc, "\x1b[2J\x1b[H") catch return;
    key_buf.appendSlice(alloc, "\x1b[1m") catch return;
    key_buf.appendSlice(alloc, new_prov.name()) catch return;
    key_buf.appendSlice(alloc, " API key\x1b[0m\n\n") catch return;
    key_buf.appendSlice(alloc, "Env var: ") catch return;
    key_buf.appendSlice(alloc, new_prov.envKey()) catch return;
    key_buf.appendSlice(alloc, "\n\n\x1b[2mPaste your key (or blank to use env var):\x1b[0m\n> ") catch return;
    out_w.interface.writeAll(key_buf.items) catch {};
    out_w.flush() catch {};

    var api_key_buf: [512]u8 = undefined;
    const api_key_opt = readLineInline(io, &api_key_buf);

    // Exit alt screen, restore cursor.
    out_w.interface.writeAll("\x1b[?25h\x1b[?1049l\x1b8") catch {};
    out_w.flush() catch {};

    // Esc cancels the whole login — don't switch provider or save anything.
    if (api_key_opt == null) {
        ui.writeAgentLine("\x1b[38;5;245m  Cancelled.\x1b[0m\n");
        return;
    }
    const api_key = api_key_opt.?;

    // Switch provider + store key in per-provider key store.
    mgr.setProvider(alloc, new_prov);
    if (api_key.len > 0) {
        mgr.setKeyFor(alloc, new_prov, std.mem.trim(u8, api_key, " \t\r\n"));
    } else {
        // Clear any stored key so env var takes effect on next load.
        mgr.setKeyFor(alloc, new_prov, "");
    }
    persistConfig(alloc, io, ui, mgr);

    var buf3: [256]u8 = undefined;
    const key_status: []const u8 = if (mgr.config.api_key.len > 0) "key saved" else "via env";
    const s = std.fmt.bufPrint(&buf3, "\x1b[38;5;245m  Logged in to {s} / {s} ({s}).\x1b[0m\n", .{ new_prov.name(), mgr.config.model, key_status }) catch return;
    ui.writeAgentLine(s);
}

/// Interactive logout: shows ONLY providers that have a saved API key (the
/// "configured" providers), then removes the key for the chosen one.
fn cmdLogout(
    alloc: std.mem.Allocator,
    io: std.Io,
    ui: *LiveUI,
    mgr: *config_mod.ConfigManager,
) void {
    const configured = mgr.configuredProviders();

    if (configured.len == 0) {
        ui.writeAgentLine("\x1b[38;5;245m  No providers have saved API keys.\x1b[0m\n");
        return;
    }

    // Build picker items — only configured providers.
    var items: [64]PickerItem = undefined;
    if (configured.len > items.len) return;
    var cur_idx: ?usize = null;
    for (configured, 0..) |sk, i| {
        var sub: []const u8 = sk.provider.name();
        if (sk.provider == mgr.config.provider) {
            cur_idx = i;
            sub = "current";
        }
        items[i] = .{ .label = sk.provider.slug(), .sublabel = sub };
    }

    const stdout = std.Io.File.stdout();
    var out_buf: [8192]u8 = undefined;
    var out_w = stdout.writer(io, &out_buf);

    const choice = runPicker(ui, &out_w, "Log out of which provider?", items[0..configured.len], cur_idx);
    if (choice == null) {
        ui.writeAgentLine("\x1b[38;5;245m  Cancelled.\x1b[0m\n");
        return;
    }
    const target = configured[choice.?].provider;

    // Remove the key for the chosen provider.
    mgr.removeKey(alloc, target);
    persistConfig(alloc, io, ui, mgr);
    var db: [256]u8 = undefined;
    const done = std.fmt.bufPrint(&db, "\x1b[38;5;245m  Logged out of {s}. Key removed.\x1b[0m\n", .{target.name()}) catch "\x1b[38;5;245m  Logged out. API key removed.\x1b[0m\n";
    ui.writeAgentLine(done);
}

/// Reads a single line of input from stdin while in raw mode.
/// Echoes characters, handles backspace, returns on Enter.
/// The terminal is already in raw mode (set by chatSession), so we read
/// byte-by-byte via poll+read.
fn readLineInline(io: std.Io, buf: []u8) ?[]const u8 {
    const stdout = std.Io.File.stdout();
    var out_buf: [128]u8 = undefined;
    var w = stdout.writer(io, &out_buf);
    var len: usize = 0;
    while (len < buf.len) {
        const c_opt = term.readByte();
        if (c_opt == null) {
            w.flush() catch {};
            return buf[0..len];
        }
        const c = c_opt.?;
        if (c == '\r' or c == '\n') {
            // Echo newline
            w.interface.writeAll("\r\n") catch {};
            w.flush() catch {};
            return buf[0..len];
        }
        if (c == 0x7f or c == 0x08) {
            if (len > 0) {
                len -= 1;
                w.interface.writeAll("\x08 \x08") catch {};
                w.flush() catch {};
            }
            continue;
        }
        if (c == 0x1b) {
            // ESC: cancel — return null so the caller can distinguish a real
            // cancel from a blank Enter (which returns an empty slice).
            w.flush() catch {};
            return null;
        }
        if (c >= 0x20 and c < 0x7f) {
            buf[len] = c;
            len += 1;
            w.interface.writeByte(c) catch {};
            w.flush() catch {};
        }
    }
    w.flush() catch {};
    return buf[0..len];
}

/// Polls stdin for up to TIMEOUT_MS. Returns bytes read, or 0 on timeout.
fn readStdinTimeout(buf: []u8) usize {
    return term.readStdinTimeout(buf, TIMEOUT_MS);
}

/// Context for the background agent thread.
const AgentCtx = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    config: *config_mod.Config,
    messages: *std.ArrayList(session.Message),
    ui: *LiveUI,
    start_ts: std.Io.Timestamp,
    done: bool = false,
    err: ?anyerror = null,
    /// Human-readable error message captured for display in the chat UI.
    /// Set by the HTTP error callback so the main loop can show it to the
    /// user instead of a generic "Error occurred." line.
    err_msg: ?[]u8 = null,
    sess: *session.Session,
    session_id: i64,
};

/// Runs the agent loop in a background thread.
fn runAgent(ctx: *AgentCtx) void {
    const alloc = ctx.alloc;
    const io = ctx.io;
    const config = ctx.config;
    var messages = ctx.messages;

    // Auto-compact if the conversation is approaching the context window.
    if (compact.maybeCompact(alloc, io, config, messages)) |result| {
        if (std.fmt.allocPrint(alloc,
            "\x1b[2m  ↻ context compacted ({d} → {d} tokens)\x1b[0m\n",
            .{ result.before_tokens, result.after_tokens },
        )) |msg| {
            ctx.ui.writeAgent(msg);
            alloc.free(msg);
        } else |_| {}
    }

    var iteration: usize = 0;
    while (iteration < MAX_TOOL_ITERATIONS) {
        iteration += 1;

        const payload = json.buildPayloadWithTools(alloc, config.provider, config.model, messages.items, config.system_prompt, config.max_tokens, config.temperature, true) catch {
            ctx.err = error.OutOfMemory;
            break;
        };
        defer alloc.free(payload);

        var stream_ctx: StreamCtx = .{
            .alloc = alloc,
            .io = io,
            .config = config,
            .tool_accum = response.ToolCallAccumulator.init(alloc),
            .out = null,
            .ui = ctx.ui,
            .start_ts = ctx.start_ts,
        };
        defer stream_ctx.deinit();

        // Start the thinking spinner
        stream_ctx.restartThinking();

        http_client.streamChat(alloc, io, config.provider, config.provider.chatUrl(), config.api_key, payload, onChunk, onDone, onRetry, onError, @ptrCast(&stream_ctx)) catch |err| {
            stream_ctx.stopThinking();
            if (err != error.HttpBadStatus) {
                ctx.err = err;
            }
            // Surface the captured HTTP error message to the main loop so it
            // can be displayed in the chat UI instead of a generic message.
            if (stream_ctx.err_msg) |m| {
                ctx.err_msg = alloc.dupe(u8, m) catch null;
            } else if (err != error.HttpBadStatus) {
                ctx.err_msg = std.fmt.allocPrint(alloc, "{t}", .{err}) catch null;
            }
            break;
        };

        // No tool calls: save and exit
        if (!stream_ctx.tool_accum.hasToolCalls()) {
            if (stream_ctx.full_reply.items.len > 0) {
                // Save to session DB
                ctx.sess.addMessage(ctx.session_id, .assistant, stream_ctx.full_reply.items) catch {};
                const reply_copy = alloc.dupe(u8, stream_ctx.full_reply.items) catch break;
                messages.append(alloc, .{ .role = .assistant, .content = reply_copy }) catch break;
            }
            // Print stats above the prompt
            printStatsUI(ctx.ui, stream_ctx.start_ts, io);
            break;
        }

        // Execute tool calls
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const tool_calls = stream_ctx.tool_accum.collect(arena.allocator()) catch break;
        if (tool_calls.len == 0) break;

        // Add assistant message with tool_calls
        const reply_copy = alloc.dupe(u8, stream_ctx.full_reply.items) catch break;
        const tcs_copy = alloc.alloc(session.ToolCallRef, tool_calls.len) catch break;
        for (tool_calls, 0..) |tc, i| {
            tcs_copy[i] = .{
                .id = alloc.dupe(u8, tc.id) catch break,
                .name = alloc.dupe(u8, tc.name) catch break,
                .arguments = alloc.dupe(u8, tc.arguments) catch break,
            };
        }
        messages.append(alloc, .{ .role = .assistant, .content = reply_copy, .tool_calls = tcs_copy }) catch break;

        // Execute all tool calls
        const results = arena.allocator().alloc(?tools.ToolResult, tool_calls.len) catch break;
        for (tool_calls, 0..) |tc, i| {
            results[i] = tools.execute(arena.allocator(), io, tc) catch null;
            if (results[i]) |result| {
                const result_copy = alloc.dupe(u8, result.content) catch break;
                const id_copy = alloc.dupe(u8, tc.id) catch break;
                messages.append(alloc, .{
                    .role = .tool,
                    .content = result_copy,
                    .tool_call_id = id_copy,
                }) catch break;
            }
        }
        // Print tool usage summary
        printToolUsageUI(arena.allocator(), ctx.ui, tool_calls, results);
    }

    ctx.done = true;
}

/// State for escape-sequence parsing and bracketed paste mode.
const PasteState = struct {
    active: bool = false,
    /// 0=idle, 1=got ESC, 2=in CSI (collecting params until final byte)
    esc: u8 = 0,
    /// Accumulates pasted bytes (single-line display, no per-char redraw).
    buf: std.ArrayList(u8) = .empty,
    /// Accumulates CSI parameter/intermediate bytes.
    csi_buf: std.ArrayList(u8) = .empty,

    fn deinit(self: *PasteState, alloc: std.mem.Allocator) void {
        self.buf.deinit(alloc);
        self.csi_buf.deinit(alloc);
    }
};

/// Handles a single key byte from stdin in raw mode.
fn handleKey(ui: *LiveUI, byte: u8, queued_msg: *?[]u8, alloc: std.mem.Allocator, paste: *PasteState) !void {
    // ── Escape sequence parser ──────────────────────────────────────────
    // State 0: idle, 1: got ESC, 2: in CSI (collecting until final byte)
    if (paste.esc == 1) {
        if (byte == '[') {
            paste.esc = 2;
            paste.csi_buf.clearRetainingCapacity();
        } else if (byte == 0x1b) {
            // Two ESCs in a row: treat first as actual ESC (cancel/ignore)
            return;
        } else {
            // ── Non-CSI escape sequences (ESC + char) ──
            // macOS Terminal sends these for Option+key combos.
            paste.esc = 0;
            switch (byte) {
                'b' => ui.onWordLeft(), // Option+Left = ESC b
                'f' => ui.onWordRight(), // Option+Right = ESC f
                else => {}, // Unknown Alt+key: ignore
            }
        }
        return;
    }
    if (paste.esc == 2) {
        // Collect CSI bytes until we hit a final byte (0x40–0x7E)
        if (byte >= 0x40 and byte <= 0x7e) {
            paste.esc = 0;
            // Full CSI sequence: csi_buf contains params, byte is the final.
            handleCSI(ui, paste.csi_buf.items, byte, paste, alloc);
            paste.csi_buf.clearRetainingCapacity();
        } else {
            paste.csi_buf.append(alloc, byte) catch {};
        }
        return;
    }
    if (byte == 0x1b) {
        paste.esc = 1;
        return;
    }

    // During paste: buffer bytes silently, no per-char redraw
    if (paste.active) {
        // Convert \r\n and \r to \n, skip the bracketed paste markers
        if (byte == '\r') {
            // Will be followed by \n typically; skip \r
            return;
        }
        paste.buf.append(alloc, byte) catch {};
        return;
    }

    switch (byte) {
        '\r', '\n' => {
            // If dropdown menu is open, accept the selected item before submitting.
            ui.acceptMenu();
            // Enter: submit the current input. takeInput() already hands us
            // an owned, exactly-sized buffer, so take it directly instead of
            // duping (and leaking) it.
            const input = ui.takeInput();
            if (input.len == 0) {
                alloc.free(input);
                return;
            }
            if (queued_msg.*) |old| alloc.free(old);
            queued_msg.* = input;
        },
        0x7f, 0x08 => {
            ui.onBackspace();
        },
        0x09 => {
            // Tab: auto-complete slash commands
            ui.onTab();
        },
        0x03 => {
            return error.Interrupt;
        },
        // Ctrl+A: move to line start (Emacs)
        0x01 => {
            ui.onLineStart();
        },
        // Ctrl+E: move to line end (Emacs)
        0x05 => {
            ui.onLineEnd();
        },
        // Ctrl+B: move cursor left (Emacs)
        0x02 => {
            ui.onCursorLeft();
        },
        // Ctrl+F: move cursor right (Emacs)
        0x06 => {
            ui.onCursorRight();
        },
        // Ctrl+W: delete word backward
        0x17 => {
            ui.onDeleteWord();
        },
        // Ctrl+U: delete to line start
        0x15 => {
            ui.onDeleteToLineStart();
        },
        // Ctrl+K: delete to line end
        0x0b => {
            ui.onDeleteLine();
        },
        // Ctrl+D: forward-delete char; EOF only when input is empty.
        0x04 => {
            if (ui.inputEmpty()) return error.EndOfStream;
            ui.onDelete();
        },
        else => {
            if (byte >= 0x20 and byte < 0x7f) {
                ui.onChar(byte);
            } else if (byte >= 0xc0) {
                ui.onChar(byte);
            }
        },
    }
}

/// Handles a completed CSI escape sequence: \x1b[<params><final>
/// `params` is everything between `[` and the final byte.
/// `final` is the terminating byte (0x40–0x7E).
fn handleCSI(ui: *LiveUI, params: []const u8, final: u8, paste: *PasteState, alloc: std.mem.Allocator) void {
    // Bracketed paste start: \x1b[200~  → params="200", final='~'
    if (final == '~' and std.mem.eql(u8, params, "200")) {
        paste.active = true;
        return;
    }
    // Bracketed paste end: \x1b[201~
    if (final == '~' and std.mem.eql(u8, params, "201")) {
        paste.active = false;
        if (paste.buf.items.len > 0) {
            ui.finishPaste(paste.buf.items);
            paste.buf.clearRetainingCapacity();
        }
        return;
    }
    // Shift+Enter (xterm): \x1b[27;2;13~  → params="27;2;13", final='~'
    if (final == '~' and std.mem.eql(u8, params, "27;2;13")) {
        ui.onNewline();
        return;
    }
    // Shift+Enter (kitty): \x1b[13;2u  → params="13;2", final='u'
    if (final == 'u' and (std.mem.eql(u8, params, "13;2") or std.mem.eql(u8, params, "13;2:1"))) {
        ui.onNewline();
        return;
    }
    // Enter (kitty, unmodified): \x1b[13u → just submit, already handled by \r
    // Tab (kitty flag 1): \x1b[9u → autocomplete
    if (final == 'u' and (std.mem.eql(u8, params, "9") or std.mem.eql(u8, params, "9:1"))) {
        ui.onTab();
        return;
    }
    // Escape (kitty flag 1): \x1b[27u → cancel/close
    if (final == 'u' and (std.mem.eql(u8, params, "27") or std.mem.eql(u8, params, "27:1"))) {
        // Treat as plain Escape: cancel any in-progress escape sequence
        return;
    }
    // Up-arrow: \x1b[A → move selection up in dropdown menu (or history up)
    if (final == 'A' and params.len == 0) {
        ui.onMenuUp();
        return;
    }
    // Down-arrow: \x1b[B → move selection down in dropdown menu (or history down)
    if (final == 'B' and params.len == 0) {
        ui.onMenuDown();
        return;
    }
    // Right-arrow: \x1b[C → accept menu item, or move cursor right
    if (final == 'C' and params.len == 0) {
        if (ui.menu_open) {
            ui.acceptMenu();
        } else {
            ui.onCursorRight();
        }
        return;
    }
    // Left-arrow: \x1b[D → move cursor left (or close menu)
    if (final == 'D' and params.len == 0) {
        if (ui.menu_open) {
            ui.closeMenu();
        } else {
            ui.onCursorLeft();
        }
        return;
    }
    // Kitty protocol arrow keys (flag 1): \x1b[65u=Up \x1b[66u=Down
    // \x1b[67u=Right \x1b[68u=Left
    if (final == 'u' and (std.mem.eql(u8, params, "65") or std.mem.eql(u8, params, "65:1"))) {
        ui.onMenuUp();
        return;
    }
    if (final == 'u' and (std.mem.eql(u8, params, "66") or std.mem.eql(u8, params, "66:1"))) {
        ui.onMenuDown();
        return;
    }
    if (final == 'u' and (std.mem.eql(u8, params, "67") or std.mem.eql(u8, params, "67:1"))) {
        if (ui.menu_open) {
            ui.acceptMenu();
        } else {
            ui.onCursorRight();
        }
        return;
    }
    if (final == 'u' and (std.mem.eql(u8, params, "68") or std.mem.eql(u8, params, "68:1"))) {
        if (ui.menu_open) {
            ui.closeMenu();
        } else {
            ui.onCursorLeft();
        }
        return;
    }
    // Home: \x1b[H or \x1b[1~ → line start (Cmd+Left in macOS Terminal)
    if ((final == 'H' and params.len == 0) or (final == '~' and std.mem.eql(u8, params, "1"))) {
        ui.onLineStart();
        return;
    }
    // End: \x1b[F or \x1b[4~ → line end (Cmd+Right in macOS Terminal)
    if ((final == 'F' and params.len == 0) or (final == '~' and std.mem.eql(u8, params, "4"))) {
        ui.onLineEnd();
        return;
    }
    // Forward-delete: \x1b[3~ → delete char after cursor
    if (final == '~' and std.mem.eql(u8, params, "3")) {
        ui.onDelete();
        return;
    }
    // Ctrl+Left: \x1b[1;5D → word backward (some terminals)
    if (final == 'D' and std.mem.eql(u8, params, "1;5")) {
        ui.onWordLeft();
        return;
    }
    // Ctrl+Right: \x1b[1;5C → word forward (some terminals)
    if (final == 'C' and std.mem.eql(u8, params, "1;5")) {
        ui.onWordRight();
        return;
    }
    // Option+Left: \x1b[1;3D → word backward (iTerm2, some terminals)
    if (final == 'D' and std.mem.eql(u8, params, "1;3")) {
        ui.onWordLeft();
        return;
    }
    // Option+Right: \x1b[1;3C → word forward (iTerm2, some terminals)
    if (final == 'C' and std.mem.eql(u8, params, "1;3")) {
        ui.onWordRight();
        return;
    }
    // Cmd+Left: \x1b[1;9D → line start (some terminals)
    if (final == 'D' and std.mem.eql(u8, params, "1;9")) {
        ui.onLineStart();
        return;
    }
    // Cmd+Right: \x1b[1;9C → line end (some terminals)
    if (final == 'C' and std.mem.eql(u8, params, "1;9")) {
        ui.onLineEnd();
        return;
    }
    // Ctrl+Delete: \x1b[3;5~ → delete word forward
    if (final == '~' and std.mem.eql(u8, params, "3;5")) {
        ui.onDeleteWordForward();
        return;
    }
    // Cmd+Delete: \x1b[3;9~ → delete line (macOS Terminal)
    if (final == '~' and std.mem.eql(u8, params, "3;9")) {
        ui.onDeleteLine();
        return;
    }
    // Cmd+Backspace: \x1b[127;9u (kitty) → delete line
    if (final == 'u' and (std.mem.eql(u8, params, "127;9") or std.mem.eql(u8, params, "127;9:1"))) {
        ui.onDeleteLine();
        return;
    }
    // Plain Backspace: \x1b[127u (kitty protocol flag 1) → delete char backward
    if (final == 'u' and (std.mem.eql(u8, params, "127") or std.mem.eql(u8, params, "127:1"))) {
        ui.onBackspace();
        return;
    }
    // Ctrl+Backspace: \x1b[127;5u (kitty) → delete word backward
    if (final == 'u' and (std.mem.eql(u8, params, "127;5") or std.mem.eql(u8, params, "127;5:1"))) {
        ui.onDeleteWord();
        return;
    }
    // Ctrl+U: \x1b[21u (kitty enhancement) or plain Ctrl+U handled elsewhere
    // Unknown CSI sequence: consume silently (params and final already discarded)
    _ = alloc;
}

/// Counts the number of lines in a text block (for paste indicator).
fn countLines(text: []const u8) usize {
    if (text.len == 0) return 0;
    var count: usize = 1;
    for (text) |c| {
        if (c == '\n') count += 1;
    }
    // Don't count trailing newline as a separate line
    if (text[text.len - 1] == '\n') count -= 1;
    return count;
}

/// Returns true if `ch` is a word character (alphanumeric or underscore).
fn isWordChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or ch == '_';
}

/// Finds the position one word backward from `pos`.
/// Skips whitespace, then skips word chars (or non-word non-space chars).
fn wordBackward(text: []const u8, pos_in: usize) usize {
    var pos = pos_in;
    // Skip trailing whitespace
    while (pos > 0 and isWhitespace(text[pos - 1])) pos -= 1;
    if (pos == 0) return 0;
    const was_word = isWordChar(text[pos - 1]);
    while (pos > 0) {
        const ch = text[pos - 1];
        if (isWhitespace(ch)) break;
        if (was_word != isWordChar(ch)) break;
        pos -= 1;
    }
    return pos;
}

/// Finds the position one word forward from `pos`.
/// Skips whitespace, then skips word chars (or non-word non-space chars).
fn wordForward(text: []const u8, pos_in: usize) usize {
    var pos = pos_in;
    // Skip leading whitespace
    while (pos < text.len and isWhitespace(text[pos])) pos += 1;
    if (pos >= text.len) return text.len;
    const was_word = isWordChar(text[pos]);
    while (pos < text.len) {
        const ch = text[pos];
        if (isWhitespace(ch)) break;
        if (was_word != isWordChar(ch)) break;
        pos += 1;
    }
    return pos;
}

fn isWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n';
}

/// Prints stats above the prompt line.
fn printStatsUI(ui: *LiveUI, start_ts: ?std.Io.Timestamp, io: std.Io) void {
    if (start_ts == null) return;
    const end_ts = std.Io.Timestamp.now(io, .awake);
    const dur_ns = start_ts.?.durationTo(end_ts).nanoseconds;
    const dur_ms = @divTrunc(dur_ns, std.time.ns_per_ms);
    const dur_s = @divTrunc(dur_ms, 1000);
    var buf: [64]u8 = undefined;
    const s = if (dur_s > 0)
        std.fmt.bufPrint(&buf, "\x1b[38;5;245m  {d}s\x1b[0m\n", .{dur_s}) catch return
    else
        std.fmt.bufPrint(&buf, "\x1b[38;5;245m  {d}ms\x1b[0m\n", .{dur_ms}) catch return;
    ui.writeAgentLine(s);
}

/// Prints tool usage above the prompt line.
fn printToolUsageUI(
    arena: std.mem.Allocator,
    ui: *LiveUI,
    tool_calls: []const tools.ToolCall,
    results: []const ?tools.ToolResult,
) void {
    const dim = "\x1b[38;5;245m";
    const reset = "\x1b[0m";

    var read_count: usize = 0;
    var search_count: usize = 0;
    var fetch_count: usize = 0;
    var list_count: usize = 0;
    var other_count: usize = 0;
    var failed_count: usize = 0;
    for (results) |res| {
        if (res == null) {
            failed_count += 1;
            continue;
        }
        const label = tools.toolTypeLabel(res.?.name);
        if (std.mem.eql(u8, label, "read")) read_count += 1 else if (std.mem.eql(u8, label, "search")) search_count += 1 else if (std.mem.eql(u8, label, "fetch")) fetch_count += 1 else if (std.mem.eql(u8, label, "list")) list_count += 1 else other_count += 1;
    }

    var bd: std.ArrayList(u8) = .empty;
    defer bd.deinit(arena);

    const addPart = struct {
        fn run(b: *std.ArrayList(u8), a: std.mem.Allocator, singular: []const u8, plural: []const u8, count: usize, first_p: *bool) void {
            if (count == 0) return;
            if (!first_p.*) b.appendSlice(a, " · ") catch {};
            first_p.* = false;
            const word = if (count == 1) singular else plural;
            const part = std.fmt.allocPrint(a, "{d} {s}", .{ count, word }) catch return;
            b.appendSlice(a, part) catch {};
        }
    }.run;
    var first = true;
    addPart(&bd, arena, "read", "reads", read_count, &first);
    addPart(&bd, arena, "search", "searches", search_count, &first);
    addPart(&bd, arena, "fetch", "fetches", fetch_count, &first);
    addPart(&bd, arena, "list", "lists", list_count, &first);
    if (other_count > 0) addPart(&bd, arena, "tool", "tools", other_count, &first);
    if (failed_count > 0) addPart(&bd, arena, "failed", "failed", failed_count, &first);

    // Build the full output into a single buffer for one writeAgentLine call
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(arena);

    out.appendSlice(arena, "\n") catch return;
    const n = tool_calls.len;
    if (n == 1) {
        out.appendSlice(arena, "\x1b[38;5;255m●\x1b[0m ") catch return;
        out.appendSlice(arena, dim) catch return;
        out.appendSlice(arena, "1 tool call") catch return;
        out.appendSlice(arena, reset) catch return;
    } else {
        var buf: [128]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "\x1b[38;5;255m●\x1b[0m {s}{d} tool calls{s}", .{ dim, n, reset }) catch return;
        out.appendSlice(arena, s) catch return;
    }
    if (bd.items.len > 0) {
        out.appendSlice(arena, " ") catch return;
        out.appendSlice(arena, dim) catch return;
        out.appendSlice(arena, "· ") catch return;
        out.appendSlice(arena, bd.items) catch return;
        out.appendSlice(arena, reset) catch return;
    }
    out.appendSlice(arena, "\n") catch return;

    for (tool_calls, 0..) |tc, i| {
        const connector = if (i < tool_calls.len - 1) "├ " else "└ ";
        const verb = tools.toolVerb(tc.name);
        const detail = tools.toolDetail(tc.name, tc.arguments);
        const max_detail = 100;
        const display_detail = if (detail.len > max_detail) detail[0..max_detail] else detail;
        out.appendSlice(arena, dim) catch return;
        out.appendSlice(arena, connector) catch return;
        out.appendSlice(arena, verb) catch return;
        if (display_detail.len > 0) {
            out.appendSlice(arena, " ") catch return;
            out.appendSlice(arena, display_detail) catch return;
        }
        out.appendSlice(arena, reset) catch return;
        out.appendSlice(arena, "\n") catch return;
    }

    ui.writeAgentLine(out.items);
}

test "unescape basic" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try unescapeAppend(std.testing.allocator, &buf, "hello\\nworld");
    try std.testing.expectEqualStrings("hello\nworld", buf.items);
}

test "unescape unicode" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try unescapeAppend(std.testing.allocator, &buf, "\\u0041");
    try std.testing.expectEqualStrings("A", buf.items);
}

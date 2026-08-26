const std = @import("std");
const provider = @import("provider.zig");

/// Maximum number of per-provider API keys we track.
pub const MAX_KEYS = 64;

pub const Config = struct {
    provider: provider.Provider = .openai,
    model: []const u8 = "",
    api_key: []const u8 = "",
    system_prompt: []const u8 = "You are a helpful assistant.",
    db_path: []const u8 = "",
    data_dir: []const u8 = "",
    max_tokens: u32 = 4096,
    temperature: f64 = 0.7,

    pub fn resolveDefaultModel(self: *Config) void {
        if (self.model.len == 0) {
            self.model = self.provider.defaultModel();
        }
    }
};

/// A per-provider API key entry. `provider` is the enum value, `key` is owned.
pub const StoredKey = struct {
    provider: provider.Provider,
    key: []const u8,
};

pub const ConfigManager = struct {
    config: Config = .{},
    /// Owned slices allocated during load()/loadFile()/setup; freed in deinit.
    /// null means the corresponding config field points into environ memory
    /// or a comptime string literal.
    owned_data_dir: ?[]u8 = null,
    owned_db_path: ?[]u8 = null,
    owned_model: ?[]u8 = null,
    owned_api_key: ?[]u8 = null,
    owned_system_prompt: ?[]u8 = null,

    /// Per-provider saved API keys (owned). Loaded from key.<slug> lines in the
    /// config file. The active config.api_key is the one for config.provider,
    /// resolved from here or env vars at load time.
    keys: [MAX_KEYS]StoredKey = undefined,
    keys_len: usize = 0,

    pub fn load(self: *ConfigManager, alloc: std.mem.Allocator, environ: *const std.process.Environ.Map) void {
        // Data directory: $AI_DATA_DIR or ~/.ai
        self.config.data_dir = environ.get("AI_DATA_DIR") orelse "";
        if (self.config.data_dir.len == 0) {
            const home = environ.get("HOME") orelse ".";
            if (std.fmt.allocPrint(alloc, "{s}/.ai", .{home})) |dir| {
                self.owned_data_dir = dir;
                self.config.data_dir = dir;
            } else |_| return;
        }

        // Database path
        self.config.db_path = environ.get("AI_DB_PATH") orelse "";
        if (self.config.db_path.len == 0) {
            if (std.fmt.allocPrint(alloc, "{s}/sessions.db", .{self.config.data_dir})) |path| {
                self.owned_db_path = path;
                self.config.db_path = path;
            } else |_| return;
        }

        // Provider
        if (environ.get("AI_PROVIDER")) |p| {
            if (provider.Provider.parse(p)) |prov| {
                self.config.provider = prov;
            }
        }

        // Model
        self.config.model = environ.get("AI_MODEL") orelse "";
        self.config.resolveDefaultModel();

        // API key: check provider-specific env var first, then generic AI_API_KEY
        const key_env = self.config.provider.envKey();
        self.config.api_key = environ.get(key_env) orelse "";
        if (self.config.api_key.len == 0) {
            self.config.api_key = environ.get("AI_API_KEY") orelse "";
        }

        // System prompt
        if (environ.get("AI_SYSTEM_PROMPT")) |sp| {
            self.config.system_prompt = sp;
        }

        // Max tokens
        if (environ.get("AI_MAX_TOKENS")) |mt| {
            if (std.fmt.parseInt(u32, mt, 10)) |val| {
                self.config.max_tokens = val;
            } else |_| {}
        }
    }

    pub fn ensureDataDir(self: *ConfigManager, io: std.Io) !void {
        std.Io.Dir.cwd().createDirPath(io, self.config.data_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    /// Path to the persisted config file: <data_dir>/config
    pub fn configFilePath(self: *const ConfigManager, alloc: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(alloc, "{s}/config", .{self.config.data_dir});
    }

    /// Loads config from <data_dir>/config if present. Simple "key=value" lines.
    /// Environment variables still take precedence; this only fills fields that
    /// are still at their defaults.
    pub fn loadFile(self: *ConfigManager, alloc: std.mem.Allocator, io: std.Io) void {
        const path = std.fmt.allocPrint(alloc, "{s}/config", .{self.config.data_dir}) catch return;
        defer alloc.free(path);

        var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return;
        defer file.close(io);

        var buf: [4096]u8 = undefined;
        const n = file.readPositionalAll(io, &buf, 0) catch return;
        const content = buf[0..n];

        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = std.mem.trim(u8, line[0..eq], " \t");
            const val = std.mem.trim(u8, line[eq + 1 ..], " \t");
            if (val.len == 0) continue;

            if (std.mem.eql(u8, key, "provider")) {
                if (provider.Provider.parse(val)) |p| self.config.provider = p;
            } else if (std.mem.eql(u8, key, "model")) {
                self.setOwnedModel(alloc, val);
            } else if (std.mem.eql(u8, key, "api_key")) {
                // Legacy single key line (backwards compat): store it for the
                // current provider.
                self.setKeyFor(alloc, self.config.provider, val);
            } else if (std.mem.eql(u8, key, "system_prompt")) {
                self.setOwnedSystemPrompt(alloc, val);
            } else if (std.mem.eql(u8, key, "max_tokens")) {
                if (std.fmt.parseInt(u32, val, 10)) |t| {
                    self.config.max_tokens = t;
                } else |_| {}
            } else if (std.mem.startsWith(u8, key, "key.")) {
                // Per-provider key: key.<slug>=<value>
                const slug = key[4..];
                if (provider.Provider.parse(slug)) |p| {
                    self.setKeyFor(alloc, p, val);
                }
            }
        }

        // After loading keys, resolve the active key for the current provider.
        // If env var already set one, it takes precedence; otherwise use the
        // stored key (the key store owns it, so just point config.api_key at it).
        if (self.config.api_key.len == 0) {
            const stored = self.getKeyFor(self.config.provider);
            if (stored.len > 0) {
                self.config.api_key = stored;
                self.owned_api_key = null; // store owns the key
            }
        }
    }

    /// Sets config.model from a heap-owned copy, tracking it for cleanup.
    pub fn setOwnedModel(self: *ConfigManager, alloc: std.mem.Allocator, val: []const u8) void {
        if (alloc.dupe(u8, val)) |dup| {
            if (self.owned_model) |old| alloc.free(old);
            self.owned_model = dup;
            self.config.model = dup;
        } else |_| {}
    }

    /// Sets config.api_key from a heap-owned copy, tracking it for cleanup.
    pub fn setOwnedApiKey(self: *ConfigManager, alloc: std.mem.Allocator, val: []const u8) void {
        if (alloc.dupe(u8, val)) |dup| {
            if (self.owned_api_key) |old| alloc.free(old);
            self.owned_api_key = dup;
            self.config.api_key = dup;
        } else |_| {}
    }

    /// Sets config.system_prompt from a heap-owned copy, tracking it for cleanup.
    pub fn setOwnedSystemPrompt(self: *ConfigManager, alloc: std.mem.Allocator, val: []const u8) void {
        if (alloc.dupe(u8, val)) |dup| {
            if (self.owned_system_prompt) |old| alloc.free(old);
            self.owned_system_prompt = dup;
            self.config.system_prompt = dup;
        } else |_| {}
    }

    /// Stores a per-provider API key. Replaces any existing key for the same
    /// provider. The key slice is heap-owned by the key store and tracked for
    /// cleanup in deinit().
    pub fn setKeyFor(self: *ConfigManager, alloc: std.mem.Allocator, prov: provider.Provider, key: []const u8) void {
        // If key is empty, remove the entry entirely.
        if (key.len == 0) {
            self.removeKey(alloc, prov);
            return;
        }
        const dup = alloc.dupe(u8, key) catch return;
        // Check if we already have an entry for this provider.
        for (0..self.keys_len) |i| {
            if (self.keys[i].provider == prov) {
                alloc.free(self.keys[i].key);
                self.keys[i].key = dup;
                // Point the active key at the stored key (store owns it).
                if (prov == self.config.provider) {
                    self.config.api_key = dup;
                    self.owned_api_key = null; // store owns the key, not owned_api_key
                }
                return;
            }
        }
        // New entry.
        if (self.keys_len >= MAX_KEYS) {
            alloc.free(dup);
            return;
        }
        self.keys[self.keys_len] = .{ .provider = prov, .key = dup };
        self.keys_len += 1;
        // Point the active key at the stored key (store owns it).
        if (prov == self.config.provider) {
            self.config.api_key = dup;
            self.owned_api_key = null; // store owns the key, not owned_api_key
        }
    }

    /// Removes a stored key for a provider. Frees the owned key slice.
    pub fn removeKey(self: *ConfigManager, alloc: std.mem.Allocator, prov: provider.Provider) void {
        var i: usize = 0;
        while (i < self.keys_len) : (i += 1) {
            if (self.keys[i].provider == prov) {
                // If this key is the active key, clear it first.
                if (prov == self.config.provider) {
                    self.config.api_key = "";
                    self.owned_api_key = null;
                }
                alloc.free(self.keys[i].key);
                // Shift remaining entries down.
                var j: usize = i;
                while (j + 1 < self.keys_len) : (j += 1) {
                    self.keys[j] = self.keys[j + 1];
                }
                self.keys_len -= 1;
                return;
            }
        }
    }

    /// Returns the stored key for a provider, or "" if none.
    pub fn getKeyFor(self: *const ConfigManager, prov: provider.Provider) []const u8 {
        for (0..self.keys_len) |i| {
            if (self.keys[i].provider == prov) return self.keys[i].key;
        }
        return "";
    }

    /// Returns true if a key is stored for the given provider.
    pub fn hasKey(self: *const ConfigManager, prov: provider.Provider) bool {
        for (0..self.keys_len) |i| {
            if (self.keys[i].provider == prov) return true;
        }
        return false;
    }

    /// Returns the list of providers that have a saved key.
    pub fn configuredProviders(self: *const ConfigManager) []const StoredKey {
        return self.keys[0..self.keys_len];
    }

    /// Switches the active provider and resets the model to that provider's
    /// default. Also swaps the active API key from the per-provider key store
    /// (or clears it if no key is stored for the new provider).
    pub fn setProvider(self: *ConfigManager, alloc: std.mem.Allocator, prov: provider.Provider) void {
        self.config.provider = prov;
        self.setOwnedModel(alloc, prov.defaultModel());
        // Swap in the stored key for this provider (if any). The key store owns
        // the key, so we just point config.api_key at it — no duplicate needed.
        const stored = self.getKeyFor(prov);
        if (stored.len > 0) {
            // Don't use setOwnedApiKey — that would duplicate and cause a
            // double-free with the key store. Just point at the stored key.
            self.config.api_key = stored;
            self.owned_api_key = null;
        } else {
            self.setOwnedApiKey(alloc, "");
        }
    }

    /// Persists the current config to <data_dir>/config as "key=value" lines.
    /// Per-provider API keys are written as key.<slug>=<value>.
    pub fn saveFile(self: *const ConfigManager, alloc: std.mem.Allocator, io: std.Io) !void {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(alloc);

        try buf.appendSlice(alloc, "# io config - generated by first-time setup\n");
        try buf.print(alloc, "provider={s}\n", .{self.config.provider.slug()});
        try buf.print(alloc, "model={s}\n", .{self.config.model});
        try buf.print(alloc, "system_prompt={s}\n", .{self.config.system_prompt});
        try buf.print(alloc, "max_tokens={d}\n", .{self.config.max_tokens});

        // Write per-provider keys.
        for (0..self.keys_len) |i| {
            try buf.print(alloc, "key.{s}={s}\n", .{ self.keys[i].provider.slug(), self.keys[i].key });
        }

        const path = try std.fmt.allocPrint(alloc, "{s}/config", .{self.config.data_dir});
        defer alloc.free(path);

        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = path,
            .data = buf.items,
        });
    }

    /// Frees all owned slices allocated during load()/loadFile().
    pub fn deinit(self: *ConfigManager, alloc: std.mem.Allocator) void {
        if (self.owned_data_dir) |dir| alloc.free(dir);
        if (self.owned_db_path) |path| alloc.free(path);
        if (self.owned_model) |m| alloc.free(m);
        if (self.owned_api_key) |k| alloc.free(k);
        if (self.owned_system_prompt) |sp| alloc.free(sp);
        // Free per-provider key store.
        for (0..self.keys_len) |i| {
            alloc.free(self.keys[i].key);
        }
    }
};

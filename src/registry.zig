const std = @import("std");
const provider = @import("provider.zig");
const http_client = @import("http_client.zig");

/// The registry URL — models.dev's live JSON catalog of all providers + models.
const REGISTRY_URL = "https://models.dev/api.json";

/// Cache file path relative to data_dir: <data_dir>/registry.json
/// Max age before we re-fetch: 24 hours.
const CACHE_TTL_SECONDS: i64 = 24 * 60 * 60;

/// Maximum number of models we'll collect per provider.
const MAX_MODELS = 256;

/// Fetches the model list for `prov` from the models.dev registry.
///
/// Strategy:
///   1. Check the local cache file (<data_dir>/registry.json).
///   2. If it's fresh (< 24h old), parse it.
///   3. If stale or missing, try to re-fetch from models.dev.
///   4. If the fetch fails (offline), fall back to the stale cache.
///   5. If no cache at all, fall back to the hardcoded `prov.models()`.
///
/// On success, returns a slice of model ID strings (allocated from `arena`).
/// On failure (no network, no cache, provider not in registry), returns the
/// hardcoded fallback list from `prov.models()`.
pub fn fetchModels(
    arena: std.mem.Allocator,
    io: std.Io,
    data_dir: []const u8,
    prov: provider.Provider,
) []const []const u8 {
    // Local providers and providers not in the registry use hardcoded lists.
    const reg_id = prov.registryId() orelse {
        return prov.models();
    };

    // Try to get the JSON blob from cache or network.
    const json_blob = loadOrFetch(arena, io, data_dir) catch {
        return prov.models();
    };

    // Parse the JSON and extract model IDs for this provider.
    return parseProviderModels(arena, json_blob, reg_id) catch {
        return prov.models();
    };
}

/// Loads the registry JSON from cache, or fetches it from the network if stale.
/// Returns the raw JSON bytes (owned by `arena`).
fn loadOrFetch(
    arena: std.mem.Allocator,
    io: std.Io,
    data_dir: []const u8,
) ![]const u8 {
    const cache_path = try std.fmt.allocPrint(arena, "{s}/registry.json", .{data_dir});

    // Check if cache exists and is fresh.
    if (loadCacheIfFresh(arena, io, cache_path)) |cached| {
        return cached;
    } else |_| {}

    // Cache is stale or missing — try to fetch from network.
    const fetched = fetchRegistry(arena, io) catch |err| {
        // Network failed — try to use stale cache as a last resort.
        return loadCacheStale(arena, io, cache_path) catch return err;
    };

    // Save the fresh data to cache for next time.
    saveCache(io, cache_path, fetched) catch {};

    return fetched;
}

/// Loads the cache file only if it exists and is less than CACHE_TTL_SECONDS old.
fn loadCacheIfFresh(
    arena: std.mem.Allocator,
    io: std.Io,
    cache_path: []const u8,
) ![]const u8 {
    var file = std.Io.Dir.cwd().openFile(io, cache_path, .{}) catch return error.FileNotFound;
    defer file.close(io);

    const stat = file.stat(io) catch return error.FileNotFound;
    const mtime = stat.mtime;

    // Check freshness: compare mtime to now (both in seconds since epoch).
    const now_ts = std.Io.Timestamp.now(io, .real);
    const now_s = now_ts.toSeconds();
    const mtime_s = mtime.toSeconds();
    const age = now_s - mtime_s;
    if (age > CACHE_TTL_SECONDS) return error.CacheStale;

    const buf = arena.alloc(u8, stat.size) catch return error.OutOfMemory;
    _ = file.readPositionalAll(io, buf, 0) catch return error.ReadFailed;
    return buf;
}

/// Loads the cache file regardless of age (fallback when network is down).
fn loadCacheStale(
    arena: std.mem.Allocator,
    io: std.Io,
    cache_path: []const u8,
) ![]const u8 {
    var file = std.Io.Dir.cwd().openFile(io, cache_path, .{}) catch return error.FileNotFound;
    defer file.close(io);

    const stat = file.stat(io) catch return error.FileNotFound;
    const buf = arena.alloc(u8, stat.size) catch return error.OutOfMemory;
    _ = file.readPositionalAll(io, buf, 0) catch return error.ReadFailed;
    return buf;
}

/// Fetches the registry JSON from models.dev over HTTP.
fn fetchRegistry(
    arena: std.mem.Allocator,
    io: std.Io,
) ![]const u8 {
    var body: std.Io.Writer.Allocating = .init(arena);
    defer body.deinit();

    const status = http_client.fetchJson(arena, io, REGISTRY_URL, &body.writer) catch return error.HttpFailed;
    if (@intFromEnum(status) >= 400) return error.HttpBadStatus;

    return body.toOwnedSlice() catch return error.OutOfMemory;
}

/// Writes the registry JSON to the cache file.
fn saveCache(io: std.Io, cache_path: []const u8, data: []const u8) !void {
    std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = cache_path,
        .data = data,
    }) catch return error.WriteFailed;
}

/// Parses the registry JSON and extracts model IDs for `provider_id`.
///
/// The JSON structure is:
///   { "provider-id": { "models": { "model-id": { "id": "model-id", ... }, ... } } }
///
/// We extract the "id" field from each model entry. If the "id" field is
/// missing, we use the object key as the model ID.
fn parseProviderModels(
    arena: std.mem.Allocator,
    json_blob: []const u8,
    provider_id: []const u8,
) ![]const []const u8 {
    var parsed = std.json.parseFromSlice(
        std.json.Value,
        arena,
        json_blob,
        .{},
    ) catch return error.ParseFailed;
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.NotAnObject;

    // Look up the provider by ID.
    const prov_val = root.object.get(provider_id) orelse return error.ProviderNotFound;
    if (prov_val != .object) return error.NotAnObject;

    // Get the "models" object.
    const models_val = prov_val.object.get("models") orelse return error.NoModels;
    if (models_val != .object) return error.NotAnObject;

    // Collect model IDs from the models object.
    var list = std.ArrayList([]const u8).empty;
    const keys = models_val.object.keys();
    const values = models_val.object.values();

    for (keys, values) |key, val| {
        if (list.items.len >= MAX_MODELS) break;

        // Prefer the "id" field if present; otherwise use the object key.
        const model_id: []const u8 = blk: {
            if (val == .object) {
                if (val.object.get("id")) |id_val| {
                    if (id_val == .string) {
                        break :blk id_val.string;
                    }
                }
            }
            break :blk key;
        };

        // Skip non-text models (image-only, embedding, TTS, etc.) — we only
        // want models that accept text input, since this is a chat tool.
        if (shouldSkipModel(val, model_id)) continue;

        const owned = try arena.dupe(u8, model_id);
        try list.append(arena, owned);
    }

    if (list.items.len == 0) return error.NoModels;

    // Sort alphabetically for a stable, predictable display.
    std.mem.sort([]const u8, list.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    return list.toOwnedSlice(arena) catch return error.OutOfMemory;
}

/// Returns true if the model should be excluded from the chat model list.
/// We skip models that don't accept text input (image generation, TTS,
/// embeddings, transcription, video generation, etc.) or that are clearly
/// not chat completion models.
fn shouldSkipModel(val: std.json.Value, model_id: []const u8) bool {
    if (val != .object) return false;

    // Filter by model ID name — skip obvious non-chat model types.
    if (containsAny(model_id, &.{
        "embedding", "embed", "tts", "whisper", "transcrib",
        "realtime", "image", "vision-only", "flux", "veo",
        "lyria", "video", "audio", "safeguard", "guard",
        "prompt-guard", "content-safety", "safety",
    })) return true;

    // Check modalities — skip if input doesn't include "text".
    if (val.object.get("modalities")) |mods| {
        if (mods == .object) {
            if (mods.object.get("input")) |input_mods| {
                if (input_mods == .array) {
                    var has_text = false;
                    for (input_mods.array.items) |item| {
                        if (item == .string and std.mem.eql(u8, item.string, "text")) {
                            has_text = true;
                            break;
                        }
                    }
                    if (!has_text) return true; // no text input → skip
                }
            }
        }
    }

    // Check context limit — skip if context is 0 (non-chat models like image gen).
    if (val.object.get("limit")) |limit_val| {
        if (limit_val == .object) {
            if (limit_val.object.get("context")) |ctx| {
                if (ctx == .integer and ctx.integer == 0) return true;
            }
        }
    }

    return false;
}

/// Returns true if `s` contains any of the substrings in `needles` (case-insensitive).
fn containsAny(s: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.ascii.indexOfIgnoreCase(s, needle) != null) return true;
    }
    return false;
}

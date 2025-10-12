//! Configuration management powered by flare.

const std = @import("std");
const flare = @import("flare");
const zlog = @import("zlog");
const math = std.math;

const empty_allowlist = [_][]const u8{};

pub const Config = struct {
    daemon: Daemon = .{},
    logging: Logging = .{},
    providers: ProviderMatrix = .{},
};

pub const Daemon = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 50051,
    health_port: ?u16 = null,

    pub fn endpoint(self: Daemon, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}:{d}", .{ self.host, self.port });
    }
};

pub const Logging = struct {
    level: []const u8 = "info",
    file_path: ?[]const u8 = null,

    pub fn toLevel(self: Logging) zlog.Level {
        if (std.ascii.eqlIgnoreCase(self.level, "trace")) return .debug;
        if (std.ascii.eqlIgnoreCase(self.level, "debug")) return .debug;
        if (std.ascii.eqlIgnoreCase(self.level, "warn")) return .warn;
        if (std.ascii.eqlIgnoreCase(self.level, "warning")) return .warn;
        if (std.ascii.eqlIgnoreCase(self.level, "error")) return .err;
        if (std.ascii.eqlIgnoreCase(self.level, "err")) return .err;
        if (std.ascii.eqlIgnoreCase(self.level, "fatal")) return .fatal;
        if (std.ascii.eqlIgnoreCase(self.level, "critical")) return .fatal;
        return .info;
    }
};

pub const ProviderMatrix = struct {
    default_strategy: []const u8 = "auto",
    allowlist: []const []const u8 = empty_allowlist[0..],
};

pub const LoadedConfig = struct {
    raw: ?flare.Config = null,
    config: Config,

    pub fn deinit(self: *LoadedConfig) void {
        if (self.raw) |*raw_cfg| {
            raw_cfg.deinit();
        }
    }

    pub fn data(self: *LoadedConfig) *const Config {
        return &self.config;
    }
};

pub fn defaults() Config {
    return .{};
}

pub fn load(allocator: std.mem.Allocator) !LoadedConfig {
    const file_sources = [_]flare.FileSource{
        .{ .path = "reaper.toml", .required = false },
        .{ .path = "./reaper.toml", .required = false },
        .{ .path = "~/.config/reaper/reaper.toml", .required = false },
        .{ .path = "/etc/reaper/reaper.toml", .required = false },
    };

    const load_options = flare.LoadOptions{
        .files = &file_sources,
        .env = .{ .prefix = "REAPER" },
    };

    var raw = try flare.load(allocator, load_options);
    errdefer raw.deinit();

    var cfg = defaults();
    applyRawConfig(&raw, &cfg);

    return LoadedConfig{
        .raw = raw,
        .config = cfg,
    };
}

pub fn loadOrDefault(allocator: std.mem.Allocator) LoadedConfig {
    return load(allocator) catch LoadedConfig{ .raw = null, .config = defaults() };
}

fn applyRawConfig(raw: *flare.Config, cfg: *Config) void {
    cfg.daemon.host = raw.getString("daemon.host", cfg.daemon.host) catch cfg.daemon.host;

    const default_port: i64 = math.cast(i64, cfg.daemon.port) orelse 0;
    const max_port: i64 = math.cast(i64, math.maxInt(u16)) orelse 65535;
    const port_value = raw.getInt("daemon.port", default_port) catch default_port;
    if (port_value >= 0 and port_value <= max_port) {
        if (math.cast(u16, port_value)) |converted| {
            cfg.daemon.port = converted;
        }
    }

    const health_port_value = raw.getInt("daemon.health_port", null) catch null;
    if (health_port_value) |hp| {
        if (hp >= 0 and hp <= max_port) {
            if (math.cast(u16, hp)) |converted_hp| {
                cfg.daemon.health_port = converted_hp;
            } else {
                cfg.daemon.health_port = null;
            }
        } else {
            cfg.daemon.health_port = null;
        }
    }

    cfg.logging.level = raw.getString("logging.level", cfg.logging.level) catch cfg.logging.level;
    const maybe_file_path = raw.getString("logging.file_path", null) catch null;
    if (maybe_file_path) |file_path| {
        cfg.logging.file_path = file_path;
    }

    cfg.providers.default_strategy = raw.getString("providers.default_strategy", cfg.providers.default_strategy) catch cfg.providers.default_strategy;
    cfg.providers.allowlist = raw.getStringList("providers.allowlist") catch cfg.providers.allowlist;
}

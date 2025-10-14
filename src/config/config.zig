//! Configuration management powered by flare.

const std = @import("std");
const flare = @import("flare");
const Schema = flare.Schema;
const zlog = @import("zlog");
const math = std.math;

const default_pid_file: []const u8 = "/tmp/reaper.pid";

const empty_allowlist = [_][]const u8{};
const empty_string_list = [_][]const u8{};
const default_api_capabilities = [_][]const u8{ "completion", "chat" };
const default_copilot_capabilities = [_][]const u8{ "completion", "chat", "agent" };
const key_buffer_len: usize = 160;

pub const Config = struct {
    daemon: Daemon = .{},
    logging: Logging = .{},
    providers: ProviderMatrix = .{},
};

pub const Daemon = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 50051,
    health_port: ?u16 = null,
    pid_file: []const u8 = default_pid_file,

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
    openai: ApiProviderConfig = .{},
    anthropic: ApiProviderConfig = .{},
    xai: ApiProviderConfig = .{},
    azure_openai: AzureOpenAIConfig = .{},
    github_copilot: CopilotConfig = .{},
};

pub const ApiProviderConfig = struct {
    enabled: bool = false,
    vault_path: ?[]const u8 = null,
    default_model: ?[]const u8 = null,
    model_allowlist: []const []const u8 = empty_string_list[0..],
    capabilities: []const []const u8 = default_api_capabilities[0..],
};

pub const AzureOpenAIConfig = struct {
    enabled: bool = false,
    vault_path: ?[]const u8 = null,
    resource: ?[]const u8 = null,
    deployment: ?[]const u8 = null,
    api_version: []const u8 = "2024-07-01-preview",
    default_model: ?[]const u8 = null,
    model_allowlist: []const []const u8 = empty_string_list[0..],
    capabilities: []const []const u8 = default_api_capabilities[0..],
};

pub const CopilotConfig = struct {
    enabled: bool = false,
    vault_path: ?[]const u8 = null,
    default_product: []const u8 = "copilot-gpt-4.1",
    allowed_variants: []const []const u8 = empty_string_list[0..],
    capabilities: []const []const u8 = default_copilot_capabilities[0..],
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

    try validateRawConfig(allocator, &raw);

    var cfg = defaults();
    applyRawConfig(&raw, &cfg);

    return LoadedConfig{
        .raw = raw,
        .config = cfg,
    };
}

pub fn loadOrDefault(allocator: std.mem.Allocator) LoadedConfig {
    return load(allocator) catch |err| blk: {
        std.log.err("Failed to load config; falling back to defaults: {s}", .{@errorName(err)});
        break :blk LoadedConfig{ .raw = null, .config = defaults() };
    };
}

fn validateRawConfig(allocator: std.mem.Allocator, raw: *flare.Config) !void {
    var schema_arena = std.heap.ArenaAllocator.init(allocator);
    defer schema_arena.deinit();

    var root_schema = try buildSchema(schema_arena.allocator());

    var validation = try flare.validateConfig(allocator, raw, &root_schema);
    defer validation.deinit(allocator);

    if (validation.warnings.items.len > 0) {
        for (validation.warnings.items) |warn| {
            std.log.warn("Config validation warning at {s}: {s}", .{ warn.path, warn.message });
        }
    }

    if (validation.hasErrors()) {
        std.log.err("Config validation failed with {d} error(s)", .{validation.errors.items.len});
        for (validation.errors.items) |err| {
            std.log.err("  at {s}: {s}", .{ err.path, err.message });
        }
        return error.InvalidConfig;
    }
}

fn buildSchema(allocator: std.mem.Allocator) !Schema {
    const allowlist_item_schema = try allocator.create(Schema);
    allowlist_item_schema.* = Schema.string(.{ .min_length = 1 });

    var daemon_fields = std.StringHashMap(*const Schema).init(allocator);
    const daemon_host = try allocator.create(Schema);
    daemon_host.* = Schema.string(.{ .min_length = 1 }).default(flare.Value{ .string_value = "127.0.0.1" });
    try daemon_fields.put("host", daemon_host);

    const daemon_port = try allocator.create(Schema);
    daemon_port.* = Schema.int(.{ .min = 1, .max = 65535 }).default(flare.Value{ .int_value = 50051 });
    try daemon_fields.put("port", daemon_port);

    const daemon_health_port = try allocator.create(Schema);
    daemon_health_port.* = Schema.int(.{ .min = 1, .max = 65535 });
    try daemon_fields.put("health_port", daemon_health_port);

    const daemon_pid_file = try allocator.create(Schema);
    daemon_pid_file.* = Schema.string(.{ .min_length = 1 }).default(flare.Value{ .string_value = default_pid_file });
    try daemon_fields.put("pid_file", daemon_pid_file);

    const daemon_schema_ptr = try allocator.create(Schema);
    daemon_schema_ptr.* = Schema{
        .schema_type = .object,
        .fields = daemon_fields,
    };

    var logging_fields = std.StringHashMap(*const Schema).init(allocator);
    const logging_level = try allocator.create(Schema);
    logging_level.* = Schema.string(.{ .min_length = 1 }).default(flare.Value{ .string_value = "info" });
    try logging_fields.put("level", logging_level);

    const logging_file_path = try allocator.create(Schema);
    logging_file_path.* = Schema.string(.{ .min_length = 1 });
    try logging_fields.put("file_path", logging_file_path);

    const logging_schema_ptr = try allocator.create(Schema);
    logging_schema_ptr.* = Schema{
        .schema_type = .object,
        .fields = logging_fields,
    };

    var providers_fields = std.StringHashMap(*const Schema).init(allocator);
    const providers_default_strategy = try allocator.create(Schema);
    providers_default_strategy.* = Schema.string(.{ .min_length = 1 }).default(flare.Value{ .string_value = "auto" });
    try providers_fields.put("default_strategy", providers_default_strategy);

    const providers_allowlist = try allocator.create(Schema);
    providers_allowlist.* = Schema.array(.{ .min_items = 0, .item_schema = allowlist_item_schema });
    try providers_fields.put("allowlist", providers_allowlist);

    const providers_openai = try createApiProviderSchema(allocator);
    try providers_fields.put("openai", providers_openai);

    const providers_anthropic = try createApiProviderSchema(allocator);
    try providers_fields.put("anthropic", providers_anthropic);

    const providers_xai = try createApiProviderSchema(allocator);
    try providers_fields.put("xai", providers_xai);

    const providers_azure = try createAzureProviderSchema(allocator);
    try providers_fields.put("azure_openai", providers_azure);

    const providers_copilot = try createCopilotProviderSchema(allocator);
    try providers_fields.put("github_copilot", providers_copilot);

    const providers_schema_ptr = try allocator.create(Schema);
    providers_schema_ptr.* = Schema{
        .schema_type = .object,
        .fields = providers_fields,
    };

    var root_fields = std.StringHashMap(*const Schema).init(allocator);
    try root_fields.put("daemon", daemon_schema_ptr);
    try root_fields.put("logging", logging_schema_ptr);
    try root_fields.put("providers", providers_schema_ptr);

    return Schema{
        .schema_type = .object,
        .fields = root_fields,
    };
}

fn addCommonProviderFields(allocator: std.mem.Allocator, fields: *std.StringHashMap(*const Schema)) !void {
    const enabled_schema = try allocator.create(Schema);
    enabled_schema.* = Schema.boolean();
    try fields.put("enabled", enabled_schema);

    const vault_path_schema = try allocator.create(Schema);
    vault_path_schema.* = Schema.string(.{ .min_length = 1 });
    try fields.put("vault_path", vault_path_schema);

    const default_model_schema = try allocator.create(Schema);
    default_model_schema.* = Schema.string(.{ .min_length = 1 });
    try fields.put("default_model", default_model_schema);

    const model_item_schema = try allocator.create(Schema);
    model_item_schema.* = Schema.string(.{ .min_length = 1 });

    const model_list_schema = try allocator.create(Schema);
    model_list_schema.* = Schema.array(.{ .min_items = 0, .item_schema = model_item_schema });
    try fields.put("model_allowlist", model_list_schema);

    const capability_item_schema = try allocator.create(Schema);
    capability_item_schema.* = Schema.string(.{ .min_length = 1 });

    const capabilities_schema = try allocator.create(Schema);
    capabilities_schema.* = Schema.array(.{ .min_items = 0, .item_schema = capability_item_schema });
    try fields.put("capabilities", capabilities_schema);
}

fn createApiProviderSchema(allocator: std.mem.Allocator) !*const Schema {
    var fields = std.StringHashMap(*const Schema).init(allocator);
    try addCommonProviderFields(allocator, &fields);

    const schema_ptr = try allocator.create(Schema);
    schema_ptr.* = Schema{
        .schema_type = .object,
        .fields = fields,
    };
    return schema_ptr;
}

fn createAzureProviderSchema(allocator: std.mem.Allocator) !*const Schema {
    var fields = std.StringHashMap(*const Schema).init(allocator);
    try addCommonProviderFields(allocator, &fields);

    const resource_schema = try allocator.create(Schema);
    resource_schema.* = Schema.string(.{ .min_length = 1 });
    try fields.put("resource", resource_schema);

    const deployment_schema = try allocator.create(Schema);
    deployment_schema.* = Schema.string(.{ .min_length = 1 });
    try fields.put("deployment", deployment_schema);

    const api_version_schema = try allocator.create(Schema);
    api_version_schema.* = Schema.string(.{ .min_length = 1 });
    try fields.put("api_version", api_version_schema);

    const schema_ptr = try allocator.create(Schema);
    schema_ptr.* = Schema{
        .schema_type = .object,
        .fields = fields,
    };
    return schema_ptr;
}

fn createCopilotProviderSchema(allocator: std.mem.Allocator) !*const Schema {
    var fields = std.StringHashMap(*const Schema).init(allocator);

    const enabled_schema = try allocator.create(Schema);
    enabled_schema.* = Schema.boolean();
    try fields.put("enabled", enabled_schema);

    const vault_path_schema = try allocator.create(Schema);
    vault_path_schema.* = Schema.string(.{ .min_length = 1 });
    try fields.put("vault_path", vault_path_schema);

    const default_product_schema = try allocator.create(Schema);
    default_product_schema.* = Schema.string(.{ .min_length = 1 });
    try fields.put("default_product", default_product_schema);

    const variant_item_schema = try allocator.create(Schema);
    variant_item_schema.* = Schema.string(.{ .min_length = 1 });

    const variants_schema = try allocator.create(Schema);
    variants_schema.* = Schema.array(.{ .min_items = 0, .item_schema = variant_item_schema });
    try fields.put("allowed_variants", variants_schema);

    const capability_item_schema = try allocator.create(Schema);
    capability_item_schema.* = Schema.string(.{ .min_length = 1 });

    const capabilities_schema = try allocator.create(Schema);
    capabilities_schema.* = Schema.array(.{ .min_items = 0, .item_schema = capability_item_schema });
    try fields.put("capabilities", capabilities_schema);

    const schema_ptr = try allocator.create(Schema);
    schema_ptr.* = Schema{
        .schema_type = .object,
        .fields = fields,
    };
    return schema_ptr;
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

    cfg.daemon.pid_file = raw.getString("daemon.pid_file", cfg.daemon.pid_file) catch cfg.daemon.pid_file;

    cfg.providers.default_strategy = raw.getString("providers.default_strategy", cfg.providers.default_strategy) catch cfg.providers.default_strategy;
    cfg.providers.allowlist = raw.getStringList("providers.allowlist") catch cfg.providers.allowlist;

    cfg.providers.openai = loadApiProviderConfig(raw, "providers.openai", cfg.providers.openai);
    cfg.providers.anthropic = loadApiProviderConfig(raw, "providers.anthropic", cfg.providers.anthropic);
    cfg.providers.xai = loadApiProviderConfig(raw, "providers.xai", cfg.providers.xai);
    cfg.providers.azure_openai = loadAzureOpenAIConfig(raw, "providers.azure_openai", cfg.providers.azure_openai);
    cfg.providers.github_copilot = loadCopilotConfig(raw, "providers.github_copilot", cfg.providers.github_copilot);
}

fn readBool(raw: *flare.Config, prefix: []const u8, field: []const u8, fallback: bool) bool {
    var key_buf: [key_buffer_len]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ prefix, field }) catch return fallback;
    return raw.getBool(key, fallback) catch fallback;
}

fn readOptionalString(raw: *flare.Config, prefix: []const u8, field: []const u8, fallback: ?[]const u8) ?[]const u8 {
    var key_buf: [key_buffer_len]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ prefix, field }) catch return fallback;
    const result = raw.getString(key, null) catch return fallback;
    return result;
}

fn readString(raw: *flare.Config, prefix: []const u8, field: []const u8, fallback: []const u8) []const u8 {
    var key_buf: [key_buffer_len]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ prefix, field }) catch return fallback;
    const result = raw.getString(key, null) catch return fallback;
    return result;
}

fn readStringList(raw: *flare.Config, prefix: []const u8, field: []const u8, fallback: []const []const u8) []const []const u8 {
    var key_buf: [key_buffer_len]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ prefix, field }) catch return fallback;
    return raw.getStringList(key) catch fallback;
}

fn loadApiProviderConfig(raw: *flare.Config, prefix: []const u8, base: ApiProviderConfig) ApiProviderConfig {
    var result = base;
    result.enabled = readBool(raw, prefix, "enabled", result.enabled);
    result.vault_path = readOptionalString(raw, prefix, "vault_path", result.vault_path);
    result.default_model = readOptionalString(raw, prefix, "default_model", result.default_model);
    result.model_allowlist = readStringList(raw, prefix, "model_allowlist", result.model_allowlist);
    result.capabilities = readStringList(raw, prefix, "capabilities", result.capabilities);
    return result;
}

fn loadAzureOpenAIConfig(raw: *flare.Config, prefix: []const u8, base: AzureOpenAIConfig) AzureOpenAIConfig {
    var result = base;
    result.enabled = readBool(raw, prefix, "enabled", result.enabled);
    result.vault_path = readOptionalString(raw, prefix, "vault_path", result.vault_path);
    result.resource = readOptionalString(raw, prefix, "resource", result.resource);
    result.deployment = readOptionalString(raw, prefix, "deployment", result.deployment);
    result.api_version = readString(raw, prefix, "api_version", result.api_version);
    result.default_model = readOptionalString(raw, prefix, "default_model", result.default_model);
    result.model_allowlist = readStringList(raw, prefix, "model_allowlist", result.model_allowlist);
    result.capabilities = readStringList(raw, prefix, "capabilities", result.capabilities);
    return result;
}

fn loadCopilotConfig(raw: *flare.Config, prefix: []const u8, base: CopilotConfig) CopilotConfig {
    var result = base;
    result.enabled = readBool(raw, prefix, "enabled", result.enabled);
    result.vault_path = readOptionalString(raw, prefix, "vault_path", result.vault_path);
    result.default_product = readString(raw, prefix, "default_product", result.default_product);
    result.allowed_variants = readStringList(raw, prefix, "allowed_variants", result.allowed_variants);
    result.capabilities = readStringList(raw, prefix, "capabilities", result.capabilities);
    return result;
}

test "validateRawConfig accepts defaults" {
    const allocator = std.testing.allocator;
    var raw = try flare.Config.init(allocator);
    defer raw.deinit();

    try validateRawConfig(allocator, &raw);
}

test "validateRawConfig rejects out-of-range daemon port" {
    const allocator = std.testing.allocator;
    var raw = try flare.Config.init(allocator);
    defer raw.deinit();

    try raw.setValue("daemon.port", flare.Value{ .int_value = 70000 });

    try std.testing.expectError(error.InvalidConfig, validateRawConfig(allocator, &raw));
}

test "applyRawConfig loads provider overrides" {
    const allocator = std.testing.allocator;
    var raw = try flare.Config.init(allocator);
    defer raw.deinit();

    try raw.setValue("providers.openai.enabled", flare.Value{ .bool_value = true });
    try raw.setValue("providers.openai.default_model", flare.Value{ .string_value = "gpt-4o" });
    try raw.setValue("providers.azure_openai.api_version", flare.Value{ .string_value = "2024-05-01-preview" });
    try raw.setValue("providers.github_copilot.default_product", flare.Value{ .string_value = "copilot[grok]" });

    var cfg = defaults();
    applyRawConfig(&raw, &cfg);

    try std.testing.expect(cfg.providers.openai.enabled);
    try std.testing.expect(cfg.providers.openai.default_model != null);
    try std.testing.expectEqualStrings("gpt-4o", cfg.providers.openai.default_model.?);
    try std.testing.expectEqualStrings("2024-05-01-preview", cfg.providers.azure_openai.api_version);
    try std.testing.expectEqualStrings("copilot[grok]", cfg.providers.github_copilot.default_product);
}

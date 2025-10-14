//! Secure vault abstraction for provider credentials.

const std = @import("std");
const providers = @import("../providers/provider.zig");

pub const Backend = enum { gvault, memory };

pub const Scope = enum { api_key, client_secret, access_token, refresh_token };

pub const SecretRef = struct {
    provider: providers.Kind,
    account: []const u8 = "default",
    scope: Scope = .api_key,
    variant: ?[]const u8 = null,

    pub fn formatKey(self: SecretRef, allocator: std.mem.Allocator, namespace: []const u8) ![]u8 {
        if (self.variant) |variant| {
            return std.fmt.allocPrint(allocator, "{s}/{s}/{s}/{s}/{s}", .{
                namespace,
                providers.slug(self.provider),
                self.account,
                variant,
                @tagName(self.scope),
            });
        }

        return std.fmt.allocPrint(allocator, "{s}/{s}/{s}/{s}", .{
            namespace,
            providers.slug(self.provider),
            self.account,
            @tagName(self.scope),
        });
    }
};

pub const VaultConfig = struct {
    backend: Backend = .gvault,
    namespace: []const u8 = "reaper",
};

pub const VaultError = error{
    UnsupportedBackend,
    SecretNotFound,
    Unimplemented,
};

pub const Vault = struct {
    allocator: std.mem.Allocator,
    config: VaultConfig,
    memory_store: ?std.StringHashMap([]u8) = null,

    pub fn init(allocator: std.mem.Allocator, config: VaultConfig) !Vault {
        var memory_store: ?std.StringHashMap([]u8) = null;
        if (config.backend == .memory) {
            memory_store = std.StringHashMap([]u8).init(allocator);
        }

        return Vault{
            .allocator = allocator,
            .config = config,
            .memory_store = memory_store,
        };
    }

    pub fn deinit(self: *Vault) void {
        if (self.memory_store) |*map| {
            var it = map.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            map.deinit();
            self.memory_store = null;
        }
    }

    pub fn store(self: *Vault, ref: SecretRef, value: []const u8) VaultError!void {
        const key = try ref.formatKey(self.allocator, self.config.namespace);
        defer self.allocator.free(key);

        switch (self.config.backend) {
            .memory => {
                if (self.memory_store) |*map| {
                    if (map.fetchRemove(key)) |existing| {
                        self.allocator.free(existing.key);
                        self.allocator.free(existing.value);
                    }

                    const key_copy = try self.allocator.dupe(u8, key);
                    const copy = try self.allocator.dupe(u8, value);
                    try map.put(key_copy, copy);
                } else {
                    unreachable; // memory backend requires initialization
                }
            },
            .gvault => return VaultError.Unimplemented,
        }
    }

    pub fn fetch(self: *Vault, ref: SecretRef) VaultError![]u8 {
        const key = try ref.formatKey(self.allocator, self.config.namespace);
        defer self.allocator.free(key);

        switch (self.config.backend) {
            .memory => {
                if (self.memory_store) |map| {
                    if (map.get(key)) |value| {
                        return self.allocator.dupe(u8, value);
                    }
                    return VaultError.SecretNotFound;
                }
                unreachable;
            },
            .gvault => return VaultError.Unimplemented,
        }
    }

    pub fn delete(self: *Vault, ref: SecretRef) VaultError!void {
        const key = try ref.formatKey(self.allocator, self.config.namespace);
        defer self.allocator.free(key);

        switch (self.config.backend) {
            .memory => {
                if (self.memory_store) |*map| {
                    if (map.fetchRemove(key)) |existing| {
                        self.allocator.free(existing.key);
                        self.allocator.free(existing.value);
                    }
                } else {
                    unreachable;
                }
            },
            .gvault => return VaultError.Unimplemented,
        }
    }

    pub fn exists(self: *Vault, ref: SecretRef) VaultError!bool {
        const key = try ref.formatKey(self.allocator, self.config.namespace);
        defer self.allocator.free(key);

        return switch (self.config.backend) {
            .memory => blk: {
                if (self.memory_store) |map| {
                    break :blk map.contains(key);
                }
                unreachable;
            },
            .gvault => VaultError.Unimplemented,
        };
    }
};

pub fn providerSecretRef(kind: providers.Kind, account: []const u8, scope: Scope, variant: ?[]const u8) SecretRef {
    return SecretRef{
        .provider = kind,
        .account = account,
        .scope = scope,
        .variant = variant,
    };
}

test "memory vault stores and retrieves secrets" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vault = try Vault.init(allocator, .{ .backend = .memory, .namespace = "test" });
    defer vault.deinit();

    const ref = providerSecretRef(.openai, "primary", .api_key, null);

    try vault.store(ref, "sk-test");
    try std.testing.expect(try vault.exists(ref));

    const fetched = try vault.fetch(ref);
    defer allocator.free(fetched);
    try std.testing.expect(std.mem.eql(u8, fetched, "sk-test"));

    try vault.delete(ref);
    try std.testing.expect(!(try vault.exists(ref)));
}

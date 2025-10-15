//! Secure vault abstraction for provider credentials.

const std = @import("std");
const providers = @import("../providers/provider.zig");
const gvault = @import("gvault");

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
    vault_path: []const u8 = "~/.config/reaper/vault",
};

pub const VaultError = error{
    UnsupportedBackend,
    SecretNotFound,
    Unimplemented,
    OutOfMemory,
};

pub const Vault = struct {
    allocator: std.mem.Allocator,
    config: VaultConfig,
    memory_store: ?std.StringHashMap([]u8) = null,
    gvault_instance: ?*gvault.Vault = null,

    pub fn init(allocator: std.mem.Allocator, config: VaultConfig) !Vault {
        var memory_store: ?std.StringHashMap([]u8) = null;
        var gvault_instance: ?*gvault.Vault = null;

        switch (config.backend) {
            .memory => {
                memory_store = std.StringHashMap([]u8).init(allocator);
            },
            .gvault => {
                const vault_ptr = try allocator.create(gvault.Vault);
                vault_ptr.* = try gvault.Vault.init(allocator, config.vault_path);
                gvault_instance = vault_ptr;
            },
        }

        return Vault{
            .allocator = allocator,
            .config = config,
            .memory_store = memory_store,
            .gvault_instance = gvault_instance,
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
        if (self.gvault_instance) |vault_ptr| {
            vault_ptr.deinit();
            self.allocator.destroy(vault_ptr);
        }
    }

    pub fn unlock(self: *Vault, passphrase: []const u8) VaultError!void {
        if (self.config.backend != .gvault) return;
        const vault_ptr = self.gvault_instance orelse return VaultError.Unimplemented;
        vault_ptr.unlock(passphrase) catch return VaultError.Unimplemented;
    }

    pub fn lock(self: *Vault) void {
        if (self.gvault_instance) |vault_ptr| {
            vault_ptr.lock();
        }
    }

    pub fn isUnlocked(self: *Vault) bool {
        if (self.gvault_instance) |vault_ptr| {
            return vault_ptr.isUnlocked();
        }
        return true; // memory backend is always "unlocked"
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
            .gvault => {
                const vault_ptr = self.gvault_instance orelse return VaultError.Unimplemented;
                const cred_type = scopeToCredentialType(ref.scope);
                _ = vault_ptr.addCredential(key, cred_type, value) catch return VaultError.Unimplemented;
            },
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
            .gvault => {
                const vault_ptr = self.gvault_instance orelse return VaultError.Unimplemented;
                const creds = vault_ptr.searchCredentials(key) catch return VaultError.SecretNotFound;
                defer vault_ptr.freeCredentialSlice(creds);

                if (creds.len == 0) return VaultError.SecretNotFound;
                const cred_id = creds[0].id;
                return vault_ptr.getCredentialData(cred_id) catch VaultError.SecretNotFound;
            },
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
            .gvault => {
                const vault_ptr = self.gvault_instance orelse return VaultError.Unimplemented;
                const creds = vault_ptr.searchCredentials(key) catch return;
                defer vault_ptr.freeCredentialSlice(creds);

                if (creds.len > 0) {
                    const cred_id = creds[0].id;
                    vault_ptr.deleteCredential(cred_id) catch {};
                }
            },
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
            .gvault => blk: {
                const vault_ptr = self.gvault_instance orelse break :blk false;
                const creds = vault_ptr.searchCredentials(key) catch break :blk false;
                defer vault_ptr.freeCredentialSlice(creds);
                break :blk creds.len > 0;
            },
        };
    }
};

fn scopeToCredentialType(scope: Scope) gvault.CredentialType {
    return switch (scope) {
        .api_key => .api_token,
        .access_token => .api_token,
        .refresh_token => .api_token,
        .client_secret => .password,
    };
}

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

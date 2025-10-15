//! Command-line interface built with flash.

const std = @import("std");
const flash = @import("flash");
const zsync = @import("zsync");

const logging = @import("../logging.zig");
const server = @import("../server.zig");
const config_mod = @import("../config/config.zig");
const version = @import("../version.zig");
const vault = @import("../auth/vault.zig");
const provider = @import("../providers/provider.zig");
const github_copilot = @import("../providers/github_copilot.zig");

const Command = flash.Command;
const CommandConfig = flash.CommandConfig;
const Context = flash.Context;
const Flag = flash.Flag;
const FlagConfig = flash.FlagConfig;
const FlashError = flash.Error;

const ReaperCLI = flash.CLI(.{
    .name = "reaper",
    .version = version.VERSION,
    .about = "Reaper.grim daemon controller",
});

const start_flags = [_]Flag{
    Flag.init("foreground", (FlagConfig{}).withHelp("Run in foreground without daemonizing").withShort('f').withLong("foreground")),
};

const stop_flags = [_]Flag{
    Flag.init("force", (FlagConfig{}).withHelp("Force shutdown if graceful stop fails").withShort('f').withLong("force")),
};

const start_command = Command.init(
    "start",
    (CommandConfig{})
        .withAbout("Start the Reaper daemon service")
        .withFlags(&start_flags)
        .withHandler(startHandler),
);

const stop_command = Command.init(
    "stop",
    (CommandConfig{})
        .withAbout("Stop the Reaper daemon service")
        .withFlags(&stop_flags)
        .withHandler(stopHandler),
);

const version_command = Command.init(
    "version",
    (CommandConfig{})
        .withAbout("Print version information")
        .withHandler(versionHandler),
);

// Auth subcommands
const auth_status_command = Command.init(
    "status",
    (CommandConfig{})
        .withAbout("Show authentication and vault status")
        .withHandler(authStatusHandler),
);

const auth_list_command = Command.init(
    "list",
    (CommandConfig{})
        .withAbout("List all available providers")
        .withHandler(authListHandler),
);

const auth_login_flags = [_]Flag{
    Flag.init("account", (FlagConfig{}).withHelp("Account identifier (defaults to 'default')").withShort('a').withLong("account")),
    Flag.init("endpoint", (FlagConfig{}).withHelp("Azure OpenAI endpoint (for azure-openai only)").withLong("endpoint")),
    Flag.init("deployment", (FlagConfig{}).withHelp("Azure OpenAI deployment name (for azure-openai only)").withLong("deployment")),
};

const auth_login_command = Command.init(
    "login",
    (CommandConfig{})
        .withAbout("Authenticate with a provider (store API key in vault)")
        .withUsage("reaper auth login <provider>")
        .withFlags(&auth_login_flags)
        .withHandler(authLoginHandler),
);

const auth_logout_command = Command.init(
    "logout",
    (CommandConfig{})
        .withAbout("Remove stored credentials for a provider")
        .withUsage("reaper auth logout <provider>")
        .withHandler(authLogoutHandler),
);

const auth_subcommands = [_]Command{
    auth_status_command,
    auth_list_command,
    auth_login_command,
    auth_logout_command,
};

const auth_command = Command.init(
    "auth",
    (CommandConfig{})
        .withAbout("Manage provider authentication and vault")
        .withSubcommands(&auth_subcommands)
        .withHandler(authRootHandler),
);

const root_subcommands = [_]Command{
    start_command,
    stop_command,
    version_command,
    auth_command,
};

const root_config = (CommandConfig{})
    .withAbout("Control the Reaper daemon")
    .withVersion(version.VERSION)
    .withSubcommands(&root_subcommands)
    .withHandler(rootHandler);

const ContextState = struct {
    runtime: *zsync.Runtime,
    config: *const config_mod.Config,
};

var context_state: ?ContextState = null;

pub fn run(allocator: std.mem.Allocator, runtime: *zsync.Runtime, config: *const config_mod.Config) !void {
    context_state = .{ .runtime = runtime, .config = config };
    defer context_state = null;

    var cli = ReaperCLI.init(allocator, root_config);
    try cli.run();
}

pub fn runWithArgs(allocator: std.mem.Allocator, runtime: *zsync.Runtime, config: *const config_mod.Config, args: []const []const u8) !void {
    context_state = .{ .runtime = runtime, .config = config };
    defer context_state = null;

    var cli = ReaperCLI.init(allocator, root_config);
    try cli.runWithArgs(args);
}

fn guardState() FlashError!ContextState {
    if (context_state) |state| {
        return state;
    }
    return FlashError.ConfigError;
}

fn rootHandler(ctx: Context) FlashError!void {
    _ = ctx;
    logging.logger().info("Reaper.grim CLI ready", .{});
}

fn startHandler(ctx: Context) FlashError!void {
    const state = try guardState();
    const foreground = ctx.getFlag("foreground");

    logging.logger().info(
        "Starting Reaper daemon (foreground={}) at {s}:{d}",
        .{ foreground, state.config.daemon.host, state.config.daemon.port },
    );

    server.launch(.{
        .runtime = state.runtime,
        .config = state.config,
        .foreground = foreground,
    }) catch |err| switch (err) {
        error.AlreadyRunning => {
            logging.logger().warn("Reaper daemon already running; skipping start", .{});
            return;
        },
        else => {
            logging.logger().err("Failed to launch daemon: {s}", .{@errorName(err)});
            return FlashError.IOError;
        },
    };
}

fn stopHandler(ctx: Context) FlashError!void {
    const state = try guardState();
    const force = ctx.getFlag("force");

    logging.logger().info("Stopping Reaper daemon (force={})", .{force});
    server.shutdown(.{ .config = state.config, .force = force }) catch |err| switch (err) {
        error.Timeout => {
            logging.logger().err("Timed out waiting for daemon to stop", .{});
            return FlashError.IOError;
        },
        else => {
            logging.logger().err("Failed to stop daemon: {s}", .{@errorName(err)});
            return FlashError.IOError;
        },
    };
}

fn versionHandler(ctx: Context) FlashError!void {
    _ = ctx;
    var stdout = std.fs.File.stdout();
    stdout.writeAll("Reaper.grim ") catch |err| {
        logging.logger().err("Failed to write version prefix: {s}", .{@errorName(err)});
        return FlashError.IOError;
    };
    stdout.writeAll(version.VERSION) catch |err| {
        logging.logger().err("Failed to write version value: {s}", .{@errorName(err)});
        return FlashError.IOError;
    };
    stdout.writeAll("\n") catch |err| {
        logging.logger().err("Failed to write newline: {s}", .{@errorName(err)});
        return FlashError.IOError;
    };
}

fn authRootHandler(ctx: Context) FlashError!void {
    _ = ctx;
    logging.logger().info("Use 'reaper auth <command>' - see 'reaper auth --help' for available commands", .{});
}

fn authStatusHandler(ctx: Context) FlashError!void {
    _ = try guardState();
    const allocator = ctx.allocator;

    var stdout = std.fs.File.stdout();

    // Initialize vault
    var vault_instance = vault.Vault.init(allocator, .{ .backend = .gvault }) catch |err| {
        logging.logger().err("Failed to initialize vault: {s}", .{@errorName(err)});
        stdout.writeAll("Error: Failed to initialize vault\n") catch {};
        return FlashError.ConfigError;
    };
    defer vault_instance.deinit();

    vault_instance.unlock("default-password") catch |err| {
        logging.logger().err("Failed to unlock vault: {s}", .{@errorName(err)});
        stdout.writeAll("Vault Status: LOCKED\n") catch return FlashError.IOError;
        return FlashError.ConfigError;
    };

    stdout.writeAll("Vault Status: UNLOCKED\n") catch return FlashError.IOError;
    stdout.writeAll("Backend: gvault (post-quantum encrypted)\n\n") catch return FlashError.IOError;

    stdout.writeAll("Provider Authentication Status:\n") catch return FlashError.IOError;

    // Check each provider
    const descriptors = provider.descriptors();
    for (descriptors) |desc| {
        const secret_ref = vault.providerSecretRef(desc.kind, "default", .api_key, null);
        const has_secret = vault_instance.exists(secret_ref) catch false;

        const status = if (has_secret) "✓ AUTHENTICATED" else "✗ Not configured";
        const line = std.fmt.allocPrint(allocator, "  {s:<20} {s}\n", .{ desc.display_name, status }) catch {
            return FlashError.IOError;
        };
        defer allocator.free(line);

        stdout.writeAll(line) catch return FlashError.IOError;
    }
}

fn authListHandler(ctx: Context) FlashError!void {
    _ = try guardState();
    const allocator = ctx.allocator;

    var stdout = std.fs.File.stdout();
    stdout.writeAll("Available Providers:\n\n") catch return FlashError.IOError;

    const descriptors = provider.descriptors();
    for (descriptors) |desc| {
        const header = std.fmt.allocPrint(allocator, "{s} ({s})\n", .{ desc.display_name, desc.slug }) catch {
            return FlashError.IOError;
        };
        defer allocator.free(header);

        stdout.writeAll(header) catch return FlashError.IOError;

        // List capabilities
        stdout.writeAll("  Capabilities: ") catch return FlashError.IOError;
        for (desc.default_capabilities, 0..) |cap, i| {
            if (i > 0) stdout.writeAll(", ") catch return FlashError.IOError;
            const cap_name = switch (cap) {
                .completion => "completion",
                .chat => "chat",
                .agent => "agent",
            };
            stdout.writeAll(cap_name) catch return FlashError.IOError;
        }
        stdout.writeAll("\n") catch return FlashError.IOError;

        // List default models
        if (desc.default_models.len > 0) {
            stdout.writeAll("  Models: ") catch return FlashError.IOError;
            for (desc.default_models, 0..) |model, i| {
                if (i > 0) stdout.writeAll(", ") catch return FlashError.IOError;
                stdout.writeAll(model) catch return FlashError.IOError;
            }
            stdout.writeAll("\n") catch return FlashError.IOError;
        }

        stdout.writeAll("\n") catch return FlashError.IOError;
    }
}

fn authLoginHandler(ctx: Context) FlashError!void {
    _ = try guardState();
    const allocator = ctx.allocator;

    // Get provider from positional argument
    const provider_arg = ctx.getPositional(0);
    if (provider_arg == null) {
        logging.logger().err("Missing provider argument", .{});
        var stdout = std.fs.File.stdout();
        stdout.writeAll("Error: Please specify a provider (e.g., 'reaper auth login openai')\n") catch {};
        stdout.writeAll("Available providers: openai, anthropic, xai, azure-openai, github-copilot, ollama\n") catch {};
        return FlashError.InvalidArgument;
    }

    const provider_slug = provider_arg.?.asString();
    const account = ctx.getString("account");
    const account_name = if (account) |acc| acc else "default";

    // Find provider descriptor
    var provider_kind: ?provider.Kind = null;
    const descriptors = provider.descriptors();
    for (descriptors) |desc| {
        if (std.mem.eql(u8, desc.slug, provider_slug)) {
            provider_kind = desc.kind;
            break;
        }
    }

    if (provider_kind == null) {
        logging.logger().err("Unknown provider: {s}", .{provider_slug});
        var stdout = std.fs.File.stdout();
        const msg = std.fmt.allocPrint(allocator, "Error: Unknown provider '{s}'\n", .{provider_slug}) catch {
            return FlashError.IOError;
        };
        defer allocator.free(msg);
        stdout.writeAll(msg) catch {};
        return FlashError.InvalidArgument;
    }

    // Initialize vault
    var vault_instance = vault.Vault.init(allocator, .{ .backend = .gvault }) catch |err| {
        logging.logger().err("Failed to initialize vault: {s}", .{@errorName(err)});
        var stdout = std.fs.File.stdout();
        stdout.writeAll("Error: Failed to initialize vault\n") catch {};
        return FlashError.ConfigError;
    };
    defer vault_instance.deinit();

    vault_instance.unlock("default-password") catch |err| {
        logging.logger().err("Failed to unlock vault: {s}", .{@errorName(err)});
        return FlashError.ConfigError;
    };

    // Special handling for GitHub Copilot OAuth device flow
    if (provider_kind.? == .github_copilot) {
        var gh_provider = github_copilot.GitHubCopilotProvider.init(allocator, account_name);
        defer gh_provider.deinit();

        gh_provider.authenticateWithDeviceFlow(&vault_instance) catch |err| {
            logging.logger().err("Failed to authenticate with GitHub Copilot: {s}", .{@errorName(err)});
            var stdout = std.fs.File.stdout();
            stdout.writeAll("Error: GitHub Copilot authentication failed\n") catch {};
            return FlashError.ConfigError;
        };

        logging.logger().info("Stored credentials for {s}:{s}", .{ provider_slug, account_name });
        return;
    }

    // Prompt for API key
    var stdout = std.fs.File.stdout();
    var stdin = std.fs.File.stdin();

    const prompt_msg = std.fmt.allocPrint(allocator, "Enter API key for {s} (account: {s}): ", .{ provider_slug, account_name }) catch {
        return FlashError.IOError;
    };
    defer allocator.free(prompt_msg);

    stdout.writeAll(prompt_msg) catch return FlashError.IOError;

    // Read API key
    var buf: [1024]u8 = undefined;
    const bytes_read = stdin.read(&buf) catch |err| {
        logging.logger().err("Failed to read API key: {s}", .{@errorName(err)});
        return FlashError.IOError;
    };

    if (bytes_read == 0) {
        stdout.writeAll("Error: No input provided\n") catch {};
        return FlashError.InvalidArgument;
    }

    // Trim newline
    const api_key = std.mem.trimRight(u8, buf[0..bytes_read], "\n\r");

    if (api_key.len == 0) {
        stdout.writeAll("Error: API key cannot be empty\n") catch {};
        return FlashError.InvalidArgument;
    }

    // Store in vault
    const secret_ref = vault.providerSecretRef(provider_kind.?, account_name, .api_key, null);
    vault_instance.store(secret_ref, api_key) catch |err| {
        logging.logger().err("Failed to store API key: {s}", .{@errorName(err)});
        stdout.writeAll("Error: Failed to store credentials in vault\n") catch {};
        return FlashError.ConfigError;
    };

    const success_msg = std.fmt.allocPrint(allocator, "✓ Successfully stored credentials for {s} (account: {s})\n", .{ provider_slug, account_name }) catch {
        return FlashError.IOError;
    };
    defer allocator.free(success_msg);

    stdout.writeAll(success_msg) catch return FlashError.IOError;
    logging.logger().info("Stored credentials for {s}:{s}", .{ provider_slug, account_name });
}

fn authLogoutHandler(ctx: Context) FlashError!void {
    _ = try guardState();
    const allocator = ctx.allocator;

    // Get provider from positional argument
    const provider_arg = ctx.getPositional(0);
    if (provider_arg == null) {
        logging.logger().err("Missing provider argument", .{});
        var stdout = std.fs.File.stdout();
        stdout.writeAll("Error: Please specify a provider (e.g., 'reaper auth logout openai')\n") catch {};
        return FlashError.InvalidArgument;
    }

    const provider_slug = provider_arg.?.asString();
    const account_name = "default"; // TODO: Add --account flag support

    // Find provider descriptor
    var provider_kind: ?provider.Kind = null;
    const descriptors = provider.descriptors();
    for (descriptors) |desc| {
        if (std.mem.eql(u8, desc.slug, provider_slug)) {
            provider_kind = desc.kind;
            break;
        }
    }

    if (provider_kind == null) {
        logging.logger().err("Unknown provider: {s}", .{provider_slug});
        var stdout = std.fs.File.stdout();
        const msg = std.fmt.allocPrint(allocator, "Error: Unknown provider '{s}'\n", .{provider_slug}) catch {
            return FlashError.IOError;
        };
        defer allocator.free(msg);
        stdout.writeAll(msg) catch {};
        return FlashError.InvalidArgument;
    }

    // Initialize vault
    var vault_instance = vault.Vault.init(allocator, .{ .backend = .gvault }) catch |err| {
        logging.logger().err("Failed to initialize vault: {s}", .{@errorName(err)});
        var stdout = std.fs.File.stdout();
        stdout.writeAll("Error: Failed to initialize vault\n") catch {};
        return FlashError.ConfigError;
    };
    defer vault_instance.deinit();

    vault_instance.unlock("default-password") catch |err| {
        logging.logger().err("Failed to unlock vault: {s}", .{@errorName(err)});
        return FlashError.ConfigError;
    };

    // Delete from vault
    const secret_ref = vault.providerSecretRef(provider_kind.?, account_name, .api_key, null);
    vault_instance.delete(secret_ref) catch |err| {
        logging.logger().err("Failed to delete credentials: {s}", .{@errorName(err)});
        var stdout = std.fs.File.stdout();
        stdout.writeAll("Error: Failed to remove credentials from vault\n") catch {};
        return FlashError.ConfigError;
    };

    var stdout = std.fs.File.stdout();
    const success_msg = std.fmt.allocPrint(allocator, "✓ Successfully removed credentials for {s} (account: {s})\n", .{ provider_slug, account_name }) catch {
        return FlashError.IOError;
    };
    defer allocator.free(success_msg);

    stdout.writeAll(success_msg) catch return FlashError.IOError;
    logging.logger().info("Removed credentials for {s}:{s}", .{ provider_slug, account_name });
}

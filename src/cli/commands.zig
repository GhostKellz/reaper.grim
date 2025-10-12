//! Command-line interface built with flash.

const std = @import("std");
const flash = @import("flash");
const zsync = @import("zsync");

const logging = @import("../logging.zig");
const server = @import("../server.zig");
const config_mod = @import("../config/config.zig");
const version = @import("../version.zig");

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

const root_subcommands = [_]Command{
    start_command,
    stop_command,
    version_command,
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
    }) catch |err| {
        logging.logger().err("Failed to launch daemon: {s}", .{@errorName(err)});
        return FlashError.IOError;
    };
}

fn stopHandler(ctx: Context) FlashError!void {
    const state = try guardState();
    const force = ctx.getFlag("force");

    logging.logger().info("Stopping Reaper daemon (force={})", .{force});
    server.shutdown(.{ .config = state.config, .force = force }) catch |err| {
        logging.logger().err("Failed to stop daemon: {s}", .{@errorName(err)});
        return FlashError.IOError;
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

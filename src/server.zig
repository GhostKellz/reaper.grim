//! Reaper daemon server bootstrap.

const std = @import("std");
const zrpc = @import("zrpc");
const zsync = @import("zsync");

const atomic = std.atomic;
const posix = std.posix;
const fs = std.fs;
const fmt = std.fmt;
const mem = std.mem;
const net = std.net;
const time = std.time;
const os = std.os;
const Thread = std.Thread;

const logging = @import("logging.zig");
const config_mod = @import("config/config.zig");
const services = @import("rpc/service.zig");
const handlers = @import("rpc/handlers.zig");

pub const LaunchOptions = struct {
    runtime: *zsync.Runtime,
    config: *const config_mod.Config,
    foreground: bool = false,
};

pub const ShutdownOptions = struct {
    config: *const config_mod.Config,
    force: bool = false,
};

const State = struct {
    allocator: std.mem.Allocator,
    server: *zrpc.Server,
    start_time_ms: i64,
    pid_file: []const u8,
    is_background: bool,
    shutdown_thread: ?std.Thread = null,
    health_thread: ?std.Thread = null,
    health_stop: atomic.Value(bool) = atomic.Value(bool).init(true),
    health_host: []const u8 = "",
    health_port: ?u16 = null,
};

var state: ?State = null;
var shutdown_requested = atomic.Value(bool).init(false);
var signal_shutdown = atomic.Value(bool).init(false);

pub fn launch(options: LaunchOptions) !void {
    if (state) |_| {
        logging.logger().warn("server already running", .{});
        return;
    }

    if (!options.foreground) {
        try daemonize(options);
        return;
    }

    try launchInProcess(options, false);
}

pub fn shutdown(options: ShutdownOptions) !void {
    if (state) |s| {
        logging.logger().info("Reaper daemon stopping (force={})", .{options.force});
        shutdown_requested.store(true, .seq_cst);
        signal_shutdown.store(false, .seq_cst);
        s.server.stop();
        return;
    }

    const pid_file = options.config.daemon.pid_file;
    const maybe_pid = readPidFile(pid_file) catch |err| switch (err) {
        error.FileNotFound => {
            logging.logger().warn("reaper daemon was not running", .{});
            return;
        },
        else => return err,
    };

    const pid = maybe_pid orelse {
        logging.logger().warn("reaper daemon was not running", .{});
        _ = removePidFile(pid_file) catch {};
        return;
    };

    if (!isProcessAlive(pid)) {
        logging.logger().warn("stale pid file detected at {s}; cleaning up", .{pid_file});
        _ = removePidFile(pid_file) catch {};
        return;
    }

    var sig: u8 = @as(u8, @intCast(posix.SIG.TERM));
    if (options.force) {
        sig = @as(u8, @intCast(posix.SIG.KILL));
    }

    posix.kill(pid, sig) catch |err| {
        logging.logger().err("failed to signal daemon (pid={}): {s}", .{ pid, @errorName(err) });
        return err;
    };

    waitForExit(pid, if (options.force) 50 else 100) catch |err| {
        if (err == error.Timeout) {
            logging.logger().err("Timed out waiting for daemon pid {} to exit", .{pid});
            if (!options.force) {
                logging.logger().err("Retry with --force to terminate the process", .{});
            }
        }
        return err;
    };

    _ = removePidFile(pid_file) catch {};
    logging.logger().info("Reaper daemon stopped (force={})", .{options.force});
}

fn launchInProcess(options: LaunchOptions, is_background: bool) !void {
    const server_ptr = try initServerState(options, is_background);

    defer {
        shutdown_requested.store(true, .seq_cst);
        stopShutdownWatcher();
        stopHealthEndpoint();
        cleanupState();
    }

    if (is_background) {
        writePidFile(options.config.daemon.pid_file, os.linux.getpid()) catch |err| {
            logging.logger().err("failed to update pid file {s}: {s}", .{ options.config.daemon.pid_file, @errorName(err) });
        };
    }

    try installSignalHandlers();
    shutdown_requested.store(false, .seq_cst);
    signal_shutdown.store(false, .seq_cst);

    try startHealthEndpoint(options.config);
    try startShutdownWatcher(server_ptr);

    logging.logger().info(
        "Reaper daemon listening on {s}:{d} (foreground={})",
        .{ options.config.daemon.host, options.config.daemon.port, !is_background },
    );

    runForeground(server_ptr, options.config) catch |err| {
        logging.logger().err("Server exited with error: {s}", .{@errorName(err)});
        return err;
    };
}

fn initServerState(options: LaunchOptions, is_background: bool) !*zrpc.Server {
    const allocator = options.runtime.allocator;

    const server_ptr = try allocator.create(zrpc.Server);
    errdefer allocator.destroy(server_ptr);

    server_ptr.* = zrpc.Server.init(allocator);
    errdefer server_ptr.deinit();

    try services.registerAll(server_ptr);

    const start_time = time.milliTimestamp();
    handlers.setContext(.{ .start_time_ms = start_time });
    try handlers.registerAll(server_ptr);

    state = .{
        .allocator = allocator,
        .server = server_ptr,
        .start_time_ms = start_time,
        .pid_file = options.config.daemon.pid_file,
        .is_background = is_background,
    };

    return server_ptr;
}

fn cleanupState() void {
    if (state) |s| {
        s.server.deinit();
        s.allocator.destroy(s.server);

        if (s.is_background) {
            _ = removePidFile(s.pid_file) catch {};
        }

        state = null;
    }
}

fn daemonize(options: LaunchOptions) !void {
    const pid_file = options.config.daemon.pid_file;

    const maybe_pid = readPidFile(pid_file) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };

    if (maybe_pid) |pid| {
        if (isProcessAlive(pid)) {
            logging.logger().warn("reaper daemon already running (pid={})", .{pid});
            return error.AlreadyRunning;
        }

        logging.logger().warn("Removing stale pid file for pid {}", .{pid});
        _ = removePidFile(pid_file) catch {};
    }

    const child_pid = try posix.fork();
    if (child_pid == 0) {
        _ = posix.chdir("/") catch {};
        redirectStandardStreams();

        launchInProcess(options, true) catch |err| {
            logging.logger().err("Failed to launch daemon in background: {s}", .{@errorName(err)});
            posix.exit(1);
        };

        posix.exit(0);
    }

    writePidFile(pid_file, child_pid) catch |err| {
        logging.logger().err("Failed to write pid file {s}: {s}", .{ pid_file, @errorName(err) });
        posix.kill(child_pid, @as(u8, @intCast(posix.SIG.TERM))) catch {};
        return err;
    };

    logging.logger().info("Reaper daemon started in background (pid={})", .{child_pid});
}

fn runForeground(server_ptr: *zrpc.Server, config: *const config_mod.Config) !void {
    const endpoint = try config.daemon.endpoint(std.heap.page_allocator);
    defer std.heap.page_allocator.free(endpoint);

    logging.logger().info("Starting service loop on {s}", .{endpoint});
    try server_ptr.serve(endpoint);
}

fn installSignalHandlers() !void {
    var action = posix.Sigaction{
        .handler = .{ .handler = signalHandler },
        .mask = mem.zeroes(posix.sigset_t),
        .flags = 0,
    };

    posix.sigaction(@as(u8, @intCast(posix.SIG.TERM)), &action, null);
    posix.sigaction(@as(u8, @intCast(posix.SIG.INT)), &action, null);
}

fn signalHandler(_: c_int) callconv(.c) void {
    shutdown_requested.store(true, .seq_cst);
    signal_shutdown.store(true, .seq_cst);
}

fn startShutdownWatcher(server_ptr: *zrpc.Server) !void {
    if (state) |*s| {
        s.shutdown_thread = try std.Thread.spawn(.{}, shutdownWatcherLoop, .{server_ptr});
    }
}

fn stopShutdownWatcher() void {
    if (state) |*s| {
        if (s.shutdown_thread) |thread| {
            thread.join();
            s.shutdown_thread = null;
        }
    }
}

fn shutdownWatcherLoop(server_ptr: *zrpc.Server) void {
    while (!shutdown_requested.load(.seq_cst)) {
        Thread.sleep(50 * time.ns_per_ms);
    }

    if (signal_shutdown.load(.seq_cst)) {
        logging.logger().info("Shutdown signal received; stopping server", .{});
        server_ptr.stop();
    }
}

fn startHealthEndpoint(config: *const config_mod.Config) !void {
    if (state) |*s| {
        if (config.daemon.health_port) |port| {
            if (s.health_thread != null) {
                s.health_stop.store(true, .seq_cst);
                if (s.health_thread) |thread| thread.join();
                s.health_thread = null;
            }
            s.health_host = config.daemon.host;
            s.health_port = port;
            s.health_stop.store(false, .seq_cst);
            s.health_thread = try std.Thread.spawn(.{}, healthServerLoop, .{ s.health_host, port, &s.health_stop, s.start_time_ms });
        }
    }
}

fn stopHealthEndpoint() void {
    if (state) |*s| {
        if (s.health_thread) |thread| {
            s.health_stop.store(true, .seq_cst);
            thread.join();
            s.health_thread = null;
        }
    }
}

fn healthServerLoop(host: []const u8, port: u16, stop_flag: *atomic.Value(bool), start_time_ms: i64) void {
    const address = net.Address.parseIp(host, port) catch |err| {
        logging.logger().err("Health server failed to parse {s}:{d}: {s}", .{ host, port, @errorName(err) });
        return;
    };

    var server = net.Address.listen(address, .{ .reuse_address = true, .force_nonblocking = true }) catch |err| {
        logging.logger().err("Health server failed to listen on {s}:{d}: {s}", .{ host, port, @errorName(err) });
        return;
    };
    defer server.deinit();

    logging.logger().info("Health endpoint listening on {s}:{d}", .{ host, port });

    while (!stop_flag.load(.seq_cst)) {
        const conn = server.accept() catch |err| {
            if (err == error.WouldBlock) {
                Thread.sleep(50 * time.ns_per_ms);
                continue;
            }
            if (stop_flag.load(.seq_cst)) break;
            logging.logger().warn("Health accept error: {s}", .{@errorName(err)});
            continue;
        };
        handleHealthConnection(conn, start_time_ms);
    }
}

fn handleHealthConnection(connection: net.Server.Connection, start_time_ms: i64) void {
    defer connection.stream.close();

    var buffer: [512]u8 = undefined;
    _ = connection.stream.read(&buffer) catch {};

    const now_ms = time.milliTimestamp();
    const uptime = if (now_ms > start_time_ms) @as(u64, @intCast(now_ms - start_time_ms)) else 0;

    var body_buf: [128]u8 = undefined;
    const body = fmt.bufPrint(&body_buf, "{{\"status\":\"SERVING\",\"uptime_ms\":{d}}}\n", .{uptime}) catch return;

    var header_buf: [160]u8 = undefined;
    const header = fmt.bufPrint(&header_buf, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{body.len}) catch return;

    connection.stream.writeAll(header) catch {};
    connection.stream.writeAll(body) catch {};
}

fn writePidFile(path: []const u8, pid: posix.pid_t) !void {
    ensureParentDirectory(path);

    var file = try openFileForWrite(path);
    defer file.close();

    var buf: [64]u8 = undefined;
    const contents = try fmt.bufPrint(&buf, "{d}\n", .{pid});
    try file.writeAll(contents);
}

fn removePidFile(path: []const u8) !void {
    if (fs.path.isAbsolute(path)) {
        try fs.deleteFileAbsolute(path);
    } else {
        try fs.cwd().deleteFile(path);
    }
}

fn readPidFile(path: []const u8) !?posix.pid_t {
    var file = openFileForRead(path) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    var buf: [64]u8 = undefined;
    const len = try file.readAll(&buf);
    if (len == 0) return null;

    const trimmed = mem.trim(u8, buf[0..len], " \n\r\t");
    if (trimmed.len == 0) return null;

    const pid = try fmt.parseInt(posix.pid_t, trimmed, 10);
    return pid;
}

fn isProcessAlive(pid: posix.pid_t) bool {
    posix.kill(pid, 0) catch |err| {
        return switch (err) {
            error.PermissionDenied => true,
            error.ProcessNotFound => false,
            error.Unexpected => false,
        };
    };
    return true;
}

fn waitForExit(pid: posix.pid_t, attempts: usize) !void {
    var remaining = attempts;
    while (remaining > 0) {
        if (!isProcessAlive(pid)) return;
        Thread.sleep(100 * time.ns_per_ms);
        remaining -= 1;
    }

    if (isProcessAlive(pid)) return error.Timeout;
}

fn redirectStandardStreams() void {
    const flags = fs.File.OpenFlags{ .mode = .read_write };
    const null_file = fs.openFileAbsolute("/dev/null", flags) catch return;
    defer null_file.close();

    const fd = null_file.handle;
    _ = posix.dup2(fd, posix.STDIN_FILENO) catch {};
    _ = posix.dup2(fd, posix.STDOUT_FILENO) catch {};
    _ = posix.dup2(fd, posix.STDERR_FILENO) catch {};
}

fn ensureParentDirectory(path: []const u8) void {
    if (fs.path.dirname(path)) |dir| {
        if (fs.path.isAbsolute(path)) {
            fs.makeDirAbsolute(dir) catch {};
        } else {
            fs.cwd().makePath(dir) catch {};
        }
    }
}

fn openFileForWrite(path: []const u8) !fs.File {
    if (fs.path.isAbsolute(path)) {
        return fs.createFileAbsolute(path, .{ .truncate = true, .read = true });
    }
    return fs.cwd().createFile(path, .{ .truncate = true, .read = true });
}

fn openFileForRead(path: []const u8) !fs.File {
    if (fs.path.isAbsolute(path)) {
        return fs.openFileAbsolute(path, .{});
    }
    return fs.cwd().openFile(path, .{});
}

test "pid file helpers roundtrip" {
    var path_buf: [128]u8 = undefined;
    const pid_path = try fmt.bufPrint(&path_buf, "/tmp/reaper-test-{d}.pid", .{time.nanoTimestamp()});
    defer removePidFile(pid_path) catch {};

    const current_pid = posix.getpid();

    try writePidFile(pid_path, current_pid);

    const loaded_pid = try readPidFile(pid_path);
    try std.testing.expect(loaded_pid != null);
    try std.testing.expectEqual(current_pid, loaded_pid.?);

    try std.testing.expect(isProcessAlive(current_pid));

    try removePidFile(pid_path);
    try std.testing.expectEqual(@as(?posix.pid_t, null), try readPidFile(pid_path));
}

test "health endpoint serves readiness response" {
    const allocator = std.testing.allocator;
    try logging.init(allocator, .{});
    defer logging.deinit();

    const port = try findAvailablePort();
    var stop_flag = atomic.Value(bool).init(false);
    const start_time = time.milliTimestamp() - 1500;

    var thread = try std.Thread.spawn(.{}, healthServerLoop, .{ "127.0.0.1", port, &stop_flag, start_time });
    defer {
        stop_flag.store(true, .seq_cst);
        thread.join();
    }

    Thread.sleep(100 * time.ns_per_ms);

    const address = try net.Address.parseIp("127.0.0.1", port);
    var client = try net.tcpConnectToAddress(address);
    defer client.close();

    const request = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    try client.writeAll(request);

    var response = std.ArrayList(u8).init(allocator);
    defer response.deinit();

    var chunk_buf: [512]u8 = undefined;
    while (true) {
        const bytes_read = client.read(&chunk_buf) catch |err| return err;

        if (bytes_read == 0) break;
        try response.appendSlice(chunk_buf[0..bytes_read]);
        if (response.items.len >= 1024) break;
    }

    try std.testing.expect(response.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, response.items, "\"status\":\"SERVING\"") != null);
}

fn findAvailablePort() !u16 {
    var port: u16 = 38000;
    while (port < 39000) : (port += 1) {
        const address = try net.Address.parseIp("127.0.0.1", port);
        var temp_server = net.Address.listen(address, .{ .reuse_address = true, .force_nonblocking = false }) catch |err| {
            if (err == error.AddressInUse) continue;
            return err;
        };
        temp_server.deinit();
        return port;
    }

    return error.AddressInUse;
}

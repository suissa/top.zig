const std = @import("std");
const model = @import("model.zig");

const c = @cImport({
    @cInclude("dirent.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("unistd.h");
    @cInclude("sys/statvfs.h");
});

const TickSample = struct {
    pid: u32,
    ticks: u64,
};

const CpuCounters = struct {
    total: u64 = 0,
    idle: u64 = 0,
    cpu_count: u16 = 1,
};

const NetworkCounters = struct {
    rx_bytes: u64 = 0,
    tx_bytes: u64 = 0,
};

pub fn collect(snapshot: *model.Snapshot, sort_mode: model.SortMode) void {
    const first_cpu = readCpuCounters();
    const first_network = readNetworkCounters();
    var first: [model.MaxProcesses]TickSample = undefined;
    const first_len = readProcessTicks(&first);

    _ = c.usleep(120_000);

    const second_cpu = readCpuCounters();
    const second_network = readNetworkCounters();
    readMemory(snapshot);
    readRootDisk(snapshot);
    readLoad(snapshot);
    readUptime(snapshot);

    snapshot.cpu_count = second_cpu.cpu_count;
    snapshot.network_rx_bps = @as(f64, @floatFromInt(second_network.rx_bytes -| first_network.rx_bytes)) / 0.120;
    snapshot.network_tx_bps = @as(f64, @floatFromInt(second_network.tx_bytes -| first_network.tx_bytes)) / 0.120;
    const total_delta = second_cpu.total -| first_cpu.total;
    const idle_delta = second_cpu.idle -| first_cpu.idle;
    snapshot.cpu_percent = if (total_delta == 0)
        0
    else
        100.0 * @as(f32, @floatFromInt(total_delta -| idle_delta)) / @as(f32, @floatFromInt(total_delta));

    snapshot.process_count = readProcesses(snapshot.processes[0..], first[0..first_len], total_delta, second_cpu.cpu_count);
    sortProcesses(snapshot.processes[0..snapshot.process_count], sort_mode);
}

fn readText(path: [*:0]const u8, buffer: []u8) []const u8 {
    const file = c.fopen(path, "rb") orelse return "";
    defer _ = c.fclose(file);
    if (buffer.len == 0) return "";
    const n = c.fread(buffer.ptr, 1, buffer.len - 1, file);
    buffer[n] = 0;
    return buffer[0..n];
}

fn readCpuCounters() CpuCounters {
    var buf: [4096]u8 = undefined;
    const text = readText("/proc/stat", &buf);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const first = lines.next() orelse return .{};

    var tok = std.mem.tokenizeScalar(u8, first, ' ');
    _ = tok.next();
    var vals: [10]u64 = [_]u64{0} ** 10;
    var i: usize = 0;
    while (tok.next()) |part| : (i += 1) {
        if (i >= vals.len) break;
        vals[i] = std.fmt.parseInt(u64, part, 10) catch 0;
    }

    var total: u64 = 0;
    for (vals) |v| total += v;
    const idle = vals[3] + vals[4];

    var cpu_count: u16 = 0;
    while (lines.next()) |line| {
        if (line.len < 4 or !std.mem.startsWith(u8, line, "cpu")) continue;
        if (line[3] >= '0' and line[3] <= '9') cpu_count += 1;
    }
    if (cpu_count == 0) cpu_count = 1;
    return .{ .total = total, .idle = idle, .cpu_count = cpu_count };
}


fn readRootDisk(snapshot: *model.Snapshot) void {
    var info: c.struct_statvfs = undefined;
    if (c.statvfs("/", &info) != 0) return;

    const block_size: u64 = @intCast(if (info.f_frsize > 0) info.f_frsize else info.f_bsize);
    const total_blocks: u64 = @intCast(info.f_blocks);
    const available_blocks: u64 = @intCast(info.f_bavail);
    snapshot.root_disk_total_bytes = total_blocks * block_size;
    const available_bytes = available_blocks * block_size;
    snapshot.root_disk_used_bytes = snapshot.root_disk_total_bytes -| available_bytes;
    snapshot.root_disk_percent = if (snapshot.root_disk_total_bytes == 0) 0 else
        100.0 * @as(f32, @floatFromInt(snapshot.root_disk_used_bytes)) /
            @as(f32, @floatFromInt(snapshot.root_disk_total_bytes));
}

fn readNetworkCounters() NetworkCounters {
    var buf: [16384]u8 = undefined;
    const text = readText("/proc/net/dev", &buf);
    var result = NetworkCounters{};
    var lines = std.mem.splitScalar(u8, text, '\n');

    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const iface = std.mem.trim(u8, line[0..colon], " \t");
        if (iface.len == 0 or std.mem.eql(u8, iface, "lo")) continue;

        var fields = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
        var index: usize = 0;
        while (fields.next()) |field| : (index += 1) {
            if (index == 0) result.rx_bytes += std.fmt.parseInt(u64, field, 10) catch 0;
            if (index == 8) {
                result.tx_bytes += std.fmt.parseInt(u64, field, 10) catch 0;
                break;
            }
        }
    }
    return result;
}

fn readMemory(snapshot: *model.Snapshot) void {
    var buf: [8192]u8 = undefined;
    const text = readText("/proc/meminfo", &buf);
    var total_kb: u64 = 0;
    var available_kb: u64 = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) total_kb = firstNumber(line);
        if (std.mem.startsWith(u8, line, "MemAvailable:")) available_kb = firstNumber(line);
    }
    snapshot.memory_total_bytes = total_kb * 1024;
    snapshot.memory_used_bytes = (total_kb -| available_kb) * 1024;
    snapshot.memory_percent = if (total_kb == 0) 0 else
        100.0 * @as(f32, @floatFromInt(total_kb -| available_kb)) / @as(f32, @floatFromInt(total_kb));
}

fn readLoad(snapshot: *model.Snapshot) void {
    var buf: [256]u8 = undefined;
    const text = readText("/proc/loadavg", &buf);
    var tok = std.mem.tokenizeScalar(u8, text, ' ');
    snapshot.load1 = parseFloat(tok.next());
    snapshot.load5 = parseFloat(tok.next());
    snapshot.load15 = parseFloat(tok.next());
}

fn readUptime(snapshot: *model.Snapshot) void {
    var buf: [128]u8 = undefined;
    const text = readText("/proc/uptime", &buf);
    var tok = std.mem.tokenizeScalar(u8, text, ' ');
    snapshot.uptime_seconds = if (tok.next()) |v| std.fmt.parseFloat(f64, v) catch 0 else 0;
}

fn readProcessTicks(out: []TickSample) usize {
    const dir = c.opendir("/proc") orelse return 0;
    defer _ = c.closedir(dir);
    var count: usize = 0;
    while (c.readdir(dir)) |ent| {
        if (count >= out.len) break;
        const name = std.mem.span(@as([*:0]const u8, @ptrCast(&ent.*.d_name)));
        const pid = parsePid(name) orelse continue;
        var path_buf: [64]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, "/proc/{d}/stat", .{pid}) catch continue;
        var stat_buf: [1024]u8 = undefined;
        const stat = readText(path.ptr, &stat_buf);
        const parsed = parseStat(stat) orelse continue;
        out[count] = .{ .pid = pid, .ticks = parsed.ticks };
        count += 1;
    }
    return count;
}

fn readProcesses(out: []model.Process, previous: []const TickSample, total_delta: u64, cpu_count: u16) usize {
    const dir = c.opendir("/proc") orelse return 0;
    defer _ = c.closedir(dir);
    var count: usize = 0;
    while (c.readdir(dir)) |ent| {
        if (count >= out.len) break;
        const name = std.mem.span(@as([*:0]const u8, @ptrCast(&ent.*.d_name)));
        const pid = parsePid(name) orelse continue;

        var stat_path_buf: [64]u8 = undefined;
        const stat_path = std.fmt.bufPrintZ(&stat_path_buf, "/proc/{d}/stat", .{pid}) catch continue;
        var stat_buf: [1024]u8 = undefined;
        const stat = readText(stat_path.ptr, &stat_buf);
        const parsed = parseStat(stat) orelse continue;

        var p = model.Process{ .pid = pid, .ppid = parsed.ppid };
        p.name_len = @intCast(@min(parsed.name.len, p.name.len));
        @memcpy(p.name[0..p.name_len], parsed.name[0..p.name_len]);

        const prev_ticks = findTicks(previous, pid);
        const proc_delta = parsed.ticks -| prev_ticks;
        p.cpu_percent = if (total_delta == 0 or prev_ticks == 0) 0 else
            100.0 * @as(f32, @floatFromInt(proc_delta)) * @as(f32, @floatFromInt(cpu_count)) /
                @as(f32, @floatFromInt(total_delta));

        readProcessMemory(pid, &p);
        readProcessCommand(pid, &p);

        out[count] = p;
        count += 1;
    }
    return count;
}

const ParsedStat = struct {
    name: []const u8,
    ppid: u32,
    ticks: u64,
};

fn parseStat(text: []const u8) ?ParsedStat {
    const open = std.mem.indexOfScalar(u8, text, '(') orelse return null;
    const close = std.mem.lastIndexOfScalar(u8, text, ')') orelse return null;
    if (close <= open or close + 2 >= text.len) return null;

    const name = text[open + 1 .. close];
    var tok = std.mem.tokenizeScalar(u8, text[close + 2 ..], ' ');
    _ = tok.next(); // state
    const ppid_s = tok.next() orelse return null;
    var field: usize = 5;
    var utime: u64 = 0;
    var stime: u64 = 0;
    while (tok.next()) |part| : (field += 1) {
        if (field == 14) utime = std.fmt.parseInt(u64, part, 10) catch 0;
        if (field == 15) {
            stime = std.fmt.parseInt(u64, part, 10) catch 0;
            break;
        }
    }
    return .{
        .name = name,
        .ppid = std.fmt.parseInt(u32, ppid_s, 10) catch 0,
        .ticks = utime + stime,
    };
}

fn readProcessMemory(pid: u32, p: *model.Process) void {
    var path_buf: [64]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "/proc/{d}/status", .{pid}) catch return;
    var buf: [4096]u8 = undefined;
    const text = readText(path.ptr, &buf);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "VmRSS:")) {
            p.memory_bytes = firstNumber(line) * 1024;
            return;
        }
    }
}

fn readProcessCommand(pid: u32, p: *model.Process) void {
    var path_buf: [64]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "/proc/{d}/cmdline", .{pid}) catch return;
    var buf: [512]u8 = undefined;
    const raw = readText(path.ptr, &buf);
    if (raw.len == 0) {
        p.command_len = p.name_len;
        @memcpy(p.command[0..p.command_len], p.name[0..p.name_len]);
        return;
    }
    const n = @min(raw.len, p.command.len);
    var i: usize = 0;
    while (i < n) : (i += 1) p.command[i] = if (raw[i] == 0) ' ' else raw[i];
    p.command_len = @intCast(n);
}

fn firstNumber(line: []const u8) u64 {
    var tok = std.mem.tokenizeAny(u8, line, " \t:");
    _ = tok.next();
    return if (tok.next()) |v| std.fmt.parseInt(u64, v, 10) catch 0 else 0;
}

fn parseFloat(v: ?[]const u8) f32 {
    return if (v) |s| std.fmt.parseFloat(f32, s) catch 0 else 0;
}

fn parsePid(name: []const u8) ?u32 {
    if (name.len == 0) return null;
    for (name) |ch| if (ch < '0' or ch > '9') return null;
    return std.fmt.parseInt(u32, name, 10) catch null;
}

fn findTicks(previous: []const TickSample, pid: u32) u64 {
    for (previous) |s| if (s.pid == pid) return s.ticks;
    return 0;
}

fn sortProcesses(items: []model.Process, mode: model.SortMode) void {
    const Ctx = struct {
        mode: model.SortMode,
        fn less(ctx: @This(), a: model.Process, b: model.Process) bool {
            return switch (ctx.mode) {
                .cpu => a.cpu_percent > b.cpu_percent,
                .memory => a.memory_bytes > b.memory_bytes,
                .pid => a.pid < b.pid,
            };
        }
    };
    std.mem.sort(model.Process, items, Ctx{ .mode = mode }, Ctx.less);
}

test "parse stat" {
    const sample = "123 (my worker) S 7 0 0 0 0 0 0 0 0 0 20 5 0 0";
    const parsed = parseStat(sample).?;
    try std.testing.expectEqual(@as(u32, 7), parsed.ppid);
    try std.testing.expectEqual(@as(u64, 25), parsed.ticks);
    try std.testing.expectEqualStrings("my worker", parsed.name);
}

test "parse pid" {
    try std.testing.expectEqual(@as(?u32, 1234), parsePid("1234"));
    try std.testing.expect(parsePid("self") == null);
}

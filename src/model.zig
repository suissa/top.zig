const std = @import("std");

pub const SortMode = enum {
    cpu,
    memory,
    pid,
};

pub const Tab = enum(u8) {
    overview = 0,
    cpu,
    memory,
    processes,
    disk,
    network,
    containers,
    system,

    pub fn label(self: Tab) []const u8 {
        return switch (self) {
            .overview => "Overview",
            .cpu => "CPU",
            .memory => "Memory",
            .processes => "Processes",
            .disk => "Disk",
            .network => "Network",
            .containers => "Containers",
            .system => "System",
        };
    }

    pub fn next(self: Tab) Tab {
        return @enumFromInt((@intFromEnum(self) + 1) % 8);
    }

    pub fn previous(self: Tab) Tab {
        return @enumFromInt((@intFromEnum(self) + 7) % 8);
    }

    pub fn fromDigit(key: u8) ?Tab {
        if (key < '1' or key > '8') return null;
        return @enumFromInt(key - '1');
    }
};


pub const TabSet = struct {
    enabled: [8]bool = [_]bool{true} ** 8,

    pub fn all() TabSet {
        return .{};
    }

    pub fn fromCsv(csv: []const u8) TabSet {
        var result = TabSet{ .enabled = [_]bool{false} ** 8 };
        var it = std.mem.tokenizeScalar(u8, csv, ',');
        var found = false;
        while (it.next()) |raw| {
            const name = std.mem.trim(u8, raw, " \t\r\n");
            if (tabFromName(name)) |tab| {
                result.enabled[@intFromEnum(tab)] = true;
                found = true;
            }
        }
        return if (found) result else TabSet.all();
    }

    pub fn isEnabled(self: *const TabSet, tab: Tab) bool {
        return self.enabled[@intFromEnum(tab)];
    }

    pub fn count(self: *const TabSet) usize {
        var n: usize = 0;
        for (self.enabled) |value| {\n            if (value) n += 1;\n        }
        return n;
    }

    pub fn first(self: *const TabSet) Tab {
        for (self.enabled, 0..) |value, i| {
            if (value) return @enumFromInt(i);
        }
        return .overview;
    }

    pub fn nth(self: *const TabSet, target: usize) ?Tab {
        var visible: usize = 0;
        for (self.enabled, 0..) |value, i| {
            if (!value) continue;
            if (visible == target) return @enumFromInt(i);
            visible += 1;
        }
        return null;
    }

    pub fn next(self: *const TabSet, current: Tab) Tab {
        var i: usize = 1;
        while (i <= 8) : (i += 1) {
            const idx = (@intFromEnum(current) + i) % 8;
            const tab: Tab = @enumFromInt(idx);
            if (self.isEnabled(tab)) return tab;
        }
        return current;
    }

    pub fn previous(self: *const TabSet, current: Tab) Tab {
        var i: usize = 1;
        while (i <= 8) : (i += 1) {
            const idx = (@intFromEnum(current) + 8 - (i % 8)) % 8;
            const tab: Tab = @enumFromInt(idx);
            if (self.isEnabled(tab)) return tab;
        }
        return current;
    }

    fn tabFromName(name: []const u8) ?Tab {
        inline for ([_]Tab{ .overview, .cpu, .memory, .processes, .disk, .network, .containers, .system }) |tab| {
            if (std.ascii.eqlIgnoreCase(name, tab.label())) return tab;
        }
        if (std.ascii.eqlIgnoreCase(name, "proc")) return .processes;
        if (std.ascii.eqlIgnoreCase(name, "mem")) return .memory;
        if (std.ascii.eqlIgnoreCase(name, "net")) return .network;
        return null;
    }
};

pub const Process = struct {
    pid: u32 = 0,
    ppid: u32 = 0,
    name: [64]u8 = [_]u8{0} ** 64,
    name_len: u8 = 0,
    command: [192]u8 = [_]u8{0} ** 192,
    command_len: u8 = 0,
    cpu_percent: f32 = 0,
    memory_bytes: u64 = 0,

    pub fn nameSlice(self: *const Process) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn commandSlice(self: *const Process) []const u8 {
        return self.command[0..self.command_len];
    }
};

pub const MaxProcesses = 512;
pub const HistoryLen = 96;

pub const Snapshot = struct {
    cpu_percent: f32 = 0,
    memory_percent: f32 = 0,
    memory_used_bytes: u64 = 0,
    memory_total_bytes: u64 = 0,
    load1: f32 = 0,
    load5: f32 = 0,
    load15: f32 = 0,
    uptime_seconds: f64 = 0,
    cpu_count: u16 = 1,
    process_count: usize = 0,
    processes: [MaxProcesses]Process = [_]Process{.{}} ** MaxProcesses,
};

pub const History = struct {
    cpu: [HistoryLen]f32 = [_]f32{0} ** HistoryLen,
    memory: [HistoryLen]f32 = [_]f32{0} ** HistoryLen,
    len: usize = 0,

    pub fn push(self: *History, cpu: f32, memory: f32) void {
        if (self.len < HistoryLen) {
            self.cpu[self.len] = cpu;
            self.memory[self.len] = memory;
            self.len += 1;
            return;
        }
        std.mem.copyForwards(f32, self.cpu[0 .. HistoryLen - 1], self.cpu[1..HistoryLen]);
        std.mem.copyForwards(f32, self.memory[0 .. HistoryLen - 1], self.memory[1..HistoryLen]);
        self.cpu[HistoryLen - 1] = cpu;
        self.memory[HistoryLen - 1] = memory;
    }
};

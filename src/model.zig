const std = @import("std");

pub const SortMode = enum {
    cpu,
    memory,
    pid,
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

const std = @import("std");
const tui = @import("tui");
const model = @import("model.zig");

pub const ViewState = struct {
    displayed_cpu: f32 = 0,
    displayed_memory: f32 = 0,
    selected: usize = 0,
    frame: u64 = 0,

    pub fn animate(self: *ViewState, snapshot: *const model.Snapshot) void {
        self.displayed_cpu += (snapshot.cpu_percent - self.displayed_cpu) * 0.16;
        self.displayed_memory += (snapshot.memory_percent - self.displayed_memory) * 0.16;
        self.frame +%= 1;
    }
};

const cyan = tui.Color.fromRGB(57, 214, 255);
const violet = tui.Color.fromRGB(160, 92, 255);
const green = tui.Color.fromRGB(74, 235, 168);
const amber = tui.Color.fromRGB(255, 191, 71);
const red = tui.Color.fromRGB(255, 91, 122);
const dim = tui.Color.fromRGB(112, 126, 150);
const white = tui.Color.fromRGB(228, 236, 247);
const panel = tui.Color.fromRGB(16, 22, 34);

pub fn render(
    screen: *tui.screen.Screen,
    snapshot: *const model.Snapshot,
    history: *const model.History,
    view: *ViewState,
    sort_mode: model.SortMode,
    now_ns: i128,
) void {
    view.animate(snapshot);
    screen.clearWithStyle(tui.Style.default.setBg(tui.Color.fromRGB(7, 10, 17)));

    if (screen.width < 58 or screen.height < 18) {
        screen.setStyle(tui.Style.default.setFg(white).bold());
        screen.putStringAt(2, 2, "top.zig");
        screen.setStyle(tui.Style.default.setFg(amber));
        screen.putStringAt(2, 4, "Terminal too small (need at least 58x18)");
        return;
    }

    drawHeader(screen, snapshot, now_ns);
    drawMetricPanel(screen, 1, 3, (screen.width - 3) / 2, 6, "CPU", view.displayed_cpu, cyan, violet);
    drawMetricPanel(screen, 2 + (screen.width - 3) / 2, 3, (screen.width - 3) / 2, 6, "MEMORY", view.displayed_memory, green, cyan);
    drawHistory(screen, 1, 10, screen.width - 2, 5, history);
    drawProcessTable(screen, 1, 16, screen.width - 2, screen.height -| 18, snapshot, sort_mode, view.frame);
    drawFooter(screen, sort_mode);
}

fn drawHeader(screen: *tui.screen.Screen, s: *const model.Snapshot, now_ns: i128) void {
    screen.setStyle(tui.Style.default.setFg(cyan).bold());
    screen.putStringAt(1, 1, "◈ top.zig");
    screen.setStyle(tui.Style.default.setFg(dim));
    var buf: [160]u8 = undefined;
    const uptime_h = @as(u64, @intFromFloat(s.uptime_seconds)) / 3600;
    const uptime_m = (@as(u64, @intFromFloat(s.uptime_seconds)) % 3600) / 60;
    const pulse = @mod(@divTrunc(now_ns, 250_000_000), 4);
    const dot: []const u8 = switch (pulse) { 0 => "·", 1 => "•", 2 => "●", else => "•" };
    const text = std.fmt.bufPrint(&buf, "{s} load {d:.2} {d:.2} {d:.2}   uptime {d}h{d:0>2}m   {d} CPUs   {d} proc", .{
        dot, s.load1, s.load5, s.load15, uptime_h, uptime_m, s.cpu_count, s.process_count,
    }) catch "";
    const x: u16 = if (text.len + 2 < screen.width) @intCast(screen.width - text.len - 1) else 14;
    screen.putStringAt(x, 1, text);
}

fn drawMetricPanel(screen: *tui.screen.Screen, x: u16, y: u16, w: u16, h: u16, title: []const u8, percent: f32, a: tui.Color, b: tui.Color) void {
    screen.setStyle(tui.Style.default.setFg(dim).setBg(panel));
    screen.fill(x, y, w, h, ' ');
    screen.drawBox(x, y, w, h, .rounded);

    screen.setStyle(tui.Style.default.setFg(white).setBg(panel).bold());
    screen.putStringAt(x + 2, y + 1, title);

    var buf: [32]u8 = undefined;
    const p = std.math.clamp(percent, 0, 999);
    const label = std.fmt.bufPrint(&buf, "{d:5.1}%", .{p}) catch "";
    if (w > label.len + 3) screen.putStringAt(@intCast(x + w - label.len - 2), y + 1, label);

    if (w <= 6) return;
    const bar_w: u16 = w - 4;
    const fill_f = std.math.clamp(percent / 100.0, 0.0, 1.0) * @as(f32, @floatFromInt(bar_w));
    const filled: u16 = @intFromFloat(fill_f);

    for (0..bar_w) |i| {
        const t = if (bar_w <= 1) 0 else @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(bar_w - 1));
        const col = blend(a, b, t);
        const active = i < filled;
        screen.setStyle(tui.Style.default
            .setFg(if (active) col else tui.Color.fromRGB(39, 48, 66))
            .setBg(panel)
            .bold());
        screen.putStringAt(@intCast(x + 2 + i), y + 3, if (active) "█" else "░");
    }
}

fn drawHistory(screen: *tui.screen.Screen, x: u16, y: u16, w: u16, h: u16, history: *const model.History) void {
    screen.setStyle(tui.Style.default.setFg(dim).setBg(panel));
    screen.fill(x, y, w, h, ' ');
    screen.drawBox(x, y, w, h, .rounded);
    screen.setStyle(tui.Style.default.setFg(white).setBg(panel).bold());
    screen.putStringAt(x + 2, y + 1, "HISTORY");
    if (w < 10 or history.len == 0) return;

    const chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
    const usable: usize = @intCast(w - 4);
    const count = @min(usable, history.len);
    const start = history.len - count;
    for (0..count) |i| {
        const value = std.math.clamp(history.cpu[start + i], 0, 100);
        const level: usize = @min(7, @as(usize, @intFromFloat(value / 100.0 * 7.0)));
        screen.setStyle(tui.Style.default.setFg(blend(cyan, violet, value / 100.0)).setBg(panel));
        screen.putStringAt(@intCast(x + 2 + i), y + 3, chars[level]);
    }
}

fn drawProcessTable(screen: *tui.screen.Screen, x: u16, y: u16, w: u16, h: u16, s: *const model.Snapshot, sort_mode: model.SortMode, frame: u64) void {
    if (h < 4) return;
    screen.setStyle(tui.Style.default.setFg(dim).setBg(panel));
    screen.fill(x, y, w, h, ' ');
    screen.drawBox(x, y, w, h, .rounded);

    screen.setStyle(tui.Style.default.setFg(white).setBg(panel).bold());
    var title_buf: [64]u8 = undefined;
    const sort_label = switch (sort_mode) { .cpu => "CPU", .memory => "MEM", .pid => "PID" };
    const title = std.fmt.bufPrint(&title_buf, "PROCESSES  sort:{s}", .{sort_label}) catch "PROCESSES";
    screen.putStringAt(x + 2, y + 1, title);

    screen.setStyle(tui.Style.default.setFg(dim).setBg(panel).bold());
    screen.putStringAt(x + 2, y + 2, "PID      CPU%      MEM       COMMAND");

    const max_rows: usize = @intCast(h - 4);
    const rows = @min(max_rows, s.process_count);
    for (0..rows) |i| {
        const p = &s.processes[i];
        const row_y: u16 = @intCast(y + 3 + i);
        const hot = p.cpu_percent >= 50;
        const color = if (hot and (frame / 10) % 2 == 0) red else if (p.cpu_percent >= 10) amber else white;
        screen.setStyle(tui.Style.default.setFg(color).setBg(panel));

        var line: [512]u8 = undefined;
        const cmd = if (p.command_len > 0) p.commandSlice() else p.nameSlice();
        const max_cmd = @min(cmd.len, @as(usize, w -| 31));
        const mem_mb = @as(f64, @floatFromInt(p.memory_bytes)) / (1024.0 * 1024.0);
        const text = std.fmt.bufPrint(&line, "{d:<8} {d:>6.1}   {d:>7.1}M   {s}", .{
            p.pid, p.cpu_percent, mem_mb, cmd[0..max_cmd],
        }) catch "";
        screen.putStringAt(x + 2, row_y, text);
    }
}

fn drawFooter(screen: *tui.screen.Screen, sort_mode: model.SortMode) void {
    if (screen.height < 2) return;
    const y = screen.height - 1;
    screen.setStyle(tui.Style.default.setBg(tui.Color.fromRGB(12, 17, 27)).setFg(dim));
    screen.fill(0, y, screen.width, 1, ' ');
    screen.setStyle(tui.Style.default.setBg(tui.Color.fromRGB(12, 17, 27)).setFg(white));
    const active = switch (sort_mode) { .cpu => "CPU", .memory => "MEM", .pid => "PID" };
    var buf: [160]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, " q quit   c CPU   m MEM   p PID   r refresh    active: {s}", .{active}) catch "";
    screen.putStringAt(2, y, text);
}

fn blend(a: tui.Color, b: tui.Color, t: f32) tui.Color {
    const ar = switch (a) { .rgb => |v| v, else => tui.Color.RGB{ .r = 255, .g = 255, .b = 255 } };
    const br = switch (b) { .rgb => |v| v, else => tui.Color.RGB{ .r = 255, .g = 255, .b = 255 } };
    return .{ .rgb = ar.blend(br, std.math.clamp(t, 0, 1)) };
}

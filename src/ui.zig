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
const bg = tui.Color.fromRGB(7, 10, 17);
const tab_bg = tui.Color.fromRGB(12, 17, 27);
const all_tabs = [_]model.Tab{
    .overview,
    .cpu,
    .memory,
    .processes,
    .disk,
    .network,
    .containers,
    .system,
};


pub fn tabAt(tab_set: *const model.TabSet, x: u16, y: u16) ?model.Tab {
    if (y != 2) return null;

    var cursor: u16 = 1;
    var visible: usize = 0;
    for (all_tabs) |tab| {
        if (!tab_set.isEnabled(tab)) continue;
        _ = visible;
        const width: u16 = @intCast(tab.label().len + 4);
        if (x >= cursor and x < cursor + width) return tab;
        cursor += width + 1;
        visible += 1;
    }
    return null;
}

pub fn render(
    screen: *tui.screen.Screen,
    snapshot: *const model.Snapshot,
    history: *const model.History,
    view: *ViewState,
    sort_mode: model.SortMode,
    tab_set: *const model.TabSet,
    active_tab: model.Tab,
    now_ns: i128,
) void {
    view.animate(snapshot);
    screen.clearWithStyle(tui.Style.default.setBg(bg));

    if (screen.width < 58 or screen.height < 18) {
        screen.setStyle(tui.Style.default.setFg(white).bold());
        screen.putStringAt(2, 2, "top.zig");
        screen.setStyle(tui.Style.default.setFg(amber));
        screen.putStringAt(2, 4, "Terminal too small (need at least 58x18)");
        return;
    }

    drawHeader(screen, snapshot, now_ns);
    drawTabs(screen, tab_set, active_tab);

    switch (active_tab) {
        .overview => drawOverview(screen, snapshot, history, view, sort_mode),
        .cpu => drawCpu(screen, snapshot, history, view, sort_mode),
        .memory => drawMemory(screen, snapshot, history, view, sort_mode),
        .processes => drawProcesses(screen, snapshot, sort_mode, view.frame),
        .disk => drawPlanned(screen, "DISK", "Capacity, throughput, I/O pressure and top I/O processes", "docs/Tabs/disk/.README.md"),
        .network => drawPlanned(screen, "NETWORK", "Interfaces, RX/TX, errors, sockets and process correlation", "docs/Tabs/network/.README.md"),
        .containers => drawPlanned(screen, "CONTAINERS", "cgroup/Docker ownership, resource use and process mapping", "docs/Tabs/containers/.README.md"),
        .system => drawSystem(screen, snapshot),
    }

    drawFooter(screen, sort_mode, tab_set, active_tab);
}

fn drawHeader(screen: *tui.screen.Screen, s: *const model.Snapshot, now_ns: i128) void {
    screen.setStyle(tui.Style.default.setFg(cyan).bold());
    screen.putStringAt(1, 1, "◈ top.zig");

    screen.setStyle(tui.Style.default.setFg(dim));
    var buf: [160]u8 = undefined;
    const uptime_h = @as(u64, @intFromFloat(s.uptime_seconds)) / 3600;
    const uptime_m = (@as(u64, @intFromFloat(s.uptime_seconds)) % 3600) / 60;
    const pulse = @mod(@divTrunc(now_ns, 250_000_000), 4);
    const dot: []const u8 = switch (pulse) {
        0 => "·",
        1 => "•",
        2 => "●",
        else => "•",
    };
    const text = std.fmt.bufPrint(&buf, "{s} load {d:.2} {d:.2} {d:.2}   uptime {d}h{d:0>2}m   {d} CPUs   {d} proc", .{
        dot, s.load1, s.load5, s.load15, uptime_h, uptime_m, s.cpu_count, s.process_count,
    }) catch "";
    const x: u16 = if (text.len + 2 < screen.width) @intCast(screen.width - text.len - 1) else 14;
    screen.putStringAt(x, 1, text);
}

fn drawTabs(screen: *tui.screen.Screen, tab_set: *const model.TabSet, active: model.Tab) void {
    screen.setStyle(tui.Style.default.setBg(tab_bg).setFg(dim));
    screen.fill(0, 2, screen.width, 1, ' ');

    var x: u16 = 1;
    var visible: usize = 0;
    for (all_tabs) |tab| {
        if (!tab_set.isEnabled(tab)) continue;
        if (x + tab.label().len + 4 >= screen.width) break;
        const is_active = tab == active;
        screen.setStyle(if (is_active)
            tui.Style.default.setBg(tui.Color.fromRGB(30, 42, 65)).setFg(cyan).bold()
        else
            tui.Style.default.setBg(tab_bg).setFg(dim));

        var label_buf: [32]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, " {d}:{s} ", .{ visible + 1, tab.label() }) catch "";
        visible += 1;
        screen.putStringAt(x, 2, label);
        x += @intCast(label.len + 1);
    }
}

fn drawOverview(screen: *tui.screen.Screen, s: *const model.Snapshot, history: *const model.History, view: *ViewState, sort_mode: model.SortMode) void {
    drawMetricPanel(screen, 1, 4, (screen.width - 3) / 2, 6, "CPU", view.displayed_cpu, cyan, violet);
    drawMetricPanel(screen, 2 + (screen.width - 3) / 2, 4, (screen.width - 3) / 2, 6, "MEMORY", view.displayed_memory, green, cyan);
    drawHistory(screen, 1, 11, screen.width - 2, 5, history, .cpu);
    drawProcessTable(screen, 1, 17, screen.width - 2, screen.height -| 19, s, sort_mode, view.frame, 0);
}

fn drawCpu(screen: *tui.screen.Screen, s: *const model.Snapshot, history: *const model.History, view: *ViewState, sort_mode: model.SortMode) void {
    drawMetricPanel(screen, 1, 4, screen.width - 2, 6, "TOTAL CPU", view.displayed_cpu, cyan, violet);
    drawHistory(screen, 1, 11, screen.width - 2, 6, history, .cpu);
    drawProcessTable(screen, 1, 18, screen.width - 2, screen.height -| 20, s, sort_mode, view.frame, 0);
}

fn drawMemory(screen: *tui.screen.Screen, s: *const model.Snapshot, history: *const model.History, view: *ViewState, sort_mode: model.SortMode) void {
    drawMetricPanel(screen, 1, 4, screen.width - 2, 6, "MEMORY", view.displayed_memory, green, cyan);

    var mem_buf: [128]u8 = undefined;
    const used_gib = @as(f64, @floatFromInt(s.memory_used_bytes)) / (1024.0 * 1024.0 * 1024.0);
    const total_gib = @as(f64, @floatFromInt(s.memory_total_bytes)) / (1024.0 * 1024.0 * 1024.0);
    const mem_text = std.fmt.bufPrint(&mem_buf, "Used {d:.2} GiB / {d:.2} GiB", .{ used_gib, total_gib }) catch "";
    screen.setStyle(tui.Style.default.setFg(white));
    screen.putStringAt(3, 10, mem_text);

    drawHistory(screen, 1, 12, screen.width - 2, 5, history, .memory);
    drawProcessTable(screen, 1, 18, screen.width - 2, screen.height -| 20, s, .memory, view.frame, 0);
    _ = sort_mode;
}

fn drawProcesses(screen: *tui.screen.Screen, s: *const model.Snapshot, sort_mode: model.SortMode, frame: u64) void {
    drawProcessTable(screen, 1, 4, screen.width - 2, screen.height -| 6, s, sort_mode, frame, 0);
}

fn drawSystem(screen: *tui.screen.Screen, s: *const model.Snapshot) void {
    const w = screen.width - 2;
    screen.setStyle(tui.Style.default.setFg(dim).setBg(panel));
    screen.fill(1, 4, w, 11, ' ');
    screen.drawBox(1, 4, w, 11, .rounded);

    screen.setStyle(tui.Style.default.setFg(white).setBg(panel).bold());
    screen.putStringAt(3, 5, "SYSTEM");

    const uptime_total: u64 = @intFromFloat(s.uptime_seconds);
    const days = uptime_total / 86400;
    const hours = (uptime_total % 86400) / 3600;
    const mins = (uptime_total % 3600) / 60;

    var line1: [128]u8 = undefined;
    var line2: [128]u8 = undefined;
    var line3: [128]u8 = undefined;
    const a = std.fmt.bufPrint(&line1, "CPU cores       {d}", .{s.cpu_count}) catch "";
    const b = std.fmt.bufPrint(&line2, "Uptime          {d}d {d}h {d}m", .{ days, hours, mins }) catch "";
    const c = std.fmt.bufPrint(&line3, "Load average    {d:.2}  {d:.2}  {d:.2}", .{ s.load1, s.load5, s.load15 }) catch "";

    screen.setStyle(tui.Style.default.setFg(white).setBg(panel));
    screen.putStringAt(3, 7, a);
    screen.putStringAt(3, 9, b);
    screen.putStringAt(3, 11, c);

    screen.setStyle(tui.Style.default.setFg(dim).setBg(panel));
    screen.putStringAt(3, 13, "Next: hostname, kernel, sensors, PSI and systemd service health");
}

const HistoryMetric = enum { cpu, memory };

fn drawHistory(screen: *tui.screen.Screen, x: u16, y: u16, w: u16, h: u16, history: *const model.History, metric: HistoryMetric) void {
    screen.setStyle(tui.Style.default.setFg(dim).setBg(panel));
    screen.fill(x, y, w, h, ' ');
    screen.drawBox(x, y, w, h, .rounded);

    screen.setStyle(tui.Style.default.setFg(white).setBg(panel).bold());
    screen.putStringAt(x + 2, y + 1, if (metric == .cpu) "CPU HISTORY" else "MEMORY HISTORY");
    if (w < 10 or history.len == 0) return;

    const chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
    const usable: usize = @intCast(w - 4);
    const count = @min(usable, history.len);
    const start = history.len - count;

    for (0..count) |i| {
        const raw = if (metric == .cpu) history.cpu[start + i] else history.memory[start + i];
        const value = std.math.clamp(raw, 0, 100);
        const level: usize = @min(7, @as(usize, @intFromFloat(value / 100.0 * 7.0)));
        const color = if (metric == .cpu) blend(cyan, violet, value / 100.0) else blend(green, cyan, value / 100.0);
        screen.setStyle(tui.Style.default.setFg(color).setBg(panel));
        screen.putStringAt(@intCast(x + 2 + i), y + 3, chars[level]);
    }
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

fn drawProcessTable(screen: *tui.screen.Screen, x: u16, y: u16, w: u16, h: u16, s: *const model.Snapshot, sort_mode: model.SortMode, frame: u64, offset: usize) void {
    if (h < 4) return;
    screen.setStyle(tui.Style.default.setFg(dim).setBg(panel));
    screen.fill(x, y, w, h, ' ');
    screen.drawBox(x, y, w, h, .rounded);

    screen.setStyle(tui.Style.default.setFg(white).setBg(panel).bold());
    var title_buf: [64]u8 = undefined;
    const sort_label = switch (sort_mode) {
        .cpu => "CPU",
        .memory => "MEM",
        .pid => "PID",
    };
    const title = std.fmt.bufPrint(&title_buf, "PROCESSES  sort:{s}", .{sort_label}) catch "PROCESSES";
    screen.putStringAt(x + 2, y + 1, title);

    screen.setStyle(tui.Style.default.setFg(dim).setBg(panel).bold());
    screen.putStringAt(x + 2, y + 2, "PID      PPID     CPU%      MEM       COMMAND");

    const max_rows: usize = @intCast(h - 4);
    const available = s.process_count -| offset;
    const rows = @min(max_rows, available);
    for (0..rows) |row| {
        const i = row + offset;
        const p = &s.processes[i];
        const row_y: u16 = @intCast(y + 3 + row);
        const hot = p.cpu_percent >= 50;
        const color = if (hot and (frame / 10) % 2 == 0) red else if (p.cpu_percent >= 10) amber else white;
        screen.setStyle(tui.Style.default.setFg(color).setBg(panel));

        var line: [512]u8 = undefined;
        const cmd = if (p.command_len > 0) p.commandSlice() else p.nameSlice();
        const max_cmd = @min(cmd.len, @as(usize, w -| 40));
        const mem_mb = @as(f64, @floatFromInt(p.memory_bytes)) / (1024.0 * 1024.0);
        const text = std.fmt.bufPrint(&line, "{d:<8} {d:<8} {d:>6.1}   {d:>7.1}M   {s}", .{
            p.pid, p.ppid, p.cpu_percent, mem_mb, cmd[0..max_cmd],
        }) catch "";
        screen.putStringAt(x + 2, row_y, text);
    }
}

fn drawPlanned(screen: *tui.screen.Screen, title: []const u8, description: []const u8, doc: []const u8) void {
    const w = screen.width - 2;
    screen.setStyle(tui.Style.default.setFg(dim).setBg(panel));
    screen.fill(1, 4, w, 10, ' ');
    screen.drawBox(1, 4, w, 10, .rounded);

    screen.setStyle(tui.Style.default.setFg(cyan).setBg(panel).bold());
    screen.putStringAt(3, 6, title);
    screen.setStyle(tui.Style.default.setFg(white).setBg(panel));
    screen.putStringAt(3, 8, description);
    screen.setStyle(tui.Style.default.setFg(dim).setBg(panel));
    screen.putStringAt(3, 10, "Collector planned; UI contract:");
    screen.putStringAt(3, 11, doc);
}

fn drawFooter(screen: *tui.screen.Screen, sort_mode: model.SortMode, tab_set: *const model.TabSet, active_tab: model.Tab) void {
    if (screen.height < 2) return;
    const y = screen.height - 1;
    screen.setStyle(tui.Style.default.setBg(tab_bg).setFg(dim));
    screen.fill(0, y, screen.width, 1, ' ');

    screen.setStyle(tui.Style.default.setBg(tab_bg).setFg(white));
    const active_sort = switch (sort_mode) {
        .cpu => "CPU",
        .memory => "MEM",
        .pid => "PID",
    };
    var buf: [220]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, " Tab/arrows navigate   1-{d} direct   click tabs   q quit   c/m/p sort   tab:{s} sort:{s}", .{
        tab_set.count(), active_tab.label(), active_sort,
    }) catch "";
    screen.putStringAt(2, y, text);
}

fn blend(a: tui.Color, b: tui.Color, t: f32) tui.Color {
    const ar = switch (a) {
        .rgb => |v| v,
        else => tui.Color.RGB{ .r = 255, .g = 255, .b = 255 },
    };
    const br = switch (b) {
        .rgb => |v| v,
        else => tui.Color.RGB{ .r = 255, .g = 255, .b = 255 },
    };
    return .{ .rgb = ar.blend(br, std.math.clamp(t, 0, 1)) };
}

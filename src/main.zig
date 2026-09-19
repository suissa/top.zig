const std = @import("std");
const tui = @import("tui");
const model = @import("model.zig");
const collector = @import("collector.zig");
const ui = @import("ui.zig");
const render_adapter = @import("renderer.zig");

const c = @cImport({
    @cInclude("poll.h");
    @cInclude("unistd.h");
    @cInclude("time.h");
    @cInclude("stdio.h");
});

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var tab_set = readTabConfig();

    var term = try tui.terminal.Terminal.init(.{
        .alternate_screen = true,
        .hide_cursor = true,
        .enable_mouse = true,
        .enable_paste = false,
        .enable_focus = false,
    });
    defer term.deinit();

    const initial_size = try term.getSize();
    var screen = try tui.screen.Screen.init(allocator, initial_size.cols, initial_size.rows);
    defer screen.deinit();

    var renderer = render_adapter.Renderer.init();

    var input = tui.input.InputReader.init(allocator);

    var snapshot = model.Snapshot{};
    var history = model.History{};
    var view = ui.ViewState{};
    var sort_mode: model.SortMode = .cpu;
    var active_tab: model.Tab = tab_set.first();

    var force_refresh = true;
    var last_collect_ns: i128 = 0;

    while (true) {
        if (readEvent(&input)) |event| {
            switch (event) {
                .key => |key| {
                    if (key.modifiers.ctrl) {
                        switch (key.key) {
                            .char => |ch| if (ch == 'c') break,
                            else => {},
                        }
                    }

                    switch (key.key) {
                        .tab => active_tab = if (key.modifiers.shift) tab_set.previous(active_tab) else tab_set.next(active_tab),
                        .left => active_tab = tab_set.previous(active_tab),
                        .right => active_tab = tab_set.next(active_tab),
                        .char => |ch| {
                            if (ch <= 0x7f) {
                                const byte: u8 = @intCast(ch);
                                if (byte >= '1' and byte <= '8') {
                                    if (tab_set.nth(byte - '1')) |tab| active_tab = tab;
                                } else switch (byte) {
                                    'q', 'Q' => break,
                                    '[', 'h' => active_tab = tab_set.previous(active_tab),
                                    ']', 'l' => active_tab = tab_set.next(active_tab),
                                    'c', 'C' => {
                                        sort_mode = .cpu;
                                        force_refresh = true;
                                    },
                                    'm', 'M' => {
                                        sort_mode = .memory;
                                        force_refresh = true;
                                    },
                                    'p', 'P' => {
                                        sort_mode = .pid;
                                        force_refresh = true;
                                    },
                                    'r', 'R' => force_refresh = true,
                                    else => {},
                                }
                            }
                        },
                        else => {},
                    }
                },
                .mouse => |mouse| {
                    if (mouse.kind == .press and mouse.button == .left) {
                        if (ui.tabAt(&tab_set, mouse.x, mouse.y)) |tab| active_tab = tab;
                    }
                },
                else => {},
            }
        }

        const size = term.getSize() catch initial_size;
        if (size.cols != screen.width or size.rows != screen.height) {
            try screen.resize(size.cols, size.rows);
        }

        const now = monotonicNs();
        if (force_refresh or now - last_collect_ns >= 900_000_000) {
            collector.collect(&snapshot, sort_mode);
            history.push(snapshot.cpu_percent, snapshot.memory_percent);
            last_collect_ns = monotonicNs();
            force_refresh = false;
        }

        ui.render(&screen, &snapshot, &history, &view, sort_mode, &tab_set, active_tab, now);
        try renderer.render(&screen);
        _ = c.usleep(33_000);
    }
}

fn readEvent(input: *tui.input.InputReader) ?tui.events.Event {
    var fds = [_]c.struct_pollfd{.{
        .fd = c.STDIN_FILENO,
        .events = c.POLLIN,
        .revents = 0,
    }};

    const ready = c.poll(&fds, 1, 0);
    if (ready <= 0 or (fds[0].revents & c.POLLIN) == 0) return null;

    var bytes: [32]u8 = undefined;
    const n = c.read(c.STDIN_FILENO, &bytes, bytes.len);
    if (n <= 0) return null;

    const len: usize = @intCast(n);
    return input.parse(bytes[0..len]) catch null;
}

fn monotonicNs() i128 {
    var ts: c.struct_timespec = undefined;
    if (c.clock_gettime(c.CLOCK_MONOTONIC, &ts) != 0) return 0;
    return @as(i128, ts.tv_sec) * 1_000_000_000 + @as(i128, ts.tv_nsec);
}


fn readTabConfig() model.TabSet {
    var result = model.TabSet.all();
    const file = c.fopen("/proc/self/cmdline", "rb") orelse return result;
    defer _ = c.fclose(file);

    var buf: [4096]u8 = undefined;
    const n = c.fread(&buf, 1, buf.len, file);
    if (n == 0) return result;

    var start: usize = 0;
    var index: usize = 0;
    while (index <= n) : (index += 1) {
        if (index == n or buf[index] == 0) {
            if (index > start) {
                const arg = buf[start..index];
                if (std.mem.startsWith(u8, arg, "--tabs=")) {
                    result = model.TabSet.fromCsv(arg["--tabs=".len..]);
                }
            }
            start = index + 1;
        }
    }
    return result;
}

const std = @import("std");
const tui = @import("tui");
const model = @import("model.zig");
const collector = @import("collector.zig");
const ui = @import("ui.zig");

const c = @cImport({
    @cInclude("poll.h");
    @cInclude("unistd.h");
});

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var term = try tui.terminal.Terminal.init(.{
        .alternate_screen = true,
        .hide_cursor = true,
        .enable_mouse = false,
        .enable_paste = false,
        .enable_focus = false,
    });
    defer term.deinit();

    const initial_size = try term.getSize();
    var screen = try tui.screen.Screen.init(allocator, initial_size.cols, initial_size.rows);
    defer screen.deinit();

    var renderer = tui.renderer.Renderer.init(allocator);
    defer renderer.deinit();

    var snapshot = model.Snapshot{};
    var history = model.History{};
    var view = ui.ViewState{};
    var sort_mode: model.SortMode = .cpu;

    var force_refresh = true;
    var last_collect_ns: i128 = 0;

    while (true) {
        if (readKey()) |key| {
            switch (key) {
                'q', 'Q', 3 => break,
                'c', 'C' => { sort_mode = .cpu; force_refresh = true; },
                'm', 'M' => { sort_mode = .memory; force_refresh = true; },
                'p', 'P' => { sort_mode = .pid; force_refresh = true; },
                'r', 'R' => force_refresh = true,
                else => {},
            }
        }

        const size = term.getSize() catch initial_size;
        if (size.cols != screen.width or size.rows != screen.height) {
            try screen.resize(size.cols, size.rows);
            renderer.invalidate();
        }

        const now = std.time.nanoTimestamp();
        if (force_refresh or now - last_collect_ns >= 900_000_000) {
            collector.collect(&snapshot, sort_mode);
            history.push(snapshot.cpu_percent, snapshot.memory_percent);
            last_collect_ns = std.time.nanoTimestamp();
            force_refresh = false;
        }

        ui.render(&screen, &snapshot, &history, &view, sort_mode, now);
        try renderer.render(&screen);
        std.Thread.sleep(33 * std.time.ns_per_ms);
    }
}

fn readKey() ?u8 {
    var fds = [_]c.struct_pollfd{.{
        .fd = c.STDIN_FILENO,
        .events = c.POLLIN,
        .revents = 0,
    }};
    const ready = c.poll(&fds, 1, 0);
    if (ready <= 0 or (fds[0].revents & c.POLLIN) == 0) return null;
    var byte: u8 = 0;
    const n = c.read(c.STDIN_FILENO, &byte, 1);
    return if (n == 1) byte else null;
}

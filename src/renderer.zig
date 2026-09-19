const std = @import("std");
const tui = @import("tui");

/// Zig 0.16-compatible immediate renderer for TUI.zig Screen.
///
/// tui.zig 0.0.2's bundled renderers still reference pre-final Zig 0.16
/// ArrayList/style helper APIs. top.zig keeps using TUI.zig's terminal,
/// screen, cells, styles, colors and input/event parser, while this thin
/// adapter emits the final Screen to stdout using the final Zig 0.16 I/O API.
pub const Renderer = struct {
    stdout: std.Io.File,
    io: std.Io,
    current_style: tui.Style = .{},

    pub fn init() Renderer {
        return .{
            .stdout = std.Io.File.stdout(),
            .io = std.Io.Threaded.global_single_threaded.io(),
        };
    }

    pub fn render(self: *Renderer, screen: *const tui.screen.Screen) !void {
        try self.writeAll("\x1b[?25l");
        try self.writeAll("\x1b[H");

        self.current_style = .{};

        for (0..screen.height) |y| {
            if (y > 0) try self.writeAll("\r\n");

            for (0..screen.width) |x| {
                const cell = screen.getCell(@intCast(x), @intCast(y)) orelse continue;
                if (cell.width == 0) continue;

                if (!cell.style.eql(self.current_style)) {
                    try self.writeStyle(cell.style);
                    self.current_style = cell.style;
                }

                switch (cell.content) {
                    .codepoint => |cp| {
                        var bytes: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(cp, &bytes) catch 0;
                        if (len > 0) try self.writeAll(bytes[0..len]);
                    },
                    .grapheme => |g| try self.writeAll(g),
                }
            }
        }

        try self.writeAll("\x1b[0m\x1b[?25l");
    }

    fn writeStyle(self: *Renderer, style: tui.Style) !void {
        try self.writeAll("\x1b[0m");
        try self.writeColor(style.fg, false);
        try self.writeColor(style.bg, true);

        if (style.attrs.bold) try self.writeAll("\x1b[1m");
        if (style.attrs.dim) try self.writeAll("\x1b[2m");
        if (style.attrs.italic) try self.writeAll("\x1b[3m");
        if (style.attrs.underline) try self.writeAll("\x1b[4m");
        if (style.attrs.blink) try self.writeAll("\x1b[5m");
        if (style.attrs.reverse) try self.writeAll("\x1b[7m");
        if (style.attrs.hidden) try self.writeAll("\x1b[8m");
        if (style.attrs.strikethrough) try self.writeAll("\x1b[9m");
        if (style.attrs.double_underline) try self.writeAll("\x1b[21m");
        if (style.attrs.curly_underline) try self.writeAll("\x1b[4:3m");
        if (style.attrs.dotted_underline) try self.writeAll("\x1b[4:4m");
        if (style.attrs.dashed_underline) try self.writeAll("\x1b[4:5m");
        if (style.attrs.overline) try self.writeAll("\x1b[53m");
    }

    fn writeColor(self: *Renderer, color: tui.Color, background: bool) !void {
        var buf: [48]u8 = undefined;
        const out = switch (color) {
            .default => if (background) "\x1b[49m" else "\x1b[39m",
            .basic => |basic| blk: {
                const n: u8 = @intFromEnum(basic);
                const code: u8 = if (background)
                    (if (n >= 8) 100 + n - 8 else 40 + n)
                else
                    (if (n >= 8) 90 + n - 8 else 30 + n);
                break :blk std.fmt.bufPrint(&buf, "\x1b[{d}m", .{code}) catch "";
            },
            .palette => |index| if (background)
                (std.fmt.bufPrint(&buf, "\x1b[48;5;{d}m", .{index}) catch "")
            else
                (std.fmt.bufPrint(&buf, "\x1b[38;5;{d}m", .{index}) catch ""),
            .rgb => |rgb| if (background)
                (std.fmt.bufPrint(&buf, "\x1b[48;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }) catch "")
            else
                (std.fmt.bufPrint(&buf, "\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }) catch ""),
        };
        try self.writeAll(out);
    }

    fn writeAll(self: *Renderer, bytes: []const u8) !void {
        try self.stdout.writeStreamingAll(self.io, bytes);
    }
};

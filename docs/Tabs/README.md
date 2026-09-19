# top.zig — Tab Architecture

This directory defines the UI contract for every top-level tab in `top.zig`.

Each tab has its own `docs/Tabs/<name>/.README.md` describing:

- what the tab shows;
- which Linux data sources feed it;
- which TUI.zig widgets should be used;
- event/keyboard/mouse behavior;
- styling and color semantics;
- layout rules;
- animation behavior;
- responsive/degraded layouts;
- implementation status.

## Tabs

| # | Tab | Purpose |
|---|---|---|
| 1 | [Overview](./overview/.README.md) | Whole-host health at a glance |
| 2 | [CPU](./cpu/.README.md) | CPU usage, cores, load and hot processes |
| 3 | [Memory](./memory/.README.md) | RAM, swap and memory-heavy processes |
| 4 | [Processes](./processes/.README.md) | Interactive process explorer |
| 5 | [Disk](./disk/.README.md) | Capacity, mounts and I/O |
| 6 | [Network](./network/.README.md) | Interfaces, RX/TX and sockets |
| 7 | [Containers](./containers/.README.md) | cgroup/Docker process correlation |
| 8 | [System](./system/.README.md) | Uptime, kernel, sensors and services |

## Navigation contract

The intended navigation model is:

- `Tab` / `Shift+Tab`: next/previous tab.
- `Alt+1..8` or a configurable numeric chord: direct tab selection.
- Mouse click on the tab header when mouse support is enabled.
- `q` / Ctrl+C: quit.
- Each tab owns only its local shortcuts; global navigation remains consistent.

The current v0.1 implementation renders directly through TUI.zig's `Screen` and `Renderer`. These documents define the target widget composition as the application evolves.

## TUI.zig references

- Widgets: https://muhammad-fiaz.github.io/tui.zig/guide/widgets
- Events: https://muhammad-fiaz.github.io/tui.zig/guide/events
- Styling: https://muhammad-fiaz.github.io/tui.zig/guide/styling
- Layout: https://muhammad-fiaz.github.io/tui.zig/guide/layout
- Animation: https://muhammad-fiaz.github.io/tui.zig/guide/animation

TUI.zig provides Tabs/Navbar navigation, Table/List/Tree display widgets, Card, ProgressBar, SplitView, ScrollView, Statusbar and custom widgets. Its event model includes keyboard, mouse and resize events; its styling system supports 24-bit RGB; and its animation layer supports interpolated values, easing and timers.

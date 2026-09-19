# top.zig

A modern Linux system monitor written in **Zig 0.16** with a rich TUI powered by [tui.zig](https://github.com/muhammad-fiaz/tui.zig).

The goal is not to reproduce `top` pixel-for-pixel, but to keep its low-level observability while making the default experience closer to a lightweight `btop`: true-color gradients, smooth metric transitions, history graphs, responsive panels and a process table that stays readable on a remote VPS.

## v0.1

- Linux metrics read directly from `/proc`.
- CPU usage sampled from `/proc/stat`.
- Memory usage from `/proc/meminfo`.
- Load averages from `/proc/loadavg`.
- Uptime from `/proc/uptime`.
- Process discovery from `/proc/<pid>/stat`, `status` and `cmdline`.
- Current per-process CPU sampling.
- Process RSS memory.
- Sort by CPU, memory or PID.
- Animated CPU and memory gauges.
- CPU history sparkline.
- 24-bit RGB gradients.
- Hot-process pulse animation.
- Animated activity indicator.
- Responsive terminal layout.
- tui.zig screen buffer + diff renderer.
- ~30 FPS visual rendering with lower-frequency metric collection.

## Controls

| Key | Action |
| --- | --- |
| `q` / Ctrl+C | Quit |
| `c` | Sort processes by CPU |
| `m` | Sort processes by memory |
| `p` | Sort processes by PID |
| `r` | Force metric refresh |

## Requirements

- Zig **0.16.0+**
- Linux
- libc
- A true-color terminal is recommended

## Build

```bash
git clone https://github.com/suissa/top.zig
cd top.zig

# Resolve tui.zig and persist its Zig package hash locally.
zig fetch --save "git+https://github.com/muhammad-fiaz/tui.zig.git"

zig build -Doptimize=ReleaseFast
./zig-out/bin/top.zig
```

Development:

```bash
zig build run
zig build test
zig fmt build.zig src
```

## Architecture

```text
/proc/stat ───────────────┐
/proc/meminfo ────────────┤
/proc/loadavg ────────────┤
/proc/uptime ─────────────┤
/proc/<pid>/stat ─────────┼─> collector.zig
/proc/<pid>/status ───────┤       │
/proc/<pid>/cmdline ──────┘       ▼
                              Snapshot
                                 │
                    ┌────────────┴────────────┐
                    ▼                         ▼
                 History                  process list
                    │                         │
                    └────────────┬────────────┘
                                 ▼
                              ui.zig
                                 │
                                 ▼
                       tui.zig Screen/Renderer
                                 │
                                 ▼
                              terminal
```

The collector deliberately stays Linux-first and dependency-light. tui.zig is responsible for terminal lifecycle, true-color cells, screen buffering and diff-based rendering.

## Visual model

The UI uses a dark base with cyan → violet and green → cyan gradients. Metric values are not snapped directly to their new value: the displayed gauges converge toward the sampled value, producing smooth visual transitions while the actual collector remains low frequency.

The renderer is intentionally faster than the collector:

```text
metrics: ~1 Hz
process CPU sampling window: 120 ms
render: ~30 FPS
```

This keeps animation fluid without polling `/proc` 30 times per second.

## UI / Tab specification

The target dashboard is documented tab-by-tab under [`docs/Tabs/`](docs/Tabs/README.md). Each tab document defines its metrics, Linux data sources, TUI.zig widgets, events, styling, layout, animation behavior, responsive rules and implementation status.

The design is grounded in the official TUI.zig guides for [widgets](https://muhammad-fiaz.github.io/tui.zig/guide/widgets), [events](https://muhammad-fiaz.github.io/tui.zig/guide/events), [styling](https://muhammad-fiaz.github.io/tui.zig/guide/styling), [layout](https://muhammad-fiaz.github.io/tui.zig/guide/layout) and [animation](https://muhammad-fiaz.github.io/tui.zig/guide/animation).

## Roadmap

- Per-core CPU graphs.
- Network RX/TX graphs from `/proc/net/dev`.
- Disk throughput and I/O pressure.
- Swap and PSI metrics.
- Temperature sensors.
- Process filtering/search.
- Process tree mode.
- PID detail drawer.
- SIGTERM/SIGKILL actions with confirmation.
- cgroup v2 correlation.
- Docker/container mapping.
- systemd unit mapping.
- PM2 application mapping.
- Process restart counters.
- Mouse selection and scrolling.
- Configurable refresh interval.
- Theme presets.
- Export snapshots to JSON/NDJSON.
- Optional remote-agent mode.

## Why tui.zig

[tui.zig](https://github.com/muhammad-fiaz/tui.zig) already targets Zig 0.16+ and provides 24-bit RGB color, double buffering, diff-based updates, Unicode rendering, widgets, themes and animation primitives. top.zig uses the lower-level screen/renderer APIs so system metrics and animation cadence remain under direct control.

## License

MIT

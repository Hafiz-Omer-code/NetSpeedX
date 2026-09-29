# NetSpeedX

[![Magisk](https://img.shields.io/badge/Magisk-v24%2B-00AA00?logo=magisk&logoColor=white)](https://github.com/topjohnwu/Magisk)
[![KernelSU](https://img.shields.io/badge/KernelSU-supported-1E88E5)](https://github.com/tiann/KernelSU)
[![APatch](https://img.shields.io/badge/APatch-supported-6A5ACD)](https://github.com/bmax121/APatch)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**A universal root module that keeps Android's TCP/IP stack tuned for the app in front of you** — eliminating the bufferbloat that causes video streams to stall or downshift quality when you push playback speed (e.g. 3x) over a Wi-Fi link that has plenty of raw bandwidth but too much queuing delay.

## Overview & Problem Statement

Stock Android network buffers are sized for "works everywhere," not for sustained high-throughput bursts. Watching video at 3x speed on a fast 20 Mbps Wi-Fi connection can still buffer, because:

- Default TCP receive windows are too small to keep a 3x-speed prefetch pipeline full, so the player idles waiting on the network.
- Oversized, un-tuned buffers cause the opposite problem — bufferbloat — where packets queue up and add latency instead of throughput.
- The kernel's congestion-control algorithm and socket buffer sizes are rarely revisited after boot, regardless of what you're actually doing on the device.

NetSpeedX watches the foreground app and network conditions, and re-tunes the kernel's TCP/UDP knobs to match — without needing a full custom kernel.

## Key Features

- **Autonomous mode switching** — Streaming, Downloading, and Browsing/Screen-Off profiles are applied automatically based on what's in the foreground and how the active network interface is actually being used.
- **Adaptive congestion control** — auto-selects the best available algorithm (`bbr` → `cubic` → `westwood`), or defers entirely to a user override / a kernel-tuning app like MTweaks via `TCP_CONG=<algo>` / `TCP_CONG=keep` in the config file.
- **SoC-tailored buffer baselines** — socket buffer ceilings are sized per vendor (Qualcomm Snapdragon, Samsung Exynos, MediaTek) rather than one generic value for every chipset.
- **Lightweight foreground tracking** — reads `/dev/cpuset/foreground` and `/dev/cpuset/top-app` directly instead of polling `dumpsys`, so the daemon doesn't hold the CPU awake just to see which app is on screen.
- **Bufferbloat-aware streaming profile** — capped receive buffers plus faster loss recovery (`tcp_early_retrans`, `tcp_recovery`, `tcp_autocorking=0`) so 3x playback stays smooth without introducing the latency spikes that oversized buffers cause.
- **Self-restoring** — snapshots the kernel's pristine values on first boot and puts them back on uninstall.

## Installation

1. Download the latest `NetSpeedX-vX.Y.Z.zip` from [Releases](../../releases).
2. Flash it from your root manager's **Modules** tab:
   - **Magisk**: Modules → Install from storage → select the zip → reboot.
   - **KernelSU**: Superuser app → Modules → Install → select the zip → reboot.
   - **APatch**: APatch app → Modules → Install → select the zip → reboot.
3. Reboot. The daemon starts automatically once `sys.boot_completed=1`.

## Usage & Verification

Check which congestion-control algorithm is active:

```sh
cat /proc/sys/net/ipv4/tcp_congestion_control

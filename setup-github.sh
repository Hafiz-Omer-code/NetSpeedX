#!/usr/bin/env bash
# setup-github.sh
# Scaffolds README.md, LICENSE, .gitignore and build.sh for the NetSpeedX
# repository, then (optionally) initializes git and publishes it to GitHub.
#
# Run this from the root of the NetSpeedX module source tree — the same
# directory that already contains module.prop, service.sh, daemon.sh,
# lib.sh, customize.sh, uninstall.sh, system.prop and META-INF/.
#
# Usage:
#   ./setup-github.sh              # writes files, then runs the git/gh steps
#   ./setup-github.sh --files-only # writes files, skips git init/commit/push
set -euo pipefail

FILES_ONLY=0
[ "${1:-}" = "--files-only" ] && FILES_ONLY=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "==> Writing repository files in $ROOT"

# ---------------------------------------------------------------------------
# 1. README.md
# ---------------------------------------------------------------------------
cat << 'EOF' > README.md
# NetSpeedX

[![Magisk](https://img.shields.io/badge/Magisk-v24%2B-00AA00?logo=magisk&logoColor=white)](https://github.com/topjohnwu/Magisk)
[![KernelSU](https://img.shields.io/badge/KernelSU-supported-1E88E5)](https://github.com/tiann/KernelSU)
[![APatch](https://img.shields.io/badge/APatch-supported-6A5ACD)](https://github.com/bmax121/APatch)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-v1.1.1-blue)](https://github.com/)

**A universal root module that keeps Android's TCP/IP stack tuned for the app
in front of you** — eliminating the bufferbloat that causes video streams to
stall or downshift quality when you push playback speed (e.g. 3x) over a
Wi-Fi link that has plenty of raw bandwidth but too much queuing delay.

## Overview & Problem Statement

Stock Android network buffers are sized for "works everywhere," not for
sustained high-throughput bursts. Watching video at 3x speed on a fast
20 Mbps Wi-Fi connection can still buffer, because:

- Default TCP receive windows are too small to keep a 3x-speed prefetch
  pipeline full, so the player idles waiting on the network.
- Oversized, un-tuned buffers cause the opposite problem — bufferbloat —
  where packets queue up and add latency instead of throughput.
- The kernel's congestion-control algorithm and socket buffer sizes are
  rarely revisited after boot, regardless of what you're actually doing on
  the device.

NetSpeedX watches the foreground app and network conditions, and re-tunes
the kernel's TCP/UDP knobs to match — without needing a full custom kernel.

## Key Features

- **Autonomous mode switching** — Streaming, Downloading, and
  Browsing/Screen-Off profiles are applied automatically based on what's in
  the foreground and how the active network interface is actually being
  used.
- **Adaptive congestion control** — auto-selects the best available
  algorithm (`bbr` → `cubic` → `westwood`), or defers entirely to a
  user override / a kernel-tuning app like MTweaks via
  `TCP_CONG=<algo>` / `TCP_CONG=keep` in the config file.
- **SoC-tailored buffer baselines** — socket buffer ceilings are sized per
  vendor (Qualcomm Snapdragon, Samsung Exynos, MediaTek) rather than one
  generic value for every chipset.
- **Lightweight foreground tracking** — reads `/dev/cpuset/foreground` and
  `/dev/cpuset/top-app` directly instead of polling `dumpsys`, so the
  daemon doesn't hold the CPU awake just to see which app is on screen.
- **Bufferbloat-aware streaming profile** — capped receive buffers plus
  faster loss recovery (`tcp_early_retrans`, `tcp_recovery`,
  `tcp_autocorking=0`) so 3x playback stays smooth without introducing the
  latency spikes that oversized buffers cause.
- **Self-restoring** — snapshots the kernel's pristine values on first boot
  and puts them back on uninstall.

## Installation

1. Download the latest `NetSpeedX-vX.Y.Z.zip` from
   [Releases](../../releases).
2. Flash it from your root manager's **Modules** tab:
   - **Magisk**: Modules → Install from storage → select the zip → reboot.
   - **KernelSU**: Superuser app → Modules → Install → select the zip →
     reboot.
   - **APatch**: APatch app → Modules → Install → select the zip → reboot.
3. Reboot. The daemon starts automatically once `sys.boot_completed=1`.

## Usage & Verification

Check which congestion-control algorithm is active:

```sh
cat /proc/sys/net/ipv4/tcp_congestion_control
```

Watch the module's own log (mode switches, SoC detection, congestion
control decisions):

```sh
tail -f /data/adb/netspeedx/netspeedx.log
```

Check the current mode NetSpeedX believes it's in:

```sh
cat /data/adb/netspeedx/state
```

## Configuration

Edit `/data/adb/netspeedx/config` (created on first install) and reboot, or
restart the daemon, to apply changes:

```sh
# Polling interval for the adaptive engine, in seconds
INTERVAL=15

# Sustained bytes/sec on the active interface that counts as "downloading"
DL_THRESHOLD=1200000
DL_ENTER=2
DL_EXIT=2

# DNS fallback, used only when Private DNS is unset
DNS1=1.1.1.1
DNS2=8.8.8.8

# TCP congestion control:
#   (blank)        = auto-select on boot: bbr > cubic > westwood
#   TCP_CONG=keep   = leave tcp_congestion_control untouched
#                     (let MTweaks / kernel defaults govern it)
#   TCP_CONG=cubic  = force a specific algorithm (only if the kernel
#                     reports it as available)
TCP_CONG=
```

Add extra apps that should trigger Streaming mode in
`/data/adb/netspeedx/streaming_apps.txt` (one package name per line, shell
globs allowed):

```
# example: com.brave.browser
com.mycustom.videoapp
```

## Uninstall

Remove the module from your root manager's Modules tab and reboot.
`uninstall.sh` restores every kernel value NetSpeedX changed back to what it
was before the module was ever installed.

## License

[MIT](LICENSE)
EOF

# ---------------------------------------------------------------------------
# 2. LICENSE (MIT)
# ---------------------------------------------------------------------------
YEAR="$(date +%Y)"
cat << EOF > LICENSE
MIT License

Copyright (c) ${YEAR} Hafiz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

# ---------------------------------------------------------------------------
# 3. .gitignore
# ---------------------------------------------------------------------------
cat << 'EOF' > .gitignore
# Packaged module builds
*.zip

# Runtime / device logs, never source
*.log

# OS cruft
.DS_Store
Thumbs.db

# Build output
build/
EOF

# ---------------------------------------------------------------------------
# 4. build.sh — packages the flashable zip
# ---------------------------------------------------------------------------
cat << 'EOF' > build.sh
#!/usr/bin/env bash
# build.sh — packages NetSpeedX into a flashable zip.
#
# Verifies:
#   - module.prop sits at the archive root (Magisk/KernelSU/APatch all
#     refuse a module.prop nested inside a subfolder)
#   - every shell script uses LF line endings only (a CRLF script fails
#     silently or aborts install on some recovery/root implementations)
# before packaging NetSpeedX-<VERSION>.zip.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [ ! -f module.prop ]; then
  echo "ERROR: module.prop not found at the repository root." >&2
  exit 1
fi
VERSION="$(sed -n 's/^version=//p' module.prop)"
[ -z "$VERSION" ] && { echo "ERROR: could not read 'version=' from module.prop" >&2; exit 1; }
OUT="NetSpeedX-${VERSION}.zip"

echo "==> Verifying module.prop is at the archive root (not nested)"
nested=$(find . -mindepth 2 -name module.prop -not -path './.git/*' || true)
if [ -n "$nested" ]; then
  echo "ERROR: found a nested module.prop, which breaks root-manager install:" >&2
  echo "$nested" >&2
  exit 1
fi

echo "==> Verifying LF-only line endings on all shell scripts"
bad=0
while IFS= read -r -d '' f; do
  if LC_ALL=C grep -qU $'\r' "$f"; then
    echo "ERROR: CRLF line endings in $f" >&2
    bad=1
  fi
done < <(find . -name '*.sh' -not -path './.git/*' -print0)
if [ "$bad" -eq 1 ]; then
  echo "Fix with: sed -i 's/\r$//' <file>" >&2
  exit 1
fi

echo "==> Packaging $OUT"
rm -f "$OUT"
zip -r9 "$OUT" . \
  -x '.git/*' \
  -x '.github/*' \
  -x 'README.md' \
  -x 'LICENSE' \
  -x '.gitignore' \
  -x 'build.sh' \
  -x 'setup-github.sh' \
  -x '*.zip' \
  -x '*.log' \
  -x '.DS_Store'

echo "==> Verifying module.prop landed at the zip root"
if ! unzip -l "$OUT" | awk '{print $NF}' | grep -qx 'module.prop'; then
  echo "ERROR: module.prop is not at the root of $OUT" >&2
  exit 1
fi

echo "==> Built $OUT"
unzip -l "$OUT"
EOF
chmod +x build.sh

echo "==> Repository files written: README.md, LICENSE, .gitignore, build.sh"

if [ "$FILES_ONLY" -eq 1 ]; then
  echo "==> --files-only set: skipping git init/commit/publish."
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Git init, commit, and publish to GitHub via gh CLI
# ---------------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is not installed; install it and re-run, or use --files-only." >&2
  exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI (gh) is not installed; install it (https://cli.github.com)" >&2
  echo "       and run 'gh auth login' first, or use --files-only and publish manually." >&2
  exit 1
fi

echo "==> Initializing git repository"
if [ ! -d .git ]; then
  git init
fi
git checkout -B main
git add -A
git commit -m "NetSpeedX: initial repository" || echo "==> Nothing to commit (already up to date)"

echo "==> Creating and pushing public GitHub repository: NetSpeedX"
gh repo create NetSpeedX --public --source=. --push

echo "==> Done. Repository published."

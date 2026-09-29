#!/system/bin/sh
# NetSpeedX shared helpers (sourced, never executed directly)
export PATH=/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:$PATH
DATA=${NSX_DATA:-/data/adb/netspeedx}
LOG=$DATA/netspeedx.log
ORIG=$DATA/original.sysctl
PROFILE=$DATA/vendor.profile
N=/proc/sys/net
NETDEV=${NETDEV:-/proc/net/dev}
LOG_MAX_LINES=500

# defaults (overridable in $DATA/config)
INTERVAL=15
DL_THRESHOLD=1200000   # bytes/s (~1.2 MB/s) on the active interface => Download mode
DL_ENTER=2             # consecutive samples above threshold to enter
DL_EXIT=2              # consecutive samples below threshold to leave
DNS1=1.1.1.1
DNS2=8.8.8.8           # e.g. 9.9.9.9 for Quad9
TCP_CONG=              # empty = auto-select (bbr > cubic > westwood)
                        # "keep"/"none" = don't touch tcp_congestion_control at all
                        # any other value = use it verbatim if the kernel supports it
[ -f "$DATA/config" ] && . "$DATA/config"

BB=
for b in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
  [ -x "$b" ] && BB=$b && break
done
bb() { if [ -n "$BB" ]; then "$BB" "$@"; else "$@"; fi; }

# append a line; when the file passes LOG_MAX_LINES keep only the newest half
log() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
  set -- $(wc -l < "$LOG" 2>/dev/null)
  if [ "${1:-0}" -gt "$LOG_MAX_LINES" ]; then
    tail -n $((LOG_MAX_LINES / 2)) "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  fi
}

# write to /proc/sys/net path; silently skip when the knob doesn't exist on this
# kernel. The explicit `|| true` guarantees this never aborts the caller even
# under `set -e`, regardless of whether the target file rejects the value.
ns() { [ -w "$N/$1" ] && { echo "$2" > "$N/$1" 2>/dev/null || true; }; }

orig() {
  [ -f "$ORIG" ] || return 0
  while IFS='|' read -r k v; do
    [ "$k" = "$1" ] && { echo "$v"; return 0; }
  done < "$ORIG"
}
restore_orig() { v=$(orig "$1"); [ -n "$v" ] && ns "$1" "$v"; }
load_profile() { [ -f "$PROFILE" ] && . "$PROFILE"; }

# ---------- network helpers ----------
get_iface() {
  out=$(ip route get 1.1.1.1 2>/dev/null | head -n 1)
  set -- $out
  while [ $# -gt 0 ]; do
    [ "$1" = dev ] && { echo "$2"; return 0; }
    shift
  done
  [ "$(cat /sys/class/net/wlan0/operstate 2>/dev/null)" = up ] && echo wlan0
}

# rx bytes for interface $1 straight from /proc/net/dev (no forks)
net_rx() {
  while read -r name rest; do
    case "$name" in
      "$1:") set -- $rest; echo "$1"; return 0 ;;
      "$1":*) echo "${name#*:}"; return 0 ;;
    esac
  done < "$NETDEV"
}

# ---------- Wi-Fi power ----------
probe_wifi() {
  WIFI_SPM=0
  cmd wifi help 2>&1 | grep -q 'set-power-mode' && WIFI_SPM=1
}

wifi_ps_off() {
  case "$1" in wlan*) ;; *) return 0 ;; esac
  [ -z "$WIFI_SPM" ] && probe_wifi
  command -v iw >/dev/null 2>&1 && iw dev "$1" set power_save off >/dev/null 2>&1
  if [ "$WIFI_SPM" = 1 ]; then
    cmd wifi set-power-mode 1 >/dev/null 2>&1
  else
    cmd wifi force-hi-perf-mode enabled >/dev/null 2>&1
    cmd wifi force-low-latency-mode enabled >/dev/null 2>&1
  fi
  echo "$1" > "$DATA/ps_off"
}

wifi_ps_restore() {
  [ -f "$DATA/ps_off" ] || return 0
  i=$(cat "$DATA/ps_off")
  [ -z "$WIFI_SPM" ] && probe_wifi
  command -v iw >/dev/null 2>&1 && iw dev "$i" set power_save on >/dev/null 2>&1
  if [ "$WIFI_SPM" = 1 ]; then
    cmd wifi set-power-mode 0 >/dev/null 2>&1
  else
    cmd wifi force-hi-perf-mode disabled >/dev/null 2>&1
    cmd wifi force-low-latency-mode disabled >/dev/null 2>&1
  fi
  rm -f "$DATA/ps_off"
}

# ---------- profiles (deterministic; only invoked on change) ----------
RESTORE_KEYS="core/rmem_default ipv4/tcp_slow_start_after_idle ipv4/tcp_mtu_probing ipv4/tcp_fastopen \
core/netdev_max_backlog ipv4/tcp_window_scaling ipv4/tcp_sack ipv4/tcp_fack \
ipv4/tcp_early_retrans ipv4/tcp_recovery ipv4/tcp_autocorking"

mode_common_reset() {
  ns core/rmem_max "$RMEM_MAX"
  ns core/wmem_max "$WMEM_MAX"
  ns ipv4/tcp_rmem "$RMEM_BASE"
  ns ipv4/tcp_wmem "$WMEM_BASE"
  for k in $RESTORE_KEYS; do restore_orig "$k"; done
}

mode_default() { mode_common_reset; }

mode_streaming() {
  mode_common_reset
  ns core/rmem_default 262144            # UDP/QUIC (HTTP/3)
  ns core/rmem_max 4194304
  ns ipv4/tcp_rmem "4096 87380 4194304"
  ns ipv4/tcp_window_scaling 1
  ns ipv4/tcp_sack 1
  ns ipv4/tcp_fack 1
  ns ipv4/tcp_slow_start_after_idle 0
  ns ipv4/tcp_early_retrans 3
  ns ipv4/tcp_recovery 1
  ns ipv4/tcp_autocorking 0
}

mode_download() {
  mode_common_reset
  ns ipv4/tcp_window_scaling 1
  ns ipv4/tcp_mtu_probing 1
  ns ipv4/tcp_fastopen 3
  ns core/netdev_max_backlog 10000
}

# tcp_rmem the active profile should have (used for cheap drift detection)
expected_rmem() {
  case "$1" in
    streaming) echo "4096 87380 4194304" ;;
    *) echo "$RMEM_BASE" ;;
  esac
}

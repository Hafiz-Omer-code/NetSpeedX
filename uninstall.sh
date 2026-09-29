#!/system/bin/sh
DATA=/data/adb/netspeedx
[ -f "$DATA/daemon.pid" ] && kill "$(cat "$DATA/daemon.pid")" 2>/dev/null
if [ -f "$DATA/ps_off" ]; then
  i=$(cat "$DATA/ps_off")
  command -v iw >/dev/null 2>&1 && iw dev "$i" set power_save on >/dev/null 2>&1
  cmd wifi set-power-mode 0 >/dev/null 2>&1
  cmd wifi force-hi-perf-mode disabled >/dev/null 2>&1
  cmd wifi force-low-latency-mode disabled >/dev/null 2>&1
fi
if [ -f "$DATA/original.sysctl" ]; then
  while IFS='|' read -r k v; do
    [ -w "/proc/sys/net/$k" ] && echo "$v" > "/proc/sys/net/$k" 2>/dev/null
  done < "$DATA/original.sysctl"
fi
rm -rf "$DATA"

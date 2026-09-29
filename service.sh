#!/system/bin/sh
# NetSpeedX - boot-time probing and baseline tuning
MODDIR=${0%/*}
. "$MODDIR/lib.sh"

mkdir -p "$DATA"
# Hard gate: nothing below this line (including the daemon launch at the
# bottom of this file) runs until the boot sequence has actually completed.
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 5; done
sleep 15   # let netd / ConnectivityService finish their own buffer setup

# --- snapshot pristine kernel values once per boot (Mode 3 + uninstall) ---
BOOTID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
if [ "$BOOTID" != "$(cat "$DATA/boot_id" 2>/dev/null)" ]; then
  : > "$ORIG"
  for k in ipv4/tcp_rmem ipv4/tcp_wmem core/rmem_max core/wmem_max core/rmem_default \
           core/netdev_max_backlog ipv4/tcp_slow_start_after_idle ipv4/tcp_mtu_probing \
           ipv4/tcp_fastopen ipv4/tcp_no_metrics_save ipv4/tcp_moderate_rcvbuf \
           ipv4/tcp_congestion_control ipv4/tcp_window_scaling ipv4/tcp_sack ipv4/tcp_fack \
           ipv4/tcp_early_retrans ipv4/tcp_recovery ipv4/tcp_autocorking; do
    [ -r "$N/$k" ] && echo "$k|$(cat "$N/$k")" >> "$ORIG"
  done
  echo "$BOOTID" > "$DATA/boot_id"
  rm -f "$DATA/ps_off"
fi

# --- congestion control ---
# TCP_CONG in $DATA/config (already sourced by lib.sh) lets the user override
# or fully opt out of auto-selection, so a manual choice (e.g. via MTweaks) or
# a hand-set sysctl is never clobbered on boot.
avail=$(cat "$N/ipv4/tcp_available_congestion_control" 2>/dev/null)
case "$TCP_CONG" in
  keep|none)
    log "CC: TCP_CONG=$TCP_CONG, leaving tcp_congestion_control untouched (current=$(cat "$N/ipv4/tcp_congestion_control" 2>/dev/null))"
    ;;
  "")
    pick=
    for a in bbr cubic westwood; do
      case " $avail " in *" $a "*) pick=$a; break ;; esac
    done
    if [ -n "$pick" ]; then
      ns ipv4/tcp_congestion_control "$pick"
      log "CC: available=[$avail] auto-selected=$pick active=$(cat "$N/ipv4/tcp_congestion_control")"
    else
      log "CC: none of bbr/cubic/westwood available ([$avail]); unchanged"
    fi
    ;;
  *)
    case " $avail " in
      *" $TCP_CONG "*)
        ns ipv4/tcp_congestion_control "$TCP_CONG"
        log "CC: user override TCP_CONG=$TCP_CONG applied, active=$(cat "$N/ipv4/tcp_congestion_control")"
        ;;
      *)
        log "CC: user override TCP_CONG=$TCP_CONG not in available=[$avail]; ignoring override, leaving unchanged"
        ;;
    esac
    ;;
esac

# --- SoC vendor detection ---
ID=$(printf '%s %s %s %s' "$(getprop ro.soc.manufacturer)" "$(getprop ro.hardware)" \
     "$(getprop ro.board.platform)" "$(getprop ro.product.board)" | tr 'A-Z' 'a-z')
case "$ID" in
  *qualcomm*|*qcom*|*snapdragon*|*msm*|*sdm*|*sm[0-9]*)
    VENDOR=qualcomm; RMEM_MAX=16777216; WMEM_MAX=8388608
    RMEM_BASE="4096 87380 8388608"; WMEM_BASE="4096 16384 8388608" ;;
  *samsung*|*exynos*|*universal[0-9]*|*s5e*)
    VENDOR=exynos; RMEM_MAX=12582912; WMEM_MAX=6291456
    RMEM_BASE="4096 87380 6291456"; WMEM_BASE="4096 16384 6291456" ;;
  *mediatek*|*mtk*|*mt[0-9]*)
    VENDOR=mediatek; RMEM_MAX=12582912; WMEM_MAX=4194304
    RMEM_BASE="4096 87380 6291456"; WMEM_BASE="4096 16384 4194304" ;;
  *)
    VENDOR=generic; RMEM_MAX=8388608; WMEM_MAX=4194304
    RMEM_BASE="4096 87380 4194304"; WMEM_BASE="4096 16384 4194304" ;;
esac
cat > "$PROFILE" <<EOP
VENDOR=$VENDOR
RMEM_MAX=$RMEM_MAX
WMEM_MAX=$WMEM_MAX
RMEM_BASE="$RMEM_BASE"
WMEM_BASE="$WMEM_BASE"
EOP
. "$PROFILE"
log "SoC id=[$ID] vendor=$VENDOR rmem_max=$RMEM_MAX wmem_max=$WMEM_MAX"

# --- general Wi-Fi optimisations ---
ns ipv4/tcp_no_metrics_save 1
ns ipv4/tcp_moderate_rcvbuf 1
mode_default

# DNS fallback only when Private DNS is unset
pdm=$(settings get global private_dns_mode 2>/dev/null)
case "$pdm" in
  ""|null|off)
    RP=$(command -v resetprop || echo setprop)
    for p in net.dns1 net.dns2 net.wlan0.dns1 net.wlan0.dns2; do
      case "$p" in *1) v=$DNS1 ;; *) v=$DNS2 ;; esac
      $RP "$p" "$v" >/dev/null 2>&1
    done
    log "DNS: private DNS unset, props set to $DNS1 / $DNS2" ;;
  *) log "DNS: private_dns_mode=$pdm, left untouched" ;;
esac

chmod 0755 "$MODDIR/daemon.sh"
nohup sh "$MODDIR/daemon.sh" >/dev/null 2>&1 &

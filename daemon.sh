#!/system/bin/sh
# NetSpeedX - lightweight adaptive engine (default poll: 15s)
MODDIR=${0%/*}
. "$MODDIR/lib.sh"
load_profile || exit 1

PIDF=$DATA/daemon.pid
if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then exit 0; fi
echo $$ > "$PIDF"
trap 'wifi_ps_restore; rm -f "$PIDF"; exit 0' TERM INT

# ---- foreground detection: cpuset only, no per-cycle dumpsys wake locks ----
# /dev/cpuset/foreground holds the currently-visible app; /dev/cpuset/top-app
# is checked too since some ROMs classify the topmost app there instead.
FOREGROUND_CGROUPS="/dev/cpuset/foreground/cgroup.procs /dev/cpuset/top-app/cgroup.procs \
/dev/cpuset/foreground/tasks /dev/cpuset/top-app/tasks"

is_streaming() {
  case "$1" in
    com.google.android.youtube|com.google.android.youtube.*|com.google.android.apps.youtube.*) return 0 ;;
    app.revanced.*|com.vanced.android.youtube|org.schabi.newpipe*|org.polymorphicshade.tubular*) return 0 ;;
    com.netflix.*|com.amazon.avod*|com.disney.*|in.startv.hotstar*|com.hbo.*|com.crunchyroll.*) return 0 ;;
    com.lagradost.cloudstream3*|eu.kanade.tachiyomi.animeextension*|xyz.jmir.tachiyomi.mi*|\
    eu.kanade.tachiyomi.animetail*|com.animeplay*|com.twitch.*|tv.twitch.*) return 0 ;;
    org.videolan.vlc|is.xyz.mpv*|com.mxtech.videoplayer*|org.xbmc.kodi) return 0 ;;
  esac
  if [ -f "$DATA/streaming_apps.txt" ]; then
    while read -r p; do
      case "$p" in ""|\#*) continue ;; esac
      case "$1" in $p) return 0 ;; esac
    done < "$DATA/streaming_apps.txt"
  fi
  return 1
}

# returns 0 = streaming app on top, 1 = not streaming, 2 = unknown (no cgroup readable)
fg_streaming() {
  FG=
  seen=0
  for cg in $FOREGROUND_CGROUPS; do
    [ -r "$cg" ] || continue
    while read -r pid; do
      name=
      { read -r name < "/proc/$pid/cmdline"; } 2>/dev/null
      [ -z "$name" ] && continue
      seen=1
      name=${name%%:*}
      if is_streaming "$name"; then FG=$name; return 0; fi
    done < "$cg"
  done
  [ "$seen" = 1 ] && return 1
  # Every cgroup path was unreadable on this ROM (rare). dumpsys is a real
  # wake/CPU cost, so it's only ever used here, never in the normal loop.
  l=$(dumpsys window 2>/dev/null | grep -m1 'mCurrentFocus=Window')
  FG=$(echo "$l" | sed -n 's/.* \([A-Za-z0-9_.]*\)\/[^ ]*.*/\1/p' | head -n 1)
  [ -z "$FG" ] && return 2
  is_streaming "$FG" && return 0
  return 1
}

screen_on() {
  for f in /sys/class/backlight/*/brightness /sys/class/leds/lcd-backlight/brightness; do
    if [ -r "$f" ]; then
      read -r b < "$f"
      [ "${b:-1}" -gt 0 ] 2>/dev/null && return 0
      return 1
    fi
  done
  dumpsys power 2>/dev/null | grep -q 'mWakefulness=Awake'
}

drifted() {
  cur=$(cat "$N/ipv4/tcp_rmem" 2>/dev/null)
  set -- $cur
  [ "$1 $2 $3" != "$(expected_rmem "$MODE")" ]
}

MODE=; LAST_IFACE=; DL=0; HI=0; LO=0; prev_rx=0; prev_t=0
# NetSpeedX never writes tcp_congestion_control from this loop (see lib.sh
# mode_* functions / RESTORE_KEYS): the value service.sh set at boot - whether
# auto-picked or a TCP_CONG override - is left alone for the whole session,
# so a kernel-tweak app changing it later is never fought or reverted here.
log "daemon started pid=$$ vendor=$VENDOR interval=${INTERVAL}s dl>${DL_THRESHOLD}B/s cc=$(cat "$N/ipv4/tcp_congestion_control" 2>/dev/null) (TCP_CONG=${TCP_CONG:-auto})"

while :; do
  IFACE=$(get_iface)
  now=$(date +%s)
  rx=0
  [ -n "$IFACE" ] && rx=$(net_rx "$IFACE")
  rx=${rx:-0}
  rate=0
  if [ "$IFACE" = "$LAST_IFACE" ] && [ "$prev_t" -gt 0 ] && [ "$now" -gt "$prev_t" ]; then
    rate=$(( (rx - prev_rx) / (now - prev_t) ))
    [ "$rate" -lt 0 ] && rate=0
  fi
  prev_rx=$rx; prev_t=$now

  if ! screen_on; then
    want=default; DL=0; HI=0; LO=0; nap=30
  else
    nap=$INTERVAL
    fg_streaming; rc=$?
    if [ "$rc" = 0 ]; then
      want=streaming; DL=0; HI=0; LO=0
    elif [ "$rc" = 2 ] && [ "$MODE" = streaming ]; then
      want=streaming            # transient focus gap
    else
      # download detection is app-agnostic: sustained rx rate on the active interface
      if [ "$rate" -gt "$DL_THRESHOLD" ]; then HI=$((HI+1)); LO=0; else LO=$((LO+1)); HI=0; fi
      if [ "$HI" -ge "$DL_ENTER" ]; then DL=1; elif [ "$LO" -ge "$DL_EXIT" ]; then DL=0; fi
      want=default
      [ "$DL" = 1 ] && want=download
    fi
  fi

  apply=0
  if [ "$want" != "$MODE" ] || [ "$IFACE" != "$LAST_IFACE" ]; then
    log "mode ${MODE:-none} -> $want (app=${FG:-none} iface=${IFACE:-none} rx=${rate}B/s)"
    if [ "$want" = streaming ]; then wifi_ps_off "$IFACE"; else wifi_ps_restore; fi
    echo "$want" > "$DATA/state"
    apply=1
  elif drifted; then
    log "netd overwrote tcp_rmem; re-applying $want"
    apply=1
  fi
  [ "$apply" = 1 ] && "mode_$want"
  MODE=$want; LAST_IFACE=$IFACE

  bb sleep "$nap"
done

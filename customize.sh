#!/system/bin/sh
SKIPUNZIP=0
DATA=/data/adb/netspeedx

ui_print "*******************************"
ui_print "  NetSpeedX v1.1 - adaptive streaming"
ui_print "*******************************"

if [ "$KSU" = true ]; then
  ui_print "- Root: KernelSU ($KSU_VER)"
elif [ "$APATCH" = true ]; then
  ui_print "- Root: APatch ($APATCH_VER)"
else
  ui_print "- Root: Magisk ($MAGISK_VER)"
  [ "${MAGISK_VER_CODE:-0}" -lt 24000 ] && abort "! Magisk v24+ required"
fi
[ "${API:-0}" -lt 26 ] && abort "! Android 8.0+ required"

CC=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)
ui_print "- Kernel congestion control: ${CC:-unknown}"
case " $CC " in *" bbr "*) ;; *) ui_print "- BBR not in kernel; will fall back to westwood/cubic" ;; esac

mkdir -p "$DATA"
# v1.0 configs pin old values (10s / 1.5MB/s); keep a backup and write new defaults
if [ -f "$DATA/config" ] && ! grep -q '^CONFIG_VER=2' "$DATA/config"; then
  mv "$DATA/config" "$DATA/config.v1.bak"
  ui_print "- Old config backed up to config.v1.bak"
fi
if [ ! -f "$DATA/config" ]; then
  cat > "$DATA/config" <<'EOC'
# NetSpeedX user config (sourced by shell)
CONFIG_VER=2
INTERVAL=15
DL_THRESHOLD=1200000
DL_ENTER=2
DL_EXIT=2
DNS1=1.1.1.1
DNS2=8.8.8.8
# TCP congestion control:
#   (blank)      = auto-select on boot: bbr > cubic > westwood
#   TCP_CONG=keep (or "none") = don't touch it; let MTweaks/kernel defaults govern
#   TCP_CONG=cubic (or any algo name) = force it, only if the kernel supports it
TCP_CONG=
EOC
fi
if [ ! -f "$DATA/streaming_apps.txt" ]; then
  cat > "$DATA/streaming_apps.txt" <<'EOA'
# Extra streaming packages/process names, one per line (shell globs allowed)
# example: com.brave.browser
EOA
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
# Explicit, auditable perms for the two scripts the daemon lifecycle depends on
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/daemon.sh" 0 0 0755
for f in uninstall.sh lib.sh customize.sh; do
  [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done
ui_print "- Done. Reboot to activate. Log: $DATA/netspeedx.log"

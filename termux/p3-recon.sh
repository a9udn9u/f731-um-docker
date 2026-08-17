#!/system/bin/sh
# p3-recon.sh v2: host-side recon, NO pgrep/taskset dependency (Termux may lack
# procps). Enumerates /proc directly and reads the app's own affinity/quota.
#
# Run in Termux while the guest is up:
#   sh /sdcard/umd/share/../p3-recon.sh    (i.e. sh /sdcard/umd/p3-recon.sh)
# Writes /sdcard/umd/p3-recon.txt (guest: /host/p3-recon.txt).
set +e
export PATH=/data/data/com.termux/files/usr/bin:$PATH
OUT=/sdcard/umd/p3-recon.txt
exec > "$OUT" 2>&1

# hex CPU mask (e.g. "0000003f") -> "0-5"
mask2cpus() {
  m=$1
  [ -z "$m" ] && { echo "(none)"; return; }
  case $m in *[!0-9a-fA-F]*) echo "(bad:$m)"; return;; esac
  n=$(printf '%d' "0x$m" 2>/dev/null) || { echo "(bad:$m)"; return; }
  out=""; i=0
  while [ $i -lt 32 ]; do
    [ $(( (n >> i) & 1 )) -eq 1 ] && { [ -n "$out" ] && out="$out,"; out="$out$i"; }
    i=$((i+1))
  done
  [ -n "$out" ] || out="(0)"
  echo "$out"
}

echo "=== p3-recon v2 $(date) ==="

echo "== cores =="
echo "nproc=$(nproc 2>/dev/null)"
[ -f /sys/devices/system/cpu/possible ] && echo "possible=$(cat /sys/devices/system/cpu/possible)"

echo "== per-core max/cur freq (kHz) + governor =="
for d in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
  [ -d "$d" ] || continue
  n=$(basename "$(dirname "$d")")
  echo "$n max=$(cat "$d/cpuinfo_max_freq" 2>/dev/null) cur=$(cat "$d/scaling_cur_freq" 2>/dev/null) gov=$(cat "$d/scaling_governor" 2>/dev/null)"
done

echo "== APP cgroup (recon = same app as the stack) =="
scg=$(sed -n 's/^0:://p' /proc/self/cgroup 2>/dev/null | head -1)
echo "self cgroup v2 path=$scg"
echo "self cpus_allowed=$(cat /proc/self/cpus_allowed 2>/dev/null) -> cores $(mask2cpus "$(cat /proc/self/cpus_allowed 2>/dev/null)")"
d="/sys/fs/cgroup${scg:-/}"
while [ -n "$d" ] && [ -d "$d" ] && [ "$d" != "/sys/fs/cgroup" ]; do
  [ -f "$d/cpuset.cpus.effective" ] && echo "  cpuset @ $d = $(cat "$d/cpuset.cpus.effective" 2>/dev/null)"
  [ -f "$d/cpu.max" ] && echo "  cpu.max  @ $d = $(cat "$d/cpu.max" 2>/dev/null)"
  d=$(dirname "$d")
done

echo "== UML host processes (comm match) =="
for sdir in /proc/[0-9]*; do
  p=${sdir#/proc/}
  [ -d "$sdir" ] || continue
  comm=$(cat "$sdir/comm" 2>/dev/null)
  case $comm in
    linux-um|umnet|passt|umd-supervise|stub_exe|stub)
      ppid=$(awk '{print $4}' "$sdir/stat" 2>/dev/null)
      aff=$(cat "$sdir/cpus_allowed" 2>/dev/null)
      echo "$comm pid=$p ppid=$ppid aff=$aff -> $(mask2cpus "$aff")"
      ;;
  esac
done

echo "== linux-um children (the seccomp stub) =="
for sdir in /proc/[0-9]*; do
  p=${sdir#/proc/}
  [ -d "$sdir" ] || continue
  [ "$(cat "$sdir/comm" 2>/dev/null)" = "linux-um" ] || continue
  rootpid=$p
  for cdir in /proc/[0-9]*; do
    c=${cdir#/proc/}
    [ -d "$cdir" ] || continue
    [ "$(awk '{print $4}' "$cdir/stat" 2>/dev/null)" = "$rootpid" ] || continue
    ccomm=$(cat "$cdir/comm" 2>/dev/null)
    caff=$(cat "$cdir/cpus_allowed" 2>/dev/null)
    echo "  child pid=$c comm=$ccom aff=$caff -> $(mask2cpus "$caff")"
  done
done

echo "== done $(date) =="

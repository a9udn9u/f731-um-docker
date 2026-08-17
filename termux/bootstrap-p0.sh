#!/system/bin/sh
# bootstrap-p0.sh: one-time migration to the P0 layout (guest image off FUSE).
#
#   OLD layout:
#     image  : /sdcard/umd/debian-docker.ext4   (FUSE /sdcard - slow)
#     /host  : /sdcard/umd/share
#   NEW layout:
#     image  : $HOME/umd/debian-docker.ext4     (real app-partition fs)
#     /host  : /sdcard/umd
#
# Run in Termux:
#   sh /sdcard/umd/share/bootstrap-p0.sh
#
# It stops the stack, installs the new restart.sh + umd-supervise, copies the
# ~6 GB guest image off FUSE, and restarts. Expect ~30-60 s, then "DONE".
set +e
export PATH=/data/data/com.termux/files/usr/bin:$PATH
umask 022

DZ=/sdcard/umd
SHARE=$DZ/share
LIVE=$HOME/umd

echo "== bootstrap-p0 start $(date) =="

# 1. install the new restart.sh (staged on the phone via the guest /host mount)
cp "$SHARE/restart.sh" "$LIVE/restart.sh" && chmod +x "$LIVE/restart.sh" \
  && echo "restart.sh installed" || { echo "FAIL: install restart.sh"; exit 1; }

# 2. move the staged supervise to where the new restart.sh looks ($DZ top level)
mv "$SHARE/umd-supervise.staged" "$DZ/umd-supervise.staged" \
  && echo "umd-supervise staged" || echo "WARN: umd-supervise.staged not found (continuing)"

# 3. the new restart.sh does the rest: stop stack -> install staged ->
#    sync image off FUSE -> start the new supervise
"$LIVE/restart.sh"

echo "== bootstrap-p0 done $(date) =="

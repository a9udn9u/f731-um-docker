#!/system/bin/sh
# restart.sh: the canonical (re)start, run in Termux.
#
#   1. stops the stack
#   2. installs staged files: /sdcard/umd/<name>.staged -> $HOME/umd/<name>
#      (this is how a dev machine updates phoneside scripts: the guest writes
#      them to /host, which is /sdcard/umd)
#   3. deploys the guest image ONLY on request: /sdcard/umd/debian-docker.ext4
#      is a drop zone. A plain restart NEVER overwrites $HOME/umd (the image
#      holds /var/lib/docker = all docker images+containers). Set UMD_SYNC=1 to
#      install a newer drop-zone image (first-time installs automatically).
#   4. starts umd-supervise detached
set +e
export PATH=/data/data/com.termux/files/usr/bin:$PATH
umask 022
cd "$HOME/umd" || exit 9
pkill -f umd-supervise 2>/dev/null
pkill -f linux-um 2>/dev/null
pkill -f umnet 2>/dev/null
pkill -f passt 2>/dev/null
sleep 2

DZ=/sdcard/umd

# staged files (from the guest via /host, or pushed by hand)
for f in $DZ/*.staged; do
  [ -f "$f" ] || continue
  base=$(basename "$f" .staged)
  cp -f "$f" "$PWD/$base" && chmod +x "$PWD/$base" 2>/dev/null
  rm -f "$f"
  echo "STAGED_INSTALLED $base $(date)" >> $DZ/supervise.log
done

# guest image: drop zone -> live location.
# OPT-IN: a plain restart must NEVER overwrite the live image, because the
# image's /var/lib/docker holds every docker image+container; clobbering it
# silently wipes them. Set UMD_SYNC=1 to deploy a newer drop-zone image.
# (First-time, when there is no live image yet, it installs automatically.)
LIVE=$PWD/debian-docker.ext4
if [ -f "$DZ/debian-docker.ext4" ]; then
  if [ ! -f "$LIVE" ]; then
    echo "IMAGE_SYNC (no live image) $(date)" >> $DZ/supervise.log
    cat "$DZ/debian-docker.ext4" > "$LIVE"
    echo "IMAGE_SYNCED $(date)" >> $DZ/supervise.log
  elif [ "${UMD_SYNC:-0}" = "1" ] && [ "$DZ/debian-docker.ext4" -nt "$LIVE" ]; then
    echo "IMAGE_SYNC (UMD_SYNC=1, newer drop-zone) $(date)" >> $DZ/supervise.log
    cat "$DZ/debian-docker.ext4" > "$LIVE"
    echo "IMAGE_SYNCED $(date)" >> $DZ/supervise.log
  else
    echo "IMAGE_SYNC_SKIP (kept live image; UMD_SYNC=1 to overwrite) $(date)" >> $DZ/supervise.log
  fi
fi

chmod +x ./umnet ./linux-um ./stub_exe ./passt ./passt-bin ./umd-supervise 2>/dev/null
ln -sf $DZ/umd.out $PWD/umd.out
echo "RESTART_MARK $(date)" >> $DZ/supervise.log
nohup ./umd-supervise > /dev/null 2>&1 &
echo "SUPERVISE_PID $!" >> $DZ/supervise.log
echo DONE >> $DZ/supervise.log

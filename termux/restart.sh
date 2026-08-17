#!/system/bin/sh
# restart.sh: the canonical (re)start, run in Termux.
#
#   1. stops the stack
#   2. installs staged files: /sdcard/umd/<name>.staged -> $HOME/umd/<name>
#      (this is how a dev machine updates phoneside scripts: the guest writes
#      them to /host, which is /sdcard/umd)
#   3. syncs the guest image: /sdcard/umd/debian-docker.ext4 is a drop zone;
#      a newer (or only) copy is moved to $HOME/umd, where the stack actually
#      reads it (real app-partition fs, not FUSE /sdcard)
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

# guest image: drop zone -> live location (only when newer or missing)
LIVE=$PWD/debian-docker.ext4
if [ -f "$DZ/debian-docker.ext4" ]; then
  if [ ! -f "$LIVE" ] || [ "$DZ/debian-docker.ext4" -nt "$LIVE" ]; then
    echo "IMAGE_SYNC $(date)" >> $DZ/supervise.log
    cat "$DZ/debian-docker.ext4" > "$LIVE"
    echo "IMAGE_SYNCED $(date)" >> $DZ/supervise.log
  fi
fi

chmod +x ./umnet ./linux-um ./stub_exe ./passt ./passt-bin ./umd-supervise 2>/dev/null
ln -sf $DZ/umd.out $PWD/umd.out
echo "RESTART_MARK $(date)" >> $DZ/supervise.log
nohup ./umd-supervise > /dev/null 2>&1 &
echo "SUPERVISE_PID $!" >> $DZ/supervise.log
echo DONE >> $DZ/supervise.log

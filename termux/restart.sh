#!/system/bin/sh
set +e
export PATH=/data/data/com.termux/files/usr/bin:$PATH
umask 022
cd "$HOME/umd" || exit 9
pkill -f umd-supervise 2>/dev/null
pkill -f linux-um 2>/dev/null
pkill -f umnet 2>/dev/null
pkill -f passt 2>/dev/null
sleep 2
cp /sdcard/umd/passt ./passt && chmod +x ./passt
cp /sdcard/umd/umd-supervise ./umd-supervise && chmod +x ./umd-supervise
chmod +x ./umnet ./linux-um ./stub_exe ./umd-probe 2>/dev/null
ln -sf /sdcard/umd/umd.out ./umd.out
echo "RESTART_MARK $(date)" >> /sdcard/umd/supervise.log
nohup ./umd-supervise > /dev/null 2>&1 &
echo "SUPERVISE_PID $!" >> /sdcard/umd/supervise.log
echo DONE >> /sdcard/umd/supervise.log
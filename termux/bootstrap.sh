#!/data/data/com.termux/files/usr/bin/sh
# Termux:Boot entry point: auto-start the UML stack on every boot.
#
# com.termux.boot (Termux:Boot) runs every executable file in
# $HOME/.termux/boot/ at boot. That calls
# restart.sh -> umd-supervise -> umnet + linux-um + passt. Once the guest is
# running, its own init (image/umarm-init, daemon mode) starts *and supervises*
# sshd (published on host:2222 via passt) and dockerd, so after a reboot
# `ssh -p 2222 root@<phone-ip>` and `docker` just work.
#
# Containers persist across a reboot: /var/lib/docker lives inside the
# persisted guest image, so --restart always/unless-stopped containers come
# back running and the rest return as Exited (start them; they are not lost).
#
# Deploy: this file must live at $HOME/.termux/boot/ (NOT $HOME/umd) so that
# Termux:Boot finds it. First-time setup: launch the Termux:Boot app once
# manually (see termux/README.md, "Auto-start after reboot").
export PATH=/data/data/com.termux/files/usr/bin:$PATH
# Let boot (Termux + shared storage, which /sdcard/umd needs) settle first.
sleep 5
/data/data/com.termux/files/home/umd/restart.sh

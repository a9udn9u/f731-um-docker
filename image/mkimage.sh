#!/bin/bash
# Build the guest rootfs image (debian-docker.ext4).
#
# The result is a small Debian bookworm/arm64 ext4 image that the UML kernel
# boots (ubd0=... root=/dev/ubda). Its /umarm-init either:
#   * one-shot: runs the command found in $SHARE/guest-cmd, prints
#     UMARM_OUTPUT_BEGIN / UMARM_EXIT=<rc>, and powers off; or
#   * daemon: keeps dockerd and sshd alive forever (the default we run).
# See umarm-init and README.md in this directory.
set -euo pipefail

DIR=$(mktemp -d /tmp/f731-image.XXXXXX)
IMG=${IMG:-debian-docker.ext4}
SIZE_MB=${SIZE_MB:-6144}
MIRROR=${MIRROR:-http://deb.debian.org/debian}

echo "[1/4] debootstrap"
debootstrap --arch=arm64 --foreign \
    --include=docker.io,containerd.io,iptables,iproute2,openssh-server,ca-certificates,procps,psmisc,curl \
    bookworm "$DIR" "$MIRROR"
chroot "$DIR" /debootstrap/debootstrap --second-stage

echo "[2/4] configure"
echo "umarm-docker" > "$DIR/etc/hostname"
printf '127.0.0.1\tlocalhost umarm-docker\n' > "$DIR/etc/hosts"
printf '/dev/ubda / ext4 defaults 0 1\n' > "$DIR/etc/fstab"

# root login for the out-of-band sshd; change or remove in production use.
chroot "$DIR" /bin/sh -c 'echo "root:REDACTED" | chpasswd'

# sshd must allow the root key/password login that the phoneside relies on.
printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' \
    >> "$DIR/etc/ssh/sshd_config"

# Android's 127.0.0.11 resolver is not reachable from the guest; use public
# resolvers on the host's uplink (the guest has no network of its own).
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$DIR/etc/resolv.conf"

install -m 755 "$(cd "$(dirname "$0")" && pwd)/umarm-init" "$DIR/umarm-init"
chroot "$DIR" /bin/sh -c 'mkdir -p /run/sshd /var/log/umd'

echo "[3/4] image ($SIZE_MB MB ext4)"
rm -f "$IMG"
mkfs.ext4 -q -F -L umarm-docker "$IMG" "${SIZE_MB}M"
mke2fs -q -d "$DIR" -L umarm-docker "$IMG"
rm -rf "$DIR"

echo "[4/4] done: $IMG"
ls -l "$IMG"

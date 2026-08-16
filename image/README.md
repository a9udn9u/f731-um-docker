# Guest image

`debian-docker.ext4`: a Debian bookworm/arm64 rootfs that the UML kernel
boots as a block device (`ubd0=<img> root=/dev/ubda`).

Built by `mkimage.sh` (needs `debootstrap`, `e2fsprogs`, run as root or with
loop/mke2fs access). Default size 6144 MB — docker + a few images fit with
room to spare.

## What is inside

- `docker.io` + `containerd.io` — the whole point.
- `openssh-server` — out-of-band access into the guest (ssh on 169.254.2.1).
- root password `<password>`, `PermitRootLogin yes`, `PasswordAuthentication yes`.
- `/etc/resolv.conf` pinned to 1.1.1.1 / 8.8.8.8 (the guest has no DNS of its
  own; 127.0.0.11 is the host's and is not reachable).
- `/umarm-init` — the init, see below.

## `/umarm-init` behaviour

It reads `umarm.share=<path>` from the kernel command line (the phoneside
passes one) and mounts it read-write as `/host` via the UML `hostfs` transport.
Then:

- **one-shot mode** — if `/host/guest-cmd` exists, it starts dockerd, waits for
  it, runs the command between `UMARM_OUTPUT_BEGIN` and `UMARM_EXIT=<rc>`
  markers, and powers the guest off. This is how the phoneside installs things
  into the image (e.g. an SSH key) without any network: write `guest-cmd` into
  the share dir, bounce the stack, read the markers from the log.
- **daemon mode** — otherwise it keeps `dockerd` and `sshd` running forever,
  restarting either whenever it dies. This is the mode the phoneside runs in.

Networking is static: the guest takes `169.254.2.1/16` on the UML vector
interface (`vec0`) with `169.254.2.2` (passt) as default route. The same
addressing is baked into `umnet` (see `../patches/kernel/0001-*`).

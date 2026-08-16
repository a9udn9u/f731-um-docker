# Dependencies

Build host: Linux x86_64, clang 14+ (host), make, git, `debootstrap` +
`e2fsprogs` (image only, needs root or equivalent).

## Pinned upstream dependencies

| dep | ref | used for |
|---|---|---|
| [zalexdev/linux-um-arm64](https://github.com/zalexdev/linux-um-arm64) | commit `6dd145a5bb80d6e52d1d4376e5ad24ef6751dd76` (branch `um-arm64`) | the UML-for-arm64 kernel port; `umnet.c`; `stub_exe`; `tools/um-arm64/config/docker.config` |
| [passt](https://passt.top/passt) | commit `defc25b9444c508d21badb6bc9a0b835ddd01126` | the userspace TCP/IP stack |
| Android NDK | r29 (`--target=aarch64-linux-android30`) | bionic headers/libc + static linking |

The kernel and passt pins are the `KCOMMIT` / `PIN` defaults in
`build/build-kernel.sh` and `passt/build.sh`; override with the same env vars.

## On the phone

- **Termux** — the app the whole stack runs in.
- **debian-docker.ext4** — built by `image/mkimage.sh`; Debian bookworm/arm64
  with `docker.io`, `containerd.io`, `openssh-server`.
- Optional: the `app/helper/` APK if you want to launch the stack from outside
  Termux.

## Attribution

The arm64 UML kernel port is the work of the
[zalexdev/linux-um-arm64](https://github.com/zalexdev/linux-um-arm64)
project; this repo only layers the f731-uml delta (see `patches/kernel/`) on
top of a pinned commit and does not modify that project.

`passt` is (c) Red Hat, Inc. and its contributors, licensed GPL-2.0-or-later;
our two patches are under the same terms.

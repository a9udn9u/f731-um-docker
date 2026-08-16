# f731-uml

> **Provenance.** This project was entirely *vibe-coded* — designed, built, and
> debugged end-to-end by an AI agent running **Usloth Qwen3.8 27B Q6** — with
> the goal of turning an unrooted **Verizon Galaxy Z Flip5** into a Docker
> server running inside UML, reachable over SSH. The kernel is based on
> [zalexdev/linux-um-arm64](https://github.com/zalexdev/linux-um-arm64). It has
> only been tested on that one device (see [Compatibility](#compatibility)).

Always-on **Docker + SSH in Termux** on a phone, with no `adb`, no root, no
virtual machine, no privileged network namespaces.

A real Linux kernel (UML ported to arm64 + bionic) runs inside the Termux app
process. It boots a small Debian guest image that runs `dockerd` and `sshd`;
the guest's network is a userspace TCP/IP stack (`passt`, patched) driven
through UML's vector transport by a small helper (`umnet`). Everything is a
bionic static binary, because an Android app process can only exec bionic
binaries.

```
phone (Termux app process)
└── umnet  ──vector fd──▶  linux-um (UML/arm64, bionic, static)
    │                          ├── ubd0: debian-docker.ext4 (Debian bookworm)
    │                          │     └── /umarm-init → dockerd + sshd (supervised)
    │                          └── hostfs: /sdcard/umd/share → /host
    └── passt (patched, bionic, static) → ordinary outbound sockets → uplink
```

Reach it from the LAN:

```sh
ssh -p 2222 root@<phone-ip>
docker run --rm hello-world
```

## What this repo contains

| dir | what |
|---|---|
| `patches/kernel/` | the f731-uml delta on top of the pinned kernel commit (applied at build time) |
| `passt/` | two patches for the Android app sandbox + a reproducible bionic build |
| `build/` | build scripts for the kernel and the net helpers, the bionic toolchain shim, dev diagnostics |
| `image/` | the guest image builder + `/umarm-init` |
| `termux/` | everything that runs on the phone (supervisor, start/stop, one-shot ops) |
| `app/helper/` | a tiny helper APK: run a Termux command from outside Termux |

The UML-for-arm64 kernel port itself is **not vendored here**; it is a pinned
dependency (see `DEPENDS.md`) with attribution to its author.

## Build

```sh
export NDK=/opt/android-ndk-r29          # android-ndk-r29
build/build-kernel.sh                    # → linux-um + stub_exe
build/build-net.sh                       # → umnet + passt
image/mkimage.sh                         # → debian-docker.ext4 (needs debootstrap, root)
```

Then get the artifacts plus the `termux/` scripts onto the phone into
`$HOME/umd` (image to `/sdcard/umd/`) and run `termux/restart.sh` inside
Termux. See `termux/README.md` for the full layout and day-2 operations.

## Compatibility

Verified on a **Verizon Galaxy Z Flip5 (SM-F731U / F731U1, GZE4 build)** —
arm64, 4K-page kernel, API 35, 8 GB RAM. It is *not* tied to that model; the
constraints are architectural:

- **arm64** only (all artifacts are aarch64).
- **API 30+** — that is the bionic build target; newer is fine.
- **Host kernel page size** — the default build is for **4K-page** devices
  (like the one above). 16K-page devices (some Android 15+) will not even
  load the binaries; rebuild per `build/README.md`.
- **~8 GB RAM / ~6 GB shared storage** minimum — guest defaults are 7168M RAM
  and a 6144M image; both are per-device knobs, see `termux/README.md` and
  `image/`.
- **Termux** for the phoneside.
- **Stock-ish app sandbox** — the patches assume the standard Android app
  profile (netlink `bind()` denied, `unshare(CLONE_NEWUSER)` blocked). On a
  heavily customized ROM, run `termux/umd-probe` and `build/diag/nltest.c`
  before investing in a full build.

## How it got here (short version)

Three Android app-sandbox restrictions had to be worked around; each is
documented where it is fixed:

1. **netlink** — `bind(AF_NETLINK, NETLINK_ROUTE)` is EACCES in the app
   sandbox (socket() works, bind is denied). Upstream passt treats this as
   fatal; we make it degrade to local mode. → `passt/passt-android.patch`
2. **addressing** — `umnet` and the guest image had to agree on 169.254.2.x.
   → `patches/kernel/0001-*` + `image/umarm-init`
3. **isolation** — `unshare(CLONE_NEWUSER)` is blocked by the app seccomp
   filter; passt's userns drop is skipped with `PASST_NO_ISOLATE=1`.
   → `passt/passt-bionic.patch` + `termux/passt`

The rest (bionic builds of a kernel and userspace tools, the exec stub for
the app's SELinux domain, the extra syscalls bionic's startup needs) is
described in `docs/notes.md` and in the patch/README notes.

## License

GPL-2.0 (see `LICENSE`). Upstream dependencies are licensed in their own
repos; see `DEPENDS.md`.

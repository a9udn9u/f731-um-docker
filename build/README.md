# Build

Everything runs on a Linux x86_64 host; artifacts are copied to the phone.

```sh
export NDK=/opt/android-ndk-r29

./build-kernel.sh    # kernel + stub_exe   → $O/linux-um, $O/stub_exe
./build-net.sh       # umnet + passt       → $O/umnet, $O/passt
# (image: ../image/mkimage.sh → debian-docker.ext4)
```

`$O` defaults to `/tmp/f731-kernel-build`; both scripts share it, and
`build-net.sh` reuses the patched kernel tree that `build-kernel.sh` checked
out (`KDIR` to point elsewhere).

## Pieces

- `bionic-shim/clang` — a PATH shim making plain `clang` invocations (the
  kernel kbuild with `LLVM=1`) target aarch64-Android bionic: host clang +
  NDK sysroot + NDK clang resource dir. `NDK` env var.
- `build-kernel.sh` — clones the pinned kernel repo, applies
  `../patches/kernel/`, builds with `CONFIG_STATIC_LINK` + `UML_NET_VECTOR` +
  4K pages + the repo's `docker.config`.
- `build-net.sh` — compiles `umnet` (single .c from the patched kernel tree)
  and builds `passt` via `../passt/build.sh`; both checked static/bionic/
  page-aligned before shipping.
- `diag/` — small standalone probes used while developing (see `diag/`).

## Page size

Default `PAGE=4096` matches the 4K-page kernel we ship. For 16K-page devices
rebuild the kernel (`PAGE_SIZE_16KB` instead of `PAGE_SIZE_4KB` in
`build-kernel.sh`) and the helpers with `PAGE=16384`; the reasoning is in
`build-net.sh`.

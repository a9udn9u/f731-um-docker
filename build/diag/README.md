# Dev diagnostics

Standalone probes kept for the record (and for re-debugging on a new device).

- `spair.c` — socketpair + frame round-trip; verifies the UML vector
  transport path in isolation.
- `nltest.c` — minimal `socket(AF_NETLINK, NETLINK_ROUTE)` + `bind()` probe.
  On the app sandbox: socket() succeeds, bind() fails EACCES. That single
  result is why `passt-android.patch` makes netlink non-fatal.

Build either as a normal host binary (for the build host) or, for on-device
testing, with the NDK:

```sh
$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang \
  --target=aarch64-linux-android30 -static -o nltest nltest.c
```

# passt (patched for the Android app sandbox)

The network stack of the guest. `passt` is a userspace TCP/IP stack: it turns
the guest's packets (handed to it by `umnet`) into ordinary outbound sockets,
so the guest gets internet with no privileges at all.

Upstream: <https://passt.top/passt>, pinned to
`defc25b9444c508d21badb6bc9a0b835ddd01126`.

## Why patches

An app process on Android is started by zygote with a seccomp filter already
installed and runs in a locked-down sandbox. Three things upstream passt does
are not possible there, so we patch it:

| file | patch | problem | fix |
|---|---|---|---|
| headers, `isolation.c` | `passt-bionic.patch` | bionic differs from glibc/musl in several headers; `unshare(CLONE_NEWUSER)` is blocked by the app seccomp filter | header/`__BIONIC__` guards; new `PASST_NO_ISOLATE` env var skips the userns drop |
| `util.c`, `netlink.c` | `passt-android.patch` | `bind(AF_NETLINK, NETLINK_ROUTE)` returns EACCES in the app sandbox (socket() works, bind is denied), which upstream treats as fatal | `ns_is_init()` no longer dies on a missing ns; netlink failures degrade to a warning and passt runs in **local mode** |

Local mode is all we need: with netlink unavailable, passt derives the guest's
addressing itself, which is exactly what the guest image is configured for
(169.254.2.0/16, see `../image/umarm-init`).

## Build

```sh
NDK=/path/to/android-ndk-r29 ./build.sh
```

Produces a static aarch64-Android `passt` (plus its self-installed seccomp
filter, widened with `EXTRA_SYSCALLS` for bionic's startup/malloc). Build
notes, including the page-size and seccomp trade-offs, are in `build.sh`.

At run time it is wrapped by `../termux/passt`, which sets
`PASST_NO_ISOLATE=1`.

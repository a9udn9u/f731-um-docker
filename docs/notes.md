# Notes: what the f731-uml delta is, and where the pieces came from

## The kernel pin and its delta

`build/build-kernel.sh` checks out
[zalexdev/linux-um-arm64](https://github.com/zalexdev/linux-um-arm64) @
`6dd145a5bb80d6e52d1d4376e5ad24ef6751dd76` (tip of `um-arm64` at the time of
writing) and applies, in order:

| patch | what it changes | why |
|---|---|---|
| `0001-...-umnet-tcp-port-and-169-254-2-addressing` | `tools/um-arm64/harness/umnet.c` | default guest addressing to 169.254.2.0/16 (guest `169.254.2.1` ↔ passt `169.254.2.2`), matching the guest image; add `--tcp-port A:B` so the phoneside can publish guest sshd (22) on a host port (2222) without the guest running a proxy |
| `0002-...-android-stub-exe-selinux` | `tools/um-arm64/harness/android.sh` | the app's SELinux domain cannot exec a path the kernel would pick by default; the harness must push/point at an explicit `stub_exe` (the SKAS stub, a kernel build artifact at `arch/um/kernel/skas/stub_exe`) |
| `0003-...-bionic-syms-sched-setattr-sync_file_range` | `arch/arm64/um/bionic-syms.redef` | two symbols bionic's libc references that the port's syscall table did not export (`sched_setattr`, `sync_file_range`); without them the guest binaries that touch them die on startup |

All three apply cleanly to the pin with `git apply` (verified); the patch set
is the diff of a working tree, i.e. it is *complete* relative to the pin.

Drift to watch: the kernel repo is still evolving (its own docs live in
`tools/um-arm64/doc/` — port design, status, syscall budget, page size). If
the pin moves, re-verify the stack applies; `0002`/`0003` are the fragile
ones.

## The passt pin and its delta

`passt/build.sh` checks out upstream passt @
`defc25b9444c508d21badb6bc9a0b835ddd01126` and applies `passt-bionic.patch`
then `passt-android.patch`. Both were verified to apply cleanly to the pin and
to reproduce the deployed binary's sources. The kernel repo's own
`build-net-bionic.sh` expects a *single* `passt-bionic.patch` (the
glibc→bionic port) from the author's local `dist/` layout; this repo splits
the second, Android-specific patch out and builds self-contained, so the two
are independent.

Note: the kernel repo's `build-net-bionic.sh` and a few harness scripts
reference the upstream author's local paths (`/root/mlu-arm64/...`) and a
`dist/` directory that is not in the public tree. We do not use that script;
`build/build-net.sh` is the self-contained replacement.

## Why everything is bionic-static

An Android app process:

- is exec'd only from the app's `nativeLibraryDir`-equivalent (Termux's home),
  so no dynamic loader is involved for our binaries → **static**;
- starts with zygote's seccomp filter installed; glibc's startup issues
  `rseq(2)`/`set_robust_list(2)` which that filter kills (status 159, no
  output) → **bionic**, whose startup is in the app's allowlist;
- runs in a SELinux domain that may not exec arbitrary kernel-chosen paths →
  the kernel needs an explicit `stub_exe`.

`passt` additionally installs its *own* seccomp filter at start-up; bionic's
malloc/startup need 16 syscalls glibc didn't, so the build widens that filter
with `EXTRA_SYSCALLS` (see `passt/build.sh`). And passt's user-namespace
privilege drop is skipped with `PASST_NO_ISOLATE=1` (`termux/passt`) because
`unshare(CLONE_NEWUSER)` is blocked in the app sandbox.

## The network, end to end

- guest `vec0` (UML vector, `CONFIG_UML_NET_VECTOR`) carries frames to
  `umnet`;
- `umnet` reframes to passt's length-prefixed socket protocol;
- `passt` (local mode, netlink unavailable) does NAT + ARP + routing for the
  169.254.2.0/16 subnet and forwards to the host's uplink sockets;
- `--tcp-port 2222:22` publishes guest sshd on the phone's port 2222;
- DNS is 1.1.1.1/8.8.8.8 inside the guest (`/etc/resolv.conf`), because
  Android's 127.0.0.11 resolver is not reachable from the guest.

## Dev diagnostics kept in `build/diag/`

- `spair.c` — minimal socketpair + frame round-trip probe, used to prove the
  vector transport path before the full stack.
- `nltest.c` — minimal netlink socket/bind probe; this is what showed
  `socket(AF_NETLINK)` succeeding while `bind()` fails EACCES in the app
  sandbox, which is the entire motivation for `passt-android.patch`.

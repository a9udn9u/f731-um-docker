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

## Performance on the F731 (Galaxy Z Flip5)

Benchmarks run from a dev machine over `ssh -p 2222` (`termux/bench.sh`),
median of 3 rounds. `compute_256m` (dd /dev/zero→/dev/null) is the thermal
drift validator: it is pure guest userspace and cannot move between
configurations, so when it drifts the other rows of that run are suspect.
Raw runs are produced by `termux/bench.sh <label>` (median of 3); the three
reference runs are inlined in the table below rather than kept as files.

### The phone throttles hard — compare only matched thermal states

The UML core runs on one host core under Android's `walt` governor, and the
app is cpuset-restricted to 6 of the 8 cores (mask `0x5f` = {0,1,2,3,4,6}:
three 2.0 GHz + three 2.8 GHz; the 3.36 GHz prime core is excluded). When
hot, the core throttles ~2.6× (compute 209 ms → 80 ms as it cools). Every
before/after below is subject to this; the `compute` and `ssh_rtt` rows are
the drift controls. Termux's `/proc` also omits `cpus_allowed{,_list}` and the
v1 `top-app` cpuset/quota files are SELinux-locked, so the mask is read via
`taskset -p`.

### What changed (P0/P1/P4) and the measured effect

Baseline was captured with the image on FUSE `/sdcard` (and the phone hot).
Steady-state is the image on `$HOME` (app partition), `noatime` root, docker
log caps, unpinned + `seccomp=on` — the port's recommended config. The third
column is the P3 single-core A/B (see below). Three reference runs, median of
3, in milliseconds — the full per-row data:

| row (ms) | baseline (hot, FUSE) | steady (no-pin) | pinned (core 4) |
|---|---:|---:|---:|
| compute_256m *(drift)* | 209 | 95 | 32 |
| ssh_rtt_local *(drift)* | 1534 | 554 | 307 |
| syscall_x100k | 33800 | 918 | 2630 |
| forkexec_x100 | 8 | 4 | 2 |
| openat_ls_usrbin | 416 | 142 | 58 |
| dd_seqwrite_256m | 7364 | 1410 | 1726 |
| dd_seqread_256m | 273 | 65 | 56 |
| dd_rand4k_sync_x300 | 29420 | 8933 | 6123 |
| dd_rand4k_buf_x300 | 28999 | 11119 | 5700 |
| tar_pack | 24904 | 3871 | 3474 |
| tar_unpack | 26220 | 5008 | 4435 |
| docker_run_x3 | 42055 | 12273 | 6024 |

The raw ~3–6× overstates the image move: ~2.6× of it is thermal (the phone
cooled between the hot baseline and the cool steady state). Normalized, the
FUSE→app-partition move is worth roughly **1.5–2×** on the disk rows. The big,
unambiguous win is real: the 256 MB sequential read went 273 → 65 ms (~4 GB/s)
and random 4 K synced writes dropped from ~99 ms to ~30 ms.

### The syscall cost is the port's inherent floor

`syscall_x100k` (100 k `dd bs=1` read/write pairs) settled at ~9 µs/syscall in
the cool state. This is **not** tunable by config or affinity — it is the host
futex/signal round-trip between the UML kernel thread and the `uml-userspace`
seccomp stub, which the port's own `doc/80-performance.md` identifies as the
mechanism: "nonvoluntary [context switches] is effectively zero... the cost is
entirely voluntary handoffs... inherent to having the kernel in another
process." On the port's reference (Snapdragon 870) it was 22 µs; the Exynos
2200 does ~9 µs. Nothing here is below that floor.

### P3: affinity pinning is a regression, not a fix

We A/B tested `CPUS=4` (pin the whole stack to one 2.8 GHz core) against
unpinned. Thermal-normalized (syscall ÷ compute), single-core pinning was
**~8.5× worse** (9.7 → 82). The port's doc reached the same conclusion on
different hardware: pinning to one core halves the microbenchmark but regresses
real work because guest compute and ubd I/O then contend for the single core.
`walt`'s free scheduling across the 6 allowed cores is already near-optimal;
leave `CPUS` unset.

### Levers not taken (deliberately)

- **Prefault ramp** (`arch/um/kernel/trap.c:173`, `um_prefault_ramp[]`): the
  one named lever for the `fault` row (program-startup page faults, ~51 µs each
  under seccomp). It is a kernel code change, capped by the stub's free batch
  slots, and only marginally speeds startup — not worth a rebuild for the gain.
- **HZ=1000 / PREEMPT_LAZY**: config-only, but the port does not cite them as
  levers and they touch guest-internal scheduling that is mostly idle for
  single-task terminal/docker work. Marginal.

Practical conclusion: after P0/P1/P4 the stack is at the UML performance floor
for its workloads. The remaining "feel" costs are the inherent per-syscall
handoff and the WiFi/SSH RTT (the `ssh_rtt` row), neither of which a phoneside
change can remove.

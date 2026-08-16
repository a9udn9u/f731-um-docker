# Phoneside (Termux)

Everything that runs on the phone, inside the Termux app. This is the
"phoneside" of the stack; the guest runs the UML kernel + `debian-docker.ext4`.

## Layout on the phone

The scripts assume they live in `$HOME/umd`, with the heavy files in
`/sdcard/umd` (shared storage, so you can push/pull them from a host machine
without `adb`):

```
$HOME/umd/
  umd-supervise umd-start umd-stop umd-status umd-log umd-probe restart.sh
  umnet linux-um stub_exe passt passt-bin umdprobe debian-docker.ext4
/sdcard/umd/
  debian-docker.ext4        # the guest image (mounted by the kernel)
  share/                    # hostfs share, mounted as /host inside the guest
  umd.out supervise.log     # logs (symlinked/created here)
```

`restart.sh` is the canonical (re)start: it copies the two live scripts from
`/sdcard/umd`, fixes permissions, and launches `umd-supervise` detached.

## The stack

`umd-supervise` runs forever and respawns the whole stack if anything dies:

```
umnet --passt ./passt --tcp-port 2222:22 -- \
  ./linux-um mem=7168M ubd0=/sdcard/umd/debian-docker.ext4 root=/dev/ubda rw \
    init=/umarm-init stub_exe="$PWD/stub_exe" panic=-1 seccomp=auto \
    con=null con0=null,fd:1 umarm.share=/sdcard/umd/share
```

- `linux-um` — the UML kernel (built by `../build/`).
- `umnet` — reframes between UML's vector `fd` transport and passt's protocol.
- `passt` — this directory's wrapper; the real binary is `passt-bin`.
- `stub_exe` — the kernel's exec stub, needed because the app's SELinux
  domain cannot exec arbitrary paths (see `../patches/kernel/0002-*`).
- `--tcp-port 2222:22` — publishes guest sshd on the host's port 2222.
- `umarm.share` — the hostfs share dir (see `../image/`).

Because `umd-supervise` is the parent and never exits, the stack comes back
after a crash or an OOM kill of any component; `termux-wake-lock` (from
`umd-start`) keeps the CPU awake while it runs.

## Usage

```sh
./umd-start          # start (wake-lock + supervise loop, detached)
./umd-status         # running? + tail of the log
./umd-log [N]        # last N lines of the guest/kernel log (default 80)
./umd-stop           # stop everything
./umd-probe          # run the exec/userns capability probes (umdprobe.c)
./restart.sh         # (re)start, the way the phone does it for real
```

## One-shot operations into the image

To run something inside the guest without a network (e.g. install an SSH key
into the image), use the one-shot mode described in `../image/README.md`:
write `guest-cmd` into `/sdcard/umd/share/`, bounce the stack via
`restart.sh`, and read the `UMARM_OUTPUT_BEGIN`/`UMARM_EXIT` markers from
`/sdcard/umd/umd.out`.

## Access

```sh
ssh -p 2222 root@<phone-ip>
```

(`<phone-ip>` is the phone's LAN address; password login as `root`/`<password>`
also works.)

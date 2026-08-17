# Phoneside (Termux)

Everything that runs on the phone, inside the Termux app. This is the
"phoneside" of the stack; the guest runs the UML kernel + `debian-docker.ext4`.

## Layout on the phone

Live files (what the stack actually reads) live in `$HOME/umd`, on the app's
**private partition — not FUSE `/sdcard`**. That matters: the guest image is a
~6 GB random-I/O ext2 disk, and reading it through FUSE `/sdcard` cost a
~99 ms/4 K synced write in benchmarks (see `../docs/notes.md`). `/sdcard/umd`
is the drop zone: shared storage for pushing a new image from a host machine
without `adb`, the hostfs share, and the logs.

```
$HOME/umd/                     # live (app partition, off FUSE)
  restart.sh  umd-supervise
  umnet  linux-um  stub_exe  passt  passt-bin
  debian-docker.ext4           # the guest image the kernel actually mounts
/sdcard/umd/                   # drop zone (FUSE) + share + logs
  debian-docker.ext4           # drop a NEW image here; UMD_SYNC=1 ./restart.sh deploys it
  *.staged                     # staged files; restart.sh installs to $HOME/umd
  umd.out  supervise.log       # logs
```

The **entire** `/sdcard/umd` is the guest's `/host` (via
`umarm.share=/sdcard/umd`), so from the guest you can read the boot log, the
supervise log, and push new scripts out as `*.staged`.

`restart.sh` is the canonical (re)start. It:
1. stops the stack (`pkill` supervise/linux-um/umnet/passt);
2. installs any `/sdcard/umd/*.staged` into `$HOME/umd/<name>` (+x) and removes
   the staged file — this is the dev→phone update channel (the guest writes to
   `/host`, which is `/sdcard/umd`);
3. deploys the guest image **only on request**: it copies
   `/sdcard/umd/debian-docker.ext4` → `$HOME/umd/…` when you set `UMD_SYNC=1`
   (and the drop-zone copy is newer). A plain restart never overwrites the live
   image — which holds `/var/lib/docker`, i.e. every docker image + container.
   First-time (no live image yet) it installs automatically.
4. launches `umd-supervise` detached.

## The stack

`umd-supervise` runs forever and respawns the whole stack if anything dies. The
guest image is read from `$HOME/umd` (off FUSE):

```
[taskset -c "$CPUS"] umnet --passt ./passt --tcp-port 2222:22 -- \
  ./linux-um mem=${MEM}M ubd0="$PWD/debian-docker.ext4" root=/dev/ubda rw \
    init=/umarm-init [stub_exe="$PWD/stub_exe"] panic=-1 seccomp=auto \
    con=null con0=null,fd:1 umarm.share=/sdcard/umd
```

Env knobs (all optional — set them on the `restart.sh` command line):
- `MEM=7168` — the guest RAM budget, ~80% of the phone's physical RAM
  (7168 fits an 8 GB-class device).
- `UMD_IMG=/path` — the guest image file (default `$PWD/debian-docker.ext4`).
- `CPUS=4-7` — pin the whole stack to these host cores via `taskset`.
  **Off by default, and recommended to stay off:** the port's own
  benchmarking found unpinned + `seccomp=on` is the fastest config for real
  work, and pinning to one core regresses it (see `../docs/notes.md`).

`seccomp=auto` selects the seccomp fast path when the host allows it (the boot
log confirms `Userspace mode: SECCOMP`). `stub_exe` is passed only if the file
exists in `$HOME/umd`; otherwise the kernel falls back to its built-in memfd
stub.

Other bits:
- `linux-um` — the UML kernel (built by `../build/`).
- `umnet` — reframes between UML's vector `fd` transport and passt's protocol.
- `passt` — this directory's wrapper; the real binary is `passt-bin`.
- `--tcp-port 2222:22` — publishes guest sshd on the host's port 2222.

Because `umd-supervise` is the parent and never exits, the stack comes back
after a crash or an OOM kill of any component.

## Usage

```sh
./restart.sh                 # (re)start — the canonical path
UMD_SYNC=1 ./restart.sh      # deploy a newer image from the /sdcard/umd drop zone
MEM=8192 ./restart.sh        # override the guest RAM budget
CPUS=4-7 ./restart.sh        # pin (only for A/B testing; see note above)
./umd-status                 # running? + tail of the log (if present)
./umd-log [N]                # last N lines of the guest/kernel log (default 80)
./umd-stop                   # stop everything (if present)
```

## Auto-start after reboot

Termux:Boot (`com.termux.boot`) brings Termux up after a phone reboot, but
nothing launches the UML on its own. To auto-start it, put `bootstrap.sh`
(this directory) into `~/.termux/boot/` — create the directory if needed and
make the file executable:

```sh
mkdir -p ~/.termux/boot
install -m 755 <path-to-this-dir>/bootstrap.sh ~/.termux/boot/
```

**First-time setup:** launch the Termux:Boot app manually at least once (from
the launcher) so Android registers it for boot events; on Samsung/OEM builds
it will not auto-start otherwise.

After that, Termux:Boot runs every executable file in `~/.termux/boot/` at
boot → `restart.sh` → `umd-supervise`. The guest's own init
(`image/umarm-init`) starts and supervises `sshd` (host:2222) and `dockerd`,
so `ssh -p 2222 root@<phone-ip>` and `docker` work with no further action.
Containers persist across reboot — their state lives in the guest image's
`/var/lib/docker`.

## One-shot operations into the image

To run something inside the guest without a network (e.g. install an SSH key
into the image), use the one-shot mode described in `../image/README.md`:
write `guest-cmd` into `/sdcard/umd/` (the guest's `/host`), bounce the stack
via `restart.sh`, and read the `UMARM_OUTPUT_BEGIN`/`UMARM_EXIT` markers from
`/sdcard/umd/umd.out`. Remove the `guest-cmd` file afterwards so the next boot
goes back to daemon mode.

## Access

```sh
ssh -p 2222 root@<phone-ip>
```

(`<phone-ip>` is the phone's LAN address. Log in as `root` with an SSH key —
installed into the image via the one-shot flow above — or with the password
you chose at image build time (`ROOT_PW` in `../image/mkimage.sh`).)

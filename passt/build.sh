#!/bin/bash
# Build passt as a static aarch64-Android (bionic) binary.
#
# Upstream passt is written for glibc/musl; bionic differs in several headers,
# and the Android *app* sandbox additionally forbids the netlink bind() and the
# user-namespace isolation passt normally drops into. Both are fixed by the two
# patches in this directory, which are applied here on top of the pinned
# upstream commit so the result is reproducible from a bare clone.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PASSUP=${PASSUP:-https://passt.top/passt}
PIN=${PIN:-defc25b9444c508d21badb6bc9a0b835ddd01126}
NDK=${NDK:-/opt/android-ndk-r29}
API=${API:-30}
O=${O:-/tmp/f731-passt-build}

# Page size the target kernel uses; see the long note in
# ../build/build-net.sh. 4096 matches the 4K-page kernel we ship.
PAGE=${PAGE:-4096}

# Bionic's startup and malloc need a handful of syscalls glibc did not; without
# these passt dies on SIGSYS right after start-up. Every entry weakens passt's
# own seccomp sandbox, so keep the list minimal.
EXTRA_SYSCALLS="clock_nanosleep epoll_create1 eventfd2 futex gettid inotify_init1 madvise membarrier mremap newfstatat pread64 prlimit64 pwrite64 set_robust_list signalfd4 waitid"

TOOL=$NDK/toolchains/llvm/prebuilt/linux-x86_64
if [ ! -x "$TOOL/clang" ]; then
    echo "no NDK at $NDK (set NDK=)" >&2
    exit 2
fi
CC="$TOOL/clang --target=aarch64-linux-android$API"

SRC=$O/passt
rm -rf "$SRC"
if [ ! -d "$O/.passt-clone" ]; then
    git clone "$PASSUP" "$O/.passt-clone" >&2
fi
git -C "$O/.passt-clone" checkout -q "$PIN"
mkdir -p "$SRC"
git -C "$O/.passt-clone" archive "$PIN" | tar -C "$SRC" -x

cd "$SRC" || exit 1
git apply --check "$HERE/passt-bionic.patch" || { echo "passt-bionic.patch fails to apply"; exit 2; }
git apply "$HERE/passt-bionic.patch"
git apply --check "$HERE/passt-android.patch" || { echo "passt-android.patch fails to apply"; exit 2; }
git apply "$HERE/passt-android.patch"

rm -f passt pasta pesto passt.avx2 pasta.avx2 seccomp.h seccomp_repair.h seccomp_pesto.h
VERSION=$(git -C "$O/.passt-clone" rev-parse --short "$PIN")
make CC="$CC" ARCH=aarch64 TARGET=aarch64-linux-android \
     VERSION="$VERSION-bionic" EXTRA_SYSCALLS="$EXTRA_SYSCALLS" \
     CFLAGS="-static -Wl,-z,max-page-size=$PAGE" \
     CPPFLAGS="-UPAGE_SIZE -DPAGE_SIZE=$PAGE" \
     passt >&2 || exit 1

# The app can only exec what it can load: no PT_INTERP, bionic static, and LOAD
# segments aligned at least at $PAGE or the ELF is unloadable.
"$TOOL/llvm-readelf" -l passt | grep -q INTERP && { echo "passt has PT_INTERP"; exit 1; }
case "$(file -b passt)" in
*"ARM aarch64"*"statically linked"*) ;;
*) echo "unexpected: $(file -b passt)"; exit 1 ;;
esac
for align in "$("$TOOL/llvm-readelf" -l passt | awk '$1 == "LOAD" { print $NF }')"; do
    [ "$align" -ge "$PAGE" ] || { echo "passt LOAD aligned $align < $PAGE"; exit 1; }
done

cp -f passt "$O/passt"
echo "passt built: $O/passt ($(file -b "$O/passt" | cut -c1-90))"

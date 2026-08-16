#!/bin/bash
# Build the two userspace networking helpers (umnet + passt) as static
# aarch64-Android (bionic) binaries.
#
# Neither needs any privilege, which is the whole point -- but an app process
# is started by zygote with a seccomp filter already installed, and a glibc
# helper dies before main() (status 159, no output). So both are bionic
# binaries, exactly like the kernel.
#
# umnet is a single translation unit that lives in the kernel repo's harness
# (tools/um-arm64/harness/umnet.c); it is built from the same patched tree that
# build-kernel.sh checked out, so the f731-uml umnet patch (the 169.254.2.x
# addressing and --tcp-port) is already applied.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KDIR=${KDIR:-/tmp/f731-kernel-build/tree}   # patched kernel tree (build-kernel.sh)
NDK=${NDK:-/opt/android-ndk-r29}
API=${API:-30}
O=${O:-/tmp/f731-kernel-build}

# Page size the target kernel uses. The link needs it because ld defaults to
# 4K segment alignment and the kernel's ELF loader mmaps each LOAD segment at
# its own page granularity: a 4K-aligned binary cannot load on a 16K-page
# kernel. passt also bakes PAGE_SIZE in at compile time; a value larger than
# the target's is harmless where a smaller one under-aligns. 4096 matches the
# 4K-page kernel we ship; build both kernels/helpers at 16384 for 16K devices.
PAGE=${PAGE:-4096}

TOOL=$NDK/toolchains/llvm/prebuilt/linux-x86_64
[ -x "$TOOL/clang" ] || { echo "no NDK at $NDK (set NDK=)" >&2; exit 2; }
CC="$TOOL/clang --target=aarch64-linux-android$API"

[ -f "$KDIR/tools/um-arm64/harness/umnet.c" ] \
    || { echo "no umnet.c under $KDIR (run build-kernel.sh first or set KDIR=)"; exit 2; }

check_bin() {
    local f align
    if "$TOOL/llvm-readelf" -l "$f" | grep -q INTERP; then
	echo "$f: has PT_INTERP, not usable in an app" >&2
	return 1
    fi
    case "$(file -b "$f")" in
    *"ARM aarch64"*"statically linked"*) ;;
    *) echo "$f: unexpected: $(file -b "$f")"; return 1 ;;
    esac
    for align in $("$TOOL/llvm-readelf" -l "$f" | awk '$1 == "LOAD" { print $NF }'); do
	[ "$align" -ge "$PAGE" ] || { echo "$f: LOAD aligned $align < $PAGE"; return 1; }
    done
}

mkdir -p "$O"

### umnet
$CC -O2 -Wall -Wextra -static -Wl,-z,max-page-size="$PAGE" \
    -o "$O/umnet" "$KDIR/tools/um-arm64/harness/umnet.c" >&2 \
    || { echo "umnet build failed"; exit 1; }

### passt (own patches + seccomp widening; see ../passt/)
NDK="$NDK" API="$API" PAGE="$PAGE" O="$O" "$HERE/../passt/build.sh" || exit 1

check_bin "$O/umnet" && check_bin "$O/passt" || exit 1
echo "net helpers built: $O/umnet $O/passt"

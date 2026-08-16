#!/bin/bash
# Build the UML-for-arm64 kernel (linux-um) from the linked kernel repo.
#
# The kernel port is not part of this tree; it lives in
# zalexdev/linux-um-arm64 and is pinned by commit. This script checks out that
# commit, applies the f731-uml kernel patch stack (../patches/kernel/), and
# builds a static aarch64-Android (bionic) kernel with CONFIG_STATIC_LINK.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KREPO=${KREPO:-https://github.com/zalexdev/linux-um-arm64.git}
KCOMMIT=${KCOMMIT:-6dd145a5bb80d6e52d1d4376e5ad24ef6751dd76}
NDK=${NDK:-/opt/android-ndk-r29}
O=${O:-/tmp/f731-kernel-build}
ROOT=$O/tree

mkdir -p "$O"
if [ ! -d "$ROOT/.git" ]; then
    git clone "$KREPO" "$ROOT" >&2
fi
git -C "$ROOT" fetch -q origin 2>/dev/null || true
git -C "$ROOT" checkout -q "$KCOMMIT"

# The f731-uml delta on top of the pinned commit (see ../patches/kernel/).
git -C "$ROOT" apply --check "$HERE"/../patches/kernel/*.patch \
    || { echo "kernel patch stack does not apply to $KCOMMIT"; exit 2; }
git -C "$ROOT" apply "$HERE"/../patches/kernel/*.patch

export NDK
export PATH="$HERE/bionic-shim:$PATH"
# Fixed metadata so the image is byte-reproducible.
export KBUILD_BUILD_TIMESTAMP="Thu Jan  1 00:00:00 UTC 1970"
export KBUILD_BUILD_USER=f731
export KBUILD_BUILD_HOST=arm64

ARGS=(-C "$ROOT" O="$O/kbuild" ARCH=um SUBARCH=arm64 LLVM=1
      HOSTCC=/usr/bin/clang HOSTCXX=/usr/bin/clang++)

make "${ARGS[@]}" arm64_defconfig </dev/null >/dev/null 2>&1 || exit 1
"$ROOT/scripts/config" --file "$O/kbuild/.config" \
    -e STATIC_LINK -e UML_NET_VECTOR -e PAGE_SIZE_4KB -d PAGE_SIZE_16KB
"$ROOT/scripts/kconfig/merge_config.sh" -m -O "$O/kbuild" \
    "$O/kbuild/.config" "$ROOT/tools/um-arm64/config/docker.config" >/dev/null 2>&1
make "${ARGS[@]}" olddefconfig </dev/null >/dev/null 2>&1 || exit 1
grep -q '^CONFIG_STATIC_LINK=y'    "$O/kbuild/.config" || { echo STATIC_FAIL; exit 1; }
grep -q '^CONFIG_PAGE_SIZE_4KB=y'  "$O/kbuild/.config" || { echo PAGE_FAIL;   exit 1; }
grep -q '^CONFIG_UML_NET_VECTOR=y' "$O/kbuild/.config" || { echo VEC_FAIL;    exit 1; }

make "${ARGS[@]}" -j"$(nproc)" </dev/null > "$O/kbuild.log" 2>&1 \
    || { echo BUILD_FAIL; tail -30 "$O/kbuild.log"; exit 1; }

cp -f "$O/kbuild/linux" "$O/linux-um"
# The SKAS exec stub the kernel needs to exec in the app's SELinux domain.
cp -f "$O/kbuild/arch/um/kernel/skas/stub_exe" "$O/stub_exe" 2>/dev/null
echo "kernel built: $O/linux-um"
file -b "$O/linux-um" | cut -c1-90

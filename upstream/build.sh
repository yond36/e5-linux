#!/bin/bash
# Build the E5's mainline kernel (linux-lts-e5) in the e5-mainline-build container:
# upstream/out/Image, Image.lk (for LK), modules/ (flat) and modules.tar (lib/modules), config, System.map.
#
#   docker build -t e5-mainline-build upstream/     (once)
#   upstream/build.sh                                (from the host; runs itself in the container)
#
# E5_KERNEL_TREE  the kernel repository (default: linux-lts-e5 next to upstream/)
# E5_RELEASE=1    the kernel of a flash package (openwrt/make-flash-bundle.sh E5_MAINLINE=1): the command line
#                 without e5.openwrt=, so boot/init starts the installed openwrt.ext4 and it can be the default
#                 boot; into upstream/out-release/, so that the trial scripts (upstream/out/) never take it
# The objects stay in the docker volume e5-mainline-out (a bind mount would be slower), per kernel release.
set -eo pipefail
if [ -z "${E5_IN_CONTAINER:-}" ]; then
    HERE="$(cd "$(dirname "$0")" && pwd)"
    K="${E5_KERNEL_TREE:-$HERE/../linux-lts-e5}"
    K="$(cd "$K" && pwd)"
    exec docker run --rm -e E5_IN_CONTAINER=1 -e E5_RELEASE="${E5_RELEASE:-}" \
        -e TZ=CST-8 -e KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-}" \
        -e E5_OUTPUT_UID="$(id -u)" -e E5_OUTPUT_GID="$(id -g)" \
        -v "$K":/src/linux -v e5-mainline-out:/out -v "$HERE":/work \
        e5-mainline-build bash /work/build.sh "$@"
fi

# An empty variable overrides kbuild's default, so unset it for local builds.
[ -n "${KBUILD_BUILD_TIMESTAMP:-}" ] || unset KBUILD_BUILD_TIMESTAMP
cd /src/linux
KV=$(make -s kernelversion)
O=/out/$KV
mkdir -p "$O"
echo "== linux-lts-e5 $KV, $(git log --oneline -1)"
# The E5 changes that are not in Enceka's tree yet ride in as patches, next to
# this script (e5-mainline-patches/).  kernel/patches/ is the 5.15 vendor
# series and does not apply here.  The tree is a pristine CI clone, so each
# patch is either not applied or already applied; anything else stops the build.
#
# The patched files are then marked assume-unchanged, WITHOUT committing: a
# tree git considers dirty makes setlocalversion append -dirty, and the release
# string 6.18.54-e5-g020b970e351e-dirty no longer matches the modules path the
# rootfs ships (/lib/modules/6.18.54-e5-g020b970e351e -- openwrt/build-rootfs.sh
# stages them under kernel.release), so no module would load: the CP chain
# never starts and ModemManager finds no modem.  (kernel/e5-linux.fragment warns
# about exactly this.)  Committing instead is not an option: the release check
# compares the kernel checkout's revision before and after the build and stops
# when it moved.
if [ -d /work/e5-mainline-patches ]; then
    patched=
    for p in $(ls /work/e5-mainline-patches/*.patch 2>/dev/null | sort); do
        if git apply --reverse --check "$p" 2>/dev/null; then
            echo "== $(basename "$p"): already applied"
        else
            echo "== applying $(basename "$p")"
            git apply "$p" || { echo "cannot apply $p" >&2; exit 1; }
        fi
        # only the files the tree already tracks (Kconfig, Makefile) count as
        # changes; the driver sources the patch adds are untracked, and the
        # dirty test -- setlocalversion's too -- runs with --untracked-files=no
        for f in $(git apply --numstat "$p" 2>/dev/null | cut -f3); do
            git ls-files --error-unmatch "$f" >/dev/null 2>&1 && patched="$patched $f"
        done
    done
    # shellcheck disable=SC2086
    [ -z "$patched" ] || git update-index --assume-unchanged $patched
    [ -z "$(git status --porcelain --untracked-files=no)" ] ||
        echo "   (note: the tree still looks changed; the release gets -dirty)"
fi

CFG=/work/e5-mainline.config DEST=/work/out
if [ -n "${E5_RELEASE:-}" ]; then
    CFG=/tmp/e5-mainline-release.config DEST=/work/out-release
    sed 's/ e5\.openwrt=[A-Za-z0-9._-]*//' /work/e5-mainline.config > "$CFG"
    ! grep -q 'e5\.openwrt=' "$CFG" || { echo "e5.openwrt= is still in the release command line" >&2; exit 1; }
    echo "   (release: no e5.openwrt=, into out-release/)"
fi
make O="$O" ARCH=arm64 allnoconfig >/dev/null
./scripts/kconfig/merge_config.sh -m -O "$O" "$O/.config" "$CFG" >/dev/null
make O="$O" ARCH=arm64 olddefconfig >/dev/null
# options Kconfig did not take: known ones are listed in config-ignored.txt, any other stops the build
# (mu300-linux: a silently dropped option has cost a working feature before)
bad=
while IFS= read -r l; do
    case "$l" in CONFIG_*=*)
        k=${l%%=*} v=${l#*=}
        g=$(grep -E "^$k=" "$O/.config" | cut -d= -f2- || true)
        if [ "$v" = n ]; then
            grep -q "^$k=[ym]" "$O/.config" && bad="$bad\nNOT DISABLED: $k"
            continue
        fi
        [ "$g" = "$v" ] || grep -qx "$k" /work/config-ignored.txt 2>/dev/null || bad="$bad\nNOT SET: $k want $v got ${g:-unset}";;
    esac
done < "$CFG"
[ -z "$bad" ] || { printf "config options not taken:$bad\n" >&2; exit 1; }

# The object tree lives in the docker volume e5-mainline-out and survives
# between runs, keyed only by kernel release -- which does not change when a
# patch's own sources do.  A stale e5-dvfs.o was silently reused that way: the
# module in the image had the cooling code but not the handshake that the
# patch's source clearly has.  Drop this series' objects first so the sources
# are what gets compiled.
rm -rf \
    "$O"/drivers/cpufreq/e5-dvfs.o "$O"/drivers/cpufreq/e5-dvfs-probe.o \
    "$O"/drivers/cpufreq/.e5-dvfs.o.cmd "$O"/drivers/cpufreq/.e5-dvfs-probe.o.cmd \
    "$O"/drivers/cpufreq/e5-dvfs.ko "$O"/drivers/cpufreq/e5-dvfs-probe.ko \
    "$O"/drivers/cpufreq/.e5-dvfs.ko.cmd "$O"/drivers/cpufreq/.e5-dvfs-probe.ko.cmd

# on failure, the compiler's own messages (a plain grep for "error" also matches object names)
make O="$O" ARCH=arm64 -j"$(nproc)" Image modules > "$O/build.log" 2>&1 || {
    grep -n -E ": (fatal )?error: |-Werror|treated as errors|undefined reference|No such file|Killed|internal compiler error|\*\*\*" -A3 "$O/build.log" | head -80 || true
    echo "--- end of build.log:"; tail -25 "$O/build.log"
    exit 1
}
# A module that silently lost half its code is worse than a failed build: the
# image ships it, it loads, and the feature is simply absent -- which is how
# the DVFS client reached the card with its cooling code but no handshake.
# Check the strings the source promises before anything is staged.
dvfs=$O/drivers/cpufreq/e5-dvfs.ko
# (what the tree actually holds: the patch is verified to contain the
# handshake, so if the built module lacks it, the tree is not what was patched)
if [ -f drivers/cpufreq/e5-dvfs.c ]; then
    echo "== e5-dvfs.c: $(wc -l < drivers/cpufreq/e5-dvfs.c) lines, sha256 $(sha256sum drivers/cpufreq/e5-dvfs.c | cut -c1-16), handshake=$(grep -c 'firmware DVFS service' drivers/cpufreq/e5-dvfs.c)"
else
    echo "== drivers/cpufreq/e5-dvfs.c does NOT exist in the tree" >&2
fi
echo "== e5-dvfs files in the object tree:"
ls -la "$O"/drivers/cpufreq/e5-dvfs* 2>/dev/null | sed "s|^|   |" | head -6
echo "== what the compiled object actually contains:"
strings "$O/drivers/cpufreq/e5-dvfs.o" 2>/dev/null | grep -E "e5-dvfs:" | head -12 | sed "s|^|   |"
echo "== e5-dvfs mentions in build.log: $(grep -c e5-dvfs "$O/build.log" 2>/dev/null || echo 0)"
grep -E "e5-dvfs" "$O/build.log" 2>/dev/null | head -4 | sed "s|^|   |"
if [ -f "$dvfs" ]; then
    for s in "firmware DVFS service" "registered, %d cluster" "cooling device"; do
        strings "$dvfs" | grep -qF "$s" || {
            echo "e5-dvfs.ko is missing the string: $s (a stale object?)" >&2; exit 1; }
    done
    echo "== e5-dvfs.ko has the handshake and the cooling code ($(stat -c %s "$dvfs") bytes)"
fi

mkdir -p $DEST
cp "$O/arch/arm64/boot/Image" "$O/System.map" "$O/modules.builtin" "$O/modules.builtin.modinfo" $DEST/
cp "$O/.config" $DEST/config
python3 /work/wrap-image.py $DEST/Image $DEST/Image.lk
cat "$O/include/config/kernel.release" > $DEST/kernel.release
# the modules: flat for the boot image (boot/build-boot-image.py --modules), and as lib/modules/<release> for
# a root filesystem
rm -rf "$O/mod" $DEST/modules && mkdir -p $DEST/modules
make -s O="$O" ARCH=arm64 INSTALL_MOD_PATH="$O/mod" INSTALL_MOD_STRIP=1 modules_install
find "$O/mod/lib/modules" -name '*.ko' -exec cp {} $DEST/modules/ \;
tar -C "$O/mod" -cf $DEST/modules.tar lib/modules
# Docker creates these files as root on Linux bind mounts. The host must be
# able to add root-modules.tar and package the outputs after this container exits.
if [ -n "${E5_OUTPUT_UID:-}" ] && [ -n "${E5_OUTPUT_GID:-}" ]; then
    chown -R "$E5_OUTPUT_UID:$E5_OUTPUT_GID" "$DEST"
fi
echo "== modules: $(ls $DEST/modules | wc -l)"
echo "== $(cat $DEST/kernel.release): $(ls -la $DEST/Image.lk | awk '{print $5}') bytes"

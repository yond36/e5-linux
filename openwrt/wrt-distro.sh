# The distribution the E5's userspace is built from.  OpenWrt and ImmortalWrt
# are both 25.12-based and use apk; the tree is assembled from the release's
# own armsr/armv8 root filesystem and its feeds.
#
#   E5_WRT_DISTRO   openwrt | immortalwrt      (default openwrt)
#   E5_WRT_VER      the release, e.g. 25.12.5  (default: the one below)
#
# ImmortalWrt does not build OpenWrt's video feed -- the info screen runs on
# it (cage, cog, WPE WebKit, Mesa, Wayland); 25.12.2 publishes base, luci,
# packages, routing and telephony only.  The screen's graphics stack therefore
# comes from OpenWrt's video feed of the same release (E5_WRT_VIDEO_*, see
# build-rootfs.sh): both releases are built from the same tree with the same
# musl 1.2.5 and gcc 14.3, and the ImmortalWrt root filesystem carries
# OpenWrt's signing key (openwrt-25.12.pem), so that feed's packages install.
E5_WRT_DISTRO=${E5_WRT_DISTRO:-openwrt}
case "$E5_WRT_DISTRO" in
openwrt)
    E5_WRT_VER=${E5_WRT_VER:-25.12.5}
    E5_WRT_GIT=https://git.openwrt.org/openwrt/openwrt.git
    ;;
immortalwrt)
    E5_WRT_VER=${E5_WRT_VER:-25.12.2}
    E5_WRT_GIT=https://github.com/immortalwrt/immortalwrt.git
    ;;
*)
    echo "E5_WRT_DISTRO: openwrt or immortalwrt (not '${E5_WRT_DISTRO}')" >&2
    exit 1
    ;;
esac
# what this build is called in file names and the docker image tag
E5_WRT_NAME=e5-$E5_WRT_DISTRO
E5_WRT_DL=https://downloads.$E5_WRT_DISTRO.org/releases
E5_WRT_URL=$E5_WRT_DL/$E5_WRT_VER/targets/armsr/armv8
E5_WRT_TARBALL=$E5_WRT_DISTRO-$E5_WRT_VER-armsr-armv8-rootfs.tar.gz
E5_WRT_BASE_IMAGE=$E5_WRT_NAME-base:$E5_WRT_VER
# the buildroot of build-modemmanager.sh / build-bluez.sh, kept in a docker
# volume per distribution (a tree of one is not that of the other)
E5_WRT_SRC_VOLUME=$E5_WRT_NAME-src
# The OpenWrt release whose video feed carries the screen's graphics stack.
E5_WRT_VIDEO_VER=${E5_WRT_VIDEO_VER:-$E5_WRT_VER}
E5_WRT_VIDEO_DL=${E5_WRT_VIDEO_DL:-https://downloads.openwrt.org/releases}
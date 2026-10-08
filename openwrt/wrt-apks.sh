# The packages that are not in every feed, pinned by their checksum.
#
#  * the Argon theme: not in OpenWrt's feeds; jerrykuku's release packages are
#    architecture independent (E5_ARGON_URL);
#  * libgst1gl and gst1-mod-opengl: WPE WebKit links GStreamer's GL pieces, and
#    they are built only where Mesa is (OpenWrt's packages feed, not its video
#    feed, and in no ImmortalWrt feed at all);
#  * libwpewebkit and libmesa-panfrost: ImmortalWrt builds no video feed, so the
#    two largest packages the screen needs come from OpenWrt's, and they are the
#    responses the CDN truncates most often.
#
# When one of the feeds behind these is regenerated and a checksum no longer
# matches, update the line here: fetch_apk says which file, and downloads the
# release's index.json next to it (packages/aarch64_generic/{packages,video}/)
# shows the version the feed now has.
#
#   fetch_apk URL SHA256 FILE   download until the checksum matches, then stop
E5_ARGON_URL=https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.4.7
E5_ARGON_APKS="c5f0e3a55ef96213884184be9aeaadc8586418986c4dde1ff1866be5e938aaef luci-theme-argon-2.4.7-r1.apk
506e2bc4bef7d40fab051bb38902f71a8af0356ebe765f01b1808f6d2ce8bf8f luci-app-argon-config-2.4.7-r1.apk
00163d6b9d7f1fccae84bd220c6f3c9a4f78fe063b1d12408127d36bfe38dd7e luci-i18n-argon-config-zh-cn-26.103.13761.3e099a3.apk"
E5_GL_APKS="9c711e73dc5bb2f8aa5498a50381ec5a1edaa85ec02f82e0a42fd92453566129 libgst1gl-1.26.4-r1.apk
14172d6aac7edfb6a56f11a7ac81c1e4bed6dfcb5909d098256a00c79e44f101 gst1-mod-opengl-1.26.4-r1.apk"
E5_BIG_APKS="2163f60be7e01e7775d5cc5dcedb74c57064af7b5728e4de45a044f57b80c7f6 libwpewebkit-2.50.1-r1.apk
0f5b883f9ddfc7a75a71759e0d635b63eeb7da6d7c104a54103226ef15d94ae0 libmesa-panfrost-25.2.4-r2.apk"
# (the CDN truncates large responses now and then -- "end of response with N
# bytes missing", apk's "wget: exited with error 4" -- and a short file would
# only fail later, inside apk, after the whole install had been downloaded
# again: every pinned file is fetched until its checksum matches)
fetch_apk() {
    url=$1 sum=$2 out=$3
    n=0
    while :; do
        if [ -f "$out" ]; then
            got=$(shasum -a 256 "$out" 2>/dev/null | cut -d" " -f1 || sha256sum "$out" | cut -d" " -f1)
            [ "$got" = "$sum" ] && return 0
            rm -f "$out"
        fi
        n=$((n + 1))
        [ "$n" -le 10 ] || { echo "cannot fetch $url: checksum mismatch after $((n - 1)) tries" >&2; return 1; }
        echo "fetching $(basename "$out") (try $n)" >&2
        curl -fsSL --http1.1 --retry 3 --retry-all-errors -o "$out.part" "$url" || true
        [ -f "$out.part" ] && mv "$out.part" "$out"
        sleep 5
    done
}
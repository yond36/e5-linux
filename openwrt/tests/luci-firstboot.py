#!/usr/bin/env python3
"""The first boot's uci-defaults, on the base image, in the order they run.

init.d/boot's uci_apply_defaults runs /etc/uci-defaults/* by name; the E5's
93-e5-luci sets the LuCI language and theme before ImmortalWrt's own
99-default-settings, which resets luci.main.lang to auto unless its
system.@imm_init[0].lang marker is set -- and neither the section nor its
config file ships in the base: preinit's config_generate writes
/etc/config/system first.  This replays that exact sequence in a container of
the distribution's own root filesystem (E5_TEST_IMAGE, the release.yml
default) and asserts what is left: Chinese, the Argon theme, and, on
ImmortalWrt, the marker that keeps them.
"""
import os
from pathlib import Path
import subprocess
import tempfile

TOP = Path(__file__).resolve().parents[2]

SHELL = '''#!/bin/sh -eu
# what preinit does on the very first boot: /etc/config/system does not ship
[ -s /etc/config/network -a -s /etc/config/system ] || /bin/config_generate >/dev/null
mkdir -p /tmp/.uci
# init.d/boot's uci_apply_defaults: by name, each removed when it succeeds
cd /etc/uci-defaults
for file in $(ls); do
    if ( . "./$file" ); then rm -f "$file"; fi
done
uci commit
# the language and the theme the image was built to come up with
[ "$(uci -q get luci.main.lang)" = zh_cn ] || { echo "luci.main.lang is $(uci -q get luci.main.lang)" >&2; exit 1; }
[ "$(uci -q get luci.main.mediaurlbase)" = /luci-static/argon ] || { echo "mediaurlbase lost" >&2; exit 1; }
# ImmortalWrt's 99-default-settings: the marker keeps it from resetting the
# language, so the marker has to be there and auto must not have won
grep -q "^DISTRIB_ID='ImmortalWrt'$" /etc/openwrt_release || exit 0
[ "$(uci -q get system.@imm_init[0].lang)" = 1 ] || { echo "ImmortalWrt lang marker missing" >&2; exit 1; }
echo "first boot leaves LuCI in Chinese with the Argon theme"
'''

with tempfile.TemporaryDirectory(prefix='e5-firstboot-') as directory:
    root = Path(directory)
    (root / 'firstboot.sh').write_text(SHELL)
    overlay = TOP / 'openwrt/overlay/etc/uci-defaults/93-e5-luci'
    subprocess.run(['docker', 'run', '--rm',
                    '-v', f'{root}:/tests:ro',
                    '-v', f'{overlay}:/e5-93-e5-luci:ro',
                    os.environ.get('E5_TEST_IMAGE', 'e5-openwrt-base:25.12.5'),
                    '/bin/sh', '-eu', '-c',
                    'cp /e5-93-e5-luci /etc/uci-defaults/93-e5-luci && '
                    'exec /bin/sh /tests/firstboot.sh'], check=True)

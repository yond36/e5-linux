#!/usr/bin/env python3
"""A truncated image download must fail the install, not land on the card.

The installer streams `wget | gunzip | dd` straight into a card partition.
Without `set -o pipefail` a truncated download (the CDN drops long responses)
makes gunzip end early and dd still exits 0, so the card receives half an
image: every ext4 metadata checksum is wrong, the kernel refuses it at mount
("Checksum for group N failed", "no journal found"), and the generation it was
written as never boots.  That is the card corruption the project saw five
times and had not explained.

This runs the installer's own pipeline against a deliberately truncated
response and asserts it exits non-zero and records the failure.

E5_TEST_IMAGE (defaulting to the release's base image) is only used as a shell
to run the pipeline in; nothing else of it is needed.
"""
import functools
import gzip
import http.server
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading

TOP = Path(__file__).resolve().parents[2]
script = (TOP / 'openwrt/device-install-image.sh').read_text()
begin = script.index('# The download, the decompression and the write are one pipeline')
end = script.index('losetup -o $((start * 512))', begin)
pipeline = script[begin:end]
assert 'pipefail' in pipeline, 'the pipeline guard is gone'
MIB = 1 << 20


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory(prefix='e5-img-dl-') as directory:
    root = Path(directory)
    # a real (if small) image, and a response that stops in the middle of it
    image = b'I' * (8 * MIB)
    packed = gzip.compress(image)
    (root / 'image.ext4.gz').write_bytes(packed)
    (root / 'short.ext4.gz').write_bytes(packed[:len(packed) // 2])
    server = http.server.ThreadingHTTPServer(('0.0.0.0', 0),
                functools.partial(QuietHandler, directory=str(root)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f'http://host.docker.internal:{server.server_port}'
    card = root / 'disk'

    def attempt(name, success, output='/test/disk'):
        card.write_bytes(b'Z' * (8 * MIB))
        body = (
            'set -eu\n'
            'SRC=' + f'{url}/{name}' + '\n'
            f'disk={output}\n'
            'start=0\n'
            + pipeline +
            'echo PIPELINE-OK\n')
        script_file = root / (name.replace('.', '_') + '.sh')
        script_file.write_text(body)
        host_args = ['--add-host=host.docker.internal:host-gateway'] if sys.platform == 'linux' else []
        result = subprocess.run(
            ['docker', 'run', '--rm', *host_args, '-v', f'{root}:/test',
             os.environ.get('E5_TEST_IMAGE', 'e5-openwrt-base:25.12.5'),
             'sh', '/test/' + script_file.name],
            capture_output=True, text=True, timeout=60)
        ok = result.returncode == 0
        assert ok == success, (name, result.stdout, result.stderr)
        print(name, 'PASS' if success else 'REJECTED (as it must be)')

    try:
        attempt('image.ext4.gz', True)
        attempt('short.ext4.gz', False)
    finally:
        server.shutdown()
print('A truncated download can no longer be written as an image')

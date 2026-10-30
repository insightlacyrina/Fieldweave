#!/usr/bin/env python3
"""Independent 2x2 export/CamillaDSP verification; never opens audio devices.

Usage: python3 scripts/verify-fir-package.py FIR-PACKAGE [--camilla /usr/local/bin/camilladsp]
Input is a low-level left impulse and a later right impulse, making all four routes distinguishable.
"""
from __future__ import annotations
import argparse
import array
import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile


def read_float_wav(path: Path) -> tuple[int, list[float]]:
    data = path.read_bytes()
    assert data[:4] == b'RIFF' and data[8:12] == b'WAVE', path
    pos = 12
    fmt = samples = None
    while pos + 8 <= len(data):
        tag, size = struct.unpack_from('<4sI', data, pos)
        body = data[pos + 8:pos + 8 + size]
        if tag == b'fmt ':
            fmt = struct.unpack_from('<HHIIHH', body)
        if tag == b'data':
            samples = body
        pos += 8 + size + size % 2
    assert fmt and samples is not None
    codec, channels, rate, _, _, bits = fmt
    assert (codec, channels, bits) == (3, 1, 32), fmt
    return rate, list(struct.unpack('<' + 'f' * (len(samples) // 4), samples))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('--camilla', default='/usr/local/bin/camilladsp')
    args = parser.parse_args()
    package = args.package.resolve()
    filters = {name: read_float_wav(package / (name + '.wav')) for name in ('LL', 'LR', 'RL', 'RR')}
    rates = {v[0] for v in filters.values()}
    assert len(rates) == 1, rates
    rate = rates.pop()
    tap_count = max(len(v[1]) for v in filters.values())
    # Keep inputs asymmetrical and quiet. This fixture is offline only.
    right_offset = 791
    source_frames = 2048
    gain_left, gain_right = .007, -.011
    stimulus = array.array('d', [0.0] * (source_frames * 2))
    stimulus[0] = gain_left
    stimulus[right_offset * 2 + 1] = gain_right
    if sys.byteorder != 'little':
        stimulus.byteswap()
    with tempfile.TemporaryDirectory(prefix='fieldweave-matrix-verification-') as temporary:
        target = Path(temporary)
        for name in ('LL', 'LR', 'RL', 'RR'):
            shutil.copy2(package / (name + '.wav'), target / (name + '.wav'))
        shutil.copy2(package / 'camilladsp-offline.yml', target / 'camilladsp-offline.yml')
        (target / 'input.f64').write_bytes(stimulus.tobytes())
        result = subprocess.run([args.camilla, '-c', 'camilladsp-offline.yml'], cwd=target, text=True, capture_output=True, timeout=20)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        result = subprocess.run([args.camilla, '-l', 'warn', 'camilladsp-offline.yml'], cwd=target, text=True, capture_output=True, timeout=45)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        output = array.array('d')
        output.frombytes((target / 'camilla-output.f64').read_bytes())
        if sys.byteorder != 'little':
            output.byteswap()
    expected_frames = source_frames + tap_count - 1
    assert len(output) % 2 == 0
    actual_frames = len(output) // 2
    assert actual_frames >= expected_frames, (actual_frames, expected_frames)
    expected = [[0.0] * actual_frames for _ in range(2)]
    for route, ear, offset, gain in [('LL', 0, 0, gain_left), ('LR', 1, 0, gain_left), ('RL', 0, right_offset, gain_right), ('RR', 1, right_offset, gain_right)]:
        for i, value in enumerate(filters[route][1]):
            expected[ear][offset + i] += gain * value
    max_error = max(abs(output[frame * 2 + ear] - expected[ear][frame]) for ear in range(2) for frame in range(actual_frames))
    assert max_error <= 1e-10, max_error
    peak = max(abs(x) for x in output)
    assert math.isfinite(peak) and peak < 1
    print(json.dumps({'verified': True, 'sample_rate': rate, 'matrix_taps': tap_count, 'expected_frames': expected_frames, 'actual_frames': actual_frames, 'max_absolute_error': max_error, 'output_peak': peak, 'routes_verified': ['LL left→left', 'LR left→right', 'RL right→left', 'RR right→right'], 'audio_device_opened': False}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

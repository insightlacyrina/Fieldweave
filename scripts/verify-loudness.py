#!/usr/bin/env python3
"""Independently render the app-generated live pipeline through real CamillaDSP.

Requires numpy. Generate evidence packages with FIELDWEAVE_BALANCE_EVIDENCE=DIR
scripts/test.sh, then run this script with DIR. No audio device is opened.
"""
from pathlib import Path
import argparse
import json
import math
import subprocess
import tempfile
import numpy as np


def k_power(rate, size):
    frequencies = np.fft.rfftfreq(size, 1 / rate)
    z = np.exp(-2j * np.pi * frequencies / rate)
    k = math.tan(math.pi * 1681.974450955533 / rate)
    q, vh = 0.7071752369554196, 10 ** (3.999843853973347 / 20)
    vb = vh ** 0.4996667741545416
    a0 = 1 + k / q + k * k
    shelf = ((vh + vb * k / q + k * k) + 2 * (k * k - vh) * z
             + (vh - vb * k / q + k * k) * z * z) / a0
    shelf /= 1 + 2 * (k * k - 1) / a0 * z + (1 - k / q + k * k) / a0 * z * z
    k = math.tan(math.pi * 38.13547087602444 / rate)
    q = 0.5003270373238773
    a0 = 1 + k / q + k * k
    high = (1 - z) ** 2 / (1 + 2 * (k * k - 1) / a0 * z + (1 - k / q + k * k) / a0 * z * z)
    return np.abs(shelf * high) ** 2


def energy(audio, rate, size, weighted):
    spectrum = np.fft.rfft(audio, n=size, axis=0)
    weight = k_power(rate, size) if weighted else np.ones(size // 2 + 1)
    return float(np.sum(np.abs(spectrum) ** 2 * weight[:, None]))


def render(package, source, target, temporary, label):
    config = json.loads((package / "configuration.json").read_text())
    rate = config["sample_rate"]
    source_path, output_path = temporary / "input.f64", temporary / "output.f64"
    np.asarray(source, dtype="<f8").tofile(source_path)
    live = (package / "live.yml").read_text()
    tail = live[live.index("filters:\n"):]
    yaml = f"""devices:
  samplerate: {rate}
  chunksize: 512
  capture: {{type: RawFile, channels: 2, filename: '{source_path}', format: F64_LE, extra_samples: 131072}}
  playback: {{type: File, channels: 2, filename: '{output_path}', format: F64_LE}}
{tail}
"""
    yaml_path = temporary / "offline.yml"
    yaml_path.write_text(yaml)
    result = subprocess.run(["/usr/local/bin/camilladsp", "-l", "warn", str(yaml_path)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    output = np.fromfile(output_path, dtype="<f8").reshape(-1, 2)
    assert np.isfinite(output).all()
    ceiling = 10 ** (target["ceiling_dbfs"] / 20)
    peak = float(np.max(np.abs(output)))
    assert peak <= ceiling + 1e-10, (package.name, label, peak, ceiling)
    return output, peak


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    count = 131072
    rng = np.random.default_rng(9172401)
    frequencies = np.fft.rfftfreq(count, 1 / 48000)
    amplitude = np.where((frequencies >= 20) & (frequencies <= 20000), 1 / np.sqrt(np.maximum(frequencies, 1)), 0)
    left = amplitude * np.exp(1j * rng.uniform(-np.pi, np.pi, len(amplitude)))
    # Every frequency has equal channel power and 0.5 real correlation.
    right = left * (0.5 + 1j * math.sqrt(0.75) * np.where(np.arange(len(left)) % 2, 1, -1))
    pink = np.fft.irfft(np.stack([left, right], axis=1), n=count, axis=0)
    pink *= 0.01 / np.max(np.abs(pink))
    stress = np.zeros((16384, 2))
    stress[:8192] = rng.choice([-1.0, 1.0], (8192, 2))
    stress[8192:12288, 0] = 1
    stress[8192:12288, 1] = -1
    records = []
    with tempfile.TemporaryDirectory(prefix="fieldweave-loudness-") as folder:
        temporary = Path(folder)
        for package in sorted((args.evidence / "Packages").iterdir()):
            target = json.loads((package / "live-loudness.json").read_text())
            output, peak = render(package, pink, target, temporary, "pink")
            fft_size = 1 << (len(output) - 1).bit_length()
            measured = 10 * math.log10(energy(output, 48000, fft_size, True) / energy(pink, 48000, fft_size, True))
            error = measured - target["target_gain_db"]
            assert abs(error) < 0.35, (package.name, measured, error)
            _, stress_peak = render(package, stress, target, temporary, "full-scale stress")
            silence, _ = render(package, np.zeros((8192, 2)), target, temporary, "silence")
            assert np.max(np.abs(silence)) == 0
            record = dict(configuration=package.name, weighted_gain_db=measured,
                          target_gain_db=target["target_gain_db"], error_db=error,
                          calibration_db=target["filter_gain_db"], quiet_peak=peak,
                          full_scale_stress_peak=stress_peak, ceiling_dbfs=target["ceiling_dbfs"])
            records.append(record)
            print(f"{package.name}: error {error:+.3f} dB; stress peak {20 * math.log10(stress_peak):.2f} dBFS", flush=True)
    report = dict(verified=True, audio_device_opened=False, engine="CamillaDSP 4.1.3",
                  fixture="deterministic correlated pink stereo, full-scale transients and exact silence",
                  max_weighted_error_db=max(abs(r["error_db"]) for r in records), configurations=records)
    (args.evidence / "Offline-Verification.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()

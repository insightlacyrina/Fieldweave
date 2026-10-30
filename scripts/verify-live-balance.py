#!/usr/bin/env python3
"""Explicit quiet hardware verification. Quit the main app first.

Uses the timed audio CLI, which owns and restores its temporary audio routing.
Requires numpy; no physical device volume is changed.
"""
from pathlib import Path
import json
import select
import subprocess
import tempfile
import wave
import numpy as np


root = Path(__file__).resolve().parents[1]
evidence = root / "Documentation/Loudness-Balance-2026-10-29"
packages = evidence / "Packages"
with tempfile.TemporaryDirectory(prefix="fieldweave-live-balance-") as folder:
    source = Path(folder) / "quiet-pink.wav"
    count = 131072
    rng = np.random.default_rng(9172401)
    frequencies = np.fft.rfftfreq(count, 1 / 48000)
    amplitude = np.where((frequencies >= 20) & (frequencies <= 20000), 1 / np.sqrt(np.maximum(frequencies, 1)), 0)
    left = amplitude * np.exp(1j * rng.uniform(-np.pi, np.pi, len(amplitude)))
    right = left * (0.5 + 1j * np.sqrt(0.75) * np.where(np.arange(len(left)) % 2, 1, -1))
    pink = np.fft.irfft(np.stack([left, right], axis=1), n=count, axis=0)
    # The existing BlackHole system volume attenuates the capture substantially.
    # At that unchanged setting this yields about -48 dBFS capture peaks, quiet
    # enough for the headphones while keeping RMS above the balancer's noise gate.
    pink *= 0.08 / np.max(np.abs(pink))
    with wave.open(str(source), "wb") as writer:
        writer.setnchannels(2); writer.setsampwidth(2); writer.setframerate(48000)
        block = (pink * 32767).astype("<i2").tobytes()
        for _ in range(90):
            writer.writeframesraw(block)
    command = [str(root / ".build/debug/fieldweave-audio"), "run", str(packages / "Immersive/configuration.json"),
               "--capture", "BlackHole2ch_UID", "--playback", "AppleUSBAudioEngine:TTGK Technology:NICEHCK NK1 Ultra:1100000:1",
               "--seconds", "12", "--sequence", str(packages), "--support", str(evidence / "Live-Support"),
               "--report", str(evidence / "Live-Verification.json")]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    player = None
    try:
        if not select.select([process.stdout], [], [], 30)[0]:
            raise RuntimeError("Live startup timed out")
        first = process.stdout.readline()
        print(first, end="", flush=True)
        assert first.startswith("LIVE_READY"), first
        player = subprocess.Popen(["/usr/bin/afplay", "-v", "0.5", str(source)])
        with (evidence / "Live-CLI.log").open("w") as log:
            log.write(first)
            for line in process.stdout:
                log.write(line)
                if line.startswith("LIVE_"):
                    print(line, end="", flush=True)
        assert process.wait(timeout=10) == 0
        report = json.loads((evidence / "Live-Verification.json").read_text())
        assert not report["error"], report["error"]
        assert report["clipped_samples"] == 0
        assert report["original_output_uid"] == report["restored_output_uid"]
        assert len(report["measurements"]) == 14
        summary = []
        for measurement in report["measurements"]:
            last = [r for r in measurement["samples"] if r["seconds"] >= 10]
            assert len(last) >= 3, measurement
            error = float(np.mean([r["gain_db"] for r in last]) - measurement["target_gain_db"])
            name = Path(measurement["configuration"]).parent.name
            summary.append(dict(configuration=name, mean_error_db=error, last_trim_db=last[-1]["trim_db"]))
            print(f"{name}: measured steady error {error:+.3f} dB", flush=True)
            assert abs(error) < 0.8, (name, error)
        (evidence / "Live-Summary.json").write_text(json.dumps(dict(verified=True, clipped_samples=0,
            route_restored=True, max_mean_error_db=max(abs(r["mean_error_db"]) for r in summary), configurations=summary), indent=2) + "\n")
    finally:
        if player is not None and player.poll() is None:
            player.terminate(); player.wait(timeout=8)
        if process.poll() is None:
            process.terminate(); process.wait(timeout=8)

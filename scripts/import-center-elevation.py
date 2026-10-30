#!/usr/bin/env python3
"""Build the native elevation bank from pinned, verified full-direction donor HRIRs.

Development-only dependencies: numpy, h5py. Runtime processing remains native Swift.
No networking, arbitrary personal matching, per-ear normalization or audio routing.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import shutil
import struct
import h5py
import numpy as np

COMMIT = "04c6c172a4e80c795656811b0eebd493d56af3e7"
DONORS = {"c01": 35, "c02": 29, "c03": 32, "c04": 49, "c05": 60, "c06": 86, "c07": 13}
ROUTES = {"LL": (30, 0, "LS_LE.wav"), "LR": (30, 1, "LS_RE.wav"),
          "RL": (330, 0, "RS_LE.wav"), "RR": (330, 1, "RS_RE.wav")}


def float_wav(samples):
    body = np.asarray(samples, dtype="<f4").tobytes()
    return (b"RIFF" + struct.pack("<I", 36 + len(body)) + b"WAVEfmt "
            + struct.pack("<IHHIIHH", 16, 3, 1, 48000, 192000, 4, 32)
            + b"data" + struct.pack("<I", len(body)) + body)


def read_float_wav(file):
    data, offset = file.read_bytes(), 12
    while offset + 8 <= len(data):
        tag, size = struct.unpack_from("<4sI", data, offset)
        if tag == b"data":
            return np.frombuffer(data[offset + 8:offset + 8 + size], dtype="<f4")
        offset += 8 + size + size % 2
    raise ValueError(f"No WAV payload in {file}")


def at_azimuth(positions, irs, elevation, azimuth, ear):
    indices = np.flatnonzero(np.abs(positions[:, 1] - elevation) < 1e-6)
    assert len(indices) > 1
    ordered = sorted(indices, key=lambda index: float(positions[index, 0] % 360))
    angles = [float(positions[index, 0] % 360) for index in ordered]
    target = azimuth % 360
    for index, angle in zip(ordered, angles):
        if abs(angle - target) < 1e-6:
            return irs[index, ear].copy(), [{"index": int(index), "weight": 1.0, "position": positions[index].tolist()}]
    extended = list(zip(angles, ordered)) + [(angles[0] + 360, ordered[0])]
    if target < angles[0]: target += 360
    for (lower, lo), (upper, hi) in zip(extended, extended[1:]):
        if lower <= target <= upper:
            t = (target - lower) / (upper - lower)
            return irs[lo, ear] * (1-t) + irs[hi, ear] * t, [
                {"index": int(lo), "weight": 1-t, "position": positions[lo].tolist()},
                {"index": int(hi), "weight": t, "position": positions[hi].tolist()}]
    raise ValueError("Missing circular azimuth bracket")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path.home() / "Desktop/Personal-HRTF-Resources/source")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    target = args.project / "Sources/FieldWeaveCore/Resources/CenterElevation"
    target.mkdir(parents=True, exist_ok=True)
    profiles = []
    sources = []
    for code, donor in DONORS.items():
        source = args.source / "artifacts/iteration05/candidate-bank" / code
        candidate = json.loads((source / "candidate-manifest.json").read_text())
        sofa = source / "Calibration_Candidate_HRIR.sofa"
        actual = hashlib.sha256(sofa.read_bytes()).hexdigest()
        expected = candidate["sofa"]["hrir"]
        assert actual == expected["sha256"] and sofa.stat().st_size == expected["bytes"]
        with h5py.File(sofa, "r") as handle:
            assert float(handle["Data.SamplingRate"][0]) == 48000
            assert np.array_equal(handle["Data.Delay"][:], np.zeros((1, 2)))
            irs = np.asarray(handle["Data.IR"], dtype=np.float64)
            positions = np.asarray(handle["SourcePosition"], dtype=np.float64)
            assert handle["SourcePosition"].attrs["Type"].decode() == "spherical"
            assert "degree" in handle["SourcePosition"].attrs["Units"].decode()
        assert irs.shape == (440, 2, 418) and np.isfinite(irs).all()
        assert np.max(np.abs(positions[:, 2]-1.47)) < 1e-5
        entries = []
        for elevation in range(-50, 51, 10):
            paths, routing = {}, {}
            for name, (azimuth, ear, original_name) in ROUTES.items():
                samples, used = at_azimuth(positions, irs, elevation, azimuth, ear)
                stem = "zero" if elevation == 0 else ("up" if elevation > 0 else "down") + str(abs(elevation))
                relative = f"{code}/{stem}-{name}.wav"
                destination = target / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                if elevation == 0:
                    original = args.project / "Sources/FieldWeave/Resources/PersonalHRTF" / code / original_name
                    assert np.array_equal(samples.astype(np.float32), read_float_wav(original))
                    # Exact reuse preserves both coefficients and the existing source provenance.
                    shutil.copy2(original, destination)
                else:
                    destination.write_bytes(float_wav(samples))
                paths[name] = relative
                routing[name] = {"azimuth_degrees": azimuth if azimuth <= 180 else azimuth-360,
                                 "output_ear": ear, "source_measurements": used,
                                 "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}
            entries.append({"degrees": elevation, "paths": paths, "routing": routing})
        profiles.append({"id": code, "donor": f"pp{donor:02d}", "elevations": entries,
                         "source_sha256": actual, "listener_match_validated": False})
        sources.append({"id": code, "path": expected["path"], "sha256": actual, "bytes": expected["bytes"]})
    manifest = {"version": 1, "sample_rate": 48000, "repository": "insightlacyrina/Personal-HRTF", "commit": COMMIT,
                "license": "CC BY 4.0", "distance_metres": 1.47, "profiles": profiles,
                "interpolation": "Unshifted linear HRIR interpolation on the same elevation ring for azimuth; runtime interpolates neighbouring elevation rings. No ear-wise scaling or onset alignment.",
                "sources": sources, "measured_elevation_grid_degrees": list(range(-50, 51, 10)),
                "ui_range_degrees": [-45, 45], "listener_localization_validated": False}
    (target / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (target / "ATTRIBUTION.txt").write_text(
        "HUTUBS measured-donor elevation HRIR bank, CC BY 4.0.\n"
        "Brinkmann et al. (2019), A Cross-Evaluated Database of Measured and Simulated HRTFs Including 3D Head Meshes, Anthropometric Features, and Headphone Impulse Responses. JAES, doi:10.17743/jaes.2019.0024.\n"
        "HUTUBS dataset doi:10.14279/depositonce-8487.\n"
        f"48kHz converted source: insightlacyrina/Personal-HRTF, commit {COMMIT}.\n"
        "Derivation: FieldWeave selects same-donor +/-30 degree source directions at multiple elevations; unavailable azimuths use documented linear interpolation. No invented listener measurements or ear calibration.\n"
        "These are measured donor data, not measurements of this listener. Listener matching and elevation perception remain unvalidated.\n")
    summary = {"profiles": len(profiles), "wavs": len(profiles)*11*4, "sample_rate": 48000,
               "frames_per_wav": 418, "zero_degree_coefficients_exact": True, "sources": sources}
    evidence = args.project / "Documentation/Center-Elevation-2026-10-29"
    evidence.mkdir(parents=True, exist_ok=True)
    (evidence / "Data-Import.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({k: v for k, v in summary.items() if k != "sources"}))


if __name__ == "__main__":
    main()

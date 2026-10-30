#!/usr/bin/env python3
"""Verify pinned GitHub connector downloads and prepare FieldWeave HRIR resources.

The JSON input contains objects with path/content/encoding/sha from GitHub fetch_file.
Network access and live audio routing are deliberately outside this importer.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import shutil
import struct

REPOSITORY = "insightlacyrina/Personal-HRTF"
COMMIT = "04c6c172a4e80c795656811b0eebd493d56af3e7"
DONORS = {"c01": 35, "c02": 29, "c03": 32, "c04": 49, "c05": 60, "c06": 86, "c07": 13}
MAPPING = {"LL": "LS_LE.wav", "LR": "LS_RE.wav", "RL": "RS_LE.wav", "RR": "RS_RE.wav"}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def inspect_mono_wav(data: bytes) -> dict:
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("Not a RIFF WAV")
    offset = 12
    fmt = payload = None
    while offset + 8 <= len(data):
        name, size = struct.unpack_from("<4sI", data, offset)
        start = offset + 8
        chunk = data[start:start + size]
        if len(chunk) != size:
            raise ValueError("Truncated WAV chunk")
        if name == b"fmt ":
            fmt = struct.unpack_from("<HHIIHH", chunk)
        elif name == b"data":
            payload = chunk
        offset = start + size + (size & 1)
    if fmt != (3, 1, 48000, 192000, 4, 32) or payload is None:
        raise ValueError("Expected mono Float32 48kHz HRIR")
    samples = struct.unpack("<" + "f" * (len(payload) // 4), payload)
    if len(samples) != 418 or not all(float("-inf") < v < float("inf") for v in samples):
        raise ValueError("Expected 418 finite samples")
    return {"sample_rate": 48000, "channels": 1, "frames": len(samples), "peak": max(map(abs, samples))}


def native_configuration(code: str) -> dict:
    donor = DONORS[code]
    return {
        "version": 1, "sample_rate": 48000,
        "design": {"width_taps": 2049, "eq_taps": 4096, "max_matrix_taps": 65536,
                   "resample_policy": "reject", "tail_energy_tolerance": 0.000001},
        "headphone": {"mode": "bypass"},
        "width": {"interpolation": "pchip_log_hz", "points": [[20, 1], [250, 1], [1000, 1], [6000, 1], [20000, 1]]},
        "center_imaging": {"enabled": True, "pan": 0, "gain_db": 0},
        "externalization": {
            "mode": "matrix_ir", "kind": "measured_hrtf", "normalization": "none",
            "paths": {key: {"path": f"{code}/{filename}", "channel": 0} for key, filename in MAPPING.items()},
            "coordinates": {"convention": "SOFA spherical: azimuth positive left, elevation positive up, distance metres",
                            "left_source": [30, 0, 1.47], "right_source": [-30, 0, 1.47]},
            "provenance": (
                f"HUTUBS measured donor pp{donor:02d}, Personal-HRTF {code}, commit {COMMIT}. "
                "Measured DONOR binaural pair; NOT a measurement of this listener; listener match and localization benefit unvalidated. "
                "Brinkmann et al. (2019), JAES doi:10.17743/jaes.2019.0024; HUTUBS doi:10.14279/depositonce-8487. "
                "CC BY 4.0. Original Float32 48kHz four-path coefficients preserved; ±30 degrees, elevation 0, 1.47m. "
                "NICEHCK NK1 Ultra headphone EQ unavailable and bypassed."
            ),
        },
        "crossfeed": {"enabled": False},
        "safety": {"preamp_db": -3, "auto_headroom": True, "ceiling_dbfs": -1},
    }


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("payload", type=Path)
    parser.add_argument("--staging", type=Path, default=Path("/tmp/fieldweave-hrtf-resources"))
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    files = json.loads(args.payload.read_text())
    if isinstance(files, dict):
        files = files["files"]
    source = args.staging / "source"
    source.mkdir(parents=True, exist_ok=True)
    seen = set()
    records = []
    for entry in files:
        relative = Path(entry["path"])
        if relative.is_absolute() or ".." in relative.parts or str(relative) in seen:
            raise ValueError(f"Unsafe or duplicate source path {relative}")
        seen.add(str(relative))
        data = (base64.b64decode(entry["content"]) if entry["encoding"] == "base64"
                else entry["content"].encode("utf-8"))
        git_hash = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
        if git_hash != entry["sha"]:
            raise ValueError(f"Git blob hash mismatch: {relative}")
        destination = source / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        records.append({"path": str(relative), "bytes": len(data), "git_blob_sha": git_hash, "sha256": sha256(data)})

    bank = source / "artifacts/iteration05/candidate-bank"
    checked = []
    for code, donor in DONORS.items():
        manifest_path = bank / code / "candidate-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        if manifest["code"] != code or manifest["donor_subject_id"] != donor:
            raise ValueError(f"Wrong candidate identity: {code}")
        if manifest["sample_rate_hz"] != 48000 or manifest["samples"] != 418:
            raise ValueError(f"Unexpected HRIR layout: {code}")
        for product in manifest["products"]:
            path = source / product["path"]
            if path.exists():
                data = path.read_bytes()
                if len(data) != product["bytes"] or sha256(data) != product["sha256"]:
                    raise ValueError(f"Candidate manifest hash mismatch: {path}")
        for filename in MAPPING.values():
            path = bank / code / "renderer" / filename
            info = inspect_mono_wav(path.read_bytes())
            checked.append({"candidate": code, "path": filename, **info})

    manifest = {"repository": REPOSITORY, "commit": COMMIT, "files": records,
                "selection": "Seven fixed ±30-degree measured-donor four-path renderers and provenance. No personal measurement or NK1 Ultra correction.",
                "verification": {"all_git_blob_hashes_match": True, "candidate_product_sha256_matches": True,
                                 "coefficients_transformed": False, "listener_match_validated": False},
                "mono_wavs": checked}
    write_json(args.staging / "download-manifest.json", manifest)

    for target in [args.project / "Sources/FieldWeave/Resources/PersonalHRTF", args.project / "Examples/PersonalHRTF"]:
        target.mkdir(parents=True, exist_ok=True)
        for code in DONORS:
            dest = target / code
            dest.mkdir(parents=True, exist_ok=True)
            for filename in MAPPING.values():
                shutil.copy2(bank / code / "renderer" / filename, dest / filename)
            shutil.copy2(bank / code / "candidate-manifest.json", dest / "candidate-manifest.json")
            write_json(target / f"{code}.json", native_configuration(code))
        shutil.copy2(bank / "ATTRIBUTION.txt", target / "ATTRIBUTION.txt")
        write_json(target / "import-manifest.json", manifest)
        catalog = {"repository": REPOSITORY, "commit": COMMIT, "default_candidate": "c01",
                   "personalized_hrtf_validated": False, "headphone_eq": "bypass: no measured NK1 Ultra calibration",
                   "candidates": [{"id": c, "donor": f"pp{d:02d}", "configuration": f"{c}.json",
                                   "label": f"{c} · HUTUBS pp{d:02d}", "listener_match_validated": False}
                                  for c, d in DONORS.items()]}
        write_json(target / "catalog.json", catalog)
    print(json.dumps({"source_files": len(records), "verified_mono_wavs": len(checked), "commit": COMMIT,
                      "staging": str(args.staging), "configurations": list(DONORS)}))


if __name__ == "__main__":
    main()

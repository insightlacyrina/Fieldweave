#!/usr/bin/env python3
"""Explicit, quiet hardware smoke test; the timed CLI restores media routing."""
from pathlib import Path
import json, math, re, select, struct, subprocess, tempfile, wave

root = Path(__file__).resolve().parents[1]
report_dir = root / "Documentation/LiveAudio-2026-10-29"
report_dir.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="fieldweave-live-test-") as temporary:
    support = report_dir / "CLI-Support"
    probe = Path(temporary) / "probe.wav"
    with wave.open(str(probe), "wb") as writer:
        writer.setnchannels(2); writer.setsampwidth(2); writer.setframerate(48000)
        frames = bytearray()
        for i in range(48000 * 5):
            fade = max(0, min(1, i / 4800, (240000 - 1 - i) / 4800))
            frames.extend(struct.pack("<hh", int(32767 * .002 * fade * math.sin(2 * math.pi * 401 * i / 48000)), int(32767 * .0015 * fade * math.sin(2 * math.pi * 809 * i / 48000))))
        writer.writeframes(frames)
    command = [str(root / ".build/debug/fieldweave-audio"), "run", str(root / "Examples/PersonalHRTF/c01.json"), "--capture", "BlackHole2ch_UID", "--playback", "AppleUSBAudioEngine:TTGK Technology:NICEHCK NK1 Ultra:1100000:1", "--seconds", "10", "--support", str(support), "--report", str(report_dir / "CLI-Smoke.json")]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        if not select.select([process.stdout], [], [], 25)[0]:
            raise RuntimeError("Live startup did not respond")
        first = process.stdout.readline()
        print(first, end="", flush=True)
        if not first.startswith("LIVE_READY"):
            raise RuntimeError("Live startup failed: " + first)
        # Start only after the runtime has verified Running and switched media output.
        player = subprocess.Popen(["/usr/bin/afplay", "-v", "0.5", str(probe)])
        helper=root/".build/camilla-query"
        if helper.exists():
            receipt=json.loads((support/"LiveAudioRoute.json").read_text())
            process_command=subprocess.check_output(["ps","-p",str(receipt["processID"]),"-o","command="],text=True)
            port=re.search(r"-p (\d+)",process_command).group(1)
            snapshot=subprocess.run([str(helper),port],capture_output=True,text=True,timeout=10)
            (report_dir/"Raw-Meters.json").write_text(snapshot.stdout)
        player.wait(timeout=10)
        assert player.returncode==0
        output = process.communicate(timeout=20)[0]
        print(output, end="")
        if process.returncode:
            raise RuntimeError("Live runtime failed")
        result = json.loads((report_dir / "CLI-Smoke.json").read_text())
        assert result["capture_peak_dbfs"] > -100, "No captured test signal"
        assert result["playback_peak_dbfs"] > -100, "No processed output signal"
        assert result["clipped_samples"] == 0
        assert result["original_output_uid"] == result["restored_output_uid"]
        assert not result["error"]
        print("LIVE_CHAIN_VERIFIED")
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=8)

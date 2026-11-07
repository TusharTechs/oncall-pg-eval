#!/usr/bin/env python3
"""QA: transcribe each narration sentence with Whisper and flag sentences whose transcript diverges from the script."""
import json, pathlib, re, difflib, subprocess
import numpy as np
from faster_whisper import WhisperModel
HERE = pathlib.Path(__file__).parent
T = json.loads((HERE / "build/timings.json").read_text())
m = WhisperModel("base.en", device="cpu", compute_type="int8", cpu_threads=2)
norm = lambda s: re.sub(r"[^a-z0-9 ]", " ", s.lower().replace("-", " ")).split()
bad = []; n = 0
for sc in T["scenes"]:
    for j, s in enumerate(sc["sentences"]):
        wav = HERE / f"build/audio/{sc['id']}_{j}.wav"
        pcm = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(wav), "-ac", "1", "-ar", "16000", "-f", "f32le", "-"], capture_output=True, check=True).stdout
        segs, _ = m.transcribe(np.frombuffer(pcm, np.float32), language="en", beam_size=1, vad_filter=False)
        heard = " ".join(x.text.strip() for x in segs)
        a, b = norm(s["text"]), norm(heard)
        r = difflib.SequenceMatcher(None, a, b).ratio(); n += 1
        if r < 0.85: bad.append((round(r, 2), sc["id"], j, s["text"], heard))
print(f"{n} sentences checked; {len(bad)} below 0.85 similarity")
for r, sid, j, want, heard in sorted(bad):
    print(f"\n[{r}] {sid}#{j}\n  script: {want}\n  heard : {heard}")

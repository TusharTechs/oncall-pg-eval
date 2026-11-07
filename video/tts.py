#!/usr/bin/env python3
"""Synthesize narration sentence-by-sentence with macOS `say`, build per-scene + full audio, and exact timings.

  python3 tts.py [--voice Aman] [--values values.json]
Outputs build/audio/*.wav, build/narration.wav, build/timings.json, build/captions.srt
"""
import argparse, json, pathlib, re, subprocess, wave

HERE = pathlib.Path(__file__).parent
B = HERE / "build"; A = B / "audio"; A.mkdir(parents=True, exist_ok=True)
SR = 48000
KOKORO = None

# spoken form -> caption form (audio uses phonetic hints so the voice says names correctly)
DISPLAY = [("OnCall P G", "OnCall-PG"), ("A I ", "AI "), ("S Q L", "SQL"), ("L L M", "LLM"), ("I D E", "IDE"),
           ("public I D", "public ID"), ("Ticket H one", "Ticket H1"), ("GPT six point one Sol", "GPT-6.1 Sol"),
           ("Postgres seventeen", "Postgres 17"), ("eighty-seven and eighty-nine, out of eighty-nine", "87 and 89, out of 89"),
           ("five million", "5 million"), ("two hundred transactions", "200 transactions"),
           ("five hundred milliseconds", "500 milliseconds"), ("nine and a half seconds", "9.5 seconds"),
           ("fifty milliseconds", "50 milliseconds"), ("fifteen seconds", "15 seconds"),
           ("ninety-five percent", "95%"), ("ninety-six percent", "96%"), ("five runs out of five", "5 runs out of 5"),
           ("five times out of five", "5 times out of 5"), ("five out of five", "5 out of 5")]

def display(s):
    for a, b in DISPLAY: s = s.replace(a, b)
    return s

def to_wav(aiff, wav):
    subprocess.run(["nice", "-n", "19", "ffmpeg", "-loglevel", "error", "-y", "-threads", "1", "-i", str(aiff),
                    "-ac", "1", "-ar", str(SR), "-sample_fmt", "s16", str(wav)], check=True)

def frames(wav):
    with wave.open(str(wav)) as w: return w.readframes(w.getnframes())

def silence(sec): return b"\x00\x00" * int(SR * sec)

def srt_time(t):
    h, rem = divmod(t, 3600); m, s = divmod(rem, 60)
    return f"{int(h):02d}:{int(m):02d}:{int(s):02d},{int(round((s - int(s)) * 1000)):03d}"

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--voice"); ap.add_argument("--engine", choices=["kokoro", "say"]); ap.add_argument("--values", default=str(HERE / "values.json"))
    a = ap.parse_args()
    N = json.loads((HERE / "narration.json").read_text())
    vals = json.loads(pathlib.Path(a.values).read_text()) if pathlib.Path(a.values).exists() else {}
    engine = a.engine or N.get("engine", "say")
    voice = a.voice or (N.get("kokoro_voice", "af_heart") if engine == "kokoro" else N["voice"]); rate = str(N["rate"]); gap = N["gap_s"]; tail = N["scene_tail_s"]
    global KOKORO
    if engine == "kokoro":
        from kokoro_onnx import Kokoro   # open-source TTS (Apache-2.0), run with video/.venv/bin/python
        KOKORO = Kokoro(str(HERE / "models/kokoro-v1.0.onnx"), str(HERE / "models/voices-v1.0.bin"))
    full = b""; t = 0.0; timings = []; srt = []; k = 0
    for si, sc in enumerate(N["scenes"]):
        scene = {"id": sc["id"], "start": round(t, 3), "sentences": []}
        lead = 0.35 if si else 0.6
        full += silence(lead); t += lead
        for j, text in enumerate(sc["sentences"]):
            for key, v in vals.items():
                if isinstance(v, str): text = text.replace("{" + key + "}", v)
            if "{" in text: raise SystemExit(f"unfilled placeholder in scene {sc['id']}: {text}")
            aiff = A / f"{sc['id']}_{j}.aiff"; wav = A / f"{sc['id']}_{j}.wav"
            if engine == "kokoro":
                import soundfile as sf
                samples, ksr = KOKORO.create(text, voice=voice, speed=N.get("speed", 1.0), lang=N.get("lang", "en-us"))
                raw = A / f"{sc['id']}_{j}.k.wav"; sf.write(str(raw), samples, ksr); to_wav(raw, wav)
            else:
                subprocess.run(["nice", "-n", "19", "say", "-v", voice, "-r", rate, "-o", str(aiff), text], check=True)
                to_wav(aiff, wav)
            pcm = frames(wav); dur = len(pcm) / 2 / SR
            scene["sentences"].append({"text": display(text), "start": round(t, 3), "end": round(t + dur, 3)})
            k += 1; srt.append(f"{k}\n{srt_time(t)} --> {srt_time(t + dur)}\n{display(text)}\n")
            full += pcm; t += dur
            if j < len(sc["sentences"]) - 1: full += silence(gap); t += gap
        full += silence(tail); t += tail
        scene["end"] = round(t, 3); timings.append(scene)
    with wave.open(str(B / "narration.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(full)
    (B / "timings.json").write_text(json.dumps({"engine": engine, "voice": voice, "total": round(t, 3), "scenes": timings}, indent=1))
    (B / "captions.srt").write_text("\n".join(srt))
    print(f"engine={engine} voice={voice} total={t:.1f}s")
    for s in timings: print(f"  {s['id']:10s} {s['start']:6.1f} -> {s['end']:6.1f}  ({s['end'] - s['start']:4.1f}s)")

if __name__ == "__main__":
    main()

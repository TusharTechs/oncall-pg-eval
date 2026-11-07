#!/bin/bash
# Build the OnCall-PG demo video end to end from the real result files.
#   ./make_video.sh [--voice Aman] [--calib ../oncall-pg-eval/results/<calibration log>] [--from S --to S]  (slice for previews)
# Output: build/oncall-pg-demo.mp4 (1080p, 24 fps, H.264 + AAC, captions burned in) and build/captions.srt
set -euo pipefail
cd "$(dirname "$0")"
VOICE=""; CALIB=""; FROM=""; TO=""
while [ $# -gt 0 ]; do case "$1" in --voice) VOICE=$2; shift 2;; --calib) CALIB=$2; shift 2;; --from) FROM=$2; shift 2;; --to) TO=$2; shift 2;; *) echo "unknown $1"; exit 1;; esac; done
python3 -I values.py >/dev/null
OMP_NUM_THREADS=2 nice -n 19 .venv/bin/python -I tts.py ${VOICE:+--voice "$VOICE"} 2>&1 | grep -v -i warning | tail -1
python3 -I build_scenes.py ${CALIB:+--calib "$CALIB"}
FR=build/frames; OUT=build/oncall-pg-demo.mp4
if [ -n "$FROM" ]; then FR=build/frames_slice; OUT=build/slice_${FROM}-${TO}.mp4; fi
rm -rf -- "$FR"; mkdir -p "$FR"
nice -n 15 node render.js 24 "${FROM:-0}" "${TO:-}" "$FR" | tail -1
AUDIO_ARGS=(-i build/narration.wav)
[ -n "$FROM" ] && AUDIO_ARGS=(-ss "$FROM" -i build/narration.wav)
nice -n 15 ffmpeg -loglevel error -y -threads 3 -framerate 24 -i "$FR/%05d.jpg" "${AUDIO_ARGS[@]}" \
  -filter_complex "[1:a]apad=pad_dur=8,loudnorm=I=-16:TP=-1.5:LRA=11[a]" -map 0:v -map "[a]" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -tune stillimage -c:a aac -b:a 160k -ar 48000 \
  -movflags +faststart -shortest "$OUT"
ffprobe -v error -show_entries format=duration,size -of default=nw=1 "$OUT" | tr '\n' ' '; echo " -> $OUT"

# Demo video pipeline
The walkthrough video (https://youtu.be/NzbBMvh8AKo) is generated from the result files, so every number on screen and in the narration is computed, not typed.

```bash
cd video
npm install                                   # playwright-core (drives your installed Google Chrome)
uv venv --python 3.14 .venv && uv pip install --python .venv/bin/python -r requirements-video.txt
mkdir -p models && curl -L -o models/kokoro-v1.0.onnx https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx \
               && curl -L -o models/voices-v1.0.bin  https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
./make_video.sh --calib ../results/calibration_N5_20261107.txt     # -> build/oncall-pg-demo.mp4 (~5 min)
```
- `values.py` computes every spoken number from `../results`.
- `tts.py` synthesizes narration sentence by sentence (Kokoro `af_heart`), which gives exact caption timing.
- `build_scenes.py` injects real data into `scenes.template.html`. `render.js` renders 24 fps frames with headless Chrome, and ffmpeg encodes them.
- `asr_check.py` transcribes the narration with Whisper and flags any sentence that diverges from the script.

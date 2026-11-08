#!/bin/bash
# render-fast.sh — fast parallel render for a faceless-shorts project.
#   bash scripts/render-fast.sh <project-dir> [output.mp4] [--workers N] [--res 0.4] [--fps 24] [--range START END]
# How it is faster: the project is split into frame-exact chunks, each chunk is
# rendered in its own headless Chrome in parallel, at a lower 3D resolution
# (the 3D is rendered smaller and upscaled, so the video stays 1080x1920).
# Chunks are rendered video-only, concatenated, and the mix is muxed once
# at the end (sliced to the same range), so the audio is never cut or doubled.
# The normal single render (capture.mjs video) still works as before.
# --range renders only part of the video (useful to re-render a fixed section).
set -u
PROJ="${1:-}"; OUT="${2:-}"
shift 2 2>/dev/null || shift 1 2>/dev/null || true
[ -n "$PROJ" ] || { echo "usage: bash scripts/render-fast.sh <project-dir> [output.mp4] [--workers N] [--res 0.4] [--fps 24] [--range START END]"; exit 2; }
PROJ="$(cd "$PROJ" && pwd)"
[ -f "$PROJ/tools/capture.mjs" ] || { echo "no tools/capture.mjs in $PROJ"; exit 1; }
[ -f "$PROJ/data/cues.json" ] || [ -f "$PROJ/data/lines.json" ] || { echo "no data/cues.json or data/lines.json in $PROJ (run voice.py + words.py, or estimate.py, first)"; exit 1; }

RES=0.4; SHADOW=512; FPS=24; WORKERS=""; RSTART=""; REND=""
while [ $# -gt 0 ]; do case "$1" in
  --workers) WORKERS="${2:?}"; shift 2 ;;
  --res) RES="${2:?}"; shift 2 ;;
  --shadow) SHADOW="${2:?}"; shift 2 ;;
  --fps) FPS="${2:?}"; shift 2 ;;
  --range) RSTART="${2:?}"; REND="${3:?}"; shift 3 ;;
  *) echo "unknown option $1"; exit 2 ;;
esac; done

# Full duration (seconds) from the timing files.
FULL=$(python3 -c "import json
d = None
for f in ('$PROJ/data/cues.json', '$PROJ/data/lines.json'):
    try:
        d = json.load(open(f))['duration']; break
    except Exception:
        pass
print(d if d else '')" 2>/dev/null)
[ -n "$FULL" ] || { echo "could not read duration from data/cues.json"; exit 1; }
START="${RSTART:-0}"; END="${REND:-$FULL}"
DUR=$(python3 -c "print(float('$END') - float('$START'))")

# Workers: one Chrome per worker needs ~1100 MB (Chrome ~800 + ffmpeg ~200 + headroom).
# Size from RAM first, then CPUs. Never more than 3: SwiftShader already
# threads inside one Chrome, so extra workers add almost nothing on 4 CPUs.
NPROC=$(nproc 2>/dev/null || echo 2)
AVAIL=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}')
[ -n "$AVAIL" ] || AVAIL=4096
BY_RAM=$(( AVAIL / 1100 )); [ "$BY_RAM" -lt 1 ] && BY_RAM=1
[ "$BY_RAM" -gt 3 ] && BY_RAM=3
N="$BY_RAM"; [ "$N" -gt "$NPROC" ] && N="$NPROC"
[ -n "$WORKERS" ] && N="$WORKERS"
[ "$N" -lt 1 ] && N=1
[ "$N" -gt "$NPROC" ] && N="$NPROC"
echo "fast render: ${START}s-${END}s (${DUR}s), ${FPS} fps, res=${RES}, shadow=${SHADOW}, ${N} worker(s) (RAM available ${AVAIL} MB, ${NPROC} CPUs)"

# Frame-exact split of the range: total frames F, chunk k covers frames [f0, f1).
F=$(python3 -c "print(round(float('$DUR') * $FPS))")
OUT="${OUT:-$PROJ/renders/fast.mp4}"
case "$OUT" in /*) ;; *) OUT="$PROJ/$OUT" ;; esac
mkdir -p "$(dirname "$OUT")"

# Work on a copy without the mix, so chunks come out video-only.
# (The mix is muxed once at the end, sliced to the same range.)
TMP=$(mktemp -d /tmp/fs-fast-XXXXXX)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM
cp -r "$PROJ/." "$TMP/" && rm -f "$TMP/data/mix.wav" "$TMP/data/narration.wav" && rm -rf "$TMP/renders" "$TMP/review"
mkdir -p "$TMP/renders/.fast"
cd "$TMP" || exit 1

export CHROME="${CHROME:-}"
PIDS=""
for k in $(seq 0 $((N - 1))); do
  F0=$(( k * F / N )); F1=$(( (k + 1) * F / N ))
  A0=$(python3 -c "print(f'{float('$START') + $F0 / $FPS:.6f}')")
  A1=$(python3 -c "print(f'{float('$START') + $F1 / $FPS:.6f}')")
  SOFTWARE_GL=1 QS="&res=$RES&aa=0&shadow=$SHADOW" FPS=$FPS node tools/capture.mjs video "renders/.fast/chunk-$k.mp4" "$A0" "$A1" > "renders/.fast/chunk-$k.log" 2>&1 &
  PIDS="$PIDS $!"
done
FAIL=0
for p in $PIDS; do wait "$p" || FAIL=1; done
[ "$FAIL" = 0 ] || { echo "a chunk render failed; logs kept in $TMP/renders/.fast/chunk-*.log"; trap - EXIT INT TERM; exit 1; }
for k in $(seq 0 $((N - 1))); do [ -f "renders/.fast/chunk-$k.mp4" ] || { echo "missing renders/.fast/chunk-$k.mp4 (work dir kept in $TMP)"; trap - EXIT INT TERM; exit 1; }; done

# Concat the video streams (same codec, fps and size, so stream copy works).
: > renders/.fast/list.txt
for k in $(seq 0 $((N - 1))); do echo "file 'chunk-$k.mp4'" >> renders/.fast/list.txt; done
cd renders/.fast || exit 1
if ! ffmpeg -v error -y -f concat -safe 0 -i list.txt -map 0:v -c:v copy -movflags +faststart video-only.mp4; then
  echo "stream-copy concat failed, retrying with re-encode..."
  ffmpeg -v error -y -f concat -safe 0 -i list.txt -map 0:v -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -movflags +faststart video-only.mp4 || exit 1
fi
# Sanity check: the joined video must be as long as the range.
GOT=$(ffprobe -v error -show_entries format=duration -of csv=p=0 video-only.mp4)
python3 -c "import sys; sys.exit(0 if abs(float('$GOT') - float('$DUR')) < 0.5 else 1)" || { echo "concat length wrong: got ${GOT}s, want ${DUR}s"; exit 1; }

# Mux the mix once, sliced to the same range (or silence if the project has no mix yet).
if [ -f "$PROJ/data/mix.wav" ]; then
  ffmpeg -v error -y -i video-only.mp4 -ss "$START" -t "$DUR" -i "$PROJ/data/mix.wav" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart "$OUT" || exit 1
else
  ffmpeg -v error -y -i video-only.mp4 -f lavfi -i anullsrc=r=48000:cl=stereo -map 0:v -map 1:a -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart "$OUT" || exit 1
fi
echo "done: $OUT ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT") s)"

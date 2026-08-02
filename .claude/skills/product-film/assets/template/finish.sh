#!/bin/bash
# Mux video + score, extract a poster, decode-verify.
#   OUT=my-film.mp4 POSTER_T=6.8 bash finish.sh
set -e
cd "$(dirname "$0")"
FF="${FF:-$(python3 -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())')}"
OUT="${OUT:-product-film.mp4}"
DUR=$(python3 -c "import json,re;print(json.loads(re.sub(r'^window\.TIMING\s*=\s*|;\s*$','',open('timings.js').read().strip()))['duration'])")
POSTER_T="${POSTER_T:-$(python3 -c "print($DUR/2)")}"

if [ -f score.wav ]; then
  # No -shortest: score.py guarantees audio length == video length; a
  # mismatch is a bug to fix, not to truncate away.
  $FF -y -loglevel error -i film_video.mp4 -i score.wav \
      -c:v copy -c:a aac -b:a 176k -movflags +faststart "$OUT"
else
  cp film_video.mp4 "$OUT"
fi
$FF -y -loglevel error -ss "$POSTER_T" -i film_video.mp4 -frames:v 1 -q:v 3 poster.jpg
$FF -v error -i "$OUT" -f null -    # must print nothing
echo "wrote $OUT + poster.jpg (decode-verified)"

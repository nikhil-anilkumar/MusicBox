#!/bin/bash
# Generates one tagged 6-second test file per supported format into ./testmedia (needs ffmpeg).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p testmedia && cd testmedia

SRC='aevalsrc=0.25*sin(2*PI*261.6*t)+0.2*sin(2*PI*329.6*t)+0.2*sin(2*PI*392*t)*(0.5+0.5*sin(2*PI*2*t)):s=44100:d=6'
gen() {
  local out=$1; shift
  ffmpeg -nostdin -loglevel error -y -f lavfi -i "$SRC" "$@" \
    -metadata title="Test ${out%.*}" -metadata artist="MusicBox Test" -metadata album="Format Suite" "$out"
}
gen 01-mp3-stereo.mp3       -ac 2 -c:a libmp3lame -b:a 192k
gen 02-mp3-mono-22k.mp3     -ac 1 -ar 22050 -c:a libmp3lame -b:a 64k
gen 03-aac.m4a              -ac 2 -c:a aac -b:a 160k
gen 04-alac.m4a             -ac 2 -sample_fmt s16p -c:a alac
gen 05-wav.wav              -ac 2 -c:a pcm_s16le
gen 06-aiff.aiff            -ac 2 -c:a pcm_s16be
gen 07-caf.caf              -ac 2 -c:a pcm_s16le
gen 08-flac-16bit.flac      -ac 2 -sample_fmt s16 -c:a flac
gen 09-flac-24bit-96k.flac  -ac 2 -ar 96000 -sample_fmt s32 -c:a flac
gen 10-ogg-vorbis.ogg       -ac 2 -ar 48000 -c:a libvorbis -q:a 5
gen 11-aac-adts.aac         -ac 2 -c:a aac -b:a 128k
ls -1

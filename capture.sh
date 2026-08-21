#!/bin/sh
# Build the current Sanyo image, show it briefly, and save MAMEs final frame.
set -eu

base=app
seconds=${1:-3}
captures=captures

mkdir -p "$captures"
nasm -w-label-orphan "$base.asm" -o "$base.img" -l "$base.lst"
mame mbc55x \
  -flop1 "$(pwd)/$base.img" \
  -ramsize 256K -skip_gameinfo -window -ui_active \
  -seconds_to_run "$seconds" \
  -snapshot_directory "$(pwd)/$captures" \
  -snapname gsnake -snapview native -snapsize 640x200 -nosnapbilinear

echo "Screenshot: $captures/gsnake.png"

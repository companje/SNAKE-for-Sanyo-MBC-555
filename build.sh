base=app

set -e

nasm -w-label-orphan "$base.asm" -o "$base.img" -l "$base.lst"

if pgrep -x "mame" > /dev/null; then
  killall -9 mame
fi

image=$(pwd)/$base.img

mame mbc55x \
  -flop1 "$image" \
  -ramsize 256K -skip_gameinfo -window -ui_active \
  -nomaximize -resolution0 800x600 -prescale 2 -gamma 3 -contrast 1.5

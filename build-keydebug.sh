#!/bin/sh
set -eu

nasm -w-label-orphan keydebug.asm -o keydebug.img -l keydebug.lst
echo "Built: keydebug.img"

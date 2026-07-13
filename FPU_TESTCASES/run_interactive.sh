#!/bin/sh
set -eu

SRC="./KV260_FPU.c"
EXE="./KV260_FPU"

if [ ! -f "$SRC" ]; then
    echo "Missing $SRC"
    exit 1
fi

echo "Compiling KV260_FPU.c"
rm -f "$EXE"
gcc -O0 -g -Wall -Wextra -std=c11 -o "$EXE" "$SRC"

echo "Running interactive FPU program"
sudo "$EXE"

#!/bin/sh
set -eu

SUITE="${1:-all}"
SRC="./KV260_FPU_TESTCASES.c"
EXE="./KV260_FPU_TESTCASES"

if [ ! -f "$SRC" ]; then
    echo "Missing $SRC"
    exit 1
fi

echo "Compiling KV260_FPU_TESTCASES.c"
rm -f "$EXE"
gcc -O0 -g -Wall -Wextra -std=c11 -o "$EXE" "$SRC"

if command -v file >/dev/null 2>&1; then
    file "$EXE"
fi

echo "Running suite: $SUITE"
if command -v sudo >/dev/null 2>&1; then
    sudo -v
    sudo "$EXE" "$SUITE"
else
    "$EXE" "$SUITE"
fi

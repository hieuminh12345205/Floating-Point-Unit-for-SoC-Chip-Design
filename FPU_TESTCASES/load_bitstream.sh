#!/bin/sh
set -eu

BIT_FILE="./design_1_wrapper.bit"
BIT_NAME="$(basename "$BIT_FILE")"
FPGA_MANAGER="/sys/class/fpga_manager/fpga0"
FIRMWARE_DIR="/lib/firmware"

if [ ! -f "$BIT_FILE" ]; then
    echo "Missing $BIT_FILE"
    exit 1
fi

if [ ! -d "$FPGA_MANAGER" ]; then
    echo "Missing $FPGA_MANAGER"
    echo "This system does not expose Linux FPGA Manager."
    exit 1
fi

echo "Loading bitstream with Linux FPGA Manager: $BIT_NAME"
sudo -v
sudo cp "$BIT_FILE" "$FIRMWARE_DIR/$BIT_NAME"
printf '0\n' | sudo tee "$FPGA_MANAGER/flags" >/dev/null
printf '%s\n' "$BIT_NAME" | sudo tee "$FPGA_MANAGER/firmware" >/dev/null

echo "Done."

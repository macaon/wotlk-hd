#!/bin/sh
# Builds client/dinput8.dll (32-bit Windows) with the Zig toolchain in cache/ (see README).
set -e
cd "$(dirname "$0")"
ZIG="${ZIG:-../cache/zig-linux-x86_64-0.13.0/zig}"
"$ZIG" cc -target x86-windows-gnu -O2 -shared -o dinput8.dll dinput8.c dinput8.def
rm -f dinput8.lib dinput8.pdb
echo "built $(pwd)/dinput8.dll"

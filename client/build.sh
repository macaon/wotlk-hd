#!/bin/sh
# Builds client/dinput8.dll (32-bit Windows) with the Zig toolchain in cache/ (see README), with
# StormLib (MIT, fetched into cache/ at a pinned commit and compiled once) linked in, and SMAA's
# lookup tables (MIT, fetched likewise) for effects.cpp. Shaders: shaders.sh, into shaders.h.
set -e
export LC_ALL=C # the object files link in glob order, which follows the locale
cd "$(dirname "$0")"
ZIG="${ZIG:-../cache/zig-linux-x86_64-0.13.0/zig}"
STORMLIB=../cache/StormLib STORMLIB_COMMIT=44ebfbf
SMAA=../cache/smaa SMAA_COMMIT=71c806a
OBJ=../cache/stormlib-obj
if [ ! -d "$STORMLIB" ]; then
    git clone -q https://github.com/ladislav-zezula/StormLib.git "$STORMLIB"
    git -C "$STORMLIB" checkout -q "$STORMLIB_COMMIT"
fi
if [ ! -d "$SMAA" ]; then
    git clone -q https://github.com/iryoku/smaa.git "$SMAA"
    git -C "$SMAA" checkout -q "$SMAA_COMMIT"
fi
if [ ! -f "$OBJ/done" ]; then
    rm -rf "$OBJ" && mkdir -p "$OBJ"
    (cd "$STORMLIB" && ls src/adpcm/adpcm.cpp src/huffman/huff.cpp src/jenkins/lookup3.c src/lzma/C/LzFind.c \
        src/lzma/C/LzmaDec.c src/lzma/C/LzmaEnc.c src/pklib/explode.c src/pklib/implode.c src/sparse/sparse.cpp \
        src/FileStream.cpp src/SBase*.cpp src/SCompression.cpp src/SFile*.cpp src/SMemUtf8.cpp \
        src/LibTomCrypt.c src/LibTomMath.c src/LibTomMathDesc.c src/zlib/*.c src/bzip2/*.c) |
        grep -v compress_zlib | while read -r f; do
        case $f in *.cpp) cc="c++ -fno-exceptions" ;; *) cc=cc ;; esac
        echo "$ZIG $cc -target x86-windows-gnu -O2 -D_7ZIP_ST -DBZ_STRICT_ANSI -w -c $STORMLIB/$f -o $OBJ/$(echo "$f" | tr / _).o"
    done | xargs -P"$(nproc)" -I{} sh -c '{}'
    touch "$OBJ/done"
fi
"$ZIG" c++ -target x86-windows-gnu -O2 -shared -w -I "$STORMLIB/src" -o dinput8.dll dinput8.c mpq.c faces.c effects.cpp portraits.c npcitems.c lua.c controls.c nameplates.c dinput8.def \
    "$OBJ"/*.o -lwininet
rm -f dinput8.lib dinput8.pdb
echo "built $(pwd)/dinput8.dll"

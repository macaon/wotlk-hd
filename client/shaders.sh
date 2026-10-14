#!/bin/sh
# Compiles post.hlsl into shaders.h (committed: build.sh does not need this). Needs Microsoft's
# d3dcompiler_47.dll, taken from the Windows SDK as winetricks does (build time only, not shipped),
# and a Wine to run it: Proton's by default.
set -e
cd "$(dirname "$0")"
ZIG="${ZIG:-../cache/zig-linux-x86_64-0.13.0/zig}"
WINE="${WINE:-$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-7-x86_64/files/bin/wine}"
FXC=../cache/fxc
mkdir -p "$FXC"
if [ ! -f "$FXC/d3dcompiler_47.dll" ]; then
    curl -fsSL -o "$FXC/sdk.cab" https://download.microsoft.com/download/B/0/C/B0C80BA3-8AD6-4958-810B-6882485230B5/standalonesdk/Installers/2630bae9681db6a9f6722366f47d055c.cab
    7z e -y -o"$FXC" "$FXC/sdk.cab" fila319f706acfa16d6707473ebf29bdc7f >/dev/null
    mv "$FXC/fila319f706acfa16d6707473ebf29bdc7f" "$FXC/d3dcompiler_47.dll"
    rm "$FXC/sdk.cab"
fi
if [ ! -d ../cache/smaa ]; then
    git clone -q https://github.com/iryoku/smaa.git ../cache/smaa
    git -C ../cache/smaa checkout -q 71c806a
fi
"$ZIG" cc -target x86-windows-gnu -O2 -o "$FXC/fxc.exe" fxc.c
rm -f "$FXC/fxc.pdb"
cp post.hlsl "$FXC/"
cp ../cache/smaa/SMAA.hlsl "$FXC/"
(cd "$FXC" && WINEPREFIX="$(pwd)/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="d3dcompiler_47=n" "$WINE" fxc.exe shaders.h post.hlsl \
    quad_vs quad_vs vs_3_0 \
    smaa_edges_vs smaa_edges_vs vs_3_0 smaa_weights_vs smaa_weights_vs vs_3_0 smaa_blend_vs smaa_blend_vs vs_3_0 \
    smaa_edges_ps smaa_edges_ps ps_3_0 smaa_weights_ps smaa_weights_ps ps_3_0 smaa_blend_ps smaa_blend_ps ps_3_0 \
    cas_ps cas_ps ps_3_0 depth_ps depth_ps ps_3_0 \
    ao_ps ao_ps ps_3_0 ao_blur_ps ao_blur_ps ps_3_0 ao_apply_ps ao_apply_ps ps_3_0 ao_view_ps ao_view_ps ps_3_0)
mv "$FXC/shaders.h" shaders.h
echo "built $(pwd)/shaders.h"

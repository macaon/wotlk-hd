#!/bin/sh
# The container's entry point (Dockerfile): the whole build into the mounted client, or the command
# given instead (docker run ... wotlk-hd python3 ui.py).
set -e
cd /src
if [ "$#" -gt 0 ]; then
    exec "$@"
fi
[ -f "$WOW_DIR/Wow.exe" ] || { echo "no Wow.exe in the client mounted at $WOW_DIR" >&2; exit 1; }
mkdir -p cache
[ -f cache/listfile.csv ] || curl -sfLo cache/listfile.csv \
    https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv
python3 build.py
python3 chars.py
python3 ui.py
client/build.sh
python3 patch_exe.py
python3 install.py 4 6 # the numbered patches, which install.py adds only by name
python3 install.py     # the per-race patches and the addon
cp client/dinput8.dll "$WOW_DIR/"
echo "Done: start Wow-hd.exe (under Wine or Proton with WINEDLLOVERRIDES=dinput8=n,b)."

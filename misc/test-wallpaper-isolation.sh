#!/usr/bin/env bash
set -euo pipefail
bin=$(realpath "${1:-target/lule}")
png=$(realpath resources/LOGO.png)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/out"
if [ -n "${2:-}" ]; then
    svg=$(realpath "$2")
else
    svg="$tmp/logo.svg"
    printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50"><path d="M0 0H100V50H0Z" fill="#ff0000"/></svg>' > "$svg"
fi
for logo in svg png; do
    bwrap --unshare-all --die-with-parent --tmpfs / \
        --ro-bind "$bin" /lule --ro-bind "$svg" /logo.svg --ro-bind "$png" /logo.png \
        --bind "$tmp/out" /out --chdir /out --clearenv --setenv PATH /missing \
        /lule wallpaper --logo="/logo.$logo" --size=40 --color=80b8cd --style=honey \
        --seed=42 --width=1280 --height=800 --output="/out/$logo.png"
    test -s "$tmp/out/$logo.png"
    file "$tmp/out/$logo.png" | grep -q 'PNG image data, 1280 x 800'
done
echo 'isolation: PNGs from SVG and PNG logos; no host filesystem, tools, libraries, or network'

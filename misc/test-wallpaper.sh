#!/usr/bin/env bash
set -euo pipefail
bin=$(realpath "${1:-target/lule}")
logo=$(realpath resources/LOGO.png)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

cat > logo.svg <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50"><path d="M0 0H100V50H0Z" fill="#ff0000"/></svg>
SVG
env -i PATH=/nonexistent "$bin" wallpaper --logo="$tmp/logo.svg" --size=40 --color=80b8cd \
    --seed=42 --width=320 --height=200 --output=standalone-svg.png
env -i PATH=/nonexistent "$bin" wallpaper --logo="$logo" --size=40 --color=80b8cd \
    --seed=42 --width=320 --height=200 --output=standalone-png.png
test -s standalone-svg.png
test -s standalone-png.png
mkdir standalone
mv standalone-*.png standalone/

printf '%s\n35\n' "$logo" | "$bin" wallpaper >interactive.log 2>prompts.log
test "$(find . -maxdepth 1 -name '*.png' | wc -l)" -eq 1
test "$(grep -o 'Logo path\|Logo size' prompts.log | wc -l)" -eq 2
! grep -q 'Background color' prompts.log
test "$(find . -maxdepth 1 -name '*.svg' | wc -l)" -eq 1

"$bin" wallpaper --list-patterns > patterns.txt
test "$(sort -u patterns.txt | wc -l)" -eq "$(wc -l < patterns.txt)"
while IFS= read -r style; do
    "$bin" wallpaper --logo "$logo" --size 35 --color '#80b8cd' \
        --style "$style" --seed 42 --width 320 --height 200 --output "$style.png"
    test -s "$style.png"
done < patterns.txt

"$bin" wallpaper --logo="$logo" --size=35 --color=abc --seed=42 --format=svg --output=one.svg
"$bin" wallpaper --logo="$logo" --size=35 --color=abc --seed=42 --format=svg --output=two.svg
cmp one.svg two.svg
"$bin" wallpaper --logo="$logo" --size=35 --seed=73 --width=320 --height=200 \
    --output=random-color.png </dev/null 2>random-prompts.log
test -s random-color.png
test ! -s random-prompts.log
"$bin" wallpaper --logo="$logo" --size=35 --seed=73 --format=svg --output=random-one.svg </dev/null
"$bin" wallpaper --logo="$logo" --size=35 --seed=73 --format=svg --output=random-two.svg </dev/null
cmp random-one.svg random-two.svg
if "$bin" wallpaper --logo="$logo" --size=35 --color=abc --seed=42 --format=svg --output=one.svg; then
    echo 'existing file overwritten' >&2; exit 1
fi
if "$bin" wallpaper </dev/null; then echo 'EOF accepted' >&2; exit 1; fi
if "$bin" wallpaper --logo="$logo" --size=nan --color=abc; then echo 'NaN accepted' >&2; exit 1; fi
test "$(find . -maxdepth 1 -name '.lule-wallpaper-*' | wc -l)" -eq 0
echo 'wallpaper smoke: standalone SVG/PNG logos, one interactive output, all patterns, deterministic SVG, safe failures'

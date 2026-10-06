#!/usr/bin/env bash
set -euo pipefail
bin=$(realpath "${1:-target/lule}")
out=${2:-target/pattern-gallery}
logo=$(realpath "${3:-resources/LOGO.png}")
mkdir -p "$out"
"$bin" wallpaper --list-patterns > "$out/patterns.txt"
printf '%s\n' '<!doctype html><meta charset="utf-8"><title>Lule pattern gallery</title><style>body{background:#222;color:#eee;font:16px sans-serif;display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px;padding:16px}figure{margin:0}img{width:100%}figcaption{padding:8px}</style>' > "$out/index.html"
while IFS= read -r style; do
    env -i PATH=/nonexistent "$bin" wallpaper --logo="$logo" --size=40 --color=80b8cd \
        --style="$style" --seed=42 --width=960 --height=600 --output="$out/$style.png"
    printf '<figure><img src="%s.png"><figcaption>%s</figcaption></figure>\n' "$style" "$style" >> "$out/index.html"
done < "$out/patterns.txt"
echo "gallery: $out/index.html"

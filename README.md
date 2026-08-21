

<img align="right" width="26%" src="./resources/LOGO.png">

lule
===

A command line tool to generate 8bit ANSI colors from wallpaper (an enhanced version of pywal but in V)
There is the old bash version in: https://github.com/warpwm/lule_bash

```
lule create -- set
```
<hr>

![](./resources/a_gif.gif)

<hr>

## Features

In order for lule to work properly, you need to set the following environment variables:
- `LULE_W` : The path to the wallpaper (one random image will be selected from this directory)
- `LULE_S` : The path to the script that will be run after the colors are generated
(please check the 'scripts/apply_colors.sh' file for an example)

```
export LULE_W="~/.wallpaper"
export LULE_S="~/.func/lule_colors.sh"

lule create -- set
```
## Building

```
nix develop --command oslo make build
```

One statically linked binary at `target/lule`, with no runtime dependencies. Without nix, any V
toolchain and a C compiler will do:

```
v -prod -cflags -static src/ -o target/lule
```

`oslo make` lists the rest — `dev`, `test`, `verify`, `install`, `docs`, `release`.

## Environment

| variable | what |
|---|---|
| `LULE_W` | directory to pick a wallpaper from at random |
| `LULE_S` | script to run once the colors are generated |
| `LULE_C` | directory holding named color schemes |
| `LULE_A` | directory to write the color cache into |
| `LULE_STDIN_MS` | how long to wait for a piped scheme (default 250ms) |

## Tuning the palette

Every knob applies to the six colors chosen from the wallpaper, and the rest of the scheme is
derived from those — so the background stays dark on a dark theme however hard you push.

```
lule create --saturation=-1.0 -- set     # greyscale
lule create --saturation=0.5 -- set      # half again as vivid
lule create --illumination=0.2 -- set    # lighter
lule create --hue=180 -- set             # rotate round the wheel
lule create --blend=0.6 -- set           # pull everything toward the accent
lule create --sort=hue -- set            # choose the accent by hue rather than dominance
```

`--sort` takes `dominance` (default), `hue`, `light`, `dark` or `chroma`.

### Reproducible schemes

The gradients are randomised, so the same wallpaper gives a different scheme each time. `--seed`
fixes both the palette extraction and the ramps, which is what lets two machines agree:

```
lule create --image=~/wall.png --seed=42 -- set
```

### Named schemes

A file of hex colors in `$LULE_C`, one per line, `#`-comments ignored — used instead of extracting
from the wallpaper:

```
$ cat ~/.config/lule/gruvbox
# gruvbox dark
#cc241d
#98971a
#d79921

$ lule create --scheme=gruvbox -- set
```

## Output

```
lule colors -- ansii     # the 256 swatches
lule colors -- list      # each color with its rgb, hsl, lab and lch values
lule colors -- image     # the wallpaper, in the terminal
lule colors -- mix       # both
lule colors -- json      # the scheme as json, for other tools
lule colors | ...        # piped: one hex color per line
```

## Daemon

```
lule daemon -- detach          # background it, cycling every 300s
lule daemon --loop=600 -- start # foreground
lule daemon -- next            # skip to another wallpaper
lule daemon -- status          # is one running?
lule daemon -- stop
```

Only one daemon runs at a time; a second refuses to start rather than fighting the first over the
control pipe.

## Running nothing

`lule create -- set` runs whatever `$LULE_S` names, and that list is remembered in the cached
scheme — so clearing the variable does not stop it. `--no-scripts` (or `-n`) does:

```
lule create -n --image=~/wall.png -- set
```

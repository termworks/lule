

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

## Templates

A template is any file with placeholders; `--pattern=IN:OUT` renders `IN` over `OUT`. The syntax
follows [matugen](https://github.com/InioX/matugen)'s, so templates read much the same either way.

### Values

`color0` … `color255`, plus `background`, `foreground`, `cursor`, `accent`, and the string values
`wallpaper` and `theme`. `dark` and `light` are booleans. `colors` and `pigments` are lists.

A bare `{{ color1 }}` prints hex **without** the leading `#`, which is what it has always done —
existing templates write `'#{{ color1 }}'` and supply their own.

### Colour formats

```
{{ accent.hex }}            #3f51b5
{{ accent.hex_stripped }}   3f51b5
{{ accent.hex_alpha }}      #3f51b5ff
{{ accent.rgb }}            rgb(63, 81, 181)
{{ accent.rgba }}           rgba(63, 81, 181, 1.00)
{{ accent.hsl }}            hsl(230, 48%, 48%)
{{ accent.red }} {{ accent.green }} {{ accent.blue }} {{ accent.alpha }}
{{ accent.hue }} {{ accent.saturation }} {{ accent.lightness }} {{ accent.luminance }}
```

### Filters

Values stay colours between stages, so filters chain:

```
{{ accent | lighten: 0.2 | grayscale }}
```

| | |
|---|---|
| colour | `lighten` `darken` `saturate` `desaturate` `rotate` `grayscale` `invert` `complement` |
| set | `set_hue` `set_saturation` `set_lightness` `set_alpha` |
| combine | `mix: "#ff0000", 0.5` |
| readable | `contrast` — black or white, whichever reads against the input |
| text | `upper` `lower` `trim` `capitalize` `replace: "a", "b"` `default: "fallback"` |
| case | `snake_case` `kebab_case` `camel_case` `pascal_case` |

A literal works as the input too: `{{ "#3f51b5" | lighten: 0.1 }}`.

The case filters take the input apart whatever convention it arrived in, so `helloWorld`,
`hello-world` and `HELLO_WORLD` all snake_case to `hello_world`. A run of capitals stays one word
until the last of them (`XMLHttpRequest` becomes `xml_http_request`), and digits stay attached to
the word before them, so `color0` does not become `color_0`.

`upper_case`, `lower_case` and the `_case` names are matugen's spellings and work here too.

### Conditionals and loops

```
<* if dark *>set background dark<* else *>set background light<* endif *>
<* if theme == "dark" *>…<* endif *>
<* if not light *>…<* endif *>

<* for c in colors *>{{ c.hex }}<* if not loop_last *>, <* endif *><* endfor *>
```

Inside a loop, `loop_index`, `loop_first` and `loop_last` are available.

### Includes

```
<* include "partial.conf" *>
```

The path is resolved **beside the file the include appears in**, not beside wherever lule was
run from, so a partial next to its template is just its name. The content is spliced into the
tree rather than rendered separately, which means an include inside a loop can use the loop
variable:

```
<* for c in colors *><* include "row.conf" *><* endfor *>
```

A file may be included any number of times, but a file that ends up including itself is refused
and reported - including when the cycle only shows up after the paths are resolved, so
`sub/../sub/x.conf` and `sub/x.conf` are recognised as the same file. Nesting stops at 16 deep.

### When something is wrong

An unknown name, field or filter is reported on stderr and the placeholder is **left in the
output** rather than replaced with nothing — a config full of blanks is harder to diagnose than
one that still shows what failed.

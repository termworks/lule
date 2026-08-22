

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

```
export LULE_W="~/.wallpaper"

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

## Templates that ship

`templates/` holds one per *format*, not per application - a css file themes anything that reads
css, an ini file anything that reads ini:

```
colors.sh  colors.css  colors.scss  colors.ini  colors.toml  colors.json  colors.Xresources
```

Point a template at wherever the program expects it:

```toml
[templates.gtk]
input  = "~/.config/lule/templates/colors.css"
output = "~/.config/gtk-4.0/colors.css"
```

They use `ansi`, which is the sixteen terminal colours - `colors` is all 256:

```
<* for c in ansi *>--color{{ loop_index }}: {{ c.hex }};
<* endfor *>
```

## Configuration

Put `init.lua` in `~/.config/lule/` (or `$LULE_C/`). It requires the `lule` module and hands
`setup` a table, the same shape the sibling tools use.
`resources/init.example.lua` is a commented starting point.

```lua
local lule = require("lule")

-- One list drives every path. This is the reason to write the config in Lua rather than toml:
-- adding an application is a word, not six lines.
local apps = { "kitty", "waybar", "rofi" }
local templates = {}
for _, app in ipairs(apps) do
  templates[#templates + 1] = lule.template(app, {
    input  = "~/.config/lule/templates/colors.ini",
    output = "~/.config/" .. app .. "/colors.ini",
  })
end

return lule.setup({
  settings  = { theme = "dark", contrast = "aa", palette = "pigment" },
  templates = templates,
})
```

`lule.template(name, spec)` only tags the table with a name, so a warning can say *which* template
is wrong; a bare `{ input = …, output = … }` is just as valid. Templates are a list, so the order
in the file is the order they render in.

Precedence runs **file, then environment, then flags** - a flag always wins. `~` is expanded by
lule, since nothing in a config file passes through a shell. `--pattern` *adds to* what the file
lists rather than replacing it.

A broken config stops the run rather than falling back to defaults, and Lua names the file and
line: `init.lua:12: syntax error near '='`. Carrying on would quietly apply a scheme you did not
ask for, over the top of the one you had.

A `config.lua` is read under the older name, and a `config.toml` when there is no Lua config at
all. Same keys, no loops.

### Doing things once the colours exist

`after` runs once the colours, the cache and the templates are all done. It is where a
post-generation shell script would otherwise go.

```lua
after = function(c)
  lule.mkdir("~/.cache/wal")
  lule.write("~/.cache/wal/colors", table.concat(c.colors, "\n"))

  -- escape sequences down every open terminal: recolours a running shell in place
  local esc = string.char(27)
  local seq = esc .. "]11;" .. c.background .. esc .. "\\"
  for i, hex in ipairs(c.ansi) do
    seq = seq .. esc .. "]4;" .. (i - 1) .. ";" .. hex .. esc .. "\\"
  end
  lule.ttys(seq)

  lule.run("hyprctl hyprpaper wallpaper ',' .. c.wallpaper .. ','")
  lule.spawn("zedtheme")
end
```

`c` is the finished scheme: `c.colors` (all 256), `c.ansi` (the sixteen), `c.background`,
`c.foreground`, `c.cursor`, `c.accent`, `c.wallpaper`, `c.theme`, `c.cache`. Lists count from one,
so `c.colors[1]` is colour 0.

| | |
|---|---|
| files | `lule.write(path, text)` `lule.append(path, text)` `lule.read(path)` `lule.copy(from, to)` `lule.mkdir(path)` |
| commands | `lule.run(cmd)` returns its exit status; `lule.spawn(cmd)` does not wait |
| terminals | `lule.ttys(text)` writes to every open pty, and answers how many |
| environment | `lule.env(name)` |

Paths take `~`. `lule.read` and `lule.env` answer `nil` when there is nothing there, so
`lule.read(p) or "default"` reads the way it looks. A failing hook is reported and the run stands:
the colours are already written by then, and throwing them away would be worse.

## Environment

| variable | what |
|---|---|
| `LULE_W` | directory to pick a wallpaper from at random |
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

### Readability

The sixteen ANSI colours are held to a minimum WCAG contrast against the background, so no slot
comes out too dim to read. Measured before this existed, 3 to 5 of the 15 fell below AA on real
wallpapers.

```
lule create -- set                       # AA (4.5:1), the default
lule create --contrast=aaa -- set        # 7:1
lule create --contrast=3.0 -- set        # a ratio of your own
lule create --contrast=none -- set       # off, colours exactly as extracted
```

Only lightness moves, and only as far as it has to, so hues survive. Colour 0 is the background
everything is measured against and the ramps past 15 are gradients rather than text, so both are
left alone.

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

### Arithmetic

```
{{ 2 + 3 * 4 }}        14 - precedence, not left to right
{{ (2 + 3) * 4 }}      20
{{ 5 / 2 }}            2.5 - whole results print as integers
{{ count * 2 + 1 }}    names holding numbers work as operands
```

`+ - * / %` with parentheses and unary minus. Division or modulo by zero is reported rather than
producing an infinity.

### Ranges

```
<* for i in 0..5 *>{{ i }}<* endfor *>      01234   - stops before 5, as in Rust
<* for i in 0..=5 *>{{ i }}<* endfor *>     012345  - inclusive
<* for i in -2..2 *>{{ i }}<* endfor *>     -2 -1 0 1
<* for i in 0..count * 2 *>...<* endfor *>  both ends may be expressions
```

A backwards range such as `10..0` is empty rather than counting down - counting down would be a
silent guess about what was meant. A range longer than 100000 steps is refused and reported, so a
mistyped bound says so instead of appearing to hang.

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

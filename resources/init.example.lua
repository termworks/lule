-- lule's configuration. Put this at ~/.config/lule/init.lua, or wherever $LULE_C points.
--
-- Settings are assigned, everything else is registered. Nothing is returned - the file is a list
-- of statements, the same shape oslo is configured in.

local lule = require("lule")

local wal = "~/.cache/wal"

-- Settings are defaults: the environment overrides them, and a command-line flag overrides both.
lule.wallpaper = "~/.wallpaper" -- `~` is expanded by lule; nothing here sees a shell
lule.theme = "dark" -- dark | light
lule.palette = "pigment" -- pigment | median | histogram | tonal
lule.contrast = "aa" -- aa | aaa | none | a ratio such as 3.0
-- lule.sort = "dominance"
-- lule.saturation, lule.illumination, lule.hue, lule.blend = 0.0
-- lule.seed, lule.loop, lule.norandom

-- Anything with a template file. One list drives every path, which is what a config written in
-- Lua buys you: adding an application is a word, not six lines.
for _, app in ipairs({ "kitty", "waybar", "rofi" }) do
  lule.template(app, {
    input  = "~/.config/lule/templates/colors.ini",
    output = "~/.config/" .. app .. "/colors.ini",
  })
end

-- Everything a post-generation shell script would otherwise do, as handlers.
--
-- `c` is the finished scheme: c.colors (all 256), c.ansi (the sixteen), c.background,
-- c.foreground, c.cursor, c.accent, c.wallpaper, c.theme, c.cache. Lists count from one, so
-- c.colors[1] is colour 0.

-- The plain list, and the two facts that go with it.
local function write_cache(c)
  lule.mkdir(wal)
  lule.write(wal .. "/colors", table.concat(c.colors, "\n"))
  lule.write(wal .. "/theme", c.theme)
  lule.write(wal .. "/wallpaper", c.wallpaper)
end

-- A format with no template file. Four lines here beats a template plus a path.
local function write_shell(c)
  local out = {
    'foreground="' .. c.foreground .. '"',
    'background="' .. c.background .. '"',
    'cursor="' .. c.cursor .. '"',
  }
  for i, hex in ipairs(c.colors) do
    out[#out + 1] = "color" .. (i - 1) .. '="' .. hex .. '"'
  end
  lule.write(wal .. "/colors.sh", table.concat(out, "\n") .. "\n")
end

-- Escape sequences, sent straight down every terminal that is open. This is what recolours a
-- running shell without restarting it.
local function recolour_terminals(c)
  local esc = string.char(27)
  local seq = esc .. "]11;" .. c.background .. esc .. "\\"
  for i, hex in ipairs(c.ansi) do
    seq = seq .. esc .. "]4;" .. (i - 1) .. ";" .. hex .. esc .. "\\"
  end
  lule.ttys(seq)
end

local function reload_desktop(c)
  lule.run('hyprctl hyprpaper wallpaper ",' .. c.wallpaper .. ',"')
  lule.spawn("zedtheme") -- not worth waiting for
end

-- As many as you like. They run in this order, and one that raises does not stop the rest.
lule.on.colors(write_cache)
lule.on.colors(write_shell)
lule.on.colors(recolour_terminals)
lule.on.colors(reload_desktop)

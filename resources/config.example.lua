-- lule's configuration. Put this at ~/.config/lule/config.lua, or wherever $LULE_C points.
--
-- Settings are defaults: the environment overrides them, and a command-line flag overrides both.
-- The `after` hook runs once the colours, the cache, the templates and the scripts are all done,
-- and is where a post-generation shell script would otherwise go.

local lule = require("lule")

local wal = "~/.cache/wal"

return lule.setup({
  settings = {
    wallpaper = "~/.wallpaper",   -- `~` is expanded by lule; nothing here sees a shell
    theme     = "dark",           -- dark | light
    palette   = "pigment",        -- pigment | median | histogram | tonal
    contrast  = "aa",             -- aa | aaa | none | a ratio such as 3.0
    -- sort = "dominance", saturation = 0.0, illumination = 0.0, hue = 0.0,
    -- blend = 0.0, seed = 0, norandom = false, loop = 300,
  },

  -- Anything with a template file. One list drives every path, which is the reason to write this
  -- in Lua rather than toml: adding an application is a word, not six lines.
  templates = (function()
    local out = {}
    for _, app in ipairs({ "kitty", "waybar", "rofi" }) do
      out[#out + 1] = lule.template(app, {
        input  = "~/.config/lule/templates/colors.ini",
        output = "~/.config/" .. app .. "/colors.ini",
      })
    end
    return out
  end)(),

  -- Everything a post-generation script used to do.
  --
  -- `c` is the finished scheme: c.colors (all 256), c.ansi (the sixteen), c.background,
  -- c.foreground, c.cursor, c.accent, c.wallpaper, c.theme, c.cache. Lists count from one, so
  -- c.colors[1] is colour 0.
  after = function(c)
    lule.mkdir(wal)

    -- The plain list, and the two facts that go with it.
    lule.write(wal .. "/colors", table.concat(c.colors, "\n"))
    lule.write(wal .. "/theme", c.theme)
    lule.write(wal .. "/wallpaper", c.wallpaper)

    -- A format with no template file. Four lines here beats a template plus a path.
    local sh = {
      'foreground="' .. c.foreground .. '"',
      'background="' .. c.background .. '"',
      'cursor="' .. c.cursor .. '"',
    }
    for i, hex in ipairs(c.colors) do
      sh[#sh + 1] = "color" .. (i - 1) .. '="' .. hex .. '"'
    end
    lule.write(wal .. "/colors.sh", table.concat(sh, "\n") .. "\n")

    -- Escape sequences, sent straight down every terminal that is open. This is what recolours a
    -- running shell without restarting it.
    local esc = string.char(27)
    local seq = esc .. "]10;" .. c.foreground .. esc .. "\\"
             .. esc .. "]11;" .. c.background .. esc .. "\\"
             .. esc .. "]12;" .. c.cursor     .. esc .. "\\"
    for i, hex in ipairs(c.ansi) do
      seq = seq .. esc .. "]4;" .. (i - 1) .. ";" .. hex .. esc .. "\\"
    end
    lule.write(wal .. "/sequences", seq)
    lule.ttys(seq)

    -- Recolour a logo in place.
    lule.run("sed -i 's/fill=\"#[^\"]*\"/fill=\"" .. c.accent .. "\"/' ~/.config/bresilla.svg")

    -- Tell the compositor, and let the slow things run in the background.
    lule.run("hyprctl hyprpaper wallpaper ',' .. " .. string.format("%q", c.wallpaper) .. " .. ','")
    lule.spawn("zedtheme")
    lule.spawn("scp -r " .. wal .. " tron.netbird:" .. (lule.env("HOME") or "~") .. "/.cache/")
  end,
})

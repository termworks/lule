-- lule's configuration. Put this at ~/.config/lule/config.lua, or wherever $LULE_C points.
--
-- Everything here is a default: the environment overrides the file, and a command-line flag
-- overrides both. A `config.toml` beside this one is ignored.

local lule = require("lule")

local home = os.getenv("HOME")

-- One list drives every path. This is the reason to write the config in Lua rather than toml:
-- adding an application is a word, not six lines.
local apps = { "kitty", "waybar", "rofi" }
local templates = {}
for _, app in ipairs(apps) do
  templates[#templates + 1] = lule.template(app, {
    input  = home .. "/.config/lule/templates/colors.ini",
    output = home .. "/.config/" .. app .. "/colors.ini",
  })
end

-- A template written out by hand is just as valid; `lule.template` only tags it with a name so
-- that a warning can say which one is wrong.
templates[#templates + 1] = {
  input  = "~/.config/lule/templates/colors.css",
  output = "~/.config/gtk-4.0/colors.css",
}

return lule.setup({
  settings = {
    -- Where to pick a wallpaper from. `~` is expanded by lule; nothing here goes through a shell.
    wallpaper = "~/.wallpaper",
    cache     = "~/.cache/lule",

    theme   = "dark",      -- dark | light
    palette = "pigment",   -- pigment | median | histogram | tonal
    sort    = "dominance", -- dominance | hue | light | dark | chroma

    -- Minimum WCAG contrast for the sixteen ANSI colours against the background.
    -- "aa" (4.5:1) | "aaa" (7:1) | "none" | a ratio such as 3.0
    contrast = "aa",

    -- saturation   = 0.0,  -- -1.0 grey .. 0 unchanged .. 1.0 doubled
    -- illumination = 0.0,  -- -1.0 darker .. 0 unchanged .. 1.0 lighter
    -- hue          = 0.0,  -- rotate every pigment round the wheel
    -- blend        = 0.0,  -- 0 unchanged .. 1.0 all one hue
    -- seed         = 0,    -- non-zero gives the same scheme for the same wallpaper
    -- norandom     = false,
    -- loop         = 300,  -- daemon interval, in seconds
  },

  templates = templates,

  -- Run after the colours are written and the templates rendered - usually to make the programs
  -- above pick the new files up.
  scripts = {
    "~/.local/bin/reload-colors",
  },
})

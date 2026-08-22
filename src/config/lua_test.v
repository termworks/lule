module config

import color
import os

fn lua_config(name string, body string) string {
	dir := os.join_path(os.temp_dir(), 'lule_lua_${name}_${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	os.write_file(config_lua_path(dir), body) or { panic(err) }
	return dir
}

fn read_lua_config(dir string) Scheme {
	mut scheme := Scheme{
		config: dir
	}
	load_lua(mut scheme)
	return scheme
}

fn test_the_older_name_is_still_read_and_init_lua_wins() {
	dir := os.join_path(os.temp_dir(), 'lule_lua_names_${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }

	os.write_file(os.join_path(dir, 'config.lua'), 'return { settings = { theme = "light" } }') or {
		panic(err)
	}
	assert read_lua_config(dir).theme == 'light'

	os.write_file(os.join_path(dir, 'init.lua'), 'return { settings = { theme = "dark" } }') or {
		panic(err)
	}
	assert read_lua_config(dir).theme == 'dark'
	os.rmdir_all(dir) or {}
}

fn test_a_missing_config_is_not_an_error() {
	absent := os.join_path(os.temp_dir(), 'lule_lua_absent_${os.getpid()}')
	os.rmdir_all(absent) or {}
	mut scheme := Scheme{
		config: absent
		theme:  'dark'
	}
	load_lua(mut scheme)
	assert scheme.theme == 'dark'
}

fn test_settings_are_read() {
	dir := lua_config('settings', 'local lule = require("lule")
return lule.setup({
  settings = {
    theme = "light",
    palette = "median",
    sort = "hue",
    saturation = 0.4,
    illumination = -0.2,
    hue = 90,
    blend = 0.3,
    seed = 77,
    loop = 600,
    norandom = true,
  },
})')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := read_lua_config(dir)
	assert s.theme == 'light'
	assert s.palette == 'median'
	assert s.sort == 'hue'
	assert s.saturation == 0.4
	assert s.illumination == -0.2
	assert s.hue == 90.0
	assert s.blend == 0.3
	assert s.seed == 77
	assert s.looop == 600
	assert s.norandom
}

fn test_contrast_words_match_the_flag() {
	for word, expected in {
		'aa':   color.contrast_aa
		'aaa':  color.contrast_aaa
		'none': -1.0
		'3.0':  3.0
	} {
		dir := lua_config('contrast', 'local lule = require("lule")
return lule.setup({ settings = { contrast = "${word}" } })')
		assert read_lua_config(dir).contrast == expected, 'contrast = ${word}'
		os.rmdir_all(dir) or {}
	}
}

fn test_unset_keys_are_left_alone() {
	dir := lua_config('sparse', 'local lule = require("lule")
return lule.setup({ settings = { theme = "light" } })')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := read_lua_config(dir)
	assert s.theme == 'light'
	assert s.scheme == ''
	assert s.palette == ''
	assert s.saturation == 0.0
	assert s.seed == 0
}

fn test_templates_keep_their_order() {
	// A list, not a map: the order in the file is the order they render in.
	dir := lua_config('templates', 'local lule = require("lule")
return lule.setup({
  templates = {
    lule.template("first", { input = "/in/a", output = "/out/a" }),
    lule.template("second", { input = "/in/b", output = "/out/b" }),
  },
})')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := read_lua_config(dir)
	assert s.patterns.len == 2
	assert s.patterns[0].from == '/in/a'
	assert s.patterns[1].from == '/in/b'
}

fn test_a_template_written_by_hand_works_too() {
	// `lule.template` only tags the table with a name; a bare table is just as valid.
	dir := lua_config('bare', 'local lule = require("lule")
return lule.setup({ templates = { { input = "/in/x", output = "/out/x" } } })')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := read_lua_config(dir)
	assert s.patterns.len == 1
	assert s.patterns[0].to == '/out/x'
}

fn test_a_template_missing_a_path_is_skipped_not_fatal() {
	dir := lua_config('halftemplate', 'local lule = require("lule")
return lule.setup({
  templates = {
    lule.template("good", { input = "/in/a", output = "/out/a" }),
    lule.template("broken", { input = "/in/b" }),
  },
})')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := read_lua_config(dir)
	assert s.patterns.len == 1
	assert s.patterns[0].from == '/in/a'
}

fn test_tilde_is_expanded() {
	dir := lua_config('tilde', 'local lule = require("lule")
return lule.setup({
  settings = { wallpaper = "~/pictures" },
  templates = { lule.template("t", { input = "~/in", output = "~/out" }) },
})')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := read_lua_config(dir)
	home := os.home_dir()
	assert s.walldir == os.join_path(home, 'pictures')
	assert s.patterns[0].from == os.join_path(home, 'in')
	assert !s.walldir.contains('~')
}

fn test_a_config_may_compute_rather_than_declare() {
	// The whole reason for choosing Lua over toml: one list drives every path.
	dir := lua_config('computed', 'local lule = require("lule")
local apps = { "kitty", "waybar", "rofi" }
local templates = {}
for _, app in ipairs(apps) do
  templates[#templates + 1] = lule.template(app, {
    input = "/tpl/" .. app,
    output = "/etc/" .. app .. "/colors",
  })
end
return lule.setup({ templates = templates })')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := read_lua_config(dir)
	assert s.patterns.len == 3
	assert s.patterns[0].from == '/tpl/kitty'
	assert s.patterns[2].to == '/etc/rofi/colors'
}

fn test_config_adds_to_patterns_rather_than_replacing() {
	dir := lua_config('append', 'local lule = require("lule")
return lule.setup({ templates = { lule.template("a", { input = "/in/a", output = "/out/a" }) } })')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut scheme := Scheme{
		config:   dir
		patterns: [Pattern{'/already', '/there'}]
	}
	load_lua(mut scheme)
	assert scheme.patterns.len == 2
	assert scheme.patterns[0].from == '/already'
}

fn test_lua_is_preferred_when_both_exist() {
	dir := lua_config('both', 'local lule = require("lule")
return lule.setup({ settings = { theme = "light" } })')
	defer {
		os.rmdir_all(dir) or {}
	}
	os.write_file(config_path(dir), '[settings]\ntheme = "dark"\n') or { panic(err) }
	mut scheme := Scheme{
		config: dir
	}
	load(mut scheme)
	assert scheme.theme == 'light', 'the toml won'
}

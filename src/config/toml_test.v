module config

import color
import os

fn config_in(name string, body string) string {
	dir := os.join_path(os.temp_dir(), 'lule_cfg_${name}_${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	os.write_file(config_path(dir), body) or { panic(err) }
	return dir
}

fn load(dir string) Scheme {
	mut scheme := Scheme{
		config: dir
	}
	config_concatinate(mut scheme)
	return scheme
}

fn test_a_missing_config_is_not_an_error() {
	// lule has always worked without one and has to keep working without one.
	empty := os.join_path(os.temp_dir(), 'lule_cfg_absent_${os.getpid()}')
	os.rmdir_all(empty) or {}
	mut scheme := Scheme{
		config: empty
		theme:  'dark'
	}
	config_concatinate(mut scheme)
	assert scheme.theme == 'dark'
}

fn test_settings_are_read() {
	dir := config_in('settings', '[settings]
theme = "light"
palette = "pigment"
sort = "hue"
saturation = 0.4
illumination = -0.2
hue = 90.0
blend = 0.3
seed = 77
loop = 600
norandom = true
')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := load(dir)
	assert s.theme == 'light'
	assert s.palette == 'pigment'
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
		'off':  -1.0
		'3.0':  3.0
	} {
		dir := config_in('contrast', '[settings]\ncontrast = "${word}"\n')
		assert load(dir).contrast == expected, 'contrast = ${word}'
		os.rmdir_all(dir) or {}
	}
}

fn test_unset_keys_are_left_alone() {
	// A missing key reads back as toml.Null, whose string form is a debug rendering of the type.
	// Treating that as a value made lule hunt for a scheme literally named after it.
	dir := config_in('sparse', '[settings]\ntheme = "light"\n')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := load(dir)
	assert s.theme == 'light'
	assert s.scheme == '', 'scheme picked up `${s.scheme}`'
	assert s.palette == ''
	assert s.sort == ''
	assert s.saturation == 0.0
	assert s.seed == 0
}

fn test_templates_become_patterns() {
	dir := config_in('templates', '[templates.kitty]
input = "/in/kitty.tpl"
output = "/out/kitty.conf"

[templates.waybar]
input = "/in/waybar.tpl"
output = "/out/waybar.css"
')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := load(dir)
	assert s.patterns.len == 2
	// Sorted by name, so the order does not depend on how the map happened to hash.
	assert s.patterns[0].from == '/in/kitty.tpl'
	assert s.patterns[0].to == '/out/kitty.conf'
	assert s.patterns[1].from == '/in/waybar.tpl'
}

fn test_a_template_missing_a_path_is_skipped_not_fatal() {
	dir := config_in('halftemplate', '[templates.good]
input = "/in/a"
output = "/out/a"

[templates.broken]
input = "/in/b"
')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := load(dir)
	assert s.patterns.len == 1
	assert s.patterns[0].from == '/in/a'
}

fn test_scripts_are_read() {
	dir := config_in('scripts', '[scripts]\nafter = ["/one.sh", "/two.sh"]\n')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := load(dir)
	assert s.scripts == ['/one.sh', '/two.sh']
}

fn test_tilde_is_expanded() {
	// Nothing in a toml file goes through a shell, so a literal `~/x` would be created as a
	// directory called `~`.
	dir := config_in('tilde', '[settings]
wallpaper = "~/pictures"

[templates.t]
input = "~/in.tpl"
output = "~/out.conf"

[scripts]
after = ["~/s.sh"]
')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := load(dir)
	home := os.home_dir()
	assert s.walldir == os.join_path(home, 'pictures')
	assert s.patterns[0].from == os.join_path(home, 'in.tpl')
	assert s.patterns[0].to == os.join_path(home, 'out.conf')
	assert s.scripts[0] == os.join_path(home, 's.sh')
	assert !s.walldir.contains('~')
}

fn test_an_empty_config_changes_nothing() {
	dir := config_in('blank', '')
	defer {
		os.rmdir_all(dir) or {}
	}
	s := load(dir)
	assert s.theme == ''
	assert s.patterns.len == 0
	assert s.scripts.len == 0
}

fn test_config_adds_to_patterns_rather_than_replacing() {
	dir := config_in('append', '[templates.a]\ninput = "/in/a"\noutput = "/out/a"\n')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut scheme := Scheme{
		config:   dir
		patterns: [Pattern{'/already', '/there'}]
	}
	config_concatinate(mut scheme)
	assert scheme.patterns.len == 2
	assert scheme.patterns[0].from == '/already'
}

module config

import color
import ui
import os
import toml
import cmd

// The config file lives beside the named schemes, in $LULE_C or ~/.config/lule.
//
// It exists because the alternative is unusable: eight templates meant eight `--pattern=in:out`
// flags on every single invocation, and $LULE_S could name exactly one script. Everything here
// can still be overridden by a flag.
pub const config_name = 'config.toml'

pub fn config_path(config_dir string) string {
	return os.join_path(config_dir, config_name)
}

// Reads the config into the scheme. Missing is not an error - lule has always worked without one,
// and it has to keep working without one.
//
// A malformed one *is* worth complaining about: silently ignoring a file the user wrote and is
// watching for an effect is the worst of both.
pub fn load(mut scheme Scheme) Hooks {
	// Lua first: it can express everything the toml can and more, so a directory holding both is
	// answered by the one that can say more. The toml loader stays for anyone who wants something
	// purely declarative.
	if os.is_file(config_lua_path(scheme.config)) {
		return load_lua(mut scheme)
	}

	path := config_path(scheme.config)
	if !os.is_file(path) {
		return Hooks{}
	}
	doc := toml.parse_file(path) or {
		eprintln('${ui.red_bold('error:')} ${ui.yellow(path)} is not valid toml')
		eprintln('${ui.red_bold('error:')} ${err}')
		exit(1)
	}

	settings := doc.value('settings')
	apply_settings(settings, mut scheme)
	apply_templates(doc.value('templates'), mut scheme, path)
	apply_scripts(doc.value('scripts'), mut scheme)
	return Hooks{}
}

// `~` is expanded here rather than left to the shell, because nothing in a toml file goes through
// a shell: a literal `~/.config/kitty` would be created as a directory called `~`.
fn expand_home(path string) string {
	if path == '~' {
		return os.home_dir()
	}
	if path.starts_with('~/') {
		return os.join_path(os.home_dir(), path[2..])
	}
	return path
}

fn apply_settings(settings toml.Any, mut scheme Scheme) {
	if v := as_text(settings.value('wallpaper')) {
		scheme.walldir = expand_home(v)
	}
	if v := as_text(settings.value('cache')) {
		scheme.cache = expand_home(v)
	}
	if v := as_text(settings.value('theme')) {
		scheme.theme = v
	}
	if v := as_text(settings.value('palette')) {
		scheme.palette = v
	}
	if v := as_text(settings.value('scheme')) {
		scheme.scheme = v
	}
	if v := as_text(settings.value('sort')) {
		scheme.sort = v
	}
	if v := as_text(settings.value('contrast')) {
		scheme.contrast = parse_contrast(v)
	}
	if v := as_float(settings.value('saturation')) {
		scheme.saturation = v
	}
	if v := as_float(settings.value('illumination')) {
		scheme.illumination = v
	}
	if v := as_float(settings.value('hue')) {
		scheme.hue = v
	}
	if v := as_float(settings.value('blend')) {
		scheme.blend = v
	}
	if v := as_float(settings.value('seed')) {
		scheme.seed = int(v)
	}
	if v := as_float(settings.value('loop')) {
		scheme.looop = int(v)
	}
	if settings.value('norandom').bool() {
		scheme.norandom = true
	}
}

// `[templates.name]` tables, each with an input and an output. Named rather than a list so a
// template can be talked about - and so editing one in place does not renumber the rest.
fn apply_templates(templates toml.Any, mut scheme Scheme, from string) {
	tables := templates.as_map()
	if tables.len == 0 {
		return
	}
	mut names := tables.keys()
	names.sort()
	mut patterns := scheme.patterns.clone()
	for name in names {
		table := tables[name] or { continue }
		input := as_text(table.value('input')) or {
			eprintln('${ui.yellow('warning:')} ${from}: template `${name}` has no input')
			continue
		}
		output := as_text(table.value('output')) or {
			eprintln('${ui.yellow('warning:')} ${from}: template `${name}` has no output')
			continue
		}
		patterns << Pattern{expand_home(input), expand_home(output)}
	}
	scheme.patterns = patterns
}

fn apply_scripts(scripts toml.Any, mut scheme Scheme) {
	list := scripts.value('after').array()
	if list.len == 0 {
		return
	}
	mut all := scheme.scripts.clone()
	for entry in list {
		if entry is toml.Null {
			continue
		}
		text := entry.string()
		if text.trim_space() != '' {
			all << expand_home(text)
		}
	}
	scheme.scripts = all
}

// A missing key comes back as toml.Null, whose .string() is a debug rendering of the type rather
// than an empty string - so the type is what gets checked here, not the text. Comparing the text
// let that debug rendering through as if it were a real setting, and lule went looking for a
// named scheme called "toml.Any(toml.Null{})".
fn as_text(value toml.Any) ?string {
	if value is toml.Null {
		return none
	}
	s := value.string()
	if s.trim_space() == '' {
		return none
	}
	return s
}

fn as_float(value toml.Any) ?f64 {
	if value is toml.Null {
		return none
	}
	return value.f64()
}

// Shared with the `--contrast` flag so the file and the flag understand the same words.
pub fn parse_contrast(text string) f64 {
	return match text.to_lower() {
		'aa' { color.contrast_aa }
		'aaa' { color.contrast_aaa }
		'none', 'off', '0', 'false' { -1.0 }
		else { text.f64() }
	}
}

// Resolves only where the config file is, ahead of reading it.
fn locate_config(a &cmd.Args, mut scheme Scheme) {
	if v := os.getenv_opt('LULE_C') {
		if v.trim_space() != '' {
			scheme.config = expand_home(v)
		}
	}
	if v := a.flags['configs'] {
		scheme.config = expand_home(v)
	}
}

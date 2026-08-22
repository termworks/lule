module config

import ui
import os
import luavm

// `~/.config/lule/config.lua`, in the shape the sibling tools use: require the module, hand
// `setup` a table, return the result.
//
//   local lule = require("lule")
//
//   return lule.setup({
//     settings  = { theme = "dark", contrast = "aa" },
//     templates = { lule.template("kitty", { input = "…", output = "…" }) },
//     scripts   = { "~/.local/bin/reload-colors" },
//   })
//
// Preferred over config.toml when both exist. The toml loader stays for anyone who wants
// something purely declarative.
pub const config_lua_name = 'config.lua'

pub fn config_lua_path(config_dir string) string {
	return os.join_path(config_dir, config_lua_name)
}

// The `lule` module a config requires, written in Lua rather than registered from V.
//
// `setup` is the identity function and `template` just tags a table. Neither needs to reach back
// into lule, so neither needs a C closure — which keeps the whole bridge to "run a script, read
// the table it returned" and leaves no way for a config to crash the host.
const lule_module = "local lule = {}

function lule.setup(config)
  return config or {}
end

-- Named so the order in the file is the order they run in, and so a warning can say which one is
-- wrong by name rather than by position.
function lule.template(name, spec)
  local t = spec or {}
  t.name = name
  return t
end

function lule.script(path)
  return path
end

package.loaded['lule'] = lule
return lule
"

// A config's `after` hook, parked until the colours exist.
//
// The Lua state stays open for the whole run rather than being torn down after the settings are
// read: settings are wanted at startup and the hook is wanted much later, and re-running the
// config to get back to it would run any side effects in its body a second time.
pub struct Hooks {
mut:
	vm      luavm.State
	config  int = -1
	present bool
}

pub fn (mut h Hooks) close() {
	if h.present {
		h.vm.close()
		h.present = false
	}
}

// Calls the `after` hook, if the config defined one.
pub fn (mut h Hooks) after(scheme &Scheme) {
	if !h.present {
		return
	}
	h.vm.fetch(h.config)
	if h.vm.field('after') == 0 || !h.vm.is_function() {
		h.vm.pop(2)
		return
	}
	push_scheme(mut h.vm, scheme)
	h.vm.call(1) or {
		// The colours are already written by this point, so a failing hook is worth reporting
		// without throwing away the run that produced them.
		eprintln('${ui.red_bold('error:')} after: ${err}')
	}
	h.vm.pop(1)
}

// Runs the config and folds what it returns into the scheme.
pub fn load_lua(mut scheme Scheme) Hooks {
	path := config_lua_path(scheme.config)
	if !os.is_file(path) {
		return Hooks{}
	}
	source := os.read_file(path) or {
		eprintln('${ui.red_bold('error:')} cannot read ${ui.yellow(path)}: ${err}')
		exit(1)
	}

	mut vm := luavm.new()

	// The module is defined before the config runs, so `require("lule")` finds it already loaded
	// and never touches the filesystem looking for a lule.lua.
	vm.run(lule_module, 'lule module') or {
		eprintln('${ui.red_bold('error:')} ${err}')
		exit(1)
	}
	// The module table is on top; the V-backed functions are added to it before the config runs.
	register_api(mut vm)
	vm.pop(1)

	vm.run(source, path) or {
		// A broken config is worth stopping for. Carrying on with defaults would silently apply a
		// scheme the user did not ask for, over the top of the one they had.
		eprintln('${ui.red_bold('error:')} ${err}')
		exit(1)
	}

	if !vm.top_is_table() {
		eprintln('${ui.yellow('warning:')} ${path} returned nothing; did you forget `return lule.setup({...})`?')
		return Hooks{}
	}

	read_lua_settings(mut vm, mut scheme)
	read_lua_templates(mut vm, mut scheme, path)
	read_lua_scripts(mut vm, mut scheme)

	// Parked in the registry so the hook can be found again once the colours exist.
	return Hooks{
		vm:      vm
		config:  vm.keep()
		present: true
	}
}

fn read_lua_settings(mut vm luavm.State, mut scheme Scheme) {
	vm.field('settings')
	defer {
		vm.pop(1)
	}
	if !vm.top_is_table() {
		return
	}

	if v := lua_text(mut vm, 'wallpaper') {
		scheme.walldir = expand_home(v)
	}
	if v := lua_text(mut vm, 'cache') {
		scheme.cache = expand_home(v)
	}
	if v := lua_text(mut vm, 'theme') {
		scheme.theme = v
	}
	if v := lua_text(mut vm, 'palette') {
		scheme.palette = v
	}
	if v := lua_text(mut vm, 'scheme') {
		scheme.scheme = v
	}
	if v := lua_text(mut vm, 'sort') {
		scheme.sort = v
	}
	// A ratio may be written either as a word or as a number, so both spellings are accepted.
	if v := lua_text(mut vm, 'contrast') {
		scheme.contrast = parse_contrast(v)
	}
	if v := lua_number(mut vm, 'saturation') {
		scheme.saturation = v
	}
	if v := lua_number(mut vm, 'illumination') {
		scheme.illumination = v
	}
	if v := lua_number(mut vm, 'hue') {
		scheme.hue = v
	}
	if v := lua_number(mut vm, 'blend') {
		scheme.blend = v
	}
	if v := lua_number(mut vm, 'seed') {
		scheme.seed = int(v)
	}
	if v := lua_number(mut vm, 'loop') {
		scheme.looop = int(v)
	}
	if v := lua_bool(mut vm, 'norandom') {
		scheme.norandom = v
	}
}

// `templates` is a list, so the order in the file is the order they are rendered in. Each entry
// is a table with `input` and `output`, whether it came through `lule.template` or was written
// out by hand.
fn read_lua_templates(mut vm luavm.State, mut scheme Scheme, from string) {
	vm.field('templates')
	defer {
		vm.pop(1)
	}
	if !vm.top_is_table() {
		return
	}

	mut patterns := scheme.patterns.clone()
	total := vm.len()
	for i := 1; i <= total; i++ {
		vm.index(i)
		if vm.top_is_table() {
			name := lua_text(mut vm, 'name') or { '#${i}' }
			input := lua_text(mut vm, 'input') or {
				eprintln('${ui.yellow('warning:')} ${from}: template ${name} has no input')
				vm.pop(1)
				continue
			}
			output := lua_text(mut vm, 'output') or {
				eprintln('${ui.yellow('warning:')} ${from}: template ${name} has no output')
				vm.pop(1)
				continue
			}
			patterns << Pattern{expand_home(input), expand_home(output)}
		}
		vm.pop(1)
	}
	scheme.patterns = patterns
}

fn read_lua_scripts(mut vm luavm.State, mut scheme Scheme) {
	vm.field('scripts')
	defer {
		vm.pop(1)
	}
	if !vm.top_is_table() {
		return
	}
	mut all := scheme.scripts.clone()
	total := vm.len()
	for i := 1; i <= total; i++ {
		vm.index(i)
		if text := vm.as_text() {
			all << expand_home(text)
		}
		vm.pop(1)
	}
	scheme.scripts = all
}

// Reading one field is always push, look, pop — so the helpers keep the three together and the
// stack cannot drift.
fn lua_text(mut vm luavm.State, key string) ?string {
	vm.field(key)
	defer {
		vm.pop(1)
	}
	return vm.as_text()
}

fn lua_number(mut vm luavm.State, key string) ?f64 {
	vm.field(key)
	defer {
		vm.pop(1)
	}
	return vm.as_number()
}

fn lua_bool(mut vm luavm.State, key string) ?bool {
	vm.field(key)
	defer {
		vm.pop(1)
	}
	return vm.as_bool()
}

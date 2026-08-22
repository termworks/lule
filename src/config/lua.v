module config

import ui
import os
import luavm

// `~/.config/lule/init.lua`, in the shape oslo is configured in: require the module, assign the
// settings, register the rest. Nothing is returned.
//
//   local lule = require("lule")
//
//   lule.theme = "dark"
//   lule.template("kitty", { input = "…", output = "…" })
//   lule.on.colors(function(c) lule.ttys(sequences_for(c)) end)
//
// One config, one name. It lives in $LULE_C or ~/.config/lule.
pub const config_name = 'init.lua'

pub fn config_path(config_dir string) string {
	return os.join_path(config_dir, config_name)
}

// The `lule` module a config requires, written in Lua rather than registered from V.
//
// Registering rather than returning is what lets a config be many small functions instead of one
// big one: `lule.on.colors` can be called as often as it likes, and each handler is named at the
// point it is written. It also means the settings are read off this table after the config has
// run, so the file needs no `return` at all.
const lule_module = "local lule = {}

lule.templates = {}
lule.handlers = { colors = {} }
lule.on = {}

-- Named so the order in the file is the order they render in, and so a warning can say which one
-- is wrong by name rather than by position.
function lule.template(name, spec)
  local t = spec or {}
  t.name = name
  lule.templates[#lule.templates + 1] = t
  return t
end

-- Called once the colours exist, the cache is written and the templates are rendered. As many as
-- you like; they run in the order they were registered, and one that raises does not stop the rest.
function lule.on.colors(fn)
  lule.handlers.colors[#lule.handlers.colors + 1] = fn
end

package.loaded['lule'] = lule
return lule
"

// The handlers a config registered, parked until the colours exist.
//
// The Lua state stays open for the whole run rather than being torn down after the settings are
// read: settings are wanted at startup and the handlers much later, and re-running the
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

// Calls every handler the config registered with `lule.on.colors`, in the order it registered them.
pub fn (mut h Hooks) after(scheme &Scheme) {
	if !h.present {
		return
	}
	h.vm.fetch(h.config)
	if h.vm.field('handlers') == 0 || !h.vm.top_is_table() {
		h.vm.pop(2)
		return
	}
	if h.vm.field('colors') == 0 || !h.vm.top_is_table() {
		h.vm.pop(3)
		return
	}

	// Built once and parked, so ten handlers are handed the same table rather than ten copies of
	// the same 256 strings.
	push_scheme(mut h.vm, scheme)
	ticket := h.vm.keep()

	total := h.vm.len()
	for i := 1; i <= total; i++ {
		h.vm.index(i)
		if !h.vm.is_function() {
			h.vm.pop(1)
			continue
		}
		h.vm.fetch(ticket)
		h.vm.call(1) or {
			// The colours are already written by this point, so a failing handler is worth
			// reporting without throwing away the run that produced them - or the handlers after it,
			// which have nothing to do with the one that raised.
			eprintln('${ui.red_bold('error:')} lule.on.colors #${i}: ${err}')
		}
	}
	h.vm.pop(3)
}

// Runs the config and folds what it set into the scheme.
pub fn load_lua(mut scheme Scheme) Hooks {
	path := config_path(scheme.config)
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
	// Then it is parked in the registry: it is what the config writes its settings onto, and what
	// the handlers are found on again once the colours exist.
	register_api(mut vm)
	lule_table := vm.keep()

	vm.run(source, path) or {
		// A broken config is worth stopping for. Carrying on with defaults would silently apply a
		// scheme the user did not ask for, over the top of the one they had.
		eprintln('${ui.red_bold('error:')} ${err}')
		exit(1)
	}
	vm.pop(1) // whatever the config evaluated to; an oslo-style config returns nothing

	vm.fetch(lule_table)
	read_lua_settings(mut vm, mut scheme)
	read_lua_templates(mut vm, mut scheme, path)
	vm.pop(1)

	return Hooks{
		vm:      vm
		config:  lule_table
		present: true
	}
}

// Read off the module table itself, which is where `lule.theme = "dark"` put them. A setting the
// config never mentions is left at whatever the environment or a flag says.
fn read_lua_settings(mut vm luavm.State, mut scheme Scheme) {
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

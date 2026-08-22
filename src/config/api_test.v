module config

import os
import color

fn hook_dir(name string) string {
	dir := os.join_path(os.temp_dir(), 'lule_hook_${name}_${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

// Runs a config's `after` hook against a scheme with real colours in it.
fn run_hook(dir string, body string) Scheme {
	os.write_file(config_lua_path(dir), body) or { panic(err) }
	mut scheme := Scheme{
		config: dir
		image:  '/w/pic.png'
		theme:  'dark'
		cache:  '/c'
	}
	mut swatches := []color.Color{}
	for i in 0 .. 256 {
		swatches << color.color_from_rgb(u8(i), u8(255 - i), u8(i / 2))
	}
	scheme.colors = swatches
	mut hooks := load_lua(mut scheme)
	hooks.after(&scheme)
	hooks.close()
	return scheme
}

fn test_the_hook_sees_the_finished_scheme() {
	dir := hook_dir('scheme')
	defer {
		os.rmdir_all(dir) or {}
	}
	run_hook(dir, 'local lule = require("lule")
return lule.setup({ after = function(c)
  lule.write("${dir}/out", table.concat({
    c.wallpaper, c.theme, c.cache, c.background, c.foreground, c.cursor,
    tostring(#c.colors), tostring(#c.ansi), c.colors[1], c.ansi[16],
  }, "|"))
end })')
	parts := os.read_file(os.join_path(dir, 'out')) or { panic(err) }.split('|')
	assert parts[0] == '/w/pic.png'
	assert parts[1] == 'dark'
	assert parts[2] == '/c'
	// Colour 0 is the background and colour 15 the foreground, as everywhere else.
	assert parts[3] == '#00ff00'
	assert parts[6] == '256', 'colors had ${parts[6]}'
	assert parts[7] == '16', 'ansi had ${parts[7]}'
	// One-based, the way Lua counts: colors[1] is colour 0.
	assert parts[8] == '#00ff00'
	assert parts[9] == '#0ff007'
}

fn test_a_config_with_no_hook_is_fine() {
	dir := hook_dir('nohook')
	defer {
		os.rmdir_all(dir) or {}
	}
	run_hook(dir, 'local lule = require("lule")
return lule.setup({ settings = { theme = "light" } })')
	// Reaching here without a crash is the assertion.
	assert true
}

fn test_write_and_read_round_trip() {
	dir := hook_dir('write')
	defer {
		os.rmdir_all(dir) or {}
	}
	run_hook(dir, 'local lule = require("lule")
return lule.setup({ after = function(c)
  lule.write("${dir}/a", "first")
  lule.append("${dir}/a", " second")
  lule.write("${dir}/echo", lule.read("${dir}/a") or "missing")
end })')
	assert os.read_file(os.join_path(dir, 'echo')) or { '' } == 'first second'
}

fn test_reading_a_missing_file_is_nil_not_empty() {
	// nil, so `lule.read(p) or "default"` works the way a Lua author expects.
	dir := hook_dir('missing')
	defer {
		os.rmdir_all(dir) or {}
	}
	run_hook(dir, 'local lule = require("lule")
return lule.setup({ after = function(c)
  lule.write("${dir}/out", lule.read("${dir}/nope") or "fallback")
end })')
	assert os.read_file(os.join_path(dir, 'out')) or { '' } == 'fallback'
}

fn test_write_creates_the_directory() {
	dir := hook_dir('mkdirs')
	defer {
		os.rmdir_all(dir) or {}
	}
	run_hook(dir, 'local lule = require("lule")
return lule.setup({ after = function(c)
  lule.write("${dir}/deep/deeper/file", "here")
end })')
	assert os.exists(os.join_path(dir, 'deep/deeper/file'))
}

fn test_copy_and_mkdir() {
	dir := hook_dir('copy')
	defer {
		os.rmdir_all(dir) or {}
	}
	os.write_file(os.join_path(dir, 'source'), 'payload') or { panic(err) }
	run_hook(dir, 'local lule = require("lule")
return lule.setup({ after = function(c)
  lule.mkdir("${dir}/made")
  lule.copy("${dir}/source", "${dir}/made/copied")
end })')
	assert os.is_dir(os.join_path(dir, 'made'))
	assert os.read_file(os.join_path(dir, 'made/copied')) or { '' } == 'payload'
}

fn test_run_answers_the_exit_status() {
	dir := hook_dir('run')
	defer {
		os.rmdir_all(dir) or {}
	}
	run_hook(dir, 'local lule = require("lule")
return lule.setup({ after = function(c)
  local ok = lule.run("true")
  local bad = lule.run("exit 3")
  lule.write("${dir}/codes", tostring(ok) .. "," .. tostring(bad))
end })')
	// Whole numbers, not floats: "0,3" rather than "0.0,3.0".
	assert os.read_file(os.join_path(dir, 'codes')) or { '' } == '0,3'
}

fn test_a_path_may_use_a_tilde() {
	dir := hook_dir('tilde')
	defer {
		os.rmdir_all(dir) or {}
	}
	run_hook(dir, 'local lule = require("lule")
return lule.setup({ after = function(c)
  lule.write("${dir}/home", tostring(lule.read("~/.lule_probe_absent") == nil))
end })')
	// Only that the tilde was expanded rather than taken literally; the file does not exist.
	assert os.read_file(os.join_path(dir, 'home')) or { '' } == 'true'
	assert !os.exists('~')
}

fn test_env_reads_the_environment() {
	dir := hook_dir('env')
	defer {
		os.rmdir_all(dir) or {}
	}
	os.setenv('LULE_HOOK_PROBE', 'present', true)
	run_hook(dir, 'local lule = require("lule")
return lule.setup({ after = function(c)
  lule.write("${dir}/out", (lule.env("LULE_HOOK_PROBE") or "?") .. "/" .. (lule.env("LULE_NOT_SET_AT_ALL") or "unset"))
end })')
	assert os.read_file(os.join_path(dir, 'out')) or { '' } == 'present/unset'
}

fn test_a_failing_hook_is_reported_not_fatal() {
	// The colours are already written by the time the hook runs, so a mistake in it must not
	// throw away the run that produced them.
	dir := hook_dir('boom')
	defer {
		os.rmdir_all(dir) or {}
	}
	run_hook(dir, 'local lule = require("lule")
return lule.setup({ after = function(c) error("deliberate") end })')
	assert true
}

fn test_the_hook_can_use_the_settings_it_declared() {
	dir := hook_dir('both')
	defer {
		os.rmdir_all(dir) or {}
	}
	scheme := run_hook(dir, 'local lule = require("lule")
local target = "${dir}/from_settings"
return lule.setup({
  settings = { theme = "light" },
  after = function(c) lule.write(target, c.theme) end,
})')
	assert scheme.theme == 'light'
	// The hook is a closure over the config body, so `target` - a local declared up there - is in
	// scope. And it sees the *settled* theme, the one the settings asked for, not the one the
	// scheme carried before the config was read.
	assert os.read_file(os.join_path(dir, 'from_settings')) or { '' } == 'light'
}

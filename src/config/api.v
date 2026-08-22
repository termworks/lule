module config

import os
import ui
import luavm

// The `lule.*` functions a config can call, and the `after` hook that gets to call them once the
// colours exist.
//
// This is what replaces a post-generation shell script. Everything such a script did — copy files
// about, write out a format lule has no template for, send escape sequences to every open
// terminal, reload a compositor — is one of these.

// Paths coming from a config are written by a person, so `~` is expanded here too. Nothing in a
// config file passes through a shell that would have done it.
fn api_path(state luavm.Handle, index int) string {
	return expand_home(luavm.arg_text(state, index))
}

fn api_write(state luavm.Handle) int {
	path := api_path(state, 1)
	body := luavm.arg_text(state, 2)
	os.mkdir_all(os.dir(path)) or {}
	os.write_file(path, body) or {
		eprintln('${ui.yellow('warning:')} lule.write ${path}: ${err}')
		return luavm.return_bool(state, false)
	}
	return luavm.return_bool(state, true)
}

fn api_append(state luavm.Handle) int {
	path := api_path(state, 1)
	body := luavm.arg_text(state, 2)
	os.mkdir_all(os.dir(path)) or {}
	mut f := os.open_append(path) or {
		eprintln('${ui.yellow('warning:')} lule.append ${path}: ${err}')
		return luavm.return_bool(state, false)
	}
	f.write_string(body) or {}
	f.close()
	return luavm.return_bool(state, true)
}

fn api_read(state luavm.Handle) int {
	path := api_path(state, 1)
	body := os.read_file(path) or { return 0 } // nil, so `or` works on the Lua side
	return luavm.return_text(state, body)
}

fn api_mkdir(state luavm.Handle) int {
	path := api_path(state, 1)
	os.mkdir_all(path) or {
		eprintln('${ui.yellow('warning:')} lule.mkdir ${path}: ${err}')
		return luavm.return_bool(state, false)
	}
	return luavm.return_bool(state, true)
}

fn api_copy(state luavm.Handle) int {
	from := api_path(state, 1)
	to := api_path(state, 2)
	os.mkdir_all(os.dir(to)) or {}
	os.cp(from, to) or {
		eprintln('${ui.yellow('warning:')} lule.copy ${from} -> ${to}: ${err}')
		return luavm.return_bool(state, false)
	}
	return luavm.return_bool(state, true)
}

// Runs a command and waits, answering its exit status. Through a shell, because a config that
// says `hyprctl hyprpaper wallpaper ",$path,"` expects shell quoting to mean what it looks like.
fn api_run(state luavm.Handle) int {
	command := luavm.arg_text(state, 1)
	result := os.execute(command)
	return luavm.return_int(state, i64(result.exit_code))
}

// Starts a command and does not wait. The script this replaces backgrounded three of them, and a
// wallpaper daemon should not block on a file copy to another machine.
fn api_spawn(state luavm.Handle) int {
	command := luavm.arg_text(state, 1)
	os.execute('${command} >/dev/null 2>&1 &')
	return luavm.return_bool(state, true)
}

// Writes text to every pseudo-terminal that is open.
//
// This is how a running terminal changes colour without being restarted: the escape sequences go
// straight down its tty. Only the numbered entries under /dev/pts are real terminals — `ptmx` is
// the multiplexer, and writing to it does something quite different.
fn api_ttys(state luavm.Handle) int {
	payload := luavm.arg_text(state, 1)
	mut written := 0
	entries := os.ls('/dev/pts') or { return luavm.return_int(state, 0) }
	for entry in entries {
		if !entry[0].is_digit() {
			continue
		}
		path := os.join_path('/dev/pts', entry)
		// A terminal that has gone away between the listing and the write is ordinary, not an
		// error worth telling anybody about.
		mut f := os.open_append(path) or { continue }
		f.write_string(payload) or {}
		f.close()
		written++
	}
	return luavm.return_int(state, i64(written))
}

fn api_env(state luavm.Handle) int {
	name := luavm.arg_text(state, 1)
	value := os.getenv(name)
	return if value == '' { 0 } else { luavm.return_text(state, value) }
}

// Adds the functions to the `lule` table that is already on top of the stack.
fn register_api(mut vm luavm.State) {
	vm.register_field('write', api_write)
	vm.register_field('append', api_append)
	vm.register_field('read', api_read)
	vm.register_field('mkdir', api_mkdir)
	vm.register_field('copy', api_copy)
	vm.register_field('run', api_run)
	vm.register_field('spawn', api_spawn)
	vm.register_field('ttys', api_ttys)
	vm.register_field('env', api_env)
}

// What the `after` hook is handed: the finished scheme, as a table.
fn push_scheme(mut vm luavm.State, scheme &Scheme) {
	vm.new_table()

	vm.push_text(scheme.image)
	vm.set_field('wallpaper')
	vm.push_text(scheme.theme)
	vm.set_field('theme')
	vm.push_text(scheme.cache)
	vm.set_field('cache')

	if scheme.colors.len > 15 {
		vm.push_text(scheme.colors[0].to_hex(true))
		vm.set_field('background')
		vm.push_text(scheme.colors[15].to_hex(true))
		vm.set_field('foreground')
		vm.push_text(scheme.colors[1].to_hex(true))
		vm.set_field('cursor')
		vm.push_text(scheme.colors[1].to_hex(true))
		vm.set_field('accent')
	}

	// Every colour, and the sixteen a terminal uses, both one-based so `colors[1]` is colour 0 the
	// way Lua counts.
	vm.new_table()
	for i, swatch in scheme.colors {
		vm.push_text(swatch.to_hex(true))
		vm.set_index(i + 1)
	}
	vm.set_field('colors')

	vm.new_table()
	for i, swatch in scheme.colors {
		if i >= 16 {
			break
		}
		vm.push_text(swatch.to_hex(true))
		vm.set_index(i + 1)
	}
	vm.set_field('ansi')
}

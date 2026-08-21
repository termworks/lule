module luavm

// A thin binding over the Lua C API — only the parts a configuration file needs: run a script,
// then walk the table it returns.
//
// Lua itself is not vendored: it comes from the flake, so the version is pinned by flake.lock
// like every other dependency and no C source lives in this repository. The archive is linked in,
// so the release binary stays one static file.

// pkg-config finds the headers and the archive, so no path to Lua appears in this file or in
// the build recipe. It also means a non-nix build works against a system lua5.4 unchanged.
//
// The flags live here rather than in `-cflags`/`-ldflags`: `v test` re-splits those on spaces,
// so `-ldflags "…/liblua.a -lm"` reached the compiler as an unknown argument `-lm`.
#pkgconfig lua5.4
#flag -lm

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

pub struct C.lua_State {}

fn C.luaL_newstate() &C.lua_State
fn C.luaL_openlibs(&C.lua_State)
fn C.luaL_loadbufferx(&C.lua_State, &char, usize, &char, &char) int
fn C.lua_pcallk(&C.lua_State, int, int, int, isize, voidptr) int
fn C.lua_close(&C.lua_State)
fn C.lua_gettop(&C.lua_State) int
fn C.lua_settop(&C.lua_State, int)
fn C.lua_type(&C.lua_State, int) int
fn C.lua_getfield(&C.lua_State, int, &char) int
fn C.lua_tolstring(&C.lua_State, int, &usize) &char
fn C.lua_toboolean(&C.lua_State, int) int
fn C.lua_tonumberx(&C.lua_State, int, &int) f64
fn C.lua_rawlen(&C.lua_State, int) usize
fn C.lua_rawgeti(&C.lua_State, int, i64) int
fn C.lua_next(&C.lua_State, int) int
fn C.lua_pushnil(&C.lua_State)
fn C.lua_pushvalue(&C.lua_State, int)
fn C.lua_createtable(&C.lua_State, int, int)
fn C.lua_setfield(&C.lua_State, int, &char)
fn C.lua_pushcclosure(&C.lua_State, voidptr, int)
fn C.lua_setglobal(&C.lua_State, &char)
fn C.lua_getglobal(&C.lua_State, &char) int

// The subset of Lua's type tags this needs to tell apart.
pub const type_nil = 0
pub const type_boolean = 1
pub const type_number = 3
pub const type_string = 4
pub const type_table = 5

pub struct State {
mut:
	handle &C.lua_State = unsafe { nil }
}

pub fn new() State {
	handle := C.luaL_newstate()
	C.luaL_openlibs(handle)
	return State{
		handle: handle
	}
}

pub fn (mut s State) close() {
	if !isnil(s.handle) {
		C.lua_close(s.handle)
		s.handle = unsafe { nil }
	}
}

// Runs a chunk and leaves its single return value on the stack.
//
// The chunk is named, which is what puts `config.lua:12:` in a Lua error rather than the entire
// source text: luaL_loadstring names the chunk after its own contents, so a syntax error in a
// forty-line config quoted all forty lines back. A leading `@` is how Lua marks a name as a file.
pub fn (mut s State) run(source string, name string) ! {
	chunk := '@' + name
	if C.luaL_loadbufferx(s.handle, source.str, usize(source.len), chunk.str, unsafe { nil }) != 0 {
		// No name prefix: the chunk is named, so Lua's own message already opens with file and line.
		return error(s.pop_error())
	}
	if C.lua_pcallk(s.handle, 0, 1, 0, 0, unsafe { nil }) != 0 {
		// No name prefix: the chunk is named, so Lua's own message already opens with file and line.
		return error(s.pop_error())
	}
}

// Lua leaves the message on the stack when a call fails; taking it off keeps the stack balanced
// for whatever the caller does next.
fn (mut s State) pop_error() string {
	message := s.text_at(-1)
	C.lua_settop(s.handle, -2)
	return if message == '' { 'unknown error' } else { message }
}

fn (s &State) text_at(index int) string {
	raw := C.lua_tolstring(s.handle, index, unsafe { nil })
	return if isnil(raw) { '' } else { unsafe { cstring_to_vstring(raw) } }
}

// --- reading the table left on the stack ------------------------------------------------------

pub fn (mut s State) top_is_table() bool {
	return C.lua_type(s.handle, -1) == type_table
}

// Pushes `table[key]` and says what it is. Every push has to be matched by a `pop`, or the stack
// grows for the rest of the run.
pub fn (mut s State) field(key string) int {
	return C.lua_getfield(s.handle, -1, key.str)
}

pub fn (mut s State) pop(n int) {
	C.lua_settop(s.handle, -n - 1)
}

pub fn (mut s State) as_text() ?string {
	if C.lua_type(s.handle, -1) !in [type_string, type_number] {
		return none
	}
	text := s.text_at(-1)
	return if text == '' { none } else { text }
}

pub fn (mut s State) as_number() ?f64 {
	if C.lua_type(s.handle, -1) != type_number {
		return none
	}
	return C.lua_tonumberx(s.handle, -1, unsafe { nil })
}

pub fn (mut s State) as_bool() ?bool {
	if C.lua_type(s.handle, -1) != type_boolean {
		return none
	}
	return C.lua_toboolean(s.handle, -1) != 0
}

// The keys of the table on top, as strings. Only string keys are reported: a config table mixing
// `{ foo = 1 }` with `{ 1, 2 }` is answered for its named half.
pub fn (mut s State) keys() []string {
	mut names := []string{}
	if !s.top_is_table() {
		return names
	}
	C.lua_pushnil(s.handle)
	for C.lua_next(s.handle, -2) != 0 {
		// key at -2, value at -1. Copy the key before reading it: lua_tolstring converts a number
		// key in place, which corrupts the iteration lua_next is in the middle of.
		C.lua_pushvalue(s.handle, -2)
		if C.lua_type(s.handle, -1) == type_string {
			names << s.text_at(-1)
		}
		C.lua_settop(s.handle, -2) // the copy
		C.lua_settop(s.handle, -2) // the value, leaving the key for the next lua_next
	}
	return names
}

// The length of the array part of the table on top.
pub fn (mut s State) len() int {
	if !s.top_is_table() {
		return 0
	}
	return int(C.lua_rawlen(s.handle, -1))
}

// Pushes the i-th element, counting from one as Lua does.
pub fn (mut s State) index(i int) int {
	return C.lua_rawgeti(s.handle, -1, i64(i))
}

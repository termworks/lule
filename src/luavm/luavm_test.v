module luavm

fn eval(source string) State {
	mut s := new()
	s.run(source, 'test') or { panic(err) }
	return s
}

fn test_a_table_comes_back() {
	mut s := eval('return { theme = "dark", loop = 300, norandom = true }')
	defer { s.close() }
	assert s.top_is_table()

	s.field('theme')
	assert s.as_text() or { '' } == 'dark'
	s.pop(1)

	s.field('loop')
	assert s.as_number() or { 0.0 } == 300.0
	s.pop(1)

	s.field('norandom')
	assert s.as_bool() or { false }
	s.pop(1)
}

fn test_a_missing_field_is_none_not_an_empty_value() {
	mut s := eval('return { theme = "dark" }')
	defer { s.close() }
	s.field('nothing')
	if _ := s.as_text() {
		assert false, 'a missing field answered as text'
	}
	if _ := s.as_number() {
		assert false, 'a missing field answered as a number'
	}
	s.pop(1)
}

fn test_named_keys_are_listed_in_full() {
	mut s := eval('return { alpha = 1, beta = 2, gamma = 3 }')
	defer { s.close() }
	mut names := s.keys()
	names.sort()
	assert names == ['alpha', 'beta', 'gamma']
}

fn test_listing_keys_leaves_the_stack_where_it_was() {
	// lua_next is a stateful walk; getting the pops wrong grows the stack every call and the
	// table under it stops being at -1.
	mut s := eval('return { a = 1, b = 2 }')
	defer { s.close() }
	before := C.lua_gettop(s.handle)
	s.keys()
	s.keys()
	assert C.lua_gettop(s.handle) == before
	assert s.top_is_table(), 'the table is no longer on top'
}

fn test_numeric_keys_do_not_corrupt_the_walk() {
	// lua_tolstring converts a number key in place, which breaks the iteration it is inside.
	// Copying the key first is what makes a mixed table safe to walk.
	mut s := eval('return { 10, 20, named = "x", 30 }')
	defer { s.close() }
	assert s.keys() == ['named']
	assert s.len() == 3
}

fn test_array_access() {
	mut s := eval('return { "one", "two", "three" }')
	defer { s.close() }
	assert s.len() == 3
	s.index(2)
	assert s.as_text() or { '' } == 'two'
	s.pop(1)
}

fn test_nested_tables() {
	mut s := eval('return { templates = { kitty = { input = "in", output = "out" } } }')
	defer { s.close() }
	s.field('templates')
	assert s.top_is_table()
	s.field('kitty')
	s.field('input')
	assert s.as_text() or { '' } == 'in'
	s.pop(1)
	s.field('output')
	assert s.as_text() or { '' } == 'out'
	// Three are on the stack here - root, templates, kitty - so two pops return to root.
	s.pop(2)
	assert s.top_is_table()
}

fn test_a_syntax_error_is_reported_not_fatal() {
	mut s := new()
	defer { s.close() }
	s.run('this is not lua', 'bad.lua') or {
		assert err.msg().contains('bad.lua')
		return
	}
	assert false, 'broken lua was accepted'
}

fn test_a_runtime_error_is_reported() {
	mut s := new()
	defer { s.close() }
	s.run('error("deliberate")', 'boom.lua') or {
		assert err.msg().contains('deliberate')
		return
	}
	assert false, 'a raising script was accepted'
}

fn test_the_standard_library_is_available() {
	// A config that computes is the whole reason for choosing Lua over toml.
	mut s := eval('local out = {} for i = 1, 3 do out[#out+1] = "n" .. i end
return { joined = table.concat(out, ",") }')
	defer { s.close() }
	s.field('joined')
	assert s.as_text() or { '' } == 'n1,n2,n3'
	s.pop(1)
}

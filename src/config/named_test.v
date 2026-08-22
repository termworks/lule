module config

import os
import cmd

fn write_scheme_file(dir string, name string, body string) string {
	path := os.join_path(dir, name)
	os.write_file(path, body) or { panic(err) }
	return path
}

fn test_named_scheme_reads_hex_and_ignores_prose() {
	tmp := os.join_path(os.temp_dir(), 'lule_scheme_test_${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}

	write_scheme_file(tmp, 'demo', '# gruvbox dark, a heading
# abc are the accent colours
#cc241d
#98971a

  #d79921
458588
not a colour at all
#12345
')
	colors := named_scheme(tmp, 'demo')

	// `# abc are the accent colours` starts with a hash and three hex characters. Parsed loosely
	// it becomes #aabbcc and joins the palette; it must not.
	assert '#aabbcc' !in colors
	assert colors == ['#cc241d', '#98971a', '#d79921', '#458588']
}

fn test_named_scheme_accepts_short_hex() {
	tmp := os.join_path(os.temp_dir(), 'lule_short_test_${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	write_scheme_file(tmp, 'short', '#abc\nfff\n')
	assert named_scheme(tmp, 'short') == ['#aabbcc', '#ffffff']
}

fn test_named_scheme_finds_suffixed_files() {
	tmp := os.join_path(os.temp_dir(), 'lule_suffix_test_${os.getpid()}')
	os.mkdir_all(tmp) or { panic(err) }
	defer {
		os.rmdir_all(tmp) or {}
	}
	write_scheme_file(tmp, 'nord.txt', '#2e3440\n#88c0d0\n')
	assert named_scheme(tmp, 'nord') == ['#2e3440', '#88c0d0']
}

// Being pointed somewhere that holds no config is worth saying out loud; the default location
// being empty is the ordinary case and stays quiet.
fn test_an_explicit_config_dir_with_no_init_lua_is_located_anyway() {
	dir := os.join_path(os.temp_dir(), 'lule_noconfig_${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	mut scheme := Scheme{}
	locate_config(cmd.parse_args(['create', '--configs=${dir}', '--', 'set']), mut scheme)
	assert scheme.config == dir
	assert !os.is_file(config_path(dir))
}

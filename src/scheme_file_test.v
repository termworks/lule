module main

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

fn test_no_scripts_flag_is_recognised() {
	assert cmd.parse_args(['create', '--no-scripts', '--', 'set']).present['no-scripts']
	assert cmd.parse_args(['create', '-n', '--', 'set']).present['n']
}

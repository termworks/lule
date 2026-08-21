module main

import os

pub const version = '0.5.0'
pub const description = "a command line to set 255 colors on tty's and other places that use ANSI colors"

pub struct Args {
pub mut:
	subcommand string
	action     string
	flags      map[string]string
	multi      map[string][]string
	present    map[string]bool
}

const subcommands = ['create', 'daemon', 'colors', 'config', 'test']

const multi_flags = ['pattern', 'script']

// The palette extractors that exist. `--palette` used to accept anything.
pub const known_palettes = ['pigment']

// clap's InferSubcommands: accept any unambiguous prefix
fn resolve_subcommand(name string) string {
	if name in subcommands {
		return name
	}
	mut hits := []string{}
	for s in subcommands {
		if s.starts_with(name) {
			hits << s
		}
	}
	if hits.len == 1 {
		return hits[0]
	}
	return ''
}

fn split_flag(arg string) (string, string, bool) {
	body := arg.trim_string_left('--')
	if body.contains('=') {
		idx := body.index('=') or { return body, '', false }
		return body[..idx], body[idx + 1..], true
	}
	return body, '', false
}

pub fn parse_args(argv []string) Args {
	mut a := Args{}
	mut i := 0
	mut after_sep := false

	for i < argv.len {
		arg := argv[i]
		i++

		if arg == '--' {
			after_sep = true
			continue
		}
		if after_sep {
			a.action = arg
			continue
		}
		if arg.starts_with('--') {
			name, value, has_value := split_flag(arg)
			key := normalize_flag(name)
			if has_value {
				if key in multi_flags {
					a.multi[key] << value
				} else {
					a.flags[key] = value
				}
			} else {
				a.present[key] = true
			}
			continue
		}
		if arg.starts_with('-') && arg.len > 1 {
			for ch in arg[1..] {
				a.present[ch.ascii_str()] = true
			}
			continue
		}
		if a.subcommand == '' {
			resolved := resolve_subcommand(arg)
			if resolved != '' {
				a.subcommand = resolved
				continue
			}
		}
		if a.action == '' {
			a.action = arg
		}
	}
	return a
}

fn normalize_flag(name string) string {
	return match name {
		'path' { 'wallpath' }
		'source' { 'image' }
		else { name }
	}
}

pub fn print_help(logo string) {
	if logo != '' {
		println(logo)
	}
	println('lule ${version}')
	println(description)
	println('')
	println('USAGE:')
	println('    lule [OPTIONS] <SUBCOMMAND> [-- <ACTION>]')
	println('')
	println('OPTIONS:')
	println('        --configs=<PATH>       specify a dir to load color configs from')
	println('        --cache=<PATH>         specify a dir where to dump color caches')
	println('        --pattern=<PATH:PATH>  specify a path to substitute pattern colors')
	println('        --script=<PATH>        specify a script to run after colors are generated')
	println('    -n, --no-scripts           generate colors but run no scripts at all')
	println('    -h, --help                 Prints help information')
	println('    -V, --version              Prints version information')
	println('')
	println('SUBCOMMANDS:')
	println('    create    Generate new colors from an image')
	println('                --wallpath=<DIRPATH>  folder to pick an image randomly')
	println('                --image=<FILEPATH>    image to extract colors from')
	println('                --palette=<NAME>      pigment (default)')
	println('                --scheme=<NAME>       color scheme from configs')
	println('                --theme=<THEME>       dark (default) | light')
	println('                --sort=<MODE>         dominance (default) | hue | light | dark | chroma')
	println('                --saturation=<N>      -1.0 grey .. 0 unchanged .. 1.0 doubled')
	println('                --illumination=<N>    -1.0 darker .. 0 unchanged .. 1.0 lighter')
	println('                --hue=<DEGREES>       rotate every pigment round the wheel')
	println('                --blend=<N>           0 unchanged .. 1.0 all one hue')
	println('                --seed=<N>            same wallpaper, same scheme, every time')
	println('                --norandom            fixed RGB ramps instead of random ones')
	println('                -- <set|regen>')
	println('    daemon    Run as daemon process with looping wallpapers')
	println('                --loop=<SECONDS>      loop time (default 300)')
	println('                -- <start|stop|next|detach|status>')
	println('    colors    Display current colors in terminal')
	println('                -g                    generate new colors, just show them')
	println('                -- <image|ansii|list|mix|json>')
	println('    config    Send specific configs to pipe or daemon')
	println('                --theme=<THEME>       dark | light')
	println('')
}

pub fn read_logo() string {
	exe_dir := os.dir(os.executable())
	candidates := [
		os.join_path(exe_dir, '..', 'resources', 'logo.txt'),
		os.join_path(exe_dir, 'resources', 'logo.txt'),
		'resources/logo.txt',
	]
	for c in candidates {
		if content := os.read_file(c) {
			return content
		}
	}
	return ''
}

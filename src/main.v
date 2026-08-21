module main

import os

fn cmd_create(a &Args, mut scheme Scheme) {
	concatinate(a, mut scheme, a.action != 'regen')
	match a.action {
		'set' { write_colors(mut scheme, false) }
		'regen' { write_colors(mut scheme, true) }
		else { write_colors(mut scheme, false) }
	}
}

fn cmd_colors(a &Args, mut scheme Scheme) {
	concatinate(a, mut scheme, a.present['g'])
	scheme.scripts = []

	if a.present['g'] {
		write_colors(mut scheme, false)
	}

	if scheme.cache != '' {
		cached := colors_from_file(os.join_path(scheme.cache, 'colors'))
		if cached.len > 0 {
			scheme.colors = cached
		}
		if content := file_to_string(os.join_path(scheme.cache, 'wallpaper')) {
			scheme.image = content
		}
		if content := file_to_string(os.join_path(scheme.cache, 'theme')) {
			scheme.theme = content
		}
	}

	if scheme.colors.len == 0 {
		eprintln('${red_bold('error:')} no colors cached yet - run ${yellow('lule create -- set')} first')
		exit(1)
	}

	cols, rows := term_size()
	action := if a.action == '' { 'ansii' } else { a.action }

	if !is_tty_stdout() {
		for color in scheme.colors {
			println(color.to_hex(true))
		}
		return
	}

	match action {
		'image' {
			display_image(scheme.image, cols, rows - 1) or {}
		}
		'ansii' {
			show_colors(scheme, 0, 256, 4)
		}
		'list' {
			show_pastel_colors(scheme, 0, 256)
		}
		'mix' {
			display_image(scheme.image, cols, rows - 3) or {}
			println('Wallpaper: ${scheme.image}, \t\t Colors: 1-16')
			show_colors(scheme, 0, 16, pad_for(cols))
		}
		else {
			show_colors(scheme, 0, 256, 4)
		}
	}
}

fn pad_for(cols int) int {
	if cols <= 56 {
		return 1
	}
	return (cols - 56) / 16
}

fn cmd_config(a &Args, mut scheme Scheme) {
	concatinate(a, mut scheme, false)
	payload := scheme.to_json()
	if !is_tty_stdout() {
		println(payload)
	} else {
		write_to_file(temp_path('lule_pipe'), payload)
	}
}

fn cmd_test(a &Args, mut scheme Scheme) {
	defs_concatinate(mut scheme)
	envi_concatinate(mut scheme)
	args_concatinate(a, mut scheme)
	pipe_concatinate(mut scheme)

	if scheme.image == '' {
		if scheme.walldir == '' {
			eprintln('${red_bold('error:')} no image or wallpath given')
			exit(1)
		}
		scheme.image = random_image(scheme.walldir)
	}

	palette := palette_from_image(scheme.image)
	scheme.pigments = palette
	scheme.colors = get_all_colors(mut scheme)

	cols, rows := term_size()
	display_image(scheme.image, cols - 10, rows - 13) or {}
	println('Palette')
	mut colors := []Color{}
	for hexstr in palette {
		colors << color_from_hex(hexstr)
	}
	show_specified_colors(colors, pad_for(cols))
	println('\n6th')
	show_specified_colors(gen_main_six(colors), pad_for(cols))
	println('\nColors')
	show_colors(scheme, 0, 16, pad_for(cols))

	pattern_generation(scheme)
}

fn main() {
	argv := os.args[1..]
	mut scheme := Scheme{}

	if argv.len == 0 {
		print_help(read_logo())
		return
	}

	a := parse_args(argv)

	if a.present['help'] || a.present['h'] {
		print_help(read_logo())
		return
	}
	if a.present['version'] || a.present['V'] {
		println('lule ${version}')
		return
	}

	match a.subcommand {
		'create' {
			cmd_create(a, mut scheme)
		}
		'colors' {
			cmd_colors(a, mut scheme)
		}
		'config' {
			cmd_config(a, mut scheme)
		}
		'daemon' {
			concatinate(a, mut scheme, a.action == 'start' || a.action == 'detach')
			run_daemon(a, mut scheme)
		}
		'test' {
			cmd_test(a, mut scheme)
		}
		else {
			print_help(read_logo())
		}
	}
}

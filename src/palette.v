module main

import color
import os
import palette

pub fn palette_from_image(image string, backend string) []string {
	colors_lab := palette.pigments(image, 16, 300, backend) or {
		eprintln('${red_bold('error:')} Problem creating palette -> ${err}')
		exit(1)
	}
	mut colors := []string{}
	for pg in colors_lab {
		lab_color := color.color_from_lab(pg.color.l, pg.color.a, pg.color.b, 1.0)
		colors << lab_color.to_hex(true)
	}
	return colors
}

pub fn colors_from_file(path string) []color.Color {
	mut colors := []color.Color{}
	for line in lines_to_vec(path) {
		colors << color.color_from_hex(line)
	}
	return colors
}

// Loads a named scheme from the configs directory: a file of hex colours, one per line, blank
// lines and `#`-comments ignored. This is what makes `--configs` and `--scheme` mean something;
// before, both were parsed, stored and never read.
pub fn named_scheme(config_dir string, name string) []string {
	if config_dir == '' {
		eprintln('${red_bold('error:')} no configs directory; set ${yellow('$LULE_C')} or pass ${yellow('--configs')}')
		exit(1)
	}
	mut tried := []string{}
	for candidate in [name, '${name}.txt', '${name}.colors'] {
		path := os.join_path(config_dir, candidate)
		tried << path
		if !os.is_file(path) {
			continue
		}
		mut colors := []string{}
		for line in lines_to_vec(path) {
			// The whole token has to be a colour, not merely start like one — otherwise a
			// comment such as `# abc are the accents` parses as #aabbcc and joins the palette.
			token := line.trim_space().trim_string_left('#')
			if token.len != 3 && token.len != 6 {
				continue
			}
			if token.bytes().any(color.hex_val(it) < 0) {
				continue
			}
			colors << color.color_from_hex(token).to_hex(true)
		}
		if colors.len == 0 {
			eprintln('${red_bold('error:')} ${yellow(path)} holds no hex colours')
			exit(1)
		}
		return colors
	}
	eprintln('${red_bold('error:')} no scheme named ${yellow(name)}')
	for path in tried {
		eprintln('${red_bold('error:')}   looked in ${path}')
	}
	exit(1)
}

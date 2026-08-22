module main

import paths
import ui
import color
import palette

pub fn palette_from_image(image string, backend string) []string {
	colors_lab := palette.pigments(image, 16, 300, backend) or {
		eprintln('${ui.red_bold('error:')} Problem creating palette -> ${err}')
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
	for line in paths.lines_to_vec(path) {
		colors << color.color_from_hex(line)
	}
	return colors
}

module main

pub fn palette_from_image(image string) []string {
	colors_lab := pigments(image, 16, 300) or {
		eprintln('${red_bold('error:')} Problem creating palette -> ${err}')
		exit(1)
	}
	mut colors := []string{}
	for pg in colors_lab {
		lab_color := color_from_lab(pg.color.l, pg.color.a, pg.color.b, 1.0)
		colors << lab_color.to_hex(true)
	}
	return colors
}

pub fn colors_from_file(path string) []Color {
	mut colors := []Color{}
	for line in lines_to_vec(path) {
		colors << color_from_hex(line)
	}
	return colors
}

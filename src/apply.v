module main

import os

pub fn write_colors(mut scheme Scheme, old bool) {
	if old {
		if scheme.cache != '' {
			scheme.pigments = lines_to_vec(os.join_path(scheme.cache, 'palette'))
			if content := file_to_string(os.join_path(scheme.cache, 'wallpaper')) {
				scheme.image = content
			}
			if content := file_to_string(os.join_path(scheme.cache, 'theme')) {
				scheme.theme = content
			}
		}
	} else {
		if scheme.image == '' {
			scheme.image = random_image(scheme.walldir)
		}
		if scheme.palette == 'pigment' {
			palette := palette_from_image(scheme.image)
			write_temp_file('lule_palette', palette.join('\n'))
			scheme.pigments = palette
		}
	}

	scheme.colors = get_all_colors(mut scheme)

	values := output_to_json(scheme, false)
	write_temp(scheme)
	write_cache(scheme)
	write_cache_json(scheme, values)
	if scheme.scripts.len > 0 {
		command_execution(scheme)
	}
}

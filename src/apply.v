module main

import os

pub fn write_colors(mut scheme Scheme, old bool) {
	// Seeded here as well as in get_all_colors, because k-means++ picks its starting centres at
	// random: without this the extracted pigments differ run to run and the seed only fixes half
	// the pipeline.
	seed_rand(scheme.seed)
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
		// Without this, an empty cache regenerated a full 256-colour ramp out of nothing: the
		// palette padding in gen_main_six invents grey when it is handed no pigments, so the
		// command reported success and wrote a grey scheme over the caller's colours.
		if scheme.pigments.len == 0 {
			eprintln('${red_bold('error:')} nothing cached to regenerate from')
			eprintln('${red_bold('error:')} run ${yellow('lule create -- set')} first')
			exit(1)
		}
	} else if scheme.scheme != '' {
		// A named scheme from the configs directory: a file of hex colours, one per line, used
		// instead of extracting from a wallpaper. The wallpaper is still recorded so the rest of
		// the pipeline and any templates still know what is on screen.
		scheme.pigments = named_scheme(scheme.config, scheme.scheme)
		if scheme.image == '' && scheme.walldir != '' {
			scheme.image = random_image(scheme.walldir)
		}
		write_temp_file('lule_palette', scheme.pigments.join('\n'))
	} else {
		if scheme.image == '' {
			scheme.image = random_image(scheme.walldir)
		}
		if scheme.palette in known_palettes {
			palette := palette_from_image(scheme.image, scheme.palette)
			write_temp_file('lule_palette', palette.join('\n'))
			scheme.pigments = palette
		}
	}

	scheme.colors = get_all_colors(mut scheme)

	values := output_to_json(scheme, false)
	write_temp(scheme)
	write_cache(scheme)
	write_cache_json(scheme, values)
	// Before the scripts, not after: a script's usual job is to reload the programs whose config
	// these templates just rewrote, and reloading them before the rewrite reloads the old colours.
	//
	// This was only ever called from the hidden `test` subcommand, so `--pattern` silently did
	// nothing during normal use - and the config file's whole purpose is templates on `create`.
	pattern_generation(scheme)

	if scheme.scripts.len > 0 {
		command_execution(scheme)
	}
}

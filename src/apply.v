module main

import wallpaper
import config
import paths
import ui
import os
import cmd

pub fn write_colors(mut scheme config.Scheme, old bool, mut hooks config.Hooks) {
	// Seeded here as well as in get_all_colors, because k-means++ picks its starting centres at
	// random: without this the extracted pigments differ run to run and the seed only fixes half
	// the pipeline.
	seed_rand(scheme.seed)
	if old {
		if scheme.cache != '' {
			scheme.pigments = paths.lines_to_vec(os.join_path(scheme.cache, 'palette'))
			if content := paths.file_to_string(os.join_path(scheme.cache, 'wallpaper')) {
				scheme.image = content
			}
			if content := paths.file_to_string(os.join_path(scheme.cache, 'theme')) {
				scheme.theme = content
			}
		}
		// Without this, an empty cache regenerated a full 256-colour ramp out of nothing: the
		// palette padding in gen_main_six invents grey when it is handed no pigments, so the
		// command reported success and wrote a grey scheme over the caller's colours.
		if scheme.pigments.len == 0 {
			eprintln('${ui.red_bold('error:')} nothing cached to regenerate from')
			eprintln('${ui.red_bold('error:')} run ${ui.yellow('lule create -- set')} first')
			exit(1)
		}
	} else if scheme.scheme != '' {
		// A named scheme from the configs directory: a file of hex colours, one per line, used
		// instead of extracting from a wallpaper. The wallpaper is still recorded so the rest of
		// the pipeline and any templates still know what is on screen.
		scheme.pigments = config.named_scheme(scheme.config, scheme.scheme)
		if scheme.image == '' && scheme.walldir != '' {
			scheme.image = wallpaper.random_image(scheme.walldir)
		}
		paths.write_temp_file('lule_palette', scheme.pigments.join('\n'))
	} else {
		if scheme.image == '' {
			scheme.image = wallpaper.random_image(scheme.walldir)
		}
		known := cmd.known_palettes()
		if scheme.palette in known {
			palette := palette_from_image(scheme.image, scheme.palette)
			paths.write_temp_file('lule_palette', palette.join('\n'))
			scheme.pigments = palette
		}
	}

	scheme.colors = get_all_colors(mut scheme)

	values := output_to_json(scheme, false)
	write_temp(scheme)
	write_cache(scheme)
	write_cache_json(scheme, values)
	// Before the `after` hook, so a hook that reloads a program is reloading the config this just
	// rewrote rather than the previous one.
	//
	// This was only ever called from the hidden `test` subcommand, so `--pattern` silently did
	// nothing during normal use - and the config file's whole purpose is templates on `create`.
	pattern_generation(scheme)

	// Last, once the colours, the cache and the templates are all written — so the hook sees the
	// same finished state anything else would.
	hooks.after(scheme)
}

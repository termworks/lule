module main

import config
import paths
import os
import json

pub fn write_temp(scheme &config.Scheme) {
	if scheme.colors.len > 0 {
		mut record := []string{}
		for swatch in scheme.colors {
			record << swatch.to_hex(true)
		}
		paths.write_temp_file('lule_colors', record.join('\n'))
	}
	if scheme.image != '' {
		paths.write_temp_file('lule_wallpaper', scheme.image)
	}
	if scheme.theme != '' {
		paths.write_temp_file('lule_theme', scheme.theme)
	}
	paths.write_temp_file('lule_scheme', scheme.to_json())
}

// Written from the scheme rather than copied out of /tmp.
//
// Copying meant the cache picked up whatever a *previous* run had left at the fixed temp paths:
// `--palette=<something unknown>` extracted no pigments, and the cache was then filled from an
// earlier run's /tmp/lule_palette — a scheme built out of another wallpaper's colours, reported
// as success. The temp files are still written for anything that reads them; they are just no
// longer the route the cache is filled by.
pub fn write_cache(scheme &config.Scheme) {
	if scheme.cache == '' {
		return
	}
	os.mkdir_all(scheme.cache) or {}

	if scheme.colors.len > 0 {
		mut record := []string{}
		for swatch in scheme.colors {
			record << swatch.to_hex(true)
		}
		paths.write_to_file(os.join_path(scheme.cache, 'colors'), record.join('\n'))
	}
	if scheme.pigments.len > 0 {
		paths.write_to_file(os.join_path(scheme.cache, 'palette'), scheme.pigments.join('\n'))
	}
	if scheme.image != '' {
		paths.write_to_file(os.join_path(scheme.cache, 'wallpaper'), scheme.image)
	}
	if scheme.theme != '' {
		paths.write_to_file(os.join_path(scheme.cache, 'theme'), scheme.theme)
	}
}

pub fn write_cache_json(scheme &config.Scheme, payload string) {
	if scheme.cache == '' {
		return
	}
	os.mkdir_all(scheme.cache) or {}
	paths.write_to_file(os.join_path(scheme.cache, 'colors.json'), payload)
}

pub fn output_to_json(scheme &config.Scheme, as_map bool) string {
	mut color_vec := []string{}
	mut color_map := map[string]string{}
	for key, color in scheme.colors {
		color_map['color${key}'] = color.to_hex(true)
		color_vec << color.to_hex(true)
	}
	if color_vec.len < 16 {
		return '{}'
	}
	special := config.Special{
		background: color_vec[0]
		foreground: color_vec[15]
		cursor:     color_vec[1]
	}
	if as_map {
		return json.encode_pretty(config.ProfileMap{
			wallpaper: scheme.image
			theme:     scheme.theme
			special:   special
			colors:    color_map
		})
	}
	return json.encode_pretty(config.ProfileVec{
		wallpaper: scheme.image
		theme:     scheme.theme
		special:   special
		colors:    color_vec
	})
}

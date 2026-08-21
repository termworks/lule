module main

import os
import json

pub fn write_temp(scheme &Scheme) {
	if scheme.colors.len > 0 {
		mut record := []string{}
		for color in scheme.colors {
			record << color.to_hex(true)
		}
		write_temp_file('lule_colors', record.join('\n'))
	}
	if scheme.image != '' {
		write_temp_file('lule_wallpaper', scheme.image)
	}
	if scheme.theme != '' {
		write_temp_file('lule_theme', scheme.theme)
	}
	write_temp_file('lule_scheme', scheme.to_json())
}

// Written from the scheme rather than copied out of /tmp.
//
// Copying meant the cache picked up whatever a *previous* run had left at the fixed temp paths:
// `--palette=<something unknown>` extracted no pigments, and the cache was then filled from an
// earlier run's /tmp/lule_palette — a scheme built out of another wallpaper's colours, reported
// as success. The temp files are still written for scripts that read them; they are just no
// longer the route the cache is filled by.
pub fn write_cache(scheme &Scheme) {
	if scheme.cache == '' {
		return
	}
	os.mkdir_all(scheme.cache) or {}

	if scheme.colors.len > 0 {
		mut record := []string{}
		for color in scheme.colors {
			record << color.to_hex(true)
		}
		write_to_file(os.join_path(scheme.cache, 'colors'), record.join('\n'))
	}
	if scheme.pigments.len > 0 {
		write_to_file(os.join_path(scheme.cache, 'palette'), scheme.pigments.join('\n'))
	}
	if scheme.image != '' {
		write_to_file(os.join_path(scheme.cache, 'wallpaper'), scheme.image)
	}
	if scheme.theme != '' {
		write_to_file(os.join_path(scheme.cache, 'theme'), scheme.theme)
	}
}

pub fn write_cache_json(scheme &Scheme, payload string) {
	if scheme.cache == '' {
		return
	}
	os.mkdir_all(scheme.cache) or {}
	write_to_file(os.join_path(scheme.cache, 'colors.json'), payload)
}

pub fn output_to_json(scheme &Scheme, as_map bool) string {
	mut color_vec := []string{}
	mut color_map := map[string]string{}
	for key, color in scheme.colors {
		color_map['color${key}'] = color.to_hex(true)
		color_vec << color.to_hex(true)
	}
	if color_vec.len < 16 {
		return '{}'
	}
	special := Special{
		background: color_vec[0]
		foreground: color_vec[15]
		cursor:     color_vec[1]
	}
	if as_map {
		return json.encode_pretty(ProfileMap{
			wallpaper: scheme.image
			theme:     scheme.theme
			special:   special
			colors:    color_map
		})
	}
	return json.encode_pretty(ProfileVec{
		wallpaper: scheme.image
		theme:     scheme.theme
		special:   special
		colors:    color_vec
	})
}

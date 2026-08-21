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

pub fn write_cache(scheme &Scheme) {
	if scheme.cache == '' {
		return
	}
	os.mkdir_all(scheme.cache) or {}
	copy_to(temp_path('lule_colors'), os.join_path(scheme.cache, 'colors'))
	copy_to(temp_path('lule_wallpaper'), os.join_path(scheme.cache, 'wallpaper'))
	copy_to(temp_path('lule_theme'), os.join_path(scheme.cache, 'theme'))
	copy_to(temp_path('lule_palette'), os.join_path(scheme.cache, 'palette'))
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

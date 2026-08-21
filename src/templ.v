module main

import os

// Substitutes {{ name }} placeholders, matching the previous Tera templates
fn render_template(content string, scheme &Scheme) string {
	mut vars := map[string]string{}
	for i, color in scheme.colors {
		vars['color${i}'] = color.to_hex(false)
	}
	if scheme.colors.len > 15 {
		vars['background'] = scheme.colors[0].to_hex(false)
		vars['foreground'] = scheme.colors[15].to_hex(false)
		vars['cursor'] = scheme.colors[1].to_hex(false)
		vars['accent'] = scheme.colors[1].to_hex(false)
	}
	vars['wallpaper'] = scheme.image
	vars['theme'] = scheme.theme

	mut out := content
	for key, value in vars {
		out = out.replace('{{ ${key} }}', value)
		out = out.replace('{{${key}}}', value)
	}
	return out
}

pub fn generate_template(original string, replaced string, scheme &Scheme) ! {
	content := file_to_string(original)!
	write_to_file(replaced, render_template(content, scheme))
}

pub fn pattern_generation(scheme &Scheme) {
	for p in scheme.patterns {
		if os.exists(p.from) && os.exists(p.to) {
			generate_template(p.from, p.to, scheme) or {
				println('failed generating ${p.from} -> ${err}')
				continue
			}
			println('generating :${p.from} into: ${p.to}')
		} else {
			println('${p.from} or ${p.to} is not a valid file')
		}
	}
}

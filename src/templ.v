module main

import config
import paths
import ui
import os
import color
import template

pub fn generate_template(original string, replaced string, scheme &config.Scheme) ! {
	content := paths.file_to_string(original)!
	rendered, problems := template.render_in(content, template_context(scheme), os.dir(original))
	for problem in problems {
		eprintln('${ui.yellow('warning:')} ${original}: ${problem}')
	}
	paths.write_to_file(replaced, rendered)
}

pub fn pattern_generation(scheme &config.Scheme) {
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

// Everything a template can name.
pub fn template_context(scheme &config.Scheme) map[string]template.TplValue {
	mut ctx := map[string]template.TplValue{}
	for i, color in scheme.colors {
		ctx['color${i}'] = template.TplValue(color)
	}
	if scheme.colors.len > 15 {
		ctx['background'] = template.TplValue(scheme.colors[0])
		ctx['foreground'] = template.TplValue(scheme.colors[15])
		ctx['cursor'] = template.TplValue(scheme.colors[1])
		ctx['accent'] = template.TplValue(scheme.colors[1])
	}
	mut extracted := []color.Color{}
	for hex in scheme.pigments {
		extracted << color.color_from_hex(hex)
	}
	ctx['colors'] = template.TplValue(scheme.colors)
	// The sixteen a terminal actually uses. `colors` holds all 256, and a template wanting only
	// the ANSI set had no way to stop at sixteen: there is no dynamic lookup by index, and a
	// loop cannot break early.
	if scheme.colors.len >= 16 {
		ctx['ansi'] = template.TplValue(scheme.colors[..16].clone())
	}
	ctx['pigments'] = template.TplValue(extracted)
	ctx['wallpaper'] = template.TplValue(scheme.image)
	ctx['theme'] = template.TplValue(scheme.theme)
	ctx['dark'] = template.TplValue(scheme.is_dark())
	ctx['light'] = template.TplValue(!scheme.is_dark())
	return ctx
}

// `dir` is where a relative `<* include *>` is resolved from - the directory of the template
// being rendered, so an include means the file beside it rather than beside the shell.

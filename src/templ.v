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
	// The directory too: a template pointed at an application that has never been configured names
	// an output whose parent does not exist yet.
	os.mkdir_all(os.dir(replaced)) or {}
	paths.write_to_file(replaced, rendered)
}

// Only the input has to exist. Requiring the output to exist as well meant a template could never
// render the first time - the file it was supposed to create had to be created by hand before lule
// would create it - and the run reported that as `is not a valid file` without saying which of the
// two it meant.
pub fn pattern_generation(scheme &config.Scheme) {
	for p in scheme.patterns {
		if !os.exists(p.from) {
			eprintln('${ui.yellow('warning:')} template ${ui.yellow(p.from)} does not exist')
			continue
		}
		generate_template(p.from, p.to, scheme) or {
			eprintln('${ui.yellow('warning:')} ${p.from}: ${err}')
			continue
		}
		println('generating :${p.from} into: ${p.to}')
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

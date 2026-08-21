module main

import template { TplValue }

// These reach for Scheme and template_context, which live here rather than in the engine: the
// engine takes a plain map so it never has to know what a colour scheme is.

fn test_template_context_exposes_the_scheme() {
	mut scheme := Scheme{
		theme:    'light'
		image:    '/w/a.png'
		pigments: ['#123456', '#654321']
	}
	scheme.colors = get_all_colors(mut scheme)
	c := template_context(&scheme)

	assert c['theme'] or { TplValue('') }.display() == 'light'
	assert c['wallpaper'] or { TplValue('') }.display() == '/w/a.png'
	assert c['dark'] or { TplValue(true) }.display() == 'false'
	assert c['light'] or { TplValue(false) }.display() == 'true'
	// color0..color255, plus the named aliases.
	assert (c['color0'] or { TplValue('') }).display() == (c['background'] or { TplValue('x') }).display()
	assert (c['color255'] or { TplValue('') }).display().len == 6
}

fn test_ansi_exposes_only_the_sixteen() {
	// `colors` is all 256. A template wanting the ANSI set had no way to stop at sixteen: there
	// is no dynamic lookup by index, and a loop cannot break early.
	mut scheme := Scheme{
		theme:    'dark'
		pigments: ['#3f51b5', '#e91e63', '#4caf50', '#ff9800']
	}
	scheme.colors = get_all_colors(mut scheme)
	c := template_context(&scheme)

	out, problems := template.render('<* for x in ansi *>{{ loop_index }} <* endfor *>', c)
	assert problems.len == 0, '${problems}'
	assert out == '0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 '

	// And it is the same sixteen the palette starts with.
	first, _ := template.render('{{ color0.hex }}', c)
	ansi_first, _ :=
		template.render('<* for x in ansi *><* if loop_first *>{{ x.hex }}<* endif *><* endfor *>', c)
	assert first == ansi_first
}

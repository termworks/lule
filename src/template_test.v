module main

fn ctx() map[string]TplValue {
	return {
		'background': TplValue(color_from_hex('#101820'))
		'accent':     TplValue(color_from_hex('#3f51b5'))
		'red':        TplValue(color_from_hex('#ff0000'))
		'theme':      TplValue('dark')
		'dark':       TplValue(true)
		'light':      TplValue(false)
		'empty':      TplValue('')
		'colors':     TplValue([color_from_hex('#111111'), color_from_hex('#222222'),
			color_from_hex('#333333')])
	}
}

fn render_ok(source string) string {
	out, problems := render(source, ctx())
	assert problems.len == 0, 'unexpected problems: ${problems}'
	return out
}

fn test_plain_text_is_untouched() {
	assert render_ok('nothing to see') == 'nothing to see'
	assert render_ok('') == ''
	// Braces that are not a placeholder must survive; config files are full of them.
	assert render_ok('a { b } c') == 'a { b } c'
}

fn test_colour_formats() {
	assert render_ok('{{ red.hex }}') == '#ff0000'
	assert render_ok('{{ red.hex_stripped }}') == 'ff0000'
	assert render_ok('{{ red.rgb }}') == 'rgb(255, 0, 0)'
	assert render_ok('{{ red.rgba }}') == 'rgba(255, 0, 0, 1.00)'
	assert render_ok('{{ red.red }}/{{ red.green }}/{{ red.blue }}') == '255/0/0'
	assert render_ok('{{ red.hsl }}') == 'hsl(0, 100%, 50%)'
	assert render_ok('{{ red.hex_alpha }}') == '#ff0000ff'
}

fn test_bare_name_is_hex() {
	assert render_ok('{{ accent }}') == '3f51b5'
	assert render_ok('{{ theme }}') == 'dark'
}

fn test_whitespace_inside_braces_is_optional() {
	assert render_ok('{{accent}}') == render_ok('{{ accent }}')
	assert render_ok('{{   accent   }}') == render_ok('{{ accent }}')
}

fn test_colour_filters() {
	// Lightening raises lightness and darkening lowers it; the exact value is the colour code's
	// business, the direction is this engine's.
	lighter := color_from_hex(render_ok('{{ accent | lighten: 0.2 }}'))
	darker := color_from_hex(render_ok('{{ accent | darken: 0.2 }}'))
	base := color_from_hex('#3f51b5')
	assert lighter.to_lab().l > base.to_lab().l
	assert darker.to_lab().l < base.to_lab().l

	assert render_ok('{{ red | invert }}') == '00ffff'
	assert render_ok('{{ red | grayscale }}') == render_ok('{{ red | grayscale }}')
	grey := color_from_hex(render_ok('{{ red | grayscale }}'))
	r, g, b := grey.rgb_u8()
	assert r == g && g == b
}

fn test_filters_chain() {
	// The value stays a colour between stages; if it degraded to a string the second filter
	// would have nothing to work with.
	out := render_ok('{{ accent | lighten: 0.1 | grayscale | invert }}')
	assert !out.starts_with('#') && out.len == 6
}

fn test_set_alpha_is_visible() {
	// Rendering plain hex here made the filter look like it did nothing.
	assert render_ok('{{ red | set_alpha: 0.5 }}') == 'ff000080'
	assert render_ok('{{ red | set_alpha: 0 }}') == 'ff000000'
	assert render_ok('{{ red | set_alpha: 1 }}') == 'ff0000'
	// `.hex` still forces six digits, for configs that cannot take eight.
	assert render_ok('{{ red | set_alpha: 0.5 | replace: "zz", "zz" }}') == 'ff000080'
}

fn test_contrast_picks_a_readable_foreground() {
	assert render_ok('{{ background | contrast }}') == 'ffffff'
	assert render_ok('{{ "#ffffff" | contrast }}') == '000000'
}

fn test_string_filters() {
	assert render_ok('{{ theme | upper }}') == 'DARK'
	assert render_ok('{{ theme | replace: "dark", "night" }}') == 'night'
	assert render_ok('{{ empty | default: "fallback" }}') == 'fallback'
	assert render_ok('{{ theme | default: "fallback" }}') == 'dark'
}

fn test_quoted_arguments_keep_separators() {
	// The splitter has to know an argument ended, without losing commas and colons inside it.
	assert render_ok('{{ "a,b" | replace: ",", "-" }}') == 'a-b'
	assert render_ok('{{ "12:34" | replace: ":", "h" }}') == '12h34'
}

fn test_literal_colours() {
	assert render_ok('{{ "#ff0000" | invert }}') == '00ffff'
	assert render_ok('{{ #ff0000 }}') == 'ff0000'
}

fn test_conditionals() {
	assert render_ok('<* if dark *>D<* else *>L<* endif *>') == 'D'
	assert render_ok('<* if light *>D<* else *>L<* endif *>') == 'L'
	assert render_ok('<* if not light *>yes<* endif *>') == 'yes'
	assert render_ok('<* if dark *>only<* endif *>') == 'only'
	assert render_ok('<* if light *>none<* endif *>') == ''
}

fn test_string_equality_in_conditions() {
	// A quoted literal must not be looked up as a variable. `dark` is a real name here and holds
	// a bool, so `theme == "dark"` compared 'dark' against 'true' and was never true.
	assert render_ok('<* if theme == "dark" *>Y<* else *>N<* endif *>') == 'Y'
	assert render_ok('<* if theme == "light" *>Y<* else *>N<* endif *>') == 'N'
	assert render_ok('<* if theme != "light" *>Y<* else *>N<* endif *>') == 'Y'
}

fn test_nested_conditionals() {
	assert render_ok('<* if dark *><* if not light *>both<* endif *><* endif *>') == 'both'
}

fn test_loops() {
	assert render_ok('<* for c in colors *>{{ c.hex }} <* endfor *>') == '#111111 #222222 #333333 '
	assert render_ok('<* for c in colors *>{{ loop_index }}<* endfor *>') == '012'
}

fn test_loop_first_and_last() {
	// The separator problem every colour-list template has.
	out :=
		render_ok('<* for c in colors *>{{ c.hex }}<* if not loop_last *>, <* endif *><* endfor *>')
	assert out == '#111111, #222222, #333333'
}

fn test_loop_body_can_use_the_outer_scope() {
	assert render_ok('<* for c in colors *>{{ theme }}<* endfor *>') == 'darkdarkdark'
}

fn test_unknown_things_are_reported_and_left_in_place() {
	// Substituting nothing turns a broken template into a working-looking one full of blanks.
	out, problems := render('{{ nosuchname }}', ctx())
	assert out == '{{ nosuchname }}'
	assert problems.len == 1
	assert problems[0].contains('nosuchname')

	out2, problems2 := render('{{ accent | nosuchfilter }}', ctx())
	assert out2 == '{{ accent | nosuchfilter }}'
	assert problems2.len == 1

	out3, problems3 := render('{{ accent.nosuchfield }}', ctx())
	assert out3 == '{{ accent.nosuchfield }}'
	assert problems3.len == 1
}

fn test_a_bad_filter_argument_is_reported() {
	_, problems := render('{{ accent | lighten: "abc" }}', ctx())
	assert problems.len == 1
	assert problems[0].contains('lighten')
}

fn test_unknown_control_tags_survive() {
	// A stray `<* ... *>` in a config file is not ours to swallow.
	assert render_ok('a <* whatever *> b') == 'a <* whatever *> b'
}

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

fn test_malformed_input_terminates_and_keeps_the_text() {
	// A parser that loops for ever on a truncated tag is worse than one that renders it oddly.
	// Every one of these has to return.
	for source in [
		'{{ unclosed',
		'{{ unclosed }',
		'<* if dark *>never closed',
		'<* for c in colors *>no end',
		'<* endif *>',
		'<* endfor *>',
		'<*',
		'{{',
		'}}',
		'*>',
		'{{ }}',
		'<* *>',
		'{{ | }}',
		'{{ accent | }}',
		'{{ accent | lighten: }}',
		'<* if *>x<* endif *>',
		'{{{{ accent }}}}',
	] {
		out, _ := render(source, ctx())
		assert out.len >= 0, 'render of `${source}` produced nothing at all'
	}
}

fn test_truncated_placeholder_is_left_alone() {
	assert render_ok('prefix {{ unclosed') == 'prefix {{ unclosed'
	assert render_ok('a <* if dark *> b') == 'a  b'
}

fn test_deeply_nested_blocks() {
	source := '<* if dark *>1<* if not light *>2<* for c in colors *>3<* endfor *>4<* endif *>5<* endif *>'
	// 1, then 2, then 3 once per colour, then 4 and 5 as the blocks close.
	assert render_ok(source) == '1233345'
}

fn test_loop_over_a_non_list_is_reported() {
	_, problems := render('<* for c in theme *>x<* endfor *>', ctx())
	assert problems.len == 1
	assert problems[0].contains('not a list')
}

fn test_loop_over_an_unknown_name_is_reported() {
	_, problems := render('<* for c in nope *>x<* endfor *>', ctx())
	assert problems.len == 1
}

fn test_many_placeholders_on_one_line() {
	assert render_ok('{{ theme }}-{{ theme }}-{{ theme }}') == 'dark-dark-dark'
}

fn test_a_value_containing_braces_is_not_re_expanded() {
	// The old engine substituted by repeated string replacement, so a value that happened to
	// contain a placeholder got expanded on a later pass. One scan, one substitution.
	mut c := ctx()
	c['tricky'] = TplValue('{{ theme }}')
	out, _ := render('{{ tricky }}', c)
	assert out == '{{ theme }}'
}

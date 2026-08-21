module template

import color
import os

fn ctx() map[string]TplValue {
	return {
		'background': TplValue(color.color_from_hex('#101820'))
		'accent':     TplValue(color.color_from_hex('#3f51b5'))
		'red':        TplValue(color.color_from_hex('#ff0000'))
		'theme':      TplValue('dark')
		'dark':       TplValue(true)
		'light':      TplValue(false)
		'empty':      TplValue('')
		'colors':     TplValue([color.color_from_hex('#111111'),
			color.color_from_hex('#222222'), color.color_from_hex('#333333')])
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
	lighter := color.color_from_hex(render_ok('{{ accent | lighten: 0.2 }}'))
	darker := color.color_from_hex(render_ok('{{ accent | darken: 0.2 }}'))
	base := color.color_from_hex('#3f51b5')
	assert lighter.to_lab().l > base.to_lab().l
	assert darker.to_lab().l < base.to_lab().l

	assert render_ok('{{ red | invert }}') == '00ffff'
	assert render_ok('{{ red | grayscale }}') == render_ok('{{ red | grayscale }}')
	grey := color.color_from_hex(render_ok('{{ red | grayscale }}'))
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

fn test_case_filters_from_prose() {
	assert render_ok('{{ "hello world" | snake_case }}') == 'hello_world'
	assert render_ok('{{ "hello world" | kebab_case }}') == 'hello-world'
	assert render_ok('{{ "hello world" | camel_case }}') == 'helloWorld'
	assert render_ok('{{ "hello world" | pascal_case }}') == 'HelloWorld'
}

fn test_case_filters_recognise_the_input_convention() {
	// The input may already be in any of these; each has to be taken apart before being put
	// back together, or `snake_case` on camelCase input would just lowercase it.
	for source in ['helloWorld', 'HelloWorld', 'hello_world', 'hello-world', 'hello world',
		'HELLO_WORLD'] {
		assert render_ok('{{ "${source}" | snake_case }}') == 'hello_world', 'from ${source}'
		assert render_ok('{{ "${source}" | camel_case }}') == 'helloWorld', 'from ${source}'
		assert render_ok('{{ "${source}" | pascal_case }}') == 'HelloWorld', 'from ${source}'
		assert render_ok('{{ "${source}" | kebab_case }}') == 'hello-world', 'from ${source}'
	}
}

fn test_case_filters_handle_acronyms() {
	// A run of capitals is one word until the last capital, which starts the next: HTTPServer is
	// http + server, not h + t + t + p + server.
	assert render_ok('{{ "HTTPServer" | snake_case }}') == 'http_server'
	assert render_ok('{{ "XMLHttpRequest" | snake_case }}') == 'xml_http_request'
	assert render_ok('{{ "HTTP" | snake_case }}') == 'http'
	assert render_ok('{{ "XMLHttpRequest" | pascal_case }}') == 'XmlHttpRequest'
}

fn test_case_filters_keep_digits_with_their_word() {
	// `color0` is one word. Splitting on the digit gives `color_0`, which is not what any config
	// key looks like.
	assert render_ok('{{ "color0" | snake_case }}') == 'color0'
	assert render_ok('{{ "color15" | kebab_case }}') == 'color15'
	assert render_ok('{{ "baseColor16" | snake_case }}') == 'base_color16'
}

fn test_case_filters_on_awkward_input() {
	assert render_ok('{{ "" | snake_case }}') == ''
	assert render_ok('{{ "   " | snake_case }}') == ''
	assert render_ok('{{ "---" | kebab_case }}') == ''
	assert render_ok('{{ "  padded  " | snake_case }}') == 'padded'
	assert render_ok('{{ "a" | pascal_case }}') == 'A'
	assert render_ok('{{ "multiple___separators" | kebab_case }}') == 'multiple-separators'
	assert render_ok('{{ "dots.and/slashes" | snake_case }}') == 'dots_and_slashes'
}

fn test_case_filters_chain_with_the_rest() {
	assert render_ok('{{ theme | pascal_case }}') == 'Dark'
	assert render_ok('{{ "some value" | snake_case | upper }}') == 'SOME_VALUE'
	assert render_ok('{{ "TheTheme" | kebab_case | replace: "-", "+" }}') == 'the+theme'
}

fn test_matugen_case_aliases() {
	assert render_ok('{{ theme | upper_case }}') == 'DARK'
	assert render_ok('{{ "LOUD" | lower_case }}') == 'loud'
	assert render_ok('{{ theme | capitalize }}') == 'Dark'
}

fn include_dir(name string) string {
	dir := os.join_path(os.temp_dir(), 'lule_inc_${name}_${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

fn put(dir string, name string, body string) {
	full := os.join_path(dir, name)
	os.mkdir_all(os.dir(full)) or {}
	os.write_file(full, body) or { panic(err) }
}

fn test_include_pulls_in_another_file() {
	dir := include_dir('basic')
	defer {
		os.rmdir_all(dir) or {}
	}
	put(dir, 'partial.conf', 'bg={{ background.hex }}')
	out, problems := render_in('a <* include "partial.conf" *> b', ctx(), dir)
	assert problems.len == 0, '${problems}'
	assert out == 'a bg=#101820 b'
}

fn test_include_resolves_beside_the_including_file() {
	// Not relative to the working directory: a template saying `include "partial"` means the one
	// next to it, wherever lule was run from.
	dir := include_dir('relative')
	defer {
		os.rmdir_all(dir) or {}
	}
	put(dir, 'nested/inner.conf', 'inner')
	put(dir, 'nested/outer.conf', 'outer(<* include "inner.conf" *>)')
	out, problems := render_in('<* include "nested/outer.conf" *>', ctx(), dir)
	assert problems.len == 0, '${problems}'
	assert out == 'outer(inner)'
}

fn test_included_content_takes_part_in_the_surrounding_block() {
	// Spliced into the tree rather than rendered on its own, so an include inside a loop sees
	// the loop variable.
	dir := include_dir('inloop')
	defer {
		os.rmdir_all(dir) or {}
	}
	put(dir, 'row.conf', '[{{ c.hex }}]')
	out, problems :=
		render_in('<* for c in colors *><* include "row.conf" *><* endfor *>', ctx(), dir)
	assert problems.len == 0, '${problems}'
	assert out == '[#111111][#222222][#333333]'
}

fn test_include_inside_a_conditional() {
	dir := include_dir('incond')
	defer {
		os.rmdir_all(dir) or {}
	}
	put(dir, 'dark.conf', 'DARK')
	put(dir, 'light.conf', 'LIGHT')
	out, _ := render_in('<* if dark *><* include "dark.conf" *><* else *><* include "light.conf" *><* endif *>',
		ctx(), dir)
	assert out == 'DARK'
}

fn test_a_file_may_be_included_twice() {
	// The cycle check tracks the current chain, not every file ever seen, so a diamond is fine.
	dir := include_dir('diamond')
	defer {
		os.rmdir_all(dir) or {}
	}
	put(dir, 'shared.conf', 'S')
	put(dir, 'a.conf', 'a<* include "shared.conf" *>')
	put(dir, 'b.conf', 'b<* include "shared.conf" *>')
	out, problems := render_in('<* include "a.conf" *><* include "b.conf" *>', ctx(), dir)
	assert problems.len == 0, '${problems}'
	assert out == 'aSbS'
}

fn test_a_self_include_is_refused() {
	dir := include_dir('selfcycle')
	defer {
		os.rmdir_all(dir) or {}
	}
	put(dir, 'loop.conf', 'x<* include "loop.conf" *>')
	out, problems := render_in('<* include "loop.conf" *>', ctx(), dir)
	assert problems.len == 1, '${problems}'
	assert problems[0].contains('circular')
	// The one real level still rendered; only the recursion was cut.
	assert out == 'x'
}

fn test_a_longer_cycle_is_refused() {
	dir := include_dir('abccycle')
	defer {
		os.rmdir_all(dir) or {}
	}
	put(dir, 'a.conf', 'A<* include "b.conf" *>')
	put(dir, 'b.conf', 'B<* include "c.conf" *>')
	put(dir, 'c.conf', 'C<* include "a.conf" *>')
	out, problems := render_in('<* include "a.conf" *>', ctx(), dir)
	assert problems.len == 1, '${problems}'
	assert problems[0].contains('circular')
	assert out == 'ABC'
}

fn test_a_cycle_through_a_relative_path_is_still_caught() {
	// `a/../a.conf` and `a.conf` are the same file; without canonicalising, the chain check
	// compares two different strings and recurses for ever.
	dir := include_dir('pathcycle')
	defer {
		os.rmdir_all(dir) or {}
	}
	put(dir, 'sub/x.conf', 'X<* include "../sub/x.conf" *>')
	out, problems := render_in('<* include "sub/x.conf" *>', ctx(), dir)
	assert problems.len == 1, '${problems}'
	assert problems[0].contains('circular')
	assert out == 'X'
}

fn test_a_missing_include_is_reported() {
	dir := include_dir('missing')
	defer {
		os.rmdir_all(dir) or {}
	}
	out, problems := render_in('before<* include "nope.conf" *>after', ctx(), dir)
	assert problems.len == 1
	assert problems[0].contains('nope.conf')
	// The rest of the template still renders.
	assert out == 'beforeafter'
}

fn test_an_include_with_no_file_named_is_reported() {
	_, problems := render('<* include *>', ctx())
	assert problems.len == 1
}

fn test_include_accepts_either_quote_style() {
	dir := include_dir('quotes')
	defer {
		os.rmdir_all(dir) or {}
	}
	put(dir, 'p.conf', 'P')
	single, _ := render_in("<* include 'p.conf' *>", ctx(), dir)
	double, _ := render_in('<* include "p.conf" *>', ctx(), dir)
	bare, _ := render_in('<* include p.conf *>', ctx(), dir)
	assert single == 'P' && double == 'P' && bare == 'P'
}

fn test_arithmetic_basics() {
	assert render_ok('{{ 2 + 3 }}') == '5'
	assert render_ok('{{ 10 - 4 }}') == '6'
	assert render_ok('{{ 6 * 7 }}') == '42'
	assert render_ok('{{ 9 / 3 }}') == '3'
	assert render_ok('{{ 7 % 3 }}') == '1'
}

fn test_arithmetic_precedence() {
	// The whole reason this is a parser and not another pipeline stage.
	assert render_ok('{{ 2 + 3 * 4 }}') == '14'
	assert render_ok('{{ (2 + 3) * 4 }}') == '20'
	assert render_ok('{{ 2 * 3 + 4 * 5 }}') == '26'
	assert render_ok('{{ 100 / 10 / 2 }}') == '5'
	assert render_ok('{{ 2 + 2 * 2 + 2 }}') == '8'
}

fn test_arithmetic_negatives_and_nesting() {
	assert render_ok('{{ 0 - 5 }}') == '-5'
	assert render_ok('{{ 3 * (0 - 2) }}') == '-6'
	assert render_ok('{{ ((1 + 2) * (3 + 4)) }}') == '21'
}

fn test_numbers_print_without_trailing_zeros() {
	assert render_ok('{{ 5 / 2 }}') == '2.5'
	assert render_ok('{{ 1 / 4 }}') == '0.25'
	assert render_ok('{{ 4 / 2 }}') == '2'
}

fn test_a_bare_number_stays_a_number() {
	// `123456` is also six hex digits. Reading it as a colour would be a surprising way to lose
	// an arithmetic operand.
	assert render_ok('{{ 123456 }}') == '123456'
	assert render_ok('{{ 42 }}') == '42'
	// But a hex colour is still a colour.
	assert render_ok('{{ #ff0000 }}') == 'ff0000'
	assert render_ok('{{ ff0000 }}') == 'ff0000'
}

fn test_arithmetic_reads_names() {
	mut c := ctx()
	c['count'] = TplValue(f64(4))
	out, problems := render('{{ count * 2 + 1 }}', c)
	assert problems.len == 0, '${problems}'
	assert out == '9'
}

fn test_division_by_zero_is_reported() {
	_, problems := render('{{ 1 / 0 }}', ctx())
	assert problems.len == 1
	assert problems[0].contains('zero')

	_, mod_problems := render('{{ 1 % 0 }}', ctx())
	assert mod_problems.len == 1
}

fn test_malformed_arithmetic_is_reported() {
	for source in ['{{ 1 + }}', '{{ (1 + 2 }}', '{{ 1 + 2) }}', '{{ * 3 }}', '{{ 1 + + }}'] {
		_, problems := render(source, ctx())
		assert problems.len >= 1, 'accepted `${source}`'
	}
}

fn test_arithmetic_does_not_capture_ordinary_names() {
	// A name, a hex colour and a quoted string must not be mistaken for arithmetic.
	assert render_ok('{{ theme }}') == 'dark'
	assert render_ok('{{ accent.hex }}') == '#3f51b5'
	assert render_ok('{{ "a-b" }}') == 'a-b'
}

fn test_range_loops() {
	// `a..b` stops before b, as in Rust.
	assert render_ok('<* for i in 0..5 *>{{ i }}<* endfor *>') == '01234'
	assert render_ok('<* for i in 1..4 *>{{ i }},<* endfor *>') == '1,2,3,'
}

fn test_inclusive_ranges() {
	assert render_ok('<* for i in 0..=5 *>{{ i }}<* endfor *>') == '012345'
	assert render_ok('<* for i in 3..=3 *>{{ i }}<* endfor *>') == '3'
}

fn test_negative_ranges() {
	assert render_ok('<* for i in -3..3 *>{{ i }} <* endfor *>') == '-3 -2 -1 0 1 2 '
}

fn test_a_backwards_range_is_empty() {
	// Rust's semantics, which is where the `..` spelling comes from. Counting down instead
	// would be a silent guess about what was meant.
	assert render_ok('<* for i in 10..0 *>{{ i }}<* endfor *>') == ''
	assert render_ok('<* for i in 5..5 *>{{ i }}<* endfor *>') == ''
}

fn test_range_ends_may_be_expressions() {
	mut c := ctx()
	c['count'] = TplValue(f64(3))
	out, problems := render('<* for i in 0..count *>{{ i }}<* endfor *>', c)
	assert problems.len == 0, '${problems}'
	assert out == '012'

	out2, problems2 := render('<* for i in 0..count * 2 *>{{ i }}<* endfor *>', c)
	assert problems2.len == 0, '${problems2}'
	assert out2 == '012345'
}

fn test_range_loop_variables() {
	assert render_ok('<* for i in 0..3 *>{{ loop_index }}<* endfor *>') == '012'
	out := render_ok('<* for i in 0..3 *>{{ i }}<* if not loop_last *>-<* endif *><* endfor *>')
	assert out == '0-1-2'
}

fn test_arithmetic_on_the_loop_variable() {
	assert render_ok('<* for i in 0..4 *>{{ i * 10 }} <* endfor *>') == '0 10 20 30 '
}

fn test_a_huge_range_is_refused_rather_than_hanging() {
	// A template asking for a billion iterations has made a mistake, and saying so beats
	// appearing to hang.
	out, problems := render('<* for i in 0..999999999 *>x<* endfor *>', ctx())
	assert problems.len == 1
	assert problems[0].contains('more than')
	assert out == ''
}

fn test_a_bad_range_end_is_reported() {
	_, problems := render('<* for i in 0..nope *>x<* endfor *>', ctx())
	assert problems.len == 1

	_, problems2 := render('<* for i in 0..theme *>x<* endfor *>', ctx())
	assert problems2.len == 1
}

fn test_ranges_and_lists_still_coexist() {
	assert render_ok('<* for c in colors *>{{ c.hex }}<* endfor *>') == '#111111#222222#333333'
	assert render_ok('<* for i in 0..2 *>{{ i }}<* endfor *>') == '01'
}

fn test_ansi_is_absent_for_a_short_palette() {
	// Nothing to expose, and a loop over a missing name reports rather than inventing one.
	_, problems := render('<* for x in ansi *>{{ x }}<* endfor *>', {
		'theme': TplValue('dark')
	})
	assert problems.len == 1
}

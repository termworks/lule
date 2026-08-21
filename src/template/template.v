module template

import color
import math
import os
import strings

// What a template expression can evaluate to. Colours stay colours all the way through the
// pipeline rather than becoming strings at the first opportunity — that is what lets
// `{{ color1 | lighten: 0.2 | set_alpha: 0.5 }}` mean anything, and it is the difference between
// a templating engine that understands colour and one doing string substitution.
pub type TplValue = color.Color | []color.Color | bool | f64 | string

// A bare `{{ color1 }}` prints **without** the leading hash, because that is what it has always
// printed and every template in the wild supplies its own: `templates/colors.sh` writes
// '#{{ background }}', which would become '##0b0e0d' the moment this started emitting one.
// `{{ color1.hex }}` is the way to ask for it.
//
// Alpha is appended once the colour carries any, so `{{ accent | set_alpha: 0.5 }}` does not
// render identically to `{{ accent }}` and look like the filter did nothing.
pub fn (v TplValue) display() string {
	return match v {
		string {
			v
		}
		color.Color {
			if v.alpha < 0.999 {
				color_field(v, 'hex_alpha_stripped') or { v.to_hex(false) }
			} else {
				v.to_hex(false)
			}
		}
		bool {
			if v {
				'true'
			} else {
				'false'
			}
		}
		f64 {
			show_number(v)
		}
		[]color.Color {
			v.map(it.to_hex(false)).join(' ')
		}
	}
}

fn (v TplValue) truthy() bool {
	return match v {
		bool { v }
		f64 { v != 0.0 }
		string { v != '' && v != 'false' && v != '0' }
		color.Color { true }
		[]color.Color { v.len > 0 }
	}
}

fn fmt2(x f64) string {
	return '${x:.2f}'
}

// The colour formats a config file might want. Named after matugen's so a template written for
// one is readable against the other.
fn color_field(c color.Color, field string) !string {
	r, g, b := c.rgb_u8()
	hsl := c.to_hsl()
	lab := c.to_lab()
	alpha := color.clamp01(c.alpha)
	return match field {
		'hex' { c.to_hex(true) }
		'hex_stripped' { c.to_hex(false) }
		'hex_alpha' { '${c.to_hex(true)}${u8(math.round(alpha * 255.0)):02x}' }
		'hex_alpha_stripped' { '${c.to_hex(false)}${u8(math.round(alpha * 255.0)):02x}' }
		'rgb' { 'rgb(${r}, ${g}, ${b})' }
		'rgba' { 'rgba(${r}, ${g}, ${b}, ${fmt2(alpha)})' }
		'hsl' { 'hsl(${hsl.h:.0f}, ${hsl.s * 100.0:.0f}%, ${hsl.l * 100.0:.0f}%)' }
		'hsla' { 'hsla(${hsl.h:.0f}, ${hsl.s * 100.0:.0f}%, ${hsl.l * 100.0:.0f}%, ${fmt2(alpha)})' }
		'red' { '${r}' }
		'green' { '${g}' }
		'blue' { '${b}' }
		'alpha' { fmt2(alpha) }
		'hue' { '${hsl.h:.0f}' }
		'saturation' { fmt2(hsl.s) }
		'lightness' { fmt2(hsl.l) }
		'luminance' { fmt2(lab.l) }
		else { error('unknown colour field `${field}`') }
	}
}

fn as_color(v TplValue, filter string) !color.Color {
	return match v {
		color.Color {
			v
		}
		string {
			color.parse_hex(v) or {
				return error('`${filter}` needs a colour, got the string `${v}`')
			}
		}
		else {
			error('`${filter}` needs a colour')
		}
	}
}

fn as_number(args []string, index int, filter string) !f64 {
	if index >= args.len {
		return error('`${filter}` needs an argument')
	}
	text := args[index]
	value := text.f64()
	if value == 0.0 && text.trim_space() !in ['0', '0.0', '-0', '.0', '0.'] {
		return error('`${filter}` wants a number, got `${text}`')
	}
	return value
}

fn apply_filter(input TplValue, name string, args []string) !TplValue {
	match name {
		// Colour transforms. Each returns a colour so they can be chained.
		'lighten' {
			c := as_color(input, name)!
			return TplValue(c.lighten(as_number(args, 0, name)!))
		}
		'darken' {
			c := as_color(input, name)!
			return TplValue(c.darken(as_number(args, 0, name)!))
		}
		'saturate' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color.color_from_hsl(hsl.h, color.clamp01(hsl.s +
				as_number(args, 0, name)!), hsl.l))
		}
		'desaturate' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color.color_from_hsl(hsl.h, color.clamp01(hsl.s - as_number(args, 0,
				name)!), hsl.l))
		}
		'set_hue' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color.color_from_hsl(as_number(args, 0, name)!, hsl.s, hsl.l))
		}
		'set_saturation' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color.color_from_hsl(hsl.h, color.clamp01(as_number(args, 0, name)!),
				hsl.l))
		}
		'set_lightness' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color.color_from_hsl(hsl.h, hsl.s, color.clamp01(as_number(args, 0,
				name)!)))
		}
		'set_alpha' {
			mut c := as_color(input, name)!
			c.alpha = color.clamp01(as_number(args, 0, name)!)
			return TplValue(c)
		}
		'rotate' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color.color_from_hsl(hsl.h + as_number(args, 0, name)!, hsl.s, hsl.l))
		}
		'grayscale' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color.color_from_hsl(hsl.h, 0.0, hsl.l))
		}
		'complement' {
			return TplValue(as_color(input, name)!.complementary())
		}
		'invert' {
			c := as_color(input, name)!
			r, g, b := c.rgb_u8()
			return TplValue(color.color_from_rgb(255 - r, 255 - g, 255 - b))
		}
		'mix' {
			c := as_color(input, name)!
			if args.len < 1 {
				return error('`mix` needs a colour to mix with')
			}
			other := color.parse_hex(args[0]) or {
				return error('`mix`: `${args[0]}` is not a colour')
			}
			amount := if args.len > 1 { as_number(args, 1, name)! } else { 0.5 }
			return TplValue(c.mix_lab(other, color.clamp01(amount)))
		}
		// Picks whichever of black or white reads against this colour. The reason a template can
		// set a foreground without the author knowing what the background turned out to be.
		'contrast' {
			c := as_color(input, name)!
			readable := if c.to_lab().l < 55.0 {
				color.color_from_rgb(255, 255, 255)
			} else {
				color.color_from_rgb(0, 0, 0)
			}
			return TplValue(readable)
		}
		// String transforms, applied to whatever the value displays as. matugen spells the first
		// two `upper_case` and `lower_case`; both names work, so a template written for either
		// tool renders here.
		'upper', 'upper_case' {
			return TplValue(input.display().to_upper())
		}
		'lower', 'lower_case' {
			return TplValue(input.display().to_lower())
		}
		'snake_case' {
			return TplValue(to_case(input.display(), 'snake'))
		}
		'kebab_case' {
			return TplValue(to_case(input.display(), 'kebab'))
		}
		'camel_case' {
			return TplValue(to_case(input.display(), 'camel'))
		}
		'pascal_case' {
			return TplValue(to_case(input.display(), 'pascal'))
		}
		'capitalize' {
			return TplValue(capitalise(input.display()))
		}
		'trim' {
			return TplValue(input.display().trim_space())
		}
		'replace' {
			if args.len < 2 {
				return error('`replace` needs a search and a replacement')
			}
			return TplValue(input.display().replace(args[0], args[1]))
		}
		'default' {
			if args.len < 1 {
				return error('`default` needs a fallback')
			}
			return if input.truthy() { input } else { TplValue(args[0]) }
		}
		else {
			return error('unknown filter `${name}`')
		}
	}
}

// Breaks a name into its words, whatever convention it arrived in, so the case filters can be
// applied to input that is already snake_case, kebab-case, camelCase or prose.
//
// Digits stay attached to the word before them: `color0` is one word, not `color` and `0`, which
// is the difference between `color0` and `color_0` coming out of snake_case.
fn split_words(input string) []string {
	mut words := []string{}
	mut current := strings.new_builder(16)
	bytes := input.bytes()

	for i, ch in bytes {
		if !ch.is_alnum() {
			// Any run of punctuation or space is a boundary.
			if current.len > 0 {
				words << current.str().to_lower()
				current = strings.new_builder(16)
			}
			continue
		}
		if ch.is_capital() && current.len > 0 {
			previous := bytes[i - 1]
			next_is_lower := i + 1 < bytes.len && bytes[i + 1].is_letter()
				&& !bytes[i + 1].is_capital()
			// `fooBar` breaks before the B. `HTTPServer` breaks before the S, not inside HTTP —
			// which is why the next character matters and not just this one.
			if !previous.is_capital() || next_is_lower {
				words << current.str().to_lower()
				current = strings.new_builder(16)
			}
		}
		current.write_u8(ch)
	}
	if current.len > 0 {
		words << current.str().to_lower()
	}
	return words
}

fn capitalise(word string) string {
	if word == '' {
		return word
	}
	return word[..1].to_upper() + word[1..]
}

fn to_case(input string, style string) string {
	words := split_words(input)
	if words.len == 0 {
		return ''
	}
	return match style {
		'snake' {
			words.join('_')
		}
		'kebab' {
			words.join('-')
		}
		'pascal' {
			words.map(capitalise(it)).join('')
		}
		else {
			// camel: the first word stays lowercase, the rest are capitalised.
			words[0] + words[1..].map(capitalise(it)).join('')
		}
	}
}

// One `a | b: x, "y" | c` pipeline, split into its stages. Quoted arguments keep commas and
// colons, so `replace: ",", ";"` and a `hsl(...)` literal both survive.
struct FilterCall {
	name string
	args []string
}

fn split_top_level(input string, sep u8) []string {
	mut parts := []string{}
	mut current := strings.new_builder(32)
	mut quote := u8(0)
	for ch in input {
		if quote != 0 {
			current.write_u8(ch)
			if ch == quote {
				quote = 0
			}
			continue
		}
		if ch == `'` || ch == `"` {
			// The quote characters are kept, not eaten. Stripping them here meant a quoted
			// literal stopped looking quoted by the time anything checked: `theme == "dark"`
			// compared against the *variable* `dark`, which is a bool, so it was never equal.
			quote = ch
			current.write_u8(ch)
			continue
		}
		if ch == sep {
			parts << current.str().trim_space()
			current = strings.new_builder(32)
			continue
		}
		current.write_u8(ch)
	}
	parts << current.str().trim_space()
	return parts
}

fn parse_pipeline(expr string) (string, []FilterCall) {
	stages := split_top_level(expr, `|`)
	mut filters := []FilterCall{}
	for stage in stages[1..] {
		if stage == '' {
			continue
		}
		idx := stage.index(':') or {
			filters << FilterCall{stage.trim_space(), []}
			continue
		}
		filters << FilterCall{
			name: stage[..idx].trim_space()
			args: split_top_level(stage[idx + 1..], `,`).map(unquote(it))
		}
	}
	return stages[0].trim_space(), filters
}

// Resolves `name`, `name.field`, a quoted literal or a bare hex colour, then runs the filters.
fn eval_expr(expr string, ctx map[string]TplValue) !string {
	base, filters := parse_pipeline(expr)
	if base == '' {
		return error('empty expression')
	}

	mut value := TplValue('')
	trimmed := base.trim_space()
	if (trimmed.starts_with('"') && trimmed.ends_with('"') && trimmed.len > 1)
		|| (trimmed.starts_with("'") && trimmed.ends_with("'") && trimmed.len > 1) {
		value = TplValue(trimmed[1..trimmed.len - 1])
	} else if looks_arithmetic(trimmed) {
		// Checked before name lookup so `loop_index * 2` is arithmetic rather than a search for a
		// name with a star in it.
		value = TplValue(eval_arith(trimmed, ctx)!)
	} else if n := text_as_number(trimmed) {
		// A bare number, before the hex check: `123456` is six hex digits, and reading it as a
		// colour rather than a number would be a surprising way to lose an arithmetic operand.
		value = TplValue(n)
	} else {
		parts := trimmed.split('.')
		name := parts[0]
		found := ctx[name] or {
			// A bare hex literal is a colour, so `{{ #ff0000 | lighten: 0.1 }}` works without
			// having to name it first.
			if c := color.parse_hex(name) {
				TplValue(c)
			} else {
				return error('unknown name `${name}`')
			}
		}
		value = found
		if parts.len > 1 {
			field := parts[1..].join('.')
			match found {
				color.Color { value = TplValue(color_field(found, field)!) }
				else { return error('`${name}` has no field `${field}`') }
			}
		}
	}

	for f in filters {
		value = apply_filter(value, f.name, f.args)!
	}
	return value.display()
}

// The document, as a tree. Control blocks nest, so a flat scan-and-replace cannot express them.
enum NodeKind {
	text
	output
	cond
	loop
}

struct Node {
mut:
	kind NodeKind
	text string // literal text, or the expression for `output` and `cond`
	name string // loop variable
	body []Node
	alt  []Node // the `else` branch
}

struct Block {
	tag    string // 'if' | 'for' | 'else' | 'endif' | 'endfor'
	rest   string
	start  int
	finish int
}

fn next_block(src string, from int) ?Block {
	open := src.index_after('<*', from) or { return none }
	close := src.index_after('*>', open) or { return none }
	inner := src[open + 2..close].trim_space()
	idx := inner.index(' ') or { return Block{inner, '', open, close + 2} }
	return Block{inner[..idx], inner[idx + 1..].trim_space(), open, close + 2}
}

// Parses until the matching closing tag, returning the nodes and where it stopped.
// Carried through the parse so `<* include *>` can resolve a path relative to the file it appears
// in, and so a cycle is caught rather than recursed into for ever.
struct ParseState {
mut:
	dir      string   // the directory of the file currently being parsed
	chain    []string // the include chain above this point, for cycle detection
	problems []string
}

// 16 is far past any sane template and still terminates promptly if the cycle check is ever
// defeated — by a symlink pair that resolves to two different real paths, say.
const max_include_depth = 16

// Relative to the including file, not the working directory. A template that says
// `<* include "partial.conf" *>` means the one next to it, wherever lule happens to be run from.
fn resolve_include(dir string, path string) string {
	joined := if os.is_abs_path(path) { path } else { os.join_path(dir, path) }
	// A canonical form is what makes the cycle check work: `a/../a.tpl` and `a.tpl` are the same
	// file and have to compare equal. real_path returns its input unchanged when the path does
	// not exist, which is fine - that case is reported as unreadable a moment later.
	return os.real_path(joined)
}

fn parse_nodes(src string, from int, stop []string, mut st ParseState) ([]Node, string, int) {
	mut nodes := []Node{}
	mut cursor := from

	for {
		block := next_block(src, cursor) or {
			nodes << Node{
				kind: .text
				text: src[cursor..]
			}
			return nodes, '', src.len
		}
		if block.start > cursor {
			nodes << Node{
				kind: .text
				text: src[cursor..block.start]
			}
		}

		if block.tag in stop {
			return nodes, block.tag, block.finish
		}

		match block.tag {
			'if' {
				body, ended, after := parse_nodes(src, block.finish, ['else', 'endif'], mut st)
				mut node := Node{
					kind: .cond
					text: block.rest
					body: body
				}
				mut cont := after
				if ended == 'else' {
					alt, _, after_else := parse_nodes(src, after, ['endif'], mut st)
					node.alt = alt
					cont = after_else
				}
				nodes << node
				cursor = cont
			}
			'for' {
				// `for name in iterable`, where the iterable is everything after `in` — not just
				// the next word. A range end may be an expression, and `0..count * 2` lost its
				// `* 2` when only one word was taken.
				words := block.rest.split(' ').filter(it != '')
				body, _, after := parse_nodes(src, block.finish, ['endfor'], mut st)
				nodes << Node{
					kind: .loop
					name: if words.len > 0 { words[0] } else { 'item' }
					text: if words.len > 2 { words[2..].join(' ') } else { '' }
					body: body
				}
				cursor = after
			}
			'include' {
				// Spliced into the tree at parse time rather than rendered separately, so the
				// included content takes part in whatever `if` or `for` surrounds it.
				path := unquote(block.rest)
				resolved := resolve_include(st.dir, path)
				if path == '' {
					st.problems << 'include: no file named'
				} else if st.chain.len >= max_include_depth {
					st.problems << 'include ${path}: nested more than ${max_include_depth} deep'
				} else if resolved in st.chain {
					// The chain, not every file ever seen: a file included twice down two
					// different branches is fine, a file that includes itself is not.
					st.problems << 'include ${path}: circular, already including it'
				} else if content := os.read_file(resolved) {
					outer_dir := st.dir
					st.chain << resolved
					st.dir = os.dir(resolved)
					inner, _, _ := parse_nodes(content, 0, [], mut st)
					st.dir = outer_dir
					st.chain.delete_last()
					nodes << inner
				} else {
					st.problems << 'include ${path}: cannot read ${resolved}'
				}
				cursor = block.finish
			}
			else {
				// Not a control tag - leave it in the output rather than swallowing it, so a
				// stray `<* ... *>` in a config file survives instead of vanishing silently.
				nodes << Node{
					kind: .text
					text: src[block.start..block.finish]
				}
				cursor = block.finish
			}
		}
	}
	return nodes, '', cursor
}

// Splits literal text on `{{ ... }}` into text and output nodes.
fn expand_outputs(text string) []Node {
	mut nodes := []Node{}
	mut cursor := 0
	for {
		open := text.index_after('{{', cursor) or { break }
		close := text.index_after('}}', open) or { break }
		if open > cursor {
			nodes << Node{
				kind: .text
				text: text[cursor..open]
			}
		}
		nodes << Node{
			kind: .output
			text: text[open + 2..close].trim_space()
		}
		cursor = close + 2
	}
	nodes << Node{
		kind: .text
		text: text[cursor..]
	}
	return nodes
}

fn render_nodes(nodes []Node, ctx map[string]TplValue, mut out strings.Builder, mut problems []string) {
	for node in nodes {
		match node.kind {
			.text {
				for piece in expand_outputs(node.text) {
					if piece.kind == .text {
						out.write_string(piece.text)
					} else {
						rendered := eval_expr(piece.text, ctx) or {
							problems << '{{ ${piece.text} }}: ${err}'
							// The original placeholder is left in place. Substituting nothing
							// makes a broken template look like a working one that produced an
							// empty value, and a config full of blanks is harder to diagnose.
							'{{ ${piece.text} }}'
						}
						out.write_string(rendered)
					}
				}
			}
			.output {
				out.write_string(eval_expr(node.text, ctx) or {
					problems << '{{ ${node.text} }}: ${err}'
					'{{ ${node.text} }}'
				})
			}
			.cond {
				taken := eval_condition(node.text, ctx, mut problems)
				render_nodes(if taken { node.body } else { node.alt }, ctx, mut out, mut problems)
			}
			.loop {
				if node.text.contains('..') {
					render_range(node, ctx, mut out, mut problems)
					continue
				}
				items := ctx[node.text] or {
					problems << 'for ... in ${node.text}: unknown name'
					continue
				}
				if items is []color.Color {
					for i, item in items {
						mut inner := ctx.clone()
						inner[node.name] = TplValue(item)
						inner['loop_index'] = TplValue(f64(i))
						inner['loop_first'] = TplValue(i == 0)
						inner['loop_last'] = TplValue(i == items.len - 1)
						render_nodes(node.body, inner, mut out, mut problems)
					}
				} else {
					problems << 'for ... in ${node.text}: not a list'
				}
			}
		}
	}
}

// `if name`, `if not name`, or `if a == b`.
fn eval_condition(expr string, ctx map[string]TplValue, mut problems []string) bool {
	mut text := expr.trim_space()
	mut negate := false
	if text.starts_with('not ') {
		negate = true
		text = text[4..].trim_space()
	}

	mut result := false
	if text.contains('==') || text.contains('!=') {
		equality := text.contains('==')
		sep := if equality { '==' } else { '!=' }
		idx := text.index(sep) or { 0 }
		left := eval_expr(text[..idx].trim_space(), ctx) or { '' }
		right_raw := text[idx + 2..].trim_space()
		right := eval_expr(right_raw, ctx) or { right_raw.trim('"\'') }
		result = if equality { left == right } else { left != right }
	} else {
		value := ctx[text] or {
			problems << 'if ${text}: unknown name'
			TplValue(false)
		}
		result = value.truthy()
	}
	return if negate { !result } else { result }
}

pub fn render_in(content string, ctx map[string]TplValue, dir string) (string, []string) {
	mut st := ParseState{
		dir: dir
	}
	nodes, _, _ := parse_nodes(content, 0, [], mut st)
	mut out := strings.new_builder(content.len + 256)
	// Parse problems come first: an include that could not be read explains the missing text
	// that any later problem is probably about.
	mut problems := st.problems.clone()
	render_nodes(nodes, ctx, mut out, mut problems)
	return out.str(), problems
}

pub fn render(content string, ctx map[string]TplValue) (string, []string) {
	return render_in(content, ctx, '.')
}

// Filter arguments are consumed as plain values, so this is where quoting is undone — after the
// splitting that needed the quotes to know where an argument ended.
fn unquote(text string) string {
	t := text.trim_space()
	if t.len > 1 && ((t.starts_with('"') && t.ends_with('"'))
		|| (t.starts_with("'") && t.ends_with("'"))) {
		return t[1..t.len - 1]
	}
	return t
}

// Numbers print as integers when they are whole, so `{{ 2 + 3 }}` is `5` rather than `5.00` and
// a loop counter reads like a counter. Fractions keep two places and lose trailing zeros.
fn show_number(x f64) string {
	if x == math.trunc(x) && math.abs(x) < 1.0e15 {
		return '${i64(x)}'
	}
	return '${x:.6f}'.trim_right('0').trim_right('.')
}

// Arithmetic, as a recursive-descent parser rather than another pipeline stage: `2 + 3 * 4` has
// to be 14, and precedence is not something a left-to-right pipeline can express.
//
//   expr   := term (('+' | '-') term)*
//   term   := factor (('*' | '/' | '%') factor)*
//   factor := '-' factor | '(' expr ')' | number | name
struct Arith {
	src string
	ctx map[string]TplValue
mut:
	pos int
}

fn (mut a Arith) skip_spaces() {
	for a.pos < a.src.len && a.src[a.pos] == ` ` {
		a.pos++
	}
}

fn (mut a Arith) peek() u8 {
	a.skip_spaces()
	return if a.pos < a.src.len { a.src[a.pos] } else { 0 }
}

fn (mut a Arith) expr() !f64 {
	mut left := a.term()!
	for {
		op := a.peek()
		if op != `+` && op != `-` {
			break
		}
		a.pos++
		right := a.term()!
		left = if op == `+` { left + right } else { left - right }
	}
	return left
}

fn (mut a Arith) term() !f64 {
	mut left := a.factor()!
	for {
		op := a.peek()
		if op != `*` && op != `/` && op != `%` {
			break
		}
		a.pos++
		right := a.factor()!
		match op {
			`*` {
				left *= right
			}
			`/` {
				if right == 0.0 {
					return error('division by zero')
				}
				left /= right
			}
			else {
				if right == 0.0 {
					return error('modulo by zero')
				}
				left = math.fmod(left, right)
			}
		}
	}
	return left
}

fn (mut a Arith) factor() !f64 {
	ch := a.peek()
	if ch == 0 {
		return error('expression ends early')
	}
	if ch == `-` {
		a.pos++
		return -a.factor()!
	}
	if ch == `+` {
		a.pos++
		return a.factor()!
	}
	if ch == `(` {
		a.pos++
		inner := a.expr()!
		if a.peek() != `)` {
			return error('missing `)`')
		}
		a.pos++
		return inner
	}
	if ch.is_digit() || ch == `.` {
		start := a.pos
		for a.pos < a.src.len && (a.src[a.pos].is_digit() || a.src[a.pos] == `.`) {
			a.pos++
		}
		return a.src[start..a.pos].f64()
	}
	if ch.is_letter() || ch == `_` {
		start := a.pos
		for a.pos < a.src.len && (a.src[a.pos].is_alnum() || a.src[a.pos] == `_`) {
			a.pos++
		}
		name := a.src[start..a.pos]
		value := a.ctx[name] or { return error('unknown name `${name}`') }
		return match value {
			f64 {
				value
			}
			// A name holding text still counts if the text is a number, which is what makes a
			// loop counter usable in arithmetic whatever it was stored as.
			string {
				if n := text_as_number(value) {
					n
				} else {
					error('`${name}` is not a number')
				}
			}
			else {
				error('`${name}` is not a number')
			}
		}
	}
	return error('cannot read `${a.src[a.pos..]}`')
}

fn text_as_number(text string) ?f64 {
	trimmed := text.trim_space()
	if trimmed == '' {
		return none
	}
	mut seen_digit := false
	for i, ch in trimmed {
		if ch.is_digit() {
			seen_digit = true
		} else if !(ch == `.` || ((ch == `-` || ch == `+`) && i == 0)) {
			return none
		}
	}
	return if seen_digit { trimmed.f64() } else { none }
}

// Whether this looks like arithmetic rather than a name, a hex colour or a literal. An operator
// at position zero does not count: `-5` is a number, and `#ff0000` must stay a colour.
fn looks_arithmetic(expr string) bool {
	mut depth := 0
	for i, ch in expr {
		if ch == `(` {
			depth++
			return true
		}
		if ch == `)` {
			depth--
		}
		if i > 0 && ch in [`+`, `*`, `/`, `%`] {
			return true
		}
		// A `-` is only an operator with something before it; and not inside a name like
		// `some-name`, which has no spaces around it.
		if i > 0 && ch == `-` && expr[i - 1] == ` ` {
			return true
		}
	}
	return depth != 0
}

fn eval_arith(expr string, ctx map[string]TplValue) !f64 {
	mut a := Arith{
		src: expr
		ctx: ctx
	}
	value := a.expr()!
	a.skip_spaces()
	if a.pos < a.src.len {
		return error('unexpected `${a.src[a.pos..]}`')
	}
	return value
}

// A template that asks for a billion iterations has made a mistake, and the useful response is
// to say so rather than to appear to hang.
const max_range_steps = 100000

// `a..b` stops before b and `a..=b` includes it, following Rust — which is where the `..`
// spelling comes from, and the expectation a template author arrives with.
//
// Both ends are full expressions, so `0..count - 1` and `0..(n * 2)` work.
fn render_range(node Node, ctx map[string]TplValue, mut out strings.Builder, mut problems []string) {
	idx := node.text.index('..') or { return }
	inclusive := node.text.len > idx + 2 && node.text[idx + 2] == `=`
	from_text := node.text[..idx].trim_space()
	to_text := node.text[idx + if inclusive { 3 } else { 2 }..].trim_space()

	from := eval_range_end(from_text, ctx) or {
		problems << 'for ... in ${node.text}: ${err}'
		return
	}
	to := eval_range_end(to_text, ctx) or {
		problems << 'for ... in ${node.text}: ${err}'
		return
	}

	start := i64(from)
	stop := if inclusive { i64(to) + 1 } else { i64(to) }
	if stop <= start {
		// Empty, as `10..0` is in Rust. Counting downwards instead would be a guess about what
		// was meant, and a silent one.
		return
	}
	if stop - start > max_range_steps {
		problems << 'for ... in ${node.text}: ${stop - start} steps, more than ${max_range_steps}'
		return
	}

	total := int(stop - start)
	for offset in 0 .. total {
		value := start + offset
		mut inner := ctx.clone()
		inner[node.name] = TplValue(f64(value))
		inner['loop_index'] = TplValue(f64(offset))
		inner['loop_first'] = TplValue(offset == 0)
		inner['loop_last'] = TplValue(offset == total - 1)
		render_nodes(node.body, inner, mut out, mut problems)
	}
}

fn eval_range_end(text string, ctx map[string]TplValue) !f64 {
	if text == '' {
		return error('a range needs both ends')
	}
	if n := text_as_number(text) {
		return n
	}
	if n := eval_arith(text, ctx) {
		return n
	}
	// A plain name is not arithmetic, so fall back to reading it out of the context.
	value := ctx[text] or { return error('unknown name `${text}`') }
	if value is f64 {
		return value
	}
	if value is string {
		if n := text_as_number(value) {
			return n
		}
	}
	return error('`${text}` is not a number')
}

module main

import math
import strings

// What a template expression can evaluate to. Colours stay colours all the way through the
// pipeline rather than becoming strings at the first opportunity — that is what lets
// `{{ color1 | lighten: 0.2 | set_alpha: 0.5 }}` mean anything, and it is the difference between
// a templating engine that understands colour and one doing string substitution.
type TplValue = Color | []Color | bool | string

// A bare `{{ color1 }}` prints **without** the leading hash, because that is what it has always
// printed and every template in the wild supplies its own: `templates/colors.sh` writes
// '#{{ background }}', which would become '##0b0e0d' the moment this started emitting one.
// `{{ color1.hex }}` is the way to ask for it.
//
// Alpha is appended once the colour carries any, so `{{ accent | set_alpha: 0.5 }}` does not
// render identically to `{{ accent }}` and look like the filter did nothing.
fn (v TplValue) display() string {
	return match v {
		string {
			v
		}
		Color {
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
		[]Color {
			v.map(it.to_hex(false)).join(' ')
		}
	}
}

fn (v TplValue) truthy() bool {
	return match v {
		bool { v }
		string { v != '' && v != 'false' && v != '0' }
		Color { true }
		[]Color { v.len > 0 }
	}
}

fn fmt2(x f64) string {
	return '${x:.2f}'
}

// The colour formats a config file might want. Named after matugen's so a template written for
// one is readable against the other.
fn color_field(c Color, field string) !string {
	r, g, b := c.rgb_u8()
	hsl := c.to_hsl()
	lab := c.to_lab()
	alpha := clamp01(c.alpha)
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

fn as_color(v TplValue, filter string) !Color {
	return match v {
		Color {
			v
		}
		string {
			parse_hex(v) or { return error('`${filter}` needs a colour, got the string `${v}`') }
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
			return TplValue(color_from_hsl(hsl.h, clamp01(hsl.s + as_number(args, 0, name)!), hsl.l))
		}
		'desaturate' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color_from_hsl(hsl.h, clamp01(hsl.s - as_number(args, 0, name)!), hsl.l))
		}
		'set_hue' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color_from_hsl(as_number(args, 0, name)!, hsl.s, hsl.l))
		}
		'set_saturation' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color_from_hsl(hsl.h, clamp01(as_number(args, 0, name)!), hsl.l))
		}
		'set_lightness' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color_from_hsl(hsl.h, hsl.s, clamp01(as_number(args, 0, name)!)))
		}
		'set_alpha' {
			mut c := as_color(input, name)!
			c.alpha = clamp01(as_number(args, 0, name)!)
			return TplValue(c)
		}
		'rotate' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color_from_hsl(hsl.h + as_number(args, 0, name)!, hsl.s, hsl.l))
		}
		'grayscale' {
			c := as_color(input, name)!
			hsl := c.to_hsl()
			return TplValue(color_from_hsl(hsl.h, 0.0, hsl.l))
		}
		'complement' {
			return TplValue(as_color(input, name)!.complementary())
		}
		'invert' {
			c := as_color(input, name)!
			r, g, b := c.rgb_u8()
			return TplValue(color_from_rgb(255 - r, 255 - g, 255 - b))
		}
		'mix' {
			c := as_color(input, name)!
			if args.len < 1 {
				return error('`mix` needs a colour to mix with')
			}
			other := parse_hex(args[0]) or { return error('`mix`: `${args[0]}` is not a colour') }
			amount := if args.len > 1 { as_number(args, 1, name)! } else { 0.5 }
			return TplValue(c.mix_lab(other, clamp01(amount)))
		}
		// Picks whichever of black or white reads against this colour. The reason a template can
		// set a foreground without the author knowing what the background turned out to be.
		'contrast' {
			c := as_color(input, name)!
			readable := if c.to_lab().l < 55.0 {
				color_from_rgb(255, 255, 255)
			} else {
				color_from_rgb(0, 0, 0)
			}
			return TplValue(readable)
		}
		// String transforms, applied to whatever the value displays as.
		'upper' {
			return TplValue(input.display().to_upper())
		}
		'lower' {
			return TplValue(input.display().to_lower())
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
	} else {
		parts := trimmed.split('.')
		name := parts[0]
		found := ctx[name] or {
			// A bare hex literal is a colour, so `{{ #ff0000 | lighten: 0.1 }}` works without
			// having to name it first.
			if c := parse_hex(name) {
				TplValue(c)
			} else {
				return error('unknown name `${name}`')
			}
		}
		value = found
		if parts.len > 1 {
			field := parts[1..].join('.')
			match found {
				Color { value = TplValue(color_field(found, field)!) }
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
fn parse_nodes(src string, from int, stop []string) ([]Node, string, int) {
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
				body, ended, after := parse_nodes(src, block.finish, ['else', 'endif'])
				mut node := Node{
					kind: .cond
					text: block.rest
					body: body
				}
				mut cont := after
				if ended == 'else' {
					alt, _, after_else := parse_nodes(src, after, ['endif'])
					node.alt = alt
					cont = after_else
				}
				nodes << node
				cursor = cont
			}
			'for' {
				// `for name in iterable`
				words := block.rest.split(' ').filter(it != '')
				body, _, after := parse_nodes(src, block.finish, ['endfor'])
				nodes << Node{
					kind: .loop
					name: if words.len > 0 { words[0] } else { 'item' }
					text: if words.len > 2 { words[2] } else { '' }
					body: body
				}
				cursor = after
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
				items := ctx[node.text] or {
					problems << 'for ... in ${node.text}: unknown name'
					continue
				}
				if items is []Color {
					for i, item in items {
						mut inner := ctx.clone()
						inner[node.name] = TplValue(item)
						inner['loop_index'] = TplValue('${i}')
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

// Everything a template can name.
pub fn template_context(scheme &Scheme) map[string]TplValue {
	mut ctx := map[string]TplValue{}
	for i, color in scheme.colors {
		ctx['color${i}'] = TplValue(color)
	}
	if scheme.colors.len > 15 {
		ctx['background'] = TplValue(scheme.colors[0])
		ctx['foreground'] = TplValue(scheme.colors[15])
		ctx['cursor'] = TplValue(scheme.colors[1])
		ctx['accent'] = TplValue(scheme.colors[1])
	}
	mut extracted := []Color{}
	for hex in scheme.pigments {
		extracted << color_from_hex(hex)
	}
	ctx['colors'] = TplValue(scheme.colors)
	ctx['pigments'] = TplValue(extracted)
	ctx['wallpaper'] = TplValue(scheme.image)
	ctx['theme'] = TplValue(scheme.theme)
	ctx['dark'] = TplValue(scheme.is_dark())
	ctx['light'] = TplValue(!scheme.is_dark())
	return ctx
}

pub fn render(content string, ctx map[string]TplValue) (string, []string) {
	nodes, _, _ := parse_nodes(content, 0, [])
	mut out := strings.new_builder(content.len + 256)
	mut problems := []string{}
	render_nodes(nodes, ctx, mut out, mut problems)
	return out.str(), problems
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

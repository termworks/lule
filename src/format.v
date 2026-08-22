module main

import config
import color

fn bg_truecolor(c color.Color, text string) string {
	r, g, b := c.rgb_u8()
	fg := if c.to_lab().l < 30.0 { '255;255;255' } else { '0;0;0' }
	return '\x1b[48;2;${r};${g};${b}m\x1b[38;2;${fg}m${text}\x1b[0m'
}

pub fn show_colors(scheme &config.Scheme, from int, to int, padding int) {
	colors := scheme.colors
	for i := from; i < to; i++ {
		if i >= colors.len {
			break
		}
		val := '  ${i:03}  '
		if (i % 12 == 4 && i > 16) || (i == 16 || i == 8) {
			println('')
		}
		if i == 16 || i == 232 {
			println('')
		}
		print(bg_truecolor(colors[i], val))
	}
	println('')
}

pub fn show_specified_colors(colors []color.Color, padding int) {
	pad := ' '.repeat(if padding > 0 { padding } else { 1 })
	for i, color in colors {
		val := '${pad}${color.to_hex(true)}${pad}'
		if (i % 12 == 4 && i > 16) || (i == 16 || i == 8) {
			println('')
		}
		print(bg_truecolor(color, val))
	}
	println('')
}

pub fn show_pastel_colors(scheme &config.Scheme, from int, to int) {
	for i := from; i < to; i++ {
		if i >= scheme.colors.len {
			break
		}
		c := scheme.colors[i]
		lab := c.to_lab()
		lch := c.to_lch()
		hsl := c.to_hsl()
		r, g, b := c.rgb_u8()
		swatch := bg_truecolor(c, '      ')
		println('${swatch} ${i:3}  ${c.to_hex(true)}  rgb(${r:3}, ${g:3}, ${b:3})  hsl(${hsl.h:6.1f}, ${hsl.s:4.2f}, ${hsl.l:4.2f})  lab(${lab.l:6.2f}, ${lab.a:7.2f}, ${lab.b:7.2f})  lch(${lch.l:6.2f}, ${lch.c:6.2f}, ${lch.h:6.2f})')
	}
}

module wallgen

import math
import strings

fn repeat_tile(body string, tw f64, th f64, w f64, h f64, seed u32) string {
	return '<defs><pattern id="tile" width="${tw}" height="${th}" patternUnits="userSpaceOnUse" patternTransform="translate(${seed % 31} ${seed % 29})"><g stroke-width="1.8">${body}</g></pattern></defs><rect width="${w}" height="${h}" fill="url(#tile)" stroke="none"/>'
}

fn geometric_tiles(style string, w f64, h f64, seed u32) string {
	body := match style {
		'diagonals' { '<path d="M-20 20L20-20M0 80L80 0M60 100L100 60M-20 60L60-20M20 100L100 20"/>' }
		'chevrons' { '<path d="M0 10L40 35L80 10M0 50L40 75L80 50" stroke-width="3"/>' }
		'herringbone' { '<path d="M0 0H40V20H20V60H0ZM40 20H80V40H60V80H40ZM0 60H40M60 40V0M20 20V0M60 60H80"/>' }
		'basketweave' { '<path d="M4 10H36M4 20H36M4 30H36M50 4V36M60 4V36M70 4V36M10 44V76M20 44V76M30 44V76M44 50H76M44 60H76M44 70H76" stroke-width="4"/>' }
		'brick' { '<path d="M0 0H80M0 40H80M40 0V40M0 40V80M80 40V80"/>' }
		'diamonds' { '<path d="M40 0L80 40L40 80L0 40ZM40 14L66 40L40 66L14 40Z"/>' }
		'octagons' { '<path d="M24 0H56L80 24V56L56 80H24L0 56V24Z"/>' }
		'scales' { '<path d="M0 0Q40 80 80 0M-40 40Q0 120 40 40M40 40Q80 120 120 40"/>' }
		'seigaiha' { '<path d="M0 40A40 40 0 0 1 80 40M8 40A32 32 0 0 1 72 40M16 40A24 24 0 0 1 64 40M24 40A16 16 0 0 1 56 40M-40 80A40 40 0 0 1 40 80M-32 80A32 32 0 0 1 32 80M-24 80A24 24 0 0 1 24 80M-16 80A16 16 0 0 1 16 80M40 80A40 40 0 0 1 120 80M48 80A32 32 0 0 1 112 80M56 80A24 24 0 0 1 104 80M64 80A16 16 0 0 1 96 80"/>' }
		'circles' { '<circle cx="40" cy="40" r="34"/><circle cx="40" cy="40" r="24"/><circle cx="40" cy="40" r="8"/>' }
		'quatrefoil' { '<path d="M25 25C5-10 75-10 55 25C90 5 90 75 55 55C75 90 5 90 25 55C-10 75-10 5 25 25Z"/>' }
		'greekkey' { '<path d="M0 10H70V70H10V30H50V50H30M80 0H0V80H80" stroke-width="3"/>' }
		'pinwheel' { '<path d="M40 40L40 4L68 12ZM40 40L76 40L68 68ZM40 40L40 76L12 68ZM40 40L4 40L12 12Z" fill="#000" fill-opacity="0.3"/>' }
		'asanoha' { hemp_leaf() }
		'cubes' { '<path d="M40 0L75 20V60L40 80L5 60V20ZM5 20L40 40L75 20M40 40V80"/><path d="M5 20L40 40V80L5 60Z" fill="#000" fill-opacity="0.25" stroke="none"/>' }
		'crosshatch' { '<path d="M4 24L24 4M4 34L34 4M14 34L34 14M46 6L74 34M46 16L64 34M56 6L74 24M6 46L34 74M6 56L24 74M16 46L34 64M44 64L64 44M44 74L74 44M54 74L74 54" stroke-width="2"/>' }
		else { '' }
	}

	if body == '' { return '' }
	return repeat_tile(body, 80, 80, w, h, seed)
}

fn hemp_leaf() string {
	mut b := strings.new_builder(1200)
	b.write_string('<polygon points="${polygon(40, 40, 40, 6, false)}"/>')
	mut p := strings.new_builder(900)
	for i in 0 .. 6 {
		a := f64(i) * math.pi / 3
		bb := a + math.pi / 3
		x := 40 + math.sin(a) * 40
		y := 40 + math.cos(a) * 40
		xx := 40 + math.sin(bb) * 40
		yy := 40 + math.cos(bb) * 40
		mx := (x + xx + 40) / 3
		my := (y + yy + 40) / 3
		line(mut p, 40, 40, x, y)
		line(mut p, mx, my, x, y)
		line(mut p, mx, my, xx, yy)
		line(mut p, mx, my, 40, 40)
	}
	b.write_string('<path d="${p.str()}"/>')
	return b.str()
}

fn routed_tiles(style string, w f64, h f64, seed u32) string {
	mut b := strings.new_builder(16000)
	step := 48.0
	for row in 0 .. int(h / step) + 1 {
		for col in 0 .. int(w / step) + 1 {
			x := col * step
			y := row * step
			flip := hash(col, row, seed) % 2 == 0
			if style == 'truchet' {
				path := if flip {
					'M0 24A24 24 0 0 0 24 0M24 48A24 24 0 0 1 48 24'
				} else {
					'M24 0A24 24 0 0 0 48 24M0 24A24 24 0 0 1 24 48'
				}
				b.write_string('<path transform="translate(${x} ${y})" d="${path}" stroke-width="2"/>')
			} else if style == 'maze' {
				path := if flip { 'M0 0L48 48' } else { 'M0 48L48 0' }
				b.write_string('<path transform="translate(${x} ${y})" d="${path}" stroke-width="2"/>')
			} else {
				rotation := int(hash(col, row, seed) % 4) * 90
				b.write_string('<g transform="translate(${x} ${y}) rotate(${rotation} 24 24)"><path d="M0 12H20L32 24V48M0 24H12L24 36V48M48 0V10H40"/><circle cx="36" cy="10" r="4"/><circle cx="32" cy="24" r="2.5"/></g>')
			}
		}
	}
	return b.str()
}

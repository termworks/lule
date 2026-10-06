module wallgen

import math
import strings

fn hash(x int, y int, seed u32) u32 {
	mut n := u32(x) * u32(374761393) + u32(y) * u32(668265263) + seed * u32(1274126177)
	n = (n ^ (n >> 13)) * u32(1274126177)
	return n ^ (n >> 16)
}

fn noise(x f64, y f64, seed u32) f64 {
	xi := int(math.floor(x))
	yi := int(math.floor(y))
	fx := x - xi
	fy := y - yi
	u := fx * fx * (3 - 2 * fx)
	v := fy * fy * (3 - 2 * fy)
	a := f64(hash(xi, yi, seed)) / 4294967295.0
	b := f64(hash(xi + 1, yi, seed)) / 4294967295.0
	c := f64(hash(xi, yi + 1, seed)) / 4294967295.0
	d := f64(hash(xi + 1, yi + 1, seed)) / 4294967295.0
	return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v
}

fn fbm(x f64, y f64, seed u32) f64 {
	mut sum := 0.0
	mut amplitude := 0.5
	mut frequency := 1.0
	for octave in 0 .. 5 {
		sum += amplitude * noise(x * frequency, y * frequency, seed + u32(octave))
		frequency *= 2
		amplitude *= 0.5
	}
	return sum
}

fn line(mut b strings.Builder, x f64, y f64, xx f64, yy f64) {
	b.write_string('M${x:.2f},${y:.2f}L${xx:.2f},${yy:.2f}')
}

fn polygon(cx f64, cy f64, radius f64, points int, star bool) string {
	mut b := strings.new_builder(200)
	for i in 0 .. points {
		angle := f64(i) * 2 * math.pi / points
		r := if star && i % 2 == 1 { radius * 0.72 } else { radius }
		x := cx + math.sin(angle) * r
		y := cy + math.cos(angle) * r
		b.write_string('${x:.2f},${y:.2f} ')
	}
	return b.str()
}

fn tile(style string) string {
	return match style {
		'cross' { '<path d="M18 18l16 16m0-16L18 34"/>' }
		'grid' { '<path d="M0 0H52V52"/><path d="M26 0V52M0 26H52" opacity="0.45"/>' }
		'dots' { '<circle cx="13" cy="13" r="7" fill="#000" stroke="none"/><circle cx="39" cy="39" r="7" fill="#000" stroke="none"/>' }
		'digi' { '<path d="M0 0L52 52M0 52L52 0M26 0V52M0 26H52" stroke-width="0.6"/><path d="M23 23h6v6h-6zM0 0h3v3H0z" fill="#000"/>' }
		'stars' { '<polygon points="${polygon(26, 26, 26, 16, true)}"/>' }
		else { '' }
	}
}

fn hexagons(style string, w f64, h f64) string {
	mut b := strings.new_builder(12000)
	r := if style == 'nato' {
		38.0
	} else if style == 'triang' {
		32.0
	} else {
		22.0
	}
	dx := math.sqrt(3) * r
	for row in -1 .. int(h / (r * 1.5)) + 2 {
		for col in -1 .. int(w / dx) + 2 {
			x := col * dx + f64(row & 1) * dx / 2
			y := row * r * 1.5
			if style == 'nato' {
				for arm in 0 .. 3 {
					a := f64(arm) * math.pi * 2 / 3
					px := math.cos(a) * 1.8
					py := -math.sin(a) * 1.8
					tx := x + math.sin(a) * r * 0.88
					ty := y + math.cos(a) * r * 0.88
					b.write_string('<polygon points="${x + px:.2f},${y + py:.2f} ${tx:.2f},${ty:.2f} ${x - px:.2f},${y - py:.2f}" fill="#000" stroke="none"/>')
				}
			} else {
				b.write_string('<polygon points="${polygon(x, y, r, 6, false)}"/>')
				if style == 'hexag' {
					b.write_string('<polygon points="${polygon(x, y, r * 0.78, 6, false)}" stroke-width="0.6"/>')
				}
				if style == 'triang' {
					mut p := strings.new_builder(160)
					for i in 0 .. 3 {
						a := f64(i) * math.pi / 3
						line(mut p, x + math.sin(a) * r, y + math.cos(a) * r, x - math.sin(a) * r,
							y - math.cos(a) * r)
					}
					b.write_string('<path d="${p.str()}"/>')
				}
			}
		}
	}
	return b.str()
}

fn dome(w f64, h f64, seed u32) string {
	mut b := strings.new_builder(16000)
	step := 110.0
	for row in -1 .. int(h / step) + 2 {
		for col in -1 .. int(w / step) + 2 {
			x, y := vertex(col, row, step, seed)
			x1, y1 := vertex(col + 1, row, step, seed)
			x2, y2 := vertex(col, row + 1, step, seed)
			x3, y3 := vertex(col + 1, row + 1, step, seed)
			line(mut b, x, y, x1, y1)
			line(mut b, x, y, x2, y2)
			line(mut b, x, y, x3, y3)
		}
	}
	return '<path d="${b.str()}" stroke-width="1.6"/>'
}

fn vertex(col int, row int, step f64, seed u32) (f64, f64) {
	x := (f64(hash(col, row, seed)) / 4294967295.0 - 0.5) * step * 0.75
	y := (f64(hash(col, row, seed + 1)) / 4294967295.0 - 0.5) * step * 0.75
	return col * step + x, row * step + y
}

fn contours(w f64, h f64, seed u32) string {
	step := 8.0
	nx := int(math.ceil(w / step)) + 1
	ny := int(math.ceil(h / step)) + 1
	mut field := []f64{len: nx * ny}
	for y in 0 .. ny {
		for x in 0 .. nx {
			field[y * nx + x] = fbm(x * step / 210, y * step / 210, seed)
		}
	}
	mut b := strings.new_builder(64000)
	for level in 2 .. 17 {
		threshold := f64(level) / 20
		for y in 0 .. ny - 1 {
			for x in 0 .. nx - 1 {
				values := [field[y * nx + x], field[y * nx + x + 1], field[(y + 1) * nx + x + 1],
					field[(y + 1) * nx + x]]
				xs := [f64(x) * step, (x + 1) * step, (x + 1) * step, x * step]
				ys := [f64(y) * step, y * step, (y + 1) * step, (y + 1) * step]
				mut px := []f64{}
				mut py := []f64{}
				for edge in 0 .. 4 {
					next := (edge + 1) % 4
					if (values[edge] >= threshold) == (values[next] >= threshold) { continue
					 }
					t := (threshold - values[edge]) / (values[next] - values[edge])
					px << xs[edge] + t * (xs[next] - xs[edge])
					py << ys[edge] + t * (ys[next] - ys[edge])
				}
				for i := 0; i + 1 < px.len; i += 2 {
					line(mut b, px[i], py[i], px[i + 1], py[i + 1])
				}
			}
		}
	}
	return '<path d="${b.str()}"/>'
}

fn pattern(style string, w f64, h f64, seed u32) string {
	tiled := geometric_tiles(style, w, h, seed)
	if tiled != '' { return tiled }
	if style in ['truchet', 'maze', 'circuit'] { return routed_tiles(style, w, h, seed) }
	if style in ['waves', 'ribbons', 'flowfield'] { return flowing(style, w, h, seed) }
	if style in ['voronoi', 'pebbles'] { return cells(style, w, h, seed) }
	if style in ['constellation', 'phyllotaxis', 'spirals', 'rosettes'] {
		return ornaments(style, w, h, seed)
	}
	if style in ['sierpinski', 'koch', 'hilbert', 'branches'] { return fractals(style, w, h, seed) }
	if style in ['honey', 'hexag', 'triang', 'nato'] { return hexagons(style, w, h) }
	if style == 'dome' { return dome(w, h, seed) }
	if style == 'contours' { return contours(w, h, seed) }
	spacing := if style == 'dots' {
		22
	} else if style == 'stars' {
		104
	} else {
		52
	}
	angle := if style in ['dots', 'digi'] { 15 } else { 0 }
	return '<defs><pattern id="pattern" width="52" height="52" patternUnits="userSpaceOnUse" patternTransform="rotate(${angle}) scale(${f64(spacing) / 52}) translate(${seed % 52} ${seed % 37})">${tile(style)}</pattern></defs><rect width="${w}" height="${h}" fill="url(#pattern)" stroke="none"/>'
}

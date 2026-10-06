module wallgen

import math
import strings

struct Point {
	x f64
	y f64
}

fn flowing(style string, w f64, h f64, seed u32) string {
	mut b := strings.new_builder(64000)
	phase := f64(hash(1, 3, seed) % 628) / 100
	if style == 'flowfield' {
		for row in -1 .. int(h / 30) + 2 {
			for col in -1 .. int(w / 70) + 2 {
				mut x := col * 70.0
				mut y := row * 30.0
				b.write_string('M${x:.2f},${y:.2f}')
				for _ in 0 .. 32 {
					a := (noise(x / 260, y / 260, seed) - 0.5) * 6
					x += math.cos(a) * 5
					y += math.sin(a) * 5
					b.write_string('L${x:.2f},${y:.2f}')
				}
			}
		}
	} else {
		spacing := if style == 'waves' { 24.0 } else { 55.0 }
		for row in -4 .. int(h / spacing) + 5 {
			strands := if style == 'ribbons' { 5 } else { 1 }
			for strand in 0 .. strands {
				for col in 0 .. int(w / 8) + 2 {
					x := col * 8.0
					displacement := if style == 'waves' {
						math.sin(x / 90 + phase) * 18
					} else {
						math.sin(x / 170 + phase + row * 0.24) * 45 +
							(fbm(x / 350, row * 0.12, seed) - 0.5) * 95
					}
					y := row * spacing + strand * 4 + displacement
					command := if col == 0 { 'M' } else { 'L' }
					b.write_string('${command}${x:.2f},${y:.2f}')
				}
			}
		}
	}
	return '<path d="${b.str()}" stroke-width="1.5" stroke-linecap="round"/>'
}

fn clip_cell(points []Point, nx f64, ny f64, limit f64) []Point {
	mut out := []Point{}
	for i, a in points {
		b := points[(i + 1) % points.len]
		da := a.x * nx + a.y * ny - limit
		db := b.x * nx + b.y * ny - limit
		if da <= 0 { out << a }
		if (da <= 0) != (db <= 0) {
			t := da / (da - db)
			out << Point{a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)}
		}
	}
	return out
}

fn cells(style string, w f64, h f64, seed u32) string {
	step := 95.0
	mut sites := []Point{}
	for row in -1 .. int(h / step) + 2 {
		for col in -1 .. int(w / step) + 2 {
			x, y := vertex(col, row, step, seed)
			sites << Point{x, y}
		}
	}
	mut b := strings.new_builder(32000)
	for i, site in sites {
		mut cell := [Point{0, 0}, Point{w, 0}, Point{w, h}, Point{0, h}]
		for j, other in sites {
			if i == j { continue
			 }
			nx := other.x - site.x
			ny := other.y - site.y
			limit := (other.x * other.x + other.y * other.y - site.x * site.x - site.y * site.y) / 2
			cell = clip_cell(cell, nx, ny, limit)
			if cell.len == 0 { break
			 }
		}
		if cell.len < 3 { continue
		 }
		mut p := strings.new_builder(200)
		if style == 'pebbles' {
			mut cx := 0.0
			mut cy := 0.0
			for point in cell {
				cx += point.x
				cy += point.y
			}
			cx /= cell.len
			cy /= cell.len
			for k in 0 .. cell.len {
				cell[k] = Point{cx + (cell[k].x - cx) * 0.83, cy + (cell[k].y - cy) * 0.83}
			}
			start := Point{(cell[0].x + cell.last().x) / 2, (cell[0].y + cell.last().y) / 2}
			p.write_string('M${start.x:.2f},${start.y:.2f}')
			for k, a in cell {
				bb := cell[(k + 1) % cell.len]
				p.write_string('Q${a.x:.2f},${a.y:.2f} ${(a.x + bb.x) / 2:.2f},${(a.y + bb.y) / 2:.2f}')
			}
		} else {
			for k, point in cell {
				command := if k == 0 { 'M' } else { 'L' }
				p.write_string('${command}${point.x:.2f},${point.y:.2f}')
			}
		}
		b.write_string('<path d="${p.str()}Z" stroke-width="1.5"/>')
	}
	return b.str()
}

fn ornaments(style string, w f64, h f64, seed u32) string {
	mut b := strings.new_builder(48000)
	if style == 'phyllotaxis' {
		cx := w / 2
		cy := h / 2
		limit := math.sqrt(w * w + h * h) / 2
		for i in 1 .. int(limit * limit / 100) + 1 {
			r := 10 * math.sqrt(f64(i))
			a := i * math.pi * (3 - math.sqrt(5)) + f64(seed % 360)
			x := cx + r * math.cos(a)
			y := cy + r * math.sin(a)
			if x < -5 || y < -5 || x > w + 5 || y > h + 5 { continue
			 }
			b.write_string('<ellipse cx="${x:.2f}" cy="${y:.2f}" rx="3" ry="5" transform="rotate(${a * 180 / math.pi:.2f} ${x:.2f} ${y:.2f})" fill="#000" stroke="none"/>')
		}
		return b.str()
	}
	step := if style == 'constellation' { 95.0 } else { 145.0 }
	for row in -1 .. int(h / step) + 2 {
		for col in -1 .. int(w / step) + 2 {
			x, y := vertex(col, row, step, seed)
			mut p := strings.new_builder(1800)
			if style == 'constellation' {
				b.write_string('<circle cx="${x:.2f}" cy="${y:.2f}" r="${2 +
					hash(col, row, seed) % 3}" fill="#000" stroke="none"/>')
				for offset in [Point{1, 0}, Point{0, 1}, Point{1, 1}] {
					if hash(col + int(offset.x) * 17, row + int(offset.y) * 13, seed) % 3 == 0 { continue
					 }
					xx, yy := vertex(col + int(offset.x), row + int(offset.y), step, seed)
					line(mut p, x, y, xx, yy)
				}
			} else {
				for k in 0 .. 181 {
					a := f64(k) * math.pi / 30
					r := if style == 'spirals' { f64(k) * 0.28 } else { 34 + 14 * math.cos(a * 5) }
					xx := x + r * math.cos(a)
					yy := y + r * math.sin(a)
					command := if k == 0 { 'M' } else { 'L' }
					p.write_string('${command}${xx:.2f},${yy:.2f}')
					if style == 'rosettes' && k == 60 { break
					 }
				}
			}
			b.write_string('<path d="${p.str()}" stroke-width="1.5"/>')
		}
	}
	return b.str()
}

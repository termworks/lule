module wallgen

import math
import strings

fn sierpinski(mut b strings.Builder, a Point, bb Point, c Point, depth int) {
	if depth == 0 {
		b.write_string('M${a.x:.2f},${a.y:.2f}L${bb.x:.2f},${bb.y:.2f}L${c.x:.2f},${c.y:.2f}Z')
		return
	}
	ab := Point{(a.x + bb.x) / 2, (a.y + bb.y) / 2}
	bc := Point{(bb.x + c.x) / 2, (bb.y + c.y) / 2}
	ca := Point{(c.x + a.x) / 2, (c.y + a.y) / 2}
	sierpinski(mut b, a, ab, ca, depth - 1)
	sierpinski(mut b, ab, bb, bc, depth - 1)
	sierpinski(mut b, ca, bc, c, depth - 1)
}

fn koch(mut b strings.Builder, a Point, end Point, depth int) {
	if depth == 0 {
		line(mut b, a.x, a.y, end.x, end.y)
		return
	}
	dx := (end.x - a.x) / 3
	dy := (end.y - a.y) / 3
	p := Point{a.x + dx, a.y + dy}
	q := Point{a.x + dx * 2, a.y + dy * 2}
	tip := Point{p.x + dx * 0.5 + dy * math.sqrt(3) / 2, p.y + dy * 0.5 - dx * math.sqrt(3) / 2}
	koch(mut b, a, p, depth - 1)
	koch(mut b, p, tip, depth - 1)
	koch(mut b, tip, q, depth - 1)
	koch(mut b, q, end, depth - 1)
}

fn hilbert_point(index int, side int) Point {
	mut x := 0
	mut y := 0
	mut t := index
	for scale := 1; scale < side; scale *= 2 {
		rx := (t / 2) & 1
		ry := (t ^ rx) & 1
		if ry == 0 {
			if rx == 1 {
				x = scale - 1 - x
				y = scale - 1 - y
			}
			x, y = y, x
		}
		x += scale * rx
		y += scale * ry
		t /= 4
	}
	return Point{f64(x), f64(y)}
}

fn branch(mut b strings.Builder, x f64, y f64, length f64, angle f64, depth int, seed u32) {
	if depth == 0 { return }
	xx := x + math.cos(angle) * length
	yy := y + math.sin(angle) * length
	line(mut b, x, y, xx, yy)
	spread := 0.35 + f64(hash(depth, 4, seed) % 25) / 100
	branch(mut b, xx, yy, length * 0.7, angle - spread, depth - 1, seed + 1)
	branch(mut b, xx, yy, length * 0.72, angle + spread, depth - 1, seed + 2)
}

fn fractals(style string, w f64, h f64, seed u32) string {
	mut p := strings.new_builder(12000)
	if style == 'hilbert' {
		for i in 0 .. 256 {
			point := hilbert_point(i, 16)
			command := if i == 0 { 'M' } else { 'L' }
			p.write_string('${command}${8 + point.x * 10},${8 + point.y * 10}')
		}
		return repeat_tile('<path d="${p.str()}" stroke-width="1.5"/>', 166, 166, w, h, seed)
	}
	if style == 'sierpinski' {
		sierpinski(mut p, Point{90, 8}, Point{8, 150}, Point{172, 150}, 3)
		return repeat_tile('<path d="${p.str()}"/>', 180, 158, w, h, seed)
	}
	if style == 'koch' {
		a := Point{90, 24}
		bb := Point{150, 128}
		c := Point{30, 128}
		koch(mut p, a, bb, 3)
		koch(mut p, bb, c, 3)
		koch(mut p, c, a, 3)
		return repeat_tile('<path d="${p.str()}" stroke-width="1.2"/>', 180, 180, w, h, seed)
	}
	for row in 0 .. int(h / 220) + 1 {
		for col in 0 .. int(w / 160) + 1 {
			branch(mut p, col * 160.0 + 80, row * 220.0 + 210, 65, -math.pi / 2, 6, seed +
				hash(col, row, seed))
		}
	}
	return '<path d="${p.str()}" stroke-width="1.2"/>'
}

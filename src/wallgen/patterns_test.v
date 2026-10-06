module wallgen

import crypto.sha256
import math

fn test_every_pattern_renders_visible_and_distinct() {
	mut seen := map[string]string{}
	for style in styles {
		body := pattern(style, 1600, 1000, 42)
		assert body.len > 0, style
		assert body == pattern(style, 1600, 1000, 42), style
		source := '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="160" viewBox="0 0 1600 1000"><g fill="none" stroke="#000">${body}</g></svg>'
		pixels := render_pixels(source, 256, 160)!
		mut visible := 0
		for i := 3; i < pixels.len; i += 4 {
			if pixels[i] > 8 { visible++ }
		}
		assert visible > 100, '${style} has no visible pattern'
		assert visible < 256 * 160 * 0.85, '${style} covers the canvas rather than drawing a pattern'
		digest := sha256.hexhash(pixels.bytestr())
		assert digest !in seen, '${style} duplicates ${seen[digest]}'
		seen[digest] = style
	}
	assert seen.len == styles.len
}

fn test_pattern_geometry_is_bounded_at_extreme_aspect_ratios() {
	for style in styles {
		for size in [Point{4000, 32}, Point{32, 4000}, Point{1000, 1000}] {
			body := pattern(style, size.x, size.y, 4294967295)
			assert body.len < 3000000, '${style}: ${body.len}'
			assert !body.contains('nan') && !body.contains('inf'), style
		}
	}
}

fn test_hilbert_visits_each_cell_with_adjacent_steps() {
	mut visited := map[string]bool{}
	mut previous := Point{}
	for i in 0 .. 256 {
		p := hilbert_point(i, 16)
		assert p.x >= 0 && p.x < 16 && p.y >= 0 && p.y < 16
		key := '${p.x},${p.y}'
		assert !visited[key]
		visited[key] = true
		if i > 0 { assert math.abs(p.x - previous.x) + math.abs(p.y - previous.y) == 1
		 }
		previous = p
	}
}

fn test_voronoi_halfplane_clipping() {
	cell := [Point{0, 0}, Point{100, 0}, Point{100, 100}, Point{0, 100}]
	clipped := clip_cell(cell, 1, 0, 50)
	assert clipped.len == 4
	for p in clipped {
		assert p.x <= 50 && p.x >= 0
	}
	assert clip_cell(cell, 1, 0, -1).len == 0
}

module palette

import cmd
import color
import math

fn planted_pixels() []color.Lab {
	// Three tight blobs of very different colours, plus a large flat grey area. The grey is the
	// majority, which is what separates the backends: some chase area, some chase colour.
	mut pixels := []color.Lab{}
	for _ in 0 .. 300 {
		pixels << color.color_from_rgb(130, 130, 130).to_lab()
	}
	for c in [color.color_from_rgb(220, 20, 20), color.color_from_rgb(20, 200, 20),
		color.color_from_rgb(20, 20, 220)] {
		r, g, b := c.rgb_u8()
		for i in 0 .. 40 {
			jitter := u8(i % 3)
			pixels << color.color_from_rgb(r + jitter, g + jitter, b + jitter).to_lab()
		}
	}
	return pixels
}

fn chroma_of(c color.Lab) f64 {
	return math.sqrt(c.a * c.a + c.b * c.b)
}

fn every_backend() []string {
	return ['pigment', 'median', 'histogram', 'tonal']
}

fn run_backend(name string, pixels []color.Lab, count int) []Pigment {
	return match name {
		'median' { palette_median_cut(pixels, count) }
		'histogram' { palette_histogram(pixels, count) }
		'tonal' { palette_tonal(pixels, count) }
		else { palette_kmeans(pixels, count, 60) }
	}
}

fn test_every_backend_is_reachable_from_the_flag() {
	// The list the flag validates against and the list the dispatch understands have to agree,
	// or a name is accepted and then silently does nothing.
	for name in every_backend() {
		known := cmd.known_palettes()
		assert name in known, '${name} is not in known_palettes'
	}
	assert cmd.known_palettes().len == every_backend().len
}

fn test_every_backend_returns_colours() {
	pixels := planted_pixels()
	for name in every_backend() {
		out := run_backend(name, pixels, 16)
		assert out.len > 0, '${name} returned nothing'
		assert out.len <= 16, '${name} returned ${out.len}, more than asked for'
	}
}

fn test_every_backend_survives_no_pixels() {
	for name in every_backend() {
		assert run_backend(name, [], 16).len == 0, '${name} on an empty image'
	}
}

fn test_every_backend_survives_one_flat_colour() {
	// A solid-colour wallpaper has fewer distinct colours than slots asked for.
	mut flat := []color.Lab{}
	for _ in 0 .. 50 {
		flat << color.color_from_rgb(90, 90, 90).to_lab()
	}
	for name in every_backend() {
		out := run_backend(name, flat, 16)
		assert out.len > 0, '${name} gave up on a flat image'
		for p in out {
			assert !p.dominance.str().contains('nan'), '${name} produced nan'
		}
	}
}

fn test_every_backend_survives_a_silly_count() {
	pixels := planted_pixels()
	for name in every_backend() {
		assert run_backend(name, pixels, 0).len == 0, '${name} with count 0'
		assert run_backend(name, pixels, 1).len <= 1, '${name} with count 1'
	}
}

fn test_median_cut_finds_the_planted_colours() {
	// Median cut divides the colour space rather than chasing area, so the three small blobs
	// survive being outnumbered four to one by grey.
	found := palette_median_cut(planted_pixels(), 8)
	for target in [color.color_from_rgb(220, 20, 20), color.color_from_rgb(20, 200, 20),
		color.color_from_rgb(20, 20, 220)] {
		mut best := 1.0e9
		for p in found {
			d := color.delta_e_cie76(target.to_lab(), p.color)
			if d < best {
				best = d
			}
		}
		assert best < 30.0, 'nothing near ${target.to_hex(true)}, closest ${best}'
	}
}

fn test_histogram_prefers_colour_over_area() {
	// The grey is the majority by pixel count. Weighting by chroma is what stops it taking every
	// slot, so the vivid blobs have to appear.
	found := palette_histogram(planted_pixels(), 8)
	mut vivid := 0
	for p in found {
		if chroma_of(p.color) > 20.0 {
			vivid++
		}
	}
	assert vivid >= 2, 'only ${vivid} chromatic entries out of ${found.len}'
}

fn test_histogram_does_not_return_near_duplicates() {
	// Buckets are a grid, so neighbouring cells hold near-identical colours.
	found := palette_histogram(planted_pixels(), 16)
	for i in 0 .. found.len {
		for j in i + 1 .. found.len {
			d := color.delta_e_cie76(found[i].color, found[j].color)
			assert d >= 8.0, 'entries ${i} and ${j} are only ${d} apart'
		}
	}
}

fn test_tonal_is_one_hue_from_dark_to_light() {
	found := palette_tonal(planted_pixels(), 16)
	assert found.len == 16

	// A ramp: lightness climbs, and no slot is pure black or pure white - those are the
	// background and foreground, and handing them back wastes two of the sixteen.
	for i in 1 .. found.len {
		assert found[i].l_or_zero() > found[i - 1].l_or_zero(), 'not ascending at ${i}'
	}
	for p in found {
		hex := color.color_from_lab(p.color.l, p.color.a, p.color.b, 1.0).to_hex(true)
		assert hex != '#000000' && hex != '#ffffff', 'ramp hit ${hex}'
	}

	// One hue throughout, which is the whole point of deriving rather than extracting.
	mut hues := []f64{}
	for p in found {
		c := color.color_from_lab(p.color.l, p.color.a, p.color.b, 1.0)
		if chroma_of(p.color) > 4.0 {
			hues << c.to_hsl().h
		}
	}
	if hues.len > 1 {
		for h in hues[1..] {
			assert math.abs(h - hues[0]) < 12.0, 'hues drifted: ${hues}'
		}
	}
}

fn test_dominance_is_a_distribution() {
	pixels := planted_pixels()
	// tonal is derived rather than measured, so its dominance is a flat share by construction;
	// the extractors report what they actually found.
	for name in every_backend() {
		mut total := 0.0
		for p in run_backend(name, pixels, 16) {
			assert p.dominance >= 0.0, '${name} produced a negative share'
			total += p.dominance
		}
		assert total > 0.9 && total < 1.1, '${name} shares summed to ${total}'
	}
}

fn test_backends_disagree_with_each_other() {
	// If two backends returned the same palette one of them would be pointless.
	pixels := planted_pixels()
	mut seen := map[string]bool{}
	for name in every_backend() {
		mut key := ''
		for p in run_backend(name, pixels, 8) {
			key += color.color_from_lab(p.color.l, p.color.a, p.color.b, 1.0).to_hex(true)
		}
		assert key !in seen, '${name} produced an identical palette to another backend'
		seen[key] = true
	}
}

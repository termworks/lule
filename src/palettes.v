module main

import color
import math

// Median cut, in color.Lab.
//
// Repeatedly splits the widest axis of a box at its median. Where k-means chases cluster centres
// and so gravitates to whatever covers the most area, median cut divides the *space* — so a
// wallpaper that is four fifths sky still gives up the colours in the other fifth.

// One distinct colour and how many pixels had it.
//
// Median cut divides *distinct colours*, not pixels. Splitting raw pixels degenerates the moment
// one colour holds most of them: every median lands inside that mass, so each split carves the
// majority in half and the minority colours never get a box of their own. On a test image that is
// 70% flat grey, the planted red came back 55 ΔE away - which is not red.
struct Swatch {
	color color.Lab
	count int
}

struct Box {
mut:
	swatches []Swatch
}

fn (b Box) spread() (int, f64) {
	if b.swatches.len == 0 {
		return 0, 0.0
	}
	first := b.swatches[0].color
	mut lo := [first.l, first.a, first.b]
	mut hi := lo.clone()
	for s in b.swatches {
		for axis, value in [s.color.l, s.color.a, s.color.b] {
			if value < lo[axis] {
				lo[axis] = value
			}
			if value > hi[axis] {
				hi[axis] = value
			}
		}
	}
	mut widest := 0
	mut width := hi[0] - lo[0]
	for axis in 1 .. 3 {
		if hi[axis] - lo[axis] > width {
			width = hi[axis] - lo[axis]
			widest = axis
		}
	}
	return widest, width
}

// Weighted by pixel count, so the average sits where the pixels actually are even though the
// splitting ignored how many there were.
fn (b Box) average() (color.Lab, int) {
	mut l := 0.0
	mut a := 0.0
	mut bb := 0.0
	mut total := 0
	for s in b.swatches {
		w := f64(s.count)
		l += s.color.l * w
		a += s.color.a * w
		bb += s.color.b * w
		total += s.count
	}
	if total == 0 {
		return color.Lab{0.0, 0.0, 0.0, 1.0}, 0
	}
	n := f64(total)
	return color.Lab{l / n, a / n, bb / n, 1.0}, total
}

// Collapses pixels onto a fine grid so that "distinct colour" means something on a photograph,
// where almost every pixel differs slightly from its neighbour.
fn to_swatches(pixels []color.Lab) []Swatch {
	step := 2.0
	mut counts := map[string]int{}
	mut sums := map[string][]f64{}
	for p in pixels {
		key := '${int(p.l / step)}:${int(p.a / step)}:${int(p.b / step)}'
		counts[key]++
		if key !in sums {
			sums[key] = [0.0, 0.0, 0.0]
		}
		mut acc := sums[key]
		acc[0] += p.l
		acc[1] += p.a
		acc[2] += p.b
		sums[key] = acc
	}
	mut out := []Swatch{}
	for key, count in counts {
		acc := sums[key] or { continue }
		n := f64(count)
		out << Swatch{color.Lab{acc[0] / n, acc[1] / n, acc[2] / n, 1.0}, count}
	}
	return out
}

pub fn palette_median_cut(pixels []color.Lab, count int) []Pigment {
	if pixels.len == 0 || count < 1 {
		return []Pigment{}
	}
	mut boxes := [Box{to_swatches(pixels)}]

	for boxes.len < count {
		// Split whichever box covers the most colour space; splitting the largest by pixel count
		// instead just keeps subdividing the sky.
		mut target := -1
		mut best := 0.0
		for i, box in boxes {
			if box.swatches.len < 2 {
				continue
			}
			_, width := box.spread()
			if width > best {
				best = width
				target = i
			}
		}
		if target < 0 {
			break // every box holds one colour; there is nothing left to divide
		}

		axis, _ := boxes[target].spread()
		mut sorted := boxes[target].swatches.clone()
		match axis {
			0 { sorted.sort(a.color.l < b.color.l) }
			1 { sorted.sort(a.color.a < b.color.a) }
			else { sorted.sort(a.color.b < b.color.b) }
		}

		middle := sorted.len / 2
		boxes[target] = Box{sorted[..middle].clone()}
		boxes << Box{sorted[middle..].clone()}
	}

	mut out := []Pigment{}
	for box in boxes {
		mean, total := box.average()
		if total > 0 {
			out << Pigment{mean, f64(total) / f64(pixels.len)}
		}
	}
	return out
}

// Frequency counting over a coarse color.Lab grid.
//
// The fastest of the three, and the one that keeps a colour that is *rare but vivid* — a neon sign
// in a night photograph — which both k-means and median cut average away. Counts are weighted by
// chroma so that a wallpaper's acre of grey sky does not win every slot.
pub fn palette_histogram(pixels []color.Lab, count int) []Pigment {
	if pixels.len == 0 || count < 1 {
		return []Pigment{}
	}
	// Coarse enough that near-identical pixels land together, fine enough to keep hues apart.
	step_l := 10.0
	step_ab := 12.0

	mut totals := map[string]f64{}
	mut sums := map[string][]f64{}
	for p in pixels {
		key := '${int(p.l / step_l)}:${int(p.a / step_ab)}:${int(p.b / step_ab)}'
		chroma := math.sqrt(p.a * p.a + p.b * p.b)
		// A vivid pixel counts for more than a grey one, but never for nothing: a genuinely
		// monochrome wallpaper still has to produce a palette.
		weight := 1.0 + chroma / 20.0
		totals[key] += weight
		if key !in sums {
			sums[key] = [0.0, 0.0, 0.0, 0.0]
		}
		mut acc := sums[key]
		acc[0] += p.l
		acc[1] += p.a
		acc[2] += p.b
		acc[3] += 1.0
		sums[key] = acc
	}

	mut ranked := totals.keys()
	ranked.sort_with_compare(fn [totals] (a &string, b &string) int {
		x := totals[*a] or { 0.0 }
		y := totals[*b] or { 0.0 }
		if x > y {
			return -1
		}
		return if x < y { 1 } else { 0 }
	})

	mut out := []Pigment{}
	mut weight_total := 0.0
	for w in totals.values() {
		weight_total += w
	}
	for key in ranked {
		if out.len >= count {
			break
		}
		acc := sums[key] or { continue }
		mean := color.Lab{acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3], 1.0}
		// Buckets are a grid, so two neighbouring cells can hold near-identical colours. Without
		// this the palette fills up with sixteen shades of the same thing.
		mut duplicate := false
		for already in out {
			if color.delta_e_cie76(mean, already.color) < 8.0 {
				duplicate = true
				break
			}
		}
		if duplicate {
			continue
		}
		out << Pigment{mean, (totals[key] or { 0.0 }) / weight_total}
	}
	return out
}

// A tonal ramp from one seed colour, in the spirit of Material You.
//
// The other three read a palette out of the image. This one reads a single *source* colour and
// derives the rest, so every slot shares a hue and the result is coherent in a way an extracted
// palette never is. Good on busy wallpapers, where extraction returns sixteen unrelated colours.
pub fn palette_tonal(pixels []color.Lab, count int) []Pigment {
	if pixels.len == 0 || count < 1 {
		return []Pigment{}
	}
	// The seed is the most *chromatic* dominant colour rather than the most common one, which on
	// most wallpapers is a near-grey that would give a ramp with no colour in it at all.
	dominant := palette_kmeans(pixels, if pixels.len < 8 { 1 } else { 8 }, 60)
	mut seed := dominant[0].color
	mut best := -1.0
	for pigment in dominant {
		chroma := math.sqrt(pigment.color.a * pigment.color.a + pigment.color.b * pigment.color.b)
		score := chroma * (0.35 + pigment.dominance)
		if score > best {
			best = score
			seed = pigment.color
		}
	}

	source := color.color_from_lab(seed.l, seed.a, seed.b, 1.0)
	hsl := source.to_hsl()
	mut out := []Pigment{}
	for i in 0 .. count {
		// Evenly spaced tones across a usable band, ends excluded: pure black and pure white are
		// the background and foreground, and a palette that hands them back wastes two slots.
		lightness := 0.08 + 0.84 * (f64(i) / f64(if count > 1 { count - 1 } else { 1 }))
		tone := color.color_from_hsl(hsl.h, hsl.s, lightness)
		out << Pigment{tone.to_lab(), 1.0 / f64(count)}
	}
	return out
}

// The lightness of a pigment, or zero. Only used by the tests, which need to assert that a tonal
// ramp ascends without reaching into the color.Lab struct at every step.
pub fn (p Pigment) l_or_zero() f64 {
	return p.color.l
}

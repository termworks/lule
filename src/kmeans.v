module main

import color
import rand
import stbi

// Index of and distance to the closest mean
fn nearest(target color.Lab, means []color.Lab) (int, f64) {
	mut best := 0
	mut best_d := color.delta_e_cie76(target, means[0])
	for i := 1; i < means.len; i++ {
		d := color.delta_e_cie76(target, means[i])
		if d < best_d {
			best_d = d
			best = i
		}
	}
	return best, best_d
}

fn recalculate(pixels []color.Lab, assign []int, cluster int) color.Lab {
	mut w_sum := 0.0
	mut l := 0.0
	mut a := 0.0
	mut b := 0.0
	for i, px in pixels {
		if assign[i] != cluster {
			continue
		}
		w_sum += 1.0
		l += px.l
		a += px.a
		b += px.b
	}
	if w_sum == 0.0 {
		return color.Lab{0.0, 0.0, 0.0, 1.0}
	}
	return color.Lab{l / w_sum, a / w_sum, b / w_sum, 1.0}
}

pub struct Pigment {
pub mut:
	color     color.Lab
	dominance f64
}

// Weighted pick over distance^2, mirroring k-means++ seeding
fn weighted_pick(weights []f64) int {
	mut total := 0.0
	for w in weights {
		total += w
	}
	if total <= 0.0 {
		return -1
	}
	mut target := rand.f64() * total
	for i, w in weights {
		target -= w
		if target <= 0.0 {
			return i
		}
	}
	return weights.len - 1
}

// K-means++ clustering in CIE color.Lab space
pub fn palette_kmeans(pixels []color.Lab, k int, max_iter int) []Pigment {
	tolerance := 1e-4
	if pixels.len == 0 || k < 1 {
		return []Pigment{}
	}

	mut means := [pixels[rand.intn(pixels.len) or { 0 }]]

	for means.len < k {
		mut distances := []f64{len: pixels.len}
		for i, px in pixels {
			_, d := nearest(px, means)
			distances[i] = d * d
		}
		idx := weighted_pick(distances)
		if idx < 0 {
			mut out := []Pigment{}
			for m in means {
				out << Pigment{m, 0.0}
			}
			len := f64(pixels.len)
			for px in pixels {
				near, _ := nearest(px, means)
				out[near].dominance += 1.0 / len
			}
			return out
		}
		means << pixels[idx]
	}

	mut assign := []int{len: pixels.len}
	mut iters_left := max_iter
	for {
		for i, px in pixels {
			near, _ := nearest(px, means)
			assign[i] = near
		}
		mut changed := false
		for i := 0; i < means.len; i++ {
			new_mean := recalculate(pixels, assign, i)
			if color.delta_e_cie76(means[i], new_mean) > tolerance {
				changed = true
			}
			means[i] = new_mean
		}
		iters_left--
		if !changed || iters_left <= 0 {
			break
		}
	}

	mut counts := []int{len: means.len}
	for a in assign {
		counts[a]++
	}
	mut out := []Pigment{}
	for i, m in means {
		out << Pigment{m, f64(counts[i]) / f64(pixels.len)}
	}
	return out
}

// Nearest-neighbour downscale so clustering stays fast on 4K wallpapers
fn sample_pixels(path string, max_dim int) ![]color.Lab {
	img := stbi.load(path, desired_channels: 3)!
	defer {
		unsafe { img.free() }
	}
	src := unsafe { &u8(img.data) }

	mut tw := img.width
	mut th := img.height
	if tw > max_dim || th > max_dim {
		if tw >= th {
			th = int(f64(th) * f64(max_dim) / f64(tw))
			tw = max_dim
		} else {
			tw = int(f64(tw) * f64(max_dim) / f64(th))
			th = max_dim
		}
	}
	if tw < 1 {
		tw = 1
	}
	if th < 1 {
		th = 1
	}

	mut pixels := []color.Lab{cap: tw * th}
	for y := 0; y < th; y++ {
		sy := int(f64(y) * f64(img.height) / f64(th))
		for x := 0; x < tw; x++ {
			sx := int(f64(x) * f64(img.width) / f64(tw))
			o := (sy * img.width + sx) * 3
			unsafe {
				c := color.color_from_rgb(src[o], src[o + 1], src[o + 2])
				pixels << c.to_lab()
			}
		}
	}
	return pixels
}

// Dispatches to whichever extractor was asked for. They all take the same sampled pixels and
// return the same shape, so the rest of the pipeline neither knows nor cares which ran.
pub fn pigments(image_path string, count int, iters int, backend string) ![]Pigment {
	pixels := sample_pixels(image_path, 512)!
	mut output := match backend {
		'median' { palette_median_cut(pixels, count) }
		'histogram' { palette_histogram(pixels, count) }
		'tonal' { palette_tonal(pixels, count) }
		else { palette_kmeans(pixels, count, iters) }
	}

	// tonal is already ordered as a ramp, dark to light; re-sorting it by dominance would shuffle
	// the one backend whose order carries meaning.
	if backend != 'tonal' {
		output.sort(a.dominance > b.dominance)
	}
	return output
}

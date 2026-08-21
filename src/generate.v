module main

import rand

// Mid-lightness colours ordered by chroma, padded with complements
pub fn gen_main_six(col []Color) []Color {
	mut colors := []Color{}
	for c in col {
		l := c.to_lab().l
		if l > 20.0 && l < 80.0 {
			colors << c
		}
	}
	colors.sort(a.to_lch().l > b.to_lch().l)

	mut i := 0
	for colors.len < 6 {
		if colors.len == 0 {
			colors << color_from_rgb(128, 128, 128)
			continue
		}
		colors << colors[i % colors.len].complementary()
		i++
	}

	mut main_colors := []Color{}
	for c in colors[..6] {
		main_colors << c
	}
	main_colors.sort(a.to_lch().c > b.to_lch().c)
	return main_colors
}

pub fn get_black_white(ac Color, black_mix f64, white_mix f64, theme bool) (Color, Color) {
	black := color_from_rgb(0, 0, 0)
	white := color_from_rgb(255, 255, 255)
	dark := black.mix_rgb(ac, black_mix)
	light := white.mix_rgb(ac, white_mix)
	if theme {
		return dark, light
	}
	return light, dark
}

pub fn get_two_grays(ac Color, mix f64, theme bool) (Color, Color) {
	darker := color_from_rgb(100, 100, 100)
	lighter := color_from_rgb(170, 170, 170)
	dark := darker.mix_rgb(ac, mix)
	light := lighter.mix_rgb(ac, mix)
	if theme {
		return dark, light
	}
	return light, dark
}

pub fn gen_prime_six(colors []Color, mix f64, theme bool) []Color {
	mut out := []Color{}
	for col in colors {
		out << if theme { col.lighten(mix) } else { col.darken(mix) }
	}
	return out
}

pub fn gen_second_six(colors []Color, mix f64, theme bool) []Color {
	mut out := []Color{}
	for col in colors {
		out << if !theme { col.lighten(mix) } else { col.darken(mix) }
	}
	return out
}

// Sample a Lab gradient through the stops, dropping both endpoints
pub fn gen_shades(colors []Color, number int) []Color {
	mut gradients := []Color{}
	if colors.len < 2 {
		return gradients
	}
	count := number + 2
	for i := 0; i < count; i++ {
		if i == 0 || i == count - 1 {
			continue
		}
		position := f64(i) / f64(count - 1)
		gradients << sample_scale(colors, position)
	}
	return gradients
}

fn sample_scale(stops []Color, position f64) Color {
	if position <= 0.0 {
		return stops[0]
	}
	if position >= 1.0 {
		return stops[stops.len - 1]
	}
	segments := stops.len - 1
	scaled := position * f64(segments)
	mut idx := int(scaled)
	if idx >= segments {
		idx = segments - 1
	}
	local := scaled - f64(idx)
	return stops[idx].mix_lab(stops[idx + 1], local)
}

pub fn gen_gradients(ac Color, col0 Color, col15 Color, black Color, white Color) []Color {
	mut gradients := []Color{}
	gradients << black
	gradients << gen_shades([black, col0], 3)
	gradients << gen_shades([col0, ac, col15], 16)
	gradients << gen_shades([col15, white], 3)
	gradients << white
	return gradients
}

pub fn generate_defined_colors(theme bool) []Color {
	base_colors := [
		color_from_rgb(228, 228, 228),
		color_from_rgb(148, 148, 148),
		color_from_rgb(198, 198, 132),
		color_from_rgb(227, 199, 138),
		color_from_rgb(238, 239, 159),
		color_from_rgb(222, 147, 95),
		color_from_rgb(240, 143, 133),
		color_from_rgb(225, 150, 162),
		color_from_rgb(255, 203, 251),
		color_from_rgb(133, 220, 130),
		color_from_rgb(136, 196, 95),
		color_from_rgb(54, 198, 146),
		color_from_rgb(126, 218, 200),
		color_from_rgb(128, 160, 255),
		color_from_rgb(138, 175, 255),
		color_from_rgb(116, 178, 255),
		color_from_rgb(173, 205, 243),
		color_from_rgb(174, 129, 255),
		color_from_rgb(207, 135, 238),
		color_from_rgb(230, 94, 114),
		color_from_rgb(255, 81, 137),
		color_from_rgb(255, 84, 84),
		color_from_rgb(244, 175, 111),
		color_from_rgb(205, 172, 252),
	]
	mut colors := []Color{}
	for color in base_colors {
		colors << if theme { color } else { color.darken(0.3) }
	}
	return colors
}

// Seeds the generator, or leaves it alone when no seed was asked for. The second word is the
// first mixed with the golden-ratio constant: the generator wants two, and handing it a zero
// alongside a small seed makes neighbouring seeds produce visibly related streams.
pub fn seed_rand(seed int) {
	if seed == 0 {
		return
	}
	lo := u32(seed)
	rand.seed([lo, lo ^ u32(0x9e3779b9)])
}

// Reorders the extracted pigments. Which pigment ends up first decides the accent, and through
// it the two greys and both ends of the ramp, so this is the cheapest knob with a visible effect.
pub fn sort_palette(mut palette []Color, mode string) {
	match mode {
		'hue' { palette.sort(a.to_lch().h < b.to_lch().h) }
		'light' { palette.sort(a.to_lab().l < b.to_lab().l) }
		'dark' { palette.sort(a.to_lab().l > b.to_lab().l) }
		'chroma' { palette.sort(a.to_lch().c > b.to_lch().c) }
		else {} // '' and 'none' keep k-means' own order, which is by dominance
	}
}

// Applied to the pigments rather than to the finished 256, so the scheme stays internally
// consistent: the background is still derived from the accent, the ramp still runs dark to light,
// and nothing has to be clamped back into place afterwards.
pub fn adjust_palette(palette []Color, scheme &Scheme) []Color {
	mut out := []Color{}
	for c in palette {
		hsl := c.to_hsl()
		mut h := hsl.h
		mut s := hsl.s
		mut l := hsl.l
		if scheme.hue != 0.0 {
			h += scheme.hue
		}
		// A multiplier, so 0 leaves the colour alone and -1 takes it to grey.
		if scheme.saturation != 0.0 {
			s = clamp01(s * (1.0 + scheme.saturation))
		}
		if scheme.illumination != 0.0 {
			l = clamp01(l + scheme.illumination)
		}
		out << color_from_hsl(h, s, l)
	}

	// Pulling every pigment toward the first one trades variety for cohesion.
	if scheme.blend > 0.0 && out.len > 1 {
		anchor := out[0]
		for i := 1; i < out.len; i++ {
			out[i] = out[i].mix_lab(anchor, clamp01(scheme.blend))
		}
	}
	return out
}

pub fn get_all_colors(mut scheme Scheme) []Color {
	theme := scheme.is_dark()

	seed_rand(scheme.seed)

	mut palette := []Color{}
	for c in scheme.pigments {
		palette << color_from_hex(c)
	}

	// Both applied to the chosen six, not to the pigments going in.
	//
	// gen_main_six filters to mid lightness and then re-sorts by chroma, so tuning the input made
	// both knobs behave chaotically: raising --illumination pushed pigments past the lightness cut
	// and changed *which* colours were picked, and a --sort on the way in was overwritten by the
	// internal sort on the way out. Measured, --illumination=0.3 came out darker than no flag at
	// all. Adjusting after selection keeps the choice fixed and the knobs monotonic.
	mut main_six := gen_main_six(palette)
	sort_palette(mut main_six, scheme.sort)
	main_six = adjust_palette(main_six, scheme)

	mut black := color_from_rgb(0, 0, 0)
	mut white := color_from_rgb(255, 255, 255)
	if !theme {
		white = color_from_rgb(0, 0, 0)
		black = color_from_rgb(255, 255, 255)
	}

	prime := gen_prime_six(main_six, 0.1, theme)
	acc := prime[0]

	col0, col15 := get_black_white(acc, 0.08, 0.12, theme)
	col7, col8 := get_two_grays(acc, 0.2, theme)

	second := gen_second_six(main_six, 0.1, theme)
	gradients := gen_gradients(acc, col0, col15, black, white)

	mut colors := []Color{}
	colors << col0
	colors << prime
	colors << col7
	colors << col8
	colors << second
	colors << col15

	colors << generate_defined_colors(theme)

	for _ in 0 .. 10 {
		hue := rand.f64() * 360.0
		saturation := 0.2 + 0.6 * rand.f64()
		lightness := 0.3 + 0.4 * rand.f64()
		colors << gen_shades([col0, color_from_hsl(hue, saturation, lightness), col15], 12)
	}

	if scheme.norandom {
		for _ in 0 .. 6 {
			hue := rand.f64() * 360.0
			saturation := 0.2 + 0.6 * rand.f64()
			lightness := 0.3 + 0.4 * rand.f64()
			colors << gen_shades([col0, color_from_hsl(hue, saturation, lightness), col15], 12)
		}
	} else {
		lightish := gradients[2]
		darkish := gradients[21]
		colors << gen_shades([lightish, color_from_rgb(255, 0, 0), darkish], 24)
		colors << gen_shades([lightish, color_from_rgb(0, 255, 0), darkish], 24)
		colors << gen_shades([lightish, color_from_rgb(0, 0, 255), darkish], 24)
	}

	colors << gradients
	return colors
}

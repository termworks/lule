module main

import rand
import math

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

// Pushes apart any colours that are too close to tell from one another.
//
// A near-monochrome wallpaper collapses: the six chosen colours come out as light greys, the
// theme lightening on top clips them all to #ffffff, and ANSI 1-6 end up identical — six terminal
// colours that cannot be distinguished. Measured on a real wallpaper, colours 1 through 6 were
// all #ffffff.
//
// Where there is chroma to work with the hue is rotated, which keeps lightness intact; on a grey
// there is no hue to rotate, so lightness steps instead, away from whichever end it is near.
fn too_close(candidate Color, others []Color, min_delta f64) bool {
	for other in others {
		if delta_e_cie76(candidate.to_lab(), other.to_lab()) < min_delta {
			return true
		}
	}
	return false
}

pub fn ensure_distinct(colors []Color, min_delta f64) []Color {
	mut out := []Color{}
	for c in colors {
		mut candidate := c
		base := c.to_hsl()
		// Each attempt is measured from the original colour rather than from the previous try,
		// and lightness wraps within a band instead of clamping. Stepping from the previous try
		// and clamping parked every further attempt on the same endpoint, which left three greys
		// identical at #757575 on a monochrome wallpaper.
		for attempt := 1; attempt <= 24; attempt++ {
			if !too_close(candidate, out, min_delta) {
				break
			}
			if base.s > 0.15 {
				// 47° does not divide 360, so repeated steps keep landing somewhere new instead
				// of cycling through the same handful of hues.
				candidate = color_from_hsl(base.h + 47.0 * f64(attempt), base.s, base.l)
			} else {
				// 0.06..0.94, so a spread grey never becomes pure black or pure white — those
				// are the background and foreground, and colliding with them is the same bug.
				lightness := 0.06 + math.fmod(base.l + 0.11 * f64(attempt), 0.88)
				candidate = color_from_hsl(base.h, base.s, lightness)
			}
		}

		// Iterating can still fail to converge: two greys starting at the same lightness walk the
		// same sequence of slots and keep colliding with each other. Falling back to a slot chosen
		// by position is what makes distinctness a guarantee rather than a likelihood.
		if too_close(candidate, out, min_delta) {
			span := if colors.len > 1 { f64(colors.len - 1) } else { 1.0 }
			candidate = color_from_hsl(base.h, base.s, 0.12 + 0.76 * (f64(out.len) / span))
		}
		out << candidate
	}
	return out
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

	// Spread after the theme lightening, because that is where the collapse happens: lightening
	// six pale greys clips every one of them to white.
	prime := ensure_distinct(gen_prime_six(main_six, 0.1, theme), 10.0)
	acc := prime[0]

	col0, col15 := get_black_white(acc, 0.08, 0.12, theme)
	col7, col8 := get_two_grays(acc, 0.2, theme)

	second := ensure_distinct(gen_second_six(main_six, 0.1, theme), 10.0)
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

	// Last, on the finished palette, because the threshold is measured against colour 0 and
	// colour 0 is not decided until everything above has run.
	return enforce_contrast(colors, resolve_contrast(scheme.contrast))
}

// The WCAG AA threshold for body text. Terminal colours are body text.
pub const contrast_aa = 4.5
pub const contrast_aaa = 7.0

// Reads `--contrast`. Zero means the flag was never given, so the default applies; a negative
// value is the explicit "leave my colours alone".
pub fn resolve_contrast(setting f64) f64 {
	if setting < 0.0 {
		return 0.0
	}
	if setting == 0.0 {
		return contrast_aa
	}
	return setting
}

// Moves one colour away from the background until it is readable against it.
//
// Hue and saturation are kept; only lightness moves, and only as far as it has to. Relative
// luminance rises monotonically with HSL lightness, so a binary search finds the smallest change
// that clears the threshold rather than overshooting to white.
//
// The direction is whichever side of the background the colour is already on, so a dark colour on
// a light background gets darker rather than being flipped to the other end.
pub fn raise_contrast(c Color, background Color, min_ratio f64) Color {
	// Measured on the colour as it will be written, not as it is held.
	//
	// Searching against the f64 colour converged on exactly the threshold, and rounding to eight
	// bits then dropped it back under: colours came out at 4.48, 4.49 and 4.50 against a 4.5
	// target. Quantising inside the test makes the guarantee true of the hex in the file.
	bg := background.quantised()
	ratio := fn [bg] (candidate Color) f64 {
		return contrast_ratio(candidate.quantised(), bg)
	}

	if ratio(c) >= min_ratio {
		return c
	}
	hsl := c.to_hsl()

	// Preferred direction is whichever side of the background the colour is already on, so a dark
	// colour on a light background gets darker rather than being flipped.
	//
	// But the preferred direction is not always the possible one: a colour a shade lighter than a
	// near-white background can never reach the threshold by getting lighter, however far it
	// goes. When it cannot, the other direction is tried before giving up.
	preferred := if c.relative_luminance() >= bg.relative_luminance() { 1.0 } else { 0.0 }
	opposite := 1.0 - preferred

	mut limit := preferred
	if ratio(color_from_hsl(hsl.h, hsl.s, preferred)) < min_ratio {
		if ratio(color_from_hsl(hsl.h, hsl.s, opposite)) >= min_ratio {
			limit = opposite
		} else {
			// Neither end reaches it - against a mid grey, nothing reaches AAA. Take whichever
			// extreme is the most readable this hue can manage.
			toward_preferred := ratio(color_from_hsl(hsl.h, hsl.s, preferred))
			toward_opposite := ratio(color_from_hsl(hsl.h, hsl.s, opposite))
			best := if toward_preferred >= toward_opposite { preferred } else { opposite }
			return color_from_hsl(hsl.h, hsl.s, best)
		}
	}

	mut near := hsl.l
	mut far := limit
	for _ in 0 .. 24 {
		mid := (near + far) / 2.0
		if ratio(color_from_hsl(hsl.h, hsl.s, mid)) >= min_ratio {
			far = mid
		} else {
			near = mid
		}
	}
	return color_from_hsl(hsl.h, hsl.s, far)
}

// The sixteen ANSI slots are what a terminal actually draws text in, so those are the ones held
// to the threshold. Slot 0 is the background they are measured against, and the ramps past 15 are
// gradients rather than text colours.
pub fn enforce_contrast(colors []Color, min_ratio f64) []Color {
	if min_ratio <= 0.0 || colors.len < 16 {
		return colors
	}
	mut out := colors.clone()
	background := out[0]
	for i in 1 .. 16 {
		out[i] = raise_contrast(out[i], background, min_ratio)
	}

	// Readability and distinctness pull against each other: on a monochrome wallpaper the six
	// spread-apart greys all get dragged to whatever lightness clears the threshold and collapse
	// back into one another. Six identical readable colours is the bug ensure_distinct exists to
	// prevent, reappearing one step later.
	//
	// Separated within the two groups of six the terminal actually uses as colours - normal
	// 1..6 and bright 9..14 - rather than across all fifteen. Fifteen colours each 10 ΔE apart
	// need 150 units of lightness, and clearing a contrast floor leaves nowhere near that much:
	// asking for it squeezed the groups back down to four distinct colours.
	for group in [[1, 2, 3, 4, 5, 6], [9, 10, 11, 12, 13, 14]] {
		separate_group(mut out, group, background, min_ratio)
	}
	return out
}

fn separate_group(mut out []Color, group []int, background Color, min_ratio f64) {
	mut placed := []Color{}
	for index in group {
		mut c := out[index]
		if too_close(c, placed, 10.0) {
			hsl := c.to_hsl()
			// Away from the background, never back toward it: moving away raises contrast, so
			// the threshold cannot be lost while the colours are being separated.
			away := if c.relative_luminance() >= background.relative_luminance() {
				1.0
			} else {
				0.0
			}
			// Ten is comfortable, but on a near-monochrome palette there is not room for six of
			// them above the contrast floor. Settling for less separation beats leaving two
			// colours identical.
			for target in [10.0, 6.0, 3.0, 1.5] {
				mut found := false
				for step in 1 .. 33 {
					lightness := hsl.l + (away - hsl.l) * (f64(step) / 33.0)
					candidate := color_from_hsl(hsl.h, hsl.s, lightness)
					if !too_close(candidate, placed, target)
						&& contrast_ratio(candidate.quantised(), background.quantised()) >= min_ratio {
						c = candidate
						found = true
						break
					}
				}
				if found {
					break
				}
			}
		}
		out[index] = c
		placed << c
	}
}

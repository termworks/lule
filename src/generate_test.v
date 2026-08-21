module main

import palette
import color

fn sample_pigments() []string {
	return ['#3f51b5', '#e91e63', '#4caf50', '#ff9800', '#9c27b0', '#00bcd4', '#795548', '#607d8b']
}

fn test_main_six_from_various_palette_sizes() {
	for size in [0, 1, 2, 5, 6, 8] {
		mut swatches := []color.Color{}
		for i in 0 .. size {
			swatches << color.color_from_rgb(u8(30 + i * 20), u8(90 + i * 10), u8(150 - i * 10))
		}
		assert gen_main_six(swatches).len == 6, 'palette of ${size} did not yield six'
	}
}

fn test_main_six_drops_extremes() {
	// Near-black and near-white are filtered before ranking; without that the accent colour ends
	// up being the background.
	swatches := [
		color.color_from_rgb(2, 2, 2),
		color.color_from_rgb(253, 253, 253),
		color.color_from_rgb(63, 81, 181),
		color.color_from_rgb(233, 30, 99),
	]
	six := gen_main_six(swatches)
	assert six.len == 6
	for c in six {
		l := c.to_lab().l
		assert l > 0.0 && l < 100.0
	}
}

fn test_gen_shades_count_and_endpoints() {
	black := color.color_from_rgb(0, 0, 0)
	white := color.color_from_rgb(255, 255, 255)
	for n in [1, 3, 12, 24] {
		shades := gen_shades([black, white], n)
		assert shades.len == n, 'asked for ${n}, got ${shades.len}'
		// Both endpoints are dropped, so no shade may equal them.
		assert shades[0].to_hex(true) != '#000000'
		assert shades[shades.len - 1].to_hex(true) != '#ffffff'
	}
}

fn test_gen_shades_is_monotonic_in_lightness() {
	shades := gen_shades([color.color_from_rgb(0, 0, 0), color.color_from_rgb(255, 255, 255)], 12)
	for i in 1 .. shades.len {
		assert shades[i].to_lab().l > shades[i - 1].to_lab().l
	}
}

fn test_gen_shades_needs_two_stops() {
	assert gen_shades([], 5).len == 0
	assert gen_shades([color.color_from_rgb(1, 2, 3)], 5).len == 0
}

fn test_full_palette_is_exactly_256() {
	// Every consumer indexes this by fixed position — colors[0], colors[1], colors[15] — and the
	// ANSI display walks 0..256. A pipeline that returns 255 breaks all of them.
	for theme in ['dark', 'light'] {
		for norandom in [true, false] {
			mut scheme := Scheme{
				theme:    theme
				pigments: sample_pigments()
				norandom: norandom
			}
			colors := get_all_colors(mut scheme)
			assert colors.len == 256, '${theme}/${norandom} produced ${colors.len}'
		}
	}
}

fn test_dark_and_light_differ_at_the_ends() {
	mut dark := Scheme{
		theme:    'dark'
		pigments: sample_pigments()
	}
	mut light := Scheme{
		theme:    'light'
		pigments: sample_pigments()
	}
	d := get_all_colors(mut dark)
	l := get_all_colors(mut light)
	// Background is dark on the dark theme and light on the light one; that inversion is the
	// whole point of the flag.
	assert d[0].to_lab().l < 50.0
	assert l[0].to_lab().l > 50.0
}

fn test_scheme_json_roundtrip() {
	original := Scheme{
		image:    '/w/a.png'
		theme:    'light'
		pigments: ['#111111', '#222222']
		walldir:  '/w'
		scripts:  ['/s.sh']
		patterns: [Pattern{'/in', '/out'}]
		looop:    42
		palette:  'pigment'
		norandom: true
	}
	back := scheme_from_json(original.to_json()) or {
		assert false, 'scheme did not round-trip: ${err}'
		return
	}
	assert back.image == original.image
	assert back.theme == original.theme
	assert back.pigments == original.pigments
	assert back.walldir == original.walldir
	assert back.scripts == original.scripts
	assert back.looop == original.looop
	assert back.norandom == original.norandom
	assert back.patterns.len == 1
	assert back.patterns[0].from == '/in'
}

fn test_scheme_rejects_rubbish() {
	if _ := scheme_from_json('not json at all') {
		assert false, 'accepted non-json'
	}
}

fn test_modi_only_overlays_what_is_set() {
	mut base := Scheme{
		image:   '/keep.png'
		theme:   'dark'
		walldir: '/w'
		looop:   300
	}
	// An empty incoming field means "not specified" and must not wipe the existing value.
	base.modi(Scheme{ theme: 'light' })
	assert base.theme == 'light'
	assert base.image == '/keep.png'
	assert base.walldir == '/w'
	assert base.looop == 300
}

fn test_is_dark_defaults_to_dark() {
	assert Scheme{}.is_dark()
	assert Scheme{
		theme: 'dark'
	}.is_dark()
	assert !Scheme{
		theme: 'light'
	}.is_dark()
}

fn test_kmeans_finds_planted_clusters() {
	// Three tight, well-separated blobs. Whatever the seeding picks, the means have to land on
	// them and the dominances have to account for every pixel.
	centres := [
		color.color_from_rgb(220, 20, 20),
		color.color_from_rgb(20, 220, 20),
		color.color_from_rgb(20, 20, 220),
	]
	mut pixels := []color.Lab{}
	for c in centres {
		r, g, b := c.rgb_u8()
		for i in 0 .. 60 {
			jitter := u8(i % 3)
			pixels << color.color_from_rgb(r + jitter, g + jitter, b + jitter).to_lab()
		}
	}

	found := palette.palette_kmeans(pixels, 3, 100)
	assert found.len == 3

	mut total := 0.0
	for p in found {
		total += p.dominance
	}
	assert total > 0.99 && total < 1.01, 'dominance summed to ${total}'

	// Every planted centre is matched by some mean.
	for c in centres {
		mut best := 1.0e9
		for p in found {
			d := color.delta_e_cie76(c.to_lab(), p.color)
			if d < best {
				best = d
			}
		}
		assert best < 5.0, 'no mean near ${c.to_hex(true)}, closest was ${best}'
	}
}

fn test_kmeans_handles_no_pixels() {
	assert palette.palette_kmeans([], 8, 10).len == 0
}

fn test_kmeans_with_a_single_flat_colour() {
	// A solid-colour wallpaper has fewer distinct colours than k. It must still return, and the
	// dominances must still be a distribution rather than NaN.
	mut pixels := []color.Lab{}
	for _ in 0 .. 50 {
		pixels << color.color_from_rgb(100, 100, 100).to_lab()
	}
	found := palette.palette_kmeans(pixels, 16, 50)
	assert found.len > 0
	mut total := 0.0
	for p in found {
		assert !p.dominance.str().contains('nan')
		total += p.dominance
	}
	assert total > 0.99 && total < 1.01
}

fn vivid() []color.Color {
	return [
		color.color_from_rgb(200, 40, 40),
		color.color_from_rgb(40, 200, 40),
		color.color_from_rgb(40, 40, 200),
		color.color_from_rgb(200, 200, 40),
	]
}

fn mean_chroma(colors []color.Color) f64 {
	mut total := 0.0
	for c in colors {
		total += c.to_lch().c
	}
	return total / f64(colors.len)
}

fn mean_lightness(colors []color.Color) f64 {
	mut total := 0.0
	for c in colors {
		total += c.to_lab().l
	}
	return total / f64(colors.len)
}

// Deliberately short of full saturation, so raising it has somewhere to go. vivid() is already
// at s=1.0 in HSL, where every positive adjustment clamps to the same place.
fn muted() []color.Color {
	return [
		color.color_from_rgb(160, 110, 110),
		color.color_from_rgb(110, 160, 110),
		color.color_from_rgb(110, 110, 160),
		color.color_from_rgb(160, 160, 110),
	]
}

fn test_saturation_is_monotonic_and_bottoms_out_at_grey() {
	mut previous := -1.0
	for s in [-1.0, -0.5, 0.0, 0.5, 1.0] {
		adjusted := adjust_palette(muted(), &Scheme{
			saturation: s
		})
		chroma := mean_chroma(adjusted)
		assert chroma > previous, 'saturation ${s} did not increase chroma'
		previous = chroma
	}
	// -1.0 is fully grey, which means r == g == b for every colour.
	for c in adjust_palette(vivid(), &Scheme{
		saturation: -1.0
	}) {
		r, g, b := c.rgb_u8()
		assert r == g && g == b, '${c.to_hex(true)} is not grey'
	}
}

fn test_illumination_is_monotonic() {
	mut previous := -1.0
	for i in [-0.3, -0.15, 0.0, 0.15, 0.3] {
		adjusted := adjust_palette(vivid(), &Scheme{
			illumination: i
		})
		light := mean_lightness(adjusted)
		assert light > previous, 'illumination ${i} did not increase lightness'
		previous = light
	}
}

fn test_hue_rotation_wraps_and_returns() {
	// A full turn is the identity, and a half turn is not.
	original := vivid()
	full := adjust_palette(original, &Scheme{
		hue: 360.0
	})
	half := adjust_palette(original, &Scheme{
		hue: 180.0
	})
	for i in 0 .. original.len {
		assert full[i].to_hex(true) == original[i].to_hex(true)
		assert half[i].to_hex(true) != original[i].to_hex(true)
	}
}

fn test_blend_pulls_everything_toward_the_first() {
	original := vivid()
	// Fully blended, every colour but the anchor has collapsed onto it.
	blended := adjust_palette(original, &Scheme{
		blend: 1.0
	})
	for c in blended {
		assert color.delta_e_cie76(c.to_lab(), original[0].to_lab()) < 1.0
	}
	// Unblended leaves them where they were.
	assert adjust_palette(original, &Scheme{
		blend: 0.0
	})[2].to_hex(true) == original[2].to_hex(true)
}

fn test_no_tuning_is_the_identity() {
	original := vivid()
	for i, c in adjust_palette(original, &Scheme{}) {
		assert c.to_hex(true) == original[i].to_hex(true)
	}
}

fn test_sort_palette_orders_as_named() {
	mut light := vivid()
	sort_palette(mut light, 'light')
	for i in 1 .. light.len {
		assert light[i].to_lab().l >= light[i - 1].to_lab().l
	}

	mut dark := vivid()
	sort_palette(mut dark, 'dark')
	for i in 1 .. dark.len {
		assert dark[i].to_lab().l <= dark[i - 1].to_lab().l
	}

	mut hue := vivid()
	sort_palette(mut hue, 'hue')
	for i in 1 .. hue.len {
		assert hue[i].to_lch().h >= hue[i - 1].to_lch().h
	}

	// An unknown mode leaves the order alone rather than throwing it away.
	mut untouched := vivid()
	sort_palette(mut untouched, 'nonsense')
	for i, c in untouched {
		assert c.to_hex(true) == vivid()[i].to_hex(true)
	}
}

fn test_seed_makes_generation_reproducible() {
	mut a := Scheme{
		pigments: sample_pigments()
		seed:     4242
	}
	mut b := Scheme{
		pigments: sample_pigments()
		seed:     4242
	}
	mut c := Scheme{
		pigments: sample_pigments()
		seed:     9999
	}
	first := get_all_colors(mut a)
	second := get_all_colors(mut b)
	third := get_all_colors(mut c)

	for i in 0 .. first.len {
		assert first[i].to_hex(true) == second[i].to_hex(true), 'seeded runs diverged at ${i}'
	}
	// A different seed has to actually change the randomised ramps.
	mut differences := 0
	for i in 0 .. first.len {
		if first[i].to_hex(true) != third[i].to_hex(true) {
			differences++
		}
	}
	assert differences > 0, 'a different seed produced an identical scheme'
}

fn test_saturation_clamps_rather_than_overflowing() {
	// vivid() is already fully saturated, so pushing further must leave it where it is instead
	// of wrapping round into a different hue.
	at_max := adjust_palette(vivid(), &Scheme{
		saturation: 0.5
	})
	way_past := adjust_palette(vivid(), &Scheme{
		saturation: 50.0
	})
	for i in 0 .. at_max.len {
		assert at_max[i].to_hex(true) == way_past[i].to_hex(true)
	}
}

fn test_illumination_clamps_at_both_ends() {
	white := adjust_palette(vivid(), &Scheme{
		illumination: 5.0
	})
	black := adjust_palette(vivid(), &Scheme{
		illumination: -5.0
	})
	for c in white {
		assert c.to_hex(true) == '#ffffff'
	}
	for c in black {
		assert c.to_hex(true) == '#000000'
	}
}

fn test_ensure_distinct_separates_identical_colours() {
	// Six copies of one grey is the monochrome-wallpaper case that produced six identical ANSI
	// colours. Every one of them has to come out telling apart from the others.
	same := []color.Color{len: 6, init: color.color_from_rgb(200, 200, 200)}
	spread := ensure_distinct(same, 10.0)
	assert spread.len == 6
	for i in 0 .. spread.len {
		for j in i + 1 .. spread.len {
			d := color.delta_e_cie76(spread[i].to_lab(), spread[j].to_lab())
			assert d >= 10.0, 'colours ${i} and ${j} are only ${d} apart'
		}
	}
}

fn test_ensure_distinct_separates_identical_saturated_colours() {
	same := []color.Color{len: 6, init: color.color_from_rgb(200, 40, 40)}
	spread := ensure_distinct(same, 10.0)
	for i in 0 .. spread.len {
		for j in i + 1 .. spread.len {
			assert color.delta_e_cie76(spread[i].to_lab(), spread[j].to_lab()) >= 10.0
		}
	}
}

fn test_ensure_distinct_leaves_distinct_colours_alone() {
	// Already-separated colours must survive untouched; the spreading is a repair, not a filter.
	original := vivid()
	for i, c in ensure_distinct(original, 10.0) {
		assert c.to_hex(true) == original[i].to_hex(true)
	}
}

fn test_ensure_distinct_avoids_the_extremes() {
	// Pure black and pure white are the background and foreground; a spread colour landing on
	// either is the same collision in a different place.
	for base in [color.color_from_rgb(250, 250, 250), color.color_from_rgb(5, 5, 5)] {
		for c in ensure_distinct([]color.Color{len: 6, init: base}, 10.0) {
			hex := c.to_hex(true)
			assert hex != '#000000' && hex != '#ffffff', 'spread onto ${hex}'
		}
	}
}

fn test_generated_scheme_has_sixteen_usable_colours() {
	// Monochrome pigments end to end: the scheme still has to offer sixteen colours a terminal
	// can tell apart.
	mut scheme := Scheme{
		theme:    'dark'
		pigments: ['#c8c8c8', '#c8c8c8', '#c8c8c8', '#c8c8c8', '#cacaca', '#c9c9c9']
	}
	colors := get_all_colors(mut scheme)
	mut seen := map[string]bool{}
	for c in colors[1..7] {
		seen[c.to_hex(true)] = true
	}
	assert seen.len == 6, 'only ${seen.len} distinct colours in 1..6'
}

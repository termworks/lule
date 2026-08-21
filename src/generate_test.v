module main

fn sample_pigments() []string {
	return ['#3f51b5', '#e91e63', '#4caf50', '#ff9800', '#9c27b0', '#00bcd4', '#795548', '#607d8b']
}

fn test_main_six_from_various_palette_sizes() {
	for size in [0, 1, 2, 5, 6, 8] {
		mut palette := []Color{}
		for i in 0 .. size {
			palette << color_from_rgb(u8(30 + i * 20), u8(90 + i * 10), u8(150 - i * 10))
		}
		assert gen_main_six(palette).len == 6, 'palette of ${size} did not yield six'
	}
}

fn test_main_six_drops_extremes() {
	// Near-black and near-white are filtered before ranking; without that the accent colour ends
	// up being the background.
	palette := [
		color_from_rgb(2, 2, 2),
		color_from_rgb(253, 253, 253),
		color_from_rgb(63, 81, 181),
		color_from_rgb(233, 30, 99),
	]
	six := gen_main_six(palette)
	assert six.len == 6
	for c in six {
		l := c.to_lab().l
		assert l > 0.0 && l < 100.0
	}
}

fn test_gen_shades_count_and_endpoints() {
	black := color_from_rgb(0, 0, 0)
	white := color_from_rgb(255, 255, 255)
	for n in [1, 3, 12, 24] {
		shades := gen_shades([black, white], n)
		assert shades.len == n, 'asked for ${n}, got ${shades.len}'
		// Both endpoints are dropped, so no shade may equal them.
		assert shades[0].to_hex(true) != '#000000'
		assert shades[shades.len - 1].to_hex(true) != '#ffffff'
	}
}

fn test_gen_shades_is_monotonic_in_lightness() {
	shades := gen_shades([color_from_rgb(0, 0, 0), color_from_rgb(255, 255, 255)], 12)
	for i in 1 .. shades.len {
		assert shades[i].to_lab().l > shades[i - 1].to_lab().l
	}
}

fn test_gen_shades_needs_two_stops() {
	assert gen_shades([], 5).len == 0
	assert gen_shades([color_from_rgb(1, 2, 3)], 5).len == 0
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
		color_from_rgb(220, 20, 20),
		color_from_rgb(20, 220, 20),
		color_from_rgb(20, 20, 220),
	]
	mut pixels := []Lab{}
	for c in centres {
		r, g, b := c.rgb_u8()
		for i in 0 .. 60 {
			jitter := u8(i % 3)
			pixels << color_from_rgb(r + jitter, g + jitter, b + jitter).to_lab()
		}
	}

	found := palette_kmeans(pixels, 3, 100)
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
			d := delta_e_cie76(c.to_lab(), p.color)
			if d < best {
				best = d
			}
		}
		assert best < 5.0, 'no mean near ${c.to_hex(true)}, closest was ${best}'
	}
}

fn test_kmeans_handles_no_pixels() {
	assert palette_kmeans([], 8, 10).len == 0
}

fn test_kmeans_with_a_single_flat_colour() {
	// A solid-colour wallpaper has fewer distinct colours than k. It must still return, and the
	// dominances must still be a distribution rather than NaN.
	mut pixels := []Lab{}
	for _ in 0 .. 50 {
		pixels << color_from_rgb(100, 100, 100).to_lab()
	}
	found := palette_kmeans(pixels, 16, 50)
	assert found.len > 0
	mut total := 0.0
	for p in found {
		assert !p.dominance.str().contains('nan')
		total += p.dominance
	}
	assert total > 0.99 && total < 1.01
}

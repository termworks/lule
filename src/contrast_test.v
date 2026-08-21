module main

import math

fn close(a f64, b f64, tolerance f64) bool {
	return math.abs(a - b) <= tolerance
}

fn sample_pigments() []string {
	return ['#3f51b5', '#e91e63', '#4caf50', '#ff9800', '#9c27b0', '#00bcd4', '#795548', '#607d8b']
}

fn test_relative_luminance_endpoints() {
	assert close(color_from_rgb(255, 255, 255).relative_luminance(), 1.0, 1e-6)
	assert close(color_from_rgb(0, 0, 0).relative_luminance(), 0.0, 1e-6)
}

fn test_contrast_ratio_known_values() {
	black := color_from_rgb(0, 0, 0)
	white := color_from_rgb(255, 255, 255)
	// The two ends of the WCAG scale.
	assert close(contrast_ratio(black, white), 21.0, 0.01)
	assert close(contrast_ratio(white, black), 21.0, 0.01)
	assert close(contrast_ratio(white, white), 1.0, 1e-9)
	// Symmetric, whichever way round it is asked.
	a := color_from_hex('#3f51b5')
	b := color_from_hex('#101820')
	assert close(contrast_ratio(a, b), contrast_ratio(b, a), 1e-9)
}

fn test_resolve_contrast_reads_the_setting() {
	assert resolve_contrast(0.0) == contrast_aa // unset means the default
	assert resolve_contrast(contrast_aaa) == contrast_aaa
	assert resolve_contrast(3.0) == 3.0
	assert resolve_contrast(-1.0) == 0.0 // negative is the explicit off
}

fn test_raise_contrast_reaches_the_threshold() {
	background := color_from_hex('#101820')
	for hex in ['#1a2430', '#22303f', '#2b2b2b', '#3f51b5', '#101821'] {
		raised := raise_contrast(color_from_hex(hex), background, contrast_aa)
		got := contrast_ratio(raised.quantised(), background.quantised())
		assert got >= contrast_aa, '${hex} only reached ${got}'
	}
}

fn test_the_guarantee_holds_after_rounding_to_hex() {
	// Searching against the f64 colour converged on exactly the threshold and rounding to eight
	// bits dropped it back under - colours came out at 4.48 and 4.49 against a 4.5 target. The
	// check has to be on the value that gets written.
	background := color_from_hex('#141414')
	for hex in ['#2a2a2a', '#333333', '#404040', '#1f2a1f', '#2b1f2b'] {
		raised := raise_contrast(color_from_hex(hex), background, contrast_aa)
		// Round-trip through hex, exactly as the cache file does.
		written := color_from_hex(raised.to_hex(true))
		assert contrast_ratio(written, background) >= contrast_aa, '${hex} failed after rounding'
	}
}

fn test_raise_contrast_leaves_a_readable_colour_alone() {
	background := color_from_hex('#101820')
	already := color_from_hex('#ffffff')
	assert raise_contrast(already, background, contrast_aa).to_hex(true) == '#ffffff'
}

fn test_raise_contrast_keeps_the_hue() {
	// Only lightness moves. A colour that changes hue to become readable is a different colour.
	background := color_from_hex('#101820')
	original := color_from_hex('#1b2f1b')
	raised := raise_contrast(original, background, contrast_aa)
	assert close(raised.to_hsl().h, original.to_hsl().h, 1.0)
}

fn test_raise_contrast_moves_away_from_the_background() {
	// On a light background a dark colour gets darker, not flipped to the other end.
	light := color_from_rgb(250, 250, 250)
	dark := color_from_hex('#9a9a9a')
	raised := raise_contrast(dark, light, contrast_aa)
	assert raised.relative_luminance() < dark.relative_luminance()

	night := color_from_rgb(5, 5, 5)
	dim := color_from_hex('#2a2a2a')
	lifted := raise_contrast(dim, night, contrast_aa)
	assert lifted.relative_luminance() > dim.relative_luminance()
}

fn test_an_impossible_threshold_gives_the_most_readable_it_can() {
	// Nothing reaches AAA against a mid grey: white is only 3.9 away and black only 5.3. The
	// answer is the more readable extreme, not a crash and not the colour unchanged.
	grey := color_from_rgb(128, 128, 128)
	raised := raise_contrast(color_from_hex('#7a7a7a'), grey, contrast_aaa)
	hex := raised.to_hex(true)
	assert hex == '#ffffff' || hex == '#000000', 'got ${hex}'
}

fn test_enforce_contrast_covers_the_ansi_sixteen() {
	mut scheme := Scheme{
		theme:    'dark'
		pigments: sample_pigments()
	}
	colors := get_all_colors(mut scheme)
	background := colors[0]
	for i in 1 .. 16 {
		got := contrast_ratio(colors[i].quantised(), background.quantised())
		assert got >= contrast_aa, 'colour ${i} is only ${got} against the background'
	}
}

fn test_enforce_contrast_can_be_turned_off() {
	mut on := Scheme{
		theme:    'dark'
		pigments: sample_pigments()
		seed:     11
	}
	mut off := Scheme{
		theme:    'dark'
		pigments: sample_pigments()
		seed:     11
		contrast: -1.0
	}
	enforced := get_all_colors(mut on)
	untouched := get_all_colors(mut off)
	mut differences := 0
	for i in 1 .. 16 {
		if enforced[i].to_hex(true) != untouched[i].to_hex(true) {
			differences++
		}
	}
	assert differences > 0, 'turning contrast off changed nothing'
}

fn test_enforce_contrast_leaves_the_background_and_the_ramps_alone() {
	// Slot 0 is what everything is measured against, and the ramps past 15 are gradients rather
	// than text colours.
	mut scheme := Scheme{
		theme:    'dark'
		pigments: sample_pigments()
		seed:     3
	}
	colors := get_all_colors(mut scheme)
	enforced := enforce_contrast(colors, contrast_aa)
	assert enforced[0].to_hex(true) == colors[0].to_hex(true)
	for i in 16 .. colors.len {
		assert enforced[i].to_hex(true) == colors[i].to_hex(true)
	}
}

fn test_enforce_contrast_ignores_a_short_palette() {
	short := [color_from_rgb(0, 0, 0), color_from_rgb(1, 1, 1)]
	assert enforce_contrast(short, contrast_aa).len == 2
}

fn test_the_other_direction_is_tried_when_the_first_cannot_reach() {
	// A colour a shade lighter than a near-white background can never reach the threshold by
	// getting lighter, however far it goes. Trying only the preferred direction returned white
	// and quietly failed the guarantee.
	background := color_from_rgb(250, 250, 250)
	slightly_lighter := color_from_rgb(253, 253, 253)
	raised := raise_contrast(slightly_lighter, background, contrast_aa)
	got := contrast_ratio(raised.quantised(), background.quantised())
	assert got >= contrast_aa, 'only reached ${got} (${raised.to_hex(true)})'
}

fn test_light_backgrounds_are_handled() {
	// The whole ANSI sixteen, on a light theme.
	mut scheme := Scheme{
		theme:    'light'
		pigments: sample_pigments()
		seed:     8
	}
	colors := get_all_colors(mut scheme)
	for i in 1 .. 16 {
		got := contrast_ratio(colors[i].quantised(), colors[0].quantised())
		assert got >= contrast_aa, 'colour ${i} is only ${got}'
	}
}

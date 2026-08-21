module main

import math

fn close(a f64, b f64, tolerance f64) bool {
	return math.abs(a - b) <= tolerance
}

fn test_lab_endpoints() {
	assert close(color_from_rgb(0, 0, 0).to_lab().l, 0.0, 0.001)
	assert close(color_from_rgb(255, 255, 255).to_lab().l, 100.0, 0.001)

	// Neutrals carry no chroma; a drifting white point shows up here first.
	white := color_from_rgb(255, 255, 255).to_lab()
	assert close(white.a, 0.0, 0.01)
	assert close(white.b, 0.0, 0.01)
}

fn test_lab_known_value() {
	// Cross-checked against Colors.jl, which gives L=38.334, a=25.58, b=-55.28 for #3f51b5.
	lab := color_from_hex('#3f51b5').to_lab()
	assert close(lab.l, 38.334, 0.01)
	assert close(lab.a, 25.58, 0.05)
	assert close(lab.b, -55.28, 0.05)
}

fn test_rgb_lab_roundtrip() {
	samples := [
		color_from_rgb(0, 0, 0),
		color_from_rgb(255, 255, 255),
		color_from_rgb(63, 81, 181),
		color_from_rgb(1, 2, 3),
		color_from_rgb(200, 15, 90),
	]
	for c in samples {
		lab := c.to_lab()
		back := color_from_lab(lab.l, lab.a, lab.b, 1.0)
		r1, g1, b1 := c.rgb_u8()
		r2, g2, b2 := back.rgb_u8()
		assert r1 == r2 && g1 == g2 && b1 == b2
	}
}

fn test_hsl_roundtrip() {
	for rgb in [[u8(10), 200, 40], [u8(255), 0, 0], [u8(128), 128, 128]] {
		c := color_from_rgb(rgb[0], rgb[1], rgb[2])
		hsl := c.to_hsl()
		back := color_from_hsl(hsl.h, hsl.s, hsl.l)
		r1, g1, b1 := c.rgb_u8()
		r2, g2, b2 := back.rgb_u8()
		assert r1 == r2 && g1 == g2 && b1 == b2
	}
}

fn test_delta_e_is_zero_for_identical() {
	lab := color_from_hex('#123456').to_lab()
	assert close(delta_e_cie76(lab, lab), 0.0, 1e-9)
	// And non-zero, symmetric, for different colours.
	other := color_from_hex('#654321').to_lab()
	forward := delta_e_cie76(lab, other)
	backward := delta_e_cie76(other, lab)
	assert forward > 0.0
	assert close(forward, backward, 1e-9), 'asymmetric: ${forward} vs ${backward}, delta ${forward - backward}'
}

fn test_lighten_and_darken_clamp() {
	// Past the ends they saturate rather than wrapping round to the other extreme.
	assert color_from_rgb(255, 255, 255).lighten(0.9).to_hex(true) == '#ffffff'
	assert color_from_rgb(0, 0, 0).darken(0.9).to_hex(true) == '#000000'
	// And they move in the direction advertised.
	mid := color_from_rgb(128, 100, 60)
	assert mid.lighten(0.2).to_lab().l > mid.to_lab().l
	assert mid.darken(0.2).to_lab().l < mid.to_lab().l
}

fn test_complementary_is_an_involution() {
	c := color_from_rgb(63, 81, 181)
	twice := c.complementary().complementary()
	r1, g1, b1 := c.rgb_u8()
	r2, g2, b2 := twice.rgb_u8()
	assert r1 == r2 && g1 == g2 && b1 == b2
}

fn test_mix_endpoints_and_midpoint() {
	black := color_from_rgb(0, 0, 0)
	white := color_from_rgb(255, 255, 255)
	assert black.mix_rgb(white, 0.0).to_hex(true) == '#000000'
	assert black.mix_rgb(white, 1.0).to_hex(true) == '#ffffff'
	assert black.mix_rgb(white, 0.5).to_hex(true) == '#808080'
	// Lab mixing keeps the endpoints too, even though the middle differs from sRGB.
	assert black.mix_lab(white, 0.0).to_hex(true) == '#000000'
	assert black.mix_lab(white, 1.0).to_hex(true) == '#ffffff'
}

fn test_hex_parsing() {
	assert color_from_hex('#ffffff').to_hex(true) == '#ffffff'
	assert color_from_hex('ffffff').to_hex(true) == '#ffffff'
	// Three-digit form doubles each nibble: #abc is #aabbcc, not #0a0b0c.
	assert color_from_hex('#abc').to_hex(true) == '#aabbcc'
	assert color_from_hex('#FFF').to_hex(true) == '#ffffff'
	assert color_from_hex('#3f51b5').to_hex(false) == '3f51b5'
}

fn test_hex_rejects_bad_input() {
	for bad in ['', '#', 'zzz', '#12', '#12345', 'nonsense'] {
		if _ := parse_hex(bad) {
			assert false, 'parse_hex accepted ${bad}'
		}
	}
}

fn test_hex_is_lowercase_and_padded() {
	// Zero-padding is what keeps the cache file parseable; #0f0f0f must not print as #f0f0f.
	assert color_from_rgb(15, 15, 15).to_hex(true) == '#0f0f0f'
	assert color_from_rgb(0, 0, 0).to_hex(false).len == 6
}

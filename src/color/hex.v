module color

pub fn hex_val(ch u8) int {
	if ch >= `0` && ch <= `9` {
		return int(ch - `0`)
	}
	if ch >= `a` && ch <= `f` {
		return int(ch - `a`) + 10
	}
	if ch >= `A` && ch <= `F` {
		return int(ch - `A`) + 10
	}
	return -1
}

// Accepts #rgb, #rrggbb and the same without a leading hash
pub fn parse_hex(input string) !Color {
	mut s := input.trim_space()
	if s.starts_with('#') {
		s = s[1..]
	}
	mut digits := ''
	for ch in s {
		if hex_val(ch) < 0 {
			break
		}
		digits += ch.ascii_str()
	}
	if digits.len == 6 {
		r := u8(hex_val(digits[0]) * 16 + hex_val(digits[1]))
		g := u8(hex_val(digits[2]) * 16 + hex_val(digits[3]))
		b := u8(hex_val(digits[4]) * 16 + hex_val(digits[5]))
		return color_from_rgb(r, g, b)
	}
	if digits.len == 3 {
		r := u8(hex_val(digits[0]))
		g := u8(hex_val(digits[1]))
		b := u8(hex_val(digits[2]))
		return color_from_rgb(r * 16 + r, g * 16 + g, b * 16 + b)
	}
	return error('Expected hex string of 3 or 6 characters length')
}

pub fn color_from_hex(hex_string string) Color {
	return parse_hex(hex_string) or { Color{0.0, 0.0, 0.0, 1.0} }
}

pub fn (c Color) to_hex(leading_hash bool) string {
	r, g, b := c.rgb_u8()
	prefix := if leading_hash { '#' } else { '' }
	return '${prefix}${r:02x}${g:02x}${b:02x}'
}

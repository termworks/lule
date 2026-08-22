module color

import math

pub struct Color {
pub mut:
	r     f64
	g     f64
	b     f64
	alpha f64 = 1.0
}

pub struct Lab {
pub mut:
	l     f64
	a     f64
	b     f64
	alpha f64 = 1.0
}

pub struct LCh {
pub mut:
	l f64
	c f64
	h f64
}

pub struct Hsl {
pub mut:
	h f64
	s f64
	l f64
}

pub fn clamp01(v f64) f64 {
	if v < 0.0 {
		return 0.0
	}
	if v > 1.0 {
		return 1.0
	}
	return v
}

pub fn color_from_rgb(r u8, g u8, b u8) Color {
	return Color{f64(r) / 255.0, f64(g) / 255.0, f64(b) / 255.0, 1.0}
}

pub fn (c Color) rgb_u8() (u8, u8, u8) {
	r := u8(math.round(clamp01(c.r) * 255.0))
	g := u8(math.round(clamp01(c.g) * 255.0))
	b := u8(math.round(clamp01(c.b) * 255.0))
	return r, g, b
}

// sRGB companding, D65 reference white
pub fn linearize(v f64) f64 {
	if v <= 0.04045 {
		return v / 12.92
	}
	return math.pow((v + 0.055) / 1.055, 2.4)
}

fn delinearize(v f64) f64 {
	if v <= 0.0031308 {
		return 12.92 * v
	}
	return 1.055 * math.pow(v, 1.0 / 2.4) - 0.055
}

fn lab_f(t f64) f64 {
	delta := 6.0 / 29.0
	if t > delta * delta * delta {
		return math.cbrt(t)
	}
	return t / (3.0 * delta * delta) + 4.0 / 29.0
}

fn lab_finv(t f64) f64 {
	delta := 6.0 / 29.0
	if t > delta {
		return t * t * t
	}
	return 3.0 * delta * delta * (t - 4.0 / 29.0)
}

pub fn (c Color) to_lab() Lab {
	rl := linearize(clamp01(c.r))
	gl := linearize(clamp01(c.g))
	bl := linearize(clamp01(c.b))

	x := (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047
	y := (0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl) / 1.00000
	z := (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883

	fx := lab_f(x)
	fy := lab_f(y)
	fz := lab_f(z)

	return Lab{
		l:     116.0 * fy - 16.0
		a:     500.0 * (fx - fy)
		b:     200.0 * (fy - fz)
		alpha: c.alpha
	}
}

pub fn color_from_lab(l f64, a f64, b f64, alpha f64) Color {
	fy := (l + 16.0) / 116.0
	fx := fy + a / 500.0
	fz := fy - b / 200.0

	x := lab_finv(fx) * 0.95047
	y := lab_finv(fy) * 1.00000
	z := lab_finv(fz) * 1.08883

	rl := 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
	gl := -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
	bl := 0.0556434 * x - 0.2040259 * y + 1.0572252 * z

	return Color{
		r:     clamp01(delinearize(rl))
		g:     clamp01(delinearize(gl))
		b:     clamp01(delinearize(bl))
		alpha: alpha
	}
}

pub fn (c Color) to_lch() LCh {
	lab := c.to_lab()
	chroma := math.sqrt(lab.a * lab.a + lab.b * lab.b)
	mut hue := math.atan2(lab.b, lab.a) * 180.0 / math.pi
	if hue < 0.0 {
		hue += 360.0
	}
	return LCh{lab.l, chroma, hue}
}

pub fn (c Color) to_hsl() Hsl {
	r := clamp01(c.r)
	g := clamp01(c.g)
	b := clamp01(c.b)
	max := math.max(r, math.max(g, b))
	min := math.min(r, math.min(g, b))
	l := (max + min) / 2.0
	if max == min {
		return Hsl{0.0, 0.0, l}
	}
	d := max - min
	s := if l > 0.5 { d / (2.0 - max - min) } else { d / (max + min) }
	mut h := 0.0
	if max == r {
		h = (g - b) / d + (if g < b { 6.0 } else { 0.0 })
	} else if max == g {
		h = (b - r) / d + 2.0
	} else {
		h = (r - g) / d + 4.0
	}
	return Hsl{h * 60.0, s, l}
}

fn hue_to_rgb(p f64, q f64, tt f64) f64 {
	mut t := tt
	if t < 0.0 {
		t += 1.0
	}
	if t > 1.0 {
		t -= 1.0
	}
	if t < 1.0 / 6.0 {
		return p + (q - p) * 6.0 * t
	}
	if t < 1.0 / 2.0 {
		return q
	}
	if t < 2.0 / 3.0 {
		return p + (q - p) * (2.0 / 3.0 - t) * 6.0
	}
	return p
}

pub fn color_from_hsl(h f64, s f64, l f64) Color {
	mut hh := math.fmod(h, 360.0)
	if hh < 0.0 {
		hh += 360.0
	}
	if s == 0.0 {
		return Color{l, l, l, 1.0}
	}
	q := if l < 0.5 { l * (1.0 + s) } else { l + s - l * s }
	p := 2.0 * l - q
	hn := hh / 360.0
	return Color{
		r:     hue_to_rgb(p, q, hn + 1.0 / 3.0)
		g:     hue_to_rgb(p, q, hn)
		b:     hue_to_rgb(p, q, hn - 1.0 / 3.0)
		alpha: 1.0
	}
}

pub fn (c Color) lighten(f f64) Color {
	hsl := c.to_hsl()
	return color_from_hsl(hsl.h, hsl.s, clamp01(hsl.l + f))
}

pub fn (c Color) darken(f f64) Color {
	return c.lighten(-f)
}

pub fn (c Color) complementary() Color {
	hsl := c.to_hsl()
	return color_from_hsl(hsl.h + 180.0, hsl.s, hsl.l)
}

// Linear interpolation in sRGB space
pub fn (c Color) mix_rgb(other Color, f f64) Color {
	return Color{
		r:     c.r + (other.r - c.r) * f
		g:     c.g + (other.g - c.g) * f
		b:     c.b + (other.b - c.b) * f
		alpha: c.alpha + (other.alpha - c.alpha) * f
	}
}

// Linear interpolation in CIE Lab space
pub fn (c Color) mix_lab(other Color, f f64) Color {
	a := c.to_lab()
	b := other.to_lab()
	return color_from_lab(a.l + (b.l - a.l) * f, a.a + (b.a - a.a) * f, a.b + (b.b - a.b) * f, 1.0)
}

// CIE76 colour difference
pub fn delta_e_cie76(a Lab, b Lab) f64 {
	dl := a.l - b.l
	da := a.a - b.a
	db := a.b - b.b
	return math.sqrt(dl * dl + da * da + db * db)
}

// WCAG relative luminance. The same linearised channels the Lab conversion uses, weighted for
// perceived brightness rather than for a colour space.
pub fn (c Color) relative_luminance() f64 {
	return 0.2126 * linearize(clamp01(c.r)) + 0.7152 * linearize(clamp01(c.g)) +
		0.0722 * linearize(clamp01(c.b))
}

// WCAG contrast, from 1.0 (identical) to 21.0 (black on white). 4.5 is the AA threshold for body
// text and 7.0 is AAA; below 3.0 two colours are hard to tell apart at all.
pub fn contrast_ratio(a Color, b Color) f64 {
	la := a.relative_luminance()
	lb := b.relative_luminance()
	lighter := if la > lb { la } else { lb }
	darker := if la > lb { lb } else { la }
	return (lighter + 0.05) / (darker + 0.05)
}

// The colour as it will be written: eight bits per channel, the same value the hex in the file
// decodes back to. Anything that has to be *true of the output* has to be measured on this.
pub fn (c Color) quantised() Color {
	r, g, b := c.rgb_u8()
	mut q := color_from_rgb(r, g, b)
	q.alpha = c.alpha
	return q
}

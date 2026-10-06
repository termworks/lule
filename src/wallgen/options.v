module wallgen

import math
import os
import strconv
import time
import color

pub const styles = ['cross', 'digi', 'dome', 'dots', 'grid', 'hexag', 'honey', 'nato', 'stars',
	'triang', 'contours', 'diagonals', 'chevrons', 'herringbone', 'basketweave', 'brick', 'diamonds',
	'octagons', 'scales', 'seigaiha', 'circles', 'quatrefoil', 'greekkey', 'pinwheel', 'asanoha',
	'cubes', 'crosshatch', 'truchet', 'maze', 'circuit', 'waves', 'ribbons', 'flowfield', 'voronoi',
	'pebbles', 'constellation', 'phyllotaxis', 'spirals', 'rosettes', 'sierpinski', 'koch', 'hilbert',
	'branches']

pub struct Options {
pub mut:
	logo   string
	size   f64    = 35
	color  string = '#ff9eae'
	width  int    = 3456
	height int    = 2160
	seed   u32    = 1
	style  string = 'random'
	format string = 'png'
	output string
}

fn expanded(path string) string {
	if path == '~' { return os.home_dir() }
	if path.starts_with('~/') { return os.join_path(os.home_dir(), path[2..]) }
	return path
}

fn hex_color(value string) !string {
	mut hex := value.trim_space().trim_string_left('#')
	if hex.len !in [3, 6] || !hex.bytes().all((it >= `0` && it <= `9`)
		|| (it >= `a` && it <= `f`) || (it >= `A` && it <= `F`)) {
		return error('color must be #RGB or #RRGGBB')
	}
	if hex.len == 3 {
		hex = '${hex[0].ascii_str().repeat(2)}${hex[1].ascii_str().repeat(2)}${hex[2].ascii_str().repeat(2)}'
	}
	return '#${hex.to_lower()}'
}

fn random_color(seed u32) string {
	hue := f64(hash(11, 0, seed) % 36000) / 100
	saturation := 0.65 + f64(hash(17, 0, seed) % 2001) / 10000
	lightness := 0.62 + f64(hash(23, 0, seed) % 801) / 10000
	return color.color_from_hsl(hue, saturation, lightness).to_hex(true)
}

fn parse_size(value string) !f64 {
	n := strconv.atof64(value)!
	if math.is_nan(n) || math.is_inf(n, 0) || n <= 0 || n > 100 {
		return error('size must be greater than 0 and at most 100 percent')
	}
	return n
}

fn dimension(value string) !int {
	n := strconv.atoi(value)!
	if n < 64 || n > 8192 { return error('width and height must be between 64 and 8192 pixels') }
	return n
}

fn arguments(args []string) !map[string]string {
	mut flags := map[string]string{}
	mut i := 0
	for i < args.len {
		arg := args[i]
		if !arg.starts_with('--') { return error('unexpected argument: ${arg}') }
		parts := arg[2..].split_nth('=', 2)
		key := parts[0]
		if key !in ['logo', 'size', 'color', 'width', 'height', 'seed', 'style', 'format', 'output'] {
			return error('unknown wallpaper option: --${key}')
		}
		if key in flags { return error('duplicate option: --${key}') }
		mut value := ''
		if parts.len == 2 {
			value = parts[1]
		} else {
			i++
			if i >= args.len || args[i].starts_with('--') { return error('--${key} needs a value') }
			value = args[i]
		}
		if value == '' { return error('--${key} needs a value') }
		flags[key] = value
		i++
	}
	return flags
}

fn ask(prompt string, fallback string) !string {
	eprint(prompt)
	value := os.input_opt('') or {
		return error('input ended; supply --logo and --size for unattended use')
	}
	return if value.trim_space() == '' { fallback } else { value.trim_space() }
}

fn options(flags map[string]string) !Options {
	mut o := Options{
		seed: u32(time.now().unix_micro())
	}
	if 'seed' in flags {
		n := strconv.parse_uint(flags['seed'], 10, 32)!
		o.seed = u32(n)
	}
	o.logo = expanded(if 'logo' in flags {
		flags['logo']
	} else {
		ask('Logo path (SVG or PNG): ', '')!
	})
	if o.logo == '' { return error('a logo path is required') }
	o.size = parse_size(if 'size' in flags {
		flags['size']
	} else {
		ask('Logo size (% of shorter canvas side) [35]: ', '35')!
	})!
	o.color = if 'color' in flags {
		hex_color(flags['color'])!
	} else {
		random_color(o.seed)
	}
	if 'width' in flags { o.width = dimension(flags['width'])! }
	if 'height' in flags { o.height = dimension(flags['height'])! }
	if i64(o.width) * o.height > 40000000 { return error('canvas cannot exceed 40 million pixels') }
	if 'style' in flags { o.style = flags['style'] }
	if o.style != 'random' && o.style !in styles {
		return error('style must be random or ${styles.join(', ')}')
	}
	if o.style == 'random' { o.style = styles[int(hash(0, 0, o.seed) % u32(styles.len))] }
	if 'format' in flags { o.format = flags['format'] }
	if o.format !in ['svg', 'png'] { return error('format must be svg or png') }
	o.output = expanded(flags['output'] or { '${o.style}-${o.seed}.${o.format}' })
	if os.file_ext(o.output).to_lower() != '.${o.format}' {
		return error('output extension must match --format=${o.format}')
	}
	return o
}

fn print_help() {
	println('lule wallpaper [OPTIONS]

With no options, asks for a logo and its size; the color is randomly chosen.
Generates ONE wallpaper with a random procedural pattern, saved as <style>-<seed>.png.

  --logo PATH       SVG or PNG logo (transparent background recommended)
  --size PERCENT    Logo bounding square as % of shorter canvas side [35]
  --color HEX       Background color, #RGB or #RRGGBB [random bright color]
  --style NAME      Pattern name [random]; see --list-patterns
  --list-patterns   Print all ${styles.len} pattern names and exit
  --seed N          Reproducible pattern and color seed, 0..4294967295 [random]
  --width N         Canvas width in pixels [3456]
  --height N        Canvas height in pixels [2160]
  --format NAME     png or svg [png]
  --output PATH     Output file; existing paths are never overwritten

Flags accept --name=value or --name value. Only missing logo/size are prompted.
Random colors have 65–85% saturation and 62–70% lightness: no white, black or gray.
PNG and SVG export are built in; no external renderer is needed.
Logo aspect ratio and original colors are preserved. No desktop settings change.')
	println('\nPatterns: ${styles.join(', ')}')
}

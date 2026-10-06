module wallgen

import encoding.base64
import encoding.xml
import math
import os
import rand
import stbi

fn logo_uri(path string) !string {
	if !os.is_file(path) { return error('logo is not a file: ${path}') }
	if os.file_size(path) > 16 * 1024 * 1024 { return error('logo must be at most 16 MiB') }
	data := os.read_bytes(path)!
	mut mime := ''
	match os.file_ext(path).to_lower() {
		'.svg' {
			doc := xml.XMLDocument.from_string(data.bytestr()) or {
				return error('invalid SVG logo: ${err}')
			}
			if doc.root.name != 'svg' { return error('logo XML root must be svg') }
			mime = 'image/svg+xml'
		}
		'.png' {
			if data.len < 24 || data[..8] != [u8(137), 80, 78, 71, 13, 10, 26, 10] {
				return error('invalid PNG logo')
			}
			w := png_dimension(data[16..20])
			h := png_dimension(data[20..24])
			if w == 0 || h == 0 || u64(w) * h > 40000000 {
				return error('logo cannot exceed 40 million pixels')
			}
			img := stbi.load_from_memory(data.data, data.len, desired_channels: 4) or {
				return error('invalid PNG logo: ${err}')
			}
			unsafe { img.free() }
			mime = 'image/png'
		}
		else {
			return error('logo must be an SVG or PNG file')
		}
	}

	return 'data:${mime};base64,${base64.encode(data)}'
}

fn png_dimension(bytes []u8) u32 {
	return u32(bytes[0]) << 24 | u32(bytes[1]) << 16 | u32(bytes[2]) << 8 | u32(bytes[3])
}

fn svg(o Options, uri string) string {
	w := f64(o.width)
	h := f64(o.height)
	unit := math.max(math.min(w, h) / 1000, math.max(w, h) / 4000)
	size := math.min(w, h) * o.size / 100
	x := (w - size) / 2
	y := (h - size) / 2
	return '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${o.width}" height="${o.height}" viewBox="0 0 ${o.width} ${o.height}">
<title>Lule ${o.style}, seed ${o.seed}</title>
<defs>
<linearGradient id="shade" x1="0" y1="0" x2="0" y2="1"><stop offset="0.38" stop-color="#1a1a1a" stop-opacity="0"/><stop offset="1" stop-color="#1a1a1a" stop-opacity="0.87"/></linearGradient>
<radialGradient id="edge" cx="50%" cy="50%" r="70%"><stop offset="0.55" stop-color="#1a1a1a" stop-opacity="0.10"/><stop offset="1" stop-color="#1a1a1a" stop-opacity="0.22"/></radialGradient>
</defs>
<rect width="100%" height="100%" fill="${o.color}"/>
<g fill="none" stroke="#000" stroke-width="1" opacity="0.10" transform="scale(${unit})">${pattern(o.style,
		w / unit, h / unit, o.seed)}</g>
<rect width="100%" height="100%" fill="url(#shade)"/>
<rect width="100%" height="100%" fill="url(#edge)"/>
<image x="${x}" y="${y}" width="${size}" height="${size}" preserveAspectRatio="xMidYMid meet" xlink:href="${uri}"/>
</svg>\n'
}

fn generate(o Options) ! {
	if os.exists(o.output) || os.is_link(o.output) {
		return error('output already exists: ${o.output}')
	}
	uri := logo_uri(o.logo)!
	parent := os.dir(os.abs_path(o.output))
	if !os.is_dir(parent) { return error('output directory does not exist: ${parent}') }
	stage := os.join_path(parent, '.lule-wallpaper-${rand.uuid_v4()}')
	os.mkdir(stage, mode: 0o700)!
	defer { os.rmdir_all(stage) or {} }
	result := os.join_path(stage, 'wallpaper.${o.format}')
	source := svg(o, uri)
	if o.format == 'png' {
		render_png(source, result, o.width, o.height)!
	} else {
		os.write_file(result, source)!
	}
	os.chmod(result, 0o600)!
	os.link(result, os.abs_path(o.output)) or {
		return error('cannot publish ${o.output} without overwriting: ${err}')
	}
}

// Prompts for missing inputs and writes one procedural wallpaper.
pub fn run(args []string) ! {
	if args == ['--list-patterns'] {
		println(styles.join('\n'))
		return
	}
	if '--help' in args || '-h' in args {
		print_help()
		return
	}
	flags := arguments(args)!
	o := options(flags)!
	generate(o)!
	println('${o.output} (pattern: ${o.style}, color: ${o.color}, seed: ${o.seed})')
}

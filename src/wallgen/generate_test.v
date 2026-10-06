module wallgen

import encoding.base64
import encoding.xml
import math
import os
import rand
import stbi
import color

fn test_omitted_color_is_bright_random_and_reproducible() {
	mut colors := map[string]bool{}
	mut hues := map[int]bool{}
	for seed in 0 .. 1000 {
		flags := arguments(['--logo=logo.svg', '--size=40', '--seed=${seed}'])!
		o := options(flags)!
		assert o.color == options(flags)!.color
		hsl := color.color_from_hex(o.color).to_hsl()
		assert hsl.s >= 0.64 && hsl.s <= 0.86
		assert hsl.l >= 0.619 && hsl.l <= 0.701
		colors[o.color] = true
		hues[int(hsl.h / 30)] = true
	}
	assert colors.len > 950
	assert hues.len == 12
	for explicit in ['#000000', '#ffffff', '#808080', '#12ab34'] {
		o :=
			options(arguments(['--logo=logo.svg', '--size=40', '--seed=42', '--color=${explicit}'])!)!
		assert o.color == explicit
	}
}

fn test_color_and_size_validation() {
	assert hex_color('#AbC')! == '#aabbcc'
	assert hex_color('123456')! == '#123456'
	for bad in ['', 'blue', '#12345', '1234567', '#12fg00', '<red>'] {
		if _ := hex_color(bad) { assert false, bad
		 }
	}
	assert parse_size('35.5')! == 35.5
	for bad in ['0', '-1', '101', 'nan', 'inf', 'abc', '35%'] {
		if _ := parse_size(bad) { assert false, bad
		 }
	}
	for bad in ['0', '63', '8193', '1.5', 'wide'] {
		if _ := dimension(bad) { assert false, bad
		 }
	}
}

fn test_flags_and_defaults() {
	flags := arguments(['--logo', '/a=b/logo.svg', '--size=40', '--color=#abc', '--seed=42'])!
	o := options(flags)!
	assert o.logo == '/a=b/logo.svg'
	assert o.size == 40
	assert o.color == '#aabbcc'
	assert o.width == 3456 && o.height == 2160
	assert o.style in styles
	assert o.format == 'png'
	assert o.output == '${o.style}-42.png'
	assert options(flags)!.style == o.style
	mut chosen := map[string]bool{}
	for seed in 0 .. 1000 {
		mut seeded := flags.clone()
		seeded['seed'] = seed.str()
		chosen[options(seeded)!.style] = true
	}
	assert chosen.len == styles.len
	for args in [['--unknown=x'], ['--logo'], ['--logo='], ['--size=2', '--size=3'],
		['positional']] {
		if _ := arguments(args) { assert false, args.str()
		 }
	}
	for extra in [{
		'seed': '-1'
	}, {
		'seed': '4294967296'
	}, {
		'style': 'all'
	}, {
		'format': 'both'
	}, {
		'output': 'a.svg'
	}, {
		'width':  '8192'
		'height': '8192'
	}] {
		mut invalid := flags.clone()
		for k, v in extra {
			invalid[k] = v
		}
		if _ := options(invalid) { assert false, extra.str()
		 }
	}
}

fn test_noise_is_finite_deterministic_and_seeded() {
	for y in -10 .. 10 {
		for x in -10 .. 10 {
			n := fbm(f64(x) / 3, f64(y) / 7, 42)
			assert !math.is_nan(n) && n >= 0 && n <= 1
			assert n == fbm(f64(x) / 3, f64(y) / 7, 42)
		}
	}
	assert fbm(1.2, 3.4, 42) != fbm(1.2, 3.4, 43)
}

fn test_every_style_is_valid_svg() {
	uri := 'data:image/svg+xml;base64,' +
		base64.encode_str('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50"><rect width="100" height="50" fill="black"/></svg>')
	mut outputs := map[string]bool{}
	for style in styles {
		o := Options{
			width:  320
			height: 200
			size:   40
			style:  style
		}
		content := svg(o, uri)
		doc := xml.XMLDocument.from_string(content)!
		assert doc.root.name == 'svg'
		assert content.contains('x="120.0" y="60.0" width="80.0" height="80.0"')
		assert content.contains('preserveAspectRatio="xMidYMid meet"')
		assert content == svg(o, uri)
		assert !content.contains('nan') && !content.contains('inf')
		assert content.len < 3000000
		assert !outputs[content]
		outputs[content] = true
	}
	wide := svg(Options{ width: 8192, height: 64, style: 'contours' }, uri)
	assert wide.len < 3000000
}

fn test_generate_png_center_and_output_safety() {
	dir := os.join_path(os.temp_dir(), 'lule-wallgen-test-${rand.uuid_v4()}')
	os.mkdir(dir)!
	defer { os.rmdir_all(dir) or {} }
	logo := os.join_path(dir, 'logo with spaces.svg')
	os.write_file(logo,
		'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50"><rect width="100" height="50" fill="#ff0000"/></svg>')!
	output := os.join_path(dir, 'result.png')
	o := Options{
		logo:   logo
		output: output
		width:  320
		height: 200
		size:   40
		style:  'honey'
		color:  '#80b8cd'
	}
	generate(o)!
	img := stbi.load(output, desired_channels: 3)!
	defer { unsafe { img.free() } }
	assert img.width == 320 && img.height == 200
	pixels := unsafe { img.data.vbytes(img.width * img.height * 3) }
	for y in 0 .. 200 {
		for x in 0 .. 320 {
			at := (y * 320 + x) * 3
			red := pixels[at] == 255 && pixels[at + 1] == 0 && pixels[at + 2] == 0
			assert red == (x >= 120 && x < 200 && y >= 80 && y < 120)
		}
	}
	assert pixels[(20 * 320 + 20) * 3 + 2] > pixels[(180 * 320 + 20) * 3 + 2]
	before := os.read_bytes(output)!
	if _ := generate(o) { assert false, 'overwrote output'
	 }
	assert before == os.read_bytes(output)!
	link := os.join_path(dir, 'link.png')
	os.symlink(output, link)!
	if _ := generate(Options{ ...o, output: link }) { assert false, 'wrote through symlink'
	 }
	assert before == os.read_bytes(output)!
	assert os.ls(dir)!.len == 3
}

fn test_invalid_logos() {
	dir := os.join_path(os.temp_dir(), 'lule-wallgen-invalid-${rand.uuid_v4()}')
	os.mkdir(dir)!
	defer { os.rmdir_all(dir) or {} }
	for name, content in {
		'bad.svg':    '<html/>'
		'bad.png':    'not a PNG'
		'bad.txt':    'text'
		'broken.svg': '<svg>'
	} {
		path := os.join_path(dir, name)
		os.write_file(path, content)!
		if _ := logo_uri(path) { assert false, name
		 }
	}
	if _ := logo_uri(os.join_path(dir, 'missing.png')) { assert false
	 }
}

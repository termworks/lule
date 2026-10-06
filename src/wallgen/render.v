module wallgen

import stbi

#pkgconfig resvg-static
#include "resvg.h"

struct C.resvg_options {}

struct C.resvg_render_tree {}

struct C.resvg_transform {
	a f32
	b f32
	c f32
	d f32
	e f32
	f f32
}

fn C.resvg_options_create() &C.resvg_options
fn C.resvg_options_destroy(&C.resvg_options)
fn C.resvg_parse_tree_from_data(&char, usize, &C.resvg_options, &&C.resvg_render_tree) int
fn C.resvg_tree_destroy(&C.resvg_render_tree)
fn C.resvg_transform_identity() C.resvg_transform
fn C.resvg_render(&C.resvg_render_tree, C.resvg_transform, u32, u32, &u8)

fn render_pixels(source string, width int, height int) ![]u8 {
	if width <= 0 || height <= 0 || i64(width) * height > 40000000 {
		return error('render dimensions must be positive and at most 40 million pixels')
	}
	settings := C.resvg_options_create()
	defer { C.resvg_options_destroy(settings) }
	mut tree := &C.resvg_render_tree(unsafe { nil })
	code := C.resvg_parse_tree_from_data(source.str, usize(source.len), settings, &tree)
	if code != 0 { return error('SVG rendering failed: resvg parse error ${code}') }
	defer { C.resvg_tree_destroy(tree) }
	mut pixels := []u8{len: width * height * 4}
	C.resvg_render(tree, C.resvg_transform_identity(), u32(width), u32(height), pixels.data)
	// Convert premultiplied RGBA to the straight alpha used by PNG.
	for i := 0; i < pixels.len; i += 4 {
		a := int(pixels[i + 3])
		if a == 0 || a == 255 { continue
		 }
		for channel in 0 .. 3 {
			pixels[i + channel] = u8((int(pixels[i + channel]) * 255 + a / 2) / a)
		}
	}
	return pixels
}

fn render_png(source string, output string, width int, height int) ! {
	pixels := render_pixels(source, width, height)!
	stbi.stbi_write_png(output, width, height, 4, pixels.data, width * 4)!
}

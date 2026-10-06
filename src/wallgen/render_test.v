module wallgen

fn test_renderer_straight_alpha() {
	pixels := render_pixels('<svg xmlns="http://www.w3.org/2000/svg" width="2" height="1"><rect width="1" height="1" fill="#ff0000" opacity="0.5"/></svg>',
		2, 1)!
	assert pixels[0] == 255 && pixels[1] == 0 && pixels[2] == 0
	assert pixels[3] >= 127 && pixels[3] <= 128
	assert pixels[4..] == [u8(0), 0, 0, 0]
}

fn test_renderer_rejects_invalid_input() {
	if _ := render_pixels('<svg>', 10, 10) { assert false
	 }
	if _ := render_pixels('', 10, 10) { assert false
	 }
	if _ := render_pixels('<svg/>', 0, 10) { assert false
	 }
	if _ := render_pixels('<svg/>', 8192, 8192) { assert false
	 }
}

fn test_embedded_renderer_preserves_patterns_gradients_and_clipping() {
	source := '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><defs><linearGradient id="g"><stop stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/></linearGradient><pattern id="p" width="10" height="10" patternUnits="userSpaceOnUse"><rect width="5" height="10" fill="#00ff00"/></pattern><clipPath id="clip"><rect width="20" height="20"/></clipPath></defs><rect width="40" height="20" fill="url(#g)"/><rect width="40" height="10" fill="url(#p)" clip-path="url(#clip)"/></svg>'
	pixels := render_pixels(source, 40, 20)!
	assert pixels[1] == 255
	assert pixels[7 * 4 + 1] == 0
	assert pixels[10 * 4 + 1] == 255
	assert pixels[20 * 4 + 1] == 0
	assert pixels[(15 * 40) * 4] > pixels[(15 * 40 + 39) * 4]
	assert pixels[(15 * 40) * 4 + 2] < pixels[(15 * 40 + 39) * 4 + 2]
}

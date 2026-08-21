module main

import stbi

// Two vertical pixels per cell via the upper half block
pub fn display_image(path string, max_cols int, max_rows int) ! {
	img := stbi.load(path, desired_channels: 3)!
	defer {
		unsafe { img.free() }
	}
	src := unsafe { &u8(img.data) }

	if max_cols < 1 || max_rows < 1 {
		return
	}

	aspect := f64(img.height) / f64(img.width)
	mut cols := max_cols
	mut rows := int(f64(cols) * aspect * 0.5)
	if rows > max_rows {
		rows = max_rows
		cols = int(f64(rows) * 2.0 / aspect)
	}
	if cols < 1 {
		cols = 1
	}
	if rows < 1 {
		rows = 1
	}

	for row := 0; row < rows; row++ {
		mut line := ''
		for col := 0; col < cols; col++ {
			sx := int(f64(col) * f64(img.width) / f64(cols))
			ty := int(f64(row * 2) * f64(img.height) / f64(rows * 2))
			by := int(f64(row * 2 + 1) * f64(img.height) / f64(rows * 2))
			to := (ty * img.width + sx) * 3
			bo := (by * img.width + sx) * 3
			unsafe {
				line += '\x1b[38;2;${src[to]};${src[to + 1]};${src[to + 2]}m' +
					'\x1b[48;2;${src[bo]};${src[bo + 1]};${src[bo + 2]}m▀'
			}
		}
		println(line + '\x1b[0m')
	}
}

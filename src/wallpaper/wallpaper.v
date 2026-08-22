module wallpaper

import ui
import os
import rand
import stbi

const image_exts = ['.png', '.jpg', '.jpeg', '.bmp', '.gif', '.tga', '.psd', '.webp']

pub fn valid_image(path string) string {
	img := stbi.load(path, desired_channels: 3) or {
		eprintln('${ui.red_bold('error:')} Path ${ui.yellow(path)} is not a valid image file')
		exit(1)
	}
	unsafe { img.free() }
	return path
}

pub fn random_image(dir string) string {
	entries := os.ls(dir) or {
		eprintln('${ui.red_bold('error:')} Could not read directory ${ui.yellow(dir)}')
		exit(1)
	}
	mut candidates := []string{}
	for e in entries {
		full := os.join_path(dir, e)
		if !os.is_file(full) {
			continue
		}
		ext := os.file_ext(full).to_lower()
		if ext in image_exts {
			candidates << full
		}
	}
	if candidates.len == 0 {
		eprintln('${ui.red_bold('error:')} No images found in ${ui.yellow(dir)}')
		exit(1)
	}

	// Shuffle and take the first that decodes, rather than picking one and giving up if it does
	// not. A wallpaper directory collects truncated downloads and files whose extension lies, and
	// one of those used to take the daemon down on whichever cycle happened to choose it.
	rand.shuffle(mut candidates) or {}
	for candidate in candidates {
		if img := stbi.load(candidate, desired_channels: 3) {
			unsafe { img.free() }
			return candidate
		}
		eprintln('${ui.yellow('warning:')} skipping ${candidate}, it does not decode')
	}
	eprintln('${ui.red_bold('error:')} No decodable images in ${ui.yellow(dir)}')
	exit(1)
}

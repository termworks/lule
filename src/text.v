module main

import os
import rand
import stbi

const image_exts = ['.png', '.jpg', '.jpeg', '.bmp', '.gif', '.tga', '.psd', '.webp']

pub fn valid_image(path string) string {
	img := stbi.load(path, desired_channels: 3) or {
		eprintln('${red_bold('error:')} Path ${yellow(path)} is not a valid image file')
		exit(1)
	}
	unsafe { img.free() }
	return path
}

pub fn random_image(dir string) string {
	entries := os.ls(dir) or {
		eprintln('${red_bold('error:')} Could not read directory ${yellow(dir)}')
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
		eprintln('${red_bold('error:')} No images found in ${yellow(dir)}')
		exit(1)
	}
	pick := candidates[rand.intn(candidates.len) or { 0 }]
	return valid_image(pick)
}

pub fn write_to_file(path string, content string) {
	os.write_file(path, content) or {
		eprintln('${red_bold('error:')} Could not write into ${yellow(path)} -> ${err}')
		exit(1)
	}
}

pub fn write_temp_file(name string, content string) {
	write_to_file(os.join_path(os.temp_dir(), name), content)
}

pub fn temp_path(name string) string {
	return os.join_path(os.temp_dir(), name)
}

pub fn file_to_string(path string) !string {
	return os.read_file(path)!
}

pub fn lines_to_vec(path string) []string {
	content := os.read_file(path) or { return []string{} }
	mut out := []string{}
	for line in content.split_into_lines() {
		if line.trim_space() != '' {
			out << line
		}
	}
	return out
}

pub fn copy_to(src string, dst string) {
	os.cp(src, dst) or {}
}

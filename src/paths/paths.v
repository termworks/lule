module paths

import os
import ui

// Reading and writing the files lule keeps - the cache, the temp files a user's script reads, and
// the templates. Nothing here knows what a colour is.

// Refuses to write through a symlink.
//
// The temp files have fixed, predictable names in a directory everyone can write to, so on a
// shared machine another user can drop a symlink at /tmp/lule_colors pointing anywhere this user
// can write, and lule would truncate the target. Checking the path itself — not what it resolves
// to — is what closes that, and it costs one lstat.
pub fn write_to_file(path string, content string) {
	if os.is_link(path) {
		eprintln('${ui.red_bold('error:')} ${ui.yellow(path)} is a symlink; refusing to write through it')
		exit(1)
	}
	os.write_file(path, content) or {
		eprintln('${ui.red_bold('error:')} Could not write into ${ui.yellow(path)} -> ${err}')
		exit(1)
	}
	// The scheme names the wallpaper directory and every script that will be run; that is nobody
	// else's business on a shared machine.
	os.chmod(path, 0o600) or {}
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

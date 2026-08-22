module config

import color
import os
import cmd

// `~` is expanded by lule rather than left to the shell, because nothing in a config file goes
// through a shell: a literal `~/.config/kitty` would be created as a directory called `~`.
fn expand_home(path string) string {
	if path == '~' {
		return os.home_dir()
	}
	if path.starts_with('~/') {
		return os.join_path(os.home_dir(), path[2..])
	}
	return path
}

// Shared with the `--contrast` flag so the file and the flag understand the same words.
pub fn parse_contrast(text string) f64 {
	return match text.to_lower() {
		'aa' { color.contrast_aa }
		'aaa' { color.contrast_aaa }
		'none', 'off', '0', 'false' { -1.0 }
		else { text.f64() }
	}
}

// Resolves only where the config file is, ahead of reading it.
fn locate_config(a &cmd.Args, mut scheme Scheme) {
	if v := os.getenv_opt('LULE_C') {
		if v.trim_space() != '' {
			scheme.config = expand_home(v)
		}
	}
	if v := a.flags['configs'] {
		scheme.config = expand_home(v)
	}
}

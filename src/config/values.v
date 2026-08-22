module config

import color
import os
import ui
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
//
// Being pointed somewhere that holds no config is worth saying out loud. A config lule never finds
// is a run that quietly does nothing a config was meant to do - no templates rendered, no handlers
// called - and it looks exactly like a config that ran and had no effect. Only when the direction
// was explicit: the default location being empty is the ordinary case and stays silent.
fn locate_config(a &cmd.Args, mut scheme Scheme) {
	mut named := ''
	if v := os.getenv_opt('LULE_C') {
		if v.trim_space() != '' {
			scheme.config = expand_home(v)
			named = '\$LULE_C'
		}
	}
	if v := a.flags['configs'] {
		scheme.config = expand_home(v)
		named = '--configs'
	}
	if named != '' && !os.is_file(config_path(scheme.config)) {
		eprintln('${ui.yellow('warning:')} ${named} is ${ui.yellow(scheme.config)}, which has no ${config_name}')
	}
}

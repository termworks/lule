module main

import os

fn defs_concatinate(mut scheme Scheme) {
	config_dir := os.config_dir() or {
		eprintln('${red_bold('error:')} Path for configs is impossible to get')
		exit(1)
	}
	cache_dir := os.cache_dir()

	scheme.theme = 'dark'
	scheme.config = os.join_path(config_dir, 'lule')
	scheme.cache = os.join_path(cache_dir, 'lule')
	scheme.palette = 'pigment'
}

fn envi_concatinate(mut scheme Scheme) {
	if v := os.getenv_opt('LULE_W') {
		scheme.walldir = v
	}
	if v := os.getenv_opt('LULE_C') {
		scheme.config = v
	}
	if v := os.getenv_opt('LULE_S') {
		if v.trim_space() != '' {
			mut newvec := [v]
			newvec << scheme.scripts
			scheme.scripts = newvec
		}
	}
	if v := os.getenv_opt('LULE_A') {
		scheme.cache = v
	}
}

fn temp_concatinate(mut scheme Scheme) {
	if content := file_to_string(temp_path('lule_scheme')) {
		if sh := scheme_from_json(content) {
			config := scheme.config
			cache := scheme.cache
			scheme = sh
			scheme.config = config
			scheme.cache = cache
		}
	}
	scheme.image = ''
}

fn args_concatinate(a &Args, mut scheme Scheme) {
	if a.multi['script'].len > 0 {
		mut scripts := scheme.scripts.clone()
		scripts << a.multi['script']
		scheme.scripts = scripts
	}

	if a.multi['pattern'].len > 0 {
		mut patterns := []Pattern{}
		for val in a.multi['pattern'] {
			parts := val.split(':')
			if parts.len == 2 {
				patterns << Pattern{parts[0], parts[1]}
			}
		}
		scheme.patterns = patterns
	}

	if v := a.flags['configs'] {
		scheme.config = v
	}
	if v := a.flags['cache'] {
		scheme.cache = v
	}

	match a.subcommand {
		'create' {
			if v := a.flags['image'] {
				scheme.image = valid_image(v)
			} else if v := a.flags['wallpath'] {
				scheme.walldir = v
				scheme.image = random_image(v)
			}
			if v := a.flags['theme'] {
				scheme.theme = v
			}
			if v := a.flags['palette'] {
				scheme.palette = v
			}
			if v := a.flags['scheme'] {
				scheme.scheme = v
			}
		}
		'config' {
			if v := a.flags['theme'] {
				scheme.theme = v
			}
		}
		'daemon' {
			if v := a.flags['loop'] {
				scheme.looop = v.int()
			}
			if scheme.looop == 0 {
				scheme.looop = 300
			}
		}
		'test' {
			if v := a.flags['image'] {
				scheme.image = valid_image(v)
			}
			if v := a.flags['theme'] {
				scheme.theme = v
			}
		}
		else {}
	}
}

fn pipe_concatinate(mut scheme Scheme) {
	if is_tty_stdin() {
		return
	}
	mut input := ''
	for {
		line := os.get_raw_line()
		if line == '' {
			break
		}
		input += line
	}
	if input.trim_space() == '' {
		return
	}
	if sh := scheme_from_json(input) {
		config := scheme.config
		cache := scheme.cache
		scheme = sh
		scheme.config = config
		scheme.cache = cache
	}
}

pub fn concatinate(a &Args, mut scheme Scheme) {
	temp_concatinate(mut scheme)
	defs_concatinate(mut scheme)
	envi_concatinate(mut scheme)
	args_concatinate(a, mut scheme)
	pipe_concatinate(mut scheme)

	if scheme.scripts.len > 0 {
		mut seen := map[string]bool{}
		mut deduped := []string{}
		for s in scheme.scripts {
			if s.trim_space() != '' && !seen[s] {
				seen[s] = true
				deduped << s
			}
		}
		scheme.scripts = deduped
	}

	if scheme.image == '' && scheme.walldir == '' {
		eprintln('${red_bold('error:')} Environment variable ${yellow("'\$LULE_W'")} is empty')
		eprintln('${red_bold('error:')} Argument option ${yellow("'--wallpath'")} is not set')
		eprintln('${red_bold('error:')} Image argument ${yellow("'--image'")} is not given')
		eprintln('\n${yellow('USAGE')}\n\tlule help <subcommands>...\n\nFor more information try ${blue('--help')}')
		exit(1)
	}
}

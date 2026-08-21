module main

import os

#include <poll.h>

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
	// Both are per-invocation choices, not settings. Persisting the named scheme meant one
	// `--scheme=gruvbox` poisoned the temp scheme, and every later `lule create` — with no
	// --scheme at all — failed looking for it, until /tmp/lule_scheme was deleted by hand.
	scheme.image = ''
	scheme.scheme = ''
}

// The palette-tuning flags, shared by `create` and `test` so a setting can be previewed with the
// command that draws it and then applied with the command that saves it.
fn tuning_concatinate(a &Args, mut scheme Scheme) {
	if v := a.flags['saturation'] {
		scheme.saturation = v.f64()
	}
	if v := a.flags['illumination'] {
		scheme.illumination = v.f64()
	}
	if v := a.flags['hue'] {
		scheme.hue = v.f64()
	}
	if v := a.flags['blend'] {
		scheme.blend = v.f64()
	}
	if v := a.flags['sort'] {
		scheme.sort = v
	}
	if v := a.flags['seed'] {
		scheme.seed = v.int()
	}
	if v := a.flags['contrast'] {
		scheme.contrast = match v.to_lower() {
			'aa' { contrast_aa }
			'aaa' { contrast_aaa }
			'none', 'off', '0' { -1.0 }
			else { v.f64() }
		}
	}
	if a.present['norandom'] {
		scheme.norandom = true
	}
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
				// Anything else extracted no pigments at all and then reported success, so the
				// scheme was built from whatever happened to be cached already.
				if v !in known_palettes {
					eprintln('${red_bold('error:')} unknown palette ${yellow(v)}')
					eprintln('${red_bold('error:')} known palettes: ${known_palettes.join(', ')}')
					exit(1)
				}
				scheme.palette = v
			}
			if v := a.flags['scheme'] {
				scheme.scheme = v
			}
			tuning_concatinate(a, mut scheme)
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
			tuning_concatinate(a, mut scheme)
		}
		else {}
	}
}

struct C.pollfd {
mut:
	fd      int
	events  i16
	revents i16
}

fn C.poll(fds &C.pollfd, nfds u64, timeout int) int

// Whether stdin has something to give within the deadline. EOF counts as ready, so a closed or
// redirected stdin answers at once and only a pipe with no writer waits out the clock.
fn stdin_ready(timeout_ms int) bool {
	mut fd := C.pollfd{
		fd:      0
		events:  i16(C.POLLIN)
		revents: 0
	}
	return unsafe { C.poll(&fd, 1, timeout_ms) } > 0
}

// A scheme may be piped in, so a non-tty stdin has to be read — but reading it unconditionally
// hangs for ever when stdin is a pipe nobody ever writes to, which is what a backgrounded
// `lule create &` inside a script leaves behind.
//
// Asking poll() first, rather than reading on a thread with a deadline: a thread blocked in
// read() keeps the process alive after main returns, and even an explicit exit() does not take
// it down, so the hang moved rather than went away.
//
// $LULE_STDIN_MS overrides the deadline for a slow producer.
fn pipe_concatinate(mut scheme Scheme) {
	if is_tty_stdin() {
		return
	}
	mut budget := 250
	if v := os.getenv_opt('LULE_STDIN_MS') {
		parsed := v.trim_space().int()
		if parsed > 0 {
			budget = parsed
		}
	}
	if !stdin_ready(budget) {
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

// `needs_image` is whether this command is going to extract colours from a wallpaper. Only then
// is a source required: `create -- regen`, `colors` without `-g`, `config` and `daemon stop`
// all read what is already in the cache, and demanding $LULE_W from them made every one of them
// fail on a machine that has no wallpaper directory configured at all.
pub fn concatinate(a &Args, mut scheme Scheme, needs_image bool) {
	temp_concatinate(mut scheme)
	defs_concatinate(mut scheme)
	envi_concatinate(mut scheme)
	args_concatinate(a, mut scheme)
	pipe_concatinate(mut scheme)

	// Scripts survive in the cached scheme, so clearing $LULE_S does not stop them running — the
	// list was already persisted by an earlier run. This is the switch that actually does.
	if a.present['no-scripts'] || a.present['n'] {
		scheme.scripts = []
	}

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

	if needs_image && scheme.image == '' && scheme.walldir == '' {
		eprintln('${red_bold('error:')} Environment variable ${yellow("'\$LULE_W'")} is empty')
		eprintln('${red_bold('error:')} Argument option ${yellow("'--wallpath'")} is not set')
		eprintln('${red_bold('error:')} Image argument ${yellow("'--image'")} is not given')
		eprintln('\n${yellow('USAGE')}\n\tlule help <subcommands>...\n\nFor more information try ${blue('--help')}')
		exit(1)
	}
}

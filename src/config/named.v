module config

import os
import color
import ui
import paths

// Loads a named scheme from the configs directory: a file of hex colours, one per line, blank
// lines and `#`-comments ignored. This is what makes `--configs` and `--scheme` mean something;
// before, both were parsed, stored and never read.
pub fn named_scheme(config_dir string, name string) []string {
	if config_dir == '' {
		eprintln('${ui.red_bold('error:')} no configs directory; set ${ui.yellow('$LULE_C')} or pass ${ui.yellow('--configs')}')
		exit(1)
	}
	mut tried := []string{}
	for candidate in [name, '${name}.txt', '${name}.colors'] {
		path := os.join_path(config_dir, candidate)
		tried << path
		if !os.is_file(path) {
			continue
		}
		mut colors := []string{}
		for line in paths.lines_to_vec(path) {
			// The whole token has to be a colour, not merely start like one — otherwise a
			// comment such as `# abc are the accents` parses as #aabbcc and joins the palette.
			token := line.trim_space().trim_string_left('#')
			if token.len != 3 && token.len != 6 {
				continue
			}
			if token.bytes().any(color.hex_val(it) < 0) {
				continue
			}
			colors << color.color_from_hex(token).to_hex(true)
		}
		if colors.len == 0 {
			eprintln('${ui.red_bold('error:')} ${ui.yellow(path)} holds no hex colours')
			exit(1)
		}
		return colors
	}
	eprintln('${ui.red_bold('error:')} no scheme named ${ui.yellow(name)}')
	for path in tried {
		eprintln('${ui.red_bold('error:')}   looked in ${path}')
	}
	exit(1)
}

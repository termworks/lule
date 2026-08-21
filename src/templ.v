module main

import os

pub fn generate_template(original string, replaced string, scheme &Scheme) ! {
	content := file_to_string(original)!
	rendered, problems := render(content, template_context(scheme))
	for problem in problems {
		eprintln('${yellow('warning:')} ${original}: ${problem}')
	}
	write_to_file(replaced, rendered)
}

pub fn pattern_generation(scheme &Scheme) {
	for p in scheme.patterns {
		if os.exists(p.from) && os.exists(p.to) {
			generate_template(p.from, p.to, scheme) or {
				println('failed generating ${p.from} -> ${err}')
				continue
			}
			println('generating :${p.from} into: ${p.to}')
		} else {
			println('${p.from} or ${p.to} is not a valid file')
		}
	}
}

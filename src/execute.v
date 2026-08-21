module main

import os

pub fn command_execution(scheme &Scheme) {
	for s in scheme.scripts {
		if os.exists(s) {
			os.execute('bash -c ${os.quoted_path(s)}')
			println('running: ${s}')
		} else {
			println('${s} is not a valid file')
		}
	}
}

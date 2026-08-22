module ui

import os
import term

// How lule speaks to a terminal: the colours it prints messages in, and whether anyone is there
// to read them. A leaf module - it knows nothing about colour schemes, so everything else is free
// to import it.

pub fn red_bold(s string) string {
	return term.bold(term.red(s))
}

pub fn yellow(s string) string {
	return term.yellow(s)
}

pub fn blue(s string) string {
	return term.blue(s)
}

pub fn term_size() (int, int) {
	cols, rows := term.get_terminal_size()
	if cols <= 0 || rows <= 0 {
		return 80, 24
	}
	return cols, rows
}

pub fn is_tty_stdout() bool {
	return os.is_atty(1) > 0
}

pub fn is_tty_stdin() bool {
	return os.is_atty(0) > 0
}

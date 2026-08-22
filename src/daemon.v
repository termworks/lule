module main

import config
import paths
import ui
import os
import time
import cmd

fn C.mkfifo(path &char, mode u32) int

fn C.setsid() int

fn ensure_fifo(path string) ! {
	if os.exists(path) {
		if os.is_file(path) {
			os.rm(path) or {}
		} else {
			return
		}
	}
	if C.mkfifo(&char(path.str), 0o644) != 0 {
		return error('could not create fifo at ${path}')
	}
}

// os.read_file sizes with stat, which reports 0 for a fifo - read the fd directly
fn read_fifo_blocking(path string) !string {
	mut f := os.open(path)!
	defer {
		f.close()
	}
	mut content := []u8{}
	mut buf := []u8{len: 4096}
	for {
		n := f.read(mut buf) or { break }
		if n <= 0 {
			break
		}
		content << buf[..n]
	}
	return content.bytestr()
}

// Each open blocks until a writer connects, then one message is yielded
fn read_pipe(pipe_name string, ch chan string) {
	for {
		ensure_fifo(pipe_name) or {
			time.sleep(time.second)
			continue
		}
		content := read_fifo_blocking(pipe_name) or {
			time.sleep(100 * time.millisecond)
			continue
		}
		if content.trim_space() != '' {
			ch <- content
		}
	}
}

fn time_to_sleep(seconds int, ch chan bool) {
	for {
		time.sleep(seconds * time.second)
		ch <- true
	}
}

fn detach() ! {
	pid := os.fork()
	if pid > 0 {
		exit(0)
	}
	C.setsid()
	second := os.fork()
	if second > 0 {
		exit(0)
	}
	paths.write_to_file(paths.temp_path('lule.pid'), '${os.getpid()}')
	os.chdir('/tmp') or {}
}

fn daemoned(mut scheme config.Scheme, mut hooks config.Hooks) {
	// Two daemons share one fifo, so each message goes to whichever happens to be reading and the
	// wallpaper timers fight each other. Refusing the second is the only sane outcome.
	if other := running_daemon_other_than(os.getpid()) {
		eprintln('${ui.red_bold('error:')} a lule daemon is already running (pid ${other})')
		eprintln('${ui.red_bold('error:')} stop it with ${ui.yellow('lule daemon -- stop')}')
		exit(1)
	}
	// `detach` writes this before forking; `start` stays in the foreground and would otherwise
	// leave `daemon -- stop` with nothing to find.
	paths.write_to_file(paths.temp_path('lule.pid'), '${os.getpid()}')

	pipe_name := paths.temp_path('lule_pipe')
	if os.is_file(pipe_name) {
		os.rm(pipe_name) or {}
	}

	pipe_ch := chan string{cap: 8}
	time_ch := chan bool{cap: 8}

	spawn read_pipe(pipe_name, pipe_ch)
	spawn time_to_sleep(scheme.looop, time_ch)

	write_colors(mut scheme, false, mut hooks)

	tty := ui.is_tty_stdout()
	for {
		if tty {
			println(scheme.to_json())
		}
		for {
			mut handled := false
			select {
				content := <-pipe_ch {
					trimmed := content.trim_space()
					if trimmed == 'stop' {
						exit(0)
					} else if trimmed == 'next' {
						scheme.image = ''
						write_colors(mut scheme, false, mut hooks)
						handled = true
					} else {
						if sh := config.scheme_from_json(trimmed) {
							scheme.modi(sh)
							if tty {
								println(scheme.theme)
							}
							write_colors(mut scheme, false, mut hooks)
							handled = true
						} else {
							if tty {
								println('${content} \n\n^^^ is not a valid json')
							}
						}
					}
				}
				_ := <-time_ch {
					scheme.image = ''
					write_colors(mut scheme, false, mut hooks)
					handled = true
				}
			}
			if handled {
				break
			}
		}
	}
}

// The pid of a running daemon, or 0. A pidfile alone is not evidence: a killed daemon leaves one
// behind, and the pid may since have been handed to something else.
fn running_daemon() int {
	pid := (paths.file_to_string(paths.temp_path('lule.pid')) or { return 0 }).trim_space().int()
	if pid <= 0 || !os.exists('/proc/${pid}') {
		return 0
	}
	// Confirm it is lule and not whatever inherited the number.
	name := os.read_file('/proc/${pid}/comm') or { return 0 }
	return if name.trim_space() == 'lule' { pid } else { 0 }
}

// As running_daemon, but ignoring one pid — the caller's own, since `detach` has already written
// its pidfile by the time the daemon body checks for a rival.
fn running_daemon_other_than(self int) ?int {
	pid := running_daemon()
	return if pid != 0 && pid != self { pid } else { none }
}

// Opening a fifo for writing blocks until a reader arrives, so sending to a daemon that is not
// running hangs the terminal for ever. A stale fifo left by a killed daemon is enough to trigger
// it. Checking for the process first turns that into a one-line error.
fn send_to_daemon(message string) {
	if running_daemon() == 0 {
		eprintln('${ui.red_bold('error:')} no lule daemon is running')
		eprintln('${ui.red_bold('error:')} start one with ${ui.yellow('lule daemon -- detach')}')
		exit(1)
	}
	paths.write_to_file(paths.temp_path('lule_pipe'), message)
}

pub fn run_daemon(a &cmd.Args, mut scheme config.Scheme, mut hooks config.Hooks) {
	match a.action {
		'start' {
			daemoned(mut scheme, mut hooks)
		}
		'detach' {
			detach() or {
				eprintln('${ui.red_bold('error:')} ${err}')
				exit(1)
			}
			daemoned(mut scheme, mut hooks)
		}
		'next' {
			send_to_daemon('next')
		}
		'stop' {
			send_to_daemon('stop')
		}
		'status' {
			pid := running_daemon()
			if pid == 0 {
				println('lule daemon: not running')
				exit(1)
			}
			println('lule daemon: running (pid ${pid})')
		}
		else {
			eprintln('${ui.red_bold('error:')} daemon action must be one of start|stop|next|detach|status')
			exit(1)
		}
	}
}

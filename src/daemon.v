module main

import os
import time

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
	write_to_file(temp_path('lule.pid'), '${os.getpid()}')
	os.chdir('/tmp') or {}
}

fn daemoned(mut scheme Scheme) {
	pipe_name := temp_path('lule_pipe')
	if os.is_file(pipe_name) {
		os.rm(pipe_name) or {}
	}

	pipe_ch := chan string{cap: 8}
	time_ch := chan bool{cap: 8}

	spawn read_pipe(pipe_name, pipe_ch)
	spawn time_to_sleep(scheme.looop, time_ch)

	write_colors(mut scheme, false)

	tty := is_tty_stdout()
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
						write_colors(mut scheme, false)
						handled = true
					} else {
						if sh := scheme_from_json(trimmed) {
							scheme.modi(sh)
							if tty {
								println(scheme.theme)
							}
							write_colors(mut scheme, false)
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
					write_colors(mut scheme, false)
					handled = true
				}
			}
			if handled {
				break
			}
		}
	}
}

pub fn run_daemon(a &Args, mut scheme Scheme) {
	pipe_name := temp_path('lule_pipe')
	match a.action {
		'start' {
			daemoned(mut scheme)
		}
		'detach' {
			detach() or {
				eprintln('${red_bold('error:')} ${err}')
				exit(1)
			}
			daemoned(mut scheme)
		}
		'next' {
			write_to_file(pipe_name, 'next')
		}
		'stop' {
			write_to_file(pipe_name, 'stop')
		}
		else {
			eprintln('${red_bold('error:')} daemon action must be one of start|stop|next|detach')
			exit(1)
		}
	}
}

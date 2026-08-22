module main

import config
import os

fn scheme_with_colors(patterns []config.Pattern) config.Scheme {
	mut scheme := config.Scheme{
		theme:    'dark'
		pigments: ['#123456', '#654321']
		patterns: patterns
	}
	scheme.colors = get_all_colors(mut scheme)
	return scheme
}

// The output is what lule is there to create; requiring it to exist first meant a template could
// never render the first time.
fn test_a_template_renders_into_an_output_that_does_not_exist_yet() {
	dir := os.join_path(os.temp_dir(), 'lule_templ_new_${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	input := os.join_path(dir, 'in.ini')
	os.write_file(input, 'bg={{ background.hex }}\n') or { panic(err) }

	// Two levels down, so the parent has to be created as well.
	output := os.join_path(dir, 'kitty', 'colors.ini')
	scheme := scheme_with_colors([config.Pattern{input, output}])
	pattern_generation(&scheme)

	rendered := os.read_file(output) or { panic('nothing was written to ${output}: ${err}') }
	assert rendered.starts_with('bg=#')
	assert !rendered.contains('{{')
}

fn test_an_existing_output_is_still_overwritten() {
	dir := os.join_path(os.temp_dir(), 'lule_templ_old_${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	input := os.join_path(dir, 'in.ini')
	output := os.join_path(dir, 'out.ini')
	os.write_file(input, 'bg={{ background.hex }}\n') or { panic(err) }
	os.write_file(output, 'stale') or { panic(err) }

	scheme := scheme_with_colors([config.Pattern{input, output}])
	pattern_generation(&scheme)
	assert (os.read_file(output) or { '' }).starts_with('bg=#')
}

// A missing input is the one thing that cannot be recovered from, and it is skipped rather than
// being fatal - the other templates have nothing to do with it.
fn test_a_missing_input_is_skipped_not_fatal() {
	dir := os.join_path(os.temp_dir(), 'lule_templ_missing_${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	good := os.join_path(dir, 'good.ini')
	os.write_file(good, 'bg={{ background.hex }}\n') or { panic(err) }
	out := os.join_path(dir, 'good.out')

	scheme := scheme_with_colors([
		config.Pattern{os.join_path(dir, 'absent.ini'), os.join_path(dir, 'absent.out')},
		config.Pattern{good, out},
	])
	pattern_generation(&scheme)

	assert !os.exists(os.join_path(dir, 'absent.out'))
	assert (os.read_file(out) or { '' }).starts_with('bg=#')
}

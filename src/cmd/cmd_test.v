module cmd

fn test_subcommand_and_trailing_action() {
	a := parse_args(['create', '--image=wall.png', '--', 'set'])
	assert a.subcommand == 'create'
	assert a.action == 'set'
	assert a.flags['image'] or { '' } == 'wall.png'
}

fn test_action_without_the_separator() {
	// `lule create set` means the same as `lule create -- set`; scripts write both.
	a := parse_args(['create', 'set'])
	assert a.subcommand == 'create'
	assert a.action == 'set'
}

fn test_subcommand_prefix_inference() {
	// clap's InferSubcommands, which the shell aliases in the wild depend on.
	assert parse_args(['crea', '--', 'set']).subcommand == 'create'
	assert parse_args(['dae', '--', 'stop']).subcommand == 'daemon'
	assert parse_args(['col']).subcommand == 'colors'
	// `c` is ambiguous between create, colors and config, so it resolves to nothing.
	assert parse_args(['c']).subcommand == ''
}

fn test_flag_aliases_are_normalised() {
	assert parse_args(['create', '--source=x.png']).flags['image'] or { '' } == 'x.png'
	assert parse_args(['create', '--path=/w']).flags['wallpath'] or { '' } == '/w'
}

fn test_repeatable_flags_accumulate() {
	a := parse_args(['--pattern=a:b', '--pattern=c:d', '--script=/s1', '--script=/s2', 'test'])
	assert a.multi['pattern'].len == 2
	assert a.multi['pattern'][0] == 'a:b'
	assert a.multi['pattern'][1] == 'c:d'
	assert a.multi['script'].len == 2
	assert a.subcommand == 'test'
}

fn test_short_flags_are_split() {
	a := parse_args(['colors', '-g'])
	assert a.subcommand == 'colors'
	assert a.present['g']
}

fn test_long_flags_without_a_value_are_present() {
	a := parse_args(['--help'])
	assert a.present['help']
	assert a.subcommand == ''
}

fn test_values_may_contain_separators() {
	// Paths hold colons and equals signs; only the first `=` separates name from value.
	a := parse_args(['--pattern=/in.tpl:/out.conf'])
	assert a.multi['pattern'][0] == '/in.tpl:/out.conf'
	b := parse_args(['create', '--image=/a=b/c.png'])
	assert b.flags['image'] or { '' } == '/a=b/c.png'
}

fn test_everything_after_the_separator_is_the_action() {
	a := parse_args(['daemon', '--loop=10', '--', 'detach'])
	assert a.subcommand == 'daemon'
	assert a.flags['loop'] or { '' } == '10'
	assert a.action == 'detach'
}

fn test_empty_argv_is_inert() {
	a := parse_args([])
	assert a.subcommand == ''
	assert a.action == ''
	assert a.flags.len == 0
}

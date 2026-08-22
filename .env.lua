-- lule's directory environment. Loaded when you `cd` here, unloaded when you leave.
--
-- Inert until `direnv allow`, and allowing it hashes the *contents* — so editing this file revokes
-- the allowance and you will be asked again.

-- The flake's dev shell, without entering one: V, a C compiler for it to hand its output to, and
-- glibc's static output so `-static` can find libc.a. The slow line here; everything below is
-- instant.
oslo.direnv.nix_develop()

-- The binary this repository builds, ahead of anything installed, so `lule` is the one from this
-- checkout rather than the one in ~/.local/bin. Idempotent, so a reload does not grow $PATH.
oslo.direnv.path_add("./target")

-- Where the checkout is, for scripts that need to find their way back to the top.
oslo.env.set("TOP_HEAD", oslo.sys.pwd())

-- A token in the environment is a token in every child process. `nix` and `gh` both read this one,
-- and neither needs it for anything done in here.
oslo.env.unset("GITHUB_TOKEN")

-- lule's own inputs, pointed at the checkout rather than at the real ones. A test build writes its
-- cache under target/ rather than over the desktop's, and $LULE_W on this machine points at a
-- directory that does not exist, which turns a daemon into an error about a missing wallpaper
-- folder.
oslo.env.set("LULE_W", oslo.sys.pwd() .. "/resources")
oslo.env.set("LULE_A", oslo.sys.pwd() .. "/target/cache")

-- The commands this repository is driven by. All unload with the directory, so they cannot fire
-- the wrong project's build.
oslo.env.set_alias("_b", "make build")
oslo.env.set_alias("_c", "make check")
oslo.env.set_alias("_r", "make run")
oslo.env.set_alias("_t", "make test")
oslo.env.set_alias("_v", "make verify")
oslo.env.set_alias("_i", "make install")

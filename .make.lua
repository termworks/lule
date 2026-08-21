-- lule's build, as recipes.
--
--   make              the recipes, with what each of them says it does
--   make build        the static release binary
--   make dev          the fast inner loop
--   make verify       the whole local gate
--
-- At an oslo prompt in this directory `make` is enough; everywhere else it is `oslo make`.

local make = oslo.make

---------------------------------------------------------------------------- what the build is

-- `v.mod` is the one place the name and the version are written down, and `release` rewrites it
-- there. Two patterns rather than a helper script: the file is four lines of Lua-ish already.
local manifest = oslo.fs.read("v.mod")
local NAME = manifest:match("name:%s*'([^']+)'")
local VERSION = manifest:match("version:%s*'([^']+)'")
assert(NAME and VERSION, "v.mod is missing a name or a version")

local SRC = "src"
local BIN = "target/" .. NAME

-- `dev` writes somewhere else on purpose. Sharing the path with `build` means an unoptimised,
-- dynamically linked binary satisfies `build`'s declared output, so `build` reports "up to date"
-- and `check-static` never runs — a verify that passes while target/lule is the debug build.
local DEV_BIN = "target/" .. NAME .. "-dev"
local PREFIX = os.getenv("PREFIX") or (os.getenv("HOME") .. "/.local")

-- Every `.v` the build depends on, for the recipes that declare staleness.
local SOURCES = { "src/*.v", "src/**/*.v", "v.mod" }

-- `-static` needs libc.a, which nixpkgs keeps in glibc's `static` output. The dev shell exports
-- where that is; outside it, plain `-static` is right on any distribution that ships libc.a in
-- its libc development package.
local function static_flags()
  local glibc = os.getenv("GLIBC_STATIC")
  if glibc and glibc ~= "" then
    return "-static -L" .. glibc .. "/lib"
  end
  return "-static"
end

---------------------------------------------------------------------------- building

-- The `Makefile` this replaced printed a banner on every target with `$(info …)`, including the
-- ones whose whole output was meant to be piped. A recipe is the honest place for it: ask, and it
-- answers.
make.recipe{ name = "version", desc = "what this checkout calls itself",
             run = function() print(("%s v%s"):format(NAME, VERSION)) end }

make.recipe{
  name = "build",
  desc = "the static release binary",
  inputs = SOURCES,
  outputs = { BIN },
  stale = "content",
  run = function()
    sh.mkdir("-p", "target")
    -- A binary linked against a /nix/store glibc stops existing the day `nix-collect-garbage`
    -- runs. lule is called from wallpaper hooks and login scripts, so it is one file that runs
    -- anywhere.
    sh.v("-prod", "-cflags", static_flags(), SRC, "-o", BIN)
    make.run("check-static")
    print(("%s  %.2f MB"):format(BIN, oslo.fs.stat(BIN).size / 1048576))
  end,
}

make.alias("b", "build")

make.recipe{
  name = "check-static",
  desc = "fail if the release ELF asks for a loader",
  run = function()
    -- That there *is* an ELF, before asking anything about it. An interrupted build leaves a
    -- zero-byte target/lule, and readelf on an empty file prints nothing — so "no INTERP, no
    -- NEEDED" came back true and the recipe reported a successful static build of nothing.
    local info = oslo.fs.stat(BIN)
    assert(info and info.size > 0, BIN .. " is missing or empty; the build did not finish")

    -- "Static" is a claim about the ELF, so check the ELF. `ldd` is not enough: it prints
    -- "statically linked" for a binary that still has an INTERP and will not start.
    local segments = oslo.run{ "readelf", "-l", BIN, capture = true }
    assert(segments.ok, "readelf could not read " .. BIN)
    assert(not (segments.out or ""):find("program interpreter"),
           BIN .. " requests a dynamic loader; it is not static")
    local dynamic = oslo.run{ "readelf", "-d", BIN, capture = true }
    assert(not (dynamic.out or ""):find("NEEDED"),
           BIN .. " has NEEDED entries; it is not static")
    print("static: no INTERP, no NEEDED")
  end,
}

make.recipe{
  name = "dev",
  desc = "the fast inner loop: an unoptimised build",
  run = function()
    sh.mkdir("-p", "target")
    sh.v(SRC, "-o", DEV_BIN)
  end,
}

make.recipe{
  name = "strip",
  desc = "build, then strip the symbols out of it",
  deps = { "build" },
  run = function()
    sh.strip(BIN)
    print(("%s  %.2f MB stripped"):format(BIN, oslo.fs.stat(BIN).size / 1048576))
  end,
}

make.recipe{ name = "clean", desc = "remove the build artifacts",
             run = function() sh.rm("-rf", "target") end }

make.recipe{ name = "compile", desc = "clean, then build", deps = { "clean", "build" } }
make.alias("c", "compile")

---------------------------------------------------------------------------- the gate

make.recipe{ name = "check", desc = "vet the source",
             run = function() sh.v("vet", SRC) end }

make.recipe{ name = "fmt", desc = "format the source",
             run = function() sh.v("fmt", "-w", SRC) end }

make.recipe{ name = "fmt-check", desc = "fail if anything is unformatted",
             run = function() sh.v("fmt", "-verify", SRC) end }

-- V's own test runner covers any `*_test.v`; the smoke test is what actually proves the binary
-- works, because the interesting failures here are runtime ones — a wallpaper that will not
-- decode, a cache directory that is not written.
make.recipe{
  name = "test",
  desc = "the V tests, then a smoke test of the built binary",
  deps = { "build" },
  run = function()
    -- Strict `sh`, so a failing V test fails the gate. `oslo.run` here would swallow the status.
    sh.v("test", SRC)
    make.run("smoke")
  end,
}
make.alias("t", "test")

make.recipe{
  name = "smoke",
  desc = "generate a palette from a known image and check the output",
  deps = { "build" },
  run = function()
    -- A handle rather than a path, and `<close>` is what removes the directory when this returns
    -- — including when an assertion below raises.
    local tmp <close> = oslo.fs.mktempdir()
    local cache = tmp.path

    -- LULE_S would run whatever the caller has wired to their real colour-applying script, which
    -- is not something a test gets to do. Empty rather than unset: the env is inherited.
    oslo.env.set("LULE_A", cache)
    oslo.env.set("LULE_S", "")
    local made = oslo.run{ BIN, "create", "--image=resources/theme_dark.png", "--", "set" }
    assert(made.ok, "lule create failed: " .. (made.err or ""))

    local colors = oslo.fs.read(cache .. "/colors")
    local count = select(2, colors:gsub("\n", "\n")) + 1
    assert(count == 256, ("expected 256 colours, got %d"):format(count))
    assert(colors:match("^#%x%x%x%x%x%x"), "first line is not a hex colour")
    print(("smoke: %d colours from theme_dark.png"):format(count))
  end,
}

make.recipe{
  name = "verify",
  desc = "the whole local gate",
  deps = { "fmt-check", "check", "test", "build" },
}
make.alias("v", "verify")

---------------------------------------------------------------------------- running

make.recipe{
  name = "run",
  desc = "run the dev binary; arguments are passed through",
  deps = { "dev" },
  -- The runner claims every `--flag` for the recipe, and `--` does not escape them, so passing
  -- one through means putting it back together from the parsed table. Flag order is lost doing
  -- that — harmless here because lule's own parser reads flags positionally-independently, and
  -- the trailing action arrives in `rest` either way.
  --
  -- `lule` is on $PATH inside this directory anyway (see `.env.lua`), so the release binary is
  -- always reachable without going through a recipe.
  run = function(a)
    local argv = { DEV_BIN }
    for key, value in pairs(a) do
      if key ~= "rest" then
        if value == true then
          argv[#argv + 1] = "--" .. key
        elseif type(value) == "string" then
          argv[#argv + 1] = "--" .. key .. "=" .. value
        end
      end
    end
    for _, word in ipairs(a.rest or {}) do argv[#argv + 1] = word end
    local ran = oslo.run(argv)
    os.exit(ran.status or 0)
  end,
}
make.alias("r", "run")

---------------------------------------------------------------------------- installing

make.recipe{
  name = "install",
  desc = "put the release binary in $PREFIX/bin",
  deps = { "build" },
  run = function()
    local dest = (os.getenv("DESTDIR") or "") .. PREFIX .. "/bin"
    sh.install("-d", dest)
    sh.install("-m", "755", BIN, dest .. "/" .. NAME)
    print("installed " .. dest .. "/" .. NAME)
  end,
}

make.recipe{
  name = "uninstall",
  desc = "take it back out of $PREFIX/bin",
  run = function()
    local dest = (os.getenv("DESTDIR") or "") .. PREFIX .. "/bin/" .. NAME
    sh.rm("-f", dest)
    print("removed " .. dest)
  end,
}

---------------------------------------------------------------------------- the book

make.recipe{
  name = "docs",
  desc = "build the mdbook into docs/",
  run = function()
    assert(oslo.run{ "sh", "-c", "command -v mdbook" }.ok,
           "mdbook is not installed, and the book needs it")
    sh.mdbook("build", "book", "--dest-dir", "docs")
  end,
}

---------------------------------------------------------------------------- releasing

-- Delegated rather than written out here, the same way oslo's own `.make.lua` does it. `git-rel`
-- bumps the version through `veri`, writes the changelog with git-cliff, tags, pushes, merges
-- develop into main and cuts the GitHub release — and it is the same sequence for every project,
-- so having a second copy of it here is how the two drift.
--
-- `veri` is what knows about V: it reads and writes both `v.mod` and the `const version` in
-- `src/cli.v`, so a release cannot leave `lule --version` disagreeing with the manifest.
make.recipe{
  name = "release",
  desc = "cut a version: --type patch | minor | major | M.m.p",
  params = { { "--type", desc = "patch | minor | major | M.m.p" } },
  run = function(a)
    assert(oslo.run{ "sh", "-c", "command -v git-rel" }.ok,
           "git-rel is not installed; install it first")
    assert(type(a.type) == "string",
           "which release? make release --type patch|minor|major|M.m.p")
    sh.git("rel", a.type)
  end,
}

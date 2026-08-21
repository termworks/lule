{
  description = "lule V development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # `-static` needs libc.a and libdl.a, which nixpkgs keeps in a separate output rather
        # than in the default glibc.
        #
        # Deliberately *not* a `buildInputs` entry. As one it goes into NIX_LDFLAGS, which the
        # compiler wrapper applies to every link — including the ordinary dynamic one `make dev`
        # does, which then resolves `memset` out of the static libc and dies at startup with
        # "IFUNC symbol 'memset' ... creates an unsatisfiable circular dependency". Only the
        # static build wants this path, so only the static build is given it: `.make.lua` reads
        # GLIBC_STATIC and passes `-L` itself.
        staticEnv = { GLIBC_STATIC = pkgs.glibc.static; };

        # Everything needed to compile and check the source, and nothing else. CI enters this
        # rather than the full shell so it does not pull mdbook, gh and git-cliff — none of which
        # it uses — across the network on every job.
        buildTools = [
          # V compiles to C and then invokes a C compiler, so the toolchain is both of these.
          # vlib ships `stbi`, so image decoding needs nothing else here.
          pkgs.vlang
          pkgs.gcc

          # `strip` and `readelf` for the release binary, and `file` for the staticness check.
          # readelf is the one that actually decides it: `ldd` prints "statically linked" for a
          # binary that still carries an INTERP and will not start.
          pkgs.binutils
          pkgs.file
        ];
      in
      {
        # The version of V is pinned in exactly one place: this flake's nixpkgs, through
        # flake.lock. CI enters `.#ci` rather than installing a V of its own, so there is no
        # second pin that can drift out from under `v fmt -verify`.
        devShells.ci = pkgs.mkShell (staticEnv // { packages = buildTools; });

        # Just the book. Separate from `.#ci` so the docs workflow does not pull a C toolchain it
        # never invokes, and separate from `.#default` so it does not pull gh and git-cliff.
        devShells.docs = pkgs.mkShell { packages = [ pkgs.mdbook ]; };

        # The CI toolchain plus what a person needs to release and to build the book.
        devShells.default = pkgs.mkShell (staticEnv // {
          packages = buildTools ++ [
            pkgs.git-cliff
            pkgs.gh
            pkgs.mdbook
          ];
        });
      }
    );
}

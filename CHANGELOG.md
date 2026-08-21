# Changelog

## [0.5.1] - 2026-08-21

### <!-- 0 -->⛰️  Features

- Add arithmetic and range loops to templates
- Add template includes with cycle detection
- Add case filters to the template engine
- Colour-aware template engine with filters and control flow

### <!-- 3 -->📚 Documentation

- Remove a duplicated note about the case filters
- Document the template engine

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Back out the accidental v0.6.0 release
- Take the toolchain from the flake instead of a second pin

## [0.5.0] - 2026-08-21

### <!-- 0 -->⛰️  Features

- Add named schemes, no-scripts and wallpaper fallback
- Add palette tuning, seeding and json output

### <!-- 1 -->🐛 Bug Fixes

- Guarantee sixteen distinguishable ansi colors
- Build the cache from this run and refuse symlinked writes
- Bound stdin reads and detect a missing daemon
- Only require a wallpaper source when generating colors

### <!-- 2 -->🚜 Refactor

- Port from rust to v

### <!-- 6 -->🧪 Testing

- Sweep delta-e symmetry over many pairs
- Report the values when delta-e symmetry fails

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Pin mdbook and fix the book output path
- Add a dry run path to the release workflow
- Install pinned v prebuilt directly
- Install the stable v release prebuilt
- Pin the v toolchain instead of chasing latest
- Build and release linux amd64 and arm64 binaries
- Replace make and devbox with oslo recipes and a flake

### Build

- Delegate release to git-rel

## [0.4.2] - 2025-11-11

## [0.4.1] - 2025-11-11

### <!-- 3 -->📚 Documentation

- Refactor daemon for TTY-less operation and service integration

## [0.4.0] - 2025-11-09

### <!-- 0 -->⛰️  Features

- Update dev dependencies and reorganize generation module

### <!-- 5 -->🎨 Styling

- Improve color contrast of light themes

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Downgrade package version to 0.3.9

## [0.4.0] - 2025-11-09

### <!-- 5 -->🎨 Styling

- Improve color contrast of light themes

## [0.3.2] - 2025-11-09

### <!-- 2 -->🚜 Refactor

- Introduce Makefile for development and refactor file handling

## [0.3.1] - 2025-04-25

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Refactor build and release processes

## [0.3.0] - 2025-03-19

### <!-- 0 -->⛰️  Features

- Enhance color generation functionality and streamline code

## [0.2.6] - 2024-02-07

### <!-- 0 -->⛰️  Features

- Decided to use "tera" at the end as template engine
- Swap templr with handlebars package
- Improve color generation with `norandom` flag

## [0.2.5] - 2024-02-07

### <!-- 2 -->🚜 Refactor

- Refactor color generation and gradient access

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Refactor file structure for better organization

## [0.2.4] - 2024-02-07

### <!-- 0 -->⛰️  Features

- Refactor color generation and scheme in gen/generate.rs

## [0.2.0] - 2024-02-07

### <!-- 3 -->📚 Documentation

- Update README.md with required environment variables and example code

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Refactor color generation and file organization
- Configure changelog generation, devbox setup, and aliases

### ADD

- Added ryon for paralell processing

### IMPORTANT

- Removed WRITE struct

<!-- WARP -->

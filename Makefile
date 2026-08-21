SHELL := /bin/bash

MAKEFLAGS := $(filter-out w --print-directory,$(MAKEFLAGS))
MAKEFLAGS += --no-print-directory

PROJECT_NAME := $(shell grep -Po "^\tname: '\K[^']+" v.mod)
PROJECT_CAP  := $(shell echo $(PROJECT_NAME) | tr '[:lower:]' '[:upper:]')
LATEST_TAG   ?= $(shell git describe --tags --abbrev=0 2>/dev/null)
TOP_DIR      := $(CURDIR)
BUILD_DIR    := $(TOP_DIR)/target
SRC_DIR      := $(TOP_DIR)/src
BIN          := $(BUILD_DIR)/$(PROJECT_NAME)

V ?= v

# Static linking needs libc.a; nix users get it from glibc.static
GLIBC_STATIC ?= $(shell nix build --no-link --print-out-paths nixpkgs\#glibc.static 2>/dev/null | tail -1)
ifneq ($(GLIBC_STATIC),)
STATIC_FLAGS := -static -L$(GLIBC_STATIC)/lib
else
STATIC_FLAGS := -static
endif

ifeq ($(PROJECT_NAME),)
$(error Error: project name not found in v.mod)
endif

$(info ------------------------------------------)
$(info Project: $(PROJECT_NAME))
$(info ------------------------------------------)

.PHONY: build b static dev config c reconfig run r test t help h clean docs release

build: static

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Fully static release binary - no runtime dependencies at all
static: $(BUILD_DIR)
	@$(V) -prod -cflags "$(STATIC_FLAGS)" $(SRC_DIR) -o $(BIN)
	@file $(BIN) | grep -q "statically linked" \
		&& echo "built $(BIN) (static, $$(du -h $(BIN) | cut -f1))" \
		|| echo "built $(BIN) (DYNAMIC - glibc static libs missing)"

dev: $(BUILD_DIR)
	@$(V) $(SRC_DIR) -o $(BIN)

b: build

config:
	@$(V) vet $(SRC_DIR)

reconfig: clean config

c: config

run: dev
	@$(BIN)

r: run

test: dev
	@$(V) test $(SRC_DIR) || true
	@echo "--- smoke test ---"
	@LULE_A=$$(mktemp -d) LULE_S= $(BIN) create --image=resources/theme_dark.png -- set
	@LULE_A=$$(mktemp -d) LULE_S= $(BIN) --version

t: test

help:
	@echo
	@echo "Usage: make [target]"
	@echo
	@echo "Available targets:"
	@echo "  build        Build static release binary (default)"
	@echo "  dev          Build unoptimised binary for development"
	@echo "  config       Vet the source"
	@echo "  reconfig     Clean and vet"
	@echo "  run          Run the main executable"
	@echo "  test         Run tests"
	@echo "  docs         Build documentation (TYPE=mdbook)"
	@echo "  release      Create a new release (TYPE=patch|minor|major)"
	@echo

h : help

clean:
	@echo "Cleaning build directory..."
	@rm -rf $(BUILD_DIR)
	@echo "Build directory cleaned."

docs:
ifeq ($(TYPE),mdbook)
	@command -v mdbook >/dev/null 2>&1 || { echo "mdbook is not installed. Please install it first."; exit 1; }
	@mdbook build $(TOP_DIR)/book --dest-dir $(TOP_DIR)/docs
	@git add --all && git commit -m "docs: building website/mdbook"
else
	$(error Invalid documentation type. Use 'make docs TYPE=mdbook')
endif

release:
	@if [ -z "$(TYPE)" ]; then \
		echo "Release type not specified. Use 'make release TYPE=[patch|minor|major]'"; \
		exit 1; \
	fi; \
	CURRENT_VERSION=$$(grep -Po "^\tversion: '\K[^']+" v.mod); \
	IFS='.' read -r MAJOR MINOR PATCH <<< "$$CURRENT_VERSION"; \
	case "$(TYPE)" in \
		major) MAJOR=$$((MAJOR+1)); MINOR=0; PATCH=0 ;; \
		minor) MINOR=$$((MINOR+1)); PATCH=0 ;; \
		patch) PATCH=$$((PATCH+1)); ;; \
		*) echo "Invalid release type. Use patch, minor or major."; exit 1 ;; \
	esac; \
	version="$$MAJOR.$$MINOR.$$PATCH"; \
	if [ -n "$(LATEST_TAG)" ]; then \
		changelog=$$(git cliff $(LATEST_TAG)..HEAD --strip all); \
		git cliff --tag $$version $(LATEST_TAG)..HEAD --prepend CHANGELOG.md; \
	else \
		changelog=$$(git cliff --unreleased --strip all); \
		git cliff --tag $$version --unreleased --prepend CHANGELOG.md; \
	fi; \
	sed -i "s/^\tversion: '.*'/\tversion: '$$version'/" v.mod; \
	sed -i "s/^pub const version = '.*'/pub const version = '$$version'/" src/cli.v; \
	git add -A && git commit -m "chore(release): prepare for $$version"; \
	echo "$$changelog"; \
	git tag -a $$version -m "$$version" -m "$$changelog"; \
	git push --follow-tags --force --set-upstream origin develop; \
	gh release create $$version --notes "$$changelog"

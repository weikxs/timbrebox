# Common tasks. `make check` is what CI runs; run it before every pull request.
.DEFAULT_GOAL := help

APP_DIR := apps/timbrebox_app
CLI_DIR := packages/timbrebox_cli
# The Dart packages, formatted and checked by tools/check.sh.
PACKAGES := packages/timbrebox_core packages/timbrebox_sources packages/timbrebox_playback $(CLI_DIR) $(APP_DIR)
# The version of the app, without the build number (0.1.0+1 -> 0.1.0).
VERSION := $(shell sed -n 's/^version: *\([^+]*\).*/\1/p' $(APP_DIR)/pubspec.yaml)

.PHONY: help
help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: check
check: privacy ## Everything CI runs: privacy, analysis, formatting and tests of every package
	tools/check.sh

.PHONY: privacy
privacy: ## Block real identities, local paths and secrets from being committed
	scripts/check-privacy.sh

.PHONY: analyze
analyze: ## Static analysis of every package
	tools/check.sh analyze

.PHONY: fmt
fmt: ## Format the Dart code
	@for package in $(PACKAGES); do \
		dirs=""; for dir in bin lib test; do [ -d "$$package/$$dir" ] && dirs="$$dirs $$package/$$dir"; done; \
		dart format $$dirs || exit 1; \
	done

.PHONY: fmt-check
fmt-check: ## Fail if any Dart file is not formatted
	tools/check.sh format

.PHONY: test
test: ## Run the tests of every package
	tools/check.sh test

.PHONY: hooks
hooks: ## Install the repository's git hooks (privacy check, Conventional Commits)
	git config core.hooksPath scripts/hooks
	@echo "git hooks installed (scripts/hooks)"

.PHONY: app
app: ## Release build of the desktop app for this machine (macOS, Linux or Windows)
	@case "$$(uname -s)" in \
		Darwin) platform=macos ;; Linux) platform=linux ;; MINGW* | MSYS* | CYGWIN*) platform=windows ;; \
		*) echo "app: unsupported system $$(uname -s)" >&2; exit 1 ;; \
	esac; \
	cd $(APP_DIR) && flutter build "$$platform" --release

.PHONY: package
package: app ## Build the app and package it as a release would, into dist/
	scripts/release/package-bundles.sh $(VERSION) dist

.PHONY: cli
cli: ## Compile the timbrebox and timbrebox_mcp commands into build/cli/
	@mkdir -p build/cli
	cd $(CLI_DIR) && dart pub get
	dart compile exe $(CLI_DIR)/bin/timbrebox.dart -o build/cli/timbrebox
	dart compile exe $(CLI_DIR)/bin/timbrebox_mcp.dart -o build/cli/timbrebox_mcp

.PHONY: clean
clean: ## Remove build output
	cd $(APP_DIR) && flutter clean
	rm -rf build dist

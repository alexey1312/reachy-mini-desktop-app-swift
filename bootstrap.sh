#!/bin/sh
# =============================================================================
# ReachyMini development environment bootstrap
# =============================================================================
# The single entry point for setting up this repo after cloning. Idempotent.
# Installs all pinned tools via the self-contained ./bin/mise and wires git
# hooks. No global mise, brew, or manual tool installs required.
#
# Swift itself is managed by swiftly (https://www.swift.org/swiftly/) via the
# .swift-version file — install swiftly separately if `swift --version`
# doesn't match .swift-version.
# =============================================================================
set -eu
cd "$(dirname "$0")"

echo "==> Trusting mise config"
./bin/mise trust --yes mise.toml

echo "==> Installing pinned tools (swiftformat, swiftlint, hk, dprint, tuist, ...)"
./bin/mise install

echo "==> Wiring git hooks (.githooks via core.hooksPath)"
git config core.hooksPath .githooks
chmod +x .githooks/*

echo "==> Done"
./bin/mise run setup
echo ""
echo "Next steps:"
echo "  ./bin/mise run build   # build the Swift package"
echo "  ./bin/mise run test    # run tests"
echo "  ./bin/mise tasks       # list all tasks"

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
command -v bun >/dev/null || { echo 'Install Bun 1.4.2 or later first' >&2; exit 1; }
bun -e 'const actual = Bun.version.split(".").map(Number); const minimum = [1, 4, 2]; const different = actual.findIndex((part, index) => part !== minimum[index]); if (different !== -1 && actual[different] < minimum[different]) throw new Error("Bun 1.4.2 or later is required")'
command -v cc >/dev/null || { echo 'Install a C compiler (Xcode Command Line Tools or build-essential) first' >&2; exit 1; }
case "$(uname -s)" in
  Linux) command -v bwrap >/dev/null || { echo 'Install bubblewrap first (for example: sudo apt-get install bubblewrap)' >&2; exit 1; } ;;
  Darwin) test -x /usr/bin/sandbox-exec || { echo 'The macOS Seatbelt launcher is unavailable' >&2; exit 1; } ;;
  *) echo 'Selvedge supports Linux and macOS only' >&2; exit 1 ;;
esac
if ! bun scripts/toolchain.mjs >/dev/null 2>&1; then bash scripts/install-bend.sh; fi
bun install --frozen-lockfile --ignore-scripts
bun run build
if command -v pre-commit >/dev/null; then
  pre-commit install
  pre-commit install --hook-type pre-push
else
  printf 'Install pre-commit to enable Git hooks. bun run check and bun run test are also available directly.\n'
fi
printf 'Setup complete. Run bun run start.\n'

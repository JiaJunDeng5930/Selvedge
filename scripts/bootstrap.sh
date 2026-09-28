#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
command -v node >/dev/null || { echo 'Install Node.js 26 or later first' >&2; exit 1; }
node -e 'if (Number(process.versions.node.split(".")[0]) < 26) throw new Error("Node.js 26 or later is required")'
command -v cc >/dev/null || { echo 'Install a C compiler (Xcode Command Line Tools or build-essential) first' >&2; exit 1; }
case "$(uname -s)" in
  Linux) command -v bwrap >/dev/null || { echo 'Install bubblewrap first (for example: sudo apt-get install bubblewrap)' >&2; exit 1; } ;;
  Darwin) test -x /usr/bin/sandbox-exec || { echo 'The macOS Seatbelt launcher is unavailable' >&2; exit 1; } ;;
  *) echo 'Selvedge supports Linux and macOS only' >&2; exit 1 ;;
esac
if ! node scripts/toolchain.mjs >/dev/null 2>&1; then bash scripts/install-bend.sh; fi
npm ci --ignore-scripts
npm run build
if command -v pre-commit >/dev/null; then
  pre-commit install
  pre-commit install --hook-type pre-push
else
  printf 'Install pre-commit to enable Git hooks. npm run check and npm test are also available directly.\n'
fi
printf 'Setup complete. Run npm start.\n'

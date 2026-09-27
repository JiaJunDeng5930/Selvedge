#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# A kernel belongs to one source fingerprint. Worktrees must not overwrite a
# shared executable while another worktree is replaying its committed journal.
mkdir -p .build
printf 'Bend build artifacts remain local to this worktree. Run bash scripts/bootstrap.sh to build.\n'

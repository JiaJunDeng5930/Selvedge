#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
git_common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
main_worktree="$(dirname "${git_common_dir}")"
shared_target="${main_worktree}/target"
worktree_target="${repo_root}/target"

mkdir -p "${shared_target}"

if [[ "${repo_root}" == "${main_worktree}" ]]; then
  printf 'Cargo build cache: %s\n' "${shared_target}"
elif [[ -L "${worktree_target}" && "${worktree_target}" -ef "${shared_target}" ]]; then
  printf 'Cargo build cache already shared: %s\n' "${shared_target}"
elif [[ -e "${worktree_target}" || -L "${worktree_target}" ]]; then
  printf 'Cannot share Cargo build cache: %s already exists. Move it aside before rerunning setup.\n' "${worktree_target}" >&2
  exit 1
else
  # Use a filesystem link so sharing also applies to ordinary Cargo commands and Git hooks.
  ln -s "${shared_target}" "${worktree_target}"
  printf 'Cargo build cache shared with: %s\n' "${shared_target}"
fi

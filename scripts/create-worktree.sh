#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF' >&2
usage: ./scripts/create-worktree.sh <branch-name>
EOF
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "missing required command: ${command_name}" >&2
    exit 1
  fi
}

main() {
  require_command git

  if [[ "$#" -ne 1 ]]; then
    usage
    exit 1
  fi

  local branch_name="$1"
  if ! git check-ref-format --branch "${branch_name}" >/dev/null 2>&1; then
    echo "invalid branch name: ${branch_name}" >&2
    exit 1
  fi

  local common_git_dir
  common_git_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
    echo "create-worktree.sh must run inside a git repository" >&2
    exit 1
  }

  local repo_root
  repo_root="$(cd "${common_git_dir}/.." && pwd -P)"

  cd "${repo_root}"

  if ! git check-ignore -q .worktrees/; then
    echo ".worktrees/ is not ignored. Add it to .gitignore before creating worktrees." >&2
    exit 1
  fi

  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    echo "branch already exists: ${branch_name}" >&2
    exit 1
  fi

  if ! git show-ref --verify --quiet "refs/heads/main"; then
    echo "main branch does not exist locally" >&2
    exit 1
  fi

  local worktree_path=".worktrees/${branch_name}"
  if [[ -e "${worktree_path}" ]]; then
    echo "worktree path already exists: ${worktree_path}" >&2
    exit 1
  fi

  mkdir -p "$(dirname "${worktree_path}")"
  git worktree add "${worktree_path}" -b "${branch_name}" main
  printf 'created worktree: %s\n' "${repo_root}/${worktree_path}"
}

main "$@"

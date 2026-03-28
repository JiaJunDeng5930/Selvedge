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

require_repo_local_worktree_ignore() {
  local ignore_details
  ignore_details="$(git check-ignore -v .worktrees/ 2>/dev/null || true)"
  if [[ -z "${ignore_details}" ]]; then
    echo ".worktrees/ is not ignored. Add it to .gitignore before creating worktrees." >&2
    exit 1
  fi

  local ignore_source
  ignore_source="${ignore_details%%:*}"
  if [[ "${ignore_source}" != ".gitignore" ]]; then
    echo ".worktrees/ must be ignored by the repository .gitignore." >&2
    exit 1
  fi
}

encode_branch_name() {
  local branch_name="$1"
  local branch_hash
  branch_hash="$(printf '%s' "${branch_name}" | git hash-object --stdin)"
  printf 'branch-%s\n' "${branch_hash}"
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

  require_repo_local_worktree_ignore

  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    echo "branch already exists: ${branch_name}" >&2
    exit 1
  fi

  if ! git show-ref --verify --quiet "refs/heads/main"; then
    echo "main branch does not exist locally" >&2
    exit 1
  fi

  local worktree_name
  worktree_name="$(encode_branch_name "${branch_name}")"

  local worktree_path=".worktrees/${worktree_name}"
  if [[ -e "${worktree_path}" ]]; then
    echo "worktree path already exists: ${worktree_path}" >&2
    exit 1
  fi

  mkdir -p .worktrees
  git worktree add --detach "${worktree_path}" main
  git -C "${worktree_path}" switch -c "${branch_name}"
  printf 'created worktree: %s\n' "${repo_root}/${worktree_path}"
}

main "$@"

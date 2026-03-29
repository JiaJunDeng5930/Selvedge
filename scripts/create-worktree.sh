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
  ignore_details="$(git check-ignore -v .worktree/ 2>/dev/null || true)"
  if [[ -z "${ignore_details}" ]]; then
    echo ".worktree/ is not ignored. Add it to .gitignore before creating worktrees." >&2
    exit 1
  fi

  local ignore_source
  ignore_source="${ignore_details%%:*}"
  if [[ "${ignore_source}" != ".gitignore" ]]; then
    echo ".worktree/ must be ignored by the repository .gitignore." >&2
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

  local checkout_root
  checkout_root="$(git rev-parse --path-format=absolute --show-toplevel 2>/dev/null)" || {
    echo "create-worktree.sh must run inside a git repository" >&2
    exit 1
  }

  cd "${checkout_root}"

  require_repo_local_worktree_ignore

  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    echo "branch already exists: ${branch_name}" >&2
    exit 1
  fi

  local base_branch
  base_branch="$(git branch --show-current)"
  if [[ -z "${base_branch}" ]]; then
    echo "create-worktree.sh requires an attached branch checkout" >&2
    exit 1
  fi

  if ! git show-ref --verify --quiet "refs/heads/${base_branch}"; then
    echo "base branch does not exist locally: ${base_branch}" >&2
    exit 1
  fi

  local worktree_name
  worktree_name="$(encode_branch_name "${branch_name}")"

  local worktree_path=".worktree/${worktree_name}"
  if [[ -e "${worktree_path}" ]]; then
    echo "worktree path already exists: ${worktree_path}" >&2
    exit 1
  fi

  mkdir -p .worktree
  git worktree add "${worktree_path}" -b "${branch_name}" "${base_branch}"
  printf 'created worktree: %s\n' "${checkout_root}/${worktree_path}"
}

main "$@"

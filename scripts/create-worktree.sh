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
  ignore_details="$(git -C "$1" check-ignore -v .worktrees/ 2>/dev/null || true)"
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

resolve_storage_root() {
  local repo_root="$1"
  local checkout_root="$2"

  if [[ "${checkout_root}" == "${repo_root}" ]]; then
    printf '%s/.worktrees\n' "${repo_root}"
    return
  fi

  printf '%s.worktrees\n' "${checkout_root}"
}

require_supported_checkout_location() {
  local repo_root="$1"
  local checkout_root="$2"

  if [[ "${checkout_root}" == "${repo_root}" ]]; then
    return
  fi

  case "${checkout_root}" in
    "${repo_root}/.worktrees/"*)
      return
      ;;
  esac

  echo "worktrees must live under ${repo_root}/.worktrees/ when using this helper" >&2
  exit 1
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

  local common_git_dir
  common_git_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
    echo "create-worktree.sh must run inside a git repository" >&2
    exit 1
  }

  local repo_root
  repo_root="$(cd "${common_git_dir}/.." && pwd -P)"

  cd "${checkout_root}"

  require_supported_checkout_location "${repo_root}" "${checkout_root}"
  require_repo_local_worktree_ignore "${repo_root}"

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

  local storage_root
  storage_root="$(resolve_storage_root "${repo_root}" "${checkout_root}")"

  local worktree_path="${storage_root}/${worktree_name}"
  if [[ -e "${worktree_path}" ]]; then
    echo "worktree path already exists: ${worktree_path}" >&2
    exit 1
  fi

  mkdir -p "${storage_root}"
  git worktree add "${worktree_path}" -b "${branch_name}" "${base_branch}"
  printf 'created worktree: %s\n' "${worktree_path}"
}

main "$@"

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

sanitize_branch_name() {
  local branch_name="$1"

  printf '%s' "${branch_name}" \
    | sed -E 's#[^A-Za-z0-9._-]+#-#g; s#-+#-#g; s#(^-+|-+$)##g'
}

main() {
  require_command git

  if [[ "$#" -ne 1 ]]; then
    usage
    exit 1
  fi

  local branch_name="$1"
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "create-worktree.sh must run inside a git repository" >&2
    exit 1
  }

  cd "${repo_root}"

  if ! git check-ignore -q .worktrees/; then
    echo ".worktrees/ is not ignored. Add it to .gitignore before creating worktrees." >&2
    exit 1
  fi

  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    echo "branch already exists: ${branch_name}" >&2
    exit 1
  fi

  local worktree_name
  worktree_name="$(sanitize_branch_name "${branch_name}")"
  if [[ -z "${worktree_name}" ]]; then
    echo "branch name cannot produce an empty worktree directory name" >&2
    exit 1
  fi

  local worktree_path=".worktrees/${worktree_name}"
  if [[ -e "${worktree_path}" ]]; then
    echo "worktree path already exists: ${worktree_path}" >&2
    exit 1
  fi

  mkdir -p .worktrees
  git worktree add "${worktree_path}" -b "${branch_name}"
  printf 'created worktree: %s\n' "${repo_root}/${worktree_path}"
}

main "$@"

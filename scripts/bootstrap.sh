#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly SCRIPT_DIR
readonly REPO_ROOT

apt_run() {
  if [[ "${EUID}" -eq 0 ]]; then
    apt-get "$@"
    return
  fi

  sudo apt-get "$@"
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "missing required command: ${command_name}" >&2
    exit 1
  fi
}

ensure_ubuntu() {
  if [[ ! -r /etc/os-release ]]; then
    echo "cannot detect operating system" >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "this script supports Ubuntu only" >&2
    exit 1
  fi
}

ensure_sudo_access() {
  if [[ "${EUID}" -eq 0 ]]; then
    return
  fi

  if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
    echo "sudo access is required; rerun from an interactive terminal or as root" >&2
    exit 1
  fi

  if ! sudo -v; then
    echo "sudo authentication failed" >&2
    exit 1
  fi
}

install_apt_packages() {
  apt_run update
  apt_run install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    pipx \
    python3 \
    python3-venv
}

install_rust_toolchain() {
  if ! command -v rustup >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain stable
  fi

  export PATH="${HOME}/.cargo/bin:${PATH}"

  rustup toolchain install stable --component clippy --component rustfmt
  rustup default stable
}

install_pre_commit() {
  if ! command -v pipx >/dev/null 2>&1; then
    echo "pipx installation failed" >&2
    exit 1
  fi

  pipx ensurepath >/dev/null
  pipx install --force pre-commit

  export PATH="${HOME}/.local/bin:${PATH}"
  require_command pre-commit
}

install_git_hooks() {
  cd "${REPO_ROOT}"

  pre-commit install
  pre-commit install --hook-type pre-push
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    require_command sudo
  fi

  ensure_ubuntu
  ensure_sudo_access
  install_apt_packages
  require_command curl
  install_rust_toolchain
  install_pre_commit
  install_git_hooks

  cat <<'EOF'
bootstrap completed

available commands:
  cargo run
  cargo test
  pre-commit run --all-files
EOF
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '\r\n' < "${repo_root}/bend-version")"
case "$(uname -s)" in Darwin) platform=darwin;; Linux) platform=linux;; *) echo 'Bend requires macOS or Linux' >&2; exit 1;; esac
case "$(uname -m)" in arm64|aarch64) architecture=arm64;; x86_64|amd64) architecture=x64;; *) echo 'Unsupported CPU architecture' >&2; exit 1;; esac
archive="bend-${version}-${platform}-${architecture}.tar.gz"
checksum="$(awk -v name="${archive}" '$2 == name {print $1}' "${repo_root}/bend-checksums.txt")"
[[ "${checksum}" =~ ^[0-9a-f]{64}$ ]] || { echo "No pinned checksum for ${archive}" >&2; exit 1; }
mkdir -p "${repo_root}/.build"
scratch="$(mktemp -d "${repo_root}/.build/install.XXXXXX")"
trap 'rm -rf "${scratch}"' EXIT
curl --proto '=https' --tlsv1.2 -fsSL --connect-timeout 15 --max-time 300 \
  "https://github.com/bendlang/bend/releases/download/v${version}/${archive}" -o "${scratch}/${archive}"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "${scratch}/${archive}")"
else
  actual="$(shasum -a 256 "${scratch}/${archive}")"
fi
[[ "${actual%% *}" == "${checksum}" ]] || { echo 'Bend archive checksum mismatch' >&2; exit 1; }
tar -xzf "${scratch}/${archive}" -C "${scratch}"
[[ "$(BEND_NO_TELEMETRY=1 "${scratch}/bend/bin/bend" version)" == "bend ${version}" ]] || { echo 'Bend archive version mismatch' >&2; exit 1; }
# Only a verified workspace-local compiler replaces the previous build cache.
rm -rf "${repo_root}/.build/bend"
mv "${scratch}/bend" "${repo_root}/.build/bend"
printf 'Installed Bend %s in %s/.build/bend\n' "${version}" "${repo_root}"
